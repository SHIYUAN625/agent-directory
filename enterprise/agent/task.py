"""
Task definitions for agent work items.

Tasks are work items pulled from NATS JetStream queues and processed by agents.
"""

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional
from uuid import UUID, uuid4
import json


class TaskStatus(str, Enum):
    """Status of a task."""
    PENDING = "pending"           # In queue, not yet picked up
    IN_PROGRESS = "in_progress"   # Being processed by an agent
    COMPLETED = "completed"       # Successfully completed
    FAILED = "failed"             # Failed after retries exhausted
    ESCALATED = "escalated"       # Escalated to coordinator
    CANCELLED = "cancelled"       # Externally cancelled
    TIMEOUT = "timeout"           # Execution timeout


@dataclass
class TaskRequirements:
    """Requirements for the agent that processes this task."""
    min_trust_level: int = 0
    required_capabilities: List[str] = field(default_factory=list)
    required_tools: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "min_trust_level": self.min_trust_level,
            "required_capabilities": self.required_capabilities,
            "required_tools": self.required_tools,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TaskRequirements":
        return cls(
            min_trust_level=data.get("min_trust_level", 0),
            required_capabilities=data.get("required_capabilities", []),
            required_tools=data.get("required_tools", []),
        )


@dataclass
class TaskSource:
    """Source of a task (who created it)."""
    agent_id: str = ""
    mission_id: str = ""
    parent_task_id: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return {
            "agent_id": self.agent_id,
            "mission_id": self.mission_id,
            "parent_task_id": self.parent_task_id,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TaskSource":
        return cls(
            agent_id=data.get("agent_id", ""),
            mission_id=data.get("mission_id", ""),
            parent_task_id=data.get("parent_task_id", ""),
        )


@dataclass
class Task:
    """
    A work item for an agent.

    Tasks are pulled from NATS JetStream queues and processed by agents.
    They support checkpointing for crash recovery and escalation to coordinators.
    """
    id: UUID = field(default_factory=uuid4)
    task_type: str = ""
    priority: int = 100  # 0-1000, higher = more urgent
    created_at: datetime = field(default_factory=datetime.utcnow)
    expires_at: Optional[datetime] = None

    # Source information
    source: TaskSource = field(default_factory=TaskSource)

    # Task payload
    payload: Dict[str, Any] = field(default_factory=dict)

    # Requirements for processing agent
    requirements: TaskRequirements = field(default_factory=TaskRequirements)

    # NATS reply subject for result
    reply_to: str = ""

    # Checkpoint ID if resuming from crash
    checkpoint_id: Optional[str] = None

    # Current status
    status: TaskStatus = TaskStatus.PENDING

    # Retry tracking
    attempt: int = 0
    max_attempts: int = 3

    def is_expired(self) -> bool:
        """Check if task has expired."""
        if self.expires_at is None:
            return False
        return datetime.utcnow() > self.expires_at

    def can_retry(self) -> bool:
        """Check if task can be retried."""
        return self.attempt < self.max_attempts

    def to_dict(self) -> Dict[str, Any]:
        """Serialize task to dictionary."""
        return {
            "id": str(self.id),
            "task_type": self.task_type,
            "priority": self.priority,
            "created_at": self.created_at.isoformat(),
            "expires_at": self.expires_at.isoformat() if self.expires_at else None,
            "source": self.source.to_dict(),
            "payload": self.payload,
            "requirements": self.requirements.to_dict(),
            "reply_to": self.reply_to,
            "checkpoint_id": self.checkpoint_id,
            "status": self.status.value,
            "attempt": self.attempt,
            "max_attempts": self.max_attempts,
        }

    def to_json(self) -> bytes:
        """Serialize to JSON bytes for NATS."""
        return json.dumps(self.to_dict()).encode('utf-8')

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "Task":
        """Deserialize task from dictionary."""
        return cls(
            id=UUID(data["id"]) if data.get("id") else uuid4(),
            task_type=data.get("task_type", ""),
            priority=data.get("priority", 100),
            created_at=datetime.fromisoformat(data["created_at"]) if data.get("created_at") else datetime.utcnow(),
            expires_at=datetime.fromisoformat(data["expires_at"]) if data.get("expires_at") else None,
            source=TaskSource.from_dict(data.get("source", {})),
            payload=data.get("payload", {}),
            requirements=TaskRequirements.from_dict(data.get("requirements", {})),
            reply_to=data.get("reply_to", ""),
            checkpoint_id=data.get("checkpoint_id"),
            status=TaskStatus(data.get("status", "pending")),
            attempt=data.get("attempt", 0),
            max_attempts=data.get("max_attempts", 3),
        )

    @classmethod
    def from_json(cls, data: bytes) -> "Task":
        """Deserialize from JSON bytes."""
        return cls.from_dict(json.loads(data.decode('utf-8')))


@dataclass
class TaskResult:
    """Result of a completed task."""
    task_id: UUID
    agent_id: str
    completed_at: datetime = field(default_factory=datetime.utcnow)
    status: TaskStatus = TaskStatus.COMPLETED
    result: Any = None
    error: Optional[str] = None
    trajectory_id: Optional[str] = None
    usage: Dict[str, int] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "task_id": str(self.task_id),
            "agent_id": self.agent_id,
            "completed_at": self.completed_at.isoformat(),
            "status": self.status.value,
            "result": self.result,
            "error": self.error,
            "trajectory_id": self.trajectory_id,
            "usage": self.usage,
        }

    def to_json(self) -> bytes:
        return json.dumps(self.to_dict()).encode('utf-8')

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TaskResult":
        return cls(
            task_id=UUID(data["task_id"]),
            agent_id=data.get("agent_id", ""),
            completed_at=datetime.fromisoformat(data["completed_at"]) if data.get("completed_at") else datetime.utcnow(),
            status=TaskStatus(data.get("status", "completed")),
            result=data.get("result"),
            error=data.get("error"),
            trajectory_id=data.get("trajectory_id"),
            usage=data.get("usage", {}),
        )

    @classmethod
    def from_json(cls, data: bytes) -> "TaskResult":
        return cls.from_dict(json.loads(data.decode('utf-8')))


@dataclass
class EscalationRequest:
    """Request to escalate a task to a coordinator."""
    task: Task
    agent_id: str
    error: str
    reason: str = "blocked"
    trajectory_id: Optional[str] = None
    attempted_resolutions: List[str] = field(default_factory=list)
    created_at: datetime = field(default_factory=datetime.utcnow)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "task": self.task.to_dict(),
            "agent_id": self.agent_id,
            "error": self.error,
            "reason": self.reason,
            "trajectory_id": self.trajectory_id,
            "attempted_resolutions": self.attempted_resolutions,
            "created_at": self.created_at.isoformat(),
        }

    def to_json(self) -> bytes:
        return json.dumps(self.to_dict()).encode('utf-8')
