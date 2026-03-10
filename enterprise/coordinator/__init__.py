"""
Mission Coordinator Service

Coordinators are specialized agents that:
- Decompose high-level goals into tasks
- Manage workforce (spawn/supervise worker agents)
- Handle escalations from workers
- Make decisions that require broader context
- Coordinate between teams

Architecture:
    Coordinators are agents (not special services) that share backing state.
    Multiple coordinator instances can run for HA and load distribution.
"""

from .service import MissionCoordinator
from .goal import Goal, GoalStatus, GoalDecomposition
from .goal_ingress import build_goal, build_goal_decomposition_task
from .workforce import WorkforceManager, AgentPool
from .escalation import EscalationHandler

__all__ = [
    "MissionCoordinator",
    "Goal",
    "GoalStatus",
    "GoalDecomposition",
    "build_goal",
    "build_goal_decomposition_task",
    "WorkforceManager",
    "AgentPool",
    "EscalationHandler",
]
