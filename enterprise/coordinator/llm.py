"""
LLM client protocol for coordinator services.

Defines the interface that any LLM backend must satisfy to be used
by the MissionCoordinator for goal decomposition, escalation resolution,
progress review, and generic task handling.
"""

from typing import Any, Dict, List, Optional, Protocol, runtime_checkable


@runtime_checkable
class LLMClient(Protocol):
    """Protocol for LLM backends used by the coordinator.

    Implementations might wrap the Anthropic SDK, OpenAI SDK, a local
    model server, or a test stub.
    """

    async def generate(
        self,
        messages: List[Dict[str, Any]],
        system: str = "",
        tools: Optional[List[Dict[str, Any]]] = None,
    ) -> str:
        """Generate a completion from the LLM.

        Args:
            messages: Conversation messages in [{"role": "...", "content": "..."}] format.
            system: Optional system prompt.
            tools: Optional tool definitions for function-calling models.

        Returns:
            The model's text response.
        """
        ...
