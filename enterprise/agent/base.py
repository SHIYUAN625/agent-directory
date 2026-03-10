"""
Enterprise Agent - Base agent class with NATS JetStream integration.

This is the core agent implementation that:
- Pulls tasks from NATS JetStream queues
- Executes with trajectory tracking
- Checkpoints state for crash recovery
- Escalates to coordinators on failure
"""

import asyncio
import json
import logging
from abc import ABC, abstractmethod
from datetime import datetime
from typing import Any, AsyncGenerator, Callable, Dict, List, Optional
from uuid import uuid4

from .events import (
    AgentEvent,
    AgentStart,
    AgentEnd,
    GenerationStep,
    ToolStep,
    EscalationEvent,
    CheckpointEvent,
    StopReason,
)
from .checkpoint import CheckpointStore
from .reactions import Reaction, Continue, Retry, Fail, Finish, select_reaction
from .routing import ensure_stream, subject_to_stream_name
from .trajectory import Trajectory
from .task import Task, TaskResult, TaskStatus, EscalationRequest

logger = logging.getLogger(__name__)


class EnterpriseAgent(ABC):
    """
    Base class for enterprise agents.

    Agents pull tasks from NATS JetStream queues, execute them with
    trajectory tracking, and report results or escalate on failure.

    Subclasses implement:
    - execute_step(): Core LLM + tool execution logic
    - get_tools(): Available tools for this agent

    The base class handles:
    - NATS connection and task queue subscription
    - Trajectory tracking and checkpointing
    - Reaction-based flow control
    - Escalation on failure
    """

    def __init__(
        self,
        identity: Dict[str, Any],
        policy: Dict[str, Any],
        nats_client: Any = None,  # nats.Client
        db_session: Any = None,   # AsyncSession for general DB use
        checkpoint_store: Optional[CheckpointStore] = None,
    ):
        """
        Initialize agent.

        Args:
            identity: Agent identity from provisioning (AgentIdentity.to_dict())
            policy: Merged policy from provisioning (MergedPolicy.to_dict())
            nats_client: Connected NATS client
            db_session: Async database session for general DB use
            checkpoint_store: Persistent store for trajectory checkpoints
        """
        self.identity = identity
        self.policy = policy
        self.nc = nats_client
        self.db = db_session
        self.checkpoint_store = checkpoint_store

        # JetStream context
        self.js = None

        # Current execution state
        self.running = False
        self.current_task: Optional[Task] = None
        self.trajectory: Optional[Trajectory] = None

        # Hooks for flow control
        self.hooks: List[Callable[[AgentEvent], Optional[Reaction]]] = []

        # Metrics
        self.tasks_processed = 0
        self.tasks_failed = 0
        self.tasks_escalated = 0

    @property
    def agent_id(self) -> str:
        return self.identity.get("name", "")

    @property
    def agent_type(self) -> str:
        return self.identity.get("agent_type", "autonomous")

    @property
    def trust_level(self) -> int:
        return self.identity.get("trust_level", 2)

    @property
    def sandbox_id(self) -> str:
        """ID of the sandbox this agent runs in."""
        sandbox = self.identity.get("sandbox", {})
        if isinstance(sandbox, dict):
            return sandbox.get("name", "")
        return ""

    @property
    def nats_subjects(self) -> List[str]:
        return self.identity.get("nats_subjects", [])

    @property
    def escalation_path(self) -> str:
        return self.identity.get("escalation_path", "escalations.human")

    @property
    def max_iterations(self) -> int:
        return self.policy.get("execution", {}).get("max_iterations", 100)

    @property
    def checkpoint_interval(self) -> int:
        return self.policy.get("execution", {}).get("checkpoint_interval_steps", 10)

    async def start(self):
        """Start the agent and begin processing tasks."""
        logger.info(f"Starting agent {self.agent_id}")

        if self.nc:
            self.js = self.nc.jetstream()

        self.running = True

        # Validate and subscribe to task queues
        valid_subjects = []
        for subject in self.nats_subjects:
            parts = subject.split(".")
            if len(parts) < 2:
                logger.error(
                    f"Skipping malformed NATS subject '{subject}': "
                    f"expected 'prefix.category[.suffix]' (got {len(parts)} parts)"
                )
                continue
            valid_subjects.append(subject)
            asyncio.create_task(self._process_queue(subject))

        if not valid_subjects:
            logger.error(f"Agent {self.agent_id} has no valid NATS subjects — will not process any tasks")

        logger.info(f"Agent {self.agent_id} started, subscribed to {valid_subjects}")

    async def stop(self):
        """Stop the agent gracefully."""
        logger.info(f"Stopping agent {self.agent_id}")
        self.running = False

    async def _process_queue(self, subject: str):
        """Process tasks from a single queue."""
        # Ensure the JetStream stream exists before subscribing.
        # Streams are derived from the subject convention (tasks.engineering → TASKS_ENGINEERING).
        # This is idempotent — if another agent already created the stream, this is a no-op.
        try:
            stream_name = await ensure_stream(self.js, subject)
        except Exception as e:
            logger.error(f"Failed to ensure stream for {subject}: {e}")
            stream_name = subject_to_stream_name(subject)

        consumer_name = f"agent-{self.agent_id}"

        try:
            sub = await self.js.pull_subscribe(
                subject=subject,
                durable=consumer_name,
                stream=stream_name,
            )
        except Exception as e:
            logger.error(f"Failed to subscribe to {subject}: {e}")
            return

        while self.running:
            try:
                msgs = await sub.fetch(batch=1, timeout=30)
                for msg in msgs:
                    await self._handle_message(msg, subject)
            except asyncio.TimeoutError:
                continue
            except Exception as e:
                logger.error(f"Error processing queue {subject}: {e}")
                await asyncio.sleep(5)

    async def _handle_message(self, msg: Any, subject: str):
        """Handle a single message from the queue."""
        try:
            task = Task.from_json(msg.data)
        except Exception as e:
            logger.error(f"Invalid task message: {e}")
            await msg.ack()  # Don't redeliver malformed messages
            return

        # Check if task is expired
        if task.is_expired():
            logger.warning(f"Task {task.id} expired, skipping")
            await msg.ack()
            return

        # Increment attempt counter
        task.attempt += 1
        task.status = TaskStatus.IN_PROGRESS

        # Process the task
        try:
            result = await self._execute_task(task)

            # Publish result
            if task.reply_to:
                await self.nc.publish(task.reply_to, result.to_json())

            # Ack the message
            await msg.ack()
            self.tasks_processed += 1

        except Retry as e:
            if task.can_retry():
                # Nak with backoff for retry
                await msg.nak(delay=e.backoff_seconds)
            else:
                # Exhausted retries, escalate
                await self._escalate_task(task, str(e))
                await msg.ack()
                self.tasks_escalated += 1

        except Fail as e:
            if e.escalate:
                await self._escalate_task(task, e.error)
                self.tasks_escalated += 1
            else:
                self.tasks_failed += 1
            await msg.ack()

        except Exception as e:
            logger.exception(f"Unexpected error processing task {task.id}")
            # Let NATS redeliver
            await msg.nak()

    async def _execute_task(self, task: Task) -> TaskResult:
        """Execute a single task with trajectory tracking."""
        self.current_task = task

        # Initialize or resume trajectory
        if task.checkpoint_id:
            self.trajectory = await self._load_checkpoint(task.checkpoint_id)
        else:
            self.trajectory = Trajectory(
                agent_id=self.agent_id,
                task_id=str(task.id),
            )

        # Emit start event
        start_event = AgentStart(
            agent_id=self.agent_id,
            task_id=str(task.id),
            agent_type=self.agent_type,
            model=self.identity.get("model", ""),
            mission=self.identity.get("mission", ""),
            task_payload=task.payload,
        )
        await self._emit_event(start_event)

        stop_reason = StopReason.FINISHED
        error_message = None
        result = None

        try:
            # Main execution loop
            step = self.trajectory.step_count
            while step < self.max_iterations:
                step += 1

                # Execute one step (subclass implements)
                async for event in self.execute_step(task, step):
                    # Dispatch hooks and emit event
                    reaction = await self._dispatch_event(event)

                    if reaction:
                        if isinstance(reaction, Finish):
                            result = reaction.result
                            stop_reason = StopReason.FINISHED
                            raise reaction
                        elif isinstance(reaction, Fail):
                            stop_reason = StopReason.ERROR
                            error_message = reaction.error
                            raise reaction
                        elif isinstance(reaction, Retry):
                            raise reaction

                # Checkpoint periodically
                if step % self.checkpoint_interval == 0:
                    await self._checkpoint()

            # Hit max iterations
            stop_reason = StopReason.MAX_ITERATIONS

        except Finish as e:
            result = e.result
            stop_reason = StopReason.FINISHED
        except Fail as e:
            error_message = e.error
            stop_reason = StopReason.ERROR
            raise
        except Retry:
            raise
        except Exception as e:
            error_message = str(e)
            stop_reason = StopReason.ERROR
            raise Fail(error=str(e), escalate=True)
        finally:
            # Emit end event
            end_event = AgentEnd(
                agent_id=self.agent_id,
                task_id=str(task.id),
                step=self.trajectory.step_count,
                stop_reason=stop_reason,
                error=error_message,
                result=result,
                total_steps=self.trajectory.step_count,
                usage=self.trajectory.usage.to_dict(),
            )
            await self._emit_event(end_event)

            self.current_task = None

        return TaskResult(
            task_id=task.id,
            agent_id=self.agent_id,
            status=TaskStatus.COMPLETED if stop_reason == StopReason.FINISHED else TaskStatus.FAILED,
            result=result,
            error=error_message,
            trajectory_id=str(self.trajectory.session_id),
            usage=self.trajectory.usage.to_dict(),
        )

    @abstractmethod
    async def execute_step(
        self,
        task: Task,
        step: int,
    ) -> AsyncGenerator[AgentEvent, None]:
        """
        Execute one step of the agent loop.

        Subclasses implement this to:
        1. Call the LLM with current context
        2. Execute any tool calls
        3. Yield events for trajectory/observability

        Should yield:
        - GenerationStep after LLM call
        - ToolStep after each tool execution

        Args:
            task: Current task being processed
            step: Current step number

        Yields:
            AgentEvent instances for trajectory tracking
        """
        raise NotImplementedError
        yield  # Make this a generator

    @abstractmethod
    def get_tools(self) -> List[Dict[str, Any]]:
        """
        Get available tools for this agent.

        Returns tool definitions in the format expected by the LLM.
        Tools should be filtered based on agent's authorized_tools
        and denied_tools from identity.
        """
        raise NotImplementedError

    async def _dispatch_event(self, event: AgentEvent) -> Optional[Reaction]:
        """Dispatch event through hooks and emit."""
        self.trajectory.add_event(event)

        # Run all hooks
        reactions = []
        for hook in self.hooks:
            try:
                reaction = await hook(event) if asyncio.iscoroutinefunction(hook) else hook(event)
                if reaction:
                    reactions.append(reaction)
            except Exception as e:
                logger.error(f"Hook error: {e}")

        # Select winning reaction
        reaction = select_reaction(*reactions)

        # Publish event to NATS
        await self._emit_event(event)

        return reaction

    async def _emit_event(self, event: AgentEvent):
        """Publish event to NATS for observability."""
        if self.nc:
            try:
                await self.nc.publish(
                    f"events.agent.{self.agent_id}",
                    json.dumps(event.to_dict()).encode()
                )
            except Exception as e:
                logger.warning(f"Failed to publish event: {e}")

    async def _checkpoint(self):
        """Save trajectory checkpoint to persistent storage."""
        if not self.trajectory:
            return

        try:
            checkpoint_id = str(uuid4())
            task_id = str(self.current_task.id) if self.current_task else ""

            # Persist to checkpoint store if available
            if self.checkpoint_store:
                await self.checkpoint_store.save(
                    checkpoint_id=checkpoint_id,
                    task_id=task_id,
                    agent_id=self.agent_id,
                    data=self.trajectory.to_json(),
                )

            # Emit checkpoint event
            event = CheckpointEvent(
                agent_id=self.agent_id,
                task_id=task_id,
                step=self.trajectory.step_count,
                checkpoint_id=checkpoint_id,
                trajectory_length=self.trajectory.step_count,
            )
            await self._emit_event(event)

            logger.debug(f"Checkpointed trajectory at step {self.trajectory.step_count}")

        except Exception as e:
            logger.error(f"Checkpoint failed: {e}")

    async def _load_checkpoint(self, checkpoint_id: str) -> Trajectory:
        """Load trajectory from checkpoint."""
        if self.checkpoint_store:
            try:
                data = await self.checkpoint_store.load(checkpoint_id)
                if data:
                    logger.info(f"Restored trajectory from checkpoint {checkpoint_id}")
                    return Trajectory.from_json(data)
            except Exception as e:
                logger.error(f"Failed to load checkpoint {checkpoint_id}: {e}")

        return Trajectory(agent_id=self.agent_id)

    async def _escalate_task(self, task: Task, error: str):
        """Escalate task to coordinator."""
        escalation = EscalationRequest(
            task=task,
            agent_id=self.agent_id,
            error=error,
            trajectory_id=str(self.trajectory.session_id) if self.trajectory else None,
        )

        # Publish to escalation subject
        escalation_subject = self.escalation_path
        if self.nc:
            try:
                await self.nc.publish(
                    escalation_subject,
                    escalation.to_json()
                )
                logger.info(f"Escalated task {task.id} to {escalation_subject}")
            except Exception as e:
                logger.error(f"Failed to escalate: {e}")

        # Emit escalation event
        event = EscalationEvent(
            agent_id=self.agent_id,
            task_id=str(task.id),
            step=self.trajectory.step_count if self.trajectory else 0,
            escalation_target=escalation_subject,
            reason="error",
            error=error,
        )
        await self._emit_event(event)

    def add_hook(self, hook: Callable[[AgentEvent], Optional[Reaction]]):
        """Add a hook for event processing."""
        self.hooks.append(hook)

    def get_stats(self) -> Dict[str, Any]:
        """Get agent statistics."""
        return {
            "agent_id": self.agent_id,
            "agent_type": self.agent_type,
            "trust_level": self.trust_level,
            "running": self.running,
            "tasks_processed": self.tasks_processed,
            "tasks_failed": self.tasks_failed,
            "tasks_escalated": self.tasks_escalated,
            "current_task": str(self.current_task.id) if self.current_task else None,
        }
