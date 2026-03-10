"""
Trajectory tracking for agent execution history.

The Trajectory class maintains the complete execution history of an agent,
supporting checkpoint/recovery and observability.
"""

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Dict, List, Optional
from uuid import UUID, uuid4

from .events import AgentEvent, event_from_dict


@dataclass
class TrajectoryStep:
    """A single step in the trajectory (generation + tool results)."""
    step_number: int
    generation: Optional[Dict[str, Any]] = None  # GenerationStep as dict
    tool_results: List[Dict[str, Any]] = field(default_factory=list)
    messages: List[Dict[str, Any]] = field(default_factory=list)  # Messages added
    timestamp: datetime = field(default_factory=datetime.utcnow)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "step_number": self.step_number,
            "generation": self.generation,
            "tool_results": self.tool_results,
            "messages": self.messages,
            "timestamp": self.timestamp.isoformat(),
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TrajectoryStep":
        if "timestamp" in data:
            data["timestamp"] = datetime.fromisoformat(data["timestamp"])
        return cls(**data)


@dataclass
class TokenUsage:
    """Token usage tracking."""
    input_tokens: int = 0
    output_tokens: int = 0

    @property
    def total_tokens(self) -> int:
        return self.input_tokens + self.output_tokens

    def add(self, input_tokens: int, output_tokens: int):
        self.input_tokens += input_tokens
        self.output_tokens += output_tokens

    def to_dict(self) -> Dict[str, int]:
        return {
            "input_tokens": self.input_tokens,
            "output_tokens": self.output_tokens,
            "total_tokens": self.total_tokens,
        }


@dataclass
class Trajectory:
    """
    Complete execution history for an agent task.

    Supports:
    - Event tracking for observability
    - Step-by-step message reconstruction
    - Checkpoint/recovery via serialization
    - Token usage aggregation
    """
    session_id: UUID = field(default_factory=uuid4)
    agent_id: str = ""
    task_id: str = ""
    system_prompt: str = ""
    events: List[AgentEvent] = field(default_factory=list)
    steps: List[TrajectoryStep] = field(default_factory=list)
    usage: TokenUsage = field(default_factory=TokenUsage)
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)

    def add_event(self, event: AgentEvent):
        """Add an event to the trajectory."""
        event.agent_id = self.agent_id
        event.task_id = self.task_id
        self.events.append(event)
        self.updated_at = datetime.utcnow()

    def add_step(self, step: TrajectoryStep):
        """Add a step to the trajectory."""
        self.steps.append(step)
        self.updated_at = datetime.utcnow()

    def add_generation(
        self,
        step_number: int,
        model: str,
        input_tokens: int,
        output_tokens: int,
        content: str,
        tool_calls: List[Dict[str, Any]],
    ):
        """Add a generation result."""
        from .events import GenerationStep

        event = GenerationStep(
            step=step_number,
            model=model,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            content=content,
            tool_calls=tool_calls,
        )
        self.add_event(event)
        self.usage.add(input_tokens, output_tokens)

        # Find or create step
        step = self._get_or_create_step(step_number)
        step.generation = event.to_dict()

    def add_tool_result(
        self,
        step_number: int,
        tool_name: str,
        tool_id: str,
        arguments: Dict[str, Any],
        result: Any,
        error: Optional[str] = None,
        duration_ms: int = 0,
    ):
        """Add a tool execution result."""
        from .events import ToolStep

        event = ToolStep(
            step=step_number,
            tool_name=tool_name,
            tool_id=tool_id,
            arguments=arguments,
            result=result,
            error=error,
            duration_ms=duration_ms,
        )
        self.add_event(event)

        # Add to step
        step = self._get_or_create_step(step_number)
        step.tool_results.append(event.to_dict())

    def _get_or_create_step(self, step_number: int) -> TrajectoryStep:
        """Get existing step or create new one."""
        for step in self.steps:
            if step.step_number == step_number:
                return step

        step = TrajectoryStep(step_number=step_number)
        self.steps.append(step)
        self.steps.sort(key=lambda s: s.step_number)
        return step

    @property
    def messages(self) -> List[Dict[str, Any]]:
        """Reconstruct all messages from steps."""
        all_messages = []
        for step in self.steps:
            all_messages.extend(step.messages)
        return all_messages

    @property
    def last_step(self) -> Optional[TrajectoryStep]:
        """Get the most recent step."""
        return self.steps[-1] if self.steps else None

    @property
    def step_count(self) -> int:
        """Number of steps in trajectory."""
        return len(self.steps)

    def get_summary(self) -> Dict[str, Any]:
        """Get high-level execution summary."""
        from .events import AgentEnd

        # Find end event if exists
        end_event = None
        for event in reversed(self.events):
            if isinstance(event, AgentEnd):
                end_event = event
                break

        return {
            "session_id": str(self.session_id),
            "agent_id": self.agent_id,
            "task_id": self.task_id,
            "steps": self.step_count,
            "events": len(self.events),
            "usage": self.usage.to_dict(),
            "stop_reason": end_event.stop_reason.value if end_event else None,
            "error": end_event.error if end_event else None,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
        }

    def to_dict(self) -> Dict[str, Any]:
        """Serialize trajectory to dictionary."""
        return {
            "session_id": str(self.session_id),
            "agent_id": self.agent_id,
            "task_id": self.task_id,
            "system_prompt": self.system_prompt,
            "events": [e.to_dict() for e in self.events],
            "steps": [s.to_dict() for s in self.steps],
            "usage": self.usage.to_dict(),
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "Trajectory":
        """Deserialize trajectory from dictionary."""
        trajectory = cls(
            session_id=UUID(data["session_id"]),
            agent_id=data.get("agent_id", ""),
            task_id=data.get("task_id", ""),
            system_prompt=data.get("system_prompt", ""),
            created_at=datetime.fromisoformat(data["created_at"]),
            updated_at=datetime.fromisoformat(data["updated_at"]),
        )

        # Deserialize events
        for event_data in data.get("events", []):
            trajectory.events.append(event_from_dict(event_data))

        # Deserialize steps
        for step_data in data.get("steps", []):
            trajectory.steps.append(TrajectoryStep.from_dict(step_data))

        # Restore usage
        usage_data = data.get("usage", {})
        trajectory.usage.input_tokens = usage_data.get("input_tokens", 0)
        trajectory.usage.output_tokens = usage_data.get("output_tokens", 0)

        return trajectory

    def to_json(self) -> str:
        """Serialize to JSON string."""
        import json
        return json.dumps(self.to_dict(), indent=2)

    @classmethod
    def from_json(cls, json_str: str) -> "Trajectory":
        """Deserialize from JSON string."""
        import json
        return cls.from_dict(json.loads(json_str))
