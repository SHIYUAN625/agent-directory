"""Tests for goal ingress helper functions."""

from enterprise.coordinator.goal import GoalPriority
from enterprise.coordinator.goal_ingress import (
    build_goal,
    build_goal_decomposition_task,
    normalize_goal_priority,
)


def test_normalize_goal_priority_buckets():
    assert normalize_goal_priority(50) == GoalPriority.LOW
    assert normalize_goal_priority(500) == GoalPriority.NORMAL
    assert normalize_goal_priority(850) == GoalPriority.HIGH
    assert normalize_goal_priority(1200) == GoalPriority.CRITICAL


def test_build_goal_and_task_defaults():
    goal = build_goal(
        title="Automate monthly reporting",
        description="Coordinate engineering and data operations tasks",
        priority=820,
        constraints=["No production downtime"],
        success_criteria=["Report generated", "Stakeholders notified"],
    )

    task = build_goal_decomposition_task(goal)
    assert task.task_type == "goal_decomposition"
    assert task.priority == GoalPriority.HIGH.value
    assert task.payload["goal"]["title"] == "Automate monthly reporting"
    assert task.payload["goal"]["constraints"] == ["No production downtime"]
    assert task.reply_to.startswith("results.coordination.")
