"""
Checkpoint persistence for agent trajectory recovery.

Provides a CheckpointStore protocol and a file-based implementation.
Agents checkpoint their trajectory periodically so they can resume
after a crash without replaying the entire execution history.
"""

import json
import logging
import os
import tempfile
from pathlib import Path
from typing import Optional, Protocol, runtime_checkable

logger = logging.getLogger(__name__)


@runtime_checkable
class CheckpointStore(Protocol):
    """Protocol for checkpoint persistence backends."""

    async def save(
        self,
        checkpoint_id: str,
        task_id: str,
        agent_id: str,
        data: str,
    ) -> None:
        """Save a checkpoint.

        Args:
            checkpoint_id: Unique checkpoint identifier.
            task_id: Task being checkpointed.
            agent_id: Agent that owns the checkpoint.
            data: Serialized trajectory JSON.
        """
        ...

    async def load(self, checkpoint_id: str) -> Optional[str]:
        """Load a checkpoint by ID.

        Returns:
            Serialized trajectory JSON, or None if not found.
        """
        ...


class FileCheckpointStore:
    """File-based checkpoint store.

    Writes trajectory JSON to files under a configurable base directory.
    Uses atomic writes (write to .tmp, then rename) to avoid corruption
    on crash during write.

    Directory layout:
        {base_dir}/{agent_id}/{checkpoint_id}.json
    """

    def __init__(self, base_dir: str = "/var/lib/agent/checkpoints"):
        self.base_dir = Path(base_dir)

    async def save(
        self,
        checkpoint_id: str,
        task_id: str,
        agent_id: str,
        data: str,
    ) -> None:
        agent_dir = self.base_dir / agent_id
        agent_dir.mkdir(parents=True, exist_ok=True)

        target = agent_dir / f"{checkpoint_id}.json"

        # Atomic write: write to temp file in the same directory, then rename.
        # os.rename is atomic on POSIX when src and dst are on the same filesystem.
        fd, tmp_path = tempfile.mkstemp(
            dir=str(agent_dir), prefix=".ckpt-", suffix=".tmp"
        )
        try:
            with os.fdopen(fd, "w") as f:
                # Wrap with metadata for easier debugging
                envelope = {
                    "checkpoint_id": checkpoint_id,
                    "task_id": task_id,
                    "agent_id": agent_id,
                    "trajectory": json.loads(data),
                }
                json.dump(envelope, f)

            os.rename(tmp_path, str(target))
            logger.debug("Checkpoint %s saved to %s", checkpoint_id, target)
        except BaseException:
            # Clean up temp file on any failure
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
            raise

    async def load(self, checkpoint_id: str) -> Optional[str]:
        # We don't know the agent_id at load time, so search all agent dirs
        if not self.base_dir.exists():
            return None

        for agent_dir in self.base_dir.iterdir():
            if not agent_dir.is_dir():
                continue
            target = agent_dir / f"{checkpoint_id}.json"
            if target.exists():
                try:
                    with open(target) as f:
                        envelope = json.load(f)
                    # Return just the trajectory data as JSON string
                    return json.dumps(envelope["trajectory"])
                except (json.JSONDecodeError, KeyError) as e:
                    logger.error(
                        "Corrupt checkpoint file %s: %s", target, e
                    )
                    return None

        return None
