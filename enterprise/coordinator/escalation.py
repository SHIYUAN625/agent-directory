"""
Escalation handling for mission coordination.

Escalations flow up the hierarchy:
  Worker Agent -> Team Coordinator -> Senior Coordinator -> Human Operator
"""

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional
from uuid import UUID, uuid4
import asyncio
import json
import logging

from ..agent.task import Task, EscalationRequest

logger = logging.getLogger(__name__)


class EscalationLevel(str, Enum):
    """Levels in escalation hierarchy."""
    TEAM = "team"               # Team coordinator
    DEPARTMENT = "department"   # Department coordinator
    SENIOR = "senior"           # Senior/executive coordinator
    HUMAN = "human"             # Human operator


class EscalationStatus(str, Enum):
    """Status of an escalation."""
    PENDING = "pending"         # Waiting for handler
    ASSIGNED = "assigned"       # Assigned to coordinator
    INVESTIGATING = "investigating"  # Being investigated
    RESOLVED = "resolved"       # Successfully resolved
    RE_ESCALATED = "re-escalated"  # Escalated further up
    REJECTED = "rejected"       # Determined to not need handling


@dataclass
class Escalation:
    """An escalation request from a worker agent."""
    id: UUID = field(default_factory=uuid4)
    task: Task = field(default_factory=Task)
    source_agent: str = ""
    error: str = ""
    reason: str = ""
    trajectory_id: Optional[str] = None
    attempted_resolutions: List[str] = field(default_factory=list)

    level: EscalationLevel = EscalationLevel.TEAM
    status: EscalationStatus = EscalationStatus.PENDING

    assigned_to: Optional[str] = None  # Coordinator handling it
    resolution: Optional[str] = None
    resolution_actions: List[Dict[str, Any]] = field(default_factory=list)

    created_at: datetime = field(default_factory=datetime.utcnow)
    assigned_at: Optional[datetime] = None
    resolved_at: Optional[datetime] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": str(self.id),
            "task": self.task.to_dict(),
            "source_agent": self.source_agent,
            "error": self.error,
            "reason": self.reason,
            "trajectory_id": self.trajectory_id,
            "attempted_resolutions": self.attempted_resolutions,
            "level": self.level.value,
            "status": self.status.value,
            "assigned_to": self.assigned_to,
            "resolution": self.resolution,
            "resolution_actions": self.resolution_actions,
            "created_at": self.created_at.isoformat(),
            "assigned_at": self.assigned_at.isoformat() if self.assigned_at else None,
            "resolved_at": self.resolved_at.isoformat() if self.resolved_at else None,
        }

    @classmethod
    def from_request(cls, request: EscalationRequest) -> "Escalation":
        """Create from escalation request."""
        return cls(
            task=request.task,
            source_agent=request.agent_id,
            error=request.error,
            reason=request.reason,
            trajectory_id=request.trajectory_id,
            attempted_resolutions=request.attempted_resolutions,
        )


class EscalationHandler:
    """
    Handles escalations from worker agents.

    Responsibilities:
    - Receive and queue escalations
    - Route to appropriate coordinator
    - Track resolution attempts
    - Re-escalate if unresolved
    - Notify humans for critical issues
    """

    def __init__(
        self,
        coordinator_id: str,
        nats_client: Any = None,
        db_session: Any = None,
    ):
        """
        Initialize escalation handler.

        Args:
            coordinator_id: ID of this coordinator
            nats_client: NATS client for messaging
            db_session: Database session for persistence
        """
        self.coordinator_id = coordinator_id
        self.nc = nats_client
        self.db = db_session

        # Pending escalations by ID
        self.escalations: Dict[UUID, Escalation] = {}

        # Queue for processing
        self.queue: asyncio.Queue[Escalation] = asyncio.Queue()

        # Resolution handlers by reason
        self.handlers: Dict[str, Any] = {}

        self._running = False
        self._processor_task = None

    async def start(self, escalation_subjects: List[str]):
        """Start listening for escalations."""
        self._running = True

        # Subscribe to escalation subjects
        if self.nc:
            for subject in escalation_subjects:
                await self.nc.subscribe(
                    subject,
                    cb=self._handle_escalation_message,
                )

        # Start processor
        self._processor_task = asyncio.create_task(self._process_loop())

        logger.info(f"Escalation handler started for {escalation_subjects}")

    async def stop(self):
        """Stop escalation handling."""
        self._running = False
        if self._processor_task:
            self._processor_task.cancel()
            try:
                await self._processor_task
            except asyncio.CancelledError:
                pass

    async def _handle_escalation_message(self, msg):
        """Handle incoming escalation from NATS."""
        try:
            data = json.loads(msg.data.decode('utf-8'))
            task = Task.from_dict(data["task"])

            escalation = Escalation(
                task=task,
                source_agent=data.get("agent_id", ""),
                error=data.get("error", ""),
                reason=data.get("reason", ""),
                trajectory_id=data.get("trajectory_id"),
                attempted_resolutions=data.get("attempted_resolutions", []),
            )

            self.escalations[escalation.id] = escalation
            await self.queue.put(escalation)

            logger.info(
                f"Received escalation {escalation.id} from {escalation.source_agent}: "
                f"{escalation.reason}"
            )

        except Exception as e:
            logger.error(f"Error handling escalation message: {e}")

    async def _process_loop(self):
        """Process escalations from queue."""
        while self._running:
            try:
                escalation = await asyncio.wait_for(
                    self.queue.get(),
                    timeout=5.0,
                )
                await self._process_escalation(escalation)
            except asyncio.TimeoutError:
                continue
            except Exception as e:
                logger.error(f"Error processing escalation: {e}")

    async def _process_escalation(self, escalation: Escalation):
        """Process a single escalation."""
        logger.info(f"Processing escalation {escalation.id}")

        escalation.status = EscalationStatus.ASSIGNED
        escalation.assigned_to = self.coordinator_id
        escalation.assigned_at = datetime.utcnow()

        try:
            # Try to resolve
            resolved = await self._attempt_resolution(escalation)

            if resolved:
                escalation.status = EscalationStatus.RESOLVED
                escalation.resolved_at = datetime.utcnow()
                await self._notify_resolution(escalation)
            else:
                # Re-escalate to higher level
                await self._re_escalate(escalation)

        except Exception as e:
            logger.error(f"Error resolving escalation {escalation.id}: {e}")
            await self._re_escalate(escalation)

    async def _attempt_resolution(self, escalation: Escalation) -> bool:
        """
        Attempt to resolve an escalation.

        Returns:
            True if resolved, False if needs re-escalation
        """
        # Check if we have a handler for this reason
        handler = self.handlers.get(escalation.reason)
        if handler:
            try:
                result = await handler(escalation)
                if result:
                    escalation.resolution = result.get("resolution", "")
                    escalation.resolution_actions = result.get("actions", [])
                    return True
            except Exception as e:
                logger.warning(f"Handler failed: {e}")

        # Try common resolution strategies
        resolution = await self._try_common_resolutions(escalation)
        if resolution:
            escalation.resolution = resolution
            return True

        return False

    async def _try_common_resolutions(self, escalation: Escalation) -> Optional[str]:
        """Try common resolution strategies."""
        reason = escalation.reason.lower()

        # Permission issues
        if "permission" in reason or "access" in reason:
            # Check if we can grant temporary access
            # TODO: Implement access grants
            return None

        # Resource issues
        if "resource" in reason or "quota" in reason:
            # Check if we can increase resources
            # TODO: Implement resource adjustment
            return None

        # Timeout issues
        if "timeout" in reason:
            # Consider increasing timeout and retrying
            return "Recommend retry with extended timeout"

        # Unknown error - needs investigation
        escalation.status = EscalationStatus.INVESTIGATING
        return None

    async def _re_escalate(self, escalation: Escalation):
        """Re-escalate to higher level."""
        escalation.status = EscalationStatus.RE_ESCALATED

        # Determine next level
        level_order = [
            EscalationLevel.TEAM,
            EscalationLevel.DEPARTMENT,
            EscalationLevel.SENIOR,
            EscalationLevel.HUMAN,
        ]

        current_idx = level_order.index(escalation.level)
        if current_idx < len(level_order) - 1:
            escalation.level = level_order[current_idx + 1]

            # Publish to higher level
            if self.nc:
                subject = f"escalations.{escalation.level.value}"
                await self.nc.publish(
                    subject,
                    json.dumps(escalation.to_dict()).encode(),
                )

            logger.info(
                f"Re-escalated {escalation.id} to {escalation.level.value}"
            )
        else:
            # Already at human level - create alert
            await self._notify_human(escalation)

    async def _notify_resolution(self, escalation: Escalation):
        """Notify source agent of resolution."""
        if self.nc:
            subject = f"control.agent.{escalation.source_agent}.commands"
            message = {
                "type": "escalation_resolved",
                "escalation_id": str(escalation.id),
                "resolution": escalation.resolution,
                "actions": escalation.resolution_actions,
            }
            await self.nc.publish(
                subject,
                json.dumps(message).encode(),
            )

        logger.info(f"Notified {escalation.source_agent} of resolution")

    async def _notify_human(self, escalation: Escalation):
        """Send alert to human operators."""
        # Publish to human escalation queue
        if self.nc:
            message = {
                "type": "human_escalation_required",
                "escalation": escalation.to_dict(),
                "summary": f"Task {escalation.task.id} from {escalation.source_agent}: {escalation.error}",
            }
            await self.nc.publish(
                "escalations.human",
                json.dumps(message).encode(),
            )

        logger.warning(f"Escalation {escalation.id} requires human attention")

    def register_handler(self, reason: str, handler):
        """Register a handler for a specific escalation reason."""
        self.handlers[reason] = handler

    def get_pending_escalations(self) -> List[Dict[str, Any]]:
        """Get all pending escalations."""
        return [
            e.to_dict() for e in self.escalations.values()
            if e.status in [EscalationStatus.PENDING, EscalationStatus.ASSIGNED, EscalationStatus.INVESTIGATING]
        ]

    def get_escalation_stats(self) -> Dict[str, Any]:
        """Get escalation statistics."""
        by_status = {}
        by_level = {}
        by_reason = {}

        for e in self.escalations.values():
            by_status[e.status.value] = by_status.get(e.status.value, 0) + 1
            by_level[e.level.value] = by_level.get(e.level.value, 0) + 1
            by_reason[e.reason] = by_reason.get(e.reason, 0) + 1

        return {
            "total": len(self.escalations),
            "by_status": by_status,
            "by_level": by_level,
            "by_reason": by_reason,
            "queue_size": self.queue.qsize(),
        }
