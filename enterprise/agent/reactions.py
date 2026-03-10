"""
Reaction-based flow control for agent execution.

Reactions are exceptions that control the agent execution loop:
- Continue: Keep going, optionally with feedback
- Retry: Re-run current step with backoff
- Fail: Stop with error, trigger escalation
- Finish: Complete successfully

Based on dreadnode SDK patterns.
"""

from dataclasses import dataclass, field
from typing import List, Optional, Any


class Reaction(Exception):
    """Base class for agent execution reactions."""
    pass


@dataclass
class Continue(Reaction):
    """
    Continue execution with optional feedback.

    The agent will proceed to the next iteration, optionally
    incorporating the feedback into its context.
    """
    feedback: Optional[str] = None
    messages: List[Any] = field(default_factory=list)

    def __str__(self):
        return f"Continue(feedback={self.feedback!r})"


@dataclass
class Retry(Reaction):
    """
    Retry the current step.

    The agent will re-run the current step, typically after
    addressing an issue identified by a hook.
    """
    reason: str = ""
    backoff_seconds: float = 5.0
    max_retries: int = 3
    messages: List[Any] = field(default_factory=list)

    def __str__(self):
        return f"Retry(reason={self.reason!r}, backoff={self.backoff_seconds}s)"


@dataclass
class Fail(Reaction):
    """
    Fail the agent execution.

    Triggers escalation to the configured escalation path.
    The error and trajectory are included in the escalation.
    """
    error: str
    reason: str = ""
    escalate: bool = True

    def __str__(self):
        return f"Fail(error={self.error!r}, escalate={self.escalate})"


@dataclass
class Finish(Reaction):
    """
    Successfully complete the agent execution.

    The agent will stop and report the result.
    """
    result: Any = None
    reason: str = "task_completed"

    def __str__(self):
        return f"Finish(reason={self.reason!r})"


# Reaction priority for conflict resolution
REACTION_PRIORITY = {
    Finish: 4,   # Highest - success takes precedence
    Fail: 3,     # Next - failure should stop execution
    Retry: 2,    # Retry before continuing
    Continue: 1, # Lowest - default behavior
}


def select_reaction(*reactions: Optional[Reaction]) -> Optional[Reaction]:
    """
    Select the highest priority reaction from a list.

    Used when multiple hooks return reactions.
    """
    valid = [r for r in reactions if r is not None]
    if not valid:
        return None

    return max(valid, key=lambda r: REACTION_PRIORITY.get(type(r), 0))
