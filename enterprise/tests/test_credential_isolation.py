"""Tests for credential vending / isolation."""

import time
from unittest.mock import patch

import pytest

from .conftest import TEST_API_KEY


HEADERS = {"X-API-Key": TEST_API_KEY}


@pytest.mark.asyncio
async def test_provision_response_has_no_plaintext_password(async_client):
    """The /provision response must not contain any plaintext secrets."""
    resp = await async_client.post(
        "/provision",
        json={"agent_type": "worker", "vm_id": "vm-001"},
        headers=HEADERS,
    )
    assert resp.status_code == 200
    data = resp.json()

    # agent_credentials should exist but NOT have 'password'
    agent_creds = data.get("agent_credentials", {})
    assert "password" not in agent_creds
    assert "principal" in agent_creds

    # domain_join should NOT have 'computer_otp'
    domain_join = data.get("domain_join", {})
    assert "computer_otp" not in domain_join

    # nats should NOT have inline secrets
    nats_creds = data.get("nats", {})
    assert "password" not in nats_creds
    assert "user_jwt" not in nats_creds
    assert "nkey_seed" not in nats_creds
    assert "user" in nats_creds
    assert nats_creds.get("auth_mode") == "password"
    assert resp.headers.get("cache-control") == "no-store"


@pytest.mark.asyncio
async def test_provision_response_has_credential_ref(async_client):
    resp = await async_client.post(
        "/provision",
        json={"agent_type": "worker", "vm_id": "vm-001"},
        headers=HEADERS,
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "credential_ref" in data
    assert len(data["credential_ref"]) == 36  # UUID format


@pytest.mark.asyncio
async def test_credential_ref_returns_credentials_once(async_client):
    """DELETE /credentials/{ref} returns the credentials exactly once."""
    # Provision to get a credential_ref
    resp = await async_client.post(
        "/provision",
        json={"agent_type": "worker", "vm_id": "vm-001"},
        headers=HEADERS,
    )
    ref = resp.json()["credential_ref"]

    # Fetch credentials
    cred_resp = await async_client.delete(
        f"/credentials/{ref}",
        headers=HEADERS,
    )
    assert cred_resp.status_code == 200

    creds = cred_resp.json()
    assert "agent_password" in creds
    assert creds["agent_password"] is not None
    assert "computer_otp" in creds
    assert creds["computer_otp"] is not None
    assert "nats_password" in creds
    assert creds["nats_password"] is not None
    assert len(creds["nats_password"]) > 0
    assert "nats_user_jwt" not in creds
    assert "nats_nkey_seed" not in creds

    # Verify Cache-Control header
    assert cred_resp.headers.get("cache-control") == "no-store"


@pytest.mark.asyncio
async def test_credential_ref_second_fetch_returns_404(async_client):
    """Second fetch of the same credential_ref should 404."""
    resp = await async_client.post(
        "/provision",
        json={"agent_type": "worker", "vm_id": "vm-001"},
        headers=HEADERS,
    )
    ref = resp.json()["credential_ref"]

    # First fetch — success
    first = await async_client.delete(f"/credentials/{ref}", headers=HEADERS)
    assert first.status_code == 200

    # Second fetch — gone
    second = await async_client.delete(f"/credentials/{ref}", headers=HEADERS)
    assert second.status_code == 404


@pytest.mark.asyncio
async def test_credential_ref_requires_api_key(async_client):
    """DELETE /credentials/{ref} requires API key."""
    resp = await async_client.post(
        "/provision",
        json={"agent_type": "worker", "vm_id": "vm-001"},
        headers=HEADERS,
    )
    ref = resp.json()["credential_ref"]

    # Try without key
    cred_resp = await async_client.delete(f"/credentials/{ref}")
    assert cred_resp.status_code == 403


@pytest.mark.asyncio
async def test_nonexistent_credential_ref_returns_404(async_client):
    resp = await async_client.delete(
        "/credentials/00000000-0000-0000-0000-000000000000",
        headers=HEADERS,
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_expired_credential_ref_returns_404(async_client):
    """Credentials older than TTL should be purged and return 404."""
    resp = await async_client.post(
        "/provision",
        json={"agent_type": "worker", "vm_id": "vm-001"},
        headers=HEADERS,
    )
    ref = resp.json()["credential_ref"]

    # The FileCredentialStore uses time.time() for TTL checks.
    # Patch it in the credential_store module to simulate expiry.
    real_time = time.time()

    with patch("enterprise.provisioner.credential_store.time") as mock_time:
        # Return a time 600 seconds in the future (beyond default TTL of 300s)
        mock_time.time.return_value = real_time + 600

        cred_resp = await async_client.delete(
            f"/credentials/{ref}",
            headers=HEADERS,
        )
        assert cred_resp.status_code == 404
