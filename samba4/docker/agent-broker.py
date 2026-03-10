#!/usr/bin/env python3
"""
Agent Runner — DC-enforced agent launcher.

Each agent authenticates as itself (Kerberos), reads its own config
from the DC via GSSAPI, and launches with a sealed config JSON.
No broker intermediary — DC ACLs enforce what the agent can see.

Flow:
1. kinit with agent's own keytab ({agent}$@REALM)
2. Assemble sealed config from LDAP/SYSVOL (agent's Kerberos ticket)
3. Write sealed config JSON
4. exec pwsh Start-AgentFromConfig.ps1

Usage:
    python3 agent-broker.py <agent-name> [--dry-run]
"""

import argparse
import json
import logging
import os
import signal
import subprocess
import sys

from enterprise.broker.config_assembler import ConfigAssembler

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [agent-runner] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)


def kinit_agent(keytab_path: str, principal: str, ccache_path: str) -> None:
    """Initialize Kerberos credentials from agent's own keytab."""
    env = os.environ.copy()
    env["KRB5CCNAME"] = ccache_path

    cmd = ["kinit", "-kt", keytab_path, principal]
    result = subprocess.run(cmd, env=env, capture_output=True, text=True)

    if result.returncode != 0:
        raise RuntimeError(f"kinit failed for {principal}: {result.stderr.strip()}")

    logger.info(f"Authenticated as {principal}")


def write_sealed_config(config: dict, agent_name: str, config_dir: str) -> str:
    """Write sealed config JSON to a file readable only by current user."""
    os.makedirs(config_dir, mode=0o700, exist_ok=True)
    config_path = os.path.join(config_dir, f"{agent_name}.json")

    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)

    os.chmod(config_path, 0o400)
    logger.info(f"Sealed config written to {config_path}")
    return config_path


def launch_agent(config_path: str, working_dir: str) -> subprocess.Popen:
    """Launch psh-agent via Start-AgentFromConfig.ps1."""
    launcher = "/opt/agent-launcher/Start-AgentFromConfig.ps1"

    cmd = ["pwsh", "-NoLogo", "-File", launcher, config_path]

    env = os.environ.copy()
    # Remove any LDAP credentials from environment
    env.pop("AGENT_AD_BIND_DN", None)
    env.pop("AGENT_AD_PASSWORD", None)

    logger.info(f"Launching agent with config: {config_path}")
    return subprocess.Popen(
        cmd,
        env=env,
        cwd=working_dir,
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Agent Runner — DC-enforced agent launcher",
    )
    parser.add_argument(
        "agent_name",
        help="Agent sAMAccountName (without trailing $)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Assemble config and print it without launching",
    )

    args = parser.parse_args()
    agent_name = args.agent_name

    # Derive config from environment / defaults
    ldap_uri = os.environ.get("AGENT_AD_LDAP_URI", "ldap://dc1.autonomy.local")
    base_dn = os.environ.get("AGENT_AD_BASE_DN", "DC=autonomy,DC=local")
    realm = base_dn.replace("DC=", "").replace(",", ".").upper()
    domain = realm.lower()
    keytab_dir = "/mnt/samba/keytabs"
    sysvol_path = os.environ.get("AGENT_SYSVOL_PATH", f"/mnt/samba/sysvol/{domain}")
    working_dir = os.environ.get("AGENT_WORKING_DIR", "/workspace")
    tool_mapping_path = os.environ.get("AGENT_TOOL_MAPPING", "/opt/agent-launcher/tool-mapping.json")

    agent_keytab = os.path.join(keytab_dir, f"{agent_name}.keytab")
    agent_principal = f"{agent_name}$@{realm}"
    ccache_path = f"/tmp/krb5cc_{agent_name}"
    config_dir = "/run/agent-config"

    # Step 1: Authenticate as the agent itself
    logger.info(f"=== Agent Runner for: {agent_name} ===")
    kinit_agent(agent_keytab, agent_principal, ccache_path)

    # Step 2: Assemble config from LDAP/SYSVOL using agent's own ticket
    logger.info("Assembling agent configuration from DC...")
    assembler = ConfigAssembler(
        ldap_uri=ldap_uri,
        base_dn=base_dn,
        sysvol_path=sysvol_path,
        tool_mapping_path=tool_mapping_path,
        ccache_path=ccache_path,
    )

    try:
        config = assembler.assemble(agent_name)
    except RuntimeError as e:
        logger.error(f"Config assembly failed: {e}")
        return 1

    # Dry run: print config and exit
    if args.dry_run:
        print("\n========================================")
        print("DRY RUN — assembled config:")
        print("========================================\n")
        print(json.dumps(config, indent=2))
        return 0

    # Step 3: Write sealed config
    config_path = write_sealed_config(config, agent_name, config_dir)

    # Step 4: Launch psh-agent
    agent_proc = launch_agent(config_path, working_dir)

    # Step 5: Wait for agent to exit
    try:
        exit_code = agent_proc.wait()
        logger.info(f"Agent exited with code: {exit_code}")
    except KeyboardInterrupt:
        logger.info("Interrupted — stopping agent...")
        agent_proc.send_signal(signal.SIGTERM)
        try:
            agent_proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            agent_proc.kill()
        exit_code = 130

    # Clean up config
    try:
        os.unlink(config_path)
    except OSError:
        pass

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
