"""
Team-based task routing derived from AD group membership.

AD groups define the organizational structure. NATS subjects and JetStream
streams are derived from it — AD is the single source of truth.

    AD Group              →  NATS Subject         →  JetStream Stream
    ─────────────────────────────────────────────────────────────────
    Team-Engineering      →  tasks.engineering     →  TASKS_ENGINEERING
    Team-DataOps          →  tasks.dataops         →  TASKS_DATAOPS
    Team-Coordination     →  tasks.coordination    →  TASKS_COORDINATION

Teams are made up of individuals with different skillsets (tools, trust
levels, models). The coordinator routes work to teams, not individuals.
Within a team, JetStream work queues distribute to available agents.
"""

import logging
from typing import List

logger = logging.getLogger(__name__)

TEAM_GROUP_PREFIX = "Team-"


def team_groups_to_subjects(group_dns: List[str]) -> List[str]:
    """
    Derive NATS task subjects from AD group membership.

    Scans an agent's memberOf DNs for Team-* groups and converts each
    to a NATS subject that the agent should subscribe to.

    Args:
        group_dns: List of AD group distinguished names from memberOf attribute.

    Returns:
        List of NATS subjects (e.g. ["tasks.engineering", "tasks.dataops"]).
    """
    subjects = []
    for dn in group_dns:
        cn = _extract_cn(dn)
        if cn and cn.startswith(TEAM_GROUP_PREFIX):
            team_name = cn[len(TEAM_GROUP_PREFIX):].lower()
            subjects.append(f"tasks.{team_name}")
    return subjects


def get_team_names(group_dns: List[str]) -> List[str]:
    """
    Extract team names from AD group DNs.

    Args:
        group_dns: List of AD group distinguished names.

    Returns:
        List of team names (e.g. ["Engineering", "DataOps"]).
    """
    teams = []
    for dn in group_dns:
        cn = _extract_cn(dn)
        if cn and cn.startswith(TEAM_GROUP_PREFIX):
            teams.append(cn[len(TEAM_GROUP_PREFIX):])
    return teams


def subject_to_stream_name(subject: str) -> str:
    """
    Derive JetStream stream name from a NATS subject.

    Convention: tasks.engineering → TASKS_ENGINEERING

    Args:
        subject: NATS subject (e.g. "tasks.engineering" or "tasks.engineering.agent-01").

    Returns:
        Stream name (e.g. "TASKS_ENGINEERING").

    Raises:
        ValueError: If subject has fewer than 2 dot-separated parts.
    """
    parts = subject.split(".")
    if len(parts) < 2:
        raise ValueError(
            f"Malformed NATS subject '{subject}': "
            f"expected 'prefix.category[.suffix]'"
        )
    return f"TASKS_{parts[1].upper()}"


async def ensure_stream(js, subject: str) -> str:
    """
    Ensure the JetStream stream for a task subject exists.

    Derives the stream name from the subject convention, then creates
    a WORK_QUEUE stream if it doesn't already exist. Idempotent — safe
    to call from multiple agents concurrently (first one wins).

    Args:
        js: JetStream context (from nats_client.jetstream()).
        subject: NATS subject to ensure a stream for.

    Returns:
        The stream name.
    """
    from nats.js.api import StreamConfig, RetentionPolicy

    stream_name = subject_to_stream_name(subject)
    parts = subject.split(".")
    base_subject = f"{parts[0]}.{parts[1]}"

    try:
        # Check if subject is already captured by a stream
        found = await js.find_stream_name_by_subject(subject)
        if found:
            return found
    except Exception:
        pass  # No stream captures this subject yet

    # Create the stream — includes both base and wildcard subjects
    try:
        await js.add_stream(StreamConfig(
            name=stream_name,
            subjects=[base_subject, f"{base_subject}.>"],
            retention=RetentionPolicy.WORK_QUEUE,
        ))
        logger.info(f"Created stream {stream_name} for {base_subject}")
    except Exception as e:
        # Stream may have been created by another agent concurrently,
        # or may already exist with different config. Either way, the
        # pull_subscribe call will surface the real error if any.
        logger.debug(f"Stream ensure for {stream_name}: {e}")

    return stream_name


def _extract_cn(dn: str) -> str:
    """Extract the CN value from a distinguished name."""
    parts = dn.split(",")
    if parts and parts[0].startswith("CN="):
        return parts[0][3:]
    return ""
