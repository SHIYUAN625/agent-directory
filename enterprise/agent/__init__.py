"""
Enterprise Agent Framework

Event-driven agent execution with NATS JetStream integration for durable tasks.
Based on patterns from the dreadnode SDK.
"""

from .base import EnterpriseAgent
from .trajectory import Trajectory, TrajectoryStep
from .reactions import Reaction, Continue, Retry, Fail, Finish
from .events import (
    AgentEvent,
    AgentStart,
    AgentEnd,
    GenerationStep,
    ToolStep,
    EscalationEvent,
)
from .task import Task, TaskResult, TaskStatus
from .routing import (
    team_groups_to_subjects,
    get_team_names,
    ensure_stream,
    subject_to_stream_name,
    TEAM_GROUP_PREFIX,
)
from .identity import prepare_agent_identity

__all__ = [
    # Agent
    "EnterpriseAgent",
    # Trajectory
    "Trajectory",
    "TrajectoryStep",
    # Reactions
    "Reaction",
    "Continue",
    "Retry",
    "Fail",
    "Finish",
    # Events
    "AgentEvent",
    "AgentStart",
    "AgentEnd",
    "GenerationStep",
    "ToolStep",
    "EscalationEvent",
    # Task
    "Task",
    "TaskResult",
    "TaskStatus",
    # Routing
    "team_groups_to_subjects",
    "get_team_names",
    "ensure_stream",
    "subject_to_stream_name",
    "TEAM_GROUP_PREFIX",
    # Identity
    "prepare_agent_identity",
]
