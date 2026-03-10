#!/usr/bin/env python3
"""
Agent Directory Management Tool for Samba4

This script provides management commands for autonomous agents in Samba4 AD.
It replaces the PowerShell cmdlets from the Windows AD version.

Usage:
    ./agent-manager.py agent create <name> [options]
    ./agent-manager.py agent get <name>
    ./agent-manager.py agent list [--type TYPE] [--trust-level LEVEL]
    ./agent-manager.py agent set <name> [options]
    ./agent-manager.py agent delete <name>
    ./agent-manager.py agent keytab <name> --output <path>

    ./agent-manager.py tool create <identifier> [options]
    ./agent-manager.py tool list [--category CATEGORY]
    ./agent-manager.py tool grant <agent> <tool>
    ./agent-manager.py tool revoke <agent> <tool>

    ./agent-manager.py policy list [--type TYPE] [--enabled]
    ./agent-manager.py policy link <agent> <policy>
    ./agent-manager.py policy unlink <agent> <policy>
    ./agent-manager.py policy effective <agent>

    ./agent-manager.py gpo list [--enabled]
    ./agent-manager.py gpo link <agent> <gpo>
    ./agent-manager.py gpo unlink <agent> <gpo>
    ./agent-manager.py gpo effective <agent>

Requires:
    - python-ldap
    - samba (for samba-tool commands)
"""

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass, field
from typing import Optional, List, Dict, Any
import os

# Try to import ldap, provide helpful error if not available
try:
    import ldap
    import ldap.modlist
    LDAP_AVAILABLE = True
except ImportError:
    LDAP_AVAILABLE = False


@dataclass
class Config:
    """Configuration for AD connection."""
    domain: str = "autonomy.local"
    ldap_uri: str = "ldaps://localhost"
    base_dn: str = ""
    bind_dn: str = ""
    bind_pw: str = ""

    def __post_init__(self):
        if not self.base_dn:
            self.base_dn = ",".join(f"DC={p}" for p in self.domain.split("."))
        if not self.bind_dn:
            self.bind_dn = f"CN=Administrator,CN=Users,{self.base_dn}"


@dataclass
class Agent:
    """Represents an AI agent in AD."""
    name: str
    dn: str = ""
    agent_type: str = "autonomous"
    trust_level: int = 2
    owner: str = ""
    parent: str = ""
    model: str = ""
    capabilities: List[str] = field(default_factory=list)
    authorized_tools: List[str] = field(default_factory=list)
    denied_tools: List[str] = field(default_factory=list)
    nats_subjects: List[str] = field(default_factory=list)
    escalation_path: str = ""
    policies: List[str] = field(default_factory=list)
    audit_level: int = 1
    llm_access: List[str] = field(default_factory=list)
    llm_quota: str = ""
    mission: str = ""
    runtime_endpoint: str = ""
    state_endpoint: str = ""

    def to_ldap_attrs(self) -> Dict[str, List[bytes]]:
        """Convert to LDAP attribute format."""
        attrs = {}

        def add_single(key: str, value: Any):
            if value:
                attrs[key] = [str(value).encode('utf-8')]

        def add_multi(key: str, values: List[str]):
            if values:
                attrs[key] = [v.encode('utf-8') for v in values]

        add_single('x-agent-Type', self.agent_type)
        add_single('x-agent-TrustLevel', self.trust_level)
        add_single('x-agent-Owner', self.owner)
        add_single('x-agent-Parent', self.parent)
        add_single('x-agent-Model', self.model)
        add_multi('x-agent-Capabilities', self.capabilities)
        add_multi('x-agent-AuthorizedTools', self.authorized_tools)
        add_multi('x-agent-DeniedTools', self.denied_tools)
        add_multi('x-agent-NatsSubjects', self.nats_subjects)
        add_single('x-agent-EscalationPath', self.escalation_path)
        add_multi('x-agent-Policies', self.policies)
        add_single('x-agent-AuditLevel', self.audit_level)
        add_multi('x-agent-LLMAccess', self.llm_access)
        add_single('x-agent-LLMQuota', self.llm_quota)
        add_single('x-agent-Mission', self.mission)
        add_single('x-agent-RuntimeEndpoint', self.runtime_endpoint)
        add_single('x-agent-StateEndpoint', self.state_endpoint)

        return attrs

    @classmethod
    def from_ldap_entry(cls, dn: str, attrs: Dict[str, List[bytes]]) -> 'Agent':
        """Create Agent from LDAP entry."""
        def get_single(key: str, default: Any = "") -> str:
            values = attrs.get(key, [])
            return values[0].decode('utf-8') if values else default

        def get_multi(key: str) -> List[str]:
            return [v.decode('utf-8') for v in attrs.get(key, [])]

        def get_int(key: str, default: int = 0) -> int:
            value = get_single(key)
            return int(value) if value else default

        # Extract CN from DN
        cn = dn.split(',')[0].replace('CN=', '')

        return cls(
            name=cn,
            dn=dn,
            agent_type=get_single('x-agent-Type', 'autonomous'),
            trust_level=get_int('x-agent-TrustLevel', 2),
            owner=get_single('x-agent-Owner'),
            parent=get_single('x-agent-Parent'),
            model=get_single('x-agent-Model'),
            capabilities=get_multi('x-agent-Capabilities'),
            authorized_tools=get_multi('x-agent-AuthorizedTools'),
            denied_tools=get_multi('x-agent-DeniedTools'),
            nats_subjects=get_multi('x-agent-NatsSubjects'),
            escalation_path=get_single('x-agent-EscalationPath'),
            policies=get_multi('x-agent-Policies'),
            audit_level=get_int('x-agent-AuditLevel', 1),
            llm_access=get_multi('x-agent-LLMAccess'),
            llm_quota=get_single('x-agent-LLMQuota'),
            mission=get_single('x-agent-Mission'),
            runtime_endpoint=get_single('x-agent-RuntimeEndpoint'),
            state_endpoint=get_single('x-agent-StateEndpoint'),
        )


class AgentManager:
    """Manages agents in Samba4 AD."""

    def __init__(self, config: Config):
        self.config = config
        self.conn: Optional[ldap.ldapobject.LDAPObject] = None

    def connect(self):
        """Connect to LDAP server."""
        if not LDAP_AVAILABLE:
            raise RuntimeError("python-ldap not installed. Run: pip install python-ldap")

        self.conn = ldap.initialize(self.config.ldap_uri)
        self.conn.protocol_version = ldap.VERSION3
        # Respect LDAPTLS_REQCERT env var for TLS certificate verification.
        # Default to 'allow' (accept self-signed) for dev; production should
        # set LDAPTLS_REQCERT=demand and configure a CA cert.
        import os
        tls_mode = os.environ.get("LDAPTLS_REQCERT", "allow")
        tls_map = {
            "never": ldap.OPT_X_TLS_NEVER,
            "allow": ldap.OPT_X_TLS_ALLOW,
            "try": ldap.OPT_X_TLS_TRY,
            "demand": ldap.OPT_X_TLS_DEMAND,
            "hard": ldap.OPT_X_TLS_HARD,
        }
        self.conn.set_option(ldap.OPT_X_TLS_REQUIRE_CERT, tls_map.get(tls_mode, ldap.OPT_X_TLS_ALLOW))
        self.conn.set_option(ldap.OPT_X_TLS_NEWCTX, 0)
        self.conn.simple_bind_s(self.config.bind_dn, self.config.bind_pw)

    def disconnect(self):
        """Disconnect from LDAP."""
        if self.conn:
            self.conn.unbind_s()
            self.conn = None

    def _agent_dn(self, name: str) -> str:
        """Get DN for agent by name."""
        # Agent names should end with $ (machine account convention)
        clean_name = name.rstrip('$')
        return f"CN={clean_name}$,CN=Agents,CN=System,{self.config.base_dn}"

    def _tool_dn(self, identifier: str) -> str:
        """Get DN for tool by identifier."""
        return f"CN={identifier},CN=Agent Tools,CN=System,{self.config.base_dn}"

    def _policy_dn(self, name: str) -> str:
        """Get DN for policy by name."""
        return f"CN={name},CN=Agent Policies,CN=System,{self.config.base_dn}"

    def _gpo_dn(self, name: str) -> str:
        """Get DN for instruction GPO by name."""
        return f"CN={name},CN=Agent Instructions,CN=System,{self.config.base_dn}"

    def create_agent(self, agent: Agent) -> str:
        """Create a new agent in AD."""
        dn = self._agent_dn(agent.name)

        # First, create the computer account using samba-tool
        sam_name = f"{agent.name.rstrip('$')}$"
        cmd = [
            "samba-tool", "user", "create", sam_name,
            "--random-password",
            "--description", f"AI Agent: {agent.agent_type}"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"Failed to create agent: {result.stderr}")

        # Now modify the entry to add agent-specific attributes
        modlist = [(ldap.MOD_ADD, 'objectClass', [b'x-agent'])]

        for attr, values in agent.to_ldap_attrs().items():
            modlist.append((ldap.MOD_ADD, attr, values))

        # Move to Agents container
        # This requires moving the user from CN=Users to CN=Agents,CN=System
        old_dn = f"CN={sam_name},CN=Users,{self.config.base_dn}"
        new_rdn = f"CN={sam_name}"
        new_parent = f"CN=Agents,CN=System,{self.config.base_dn}"

        try:
            self.conn.rename_s(old_dn, new_rdn, new_parent)
        except ldap.NO_SUCH_OBJECT:
            # Already in the right place or different location
            pass

        # Apply agent attributes
        self.conn.modify_s(dn, modlist)

        return dn

    def get_agent(self, name: str) -> Optional[Agent]:
        """Get an agent by name."""
        dn = self._agent_dn(name)

        try:
            result = self.conn.search_s(
                dn, ldap.SCOPE_BASE,
                "(objectClass=x-agent)"
            )
            if result:
                return Agent.from_ldap_entry(result[0][0], result[0][1])
        except ldap.NO_SUCH_OBJECT:
            pass

        return None

    def list_agents(
        self,
        agent_type: Optional[str] = None,
        trust_level: Optional[int] = None
    ) -> List[Agent]:
        """List agents, optionally filtered."""
        base = f"CN=Agents,CN=System,{self.config.base_dn}"

        filters = ["(objectClass=x-agent)"]
        if agent_type:
            filters.append(f"(x-agent-Type={agent_type})")
        if trust_level is not None:
            filters.append(f"(x-agent-TrustLevel={trust_level})")

        if len(filters) > 1:
            filter_str = f"(&{''.join(filters)})"
        else:
            filter_str = filters[0]

        try:
            results = self.conn.search_s(base, ldap.SCOPE_SUBTREE, filter_str)
            return [Agent.from_ldap_entry(dn, attrs) for dn, attrs in results]
        except ldap.NO_SUCH_OBJECT:
            return []

    def update_agent(self, name: str, updates: Dict[str, Any]) -> bool:
        """Update an agent's attributes."""
        dn = self._agent_dn(name)

        modlist = []
        for key, value in updates.items():
            attr_name = f"x-agent-{key}"
            if isinstance(value, list):
                encoded = [v.encode('utf-8') for v in value]
            else:
                encoded = [str(value).encode('utf-8')]
            modlist.append((ldap.MOD_REPLACE, attr_name, encoded))

        self.conn.modify_s(dn, modlist)
        return True

    def delete_agent(self, name: str) -> bool:
        """Delete an agent."""
        dn = self._agent_dn(name)

        # Use samba-tool to delete
        sam_name = f"{name.rstrip('$')}$"
        cmd = ["samba-tool", "user", "delete", sam_name]
        result = subprocess.run(cmd, capture_output=True, text=True)

        return result.returncode == 0

    def generate_keytab(self, name: str, output_path: str) -> bool:
        """Generate a keytab for an agent."""
        sam_name = f"{name.rstrip('$')}$"

        # Use samba-tool to export keytab
        cmd = [
            "samba-tool", "domain", "exportkeytab",
            output_path,
            "--principal", f"{sam_name}@{self.config.domain.upper()}"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"Failed to generate keytab: {result.stderr}")

        # Secure the keytab file
        os.chmod(output_path, 0o600)

        return True

    def grant_tool(self, agent_name: str, tool_identifier: str) -> bool:
        """Grant tool access to an agent."""
        agent_dn = self._agent_dn(agent_name)
        tool_dn = self._tool_dn(tool_identifier)

        modlist = [(ldap.MOD_ADD, 'x-agent-AuthorizedTools', [tool_dn.encode('utf-8')])]

        try:
            self.conn.modify_s(agent_dn, modlist)
            return True
        except ldap.TYPE_OR_VALUE_EXISTS:
            return True  # Already granted

    def revoke_tool(self, agent_name: str, tool_identifier: str) -> bool:
        """Revoke tool access from an agent."""
        agent_dn = self._agent_dn(agent_name)
        tool_dn = self._tool_dn(tool_identifier)

        modlist = [(ldap.MOD_DELETE, 'x-agent-AuthorizedTools', [tool_dn.encode('utf-8')])]

        try:
            self.conn.modify_s(agent_dn, modlist)
            return True
        except ldap.NO_SUCH_ATTRIBUTE:
            return True  # Already revoked

    def link_policy(self, agent_name: str, policy_name: str) -> bool:
        """Link a policy to an agent."""
        agent_dn = self._agent_dn(agent_name)
        policy_dn = self._policy_dn(policy_name)

        modlist = [(ldap.MOD_ADD, 'x-agent-Policies', [policy_dn.encode('utf-8')])]

        try:
            self.conn.modify_s(agent_dn, modlist)
            return True
        except ldap.TYPE_OR_VALUE_EXISTS:
            return True

    def unlink_policy(self, agent_name: str, policy_name: str) -> bool:
        """Unlink a policy from an agent."""
        agent_dn = self._agent_dn(agent_name)
        policy_dn = self._policy_dn(policy_name)

        modlist = [(ldap.MOD_DELETE, 'x-agent-Policies', [policy_dn.encode('utf-8')])]

        try:
            self.conn.modify_s(agent_dn, modlist)
            return True
        except ldap.NO_SUCH_ATTRIBUTE:
            return True

    def get_effective_policies(self, agent_name: str) -> List[Dict[str, Any]]:
        """Get effective policies for an agent, sorted by priority."""
        agent = self.get_agent(agent_name)
        if not agent:
            return []

        policies = []
        for policy_dn in agent.policies:
            try:
                result = self.conn.search_s(
                    policy_dn, ldap.SCOPE_BASE,
                    "(objectClass=x-agentPolicy)"
                )
                if result:
                    attrs = result[0][1]
                    policies.append({
                        'name': attrs.get('x-policy-Identifier', [b''])[0].decode('utf-8'),
                        'type': attrs.get('x-policy-Type', [b''])[0].decode('utf-8'),
                        'priority': int(attrs.get('x-policy-Priority', [b'0'])[0].decode('utf-8')),
                        'path': attrs.get('x-policy-Path', [b''])[0].decode('utf-8'),
                        'enabled': attrs.get('x-policy-Enabled', [b'FALSE'])[0].decode('utf-8') == 'TRUE',
                    })
            except ldap.NO_SUCH_OBJECT:
                continue

        # Sort by priority (higher first)
        policies.sort(key=lambda p: p['priority'], reverse=True)

        return policies

    def list_policies(
        self,
        policy_type: Optional[str] = None,
        enabled_only: bool = False
    ) -> List[Dict[str, Any]]:
        """List all policies, optionally filtered by type or enabled status."""
        base = f"CN=Agent Policies,CN=System,{self.config.base_dn}"

        filters = ["(objectClass=x-agentPolicy)"]
        if policy_type:
            filters.append(f"(x-policy-Type={policy_type})")
        if enabled_only:
            filters.append("(x-policy-Enabled=TRUE)")

        if len(filters) > 1:
            filter_str = f"(&{''.join(filters)})"
        else:
            filter_str = filters[0]

        try:
            results = self.conn.search_s(base, ldap.SCOPE_SUBTREE, filter_str)
        except ldap.NO_SUCH_OBJECT:
            return []

        policies = []
        for dn, attrs in results:
            policies.append({
                'name': attrs.get('x-policy-Identifier', [b''])[0].decode('utf-8'),
                'type': attrs.get('x-policy-Type', [b''])[0].decode('utf-8'),
                'priority': int(attrs.get('x-policy-Priority', [b'0'])[0].decode('utf-8')),
                'path': attrs.get('x-policy-Path', [b''])[0].decode('utf-8'),
                'enabled': attrs.get('x-policy-Enabled', [b'FALSE'])[0].decode('utf-8') == 'TRUE',
                'version': attrs.get('x-policy-Version', [b''])[0].decode('utf-8'),
            })

        policies.sort(key=lambda p: p['priority'])
        return policies

    def list_gpos(self, enabled_only: bool = False) -> List[Dict[str, Any]]:
        """List all instruction GPOs."""
        base = f"CN=Agent Instructions,CN=System,{self.config.base_dn}"

        if enabled_only:
            filter_str = "(&(objectClass=x-agentInstructionGPO)(x-gpo-Enabled=TRUE))"
        else:
            filter_str = "(objectClass=x-agentInstructionGPO)"

        try:
            results = self.conn.search_s(base, ldap.SCOPE_SUBTREE, filter_str)
        except ldap.NO_SUCH_OBJECT:
            return []

        gpos = []
        for dn, attrs in results:
            cn_vals = attrs.get('cn', [b''])
            gpos.append({
                'name': cn_vals[0].decode('utf-8'),
                'display_name': attrs.get('x-gpo-DisplayName', [b''])[0].decode('utf-8'),
                'priority': int(attrs.get('x-gpo-Priority', [b'0'])[0].decode('utf-8')),
                'merge_strategy': attrs.get('x-gpo-MergeStrategy', [b''])[0].decode('utf-8'),
                'instruction_path': attrs.get('x-gpo-InstructionPath', [b''])[0].decode('utf-8'),
                'enabled': attrs.get('x-gpo-Enabled', [b'FALSE'])[0].decode('utf-8') == 'TRUE',
                'version': attrs.get('x-gpo-Version', [b''])[0].decode('utf-8'),
            })

        gpos.sort(key=lambda g: g['priority'])
        return gpos

    def link_gpo(self, agent_name: str, gpo_name: str) -> bool:
        """Link an instruction GPO to an agent."""
        agent_dn = self._agent_dn(agent_name)
        gpo_dn = self._gpo_dn(gpo_name)

        modlist = [(ldap.MOD_ADD, 'x-agent-InstructionGPOs', [gpo_dn.encode('utf-8')])]

        try:
            self.conn.modify_s(agent_dn, modlist)
            return True
        except ldap.TYPE_OR_VALUE_EXISTS:
            return True

    def unlink_gpo(self, agent_name: str, gpo_name: str) -> bool:
        """Unlink an instruction GPO from an agent."""
        agent_dn = self._agent_dn(agent_name)
        gpo_dn = self._gpo_dn(gpo_name)

        modlist = [(ldap.MOD_DELETE, 'x-agent-InstructionGPOs', [gpo_dn.encode('utf-8')])]

        try:
            self.conn.modify_s(agent_dn, modlist)
            return True
        except ldap.NO_SUCH_ATTRIBUTE:
            return True

    def get_effective_gpos(self, agent_name: str) -> List[Dict[str, Any]]:
        """Get effective instruction GPOs for an agent, sorted by priority."""
        agent_dn = self._agent_dn(agent_name)

        try:
            result = self.conn.search_s(
                agent_dn, ldap.SCOPE_BASE,
                "(objectClass=x-agent)",
                ['x-agent-InstructionGPOs']
            )
        except ldap.NO_SUCH_OBJECT:
            return []

        if not result:
            return []

        attrs = result[0][1]
        gpo_dns = [v.decode('utf-8') for v in attrs.get('x-agent-InstructionGPOs', [])]

        gpos = []
        for gpo_dn in gpo_dns:
            try:
                gpo_result = self.conn.search_s(
                    gpo_dn, ldap.SCOPE_BASE,
                    "(objectClass=x-agentInstructionGPO)"
                )
                if gpo_result:
                    gpo_attrs = gpo_result[0][1]
                    cn_vals = gpo_attrs.get('cn', [b''])
                    gpos.append({
                        'name': cn_vals[0].decode('utf-8'),
                        'display_name': gpo_attrs.get('x-gpo-DisplayName', [b''])[0].decode('utf-8'),
                        'priority': int(gpo_attrs.get('x-gpo-Priority', [b'0'])[0].decode('utf-8')),
                        'merge_strategy': gpo_attrs.get('x-gpo-MergeStrategy', [b''])[0].decode('utf-8'),
                        'instruction_path': gpo_attrs.get('x-gpo-InstructionPath', [b''])[0].decode('utf-8'),
                        'enabled': gpo_attrs.get('x-gpo-Enabled', [b'FALSE'])[0].decode('utf-8') == 'TRUE',
                        'version': gpo_attrs.get('x-gpo-Version', [b''])[0].decode('utf-8'),
                    })
            except ldap.NO_SUCH_OBJECT:
                continue

        gpos.sort(key=lambda g: g['priority'])
        return gpos


def main():
    parser = argparse.ArgumentParser(
        description="Agent Directory Management Tool for Samba4",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument('--domain', default='autonomy.local', help='AD domain')
    parser.add_argument('--ldap-uri', default='ldaps://localhost', help='LDAP URI')
    parser.add_argument('--bind-dn', help='Bind DN (default: Administrator)')
    parser.add_argument('--bind-pw', help='Bind password')
    parser.add_argument('--json', action='store_true', help='Output as JSON')

    subparsers = parser.add_subparsers(dest='command', help='Commands')

    # Agent commands
    agent_parser = subparsers.add_parser('agent', help='Agent management')
    agent_sub = agent_parser.add_subparsers(dest='agent_command')

    # agent create
    create_parser = agent_sub.add_parser('create', help='Create an agent')
    create_parser.add_argument('name', help='Agent name')
    create_parser.add_argument('--type', default='autonomous',
                               choices=['autonomous', 'assistant', 'tool', 'orchestrator', 'coordinator'])
    create_parser.add_argument('--trust-level', type=int, default=2, choices=[0, 1, 2, 3, 4])
    create_parser.add_argument('--owner', help='Owner DN')
    create_parser.add_argument('--model', help='AI model identifier')
    create_parser.add_argument('--mission', help='Agent mission statement')
    create_parser.add_argument('--nats-subjects', nargs='+', help='NATS subjects')
    create_parser.add_argument('--llm-access', nargs='+', help='Allowed LLM models')

    # agent get
    get_parser = agent_sub.add_parser('get', help='Get agent details')
    get_parser.add_argument('name', help='Agent name')

    # agent list
    list_parser = agent_sub.add_parser('list', help='List agents')
    list_parser.add_argument('--type', help='Filter by type')
    list_parser.add_argument('--trust-level', type=int, help='Filter by trust level')

    # agent set
    set_parser = agent_sub.add_parser('set', help='Update agent')
    set_parser.add_argument('name', help='Agent name')
    set_parser.add_argument('--type', choices=['autonomous', 'assistant', 'tool', 'orchestrator', 'coordinator'])
    set_parser.add_argument('--trust-level', type=int, choices=[0, 1, 2, 3, 4])
    set_parser.add_argument('--model', help='AI model identifier')
    set_parser.add_argument('--mission', help='Agent mission statement')

    # agent delete
    delete_parser = agent_sub.add_parser('delete', help='Delete agent')
    delete_parser.add_argument('name', help='Agent name')

    # agent keytab
    keytab_parser = agent_sub.add_parser('keytab', help='Generate keytab')
    keytab_parser.add_argument('name', help='Agent name')
    keytab_parser.add_argument('--output', '-o', required=True, help='Output path')

    # Tool commands
    tool_parser = subparsers.add_parser('tool', help='Tool management')
    tool_sub = tool_parser.add_subparsers(dest='tool_command')

    # tool grant
    grant_parser = tool_sub.add_parser('grant', help='Grant tool access')
    grant_parser.add_argument('agent', help='Agent name')
    grant_parser.add_argument('tool', help='Tool identifier')

    # tool revoke
    revoke_parser = tool_sub.add_parser('revoke', help='Revoke tool access')
    revoke_parser.add_argument('agent', help='Agent name')
    revoke_parser.add_argument('tool', help='Tool identifier')

    # Policy commands
    policy_parser = subparsers.add_parser('policy', help='Policy management')
    policy_sub = policy_parser.add_subparsers(dest='policy_command')

    # policy link
    link_parser = policy_sub.add_parser('link', help='Link policy to agent')
    link_parser.add_argument('agent', help='Agent name')
    link_parser.add_argument('policy', help='Policy name')

    # policy unlink
    unlink_parser = policy_sub.add_parser('unlink', help='Unlink policy from agent')
    unlink_parser.add_argument('agent', help='Agent name')
    unlink_parser.add_argument('policy', help='Policy name')

    # policy list
    policy_list_parser = policy_sub.add_parser('list', help='List policies')
    policy_list_parser.add_argument('--type', help='Filter by policy type')
    policy_list_parser.add_argument('--enabled', action='store_true', help='Show only enabled')

    # policy effective
    effective_parser = policy_sub.add_parser('effective', help='Show effective policies')
    effective_parser.add_argument('agent', help='Agent name')

    # GPO commands
    gpo_parser = subparsers.add_parser('gpo', help='Instruction GPO management')
    gpo_sub = gpo_parser.add_subparsers(dest='gpo_command')

    # gpo list
    gpo_list_parser = gpo_sub.add_parser('list', help='List instruction GPOs')
    gpo_list_parser.add_argument('--enabled', action='store_true', help='Show only enabled')

    # gpo link
    gpo_link_parser = gpo_sub.add_parser('link', help='Link GPO to agent')
    gpo_link_parser.add_argument('agent', help='Agent name')
    gpo_link_parser.add_argument('gpo', help='GPO name')

    # gpo unlink
    gpo_unlink_parser = gpo_sub.add_parser('unlink', help='Unlink GPO from agent')
    gpo_unlink_parser.add_argument('agent', help='Agent name')
    gpo_unlink_parser.add_argument('gpo', help='GPO name')

    # gpo effective
    gpo_effective_parser = gpo_sub.add_parser('effective', help='Show effective GPOs for agent')
    gpo_effective_parser.add_argument('agent', help='Agent name')

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    # Create config
    config = Config(
        domain=args.domain,
        ldap_uri=args.ldap_uri,
        bind_dn=args.bind_dn or "",
        bind_pw=args.bind_pw or "",
    )

    # Execute command
    manager = AgentManager(config)

    try:
        manager.connect()

        if args.command == 'agent':
            if args.agent_command == 'create':
                agent = Agent(
                    name=args.name,
                    agent_type=args.type,
                    trust_level=args.trust_level,
                    owner=args.owner or "",
                    model=args.model or "",
                    mission=args.mission or "",
                    nats_subjects=args.nats_subjects or [],
                    llm_access=args.llm_access or [],
                )
                dn = manager.create_agent(agent)
                if args.json:
                    print(json.dumps({'dn': dn}))
                else:
                    print(f"Created agent: {dn}")

            elif args.agent_command == 'get':
                agent = manager.get_agent(args.name)
                if agent:
                    if args.json:
                        print(json.dumps(agent.__dict__, indent=2))
                    else:
                        print(f"Name: {agent.name}")
                        print(f"DN: {agent.dn}")
                        print(f"Type: {agent.agent_type}")
                        print(f"Trust Level: {agent.trust_level}")
                        print(f"Model: {agent.model}")
                        print(f"Mission: {agent.mission}")
                        print(f"NATS Subjects: {', '.join(agent.nats_subjects)}")
                        print(f"LLM Access: {', '.join(agent.llm_access)}")
                else:
                    print(f"Agent not found: {args.name}", file=sys.stderr)
                    sys.exit(1)

            elif args.agent_command == 'list':
                agents = manager.list_agents(
                    agent_type=args.type,
                    trust_level=args.trust_level
                )
                if args.json:
                    print(json.dumps([a.__dict__ for a in agents], indent=2))
                else:
                    for agent in agents:
                        print(f"{agent.name}\t{agent.agent_type}\tL{agent.trust_level}\t{agent.model}")

            elif args.agent_command == 'set':
                updates = {}
                if args.type:
                    updates['Type'] = args.type
                if args.trust_level is not None:
                    updates['TrustLevel'] = args.trust_level
                if args.model:
                    updates['Model'] = args.model
                if args.mission:
                    updates['Mission'] = args.mission

                if updates:
                    manager.update_agent(args.name, updates)
                    print(f"Updated agent: {args.name}")
                else:
                    print("No updates specified")

            elif args.agent_command == 'delete':
                if manager.delete_agent(args.name):
                    print(f"Deleted agent: {args.name}")
                else:
                    print(f"Failed to delete agent: {args.name}", file=sys.stderr)
                    sys.exit(1)

            elif args.agent_command == 'keytab':
                manager.generate_keytab(args.name, args.output)
                print(f"Generated keytab: {args.output}")

        elif args.command == 'tool':
            if args.tool_command == 'grant':
                manager.grant_tool(args.agent, args.tool)
                print(f"Granted {args.tool} to {args.agent}")

            elif args.tool_command == 'revoke':
                manager.revoke_tool(args.agent, args.tool)
                print(f"Revoked {args.tool} from {args.agent}")

        elif args.command == 'policy':
            if args.policy_command == 'list':
                policies = manager.list_policies(
                    policy_type=args.type,
                    enabled_only=args.enabled
                )
                if args.json:
                    print(json.dumps(policies, indent=2))
                else:
                    for p in policies:
                        status = "enabled" if p['enabled'] else "disabled"
                        print(f"{p['priority']}\t{p['name']}\t{p['type']}\t{status}")

            elif args.policy_command == 'link':
                manager.link_policy(args.agent, args.policy)
                print(f"Linked {args.policy} to {args.agent}")

            elif args.policy_command == 'unlink':
                manager.unlink_policy(args.agent, args.policy)
                print(f"Unlinked {args.policy} from {args.agent}")

            elif args.policy_command == 'effective':
                policies = manager.get_effective_policies(args.agent)
                if args.json:
                    print(json.dumps(policies, indent=2))
                else:
                    for p in policies:
                        status = "enabled" if p['enabled'] else "disabled"
                        print(f"{p['priority']}\t{p['name']}\t{p['type']}\t{status}")

        elif args.command == 'gpo':
            if args.gpo_command == 'list':
                gpos = manager.list_gpos(enabled_only=args.enabled)
                if args.json:
                    print(json.dumps(gpos, indent=2))
                else:
                    for g in gpos:
                        status = "enabled" if g['enabled'] else "disabled"
                        print(f"{g['priority']}\t{g['name']}\t{g['merge_strategy']}\t{status}")

            elif args.gpo_command == 'link':
                manager.link_gpo(args.agent, args.gpo)
                print(f"Linked GPO {args.gpo} to {args.agent}")

            elif args.gpo_command == 'unlink':
                manager.unlink_gpo(args.agent, args.gpo)
                print(f"Unlinked GPO {args.gpo} from {args.agent}")

            elif args.gpo_command == 'effective':
                gpos = manager.get_effective_gpos(args.agent)
                if args.json:
                    print(json.dumps(gpos, indent=2))
                else:
                    for g in gpos:
                        status = "enabled" if g['enabled'] else "disabled"
                        print(f"{g['priority']}\t{g['name']}\t{g['merge_strategy']}\t{status}")

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        manager.disconnect()


if __name__ == '__main__':
    main()
