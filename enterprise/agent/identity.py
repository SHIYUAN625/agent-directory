"""
Helpers to normalize AD-assembled identity data for EnterpriseAgent runtime.
"""

from __future__ import annotations

from typing import Any, Dict, List

from .routing import team_groups_to_subjects


def prepare_agent_identity(
    config: Dict[str, Any],
    escalation_path: str = "escalations.team",
) -> Dict[str, Any]:
    """
    Transform ConfigAssembler output into EnterpriseAgent-compatible identity.

    - Maps `type` -> `agent_type`
    - Normalizes escalation path to a NATS subject string
    - Derives task subjects from Team-* group membership
    """
    source = config.get("agent", config)
    agent = dict(source)

    agent["agent_type"] = agent.get("agent_type") or agent.get("type", "autonomous")
    agent.pop("type", None)

    agent["escalation_path"] = _normalize_escalation_path(
        agent.get("escalation_path"),
        escalation_path,
    )

    groups = _as_list(agent.get("groups"))
    derived_subjects = team_groups_to_subjects(groups)
    if derived_subjects:
        agent["nats_subjects"] = derived_subjects
    else:
        # Fallback to precomputed subjects if group membership is unavailable.
        agent["nats_subjects"] = _task_subjects(_as_list(agent.get("nats_subjects")))

    return agent


def _normalize_escalation_path(value: Any, default_path: str) -> str:
    if isinstance(value, str):
        return value if value.startswith("escalations.") else default_path
    if isinstance(value, list):
        for item in value:
            if isinstance(item, str) and item.startswith("escalations."):
                return item
    return default_path


def _task_subjects(subjects: List[str]) -> List[str]:
    cleaned: List[str] = []
    for subject in subjects:
        if not isinstance(subject, str):
            continue
        parts = subject.split(".")
        if len(parts) >= 2 and parts[0] == "tasks":
            cleaned.append(subject)
    return cleaned


def _as_list(value: Any) -> List[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]
