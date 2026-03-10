"""
Agent execution events for observability and trajectory tracking.

Events are immutable records of agent execution, used for:
- Trajectory reconstruction
- Observability/monitoring
- Audit logging
- Checkpoint/recovery
"""

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional
from uuid import UUID, uuid4


class StopReason(str, Enum):
    """Reason for agent execution stopping."""
    FINISHED = "finished"           # Task completed successfully
    MAX_ITERATIONS = "max_iterations"  # Hit iteration limit
    ERROR = "error"                 # Unrecoverable error
    ESCALATED = "escalated"         # Escalated to coordinator
    TIMEOUT = "timeout"             # Execution timeout
    CANCELLED = "cancelled"         # Externally cancelled


@dataclass
class AgentEvent:
    """Base class for all agent events."""
    id: UUID = field(default_factory=uuid4)
    timestamp: datetime = field(default_factory=datetime.utcnow)
    agent_id: str = ""
    task_id: str = ""
    step: int = 0

    # Metrics attached by hooks
    metrics: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Serialize event to dictionary."""
        return {
            "_type": self.__class__.__name__,
            "id": str(self.id),
            "timestamp": self.timestamp.isoformat(),
            "agent_id": self.agent_id,
            "task_id": self.task_id,
            "step": self.step,
            "metrics": self.metrics,
        }


@dataclass
class AgentStart(AgentEvent):
    """Agent execution started."""
    agent_type: str = ""
    model: str = ""
    mission: str = ""
    task_payload: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        d = super().to_dict()
        d.update({
            "agent_type": self.agent_type,
            "model": self.model,
            "mission": self.mission,
            "task_payload": self.task_payload,
        })
        return d


@dataclass
class AgentEnd(AgentEvent):
    """Agent execution ended."""
    stop_reason: StopReason = StopReason.FINISHED
    error: Optional[str] = None
    result: Any = None
    total_steps: int = 0
    usage: Dict[str, int] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        d = super().to_dict()
        d.update({
            "stop_reason": self.stop_reason.value,
            "error": self.error,
            "result": self.result,
            "total_steps": self.total_steps,
            "usage": self.usage,
        })
        return d


@dataclass
class GenerationStep(AgentEvent):
    """LLM generation completed."""
    model: str = ""
    input_tokens: int = 0
    output_tokens: int = 0
    content: str = ""
    tool_calls: List[Dict[str, Any]] = field(default_factory=list)
    thinking: Optional[str] = None
    stop_reason: str = ""

    def to_dict(self) -> Dict[str, Any]:
        d = super().to_dict()
        d.update({
            "model": self.model,
            "input_tokens": self.input_tokens,
            "output_tokens": self.output_tokens,
            "content": self.content,
            "tool_calls": self.tool_calls,
            "thinking": self.thinking,
            "stop_reason": self.stop_reason,
        })
        return d


@dataclass
class ToolStep(AgentEvent):
    """Tool execution completed."""
    tool_name: str = ""
    tool_id: str = ""
    arguments: Dict[str, Any] = field(default_factory=dict)
    result: Any = None
    error: Optional[str] = None
    duration_ms: int = 0
    stopped: bool = False  # Tool requested execution stop

    def to_dict(self) -> Dict[str, Any]:
        d = super().to_dict()
        d.update({
            "tool_name": self.tool_name,
            "tool_id": self.tool_id,
            "arguments": self.arguments,
            "result": self.result,
            "error": self.error,
            "duration_ms": self.duration_ms,
            "stopped": self.stopped,
        })
        return d


@dataclass
class EscalationEvent(AgentEvent):
    """Task escalated to coordinator or human."""
    escalation_target: str = ""  # DN or identifier of escalation target
    reason: str = ""
    error: Optional[str] = None
    attempted_resolutions: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        d = super().to_dict()
        d.update({
            "escalation_target": self.escalation_target,
            "reason": self.reason,
            "error": self.error,
            "attempted_resolutions": self.attempted_resolutions,
        })
        return d


@dataclass
class CheckpointEvent(AgentEvent):
    """Trajectory checkpointed to warm storage."""
    checkpoint_id: str = ""
    trajectory_length: int = 0
    storage_uri: str = ""

    def to_dict(self) -> Dict[str, Any]:
        d = super().to_dict()
        d.update({
            "checkpoint_id": self.checkpoint_id,
            "trajectory_length": self.trajectory_length,
            "storage_uri": self.storage_uri,
        })
        return d


@dataclass
class PolicyViolationEvent(AgentEvent):
    """Agent violated a policy constraint."""
    policy_name: str = ""
    violation_type: str = ""  # tool_denied, resource_exceeded, etc.
    details: Dict[str, Any] = field(default_factory=dict)
    action_taken: str = ""  # blocked, warned, etc.

    def to_dict(self) -> Dict[str, Any]:
        d = super().to_dict()
        d.update({
            "policy_name": self.policy_name,
            "violation_type": self.violation_type,
            "details": self.details,
            "action_taken": self.action_taken,
        })
        return d


# Event type registry for deserialization
EVENT_TYPES = {
    "AgentStart": AgentStart,
    "AgentEnd": AgentEnd,
    "GenerationStep": GenerationStep,
    "ToolStep": ToolStep,
    "EscalationEvent": EscalationEvent,
    "CheckpointEvent": CheckpointEvent,
    "PolicyViolationEvent": PolicyViolationEvent,
}


def event_from_dict(data: Dict[str, Any]) -> AgentEvent:
    """Deserialize an event from dictionary."""
    event_type = data.pop("_type", "AgentEvent")
    cls = EVENT_TYPES.get(event_type, AgentEvent)

    # Parse datetime
    if "timestamp" in data:
        data["timestamp"] = datetime.fromisoformat(data["timestamp"])

    # Parse UUID
    if "id" in data:
        data["id"] = UUID(data["id"])

    # Parse stop_reason enum
    if "stop_reason" in data and cls == AgentEnd:
        data["stop_reason"] = StopReason(data["stop_reason"])

    return cls(**data)
