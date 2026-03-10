"""Tests for DB-backed identity leasing semantics."""

import pytest

from .conftest import TEST_API_KEY


HEADERS = {"X-API-Key": TEST_API_KEY}


@pytest.mark.asyncio
async def test_provision_uses_unique_identity_leases(async_client):
    """Two concurrent allocations should not reuse the same identity."""
    first = await async_client.post(
        "/provision",
        json={"agent_type": "worker", "vm_id": "vm-001"},
        headers=HEADERS,
    )
    second = await async_client.post(
        "/provision",
        json={"agent_type": "worker", "vm_id": "vm-002"},
        headers=HEADERS,
    )

    assert first.status_code == 200
    assert second.status_code == 200

    first_identity = first.json()["identity"]["name"]
    second_identity = second.json()["identity"]["name"]
    assert first_identity != second_identity


@pytest.mark.asyncio
async def test_provision_fails_when_all_matching_identities_are_leased(async_client):
    """If all worker identities are leased, next request should fail."""
    # We have two worker identities in FakeLDAPClient.
    for vm_id in ("vm-001", "vm-002"):
        resp = await async_client.post(
            "/provision",
            json={"agent_type": "worker", "vm_id": vm_id},
            headers=HEADERS,
        )
        assert resp.status_code == 200

    third = await async_client.post(
        "/provision",
        json={"agent_type": "worker", "vm_id": "vm-003"},
        headers=HEADERS,
    )
    assert third.status_code == 500
    assert third.json()["detail"] == "Provisioning failed"


@pytest.mark.asyncio
async def test_release_frees_lease_for_reuse(async_client):
    """Releasing an identity should make it leasable again."""
    first = await async_client.post(
        "/provision",
        json={"agent_type": "worker", "vm_id": "vm-001"},
        headers=HEADERS,
    )
    assert first.status_code == 200
    first_identity = first.json()["identity"]["name"]

    released = await async_client.post(
        "/release",
        json={"identity_name": first_identity, "vm_id": "vm-001"},
        headers=HEADERS,
    )
    assert released.status_code == 200

    reprovision = await async_client.post(
        "/provision",
        json={"agent_type": "worker", "vm_id": "vm-004"},
        headers=HEADERS,
    )
    assert reprovision.status_code == 200
    assert reprovision.json()["identity"]["name"] == first_identity
