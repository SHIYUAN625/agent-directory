"""
Goal representation and decomposition for mission coordination.
"""

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional
from uuid import UUID, uuid4


class GoalStatus(str, Enum):
    """Status of a goal."""
    PENDING = "pending"           # Not started
    PLANNING = "planning"         # Being decomposed
    IN_PROGRESS = "in_progress"   # Tasks being executed
    BLOCKED = "blocked"           # Waiting on dependency or escalation
    COMPLETED = "completed"       # Successfully finished
    FAILED = "failed"             # Failed after retries
    CANCELLED = "cancelled"       # Manually cancelled


class GoalPriority(int, Enum):
    """Priority levels for goals."""
    LOW = 100
    NORMAL = 500
    HIGH = 800
    CRITICAL = 1000


@dataclass
class GoalMetrics:
    """Metrics for goal progress tracking."""
    total_tasks: int = 0
    completed_tasks: int = 0
    failed_tasks: int = 0
    in_progress_tasks: int = 0
    blocked_tasks: int = 0
    estimated_completion: Optional[datetime] = None
    actual_start: Optional[datetime] = None
    actual_completion: Optional[datetime] = None

    @property
    def progress_percent(self) -> float:
        if self.total_tasks == 0:
            return 0.0
        return (self.completed_tasks / self.total_tasks) * 100

    def to_dict(self) -> Dict[str, Any]:
        return {
            "total_tasks": self.total_tasks,
            "completed_tasks": self.completed_tasks,
            "failed_tasks": self.failed_tasks,
            "in_progress_tasks": self.in_progress_tasks,
            "blocked_tasks": self.blocked_tasks,
            "progress_percent": self.progress_percent,
            "estimated_completion": self.estimated_completion.isoformat() if self.estimated_completion else None,
            "actual_start": self.actual_start.isoformat() if self.actual_start else None,
            "actual_completion": self.actual_completion.isoformat() if self.actual_completion else None,
        }


@dataclass
class Goal:
    """
    A high-level goal that can be decomposed into tasks.

    Goals represent the desired outcome. The coordinator:
    1. Analyzes the goal to understand requirements
    2. Decomposes it into sub-goals or tasks
    3. Manages execution and tracks progress
    4. Reports completion or escalates issues
    """
    id: UUID = field(default_factory=uuid4)
    title: str = ""
    description: str = ""
    priority: GoalPriority = GoalPriority.NORMAL
    status: GoalStatus = GoalStatus.PENDING

    # Source
    source_agent: str = ""        # Agent that created this goal
    source_mission: str = ""      # Parent mission ID
    parent_goal: Optional[UUID] = None  # Parent goal if sub-goal

    # Decomposition
    sub_goals: List[UUID] = field(default_factory=list)
    task_ids: List[UUID] = field(default_factory=list)
    dependencies: List[UUID] = field(default_factory=list)  # Goals that must complete first

    # Context for decomposition
    context: Dict[str, Any] = field(default_factory=dict)
    constraints: List[str] = field(default_factory=list)
    success_criteria: List[str] = field(default_factory=list)

    # Progress
    metrics: GoalMetrics = field(default_factory=GoalMetrics)

    # Timestamps
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": str(self.id),
            "title": self.title,
            "description": self.description,
            "priority": self.priority.value,
            "status": self.status.value,
            "source_agent": self.source_agent,
            "source_mission": self.source_mission,
            "parent_goal": str(self.parent_goal) if self.parent_goal else None,
            "sub_goals": [str(g) for g in self.sub_goals],
            "task_ids": [str(t) for t in self.task_ids],
            "dependencies": [str(d) for d in self.dependencies],
            "context": self.context,
            "constraints": self.constraints,
            "success_criteria": self.success_criteria,
            "metrics": self.metrics.to_dict(),
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "Goal":
        metrics_data = data.get("metrics", {})
        metrics = GoalMetrics(
            total_tasks=metrics_data.get("total_tasks", 0),
            completed_tasks=metrics_data.get("completed_tasks", 0),
            failed_tasks=metrics_data.get("failed_tasks", 0),
            in_progress_tasks=metrics_data.get("in_progress_tasks", 0),
            blocked_tasks=metrics_data.get("blocked_tasks", 0),
        )

        return cls(
            id=UUID(data["id"]) if data.get("id") else uuid4(),
            title=data.get("title", ""),
            description=data.get("description", ""),
            priority=GoalPriority(data.get("priority", 500)),
            status=GoalStatus(data.get("status", "pending")),
            source_agent=data.get("source_agent", ""),
            source_mission=data.get("source_mission", ""),
            parent_goal=UUID(data["parent_goal"]) if data.get("parent_goal") else None,
            sub_goals=[UUID(g) for g in data.get("sub_goals", [])],
            task_ids=[UUID(t) for t in data.get("task_ids", [])],
            dependencies=[UUID(d) for d in data.get("dependencies", [])],
            context=data.get("context", {}),
            constraints=data.get("constraints", []),
            success_criteria=data.get("success_criteria", []),
            metrics=metrics,
            created_at=datetime.fromisoformat(data["created_at"]) if data.get("created_at") else datetime.utcnow(),
            updated_at=datetime.fromisoformat(data["updated_at"]) if data.get("updated_at") else datetime.utcnow(),
        )


@dataclass
class GoalDecomposition:
    """
    Result of decomposing a goal into actionable items.

    Created by the coordinator's LLM reasoning about how to achieve a goal.
    """
    goal_id: UUID
    sub_goals: List[Goal] = field(default_factory=list)
    tasks: List[Dict[str, Any]] = field(default_factory=list)  # Task definitions
    approach: str = ""           # Description of chosen approach
    rationale: str = ""          # Why this approach was chosen
    alternatives: List[str] = field(default_factory=list)  # Other approaches considered
    risks: List[str] = field(default_factory=list)
    requires_approval: bool = False  # If true, needs human approval before execution

    def to_dict(self) -> Dict[str, Any]:
        return {
            "goal_id": str(self.goal_id),
            "sub_goals": [g.to_dict() for g in self.sub_goals],
            "tasks": self.tasks,
            "approach": self.approach,
            "rationale": self.rationale,
            "alternatives": self.alternatives,
            "risks": self.risks,
            "requires_approval": self.requires_approval,
        }


DECOMPOSITION_PROMPT = """
You are a mission coordinator for an autonomous enterprise. Your task is to decompose
a high-level goal into actionable sub-goals and tasks that can be executed by worker agents.

GOAL: {title}
DESCRIPTION: {description}

CONTEXT:
{context}

CONSTRAINTS:
{constraints}

SUCCESS CRITERIA:
{success_criteria}

AVAILABLE AGENT TYPES:
{agent_types}

Analyze this goal and provide a decomposition plan:

1. APPROACH: Describe your chosen approach to achieving this goal.

2. SUB-GOALS: If the goal is complex, break it into smaller sub-goals.
   Each sub-goal should be independently achievable and measurable.

3. TASKS: For each sub-goal (or the main goal if simple), define specific tasks:
   - task_type: Type of agent needed (code-review, analysis, generic, etc.)
   - description: Clear description of what the task should accomplish
   - dependencies: Other task IDs that must complete first
   - priority: 0-1000 (higher = more urgent)
   - requirements: capabilities or trust level needed

4. RISKS: What could go wrong? What are the dependencies?

5. APPROVAL_REQUIRED: Does this need human approval before execution?
   (Required for: destructive operations, external communications, large resource usage)

Respond in JSON format.
"""
