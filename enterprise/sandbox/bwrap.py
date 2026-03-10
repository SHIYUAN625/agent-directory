"""
Bubblewrap (bwrap) sandbox profile for agents.

bwrap provides lightweight container-like sandboxing using Linux namespaces.
This is used inside Firecracker VMs for defense-in-depth isolation.

Key isolation features:
- Mount namespace: Controlled filesystem view
- Network namespace: Isolated or no network
- PID namespace: Can't see/signal other processes
- User namespace: Unprivileged inside sandbox
- No new privileges: Can't escalate via setuid
"""

from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional
import json
import shlex


class NetworkMode(str, Enum):
    """Network namespace mode."""
    NONE = "none"           # No network access
    ISOLATED = "isolated"   # Separate namespace, no routes
    HOST = "host"           # Share host network (use with caution)
    HOST_FILTERED = "host_filtered"  # Host network with iptables filtering


@dataclass
class Mount:
    """A filesystem mount for the sandbox."""
    source: str              # Source path on host
    dest: str                # Destination path in sandbox
    mode: str = "ro"         # ro, rw, or dev
    type: str = "bind"       # bind, tmpfs, proc, etc.
    options: List[str] = field(default_factory=list)  # Mount options

    def to_bwrap_args(self) -> List[str]:
        """Convert to bwrap command-line arguments."""
        args = []

        if self.type == "tmpfs":
            args.extend(["--tmpfs", self.dest])
        elif self.type == "proc":
            args.extend(["--proc", self.dest])
        elif self.type == "dev":
            args.extend(["--dev", self.dest])
        elif self.type == "bind":
            if self.mode == "ro":
                args.extend(["--ro-bind", self.source, self.dest])
            elif self.mode == "rw":
                args.extend(["--bind", self.source, self.dest])
            elif self.mode == "dev":
                args.extend(["--dev-bind", self.source, self.dest])

        return args


@dataclass
class SandboxConfig:
    """Configuration for agent sandbox from policy."""
    # Network
    network_mode: NetworkMode = NetworkMode.ISOLATED

    # Filesystem
    read_only_root: bool = True
    writable_home: bool = True
    writable_tmp: bool = True
    tmp_size_mb: int = 256
    home_path: str = "/home/agent"

    # Mounts
    extra_ro_mounts: List[str] = field(default_factory=list)  # host:container
    extra_rw_mounts: List[str] = field(default_factory=list)

    # Process
    new_session: bool = True
    die_with_parent: bool = True
    no_new_privileges: bool = True

    # User namespace
    uid: int = 1000
    gid: int = 1000

    # Resource limits (via rlimit)
    max_memory_mb: int = 4096
    max_files: int = 1024
    max_processes: int = 256

    # Seccomp
    seccomp_profile: str = "default"

    @classmethod
    def from_policy(cls, policy: Dict[str, Any]) -> "SandboxConfig":
        """Create config from merged policy."""
        sandbox = policy.get("sandbox", {})
        compute = policy.get("compute", {})

        network_str = sandbox.get("network_namespace", "isolated")
        network_mode = NetworkMode(network_str) if network_str in [m.value for m in NetworkMode] else NetworkMode.ISOLATED

        return cls(
            network_mode=network_mode,
            read_only_root=sandbox.get("read_only_root", True),
            no_new_privileges=sandbox.get("no_new_privileges", True),
            seccomp_profile=sandbox.get("seccomp_profile", "default"),
            max_memory_mb=compute.get("max_memory_mb", 4096),
        )


@dataclass
class BwrapProfile:
    """
    Complete bwrap sandbox profile for an agent.

    This defines the full sandbox configuration including:
    - Filesystem mounts and visibility
    - Network isolation mode
    - User/group mapping
    - Resource limits
    - Seccomp filter
    """
    config: SandboxConfig
    agent_home: str = "/home/agent"
    credential_broker_socket: str = "/run/broker.sock"

    def get_mounts(self) -> List[Mount]:
        """Get all mounts for the sandbox."""
        mounts = []

        # Base system mounts (read-only)
        if self.config.read_only_root:
            # Bind mount essential directories read-only
            for path in ["/usr", "/lib", "/lib64", "/bin", "/sbin", "/etc"]:
                if Path(path).exists():
                    mounts.append(Mount(source=path, dest=path, mode="ro"))

        # /proc (filtered)
        mounts.append(Mount(source="", dest="/proc", type="proc"))

        # /dev (minimal)
        mounts.append(Mount(source="", dest="/dev", type="dev"))

        # /tmp (writable tmpfs)
        if self.config.writable_tmp:
            mounts.append(Mount(
                source="",
                dest="/tmp",
                type="tmpfs",
                options=[f"size={self.config.tmp_size_mb}M"],
            ))

        # Agent home directory (writable)
        if self.config.writable_home:
            mounts.append(Mount(
                source=self.agent_home,
                dest="/home/agent",
                mode="rw",
            ))

        # Credential broker socket
        mounts.append(Mount(
            source=self.credential_broker_socket,
            dest="/run/broker.sock",
            mode="ro",  # Socket is read-only from sandbox perspective
        ))

        # Extra mounts from config
        for mount_spec in self.config.extra_ro_mounts:
            if ":" in mount_spec:
                src, dst = mount_spec.split(":", 1)
                mounts.append(Mount(source=src, dest=dst, mode="ro"))

        for mount_spec in self.config.extra_rw_mounts:
            if ":" in mount_spec:
                src, dst = mount_spec.split(":", 1)
                mounts.append(Mount(source=src, dest=dst, mode="rw"))

        return mounts

    def to_bwrap_args(self) -> List[str]:
        """Generate bwrap command-line arguments."""
        args = []

        # Unshare namespaces
        args.append("--unshare-all")

        # Keep or create new network namespace
        if self.config.network_mode == NetworkMode.HOST:
            args.append("--share-net")
        # For other modes, --unshare-all already creates new net namespace

        # User mapping
        args.extend([
            "--uid", str(self.config.uid),
            "--gid", str(self.config.gid),
        ])

        # Process isolation
        if self.config.new_session:
            args.append("--new-session")

        if self.config.die_with_parent:
            args.append("--die-with-parent")

        # Security
        if self.config.no_new_privileges:
            args.append("--cap-drop", "ALL")

        # Hostname
        args.extend(["--hostname", "agent"])

        # Mounts
        for mount in self.get_mounts():
            args.extend(mount.to_bwrap_args())

        # Working directory
        args.extend(["--chdir", "/home/agent"])

        # Environment cleanup
        args.append("--clearenv")

        # Set essential environment variables
        env_vars = {
            "HOME": "/home/agent",
            "USER": "agent",
            "PATH": "/usr/local/bin:/usr/bin:/bin",
            "LANG": "C.UTF-8",
            "BROKER_SOCKET": "/run/broker.sock",
        }
        for key, value in env_vars.items():
            args.extend(["--setenv", key, value])

        return args

    def to_command(self, agent_command: List[str]) -> List[str]:
        """Generate full bwrap command to run agent."""
        cmd = ["bwrap"]
        cmd.extend(self.to_bwrap_args())

        # Add seccomp filter if available
        if self.config.seccomp_profile != "none":
            seccomp_path = f"/etc/agent/seccomp/{self.config.seccomp_profile}.bpf"
            if Path(seccomp_path).exists():
                cmd.extend(["--seccomp", "3", f"3<{seccomp_path}"])

        # Separator and agent command
        cmd.append("--")
        cmd.extend(agent_command)

        return cmd

    def to_dict(self) -> Dict[str, Any]:
        """Serialize profile to dictionary."""
        return {
            "config": {
                "network_mode": self.config.network_mode.value,
                "read_only_root": self.config.read_only_root,
                "writable_home": self.config.writable_home,
                "writable_tmp": self.config.writable_tmp,
                "tmp_size_mb": self.config.tmp_size_mb,
                "no_new_privileges": self.config.no_new_privileges,
                "uid": self.config.uid,
                "gid": self.config.gid,
                "max_memory_mb": self.config.max_memory_mb,
                "seccomp_profile": self.config.seccomp_profile,
            },
            "agent_home": self.agent_home,
            "credential_broker_socket": self.credential_broker_socket,
            "mounts": [
                {"source": m.source, "dest": m.dest, "mode": m.mode, "type": m.type}
                for m in self.get_mounts()
            ],
        }


def generate_bwrap_command(
    policy: Dict[str, Any],
    agent_home: str,
    broker_socket: str,
    agent_command: List[str],
) -> str:
    """
    Generate a complete bwrap command string.

    Args:
        policy: Merged policy dictionary
        agent_home: Path to agent's home directory
        broker_socket: Path to credential broker socket
        agent_command: Command to run inside sandbox

    Returns:
        Shell command string
    """
    config = SandboxConfig.from_policy(policy)
    profile = BwrapProfile(
        config=config,
        agent_home=agent_home,
        credential_broker_socket=broker_socket,
    )

    cmd = profile.to_command(agent_command)
    return shlex.join(cmd)


# Pre-defined profiles for common agent types
PROFILES = {
    "worker": SandboxConfig(
        network_mode=NetworkMode.ISOLATED,
        read_only_root=True,
        max_memory_mb=2048,
    ),
    "coordinator": SandboxConfig(
        network_mode=NetworkMode.ISOLATED,
        read_only_root=True,
        max_memory_mb=8192,
        max_processes=512,
    ),
    "untrusted": SandboxConfig(
        network_mode=NetworkMode.NONE,
        read_only_root=True,
        writable_home=False,
        max_memory_mb=512,
        max_processes=32,
    ),
}


def get_profile(agent_type: str, trust_level: int) -> SandboxConfig:
    """Get appropriate sandbox profile based on agent type and trust."""
    if trust_level == 0:
        return PROFILES["untrusted"]
    elif agent_type in ["coordinator", "orchestrator"]:
        return PROFILES["coordinator"]
    else:
        return PROFILES["worker"]
