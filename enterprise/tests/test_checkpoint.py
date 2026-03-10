"""Tests for checkpoint persistence (FileCheckpointStore)."""

import json
import os
import tempfile

import pytest

from enterprise.agent.checkpoint import FileCheckpointStore
from enterprise.agent.trajectory import Trajectory


@pytest.fixture
def checkpoint_dir(tmp_path):
    """Provide a temp directory for checkpoint storage."""
    return str(tmp_path / "checkpoints")


@pytest.fixture
def store(checkpoint_dir):
    return FileCheckpointStore(base_dir=checkpoint_dir)


def _sample_trajectory(agent_id: str = "test-agent", task_id: str = "task-001") -> Trajectory:
    t = Trajectory(agent_id=agent_id, task_id=task_id)
    t.add_generation(
        step_number=1,
        model="claude-sonnet-4-5-20250929",
        input_tokens=100,
        output_tokens=50,
        content="Hello world",
        tool_calls=[],
    )
    return t


@pytest.mark.asyncio
async def test_save_and_load(store, checkpoint_dir):
    """Save a trajectory checkpoint and load it back."""
    trajectory = _sample_trajectory()
    checkpoint_id = "ckpt-001"

    await store.save(
        checkpoint_id=checkpoint_id,
        task_id="task-001",
        agent_id="test-agent",
        data=trajectory.to_json(),
    )

    # Verify file was created
    expected_path = os.path.join(checkpoint_dir, "test-agent", f"{checkpoint_id}.json")
    assert os.path.exists(expected_path)

    # Load it back
    loaded_data = await store.load(checkpoint_id)
    assert loaded_data is not None

    loaded = Trajectory.from_json(loaded_data)
    assert loaded.agent_id == "test-agent"
    assert loaded.task_id == "task-001"
    assert loaded.step_count == 1
    assert loaded.usage.input_tokens == 100
    assert loaded.usage.output_tokens == 50


@pytest.mark.asyncio
async def test_load_missing_returns_none(store):
    """Loading a nonexistent checkpoint returns None."""
    result = await store.load("nonexistent-checkpoint-id")
    assert result is None


@pytest.mark.asyncio
async def test_load_missing_base_dir_returns_none(tmp_path):
    """If the base_dir doesn't exist at all, load returns None."""
    store = FileCheckpointStore(base_dir=str(tmp_path / "does-not-exist"))
    result = await store.load("anything")
    assert result is None


@pytest.mark.asyncio
async def test_atomic_write_no_leftover_tmp(store, checkpoint_dir):
    """After successful save, no .tmp files should remain."""
    trajectory = _sample_trajectory()

    await store.save(
        checkpoint_id="ckpt-atomic",
        task_id="task-001",
        agent_id="test-agent",
        data=trajectory.to_json(),
    )

    agent_dir = os.path.join(checkpoint_dir, "test-agent")
    for f in os.listdir(agent_dir):
        assert not f.endswith(".tmp"), f"Leftover tmp file: {f}"


@pytest.mark.asyncio
async def test_save_overwrites_existing(store, checkpoint_dir):
    """Saving with the same checkpoint_id overwrites the previous file."""
    t1 = _sample_trajectory()
    t2 = _sample_trajectory()
    t2.add_generation(
        step_number=2,
        model="claude-sonnet-4-5-20250929",
        input_tokens=200,
        output_tokens=100,
        content="Step 2",
        tool_calls=[],
    )

    checkpoint_id = "ckpt-overwrite"
    await store.save(checkpoint_id=checkpoint_id, task_id="task-001",
                     agent_id="test-agent", data=t1.to_json())
    await store.save(checkpoint_id=checkpoint_id, task_id="task-001",
                     agent_id="test-agent", data=t2.to_json())

    loaded_data = await store.load(checkpoint_id)
    loaded = Trajectory.from_json(loaded_data)
    assert loaded.step_count == 2


@pytest.mark.asyncio
async def test_checkpoint_file_is_valid_json(store, checkpoint_dir):
    """The stored file should be valid JSON with an envelope."""
    trajectory = _sample_trajectory()
    checkpoint_id = "ckpt-json"

    await store.save(
        checkpoint_id=checkpoint_id,
        task_id="task-001",
        agent_id="test-agent",
        data=trajectory.to_json(),
    )

    path = os.path.join(checkpoint_dir, "test-agent", f"{checkpoint_id}.json")
    with open(path) as f:
        envelope = json.load(f)

    assert envelope["checkpoint_id"] == checkpoint_id
    assert envelope["task_id"] == "task-001"
    assert envelope["agent_id"] == "test-agent"
    assert "trajectory" in envelope
    assert envelope["trajectory"]["agent_id"] == "test-agent"
