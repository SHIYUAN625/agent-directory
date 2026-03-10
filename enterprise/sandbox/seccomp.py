"""
Seccomp filter profiles for agent sandboxing.

Seccomp (secure computing) filters restrict the system calls available
to a process. This provides defense-in-depth alongside bwrap namespaces
and Firecracker VM isolation.
"""

import json
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional


class SeccompAction(str, Enum):
    """Action to take when syscall matches."""
    ALLOW = "SCMP_ACT_ALLOW"
    ERRNO = "SCMP_ACT_ERRNO"
    KILL = "SCMP_ACT_KILL"
    TRAP = "SCMP_ACT_TRAP"
    LOG = "SCMP_ACT_LOG"


@dataclass
class SyscallRule:
    """A rule for a specific syscall."""
    name: str
    action: SeccompAction = SeccompAction.ALLOW
    args: List[Dict[str, Any]] = field(default_factory=list)  # Argument filters


@dataclass
class SeccompProfile:
    """
    Seccomp filter profile.

    Defines which syscalls are allowed/denied for sandboxed agents.
    """
    name: str
    default_action: SeccompAction = SeccompAction.ERRNO
    architectures: List[str] = field(default_factory=lambda: ["SCMP_ARCH_X86_64"])
    syscalls: List[SyscallRule] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to seccomp JSON format (OCI/docker compatible)."""
        return {
            "defaultAction": self.default_action.value,
            "architectures": self.architectures,
            "syscalls": [
                {
                    "names": [rule.name],
                    "action": rule.action.value,
                    "args": rule.args,
                }
                for rule in self.syscalls
            ],
        }

    def to_json(self, indent: int = 2) -> str:
        """Serialize to JSON string."""
        return json.dumps(self.to_dict(), indent=indent)

    @classmethod
    def from_dict(cls, data: Dict[str, Any], name: str = "custom") -> "SeccompProfile":
        """Load from dictionary."""
        syscalls = []
        for rule in data.get("syscalls", []):
            for syscall_name in rule.get("names", []):
                syscalls.append(SyscallRule(
                    name=syscall_name,
                    action=SeccompAction(rule.get("action", "SCMP_ACT_ALLOW")),
                    args=rule.get("args", []),
                ))

        return cls(
            name=name,
            default_action=SeccompAction(data.get("defaultAction", "SCMP_ACT_ERRNO")),
            architectures=data.get("architectures", ["SCMP_ARCH_X86_64"]),
            syscalls=syscalls,
        )


# Safe syscalls allowed for all agents
SAFE_SYSCALLS = [
    # File operations (basic)
    "read", "write", "close", "fstat", "lseek", "mmap", "mprotect",
    "munmap", "brk", "pread64", "pwrite64", "readv", "writev",
    "access", "pipe", "dup", "dup2", "dup3",
    "fcntl", "flock", "fsync", "fdatasync",
    "ftruncate", "getdents", "getdents64",
    "lstat", "stat", "fstatat", "newfstatat", "statx",
    "openat", "readlinkat", "faccessat", "faccessat2",
    "fchmod", "fchmodat",

    # Process (safe)
    "exit", "exit_group", "wait4", "waitid",
    "getpid", "getppid", "getuid", "geteuid", "getgid", "getegid",
    "setuid", "setgid", "setgroups",
    "getgroups", "setreuid", "setregid",
    "gettid", "set_tid_address",
    "getrlimit", "prlimit64", "setrlimit",

    # Signals
    "rt_sigaction", "rt_sigprocmask", "rt_sigreturn",
    "sigaltstack", "kill", "tgkill",

    # Time
    "clock_gettime", "clock_getres", "clock_nanosleep",
    "gettimeofday", "nanosleep", "timer_create",
    "timer_settime", "timer_gettime", "timer_delete",

    # Memory
    "madvise", "mincore", "mremap",

    # Futex/threading
    "futex", "set_robust_list", "get_robust_list",
    "clone", "clone3", "vfork",

    # Epoll/select
    "epoll_create", "epoll_create1", "epoll_ctl", "epoll_wait", "epoll_pwait",
    "select", "pselect6", "poll", "ppoll",

    # IPC (limited)
    "pipe2", "eventfd", "eventfd2",

    # Misc
    "uname", "sysinfo", "prctl", "arch_prctl",
    "getrandom", "getcwd", "chdir", "fchdir",
]

# Syscalls for network access (isolated mode)
NETWORK_SYSCALLS = [
    "socket", "connect", "accept", "accept4",
    "bind", "listen", "getsockname", "getpeername",
    "sendto", "recvfrom", "sendmsg", "recvmsg",
    "shutdown", "setsockopt", "getsockopt",
    "sendmmsg", "recvmmsg",
]

# Dangerous syscalls (never allowed for agents)
DANGEROUS_SYSCALLS = [
    # Kernel modules
    "init_module", "finit_module", "delete_module",

    # System control
    "reboot", "kexec_load", "kexec_file_load",
    "swapon", "swapoff",

    # Raw device access
    "ioctl",  # Very dangerous, should be filtered carefully

    # Mount operations
    "mount", "umount", "umount2", "pivot_root",

    # Namespaces (handled by bwrap)
    "unshare", "setns",

    # Keyring (credential theft)
    "keyctl", "add_key", "request_key",

    # Process debugging
    "ptrace", "process_vm_readv", "process_vm_writev",

    # BPF (could escape sandbox)
    "bpf",

    # Performance monitoring
    "perf_event_open",

    # Personality (could affect child processes)
    "personality",
]


def generate_seccomp_filter(
    trust_level: int,
    allow_network: bool = True,
) -> SeccompProfile:
    """
    Generate a seccomp filter based on trust level.

    Args:
        trust_level: Agent trust level (0-4)
        allow_network: Whether to allow network syscalls

    Returns:
        SeccompProfile with appropriate restrictions
    """
    syscalls = []

    # Always allow safe syscalls
    for name in SAFE_SYSCALLS:
        syscalls.append(SyscallRule(name=name, action=SeccompAction.ALLOW))

    # Network syscalls based on flag
    if allow_network:
        for name in NETWORK_SYSCALLS:
            syscalls.append(SyscallRule(name=name, action=SeccompAction.ALLOW))

    # Higher trust levels get more syscalls
    if trust_level >= 2:
        # Standard trust: allow exec for tools
        syscalls.append(SyscallRule(name="execve", action=SeccompAction.ALLOW))
        syscalls.append(SyscallRule(name="execveat", action=SeccompAction.ALLOW))

    if trust_level >= 3:
        # Elevated trust: allow more filesystem ops
        for name in ["mkdir", "mkdirat", "rmdir", "unlink", "unlinkat",
                     "rename", "renameat", "renameat2", "link", "linkat",
                     "symlink", "symlinkat", "chmod", "chown", "fchown"]:
            syscalls.append(SyscallRule(name=name, action=SeccompAction.ALLOW))

    # Create profile
    profile = SeccompProfile(
        name=f"agent-trust-{trust_level}",
        default_action=SeccompAction.ERRNO,
        syscalls=syscalls,
    )

    return profile


# Pre-defined profiles
PROFILES = {
    "default": generate_seccomp_filter(trust_level=2, allow_network=True),
    "untrusted": generate_seccomp_filter(trust_level=0, allow_network=False),
    "elevated": generate_seccomp_filter(trust_level=3, allow_network=True),
    "network-isolated": generate_seccomp_filter(trust_level=2, allow_network=False),
}


def get_profile(name: str) -> Optional[SeccompProfile]:
    """Get a pre-defined seccomp profile by name."""
    return PROFILES.get(name)
