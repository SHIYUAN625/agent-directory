"""Shared fixtures for enterprise tests."""

import os
import pytest
import pytest_asyncio

# Ensure PROVISIONER_API_KEY is set before any import of service.py
# (module-level app = create_app() runs on import)
os.environ.setdefault("PROVISIONER_API_KEY", "test-secret-key")

from httpx import ASGITransport, AsyncClient

from enterprise.provisioner.config import DatabaseConfig, LDAPConfig, NATSConfig, ProvisionerConfig
from enterprise.provisioner.identity import AgentIdentity, SandboxIdentity
from enterprise.provisioner.policy import MergedPolicy


TEST_API_KEY = "test-secret-key"


def _make_test_config(**overrides) -> ProvisionerConfig:
    """Create a ProvisionerConfig suitable for testing."""
    defaults = dict(
        api_key=TEST_API_KEY,
        ldap=LDAPConfig(
            uri="ldaps://localhost",
            base_dn="DC=test,DC=local",
            bind_dn="CN=admin,DC=test,DC=local",
            bind_pw="password",
        ),
        nats=NATSConfig(
            servers=["nats://localhost:4222"],
            auth_mode="password",
            user="provisioner",
            password="test-provisioner-pw",
            agent_passwords={
                "worker": "test-worker-pw",
                "coordinator": "test-coordinator-pw",
                "analyst": "test-analyst-pw",
            },
        ),
        database=DatabaseConfig(uri="sqlite:///./test-leases.db", lease_ttl_seconds=300),
    )
    defaults.update(overrides)
    return ProvisionerConfig(**defaults)


def _make_agent_identity(name: str = "worker-01") -> AgentIdentity:
    return AgentIdentity(
        name=name,
        dn=f"CN={name}$,CN=Agents,CN=System,DC=test,DC=local",
        sid="S-1-5-21-0-0-0-1001",
        principal=f"{name}$@TEST.LOCAL",
        agent_type="worker",
        trust_level=3,
    )


def _make_merged_policy() -> MergedPolicy:
    return MergedPolicy()


class FakeLDAPClient:
    """Minimal fake that satisfies ProvisioningService's LDAP needs."""

    def __init__(self):
        self._agents = [
            _make_agent_identity("worker-01"),
            _make_agent_identity("worker-02"),
        ]

    async def ping(self) -> bool:
        return True

    def search_agents(self, agent_type=None, name=None):
        results = list(self._agents)
        if agent_type:
            results = [a for a in results if a.agent_type == agent_type]
        if name:
            results = [a for a in results if a.name == name]
        return results

    def get_agent(self, name):
        for a in self._agents:
            if a.name == name:
                return a
        return None

    def set_password(self, dn, password):
        return True

    def create_computer(self, name, container_dn, password):
        return True

    def delete_computer(self, name, container_dn):
        return True

    async def get_policy(self, dn):
        return None


class FakePolicyLoader:
    """Returns a default MergedPolicy for any agent."""

    async def load_policies_for_agent(self, **kwargs):
        return _make_merged_policy()


@pytest.fixture
def test_config():
    return _make_test_config()


@pytest_asyncio.fixture
async def provisioner_app(test_config, tmp_path):
    """Create a FastAPI app with fake LDAP backend and file-backed credential store.

    httpx's ASGITransport does NOT fire FastAPI startup/shutdown events,
    so we manually inject the fake LDAP client and policy loader into
    the ProvisioningService after create_app(). The credential store
    is injected cleanly via create_app's credential_store parameter.
    """
    from enterprise.provisioner.credential_store import FileCredentialStore
    from enterprise.provisioner.service import create_app

    test_config.database.uri = f"sqlite:///{tmp_path}/leases.db"
    cred_store = FileCredentialStore(str(tmp_path / "credentials"))
    app = create_app(config=test_config, credential_store=cred_store)

    # Find the ProvisioningService instance by walking route closures
    # and inject fake LDAP/policy backends.
    for route in app.routes:
        if hasattr(route, "endpoint") and hasattr(route.endpoint, "__closure__"):
            for cell in (route.endpoint.__closure__ or []):
                try:
                    obj = cell.cell_contents
                    from enterprise.provisioner.service import ProvisioningService
                    if isinstance(obj, ProvisioningService):
                        obj._ldap_client = FakeLDAPClient()
                        obj._policy_loader = FakePolicyLoader()
                        obj._running = True
                        yield app
                        return
                except (ValueError, TypeError):
                    continue

    # Fallback: if we can't find the service, yield the app anyway
    # (tests will fail with a clear error)
    yield app


@pytest_asyncio.fixture
async def async_client(provisioner_app):
    """httpx AsyncClient bound to the test FastAPI app."""
    transport = ASGITransport(app=provisioner_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client
