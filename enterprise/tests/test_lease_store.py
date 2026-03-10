"""Tests for SQLite lease store."""

import time
from unittest.mock import patch

import pytest

from enterprise.provisioner.lease_store import SQLiteLeaseStore


@pytest.mark.asyncio
async def test_reserve_is_exclusive(tmp_path):
    store = SQLiteLeaseStore(f"sqlite:///{tmp_path}/leases.db")

    assert await store.reserve("worker-01", "vm-a", ttl_seconds=60) is True
    assert await store.reserve("worker-01", "vm-b", ttl_seconds=60) is False


@pytest.mark.asyncio
async def test_release_allows_reuse(tmp_path):
    store = SQLiteLeaseStore(f"sqlite:///{tmp_path}/leases.db")

    assert await store.reserve("worker-01", "vm-a", ttl_seconds=60) is True
    assert await store.release("worker-01", vm_id="vm-a") is True
    assert await store.reserve("worker-01", "vm-b", ttl_seconds=60) is True


@pytest.mark.asyncio
async def test_purge_expired_removes_stale_leases(tmp_path):
    store = SQLiteLeaseStore(f"sqlite:///{tmp_path}/leases.db")
    assert await store.reserve("worker-01", "vm-a", ttl_seconds=5) is True

    base_time = time.time()
    with patch("enterprise.provisioner.lease_store.time") as mock_time:
        mock_time.time.return_value = base_time + 30
        purged = await store.purge_expired()
        assert purged >= 1

    assert await store.reserve("worker-01", "vm-b", ttl_seconds=60) is True
