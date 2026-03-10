"""
Config Assembler — reads agent identity from LDAP and assembles sealed config.

Uses the broker's Kerberos ticket (GSSAPI) to read from the DC.
The assembled config is a complete JSON dict that the PowerShell launcher
can consume without any LDAP access.
"""

import json
import logging
import os
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


class ConfigAssembler:
    """
    Assembles a complete agent configuration from LDAP and SYSVOL.

    Replicates the LDAP reads from Start-AgentFromAD.ps1 in Python,
    using the broker's Kerberos ticket for authentication.
    """

    def __init__(
        self,
        ldap_uri: str = "ldaps://dc1.autonomy.local",
        base_dn: str = "DC=autonomy,DC=local",
        sysvol_path: str = "/mnt/samba/sysvol/autonomy.local",
        tool_mapping_path: str = "/opt/agent-launcher/tool-mapping.json",
        ccache_path: Optional[str] = None,
    ):
        self.ldap_uri = ldap_uri
        self.base_dn = base_dn
        self.sysvol_path = sysvol_path
        self.ccache_path = ccache_path
        self.tool_mapping = self._load_tool_mapping(tool_mapping_path)

        # Derived DNs
        self.agents_dn = f"CN=Agents,CN=System,{base_dn}"
        self.tools_dn = f"CN=Agent Tools,CN=System,{base_dn}"
        self.policies_dn = f"CN=Agent Policies,CN=System,{base_dn}"
        self.instructions_dn = f"CN=Agent Instructions,CN=System,{base_dn}"

    def _load_tool_mapping(self, path: str) -> Dict[str, Any]:
        """Load tool mapping from JSON file."""
        try:
            with open(path) as f:
                return json.load(f)
        except FileNotFoundError:
            logger.warning(f"Tool mapping not found at {path}, using defaults")
            return {
                "tool_mapping": {},
                "command_tool_prefixes": {},
                "unrestricted_shell_tools": ["gnu.bash"],
            }

    def _ldapsearch(
        self,
        base_dn: str,
        filter: str = "(objectClass=*)",
        scope: str = "base",
        attributes: Optional[List[str]] = None,
    ) -> List[Dict[str, Any]]:
        """Run ldapsearch with GSSAPI authentication."""
        env = os.environ.copy()
        if self.ccache_path:
            env["KRB5CCNAME"] = self.ccache_path
        env["LDAPTLS_REQCERT"] = os.environ.get("LDAPTLS_REQCERT", "demand")

        scope_map = {"base": "base", "onelevel": "one", "subtree": "sub"}
        scope_arg = scope_map.get(scope, "base")

        cmd = [
            "ldapsearch",
            "-N",
            "-H", self.ldap_uri,
            "-Y", "GSSAPI",
            "-b", base_dn,
            "-s", scope_arg,
            filter,
        ]
        if attributes:
            cmd.extend(attributes)

        result = subprocess.run(
            cmd,
            env=env,
            capture_output=True,
            text=True,
        )

        if result.returncode != 0:
            raise RuntimeError(
                f"ldapsearch failed (exit {result.returncode}): "
                f"base={base_dn} filter={filter}: {result.stderr.strip()}"
            )

        return self._parse_ldif(result.stdout)

    def _parse_ldif(self, ldif: str) -> List[Dict[str, Any]]:
        """Parse LDIF output into list of entry dicts."""
        entries = []
        current: Dict[str, Any] = {}
        current_dn = ""
        last_attr = ""

        for line in ldif.split("\n"):
            # Skip comments
            if line.startswith("#"):
                continue

            # Blank line = end of entry
            if not line.strip():
                if current_dn:
                    entries.append({"dn": current_dn, **current})
                    current = {}
                    current_dn = ""
                    last_attr = ""
                continue

            # Skip search metadata
            if line.startswith("search:") or line.startswith("result:") or line.startswith("ref:"):
                continue

            # Continuation line
            if line.startswith(" "):
                if last_attr and last_attr in current:
                    val = current[last_attr]
                    if isinstance(val, list):
                        val[-1] += line[1:]
                    else:
                        current[last_attr] = val + line[1:]
                continue

            # Attribute: value
            if ": " in line:
                attr, value = line.split(": ", 1)
                last_attr = attr

                if attr == "dn":
                    current_dn = value
                elif attr in current:
                    existing = current[attr]
                    if isinstance(existing, list):
                        existing.append(value)
                    else:
                        current[attr] = [existing, value]
                else:
                    current[attr] = value

        # Last entry
        if current_dn:
            entries.append({"dn": current_dn, **current})

        return entries

    def _read_sysvol_file(self, relative_path: str) -> Optional[str]:
        """Read a file from the SYSVOL mount."""
        full_path = (Path(self.sysvol_path) / relative_path).resolve()
        # Prevent path traversal outside SYSVOL root
        sysvol_root = Path(self.sysvol_path).resolve()
        if not str(full_path).startswith(str(sysvol_root) + os.sep) and full_path != sysvol_root:
            logger.warning(f"Path traversal blocked: {relative_path} resolves outside SYSVOL")
            return None
        try:
            if full_path.exists():
                return full_path.read_text()
        except Exception as e:
            logger.warning(f"Could not read SYSVOL file {full_path}: {e}")
        return None

    def _ensure_list(self, value: Any) -> List[str]:
        """Normalize a value to a list (LDAP attrs may be single or multi-valued)."""
        if value is None:
            return []
        if isinstance(value, list):
            return value
        return [value]

    def assemble(self, agent_name: str) -> Dict[str, Any]:
        """
        Assemble the complete configuration for an agent.

        Returns a dict suitable for writing as JSON to the sealed config file.
        """
        logger.info(f"Assembling config for agent: {agent_name}")

        # 1. Read agent identity
        agent_dn = f"CN={agent_name}$,{self.agents_dn}"
        entries = self._ldapsearch(
            base_dn=agent_dn,
            filter="(objectClass=x-agent)",
            scope="base",
            attributes=[
                "cn", "sAMAccountName",
                "x-agent-Type", "x-agent-TrustLevel", "x-agent-Model",
                "x-agent-Mission", "x-agent-AuthorizedTools", "x-agent-DeniedTools",
                "x-agent-Policies", "x-agent-InstructionGPOs",
                "x-agent-LLMAccess", "x-agent-LLMQuota",
                "x-agent-NatsSubjects", "x-agent-EscalationPath",
                "x-agent-Sandbox", "x-agent-AuditLevel",
                "memberOf",
            ],
        )

        if not entries:
            raise RuntimeError(f"Agent '{agent_name}' not found at: {agent_dn}")

        agent = entries[0]

        identity = {
            "name": agent_name,
            "dn": agent_dn,
            "type": agent.get("x-agent-Type", ""),
            "trust_level": int(agent.get("x-agent-TrustLevel", "0")),
            "model": agent.get("x-agent-Model", ""),
            "mission": agent.get("x-agent-Mission", ""),
            "audit_level": int(agent.get("x-agent-AuditLevel", "0")),
            "llm_access": self._ensure_list(agent.get("x-agent-LLMAccess")),
            "nats_subjects": self._ensure_list(agent.get("x-agent-NatsSubjects")),
            "escalation_path": self._ensure_list(agent.get("x-agent-EscalationPath")),
            "groups": self._ensure_list(agent.get("memberOf")),
        }

        llm_quota_raw = agent.get("x-agent-LLMQuota")
        if llm_quota_raw:
            try:
                identity["llm_quota"] = json.loads(llm_quota_raw)
            except (json.JSONDecodeError, TypeError):
                identity["llm_quota"] = {}
        else:
            identity["llm_quota"] = {}

        logger.info(f"  Identity: type={identity['type']}, trust={identity['trust_level']}, model={identity['model']}")

        # 2. Resolve tool grants
        authorized_tool_dns = self._ensure_list(agent.get("x-agent-AuthorizedTools"))
        denied_tool_dns = self._ensure_list(agent.get("x-agent-DeniedTools"))

        authorized_tools = []
        for tool_dn in authorized_tool_dns:
            tool_info = self._resolve_tool(tool_dn)
            if tool_info:
                authorized_tools.append(tool_info)

        denied_tools = []
        for tool_dn in denied_tool_dns:
            tool_info = self._resolve_tool(tool_dn)
            if tool_info:
                denied_tools.append(tool_info)

        # 3. Map AD tools to psh-agent tools
        tools_config = self._map_tools(authorized_tools, denied_tools)

        # 4. Read instruction GPOs -> system prompt
        gpo_dns = self._ensure_list(agent.get("x-agent-InstructionGPOs"))
        system_prompt = self._assemble_system_prompt(identity, gpo_dns, tools_config)

        # 5. Read policies -> merged enforcement config
        policy_dns = self._ensure_list(agent.get("x-agent-Policies"))
        merged_policy = self._merge_policies(policy_dns, identity)

        # Apply agent-specific LLM quota to merged policy
        if identity["llm_quota"]:
            if "daily_tokens" in identity["llm_quota"]:
                merged_policy.setdefault("llm", {})["daily_token_limit"] = identity["llm_quota"]["daily_tokens"]
            if "max_context" in identity["llm_quota"]:
                merged_policy.setdefault("llm", {})["max_context_tokens"] = identity["llm_quota"]["max_context"]

        # 6. Compute connection string
        model = identity["model"]
        if any(model.startswith(p) for p in ("claude", "anthropic")):
            provider = "anthropic"
        elif any(model.startswith(p) for p in ("gpt", "openai")):
            provider = "openai"
        else:
            provider = "anthropic"
        connection_string = f"{provider}/{model}"

        # 7. Assemble final config
        max_steps = merged_policy.get("execution", {}).get("max_iterations", 50)

        config = {
            "version": 1,
            "agent": identity,
            "connection_string": connection_string,
            "system_prompt": system_prompt,
            "tools": tools_config,
            "policy": merged_policy,
            "max_steps": max_steps,
        }

        logger.info(
            f"  Config assembled: {len(tools_config['enabled_builtin_tools'])} tools, "
            f"{len(gpo_dns)} GPOs, {len(policy_dns)} policies"
        )

        return config

    def _resolve_tool(self, tool_dn: str) -> Optional[Dict[str, str]]:
        """Read a tool entry from LDAP and return its metadata."""
        try:
            entries = self._ldapsearch(
                base_dn=tool_dn,
                scope="base",
                attributes=["x-tool-Identifier", "x-tool-Category", "x-tool-RiskLevel"],
            )
            if entries:
                return {
                    "dn": tool_dn,
                    "identifier": entries[0].get("x-tool-Identifier", ""),
                    "category": entries[0].get("x-tool-Category", ""),
                    "risk_level": entries[0].get("x-tool-RiskLevel", "0"),
                }
        except Exception as e:
            logger.warning(f"Could not resolve tool {tool_dn}: {e}")
        return None

    def _map_tools(
        self,
        authorized_tools: List[Dict[str, str]],
        denied_tools: List[Dict[str, str]],
    ) -> Dict[str, Any]:
        """Map AD tool identifiers to psh-agent built-in tools."""
        tool_mapping = self.tool_mapping.get("tool_mapping", {})
        command_prefixes_map = self.tool_mapping.get("command_tool_prefixes", {})
        unrestricted_tools = self.tool_mapping.get("unrestricted_shell_tools", [])

        denied_ids = {t["identifier"] for t in denied_tools}
        authorized_ids = []

        enabled_builtins = set()
        allowed_command_prefixes = []
        has_unrestricted_shell = False

        for tool in authorized_tools:
            tool_id = tool["identifier"]

            if tool_id in denied_ids:
                logger.info(f"  Tool {tool_id} denied by override")
                continue

            authorized_ids.append(tool_id)

            # Map to built-in tools
            if tool_id in tool_mapping:
                for bt in tool_mapping[tool_id]:
                    enabled_builtins.add(bt)

            # Check for command-prefix tools
            if tool_id in command_prefixes_map:
                enabled_builtins.add("run_command")
                allowed_command_prefixes.extend(command_prefixes_map[tool_id])

            # Check for unrestricted shell
            if tool_id in unrestricted_tools:
                has_unrestricted_shell = True

        return {
            "authorized_ids": authorized_ids,
            "denied_ids": list(denied_ids),
            "enabled_builtin_tools": sorted(enabled_builtins),
            "allowed_command_prefixes": allowed_command_prefixes,
            "has_unrestricted_shell": has_unrestricted_shell,
        }

    def _assemble_system_prompt(
        self,
        identity: Dict[str, Any],
        gpo_dns: List[str],
        tools_config: Dict[str, Any],
    ) -> str:
        """Read instruction GPOs from LDAP/SYSVOL and assemble system prompt."""
        parts = []

        # Agent identity header
        parts.append(
            f"# Agent Identity\n\n"
            f"- **Name:** {identity['name']}\n"
            f"- **Type:** {identity['type']}\n"
            f"- **Trust Level:** {identity['trust_level']}\n"
            f"- **Model:** {identity['model']}\n"
            f"- **Mission:** {identity['mission']}\n"
            f"- **Audit Level:** {identity['audit_level']}"
        )

        # Read instruction GPOs
        instruction_parts = []
        for gpo_dn in gpo_dns:
            try:
                entries = self._ldapsearch(
                    base_dn=gpo_dn,
                    scope="base",
                    attributes=[
                        "x-gpo-DisplayName", "x-gpo-InstructionPath",
                        "x-gpo-Priority", "x-gpo-MergeStrategy",
                    ],
                )
                if entries:
                    gpo = entries[0]
                    path = gpo.get("x-gpo-InstructionPath", "")
                    priority = int(gpo.get("x-gpo-Priority", "0"))
                    name = gpo.get("x-gpo-DisplayName", "")

                    content = self._read_sysvol_file(path)
                    if content:
                        instruction_parts.append({
                            "name": name,
                            "priority": priority,
                            "content": content,
                        })
                        logger.info(f"  GPO: {name} (priority: {priority})")
                    else:
                        logger.warning(f"  GPO: {name} — content not found at {path}")
            except Exception as e:
                logger.warning(f"Could not read GPO {gpo_dn}: {e}")

        # Sort by priority (lowest first = base instructions first)
        instruction_parts.sort(key=lambda p: p["priority"])

        for part in instruction_parts:
            parts.append(part["content"])

        # Tool authorization summary
        tool_section = f"\n# Tool Authorization\n\nYou are authorized to use the following tools: {', '.join(tools_config['authorized_ids'])}"
        if tools_config["denied_ids"]:
            tool_section += f"\nExplicitly denied: {', '.join(tools_config['denied_ids'])}"
        if not tools_config["has_unrestricted_shell"] and tools_config["allowed_command_prefixes"]:
            tool_section += f"\nFor shell commands, you may only run: {', '.join(tools_config['allowed_command_prefixes'])}"
        parts.append(tool_section)

        return "\n\n".join(parts)

    def _merge_policies(
        self,
        policy_dns: List[str],
        identity: Dict[str, Any],
    ) -> Dict[str, Any]:
        """Read and merge policies from LDAP/SYSVOL."""
        merged: Dict[str, Any] = {
            "tools": {"deny": []},
            "execution": {},
            "llm": {},
            "audit": {},
        }

        for policy_dn in policy_dns:
            try:
                entries = self._ldapsearch(
                    base_dn=policy_dn,
                    scope="base",
                    attributes=[
                        "x-policy-Identifier", "x-policy-Path",
                        "x-policy-Priority", "x-policy-Enabled",
                    ],
                )
                if not entries:
                    continue

                policy = entries[0]
                if policy.get("x-policy-Enabled") != "TRUE":
                    continue

                policy_path = policy.get("x-policy-Path", "")
                policy_id = policy.get("x-policy-Identifier", "")
                content = self._read_sysvol_file(policy_path)

                if not content:
                    continue

                try:
                    policy_json = json.loads(content)
                except json.JSONDecodeError:
                    logger.warning(f"Invalid JSON in policy {policy_id}")
                    continue

                settings = policy_json.get("settings", {})

                # Merge tool denials
                if settings.get("tools", {}).get("deny"):
                    merged["tools"]["deny"].extend(settings["tools"]["deny"])

                # Merge execution limits
                if "execution" in settings:
                    merged["execution"].update(settings["execution"])

                # Merge LLM limits
                if "llm" in settings:
                    merged["llm"].update(settings["llm"])

                # Merge audit settings
                if "audit" in settings:
                    merged["audit"].update(settings["audit"])

                logger.info(f"  Policy: {policy_id}")

            except Exception as e:
                logger.warning(f"Could not read policy {policy_dn}: {e}")

        return merged
