"""Goal ingress helpers for submitting high-level goals to coordinators."""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional
from uuid import uuid4

from ..agent.task import Task, TaskSource
from .goal import Goal, GoalPriority

DEFAULT_COORDINATION_SUBJECT = "tasks.coordination"


def normalize_goal_priority(value: int) -> GoalPriority:
    """Map arbitrary integer priority to supported goal priority enum."""
    if value >= GoalPriority.CRITICAL.value:
        return GoalPriority.CRITICAL
    if value >= GoalPriority.HIGH.value:
        return GoalPriority.HIGH
    if value >= GoalPriority.NORMAL.value:
        return GoalPriority.NORMAL
    return GoalPriority.LOW


def build_goal(
    title: str,
    description: str,
    *,
    priority: int = GoalPriority.NORMAL.value,
    source_agent: str = "enterprise-operator",
    source_mission: str = "manual-goal-ingress",
    context: Optional[Dict[str, Any]] = None,
    constraints: Optional[List[str]] = None,
    success_criteria: Optional[List[str]] = None,
) -> Goal:
    """Construct a Goal object from ingress inputs."""
    return Goal(
        title=title,
        description=description,
        priority=normalize_goal_priority(priority),
        source_agent=source_agent,
        source_mission=source_mission,
        context=context or {},
        constraints=constraints or [],
        success_criteria=success_criteria or [],
    )


def build_goal_decomposition_task(
    goal: Goal,
    *,
    ingress_agent: str = "goal-ingress",
    mission_id: str = "manual-goal-ingress",
    reply_to: Optional[str] = None,
    expires_in_minutes: int = 30,
) -> Task:
    """Build a goal_decomposition task for a coordinator queue."""
    return Task(
        task_type="goal_decomposition",
        priority=goal.priority.value,
        source=TaskSource(
            agent_id=ingress_agent,
            mission_id=mission_id,
            parent_task_id=str(goal.id),
        ),
        payload={"goal": goal.to_dict()},
        reply_to=reply_to or f"results.coordination.{uuid4()}",
        expires_at=datetime.utcnow() + timedelta(minutes=expires_in_minutes),
    )
