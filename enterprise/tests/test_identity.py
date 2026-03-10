"""Tests for runtime identity normalization helpers."""

from enterprise.agent.identity import prepare_agent_identity


def test_prepare_agent_identity_maps_type_and_subjects_from_groups():
    config = {
        "agent": {
            "name": "claude-assistant-01",
            "type": "assistant",
            "groups": [
                "CN=Team-Engineering,OU=Groups,DC=autonomy,DC=local",
                "CN=Team-DataOps,OU=Groups,DC=autonomy,DC=local",
            ],
            "escalation_path": [
                "CN=Escalation-Coordinator,OU=Groups,DC=autonomy,DC=local",
            ],
        }
    }

    identity = prepare_agent_identity(config, escalation_path="escalations.team")

    assert identity["agent_type"] == "assistant"
    assert "type" not in identity
    assert sorted(identity["nats_subjects"]) == ["tasks.dataops", "tasks.engineering"]
    assert identity["escalation_path"] == "escalations.team"


def test_prepare_agent_identity_uses_existing_task_subjects_when_groups_missing():
    config = {
        "agent": {
            "name": "worker-01",
            "type": "autonomous",
            "groups": [],
            "nats_subjects": ["tasks.engineering", "events.agent.worker-01.heartbeat"],
            "escalation_path": "escalations.ops",
        }
    }

    identity = prepare_agent_identity(config)

    assert identity["agent_type"] == "autonomous"
    assert identity["nats_subjects"] == ["tasks.engineering"]
    assert identity["escalation_path"] == "escalations.ops"
