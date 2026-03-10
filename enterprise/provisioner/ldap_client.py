"""Real LDAP client for provisioner — uses subprocess ldapsearch/ldapmodify."""

import base64
import logging
import os
import re
import subprocess
from typing import Any, Dict, List, Optional

from .identity import AgentIdentity

logger = logging.getLogger(__name__)
_AGENT_NAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$")

# x-agent-AuditLevel uses integer syntax (2.5.5.9), range 0-3
AUDIT_LEVEL_MINIMAL = 0
AUDIT_LEVEL_STANDARD = 1
AUDIT_LEVEL_DETAILED = 2
AUDIT_LEVEL_DEBUG = 3


def _escape_filter_value(value: str) -> str:
    """Escape an LDAP filter value per RFC 4515."""
    escaped: List[str] = []
    for ch in value:
        if ch in ("*", "(", ")", "\\", "\x00"):
            escaped.append(f"\\{ord(ch):02x}")
        else:
            escaped.append(ch)
    return "".join(escaped)


class LDAPClient:
    """LDAP client that shells out to ldapsearch/ldapmodify.

    Same approach as ConfigAssembler — no python-ldap dependency,
    works with both simple bind and GSSAPI.
    """

    def __init__(
        self,
        uri: str,
        base_dn: str,
        bind_dn: str = "",
        bind_pw: str = "",
        agents_dn: str = "",
        ccache_path: Optional[str] = None,
        ca_cert: Optional[str] = None,
    ):
        self.uri = uri
        self.base_dn = base_dn
        self.bind_dn = bind_dn
        self.bind_pw = bind_pw
        self.agents_dn = agents_dn or f"CN=Agents,CN=System,{base_dn}"
        self.ccache_path = ccache_path
        self.ca_cert = ca_cert

    def _build_auth_args(self) -> List[str]:
        """Build authentication arguments for ldap commands."""
        if self.ccache_path:
            return ["-Y", "GSSAPI"]
        elif self.bind_dn and self.bind_pw:
            return ["-x", "-D", self.bind_dn, "-w", self.bind_pw]
        else:
            return ["-x"]

    def _build_env(self) -> Dict[str, str]:
        env = os.environ.copy()
        if self.ccache_path:
            env["KRB5CCNAME"] = self.ccache_path
        env["LDAPTLS_REQCERT"] = os.environ.get("LDAPTLS_REQCERT", "demand")
        if self.ca_cert:
            env["LDAPTLS_CACERT"] = self.ca_cert
        return env

    def _ldapsearch(
        self,
        base_dn: str,
        ldap_filter: str = "(objectClass=*)",
        scope: str = "base",
        attributes: Optional[List[str]] = None,
    ) -> List[Dict[str, Any]]:
        scope_map = {"base": "base", "onelevel": "one", "subtree": "sub"}
        cmd = [
            "ldapsearch", "-N",
            "-H", self.uri,
            *self._build_auth_args(),
            "-b", base_dn,
            "-s", scope_map.get(scope, "base"),
            ldap_filter,
        ]
        if attributes:
            cmd.extend(attributes)

        result = subprocess.run(
            cmd, env=self._build_env(), capture_output=True, text=True,
        )
        if result.returncode != 0:
            logger.error(f"ldapsearch failed: {result.stderr.strip()}")
            return []

        return self._parse_ldif(result.stdout)

    def _ldapmodify(self, ldif: str) -> bool:
        cmd = [
            "ldapmodify",
            "-H", self.uri,
            *self._build_auth_args(),
        ]
        result = subprocess.run(
            cmd, env=self._build_env(),
            input=ldif, capture_output=True, text=True,
        )
        if result.returncode != 0:
            logger.error(f"ldapmodify failed: {result.stderr.strip()}")
            return False
        return True

    def _validate_agent_name(self, name: str) -> bool:
        """Validate generated or requested agent names before LDAP writes."""
        return bool(_AGENT_NAME_PATTERN.fullmatch(name))

    async def ping(self) -> bool:
        """Validate LDAP connectivity and bind credentials."""
        entries = self._ldapsearch(
            base_dn=self.base_dn,
            ldap_filter="(objectClass=*)",
            scope="base",
            attributes=["dn"],
        )
        if not entries:
            logger.error("LDAP connectivity check failed for base DN %s", self.base_dn)
            return False
        return True

    async def create_agent(
        self,
        name: str,
        agent_type: str = "worker",
        trust_level: int = 2,
    ) -> Optional[AgentIdentity]:
        """Create an agent identity in AD via ldapmodify."""
        if not self._validate_agent_name(name):
            logger.error("Refusing to create agent with invalid name: %r", name)
            return None

        dn = f"CN={name}$,{self.agents_dn}"
        realm = self.base_dn.replace("DC=", "").replace(",", ".").upper()
        principal = f"{name}$@{realm}"

        ldif = (
            f"dn: {dn}\n"
            f"changetype: add\n"
            f"objectClass: top\n"
            f"objectClass: person\n"
            f"objectClass: organizationalPerson\n"
            f"objectClass: user\n"
            f"objectClass: x-agent\n"
            f"cn: {name}$\n"
            f"sAMAccountName: {name}$\n"
            f"userPrincipalName: {principal}\n"
            f"x-agent-Type: {agent_type}\n"
            f"x-agent-TrustLevel: {trust_level}\n"
            f"x-agent-AuditLevel: {AUDIT_LEVEL_STANDARD}\n"
        )

        if not self._ldapmodify(ldif):
            logger.error(f"Failed to create agent {name}")
            return None

        return AgentIdentity(
            name=name,
            dn=dn,
            sid="",
            principal=principal,
            agent_type=agent_type,
            trust_level=trust_level,
        )

    def search_agents(
        self,
        agent_type: Optional[str] = None,
        name: Optional[str] = None,
    ) -> List[AgentIdentity]:
        """Search for agent identities in AD.

        Args:
            agent_type: Filter by x-agent-Type (e.g. "worker").
            name: Filter by sAMAccountName (exact match, without $ suffix).

        Returns:
            List of matching AgentIdentity objects.
        """
        filters = ["(objectClass=x-agent)"]
        if agent_type:
            filters.append(f"(x-agent-Type={_escape_filter_value(agent_type)})")
        if name:
            filters.append(f"(sAMAccountName={_escape_filter_value(name)}$)")

        ldap_filter = f"(&{''.join(filters)})" if len(filters) > 1 else filters[0]

        entries = self._ldapsearch(
            base_dn=self.agents_dn,
            ldap_filter=ldap_filter,
            scope="onelevel",
            attributes=[
                "cn", "sAMAccountName", "objectSid",
                "x-agent-Type", "x-agent-TrustLevel", "x-agent-Model",
                "x-agent-Mission", "x-agent-AuthorizedTools", "x-agent-DeniedTools",
                "x-agent-Policies", "x-agent-NatsSubjects",
                "x-agent-EscalationPath", "x-agent-AuditLevel",
                "x-agent-LLMAccess", "x-agent-LLMQuota",
            ],
        )

        results = []
        for entry in entries:
            sam = entry.get("sAMAccountName", "")
            agent_name = sam.rstrip("$")
            if not agent_name:
                continue

            def _ensure_list(val):
                if val is None:
                    return []
                return val if isinstance(val, list) else [val]

            results.append(AgentIdentity(
                name=agent_name,
                dn=entry.get("dn", ""),
                sid=entry.get("objectSid", ""),
                principal=f"{sam}@{self.base_dn.replace('DC=', '').replace(',', '.').upper()}",
                agent_type=entry.get("x-agent-Type", ""),
                trust_level=int(entry.get("x-agent-TrustLevel", "0")),
                model=entry.get("x-agent-Model", ""),
                mission=entry.get("x-agent-Mission", ""),
                capabilities=_ensure_list(entry.get("x-agent-Capabilities")),
                authorized_tools=_ensure_list(entry.get("x-agent-AuthorizedTools")),
                denied_tools=_ensure_list(entry.get("x-agent-DeniedTools")),
                nats_subjects=_ensure_list(entry.get("x-agent-NatsSubjects")),
                escalation_path=entry.get("x-agent-EscalationPath", ""),
                policies=_ensure_list(entry.get("x-agent-Policies")),
                audit_level=int(entry.get("x-agent-AuditLevel", "1")),
                llm_access=_ensure_list(entry.get("x-agent-LLMAccess")),
            ))

        return results

    def get_agent(self, name: str) -> Optional[AgentIdentity]:
        """Get a single agent identity by name.

        Args:
            name: Agent sAMAccountName (without $ suffix).

        Returns:
            AgentIdentity if found, None otherwise.
        """
        results = self.search_agents(name=name)
        return results[0] if results else None

    def _ldapadd(self, ldif: str) -> bool:
        """Add a new entry via ldapadd."""
        cmd = [
            "ldapadd",
            "-H", self.uri,
            *self._build_auth_args(),
        ]
        result = subprocess.run(
            cmd, env=self._build_env(),
            input=ldif, capture_output=True, text=True,
        )
        if result.returncode != 0:
            logger.error(f"ldapadd failed: {result.stderr.strip()}")
            return False
        return True

    def _ldapdelete(self, dn: str) -> bool:
        """Delete an entry via ldapdelete."""
        cmd = [
            "ldapdelete",
            "-H", self.uri,
            *self._build_auth_args(),
            dn,
        ]
        result = subprocess.run(
            cmd, env=self._build_env(),
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            logger.error(f"ldapdelete failed: {result.stderr.strip()}")
            return False
        return True

    def set_password(self, dn: str, new_password: str) -> bool:
        """Set unicodePwd on an AD account. Requires LDAPS.

        AD requires the password as UTF-16LE encoded, surrounded by double quotes,
        then base64-encoded in the LDIF.
        """
        encoded = ('"' + new_password + '"').encode("utf-16-le")
        b64_password = base64.b64encode(encoded).decode("ascii")

        ldif = (
            f"dn: {dn}\n"
            f"changetype: modify\n"
            f"replace: unicodePwd\n"
            f"unicodePwd:: {b64_password}\n"
            f"-\n"
        )

        # unicodePwd requires LDAPS — swap ldap:// to ldaps:// if needed
        uri = self.uri
        if uri.startswith("ldap://"):
            uri = uri.replace("ldap://", "ldaps://", 1)
            if ":389" in uri:
                uri = uri.replace(":389", ":636")

        cmd = [
            "ldapmodify",
            "-H", uri,
            *self._build_auth_args(),
        ]
        env = self._build_env()

        result = subprocess.run(
            cmd, env=env, input=ldif, capture_output=True, text=True,
        )
        if result.returncode != 0:
            logger.error(f"set_password failed for {dn}: {result.stderr.strip()}")
            return False
        logger.info(f"Password set for {dn}")
        return True

    def create_computer(self, name: str, container_dn: str, password: str) -> bool:
        """Pre-stage a computer account for domain join.

        Args:
            name: Computer name (without $ suffix).
            container_dn: DN of the container (e.g. CN=Agent Sandboxes,CN=System,DC=...).
            password: Initial one-time password for the computer account.
        """
        if not self._validate_agent_name(name):
            logger.error("Invalid computer name: %r", name)
            return False

        dn = f"CN={name},{container_dn}"
        encoded_pw = ('"' + password + '"').encode("utf-16-le")
        b64_pw = base64.b64encode(encoded_pw).decode("ascii")

        ldif = (
            f"dn: {dn}\n"
            f"objectClass: top\n"
            f"objectClass: person\n"
            f"objectClass: organizationalPerson\n"
            f"objectClass: user\n"
            f"objectClass: computer\n"
            f"cn: {name}\n"
            f"sAMAccountName: {name}$\n"
            f"userAccountControl: 4096\n"
            f"unicodePwd:: {b64_pw}\n"
        )

        # Use LDAPS for unicodePwd
        uri = self.uri
        if uri.startswith("ldap://"):
            uri = uri.replace("ldap://", "ldaps://", 1)
            if ":389" in uri:
                uri = uri.replace(":389", ":636")

        cmd = [
            "ldapadd",
            "-H", uri,
            *self._build_auth_args(),
        ]
        env = self._build_env()

        result = subprocess.run(
            cmd, env=env, input=ldif, capture_output=True, text=True,
        )
        if result.returncode != 0:
            logger.error(f"create_computer failed for {name}: {result.stderr.strip()}")
            return False
        logger.info(f"Computer account {name} pre-staged in {container_dn}")
        return True

    def delete_computer(self, name: str, container_dn: str) -> bool:
        """Delete a pre-staged computer account.

        Args:
            name: Computer name (without $ suffix).
            container_dn: DN of the container.
        """
        dn = f"CN={name},{container_dn}"
        return self._ldapdelete(dn)

    async def get_policy(self, dn: str) -> Optional[Dict[str, Any]]:
        """Read a policy entry from AD."""
        entries = self._ldapsearch(
            base_dn=dn,
            ldap_filter="(objectClass=x-agentPolicy)",
            scope="base",
        )
        if not entries:
            return None
        return entries[0]

    @staticmethod
    def _parse_ldif(ldif: str) -> List[Dict[str, Any]]:
        entries: List[Dict[str, Any]] = []
        current: Dict[str, Any] = {}
        current_dn = ""
        last_attr = ""

        for line in ldif.split("\n"):
            if line.startswith("#"):
                continue
            if not line.strip():
                if current_dn:
                    entries.append({"dn": current_dn, **current})
                    current = {}
                    current_dn = ""
                    last_attr = ""
                continue
            if line.startswith("search:") or line.startswith("result:") or line.startswith("ref:"):
                continue
            if line.startswith(" "):
                if last_attr and last_attr in current:
                    val = current[last_attr]
                    if isinstance(val, list):
                        val[-1] += line[1:]
                    else:
                        current[last_attr] = val + line[1:]
                continue
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

        if current_dn:
            entries.append({"dn": current_dn, **current})

        return entries
