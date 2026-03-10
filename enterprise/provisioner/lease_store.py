"""
Database-backed identity lease store.

Leases prevent the same AD identity from being assigned to multiple VMs
at the same time. This implementation uses SQLite to provide transactional
reserve/release semantics without extra dependencies.
"""

import logging
import sqlite3
import time
from pathlib import Path
from typing import Optional, Protocol, runtime_checkable

logger = logging.getLogger(__name__)


@runtime_checkable
class LeaseStore(Protocol):
    """Protocol for identity lease backends."""

    async def reserve(self, identity_name: str, vm_id: str, ttl_seconds: int) -> bool:
        """Try to reserve an identity for a VM."""
        ...

    async def release(self, identity_name: str, vm_id: Optional[str] = None) -> bool:
        """Release an identity lease."""
        ...

    async def purge_expired(self) -> int:
        """Remove expired leases."""
        ...


class SQLiteLeaseStore:
    """SQLite-backed lease store.

    URI format:
      sqlite:////absolute/path/to/leases.db
      sqlite:///relative/path/to/leases.db
      sqlite:///:memory:
    """

    def __init__(self, uri: str):
        self.uri = uri
        self.db_path = self._parse_sqlite_uri(uri)
        if self.db_path != ":memory:":
            Path(self.db_path).parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    @staticmethod
    def _parse_sqlite_uri(uri: str) -> str:
        if uri == "sqlite:///:memory:":
            return ":memory:"
        if not uri.startswith("sqlite:///"):
            raise RuntimeError(
                f"Unsupported lease database URI '{uri}'. "
                "Use sqlite:///... for the lease store."
            )
        return uri[len("sqlite:///"):]

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self.db_path, timeout=10, isolation_level=None)

    def _init_db(self):
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS identity_leases (
                    identity_name TEXT PRIMARY KEY,
                    vm_id TEXT NOT NULL,
                    acquired_at INTEGER NOT NULL,
                    expires_at INTEGER NOT NULL
                )
                """
            )
            conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_identity_leases_expires_at "
                "ON identity_leases(expires_at)"
            )

    async def reserve(self, identity_name: str, vm_id: str, ttl_seconds: int) -> bool:
        now = int(time.time())
        expires_at = now + ttl_seconds

        with self._connect() as conn:
            try:
                conn.execute("BEGIN IMMEDIATE")
                conn.execute(
                    "DELETE FROM identity_leases WHERE expires_at <= ?",
                    (now,),
                )

                existing = conn.execute(
                    "SELECT vm_id FROM identity_leases WHERE identity_name = ?",
                    (identity_name,),
                ).fetchone()
                if existing:
                    # Idempotent refresh for same VM
                    if existing[0] == vm_id:
                        conn.execute(
                            "UPDATE identity_leases "
                            "SET acquired_at = ?, expires_at = ? "
                            "WHERE identity_name = ?",
                            (now, expires_at, identity_name),
                        )
                        conn.commit()
                        return True
                    conn.rollback()
                    return False

                conn.execute(
                    "INSERT INTO identity_leases(identity_name, vm_id, acquired_at, expires_at) "
                    "VALUES(?, ?, ?, ?)",
                    (identity_name, vm_id, now, expires_at),
                )
                conn.commit()
                return True
            except Exception:
                conn.rollback()
                raise

    async def release(self, identity_name: str, vm_id: Optional[str] = None) -> bool:
        with self._connect() as conn:
            if vm_id:
                cur = conn.execute(
                    "DELETE FROM identity_leases WHERE identity_name = ? AND vm_id = ?",
                    (identity_name, vm_id),
                )
            else:
                cur = conn.execute(
                    "DELETE FROM identity_leases WHERE identity_name = ?",
                    (identity_name,),
                )
            return cur.rowcount > 0

    async def purge_expired(self) -> int:
        now = int(time.time())
        with self._connect() as conn:
            cur = conn.execute(
                "DELETE FROM identity_leases WHERE expires_at <= ?",
                (now,),
            )
            return cur.rowcount
