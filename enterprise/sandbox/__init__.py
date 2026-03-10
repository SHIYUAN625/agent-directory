"""
Agent Sandbox Configuration

Provides bwrap (bubblewrap) sandbox profiles for agent isolation.
Defense-in-depth: VM-level isolation via Firecracker + process-level via bwrap.
"""

from .bwrap import BwrapProfile, SandboxConfig, generate_bwrap_command
from .seccomp import SeccompProfile, generate_seccomp_filter

__all__ = [
    "BwrapProfile",
    "SandboxConfig",
    "generate_bwrap_command",
    "SeccompProfile",
    "generate_seccomp_filter",
]
