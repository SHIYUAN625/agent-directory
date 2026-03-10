#!/usr/bin/env python3
"""Run a persistent EnterpriseAgent process using AD-backed identity."""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import signal
import subprocess
import sys
from typing import Any, Dict, List
from urllib.parse import urlparse, urlunparse

import nats

from enterprise.agent.base import EnterpriseAgent
from enterprise.agent.events import GenerationStep
from enterprise.agent.identity import prepare_agent_identity
from enterprise.agent.reactions import Finish
from enterprise.broker.config_assembler import ConfigAssembler
from enterprise.coordinator.service import MissionCoordinator

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("runtime-agent")


class RuntimeWorker(EnterpriseAgent):
    """Minimal worker runtime for team queues."""

    async def execute_step(self, task, step):
        description = task.payload.get("description") or f"task {task.task_type}"
        yield GenerationStep(
            step=step,
            model=self.identity.get("model", ""),
            content=f"Completed: {description}",
        )
        raise Finish(
            result={
                "status": "completed",
                "agent": self.agent_id,
                "task_type": task.task_type,
                "description": description,
            }
        )

    def get_tools(self):
        return []


class ScriptedLLMClient:
    """Deterministic coordinator backend for decomposition without external LLMs."""

    def __init__(self, route_teams: List[str]):
        self.route_teams = [team.strip().lower() for team in route_teams if team.strip()]
        if not self.route_teams:
            self.route_teams = ["engineering", "dataops"]

    async def generate(self, messages, system="", tools=None):
        prompt = ""
        if messages:
            prompt = messages[-1].get("content", "")
        low_prompt = prompt.lower()
        low_system = system.lower()

        if "decompose" in low_system or "decompose" in low_prompt:
            tasks = [
                {
                    "task_type": team,
                    "description": f"{team} workstream execution",
                    "priority": 500,
                }
                for team in self.route_teams
            ]
            return json.dumps(
                {
                    "approach": "Parallel execution by team",
                    "tasks": tasks,
                    "risks": [],
                    "requires_approval": False,
                }
            )

        if "escalation" in low_prompt:
            return json.dumps(
                {
                    "root_cause": "runtime worker failure",
                    "resolution_steps": ["collect context", "escalate to operators"],
                    "action": "escalate",
                }
            )

        if "review the progress" in low_prompt:
            return json.dumps(
                {
                    "overall_status": "active",
                    "blocked_goals": [],
                    "recommendations": ["continue execution"],
                }
            )

        return json.dumps(
            {
                "analysis": "handled",
                "actions": [],
                "result": "completed",
            }
        )


class StandaloneCoordinator(MissionCoordinator):
    """Coordinator runtime without provisioner-driven workforce orchestration."""

    async def start(self):
        await EnterpriseAgent.start(self)

    async def stop(self):
        await EnterpriseAgent.stop(self)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run EnterpriseAgent from AD identity")
    parser.add_argument("agent_name", help="Agent sAMAccountName (without trailing $)")
    parser.add_argument(
        "--mode",
        choices=["auto", "worker", "coordinator"],
        default="auto",
        help="Runtime mode. auto resolves from AD agent type.",
    )
    parser.add_argument(
        "--nats-url",
        default="",
        help="Explicit NATS URL (overrides role-based default)",
    )
    parser.add_argument(
        "--route-teams",
        default="engineering,dataops",
        help="Comma-separated teams for scripted coordinator decomposition",
    )
    parser.add_argument(
        "--escalation-path",
        default="escalations.team",
        help="Fallback escalation subject when AD path is not a NATS subject",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Assemble identity, print runtime config, and exit",
    )
    return parser.parse_args()


def _masked_nats_url(url: str) -> str:
    parsed = urlparse(url)
    if parsed.password is None:
        return url
    username = parsed.username or ""
    host = parsed.hostname or ""
    if parsed.port:
        host = f"{host}:{parsed.port}"
    netloc = f"{username}:***@{host}" if username else host
    return urlunparse((parsed.scheme, netloc, parsed.path, parsed.params, parsed.query, parsed.fragment))


def _kinit_agent(agent_name: str, realm: str, keytab_dir: str) -> str:
    keytab_path = os.path.join(keytab_dir, f"{agent_name}.keytab")
    principal = f"{agent_name}$@{realm}"
    ccache_path = f"/tmp/krb5cc_{agent_name}"
    env = os.environ.copy()
    env["KRB5CCNAME"] = ccache_path

    result = subprocess.run(
        ["kinit", "-kt", keytab_path, principal],
        env=env,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"kinit failed for {principal}: {result.stderr.strip()}")

    logger.info("Authenticated as %s", principal)
    return ccache_path


def _resolve_mode(requested_mode: str, identity: Dict[str, Any]) -> str:
    if requested_mode != "auto":
        return requested_mode
    if identity.get("agent_type") == "coordinator":
        return "coordinator"
    return "worker"


def _default_nats_url(mode: str) -> str:
    host = os.environ.get("NATS_HOST", "nats.autonomy.local:4222")
    if mode == "coordinator":
        username = "coordinator"
        password = os.environ.get("NATS_COORDINATOR_PASSWORD", "")
        env_name = "NATS_COORDINATOR_PASSWORD"
    else:
        username = "worker"
        password = os.environ.get("NATS_WORKER_PASSWORD", "")
        env_name = "NATS_WORKER_PASSWORD"

    if not password:
        raise RuntimeError(f"{env_name} is required when --nats-url is not provided")

    return f"nats://{username}:{password}@{host}"


def _build_config_assembler(agent_name: str) -> ConfigAssembler:
    ldap_uri = os.environ.get("AGENT_AD_LDAP_URI", "ldap://dc1.autonomy.local")
    base_dn = os.environ.get("AGENT_AD_BASE_DN", "DC=autonomy,DC=local")
    realm = base_dn.replace("DC=", "").replace(",", ".").upper()
    domain = realm.lower()
    keytab_dir = os.environ.get("AGENT_KEYTAB_DIR", "/mnt/samba/keytabs")
    sysvol_path = os.environ.get("AGENT_SYSVOL_PATH", f"/mnt/samba/sysvol/{domain}")
    tool_mapping_path = os.environ.get("AGENT_TOOL_MAPPING", "/opt/e2e-test/tool-mapping.json")

    ccache_path = _kinit_agent(agent_name, realm, keytab_dir)

    return ConfigAssembler(
        ldap_uri=ldap_uri,
        base_dn=base_dn,
        sysvol_path=sysvol_path,
        tool_mapping_path=tool_mapping_path,
        ccache_path=ccache_path,
    )


async def _run(args: argparse.Namespace) -> int:
    assembler = _build_config_assembler(args.agent_name)
    config = assembler.assemble(args.agent_name)
    identity = prepare_agent_identity(config, escalation_path=args.escalation_path)
    policy = config.get("policy", {})

    mode = _resolve_mode(args.mode, identity)
    nats_url = args.nats_url or _default_nats_url(mode)

    if args.dry_run:
        payload = {
            "mode": mode,
            "agent_name": identity.get("name"),
            "agent_type": identity.get("agent_type"),
            "nats_subjects": identity.get("nats_subjects", []),
            "escalation_path": identity.get("escalation_path"),
            "nats_url": _masked_nats_url(nats_url),
        }
        print(json.dumps(payload, indent=2))
        return 0

    logger.info(
        "Starting runtime agent=%s mode=%s subjects=%s nats=%s",
        identity.get("name"),
        mode,
        identity.get("nats_subjects", []),
        _masked_nats_url(nats_url),
    )

    nc = await nats.connect(nats_url)
    if mode == "coordinator":
        route_teams = [part for part in args.route_teams.split(",") if part.strip()]
        llm_client = ScriptedLLMClient(route_teams=route_teams)
        agent = StandaloneCoordinator(
            identity=identity,
            policy=policy,
            nats_client=nc,
            llm_client=llm_client,
        )
    else:
        agent = RuntimeWorker(
            identity=identity,
            policy=policy,
            nats_client=nc,
        )

    await agent.start()

    stop_event = asyncio.Event()
    loop = asyncio.get_running_loop()

    def _signal_stop():
        stop_event.set()

    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, _signal_stop)
        except NotImplementedError:
            # Windows fallback (not used in docker runtime).
            signal.signal(sig, lambda *_: _signal_stop())

    await stop_event.wait()

    logger.info("Stopping runtime agent=%s", identity.get("name"))
    await agent.stop()
    await nc.drain()
    return 0


def main() -> int:
    try:
        args = _parse_args()
        return asyncio.run(_run(args))
    except KeyboardInterrupt:
        return 130
    except Exception as exc:
        print(f"run-enterprise-agent failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
