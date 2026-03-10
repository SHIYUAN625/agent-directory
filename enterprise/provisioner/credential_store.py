"""
Durable credential store for one-time credential vending.

Credentials are stored as individual JSON files with atomic writes.
TTL-based expiry ensures credentials don't accumulate. Each credential
can be fetched exactly once (fetch-and-delete), preventing replay.

Directory layout:
    {base_dir}/{ref}.json

Production upgrade path: swap FileCredentialStore for a Redis/Postgres
implementation behind the same CredentialStore protocol.
"""

import json
import logging
import os
import re
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, Optional, Protocol, runtime_checkable

logger = logging.getLogger(__name__)
_REF_PATTERN = re.compile(r"^[A-Za-z0-9-]{1,128}$")


@runtime_checkable
class CredentialStore(Protocol):
    """Protocol for credential persistence backends."""

    async def store(
        self, ref: str, credentials: Dict[str, Any], ttl: int = 300
    ) -> None:
        """Store credentials under a one-time reference.

        Args:
            ref: Unique reference ID (UUID).
            credentials: Credential material to store.
            ttl: Time-to-live in seconds.
        """
        ...

    async def fetch_and_delete(self, ref: str) -> Optional[Dict[str, Any]]:
        """Fetch credentials by reference and delete them.

        Returns the credential dict exactly once. Subsequent calls
        for the same ref return None. Also returns None if the
        credential has expired.
        """
        ...

    async def purge_expired(self) -> int:
        """Remove all expired entries. Returns count purged."""
        ...


class FileCredentialStore:
    """File-based durable credential store.

    Each credential reference maps to a single JSON file.
    Uses atomic writes (write to .tmp then rename) to prevent
    corruption on crash. TTL is embedded in the file and checked
    on fetch.
    """

    def __init__(self, base_dir: str = "/var/lib/provisioner/credentials"):
        self.base_dir = Path(base_dir)

    def _ensure_secure_dir(self) -> None:
        self.base_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        try:
            os.chmod(self.base_dir, 0o700)
        except OSError:
            logger.warning("Could not enforce mode 0700 on %s", self.base_dir)

    def _path_for_ref(self, ref: str) -> Path:
        if not _REF_PATTERN.fullmatch(ref):
            raise ValueError(f"Invalid credential reference: {ref!r}")
        return self.base_dir / f"{ref}.json"

    async def store(
        self, ref: str, credentials: Dict[str, Any], ttl: int = 300
    ) -> None:
        self._ensure_secure_dir()

        target = self._path_for_ref(ref)
        envelope = {
            "credentials": credentials,
            "created_at": time.time(),
            "ttl": ttl,
        }

        fd, tmp_path = tempfile.mkstemp(
            dir=str(self.base_dir), prefix=".cred-", suffix=".tmp"
        )
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "w") as f:
                json.dump(envelope, f)
            os.replace(tmp_path, str(target))
            os.chmod(target, 0o600)
            logger.debug("Credential ref %s stored", ref)
        except BaseException:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
            raise

    async def fetch_and_delete(self, ref: str) -> Optional[Dict[str, Any]]:
        try:
            target = self._path_for_ref(ref)
        except ValueError:
            return None

        if not target.exists():
            return None

        try:
            with open(target) as f:
                envelope = json.load(f)

            # Check TTL
            age = time.time() - envelope["created_at"]
            if age > envelope["ttl"]:
                target.unlink(missing_ok=True)
                logger.debug("Credential ref %s expired (age=%.0fs)", ref, age)
                return None

            # One-time fetch: delete after read
            target.unlink(missing_ok=True)
            return envelope["credentials"]
        except (json.JSONDecodeError, KeyError) as e:
            logger.error("Corrupt credential file %s: %s", target, e)
            target.unlink(missing_ok=True)
            return None

    async def purge_expired(self) -> int:
        if not self.base_dir.exists():
            return 0

        count = 0
        now = time.time()
        for path in self.base_dir.iterdir():
            if not path.name.endswith(".json"):
                continue
            try:
                with open(path) as f:
                    envelope = json.load(f)
                age = now - envelope["created_at"]
                if age > envelope["ttl"]:
                    path.unlink(missing_ok=True)
                    count += 1
            except (json.JSONDecodeError, KeyError, OSError):
                # Corrupt or unreadable — remove it
                try:
                    path.unlink(missing_ok=True)
                except OSError:
                    pass
                count += 1

        if count:
            logger.debug("Purged %d expired credential(s)", count)
        return count
