"""Policy loading and merging for agents."""

import json
import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


@dataclass
class PolicyDefinition:
    """A single policy definition from AD."""
    name: str
    policy_type: str
    priority: int
    path: str
    enabled: bool
    version: str
    applies_to_types: List[str] = field(default_factory=list)
    applies_to_trust_levels: List[int] = field(default_factory=list)
    content: Dict[str, Any] = field(default_factory=dict)


@dataclass
class MergedPolicy:
    """The effective policy for an agent after merging."""
    # Tools configuration
    allowed_tools: List[str] = field(default_factory=list)
    denied_tools: List[str] = field(default_factory=list)
    require_audit_for_risk_above: int = 3

    # Credentials
    allow_keytab_access: bool = False
    credential_broker_required: bool = True
    max_credential_lifetime_seconds: int = 3600
    allow_credential_delegation: bool = False

    # Sandbox
    bwrap_required: bool = True
    seccomp_profile: str = "default"
    network_namespace: str = "isolated"
    user_namespace: bool = True
    no_new_privileges: bool = True
    read_only_root: bool = False

    # Compute
    max_memory_mb: int = 4096
    max_cpu_percent: int = 100
    max_runtime_seconds: int = 3600
    max_disk_mb: int = 1024

    # LLM
    daily_token_limit: int = 1000000
    max_context_tokens: int = 200000
    max_output_tokens: int = 16000
    llm_rate_limit: int = 60

    # Network
    allow_internet: bool = False
    allow_intranet: bool = True
    egress_whitelist: List[str] = field(default_factory=list)
    egress_blacklist: List[str] = field(default_factory=list)

    # NATS
    nats_server: str = ""
    nats_allowed_subjects: List[str] = field(default_factory=list)
    nats_denied_subjects: List[str] = field(default_factory=list)

    # Agents
    max_spawned_agents: int = 0
    max_delegated_tasks: int = 10
    delegation_depth_limit: int = 2
    can_supervise_workers: bool = False

    # Execution
    max_iterations: int = 100
    max_consecutive_errors: int = 5
    checkpoint_interval_steps: int = 10
    allow_self_modification: bool = False

    # Escalation
    escalate_on_blocked: bool = True
    escalate_on_error_threshold: int = 3
    human_escalation_enabled: bool = True

    # Audit
    log_all_tool_calls: bool = True
    log_network_requests: bool = True
    log_file_access: bool = True
    anomaly_detection: bool = True

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization."""
        return {
            "tools": {
                "allow": self.allowed_tools,
                "deny": self.denied_tools,
                "require_audit_for_risk_above": self.require_audit_for_risk_above,
            },
            "credentials": {
                "allow_keytab_access": self.allow_keytab_access,
                "credential_broker_required": self.credential_broker_required,
                "max_credential_lifetime_seconds": self.max_credential_lifetime_seconds,
                "allow_credential_delegation": self.allow_credential_delegation,
            },
            "sandbox": {
                "bwrap_required": self.bwrap_required,
                "seccomp_profile": self.seccomp_profile,
                "network_namespace": self.network_namespace,
                "user_namespace": self.user_namespace,
                "no_new_privileges": self.no_new_privileges,
                "read_only_root": self.read_only_root,
            },
            "compute": {
                "max_memory_mb": self.max_memory_mb,
                "max_cpu_percent": self.max_cpu_percent,
                "max_runtime_seconds": self.max_runtime_seconds,
                "max_disk_mb": self.max_disk_mb,
            },
            "llm": {
                "daily_token_limit": self.daily_token_limit,
                "max_context_tokens": self.max_context_tokens,
                "max_output_tokens": self.max_output_tokens,
                "rate_limit": self.llm_rate_limit,
            },
            "network": {
                "allow_internet": self.allow_internet,
                "allow_intranet": self.allow_intranet,
                "egress_whitelist": self.egress_whitelist,
                "egress_blacklist": self.egress_blacklist,
            },
            "nats": {
                "server": self.nats_server,
                "allowed_subjects": self.nats_allowed_subjects,
                "denied_subjects": self.nats_denied_subjects,
            },
            "agents": {
                "max_spawned_agents": self.max_spawned_agents,
                "max_delegated_tasks": self.max_delegated_tasks,
                "delegation_depth_limit": self.delegation_depth_limit,
                "can_supervise_workers": self.can_supervise_workers,
            },
            "execution": {
                "max_iterations": self.max_iterations,
                "max_consecutive_errors": self.max_consecutive_errors,
                "checkpoint_interval_steps": self.checkpoint_interval_steps,
                "allow_self_modification": self.allow_self_modification,
            },
            "escalation": {
                "escalate_on_blocked": self.escalate_on_blocked,
                "escalate_on_error_threshold": self.escalate_on_error_threshold,
                "human_escalation_enabled": self.human_escalation_enabled,
            },
            "audit": {
                "log_all_tool_calls": self.log_all_tool_calls,
                "log_network_requests": self.log_network_requests,
                "log_file_access": self.log_file_access,
                "anomaly_detection": self.anomaly_detection,
            },
        }


class PolicyLoader:
    """Loads and merges policies from AD and SYSVOL."""

    def __init__(
        self,
        ldap_client,
        smb_config,
    ):
        self.ldap = ldap_client
        self.smb_config = smb_config

        # Cache of loaded policy content
        self._policy_cache: Dict[str, PolicyDefinition] = {}

    async def load_policies_for_agent(
        self,
        agent_dn: str,
        agent_type: str,
        trust_level: int,
        policy_dns: List[str],
    ) -> MergedPolicy:
        """
        Load and merge all applicable policies for an agent.

        Policy precedence (lower priority applied first, higher overrides):
        1. Base policies (priority 0-99)
        2. Type policies (priority 100-199)
        3. Trust level policies (priority 150)
        4. Agent-specific policies (priority 200+)
        """
        # Get all policies linked to agent
        policies = []

        for policy_dn in policy_dns:
            policy = await self._load_policy(policy_dn)
            if policy and policy.enabled:
                # Check if policy applies to this agent
                if self._policy_applies(policy, agent_type, trust_level):
                    policies.append(policy)

        # Sort by priority (lower first)
        policies.sort(key=lambda p: p.priority)

        # Merge policies
        merged = MergedPolicy()

        for policy in policies:
            self._apply_policy(merged, policy)

        logger.info(
            f"Merged {len(policies)} policies for {agent_dn}: "
            f"{[p.name for p in policies]}"
        )

        return merged

    async def _load_policy(self, policy_dn: str) -> Optional[PolicyDefinition]:
        """Load a policy from AD and its content from SYSVOL."""
        # Check cache first
        if policy_dn in self._policy_cache:
            return self._policy_cache[policy_dn]

        # Fetch policy metadata from LDAP
        policy_attrs = await self.ldap.get_policy(policy_dn)
        if not policy_attrs:
            logger.warning(f"Policy not found: {policy_dn}")
            return None

        policy = PolicyDefinition(
            name=policy_attrs.get("x-policy-Identifier", ""),
            policy_type=policy_attrs.get("x-policy-Type", ""),
            priority=int(policy_attrs.get("x-policy-Priority", 0)),
            path=policy_attrs.get("x-policy-Path", ""),
            enabled=policy_attrs.get("x-policy-Enabled", "TRUE") == "TRUE",
            version=policy_attrs.get("x-policy-Version", ""),
            applies_to_types=policy_attrs.get("x-policy-AppliesToTypes", []),
            applies_to_trust_levels=[
                int(l) for l in policy_attrs.get("x-policy-AppliesToTrustLevels", [])
            ],
        )

        # Load content from SYSVOL
        if policy.path:
            content = await self._load_policy_content(policy.path)
            if content:
                policy.content = content

        self._policy_cache[policy_dn] = policy
        return policy

    async def _load_policy_content(self, path: str) -> Optional[Dict[str, Any]]:
        """Load policy JSON from SYSVOL."""
        # Build full path
        full_path = Path(self.smb_config.mount_point) / path

        try:
            if full_path.exists():
                with open(full_path) as f:
                    return json.load(f)
            else:
                logger.warning(f"Policy file not found: {full_path}")
                return None
        except json.JSONDecodeError as e:
            logger.error(f"Invalid policy JSON at {full_path}: {e}")
            return None
        except Exception as e:
            logger.error(f"Error loading policy from {full_path}: {e}")
            return None

    def _policy_applies(
        self,
        policy: PolicyDefinition,
        agent_type: str,
        trust_level: int,
    ) -> bool:
        """Check if a policy applies to the given agent."""
        # Check type filter
        if policy.applies_to_types:
            if agent_type not in policy.applies_to_types:
                return False

        # Check trust level filter
        if policy.applies_to_trust_levels:
            if trust_level not in policy.applies_to_trust_levels:
                return False

        return True

    def _apply_policy(self, merged: MergedPolicy, policy: PolicyDefinition):
        """Apply a policy's settings to the merged policy."""
        content = policy.content.get("settings", {})

        # Tools
        if "tools" in content:
            tools = content["tools"]
            if "allow" in tools:
                merged.allowed_tools.extend(tools["allow"])
            if "deny" in tools:
                merged.denied_tools.extend(tools["deny"])
            if "require_audit_for_risk_above" in tools:
                merged.require_audit_for_risk_above = tools["require_audit_for_risk_above"]

        # Credentials
        if "credentials" in content:
            creds = content["credentials"]
            for key in ["allow_keytab_access", "credential_broker_required",
                        "max_credential_lifetime_seconds", "allow_credential_delegation"]:
                if key in creds:
                    setattr(merged, key, creds[key])

        # Sandbox
        if "sandbox" in content:
            sandbox = content["sandbox"]
            for key in ["bwrap_required", "seccomp_profile", "network_namespace",
                        "user_namespace", "no_new_privileges", "read_only_root"]:
                if key in sandbox:
                    setattr(merged, key, sandbox[key])

        # Compute
        if "compute" in content:
            compute = content["compute"]
            for key in ["max_memory_mb", "max_cpu_percent", "max_runtime_seconds", "max_disk_mb"]:
                if key in compute:
                    setattr(merged, key, compute[key])

        # LLM
        if "llm" in content:
            llm = content["llm"]
            if "daily_token_limit" in llm:
                merged.daily_token_limit = llm["daily_token_limit"]
            if "max_context_tokens" in llm:
                merged.max_context_tokens = llm["max_context_tokens"]
            if "max_output_tokens" in llm:
                merged.max_output_tokens = llm["max_output_tokens"]
            if "rate_limit_requests_per_minute" in llm:
                merged.llm_rate_limit = llm["rate_limit_requests_per_minute"]

        # Network
        if "network" in content:
            network = content["network"]
            for key in ["allow_internet", "allow_intranet"]:
                if key in network:
                    setattr(merged, key, network[key])
            if "egress" in content:
                egress = content["egress"]
                if "whitelist" in egress:
                    merged.egress_whitelist.extend(egress["whitelist"])
                if "blacklist" in egress:
                    merged.egress_blacklist.extend(egress["blacklist"])

        # NATS
        if "nats" in content:
            nats = content["nats"]
            if "server" in nats:
                merged.nats_server = nats["server"]
            if "allowed_subject_prefixes" in nats:
                merged.nats_allowed_subjects.extend(nats["allowed_subject_prefixes"])
            if "denied_subject_prefixes" in nats:
                merged.nats_denied_subjects.extend(nats["denied_subject_prefixes"])

        # Agents
        if "agents" in content:
            agents = content["agents"]
            for key in ["max_spawned_agents", "max_delegated_tasks",
                        "delegation_depth_limit", "can_supervise_workers"]:
                if key in agents:
                    setattr(merged, key, agents[key])

        # Execution
        if "execution" in content:
            execution = content["execution"]
            for key in ["max_iterations", "max_consecutive_errors",
                        "checkpoint_interval_steps", "allow_self_modification"]:
                if key in execution:
                    setattr(merged, key, execution[key])

        # Escalation
        if "escalation" in content:
            escalation = content["escalation"]
            for key in ["escalate_on_blocked", "escalate_on_error_threshold",
                        "human_escalation_enabled"]:
                if key in escalation:
                    setattr(merged, key, escalation[key])

        # Audit
        if "audit" in content:
            audit = content["audit"]
            for key in ["log_all_tool_calls", "log_network_requests",
                        "log_file_access", "anomaly_detection"]:
                if key in audit:
                    setattr(merged, key, audit[key])

    def invalidate_cache(self, policy_dn: Optional[str] = None):
        """Invalidate policy cache."""
        if policy_dn:
            self._policy_cache.pop(policy_dn, None)
        else:
            self._policy_cache.clear()
