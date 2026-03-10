"""
Agent Provisioning Service

The central service for provisioning agent identities and configuration.
Queries AD directly — agent identities live in LDAP, that IS the database.

Agents domain-join by creating their own keytab from a temporary password
set by this service. No keytab export or samba-tool dependency needed.
"""

import json
import logging
import secrets
import string
from contextlib import asynccontextmanager
from dataclasses import dataclass
from typing import Any, Dict, Optional
from uuid import UUID, uuid4

from .config import ProvisionerConfig
from .credential_store import CredentialStore, FileCredentialStore
from .lease_store import LeaseStore, SQLiteLeaseStore
from .identity import AgentIdentity, SandboxIdentity
from .policy import MergedPolicy, PolicyLoader

logger = logging.getLogger(__name__)


@dataclass
class ProvisioningBundle:
    """Complete provisioning bundle for an agent."""
    identity: AgentIdentity
    sandbox: SandboxIdentity

    # Domain-join parameters (agent creates own keytab from these)
    domain_join: Dict[str, str]
    agent_credentials: Dict[str, str]

    # Configuration
    policy: MergedPolicy
    nats_credentials: Dict[str, str]

    # Mounts
    smb_mounts: Dict[str, str]  # mount_point -> smb_path

    def to_dict(self) -> Dict[str, Any]:
        """Serialize for injection into agent environment."""
        return {
            "identity": self.identity.to_dict(),
            "sandbox": self.sandbox.to_dict(),
            "domain_join": self.domain_join,
            "agent_credentials": self.agent_credentials,
            "policy": self.policy.to_dict(),
            "nats": self.nats_credentials,
            "smb_mounts": self.smb_mounts,
        }

    def to_json(self) -> str:
        """Serialize to JSON."""
        return json.dumps(self.to_dict(), indent=2)


class ProvisioningService:
    """
    Agent Provisioning Service.

    Responsibilities:
    - Query AD for agent identities (AD is the source of truth)
    - Set temporary passwords for agent domain-join
    - Pre-stage sandbox computer accounts
    - Load and merge policies from AD/SYSVOL
    - Create complete provisioning bundles
    """

    def __init__(self, config: ProvisionerConfig):
        self.config = config
        self._ldap_client = None
        self._policy_loader = None
        self._credential_store: Optional[CredentialStore] = None
        self._lease_store: Optional[LeaseStore] = None
        self._running = False

    async def start(self):
        """Start the provisioning service."""
        logger.info("Starting provisioning service...")

        # Initialize LDAP client
        self._ldap_client = await self._create_ldap_client()
        if hasattr(self._ldap_client, "ping"):
            if not await self._ldap_client.ping():
                raise RuntimeError(
                    f"Unable to connect to LDAP at {self.config.ldap.uri} "
                    f"for base DN {self.config.ldap.base_dn}"
                )

        # Initialize policy loader
        self._policy_loader = PolicyLoader(
            ldap_client=self._ldap_client,
            smb_config=self.config.smb,
        )

        self._running = True
        logger.info("Provisioning service started")

    async def stop(self):
        """Stop the provisioning service."""
        logger.info("Stopping provisioning service...")
        self._running = False
        logger.info("Provisioning service stopped")

    async def provision_agent(
        self,
        agent_type: str,
        vm_id: str,
        requirements: Optional[Dict[str, Any]] = None,
    ) -> ProvisioningBundle:
        """
        Provision an agent for a VM or container.

        Searches AD for an agent of the requested type, sets a temporary
        password for domain-join, pre-stages a sandbox computer account,
        and assembles a complete provisioning bundle.

        Args:
            agent_type: Type of agent (worker, coordinator, etc.)
            vm_id: ID of the VM/container being provisioned
            requirements: Optional requirements for identity selection

        Returns:
            ProvisioningBundle with all data needed to domain-join and boot agent
        """
        logger.info(f"Provisioning agent type={agent_type} for vm={vm_id}")

        # Search AD for an agent of the requested type
        agents = self._ldap_client.search_agents(agent_type=agent_type)

        if requirements:
            min_trust = requirements.get("min_trust_level", 0)
            required_caps = set(requirements.get("capabilities", []))
            agents = [
                a for a in agents
                if a.trust_level >= min_trust
                and (not required_caps or required_caps.issubset(set(a.capabilities)))
            ]

        if not agents:
            raise RuntimeError(f"No identity available for agent type {agent_type}")

        if not self._lease_store:
            raise RuntimeError("Lease store is not configured")
        await self._lease_store.purge_expired()

        # Reserve the first available identity (transactional lease).
        identity: Optional[AgentIdentity] = None
        for candidate in agents:
            leased = await self._lease_store.reserve(
                identity_name=candidate.name,
                vm_id=vm_id,
                ttl_seconds=self.config.database.lease_ttl_seconds,
            )
            if leased:
                identity = candidate
                break

        if identity is None:
            raise RuntimeError(
                f"No identity lease available for agent type {agent_type}; "
                "all matching identities are already in use"
            )

        identity.assigned_vm_id = vm_id

        try:
            # Set temporary password on agent account for domain-join
            agent_password = self._generate_temp_password()
            self._set_agent_password(identity.dn, agent_password)

            # Pre-stage sandbox computer account
            sandbox_name = f"sbx-{identity.name}"
            sandbox_dn = f"CN={sandbox_name},CN=Agent Sandboxes,CN=System,{self.config.ldap.base_dn}"
            sandbox_otp = self._generate_temp_password()
            self._prestage_computer(
                sandbox_name,
                f"CN=Agent Sandboxes,CN=System,{self.config.ldap.base_dn}",
                sandbox_otp,
            )

            sandbox = SandboxIdentity(
                name=sandbox_name,
                dn=sandbox_dn,
                sid="",
                principal=f"{sandbox_name}$@{self.config.kerberos.realm}",
                security_profile="bwrap",
                status="active",
            )

            # Domain-join parameters for the agent environment
            krb = self.config.kerberos
            domain_join = {
                "realm": krb.realm,
                "dc_hostname": krb.dc_hostname,
                "computer_name": sandbox_name,
                "computer_otp": sandbox_otp,
            }
            if krb.dc_ip:
                domain_join["dc_ip"] = krb.dc_ip

            agent_credentials = {
                "principal": identity.principal,
                "password": agent_password,
            }

            # Load effective policy
            policy = await self._policy_loader.load_policies_for_agent(
                agent_dn=identity.dn,
                agent_type=identity.agent_type,
                trust_level=identity.trust_level,
                policy_dns=identity.policies,
            )

            # Generate NATS credentials
            nats_creds = await self._generate_nats_credentials(identity, policy)

            # Determine SMB mounts
            smb_mounts = self._get_smb_mounts(identity)

            bundle = ProvisioningBundle(
                identity=identity,
                sandbox=sandbox,
                domain_join=domain_join,
                agent_credentials=agent_credentials,
                policy=policy,
                nats_credentials=nats_creds,
                smb_mounts=smb_mounts,
            )

            logger.info(
                f"Provisioned agent {identity.name} for vm={vm_id}, "
                f"trust_level={identity.trust_level}"
            )

            return bundle
        except Exception:
            # Roll back lease if provisioning fails after reservation.
            await self._lease_store.release(identity.name, vm_id=vm_id)
            raise

    async def release_agent(self, identity_name: str, vm_id: str):
        """
        Release an agent identity.

        Called when a VM/container is destroyed. The agent identity remains
        in AD; the pre-staged sandbox computer account is deleted.
        """
        logger.info(f"Releasing agent {identity_name} from vm={vm_id}")

        identity = self._ldap_client.get_agent(identity_name)
        if not identity:
            logger.warning(f"Identity {identity_name} not found in AD")
            if self._lease_store:
                await self._lease_store.release(identity_name, vm_id=vm_id)
            return

        # Delete pre-staged sandbox computer account
        sandbox_name = f"sbx-{identity_name}"
        sandboxes_dn = f"CN=Agent Sandboxes,CN=System,{self.config.ldap.base_dn}"
        if self._ldap_client.delete_computer(sandbox_name, sandboxes_dn):
            logger.info(f"Deleted sandbox computer {sandbox_name}")
        else:
            logger.warning(f"Could not delete sandbox computer {sandbox_name} (may not exist)")

        if self._lease_store:
            await self._lease_store.release(identity_name, vm_id=vm_id)
        logger.info(f"Agent {identity_name} released from vm={vm_id}")

    async def get_agent_config(self, identity_name: str) -> Optional[Dict[str, Any]]:
        """
        Get current configuration for an agent.

        Used by agents to refresh their config at runtime.
        """
        identity = self._ldap_client.get_agent(identity_name)
        if not identity:
            return None

        # Reload policy
        policy = await self._policy_loader.load_policies_for_agent(
            agent_dn=identity.dn,
            agent_type=identity.agent_type,
            trust_level=identity.trust_level,
            policy_dns=identity.policies,
        )

        return {
            "identity": identity.to_dict(),
            "policy": policy.to_dict(),
        }

    @staticmethod
    def _generate_temp_password(length: int = 32) -> str:
        """Generate a cryptographically random temporary password."""
        alphabet = string.ascii_letters + string.digits + string.punctuation
        return "".join(secrets.choice(alphabet) for _ in range(length))

    def _set_agent_password(self, dn: str, password: str):
        """Set a temporary password on an agent account via LDAPS."""
        if not self._ldap_client.set_password(dn, password):
            raise RuntimeError(f"Failed to set password for {dn}")
        logger.info(f"Temporary password set for {dn}")

    def _prestage_computer(self, name: str, container_dn: str, password: str):
        """Pre-stage a sandbox computer account with a one-time password."""
        if not self._ldap_client.create_computer(name, container_dn, password):
            raise RuntimeError(f"Failed to pre-stage computer {name}")
        logger.info(f"Pre-staged computer {name}")

    async def _create_ldap_client(self):
        """Create LDAP client backed by subprocess ldapsearch/ldapmodify."""
        from .ldap_client import LDAPClient
        return LDAPClient(
            uri=self.config.ldap.uri,
            base_dn=self.config.ldap.base_dn,
            bind_dn=self.config.ldap.bind_dn,
            bind_pw=self.config.ldap.bind_pw,
            agents_dn=self.config.ldap.agents_dn(),
            ca_cert=self.config.ldap.ca_cert,
        )

    async def _generate_nats_credentials(
        self,
        identity: AgentIdentity,
        policy: MergedPolicy,
    ) -> Dict[str, str]:
        """Build NATS credentials for an agent."""
        agent_type = identity.agent_type
        auth_mode = (self.config.nats.auth_mode or "password").lower()

        if auth_mode == "jwt":
            user_jwt = self.config.nats.agent_user_jwts.get(agent_type, "")
            nkey_seed = self.config.nats.agent_nkey_seeds.get(agent_type, "")
            if not user_jwt or not nkey_seed:
                env_prefix = f"NATS_{agent_type.upper().replace('-', '_')}"
                raise RuntimeError(
                    f"No NATS JWT credentials configured for agent type '{agent_type}'. "
                    f"Set {env_prefix}_USER_JWT and {env_prefix}_NKEY_SEED."
                )

            return {
                "auth_mode": "jwt",
                "servers": policy.nats_server or self.config.nats.servers[0],
                "user": identity.name,
                "user_jwt": user_jwt,
                "nkey_seed": nkey_seed,
                "allowed_subjects": policy.nats_allowed_subjects,
                "denied_subjects": policy.nats_denied_subjects,
            }

        if auth_mode == "password":
            password = self.config.nats.agent_passwords.get(agent_type, "")
            if not password:
                raise RuntimeError(
                    f"No NATS password configured for agent type '{agent_type}'. "
                    f"Set NATS_{agent_type.upper().replace('-', '_')}_PASSWORD "
                    f"in the environment."
                )
            return {
                "auth_mode": "password",
                "servers": policy.nats_server or self.config.nats.servers[0],
                "user": agent_type,
                "password": password,
                "allowed_subjects": policy.nats_allowed_subjects,
                "denied_subjects": policy.nats_denied_subjects,
            }

        raise RuntimeError(
            f"Unsupported NATS_AUTH_MODE '{auth_mode}'. "
            "Supported values: jwt, password."
        )

    def _get_smb_mounts(self, identity: AgentIdentity) -> Dict[str, str]:
        """Determine SMB mounts for agent."""
        server = self.config.smb.server

        mounts = {
            # Domain shared folder
            "/mnt/shared": f"//{server}/Domain/shared",

            # Agent home folder
            f"/home/{identity.name}": f"//{server}/Agents/{identity.name}",
        }

        return mounts


# HTTP API for provisioning service

import hmac

from fastapi import Depends, FastAPI, HTTPException
from fastapi.responses import JSONResponse
from fastapi.security import APIKeyHeader
from pydantic import BaseModel


class ProvisionRequest(BaseModel):
    agent_type: str
    vm_id: str
    requirements: Optional[Dict[str, Any]] = None


class ReleaseRequest(BaseModel):
    identity_name: str
    vm_id: str


def create_app(
    config: Optional[ProvisionerConfig] = None,
    credential_store: Optional[CredentialStore] = None,
    lease_store: Optional[LeaseStore] = None,
) -> FastAPI:
    """Create FastAPI app for provisioning service.

    Args:
        config: Provisioner configuration. If None, loads from environment.
        credential_store: Durable credential store. If None, creates a
            FileCredentialStore from config.credential_store_dir.
        lease_store: Identity lease store. If None, creates a SQLite
            lease store from config.database.uri.
    """
    if config is None:
        config = ProvisionerConfig.from_env()

    if not config.api_key:
        raise RuntimeError(
            "PROVISIONER_API_KEY is required. "
            "Set it in the environment before starting the service."
        )

    service = ProvisioningService(config)

    @asynccontextmanager
    async def _lifespan(_: FastAPI):
        await service.start()
        try:
            yield
        finally:
            await service.stop()

    application = FastAPI(title="Agent Provisioning Service", lifespan=_lifespan)

    # Durable one-time credential store (file-backed by default)
    if credential_store is None:
        credential_store = FileCredentialStore(config.credential_store_dir)
    service._credential_store = credential_store

    # DB-backed lease store (SQLite implementation).
    if lease_store is None:
        lease_store = SQLiteLeaseStore(config.database.uri)
    service._lease_store = lease_store

    _api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)

    async def require_api_key(
        api_key: Optional[str] = Depends(_api_key_header),
    ) -> str:
        if api_key is None or not hmac.compare_digest(api_key, config.api_key):
            raise HTTPException(status_code=403, detail="Invalid or missing API key")
        return api_key

    @application.post("/provision")
    async def provision(
        request: ProvisionRequest,
        _key: str = Depends(require_api_key),
    ):
        try:
            bundle = await service.provision_agent(
                agent_type=request.agent_type,
                vm_id=request.vm_id,
                requirements=request.requirements,
            )
            response = bundle.to_dict()

            # Extract ALL credential material from the response and store
            # it under a one-time reference. Nothing secret is returned inline.
            credential_ref = str(uuid4())
            if service._credential_store is None:
                raise RuntimeError("Credential store is not configured")

            credentials = {
                "agent_password": response.get("agent_credentials", {}).pop("password", None),
                "computer_otp": response.get("domain_join", {}).pop("computer_otp", None),
                "nats_password": response.get("nats", {}).pop("password", None),
                "nats_user_jwt": response.get("nats", {}).pop("user_jwt", None),
                "nats_nkey_seed": response.get("nats", {}).pop("nkey_seed", None),
            }
            # Avoid storing null placeholders when auth mode doesn't use them.
            credentials = {k: v for k, v in credentials.items() if v is not None}

            # Purge expired entries opportunistically.
            await service._credential_store.purge_expired()
            await service._credential_store.store(
                credential_ref,
                credentials,
                ttl=config.credential_ttl_seconds,
            )

            response["credential_ref"] = credential_ref
            return JSONResponse(
                content=response,
                headers={"Cache-Control": "no-store"},
            )
        except Exception:
            logger.exception(
                "Provisioning request failed (agent_type=%s vm_id=%s)",
                request.agent_type,
                request.vm_id,
            )
            raise HTTPException(status_code=500, detail="Provisioning failed")

    @application.delete("/credentials/{ref}")
    async def fetch_credentials(
        ref: UUID,
        _key: str = Depends(require_api_key),
    ):
        """Retrieve credentials exactly once. Returns the credential
        material and removes it from the store."""
        if service._credential_store is None:
            raise HTTPException(status_code=500, detail="Credential store not configured")

        ref_str = str(ref)
        await service._credential_store.purge_expired()

        creds = await service._credential_store.fetch_and_delete(ref_str)
        if creds is None:
            raise HTTPException(
                status_code=404,
                detail="Credential reference not found or expired",
            )

        return JSONResponse(
            content=creds,
            headers={"Cache-Control": "no-store"},
        )

    @application.post("/release")
    async def release(
        request: ReleaseRequest,
        _key: str = Depends(require_api_key),
    ):
        try:
            await service.release_agent(
                identity_name=request.identity_name,
                vm_id=request.vm_id,
            )
            return {"status": "released"}
        except Exception:
            logger.exception(
                "Release request failed (identity_name=%s vm_id=%s)",
                request.identity_name,
                request.vm_id,
            )
            raise HTTPException(status_code=500, detail="Release failed")

    @application.get("/agent/{identity_name}/config")
    async def get_config(
        identity_name: str,
        _key: str = Depends(require_api_key),
    ):
        try:
            cfg = await service.get_agent_config(identity_name)
            if not cfg:
                raise HTTPException(status_code=404, detail="Agent not found")
            return cfg
        except HTTPException:
            raise
        except Exception:
            logger.exception("Config request failed (identity_name=%s)", identity_name)
            raise HTTPException(status_code=500, detail="Config retrieval failed")

    @application.get("/health")
    async def health():
        return {"status": "healthy"}

    return application


# Module-level app for: uvicorn enterprise.provisioner.service:app
app = create_app()


if __name__ == "__main__":
    import uvicorn

    _config = ProvisionerConfig.from_env()
    uvicorn.run(app, host=_config.listen_address, port=_config.listen_port)
