"""Credential store security tests."""

import stat

import pytest

from enterprise.provisioner.credential_store import FileCredentialStore


@pytest.mark.asyncio
async def test_store_enforces_secure_permissions(tmp_path):
    store = FileCredentialStore(str(tmp_path / "credentials"))
    await store.store("123e4567-e89b-12d3-a456-426614174000", {"secret": "value"})

    base_mode = stat.S_IMODE((tmp_path / "credentials").stat().st_mode)
    file_mode = stat.S_IMODE(
        (tmp_path / "credentials" / "123e4567-e89b-12d3-a456-426614174000.json").stat().st_mode
    )

    assert base_mode == 0o700
    assert file_mode == 0o600


@pytest.mark.asyncio
async def test_store_rejects_invalid_reference(tmp_path):
    store = FileCredentialStore(str(tmp_path / "credentials"))

    with pytest.raises(ValueError):
        await store.store("../bad", {"secret": "value"})

    assert await store.fetch_and_delete("../bad") is None
