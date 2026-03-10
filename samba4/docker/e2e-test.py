#!/usr/bin/env python3
"""
End-to-End Coordination Test

Tests the full flow: agent authenticates via Kerberos → reads config from AD →
connects to NATS → coordinator decomposes a task → workers execute → results
flow back → escalation path works → events are observable.

Organizational model:
  - AD groups define the org structure (Team-* groups = work queues)
  - NATS subjects are derived FROM group membership, not hardcoded
  - Coordinator routes work to teams, not individuals
  - Within a team, agents compete for work via JetStream work queues
  - Individual agents bring different skillsets (tools, trust level, model)

Phases:
  1. Identity & Config Assembly (kinit + ConfigAssembler for each agent)
  2. NATS Connectivity & Stream Setup (team-based streams)
  3. Single-Agent Task Execution (subjects derived from AD groups)
  4. Multi-Agent Coordination (coordinator decomposes → teams execute)
  5. Escalation Flow (failing worker → escalation published)
  6. Event Stream Verification
"""

import asyncio
import json
import logging
import os
import subprocess
import sys
from uuid import uuid4

import nats
from nats.js.api import StreamConfig, RetentionPolicy

from enterprise.agent.base import EnterpriseAgent
from enterprise.agent.events import GenerationStep, AgentStart, AgentEnd
from enterprise.agent.reactions import Finish, Fail
from enterprise.agent.identity import prepare_agent_identity
from enterprise.agent.routing import (
    team_groups_to_subjects,
    get_team_names,
    ensure_stream,
    TEAM_GROUP_PREFIX,
)
from enterprise.agent.task import Task, TaskResult, TaskStatus
from enterprise.broker.config_assembler import ConfigAssembler
from enterprise.coordinator.service import MissionCoordinator

logging.basicConfig(
    level=logging.WARNING,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("e2e")
logger.setLevel(logging.INFO)

# ---------------------------------------------------------------------------
# Test infrastructure
# ---------------------------------------------------------------------------

PASS_COUNT = 0
FAIL_COUNT = 0
ERRORS = []


def pass_check(desc):
    global PASS_COUNT
    PASS_COUNT += 1
    print(f"  PASS: {desc}", flush=True)


def fail_check(desc, error=None):
    global FAIL_COUNT
    FAIL_COUNT += 1
    msg = f"  FAIL: {desc}"
    if error:
        msg += f" ({error})"
    ERRORS.append(msg)
    print(msg, flush=True)


def check(desc, condition, error=None):
    if condition:
        pass_check(desc)
    else:
        fail_check(desc, error)


# ---------------------------------------------------------------------------
# Mock agent subclasses
# ---------------------------------------------------------------------------

class MockWorker(EnterpriseAgent):
    """Worker that immediately completes any task."""

    async def execute_step(self, task, step):
        desc = task.payload.get("description", "unknown")
        yield GenerationStep(step=step, model="mock", content=f"Processing: {desc}")
        raise Finish(result=f"completed: {desc}")

    def get_tools(self):
        return []


class FailingWorker(EnterpriseAgent):
    """Worker that always fails with escalation."""

    async def execute_step(self, task, step):
        yield GenerationStep(step=step, model="mock", content="Failing...")
        raise Fail(error="permission denied")
        # Fail.escalate defaults to True

    def get_tools(self):
        return []


class MockCoordinator(MissionCoordinator):
    """
    Coordinator with deterministic task decomposition.

    Routes work to teams by name — the same team names that appear as
    AD groups (Team-Engineering, Team-DataOps) and derive NATS subjects
    (tasks.engineering, tasks.dataops).

    Fixes for real MissionCoordinator design gaps:
    - Sets llm_client=True so _decompose_goal takes the LLM branch
    - Overrides _llm_decompose to return deterministic JSON
    - Overrides execute_step to raise Finish after decomposition
      (real _decompose_goal returns normally, causing infinite loop)
    - Overrides start() to skip WorkforceManager/EscalationHandler
      (they need provisioner HTTP, add noise to E2E test)
    """

    def __init__(self, identity, policy, nats_client=None):
        super().__init__(
            identity=identity,
            policy=policy,
            nats_client=nats_client,
            llm_client=True,  # Bug #5: must be truthy for decomposition
        )

    async def start(self):
        """Skip WorkforceManager and EscalationHandler -- just subscribe."""
        if self.nc:
            self.js = self.nc.jetstream()
        self.running = True
        for subject in self.nats_subjects:
            parts = subject.split(".")
            if len(parts) < 2:
                continue
            asyncio.create_task(self._process_queue(subject))

    async def execute_step(self, task, step):
        """
        Bug #4 fix: _decompose_goal never raises Finish, so the
        _execute_task loop would run to max_iterations. Override to
        run decomposition once then signal completion.
        """
        if task.task_type == "goal_decomposition":
            async for event in self._decompose_goal(task, step):
                yield event
            raise Finish(result={"decomposition": "complete"})
        else:
            yield GenerationStep(step=step, content=f"Unhandled: {task.task_type}")
            raise Finish(result="skipped")

    async def _llm_decompose(self, prompt):
        """
        Deterministic decomposition -- routes work to teams.

        task_type values match the team-derived NATS subjects:
          "engineering" → tasks.engineering (Team-Engineering queue)
          "dataops"     → tasks.dataops     (Team-DataOps queue)
        """
        return json.dumps({
            "approach": "Parallel execution across teams",
            "tasks": [
                {
                    "task_type": "engineering",
                    "description": "review the code",
                    "priority": 500,
                },
                {
                    "task_type": "dataops",
                    "description": "process the dataset",
                    "priority": 500,
                },
            ],
            "risks": [],
            "requires_approval": False,
        })

    def get_tools(self):
        return []


# ---------------------------------------------------------------------------
# Phase implementations
# ---------------------------------------------------------------------------

async def phase1_identity(configs: dict):
    """Phase 1: Identity & Config Assembly."""
    print("\n--- Phase 1: Identity & Config Assembly ---", flush=True)

    agents = {
        "claude-assistant-01": {
            "type": "assistant",
            "trust_level": 2,
            "model": "claude-opus-4-5",
            "expected_tools": ["filesystem.read", "filesystem.write", "git.cli",
                               "python.interpreter", "llm.inference"],
            "expected_team": "Team-Engineering",
        },
        "data-processor-01": {
            "type": "autonomous",
            "trust_level": 2,
            "model": "claude-sonnet-4",
            "expected_tools": ["filesystem.read", "filesystem.write",
                               "python.interpreter", "database.postgresql",
                               "database.redis", "jq.processor", "api.http",
                               "llm.inference", "nats.client"],
            "expected_team": "Team-DataOps",
        },
        "coordinator-main": {
            "type": "coordinator",
            "trust_level": 3,
            "model": "claude-opus-4-5",
            "expected_tools": ["filesystem.read", "git.cli", "llm.inference",
                               "agent.spawn", "agent.delegate", "nats.client",
                               "ldap.search", "ray.submit", "ray.status"],
            "expected_team": "Team-Coordination",
        },
    }

    ldap_uri = os.environ.get("AGENT_AD_LDAP_URI", "ldap://dc1.autonomy.local")
    base_dn = os.environ.get("AGENT_AD_BASE_DN", "DC=autonomy,DC=local")
    sysvol_path = os.environ.get("AGENT_SYSVOL_PATH",
                                 "/mnt/samba/sysvol/autonomy.local")

    for name, expected in agents.items():
        # kinit with per-agent ccache
        keytab = f"/mnt/samba/keytabs/{name}.keytab"
        ccache = f"/tmp/krb5cc_{name}"
        env = {**os.environ, "KRB5CCNAME": ccache}
        result = subprocess.run(
            ["kinit", "-kt", keytab, f"{name}$@AUTONOMY.LOCAL"],
            env=env, capture_output=True, text=True,
        )
        check(f"kinit {name}", result.returncode == 0, result.stderr.strip())

        if result.returncode != 0:
            fail_check(f"config assembly {name}", "skipped (kinit failed)")
            continue

        # Assemble config
        try:
            assembler = ConfigAssembler(
                ldap_uri=ldap_uri,
                base_dn=base_dn,
                sysvol_path=sysvol_path,
                tool_mapping_path="/opt/e2e-test/tool-mapping.json",
                ccache_path=ccache,
            )
            config = assembler.assemble(name)
            check(f"config assembly {name}", True)
        except Exception as e:
            fail_check(f"config assembly {name}", str(e))
            continue

        # Verify identity fields
        identity = config["agent"]
        check(f"{name} type={expected['type']}",
              identity.get("type") == expected["type"],
              f"got {identity.get('type')}")
        check(f"{name} trust_level={expected['trust_level']}",
              identity.get("trust_level") == expected["trust_level"],
              f"got {identity.get('trust_level')}")
        check(f"{name} model={expected['model']}",
              identity.get("model") == expected["model"],
              f"got {identity.get('model')}")

        # Verify individual skillset (tools)
        authorized = config["tools"]["authorized_ids"]
        check(f"{name} tools non-empty", len(authorized) > 0)
        for tool_id in expected["expected_tools"]:
            check(f"{name} has tool {tool_id}", tool_id in authorized,
                  f"authorized={authorized}")

        # Verify team membership (AD group → NATS routing)
        groups = identity.get("groups", [])
        group_cns = [dn.split(",")[0].replace("CN=", "") for dn in groups]
        check(f"{name} member of {expected['expected_team']}",
              expected["expected_team"] in group_cns,
              f"groups={group_cns}")

        # Verify team → subject derivation
        team_subjects = team_groups_to_subjects(groups)
        expected_subject = f"tasks.{expected['expected_team'][len(TEAM_GROUP_PREFIX):].lower()}"
        check(f"{name} team subject={expected_subject}",
              expected_subject in team_subjects,
              f"derived={team_subjects}")

        # System prompt
        check(f"{name} system_prompt contains '# Agent Identity'",
              "# Agent Identity" in config.get("system_prompt", ""))

        # Policy
        check(f"{name} policy has content",
              bool(config.get("policy")))

        configs[name] = config


async def phase2_nats(nc, configs: dict):
    """Phase 2: NATS Connectivity & Stream Setup.

    Streams are derived from AD group membership — not hardcoded.
    Each Team-* group in AD gets a corresponding JetStream work queue.
    Adding a new team group to AD automatically creates a new stream.
    """
    print("\n--- Phase 2: NATS Connectivity & Streams ---", flush=True)

    check("NATS connected", nc.is_connected)

    js = nc.jetstream()

    # --- Discover teams from assembled configs ---
    # Scan all agents' group memberships to find every Team-* group.
    # This is the same data that prepare_agent_identity() uses for routing,
    # so streams and subscriptions are guaranteed to align.
    discovered_teams = set()
    for config in configs.values():
        groups = config["agent"].get("groups", [])
        for team in get_team_names(groups):
            discovered_teams.add(team)

    check("discovered teams from AD",
          len(discovered_teams) > 0,
          f"found: {discovered_teams}")

    # --- Create a task stream per team ---
    # Each stream captures both the base subject and wildcard:
    #   tasks.engineering     — coordinator publishes here
    #   tasks.engineering.>   — agent-specific routing if needed
    streams = []
    for team in sorted(discovered_teams):
        team_lower = team.lower()
        streams.append(StreamConfig(
            name=f"TASKS_{team.upper()}",
            subjects=[f"tasks.{team_lower}", f"tasks.{team_lower}.>"],
            retention=RetentionPolicy.WORK_QUEUE,
        ))

    # Escalation test stream (not an AD team — used by Phase 5)
    streams.append(StreamConfig(
        name="TASKS_FAILTEST",
        subjects=["tasks.failtest", "tasks.failtest.>"],
        retention=RetentionPolicy.WORK_QUEUE,
    ))

    # Infrastructure streams (always present)
    streams.extend([
        StreamConfig(
            name="ESCALATIONS",
            subjects=["escalations.>"],
            retention=RetentionPolicy.WORK_QUEUE,
        ),
        StreamConfig(
            name="EVENTS",
            subjects=["events.>"],
            retention=RetentionPolicy.LIMITS,
        ),
        StreamConfig(
            name="RESULTS",
            subjects=["results.>"],
            retention=RetentionPolicy.LIMITS,
        ),
    ])

    for sc in streams:
        try:
            await js.add_stream(sc)
            check(f"stream {sc.name} created", True)
        except Exception as e:
            fail_check(f"stream {sc.name} created", str(e))

    # Verify team-based routing for each discovered team
    for team in sorted(discovered_teams):
        team_lower = team.lower()
        stream_name = f"TASKS_{team.upper()}"
        try:
            found = await js.find_stream_name_by_subject(f"tasks.{team_lower}")
            check(f"tasks.{team_lower} routes to {stream_name}",
                  found == stream_name, f"got {found}")
        except Exception as e:
            fail_check(f"tasks.{team_lower} routes to {stream_name}", str(e))


async def phase3_single_agent(nc, configs: dict):
    """Phase 3: Single-Agent Task Execution.

    Workers derive their NATS subjects from AD group membership.
    Team-Engineering → tasks.engineering, Team-DataOps → tasks.dataops.
    """
    print("\n--- Phase 3: Single-Agent Task Execution ---", flush=True)

    js = nc.jetstream()
    workers = []

    # --- Engineering team worker (claude-assistant-01) ---
    if "claude-assistant-01" in configs:
        identity = prepare_agent_identity(
            configs["claude-assistant-01"],
            escalation_path="escalations.team",
        )
        # Verify subjects were derived from team group
        check("claude-assistant-01 subscribed to tasks.engineering",
              "tasks.engineering" in identity.get("nats_subjects", []),
              f"subjects={identity.get('nats_subjects')}")

        worker = MockWorker(
            identity=identity,
            policy=configs["claude-assistant-01"]["policy"],
            nats_client=nc,
        )
        await worker.start()
        check("worker claude-assistant-01 started", worker.running)
        workers.append(worker)

        # Subscribe to results BEFORE publishing task
        result_future = asyncio.get_event_loop().create_future()

        async def on_eng_result(msg):
            if not result_future.done():
                result_future.set_result(msg.data)

        sub = await nc.subscribe("results.test-engineering", cb=on_eng_result)

        # Publish task to engineering team queue
        task1 = Task(
            task_type="engineering",
            payload={"description": "write unit tests"},
            reply_to="results.test-engineering",
        )
        await js.publish("tasks.engineering", task1.to_json())

        try:
            raw = await asyncio.wait_for(result_future, timeout=15.0)
            result = TaskResult.from_json(raw)
            check("engineering task result received", True)
            check("engineering task status=completed",
                  result.status == TaskStatus.COMPLETED)
            check("engineering task result contains description",
                  "write unit tests" in str(result.result))
        except asyncio.TimeoutError:
            fail_check("engineering task result received", "timeout after 15s")

        await sub.unsubscribe()
    else:
        fail_check("worker claude-assistant-01 started",
                    "config not assembled")

    # --- DataOps team worker (data-processor-01) ---
    if "data-processor-01" in configs:
        identity = prepare_agent_identity(
            configs["data-processor-01"],
            escalation_path="escalations.team",
        )
        check("data-processor-01 subscribed to tasks.dataops",
              "tasks.dataops" in identity.get("nats_subjects", []),
              f"subjects={identity.get('nats_subjects')}")

        worker = MockWorker(
            identity=identity,
            policy=configs["data-processor-01"]["policy"],
            nats_client=nc,
        )
        await worker.start()
        check("worker data-processor-01 started", worker.running)
        workers.append(worker)

        result_future2 = asyncio.get_event_loop().create_future()

        async def on_data_result(msg):
            if not result_future2.done():
                result_future2.set_result(msg.data)

        sub2 = await nc.subscribe("results.test-dataops", cb=on_data_result)

        # Publish task to dataops team queue
        task2 = Task(
            task_type="dataops",
            payload={"description": "process ETL pipeline"},
            reply_to="results.test-dataops",
        )
        await js.publish("tasks.dataops", task2.to_json())

        try:
            raw = await asyncio.wait_for(result_future2, timeout=15.0)
            result = TaskResult.from_json(raw)
            check("dataops task result received", True)
            check("dataops task status=completed",
                  result.status == TaskStatus.COMPLETED)
            check("dataops task result contains description",
                  "process ETL pipeline" in str(result.result))
        except asyncio.TimeoutError:
            fail_check("dataops task result received", "timeout after 15s")

        await sub2.unsubscribe()
    else:
        fail_check("worker data-processor-01 started",
                    "config not assembled")

    return workers


async def phase4_coordination(nc, configs: dict, workers: list):
    """Phase 4: Multi-Agent Coordination.

    Coordinator decomposes a goal into tasks routed to teams.
    _create_worker_task publishes to tasks.{task_type}:
      task_type="engineering" → tasks.engineering (Team-Engineering)
      task_type="dataops"     → tasks.dataops     (Team-DataOps)
    Workers from Phase 3 are still subscribed to their team queues.
    """
    print("\n--- Phase 4: Multi-Agent Coordination ---", flush=True)

    if "coordinator-main" not in configs:
        fail_check("coordinator started", "config not assembled")
        return None

    js = nc.jetstream()

    # Coordinator subscribes to its own team queue (Team-Coordination)
    coord_identity = prepare_agent_identity(
        configs["coordinator-main"],
        escalation_path="escalations.human",
    )
    check("coordinator subscribed to tasks.coordination",
          "tasks.coordination" in coord_identity.get("nats_subjects", []),
          f"subjects={coord_identity.get('nats_subjects')}")

    coord_policy = dict(configs["coordinator-main"]["policy"])
    coord_policy.setdefault("execution", {})["max_iterations"] = 5

    coordinator = MockCoordinator(
        identity=coord_identity,
        policy=coord_policy,
        nats_client=nc,
    )
    await coordinator.start()
    check("coordinator started", coordinator.running)

    # Subscribe to results.> BEFORE publishing goal
    worker_results = []
    results_ready = asyncio.Event()

    async def collect_result(msg):
        worker_results.append(msg.data)
        if len(worker_results) >= 2:
            results_ready.set()

    results_sub = await nc.subscribe("results.>", cb=collect_result)

    # Subscribe to coordination result
    coord_result_future = asyncio.get_event_loop().create_future()

    async def on_coord_result(msg):
        if not coord_result_future.done():
            coord_result_future.set_result(msg.data)

    coord_reply = f"results.coordination.{uuid4()}"
    coord_result_sub = await nc.subscribe(coord_reply, cb=on_coord_result)

    # Publish goal_decomposition task to coordination team queue
    goal_task = Task(
        task_type="goal_decomposition",
        payload={
            "goal": {
                "title": "E2E Test Goal",
                "description": "Test multi-agent coordination across teams",
                "constraints": [],
                "success_criteria": ["All team subtasks complete"],
                "context": {},
            }
        },
        reply_to=coord_reply,
    )
    await js.publish("tasks.coordination", goal_task.to_json())

    # Wait for coordinator to complete (it decomposes + raises Finish)
    try:
        raw = await asyncio.wait_for(coord_result_future, timeout=20.0)
        coord_result = TaskResult.from_json(raw)
        check("coordinator completed decomposition",
              coord_result.status == TaskStatus.COMPLETED)
    except asyncio.TimeoutError:
        fail_check("coordinator completed decomposition", "timeout after 20s")

    # Wait for worker results (coordinator publishes to tasks.engineering and
    # tasks.dataops, team members process and reply to results.{goal.id})
    try:
        await asyncio.wait_for(results_ready.wait(), timeout=20.0)
        check(f"received {len(worker_results)} worker results",
              len(worker_results) >= 2)
        for raw_result in worker_results:
            r = TaskResult.from_json(raw_result)
            check(f"worker result status=completed (agent={r.agent_id})",
                  r.status == TaskStatus.COMPLETED)
    except asyncio.TimeoutError:
        fail_check(f"worker results (got {len(worker_results)}/2)",
                   "timeout after 20s")

    await results_sub.unsubscribe()
    await coord_result_sub.unsubscribe()

    return coordinator


async def phase5_escalation(nc):
    """Phase 5: Escalation Flow."""
    print("\n--- Phase 5: Escalation ---", flush=True)

    js = nc.jetstream()

    # Subscribe to escalations BEFORE starting worker
    escalation_future = asyncio.get_event_loop().create_future()

    async def on_escalation(msg):
        if not escalation_future.done():
            escalation_future.set_result(msg.data)

    esc_sub = await nc.subscribe("escalations.>", cb=on_escalation)

    # Create failing worker (hardcoded identity — not from AD, testing the
    # escalation path itself rather than organizational routing)
    fail_identity = {
        "name": "fail-worker-01",
        "agent_type": "autonomous",
        "trust_level": 1,
        "model": "mock",
        "mission": "always fail",
        "audit_level": 0,
        "nats_subjects": ["tasks.failtest.test"],
        "escalation_path": "escalations.team",
    }
    fail_policy = {
        "execution": {
            "max_iterations": 5,
            "checkpoint_interval_steps": 100,
        }
    }

    fail_worker = FailingWorker(
        identity=fail_identity,
        policy=fail_policy,
        nats_client=nc,
    )
    await fail_worker.start()

    # Publish task
    fail_task = Task(
        task_type="failtest",
        payload={"description": "this should fail"},
        reply_to="results.failtest",
    )
    await js.publish("tasks.failtest.test", fail_task.to_json())

    # Wait for escalation
    try:
        raw = await asyncio.wait_for(escalation_future, timeout=15.0)
        esc_data = json.loads(raw.decode())
        check("escalation received", True)
        check("escalation error='permission denied'",
              esc_data.get("error") == "permission denied")
        check("escalation source=fail-worker-01",
              esc_data.get("agent_id") == "fail-worker-01")
    except asyncio.TimeoutError:
        fail_check("escalation received", "timeout after 15s")

    await esc_sub.unsubscribe()
    return fail_worker


async def phase6_events(nc):
    """Phase 6: Event Stream Verification."""
    print("\n--- Phase 6: Event Stream ---", flush=True)

    js = nc.jetstream()

    # Read events from the EVENTS stream via ordered consumer
    try:
        events_sub = await js.subscribe("events.>", ordered_consumer=True)
    except Exception as e:
        fail_check("events stream subscription", str(e))
        return

    collected_events = []
    try:
        while True:
            msg = await asyncio.wait_for(events_sub.next_msg(), timeout=3.0)
            try:
                event_data = json.loads(msg.data.decode())
                collected_events.append(event_data)
            except (json.JSONDecodeError, UnicodeDecodeError):
                pass
    except (asyncio.TimeoutError, Exception):
        pass  # No more messages

    check(f"events collected ({len(collected_events)} total)",
          len(collected_events) > 0)

    # Check for AgentStart events
    starts = [e for e in collected_events if e.get("_type") == "AgentStart"]
    check(f"AgentStart events found ({len(starts)})", len(starts) > 0)

    # Check for AgentEnd events
    ends = [e for e in collected_events if e.get("_type") == "AgentEnd"]
    check(f"AgentEnd events found ({len(ends)})", len(ends) > 0)

    # Verify events have correct agent IDs
    known_agents = {
        "claude-assistant-01", "data-processor-01",
        "coordinator-main", "fail-worker-01",
    }
    event_agents = {
        e.get("agent_id") for e in collected_events if e.get("agent_id")
    }
    check("events contain known agent IDs",
          len(event_agents & known_agents) > 0,
          f"found: {event_agents}")

    await events_sub.unsubscribe()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def main():
    print("=" * 55, flush=True)
    print("=== End-to-End Coordination Test ===", flush=True)
    print(f"Domain: {os.environ.get('SAMBA_REALM', 'AUTONOMY.LOCAL')}", flush=True)
    print(f"NATS:   {os.environ.get('NATS_URL', 'nats://nats.autonomy.local:4222')}",
          flush=True)
    print("=" * 55, flush=True)

    configs = {}

    # Phase 1: Identity & Config Assembly
    await phase1_identity(configs)

    if not configs:
        print("\nFATAL: No configs assembled, cannot continue", flush=True)
        sys.exit(1)

    # Connect to NATS
    nats_url = os.environ.get("NATS_URL", "nats://nats.autonomy.local:4222")
    try:
        nc = await nats.connect(nats_url)
    except Exception as e:
        fail_check("NATS connection", str(e))
        print("\nFATAL: Cannot connect to NATS, cannot continue", flush=True)
        sys.exit(1)

    try:
        # Phase 2: NATS Connectivity & Stream Setup (derived from AD groups)
        await phase2_nats(nc, configs)

        # Phase 3: Single-Agent Task Execution
        workers = await phase3_single_agent(nc, configs)

        # Phase 4: Multi-Agent Coordination
        coordinator = await phase4_coordination(nc, configs, workers)

        # Phase 5: Escalation Flow
        fail_worker = await phase5_escalation(nc)

        # Brief pause for events to propagate to EVENTS stream
        await asyncio.sleep(1)

        # Phase 6: Event Stream Verification
        await phase6_events(nc)

        # Cleanup: stop all agents
        all_agents = list(workers or [])
        if coordinator:
            all_agents.append(coordinator)
        if fail_worker:
            all_agents.append(fail_worker)

        for agent in all_agents:
            try:
                await agent.stop()
            except Exception:
                pass

    finally:
        await nc.close()

    # Summary
    print(flush=True)
    print("=" * 55, flush=True)
    color = "\033[32m" if FAIL_COUNT == 0 else "\033[31m"
    reset = "\033[0m"
    print(f"{color}Results: {PASS_COUNT} passed, {FAIL_COUNT} failed{reset}",
          flush=True)
    print("=" * 55, flush=True)

    if ERRORS:
        print("\nFailures:", flush=True)
        for e in ERRORS:
            print(f"  {e}", flush=True)

    sys.exit(1 if FAIL_COUNT > 0 else 0)


if __name__ == "__main__":
    asyncio.run(main())
