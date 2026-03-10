"""Agent identity data structures."""

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Optional, List, Dict, Any
import logging

logger = logging.getLogger(__name__)


class IdentityStatus(str, Enum):
    """Status of an identity in the pool."""
    AVAILABLE = "available"      # Ready to be assigned
    IN_USE = "in_use"           # Currently assigned to a VM
    PROVISIONING = "provisioning"  # Being set up
    REAPING = "reaping"         # Being cleaned up
    ERROR = "error"             # Failed state


@dataclass
class SandboxIdentity:
    """Represents a sandbox execution environment in AD."""
    name: str                    # sAMAccountName without $
    dn: str                      # Distinguished name
    sid: str                     # objectSid
    principal: str               # Kerberos principal (name$@REALM)
    endpoint: str = ""
    security_profile: str = "bwrap"
    resource_policy: str = ""
    network_policy: str = ""
    status: str = "standby"

    def to_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "dn": self.dn,
            "sid": self.sid,
            "principal": self.principal,
            "endpoint": self.endpoint,
            "security_profile": self.security_profile,
            "resource_policy": self.resource_policy,
            "network_policy": self.network_policy,
            "status": self.status,
        }


@dataclass
class AgentIdentity:
    """Represents an agent's identity in AD (inherits from user, not computer)."""
    # Core identity
    name: str                    # sAMAccountName (no $ suffix for user objects)
    dn: str                      # Distinguished name
    sid: str                     # objectSid
    principal: str               # Kerberos principal (name@REALM, no $ suffix)

    # Agent configuration from AD
    agent_type: str = "autonomous"
    trust_level: int = 2
    owner: str = ""
    model: str = ""
    capabilities: List[str] = field(default_factory=list)
    authorized_tools: List[str] = field(default_factory=list)
    denied_tools: List[str] = field(default_factory=list)
    nats_subjects: List[str] = field(default_factory=list)
    escalation_path: str = ""
    policies: List[str] = field(default_factory=list)
    audit_level: int = 1
    llm_access: List[str] = field(default_factory=list)
    llm_quota: Dict[str, Any] = field(default_factory=dict)
    mission: str = ""

    # Pool management
    status: IdentityStatus = IdentityStatus.AVAILABLE
    assigned_vm_id: Optional[str] = None
    last_used: Optional[datetime] = None
    created_at: datetime = field(default_factory=datetime.utcnow)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization."""
        return {
            "name": self.name,
            "dn": self.dn,
            "sid": self.sid,
            "principal": self.principal,
            "agent_type": self.agent_type,
            "trust_level": self.trust_level,
            "owner": self.owner,
            "model": self.model,
            "capabilities": self.capabilities,
            "authorized_tools": self.authorized_tools,
            "denied_tools": self.denied_tools,
            "nats_subjects": self.nats_subjects,
            "escalation_path": self.escalation_path,
            "policies": self.policies,
            "audit_level": self.audit_level,
            "llm_access": self.llm_access,
            "llm_quota": self.llm_quota,
            "mission": self.mission,
            "status": self.status.value,
            "assigned_vm_id": self.assigned_vm_id,
            "last_used": self.last_used.isoformat() if self.last_used else None,
            "created_at": self.created_at.isoformat(),
        }


