"""Tests for coordinator error paths — no LLM graceful degradation."""

import json

import pytest

from enterprise.agent.events import GenerationStep, ToolStep
from enterprise.agent.base import EnterpriseAgent
from enterprise.agent.reactions import Finish
from enterprise.agent.task import Task
from enterprise.coordinator.service import MissionCoordinator
from enterprise.coordinator.goal import Goal, GoalStatus
from enterprise.coordinator.escalation import EscalationHandler
from enterprise.coordinator.workforce import WorkforceManager


def _make_coordinator(llm_client=None):
    """Create a MissionCoordinator with minimal identity/policy."""
    identity = {
        "name": "coord-01",
        "agent_type": "coordinator",
        "trust_level": 5,
        "model": "claude-sonnet-4-5-20250929",
        "nats_subjects": ["tasks.coordination", "escalations.team-alpha"],
        "escalation_path": "escalations.senior",
        "mission": "Coordinate team alpha",
    }
    policy = {
        "execution": {"max_iterations": 50, "checkpoint_interval_steps": 10},
    }
    return MissionCoordinator(
        identity=identity,
        policy=policy,
        nats_client=None,
        db_session=None,
        llm_client=llm_client,
    )


def _make_escalation_task():
    return Task(
        task_type="escalation_resolution",
        payload={
            "escalation": {
                "source_agent": "worker-01",
                "error": "tool execution failed",
                "reason": "permission denied",
                "attempted_resolutions": ["retry"],
            },
        },
    )


def _make_progress_review_task():
    return Task(
        task_type="progress_review",
        payload={},
    )


def _make_generic_task():
    return Task(
        task_type="analyze_results",
        payload={"description": "Summarize weekly output"},
    )


class FakeLLMClient:
    """Simple LLM stub that returns canned JSON responses."""

    def __init__(self, response: str = "{}"):
        self.response = response
        self.calls = []

    async def generate(self, messages, system="", tools=None):
        self.calls.append({"messages": messages, "system": system, "tools": tools})
        return self.response


@pytest.mark.asyncio
async def test_coordinator_start_wires_workforce_api_key(monkeypatch):
    """Coordinator startup should initialize WorkforceManager with an API key."""
    coord = _make_coordinator(llm_client=None)
    coord.provisioner_api_key = "test-provisioner-key"

    async def _noop_start(self, *args, **kwargs):
        return None

    async def _noop_stop(self, *args, **kwargs):
        return None

    monkeypatch.setattr(WorkforceManager, "start", _noop_start)
    monkeypatch.setattr(WorkforceManager, "stop", _noop_stop)
    monkeypatch.setattr(EscalationHandler, "start", _noop_start)
    monkeypatch.setattr(EscalationHandler, "stop", _noop_stop)
    monkeypatch.setattr(EnterpriseAgent, "start", _noop_start)
    monkeypatch.setattr(EnterpriseAgent, "stop", _noop_stop)

    await coord.start()
    try:
        assert coord.workforce is not None
        assert coord.workforce.api_key == "test-provisioner-key"
    finally:
        await coord.stop()


# --- Escalation resolution ---

@pytest.mark.asyncio
async def test_resolve_escalation_without_llm_degrades():
    """Without LLM, escalation resolution should yield events, not crash."""
    coord = _make_coordinator(llm_client=None)
    task = _make_escalation_task()

    events = []
    async for event in coord._resolve_escalation(task, step=1):
        events.append(event)

    assert len(events) == 1
    assert isinstance(events[0], ToolStep)
    assert events[0].result["status"] == "no_llm"
    assert events[0].result["action"] == "escalate"


@pytest.mark.asyncio
async def test_resolve_escalation_with_llm():
    """With LLM, escalation resolution should call LLM and yield events."""
    llm = FakeLLMClient(response=json.dumps({
        "root_cause": "permission misconfiguration",
        "resolution_steps": ["update ACL", "retry task"],
        "action": "retry",
    }))
    coord = _make_coordinator(llm_client=llm)
    task = _make_escalation_task()

    events = []
    async for event in coord._resolve_escalation(task, step=1):
        events.append(event)

    assert len(events) == 2
    assert isinstance(events[0], GenerationStep)
    assert isinstance(events[1], ToolStep)
    assert events[1].result["action"] == "retry"
    assert len(llm.calls) == 1


# --- Progress review ---

@pytest.mark.asyncio
async def test_review_progress_without_llm_degrades():
    """Without LLM, progress review returns raw metrics."""
    coord = _make_coordinator(llm_client=None)

    # Add some goals for the review
    goal = Goal(title="Deploy service", description="Deploy v2")
    goal.status = GoalStatus.IN_PROGRESS
    goal.metrics.total_tasks = 5
    goal.metrics.completed_tasks = 3
    coord.goals[goal.id] = goal

    task = _make_progress_review_task()

    events = []
    async for event in coord._review_progress(task, step=1):
        events.append(event)

    assert len(events) == 1
    assert isinstance(events[0], ToolStep)
    result = events[0].result
    assert result["status"] == "no_llm"
    assert len(result["goals"]) == 1
    assert result["goals"][0]["tasks_completed"] == 3


@pytest.mark.asyncio
async def test_review_progress_with_llm():
    """With LLM, progress review calls LLM with goal summaries."""
    llm = FakeLLMClient(response=json.dumps({
        "overall_status": "on track",
        "blocked_goals": [],
        "recommendations": ["Continue current pace"],
    }))
    coord = _make_coordinator(llm_client=llm)

    goal = Goal(title="Deploy service", description="Deploy v2")
    goal.status = GoalStatus.IN_PROGRESS
    coord.goals[goal.id] = goal

    task = _make_progress_review_task()

    events = []
    async for event in coord._review_progress(task, step=1):
        events.append(event)

    assert len(events) == 2
    assert isinstance(events[0], GenerationStep)
    assert isinstance(events[1], ToolStep)
    assert events[1].result["overall_status"] == "on track"


# --- Generic task handling ---

@pytest.mark.asyncio
async def test_handle_generic_task_without_llm_degrades():
    """Without LLM, generic tasks should escalate, not crash."""
    coord = _make_coordinator(llm_client=None)
    task = _make_generic_task()

    events = []
    async for event in coord._handle_generic_task(task, step=1):
        events.append(event)

    assert len(events) == 1
    assert isinstance(events[0], ToolStep)
    assert events[0].result["status"] == "no_llm"
    assert events[0].result["action"] == "escalate"


@pytest.mark.asyncio
async def test_handle_generic_task_with_llm():
    """With LLM, generic tasks should call LLM with tools and yield events."""
    llm = FakeLLMClient(response=json.dumps({
        "analysis": "Weekly output looks good",
        "actions": [],
        "result": "Summary complete",
    }))
    coord = _make_coordinator(llm_client=llm)
    task = _make_generic_task()

    events = []
    async for event in coord._handle_generic_task(task, step=1):
        events.append(event)

    assert len(events) == 2
    assert isinstance(events[0], GenerationStep)
    assert isinstance(events[1], ToolStep)
    # Verify tools were passed to the LLM
    assert llm.calls[0]["tools"] is not None
    assert len(llm.calls[0]["tools"]) > 0


# --- Goal decomposition (existing else branch) ---

@pytest.mark.asyncio
async def test_decompose_goal_without_llm_creates_simple_task():
    """Without LLM, goal decomposition yields a simple task event."""
    coord = _make_coordinator(llm_client=None)

    task = Task(
        task_type="goal_decomposition",
        payload={
            "goal": {
                "title": "Build feature X",
                "description": "Implement the feature",
                "context": {},
                "constraints": [],
                "success_criteria": ["Tests pass"],
            },
        },
    )

    events = []
    async for event in coord._decompose_goal(task, step=1):
        events.append(event)

    assert len(events) == 1
    assert isinstance(events[0], ToolStep)
    assert events[0].tool_name == "simple_decomposition"


@pytest.mark.asyncio
async def test_execute_step_signals_finish_for_goal_decomposition():
    """execute_step should complete coordinator tasks in one pass."""
    coord = _make_coordinator(llm_client=None)
    task = Task(
        task_type="goal_decomposition",
        payload={
            "goal": {
                "title": "Reduce support backlog",
                "description": "Coordinate cross-team work",
                "context": {},
                "constraints": [],
                "success_criteria": ["Backlog reduced"],
            },
        },
    )

    events = []
    with pytest.raises(Finish) as exc_info:
        async for event in coord.execute_step(task, step=1):
            events.append(event)

    assert len(events) == 1
    assert isinstance(events[0], ToolStep)
    assert exc_info.value.result["status"] == "completed"
