"""
Mission Coordinator Service

The coordinator is a specialized agent that manages goals, workforce,
and escalations. Multiple coordinators can run for HA with shared state.
"""

import asyncio
import json
import logging
import os
from datetime import datetime
from typing import Any, AsyncGenerator, Dict, List, Optional
from uuid import UUID, uuid4

from ..agent.base import EnterpriseAgent
from ..agent.events import AgentEvent, GenerationStep, ToolStep
from ..agent.reactions import Finish
from ..agent.routing import ensure_stream
from ..agent.task import Task, TaskResult, TaskSource, TaskStatus
from ..agent.trajectory import Trajectory
from .goal import Goal, GoalStatus, GoalDecomposition, DECOMPOSITION_PROMPT
from .workforce import WorkforceManager
from .escalation import EscalationHandler

logger = logging.getLogger(__name__)


class MissionCoordinator(EnterpriseAgent):
    """
    Mission Coordinator Agent.

    A coordinator is an agent that:
    - Decomposes high-level goals into tasks
    - Manages workforce (spawns/supervises workers)
    - Handles escalations from workers
    - Makes decisions requiring broader context
    """

    def __init__(
        self,
        identity: Dict[str, Any],
        policy: Dict[str, Any],
        nats_client: Any = None,
        db_session: Any = None,
        provisioner_url: str = "http://localhost:8080",
        provisioner_api_key: str = "",
        llm_client: Any = None,
    ):
        """
        Initialize coordinator.

        Args:
            identity: Agent identity from provisioning
            policy: Merged policy
            nats_client: NATS client
            db_session: Database session for shared state
            provisioner_url: URL of provisioning service
            provisioner_api_key: API key for provisioner service
            llm_client: LLM client for goal decomposition
        """
        super().__init__(identity, policy, nats_client, db_session)

        self.provisioner_url = provisioner_url
        self.provisioner_api_key = provisioner_api_key or os.getenv("PROVISIONER_API_KEY", "")
        self.llm = llm_client

        # Coordinator-specific components
        self.workforce: Optional[WorkforceManager] = None
        self.escalation_handler: Optional[EscalationHandler] = None

        # Goals being managed
        self.goals: Dict[UUID, Goal] = {}

        # Shared state service (Redis or PostgreSQL)
        self.shared_state: Dict[str, Any] = {}

    async def start(self):
        """Start the coordinator."""
        logger.info(f"Starting mission coordinator {self.agent_id}")

        # Initialize workforce manager
        self.workforce = WorkforceManager(
            provisioner_url=self.provisioner_url,
            api_key=self.provisioner_api_key,
            nats_client=self.nc,
            db_session=self.db,
        )
        await self.workforce.start()

        # Initialize escalation handler
        self.escalation_handler = EscalationHandler(
            coordinator_id=self.agent_id,
            nats_client=self.nc,
            db_session=self.db,
        )

        # Get escalation subjects from identity
        escalation_subjects = [
            s for s in self.nats_subjects
            if s.startswith("escalations.")
        ]
        await self.escalation_handler.start(escalation_subjects)

        # Start base agent
        await super().start()

        logger.info(f"Mission coordinator {self.agent_id} started")

    async def stop(self):
        """Stop the coordinator."""
        if self.workforce:
            await self.workforce.stop()
        if self.escalation_handler:
            await self.escalation_handler.stop()
        await super().stop()

    async def execute_step(
        self,
        task: Task,
        step: int,
    ) -> AsyncGenerator[AgentEvent, None]:
        """
        Execute one step of coordinator logic.

        Coordinator tasks include:
        - Goal decomposition
        - Workforce management
        - Escalation resolution
        - Progress monitoring
        """
        task_type = task.task_type

        finish_result: Dict[str, Any]

        if task_type == "goal_decomposition":
            async for event in self._decompose_goal(task, step):
                yield event
            finish_result = {"status": "completed", "task_type": task_type}

        elif task_type == "escalation_resolution":
            async for event in self._resolve_escalation(task, step):
                yield event
            finish_result = {"status": "completed", "task_type": task_type}

        elif task_type == "workforce_rebalance":
            async for event in self._rebalance_workforce(task, step):
                yield event
            finish_result = {"status": "completed", "task_type": task_type}

        elif task_type == "progress_review":
            async for event in self._review_progress(task, step):
                yield event
            finish_result = {"status": "completed", "task_type": task_type}

        else:
            # Generic coordination task - use LLM
            async for event in self._handle_generic_task(task, step):
                yield event
            finish_result = {"status": "completed", "task_type": task_type}

        # Coordinator tasks are one-shot decisions/actions for now.
        # Signal completion so the base execution loop does not re-run
        # the same task until max_iterations.
        raise Finish(result=finish_result)

    def get_tools(self) -> List[Dict[str, Any]]:
        """Get coordinator tools."""
        return [
            {
                "name": "create_task",
                "description": "Create a task for worker agents",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "task_type": {"type": "string"},
                        "description": {"type": "string"},
                        "priority": {"type": "integer"},
                        "requirements": {"type": "object"},
                    },
                    "required": ["task_type", "description"],
                },
            },
            {
                "name": "spawn_agent",
                "description": "Request a new agent from provisioner",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "agent_type": {"type": "string"},
                        "requirements": {"type": "object"},
                    },
                    "required": ["agent_type"],
                },
            },
            {
                "name": "query_workforce",
                "description": "Get current workforce status",
                "parameters": {"type": "object", "properties": {}},
            },
            {
                "name": "resolve_escalation",
                "description": "Mark an escalation as resolved",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "escalation_id": {"type": "string"},
                        "resolution": {"type": "string"},
                        "actions": {"type": "array"},
                    },
                    "required": ["escalation_id", "resolution"],
                },
            },
            {
                "name": "escalate_to_human",
                "description": "Escalate an issue to human operators",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "summary": {"type": "string"},
                        "context": {"type": "object"},
                        "urgency": {"type": "string"},
                    },
                    "required": ["summary"],
                },
            },
        ]

    async def _decompose_goal(
        self,
        task: Task,
        step: int,
    ) -> AsyncGenerator[AgentEvent, None]:
        """Decompose a goal into sub-goals and tasks."""
        goal_data = task.payload.get("goal", {})
        goal = Goal.from_dict(goal_data)
        goal.status = GoalStatus.PLANNING

        self.goals[goal.id] = goal

        # Build decomposition prompt
        prompt = DECOMPOSITION_PROMPT.format(
            title=goal.title,
            description=goal.description,
            context=json.dumps(goal.context, indent=2),
            constraints="\n".join(f"- {c}" for c in goal.constraints),
            success_criteria="\n".join(f"- {c}" for c in goal.success_criteria),
            agent_types=", ".join(self.workforce.pool_configs.keys()) if self.workforce else "worker",
        )

        # Call LLM for decomposition
        if self.llm:
            # TODO: Actual LLM call
            response = await self._llm_decompose(prompt)

            yield GenerationStep(
                step=step,
                model=self.identity.get("model", ""),
                input_tokens=len(prompt) // 4,  # Rough estimate
                output_tokens=len(response) // 4,
                content=response,
            )

            # Parse decomposition
            try:
                decomposition = self._parse_decomposition(goal, response)

                # Create tasks from decomposition
                for task_def in decomposition.tasks:
                    await self._create_worker_task(task_def, goal)

                goal.status = GoalStatus.IN_PROGRESS
                goal.metrics.total_tasks = len(decomposition.tasks)

                yield ToolStep(
                    step=step,
                    tool_name="goal_decomposition",
                    tool_id=str(uuid4()),
                    arguments={"goal_id": str(goal.id)},
                    result=decomposition.to_dict(),
                )

            except Exception as e:
                logger.error(f"Decomposition failed: {e}")
                goal.status = GoalStatus.FAILED
                raise

        else:
            # No LLM - create simple task
            yield ToolStep(
                step=step,
                tool_name="simple_decomposition",
                tool_id=str(uuid4()),
                arguments={"goal_id": str(goal.id)},
                result={"message": "No LLM available, created single task"},
            )

    async def _llm_decompose(self, prompt: str) -> str:
        """Call LLM for goal decomposition."""
        response = await self.llm.generate(
            messages=[{"role": "user", "content": prompt}],
            system="You are a mission coordinator. Decompose goals into concrete tasks. Respond with JSON.",
        )
        return response

    def _parse_decomposition(self, goal: Goal, response: str) -> GoalDecomposition:
        """Parse LLM response into GoalDecomposition."""
        try:
            data = json.loads(response)
        except json.JSONDecodeError:
            # Try to extract JSON from response
            import re
            match = re.search(r'\{.*\}', response, re.DOTALL)
            if match:
                data = json.loads(match.group())
            else:
                raise ValueError("Could not parse decomposition response")

        return GoalDecomposition(
            goal_id=goal.id,
            tasks=data.get("tasks", []),
            approach=data.get("approach", ""),
            rationale=data.get("rationale", ""),
            alternatives=data.get("alternatives", []),
            risks=data.get("risks", []),
            requires_approval=data.get("requires_approval", False),
        )

    async def _create_worker_task(self, task_def: Dict[str, Any], goal: Goal):
        """Create a task and publish to worker queue."""
        task = Task(
            task_type=task_def.get("task_type", "generic"),
            priority=task_def.get("priority", 500),
            source=TaskSource(
                agent_id=self.agent_id,
                mission_id=goal.source_mission,
                parent_task_id=str(goal.id),
            ),
            payload={
                "description": task_def.get("description", ""),
                "goal_id": str(goal.id),
                **task_def.get("context", {}),
            },
            reply_to=f"results.{goal.id}",
        )

        goal.task_ids.append(task.id)

        # Publish to appropriate queue
        subject = f"tasks.{task.task_type}"
        if self.nc:
            js = self.nc.jetstream()
            await ensure_stream(js, subject)
            await js.publish(subject, task.to_json())

        logger.info(f"Created task {task.id} for goal {goal.id}")

    async def _resolve_escalation(
        self,
        task: Task,
        step: int,
    ) -> AsyncGenerator[AgentEvent, None]:
        """Handle escalation resolution task."""
        escalation_data = task.payload.get("escalation", {})

        prompt = (
            "An escalation has been received that requires your attention:\n\n"
            f"Source Agent: {escalation_data.get('source_agent')}\n"
            f"Error: {escalation_data.get('error')}\n"
            f"Reason: {escalation_data.get('reason')}\n"
            f"Attempted Resolutions: {escalation_data.get('attempted_resolutions', [])}\n\n"
            "Analyze this escalation and respond with JSON containing:\n"
            '  "root_cause": string,\n'
            '  "resolution_steps": [string, ...],\n'
            '  "action": "retry" | "modify" | "escalate"\n'
        )

        if self.llm:
            response = await self.llm.generate(
                messages=[{"role": "user", "content": prompt}],
                system="You are a mission coordinator resolving an escalation. Respond with JSON.",
            )

            yield GenerationStep(
                step=step,
                model=self.identity.get("model", ""),
                input_tokens=len(prompt) // 4,
                output_tokens=len(response) // 4,
                content=response,
            )

            # Parse and act on the resolution
            try:
                resolution = json.loads(response)
            except json.JSONDecodeError:
                resolution = {"root_cause": "unknown", "action": "escalate", "raw_response": response}

            yield ToolStep(
                step=step,
                tool_name="resolve_escalation",
                tool_id=str(uuid4()),
                arguments={"escalation": escalation_data},
                result=resolution,
            )
        else:
            # No LLM available — log and re-escalate up the chain
            logger.warning("No LLM available for escalation resolution, re-escalating")
            yield ToolStep(
                step=step,
                tool_name="resolve_escalation",
                tool_id=str(uuid4()),
                arguments={"escalation": escalation_data},
                result={
                    "status": "no_llm",
                    "action": "escalate",
                    "message": "No LLM configured — escalation forwarded up the chain",
                },
            )

    async def _rebalance_workforce(
        self,
        task: Task,
        step: int,
    ) -> AsyncGenerator[AgentEvent, None]:
        """Rebalance workforce based on current demand."""
        if self.workforce:
            status = self.workforce.get_workforce_status()

            yield ToolStep(
                step=step,
                tool_name="query_workforce",
                tool_id=str(uuid4()),
                arguments={},
                result=status,
            )

    async def _review_progress(
        self,
        task: Task,
        step: int,
    ) -> AsyncGenerator[AgentEvent, None]:
        """Review progress on active goals."""
        # Gather goal metrics
        goal_summaries = []
        for goal_id, goal in self.goals.items():
            goal_summaries.append({
                "goal_id": str(goal_id),
                "title": goal.title,
                "status": goal.status.value,
                "tasks_total": goal.metrics.total_tasks,
                "tasks_completed": goal.metrics.completed_tasks,
                "tasks_failed": goal.metrics.failed_tasks,
            })

        if self.llm:
            prompt = (
                "Review the progress of these active goals and provide analysis:\n\n"
                f"{json.dumps(goal_summaries, indent=2)}\n\n"
                "Respond with JSON containing:\n"
                '  "overall_status": string,\n'
                '  "blocked_goals": [goal_id, ...],\n'
                '  "recommendations": [string, ...]\n'
            )

            response = await self.llm.generate(
                messages=[{"role": "user", "content": prompt}],
                system="You are a mission coordinator reviewing goal progress. Respond with JSON.",
            )

            yield GenerationStep(
                step=step,
                model=self.identity.get("model", ""),
                input_tokens=len(prompt) // 4,
                output_tokens=len(response) // 4,
                content=response,
            )

            try:
                analysis = json.loads(response)
            except json.JSONDecodeError:
                analysis = {"overall_status": "unknown", "raw_response": response}

            yield ToolStep(
                step=step,
                tool_name="review_progress",
                tool_id=str(uuid4()),
                arguments={"goal_count": len(goal_summaries)},
                result=analysis,
            )
        else:
            # No LLM — return raw metrics
            yield ToolStep(
                step=step,
                tool_name="review_progress",
                tool_id=str(uuid4()),
                arguments={"goal_count": len(goal_summaries)},
                result={
                    "status": "no_llm",
                    "goals": goal_summaries,
                    "message": "Raw goal metrics (no LLM analysis available)",
                },
            )

    async def _handle_generic_task(
        self,
        task: Task,
        step: int,
    ) -> AsyncGenerator[AgentEvent, None]:
        """Handle generic coordination task with LLM."""
        description = task.payload.get("description", "")
        context = {k: v for k, v in task.payload.items() if k != "description"}

        if self.llm:
            prompt = (
                f"Handle this coordination task:\n\n"
                f"Description: {description}\n"
                f"Context: {json.dumps(context, indent=2)}\n\n"
                "Determine what actions to take and respond with JSON containing:\n"
                '  "analysis": string,\n'
                '  "actions": [{"tool": string, "arguments": object}, ...],\n'
                '  "result": string\n'
            )

            response = await self.llm.generate(
                messages=[{"role": "user", "content": prompt}],
                system="You are a mission coordinator. Analyze the task and determine actions.",
                tools=self.get_tools(),
            )

            yield GenerationStep(
                step=step,
                model=self.identity.get("model", ""),
                input_tokens=len(prompt) // 4,
                output_tokens=len(response) // 4,
                content=response,
            )

            try:
                result = json.loads(response)
            except json.JSONDecodeError:
                result = {"analysis": response, "actions": []}

            yield ToolStep(
                step=step,
                tool_name="generic_task",
                tool_id=str(uuid4()),
                arguments={"description": description},
                result=result,
            )
        else:
            # No LLM — escalate the task since we can't reason about it
            logger.warning("No LLM available for generic task, escalating")
            yield ToolStep(
                step=step,
                tool_name="generic_task",
                tool_id=str(uuid4()),
                arguments={"description": description},
                result={
                    "status": "no_llm",
                    "action": "escalate",
                    "message": "No LLM configured — task requires human review",
                },
            )

    def get_coordinator_status(self) -> Dict[str, Any]:
        """Get coordinator-specific status."""
        base_stats = self.get_stats()
        base_stats.update({
            "active_goals": len([g for g in self.goals.values() if g.status == GoalStatus.IN_PROGRESS]),
            "completed_goals": len([g for g in self.goals.values() if g.status == GoalStatus.COMPLETED]),
            "workforce": self.workforce.get_workforce_status() if self.workforce else {},
            "escalations": self.escalation_handler.get_escalation_stats() if self.escalation_handler else {},
        })
        return base_stats
