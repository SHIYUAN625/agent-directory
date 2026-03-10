"""NATS auth mode generation tests."""

import pytest

from enterprise.provisioner.config import NATSConfig, ProvisionerConfig
from enterprise.provisioner.identity import AgentIdentity
from enterprise.provisioner.policy import MergedPolicy
from enterprise.provisioner.service import ProvisioningService


def _identity(agent_type: str = "worker") -> AgentIdentity:
    return AgentIdentity(
        name="worker-01",
        dn="CN=worker-01$,CN=Agents,CN=System,DC=test,DC=local",
        sid="S-1-5-21-test",
        principal="worker-01$@TEST.LOCAL",
        agent_type=agent_type,
        trust_level=2,
    )


@pytest.mark.asyncio
async def test_generate_nats_credentials_password_mode():
    config = ProvisionerConfig(
        api_key="test",
        nats=NATSConfig(
            auth_mode="password",
            servers=["nats://localhost:4222"],
            agent_passwords={"worker": "worker-secret"},
        ),
    )
    service = ProvisioningService(config)

    creds = await service._generate_nats_credentials(_identity(), MergedPolicy())
    assert creds["auth_mode"] == "password"
    assert creds["user"] == "worker"
    assert creds["password"] == "worker-secret"


@pytest.mark.asyncio
async def test_generate_nats_credentials_jwt_mode():
    config = ProvisionerConfig(
        api_key="test",
        nats=NATSConfig(
            auth_mode="jwt",
            servers=["nats://localhost:4222"],
            agent_user_jwts={"worker": "worker.jwt.token"},
            agent_nkey_seeds={"worker": "SUATESTWORKERSEED1234567890"},
        ),
    )
    service = ProvisioningService(config)

    creds = await service._generate_nats_credentials(_identity(), MergedPolicy())
    assert creds["auth_mode"] == "jwt"
    assert creds["user"] == "worker-01"
    assert creds["user_jwt"] == "worker.jwt.token"
    assert creds["nkey_seed"] == "SUATESTWORKERSEED1234567890"
