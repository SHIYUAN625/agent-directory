"""Configuration for the provisioning service."""

from dataclasses import dataclass, field
from typing import Dict, List, Optional
import os


@dataclass
class LDAPConfig:
    """LDAP connection configuration."""
    uri: str = "ldaps://localhost"
    base_dn: str = "DC=autonomy,DC=local"
    bind_dn: str = ""
    bind_pw: str = ""
    use_tls: bool = False
    ca_cert: Optional[str] = None

    # Container DNs
    agents_container: str = "CN=Agents,CN=System"
    tools_container: str = "CN=Agent Tools,CN=System"
    policies_container: str = "CN=Agent Policies,CN=System"

    def agents_dn(self) -> str:
        return f"{self.agents_container},{self.base_dn}"

    def tools_dn(self) -> str:
        return f"{self.tools_container},{self.base_dn}"

    def policies_dn(self) -> str:
        return f"{self.policies_container},{self.base_dn}"


@dataclass
class KerberosConfig:
    """Kerberos configuration."""
    realm: str = "AUTONOMY.LOCAL"
    kdc: str = "kdc.autonomy.local"
    admin_server: str = "kdc.autonomy.local"
    dc_ip: str = ""
    dc_hostname: str = "kdc.autonomy.local"


@dataclass
class SMBConfig:
    """SMB/SYSVOL configuration."""
    server: str = "files.autonomy.local"
    share: str = "SYSVOL"
    domain: str = "autonomy.local"
    policies_path: str = "autonomy.local/AgentPolicies"
    mount_point: str = "/mnt/sysvol"


@dataclass
class PoolConfig:
    """Identity pool configuration."""
    # Pool sizing
    headroom_percent: float = 0.20  # 20% headroom
    min_pool_size: int = 5
    max_pool_size: int = 100

    # Pool behavior
    reap_idle_after_seconds: int = 86400  # 24 hours
    check_interval_seconds: int = 60

    # Pool per agent type
    default_pools: dict = field(default_factory=lambda: {
        "worker": {"min": 10, "max": 50},
        "coordinator": {"min": 3, "max": 10},
        "analyst": {"min": 5, "max": 20},
    })


@dataclass
class DatabaseConfig:
    """Database configuration for lease/reservation state."""
    uri: str = "sqlite:////tmp/provisioner/leases.db"
    pool_size: int = 5
    max_overflow: int = 10
    lease_ttl_seconds: int = 900


@dataclass
class NATSConfig:
    """NATS configuration.

    auth_mode controls how agent credentials are injected:
    - password: provisioner returns static role passwords (default, current deployment path)
    - jwt: provisioner returns user_jwt + nkey_seed (optional)
    """
    servers: List[str] = field(default_factory=lambda: ["nats://localhost:4222"])
    auth_mode: str = "password"
    user: str = "provisioner"
    password: str = ""
    connect_timeout: int = 10
    agent_passwords: Dict[str, str] = field(default_factory=dict)
    agent_user_jwts: Dict[str, str] = field(default_factory=dict)
    agent_nkey_seeds: Dict[str, str] = field(default_factory=dict)


_NATS_AGENT_TYPES = ("worker", "coordinator", "analyst", "code-reviewer")


def _load_nats_agent_passwords() -> Dict[str, str]:
    """Load per-agent-type NATS passwords from environment.

    Reads NATS_<TYPE>_PASSWORD for each known agent type.
    Example: NATS_WORKER_PASSWORD, NATS_COORDINATOR_PASSWORD.
    """
    passwords: Dict[str, str] = {}
    for agent_type in _NATS_AGENT_TYPES:
        env_key = f"NATS_{agent_type.upper().replace('-', '_')}_PASSWORD"
        val = os.getenv(env_key, "")
        if val:
            passwords[agent_type] = val
    return passwords


def _load_nats_agent_user_jwts() -> Dict[str, str]:
    """Load per-agent-type NATS JWTs from environment."""
    jwts: Dict[str, str] = {}
    for agent_type in _NATS_AGENT_TYPES:
        env_key = f"NATS_{agent_type.upper().replace('-', '_')}_USER_JWT"
        val = os.getenv(env_key, "")
        if val:
            jwts[agent_type] = val
    return jwts


def _load_nats_agent_nkey_seeds() -> Dict[str, str]:
    """Load per-agent-type NATS nkey seeds from environment."""
    seeds: Dict[str, str] = {}
    for agent_type in _NATS_AGENT_TYPES:
        env_key = f"NATS_{agent_type.upper().replace('-', '_')}_NKEY_SEED"
        val = os.getenv(env_key, "")
        if val:
            seeds[agent_type] = val
    return seeds


@dataclass
class ProvisionerConfig:
    """Main provisioner configuration."""
    ldap: LDAPConfig = field(default_factory=LDAPConfig)
    kerberos: KerberosConfig = field(default_factory=KerberosConfig)
    smb: SMBConfig = field(default_factory=SMBConfig)
    pool: PoolConfig = field(default_factory=PoolConfig)
    database: DatabaseConfig = field(default_factory=DatabaseConfig)
    nats: NATSConfig = field(default_factory=NATSConfig)

    # Service configuration
    listen_address: str = "0.0.0.0"
    listen_port: int = 8080
    metrics_port: int = 9090
    api_key: str = ""
    credential_store_dir: str = "/var/lib/provisioner/credentials"
    credential_ttl_seconds: int = 300

    @classmethod
    def from_env(cls) -> "ProvisionerConfig":
        """Load configuration from environment variables."""
        return cls(
            api_key=os.getenv("PROVISIONER_API_KEY", ""),
            credential_store_dir=os.getenv(
                "CREDENTIAL_STORE_DIR", "/var/lib/provisioner/credentials"
            ),
            credential_ttl_seconds=int(os.getenv("CREDENTIAL_TTL_SECONDS", "300")),
            ldap=LDAPConfig(
                uri=os.getenv("LDAP_URI", "ldaps://localhost"),
                base_dn=os.getenv("LDAP_BASE_DN", "DC=autonomy,DC=local"),
                bind_dn=os.getenv("LDAP_BIND_DN", ""),
                bind_pw=os.getenv("LDAP_BIND_PW", ""),
                use_tls=os.getenv("LDAP_USE_TLS", "").lower() == "true",
                ca_cert=os.getenv("LDAP_CA_CERT") or None,
            ),
            kerberos=KerberosConfig(
                realm=os.getenv("KRB5_REALM", "AUTONOMY.LOCAL"),
                kdc=os.getenv("KRB5_KDC", "kdc.autonomy.local"),
                dc_ip=os.getenv("KRB5_DC_IP", ""),
                dc_hostname=os.getenv("KRB5_DC_HOSTNAME", os.getenv("KRB5_KDC", "kdc.autonomy.local")),
            ),
            smb=SMBConfig(
                server=os.getenv("SMB_SERVER", "files.autonomy.local"),
                domain=os.getenv("SMB_DOMAIN", "autonomy.local"),
            ),
            database=DatabaseConfig(
                uri=os.getenv("DATABASE_URI", "sqlite:////tmp/provisioner/leases.db"),
                lease_ttl_seconds=int(os.getenv("LEASE_TTL_SECONDS", "900")),
            ),
            nats=NATSConfig(
                servers=os.getenv("NATS_SERVERS", "nats://localhost:4222").split(","),
                auth_mode=os.getenv("NATS_AUTH_MODE", "password").lower(),
                user=os.getenv("NATS_USER", "provisioner"),
                password=os.getenv("NATS_PASSWORD", ""),
                agent_passwords=_load_nats_agent_passwords(),
                agent_user_jwts=_load_nats_agent_user_jwts(),
                agent_nkey_seeds=_load_nats_agent_nkey_seeds(),
            ),
        )
