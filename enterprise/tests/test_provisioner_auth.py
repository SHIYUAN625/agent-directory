"""Tests for provisioner API authentication."""

import pytest
from enterprise.provisioner.config import ProvisionerConfig
from .conftest import TEST_API_KEY


def _find_provisioning_service(app):
    from enterprise.provisioner.service import ProvisioningService

    for route in app.routes:
        endpoint = getattr(route, "endpoint", None)
        closure = getattr(endpoint, "__closure__", None)
        for cell in (closure or []):
            try:
                obj = cell.cell_contents
            except ValueError:
                continue
            if isinstance(obj, ProvisioningService):
                return obj
    raise RuntimeError("ProvisioningService not found in app routes")


@pytest.mark.asyncio
async def test_provision_without_key_returns_403(async_client):
    resp = await async_client.post("/provision", json={
        "agent_type": "worker",
        "vm_id": "vm-001",
    })
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_provision_with_wrong_key_returns_403(async_client):
    resp = await async_client.post(
        "/provision",
        json={"agent_type": "worker", "vm_id": "vm-001"},
        headers={"X-API-Key": "wrong-key"},
    )
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_provision_with_correct_key_succeeds(async_client):
    resp = await async_client.post(
        "/provision",
        json={"agent_type": "worker", "vm_id": "vm-001"},
        headers={"X-API-Key": TEST_API_KEY},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "identity" in data
    assert "credential_ref" in data


@pytest.mark.asyncio
async def test_release_requires_key(async_client):
    resp = await async_client.post("/release", json={
        "identity_name": "worker-01",
        "vm_id": "vm-001",
    })
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_release_with_key_succeeds(async_client):
    resp = await async_client.post(
        "/release",
        json={"identity_name": "worker-01", "vm_id": "vm-001"},
        headers={"X-API-Key": TEST_API_KEY},
    )
    assert resp.status_code == 200


@pytest.mark.asyncio
async def test_agent_config_requires_key(async_client):
    resp = await async_client.get("/agent/worker-01/config")
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_agent_config_with_key_succeeds(async_client):
    resp = await async_client.get(
        "/agent/worker-01/config",
        headers={"X-API-Key": TEST_API_KEY},
    )
    assert resp.status_code == 200


@pytest.mark.asyncio
async def test_health_no_key_required(async_client):
    resp = await async_client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "healthy"}


def test_missing_api_key_refuses_startup():
    """create_app with empty api_key should raise RuntimeError."""
    from enterprise.provisioner.service import create_app

    config = ProvisionerConfig(api_key="")
    with pytest.raises(RuntimeError, match="PROVISIONER_API_KEY"):
        create_app(config=config)


@pytest.mark.asyncio
async def test_provision_internal_error_is_sanitized(
    async_client,
    provisioner_app,
    monkeypatch,
):
    service = _find_provisioning_service(provisioner_app)

    async def _boom(*args, **kwargs):
        raise RuntimeError("internal secret: do-not-leak")

    monkeypatch.setattr(service, "provision_agent", _boom)

    resp = await async_client.post(
        "/provision",
        json={"agent_type": "worker", "vm_id": "vm-001"},
        headers={"X-API-Key": TEST_API_KEY},
    )
    assert resp.status_code == 500
    assert resp.json()["detail"] == "Provisioning failed"
    assert "do-not-leak" not in resp.text
