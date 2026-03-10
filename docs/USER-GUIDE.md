# Agent Directory User Guide

A practical guide for developers and operators who deploy and run AI agents managed by the Agent Directory. This guide covers the Samba4/Docker deployment path (the primary dev/test path) and how agents work at runtime.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Understanding the Architecture](#understanding-the-architecture)
3. [Running Agents](#running-agents)
4. [Sample Agents](#sample-agents)
5. [Creating Your Own Agents](#creating-your-own-agents)
6. [Customizing Agent Behavior](#customizing-agent-behavior)
7. [Tool Mapping](#tool-mapping)
8. [Verification and Testing](#verification-and-testing)
9. [Troubleshooting](#troubleshooting)
10. [Environment Reset](#environment-reset)
11. [Next Steps](#next-steps)

---

## Getting Started

### Prerequisites

| Component | Requirement |
|-----------|-------------|
| Docker | Docker Desktop or Docker Engine with Compose v2 |
| make | GNU Make (pre-installed on macOS and most Linux distributions) |
| Platform | `linux/amd64` (the DC image runs under emulation on Apple Silicon) |
| Disk | ~2 GB for the DC image + volumes |

Optional for running agents:

| Component | Requirement |
|-----------|-------------|
| ANTHROPIC_API_KEY | API key exported in your shell |

### Setup Steps

```bash
cd samba4/docker
cp .env.example .env
```

Edit `.env` and set a strong password for `SAMBA_ADMIN_PASSWORD`. The other values have working defaults:

```
SAMBA_DOMAIN=AUTONOMY
SAMBA_REALM=AUTONOMY.LOCAL
SAMBA_ADMIN_PASSWORD=YourStrongPassword123!
SAMBA_DNS_FORWARDER=8.8.8.8
```

Start the domain controller:

```bash
make up
```

This builds the Docker image and starts the container. On first boot, the entrypoint script provisions the AD domain, installs the custom schema, creates sample agents, sets up ACLs, and generates Kerberos keytabs. This takes roughly 60--90 seconds.

Watch the logs and wait for the bootstrap to finish:

```bash
make logs
```

You are looking for this line:

```
[HH:MM:SS] Bootstrap complete
```

Once the bootstrap is complete, Samba restarts in the foreground and the DC is ready. Verify that the sample agents were created:

```bash
make list-agents
```

Expected output:

```
dn: CN=claude-assistant-01$,CN=Agents,CN=System,DC=autonomy,DC=local
cn: claude-assistant-01$
x-agent-Type: assistant
x-agent-TrustLevel: 2
x-agent-Model: claude-opus-4-5

dn: CN=data-processor-01$,CN=Agents,CN=System,DC=autonomy,DC=local
cn: data-processor-01$
x-agent-Type: autonomous
x-agent-TrustLevel: 2
x-agent-Model: claude-sonnet-4

dn: CN=coordinator-main$,CN=Agents,CN=System,DC=autonomy,DC=local
cn: coordinator-main$
x-agent-Type: coordinator
x-agent-TrustLevel: 3
x-agent-Model: claude-opus-4-5
```

---

## Understanding the Architecture

### What the DC Stores

The domain controller is the single source of truth for agent identity and configuration. Each agent is a user object in Active Directory with the `x-agent` auxiliary class attached. The DC stores:

- **Identity** -- agent name, type, trust level, model, mission statement
- **Tool grants** -- DN references to tool objects in `CN=Agent Tools,CN=System`
- **Policy links** -- DN references to policy objects in `CN=Agent Policies,CN=System`
- **Instruction GPOs** -- DN references to instruction GPO objects in `CN=Agent Instructions,CN=System`; the instruction content (markdown) lives in SYSVOL
- **Kerberos credentials** -- machine account password, SPN, keytab

### How Agents Authenticate

Agents authenticate as themselves using Kerberos. Each agent has a keytab file containing its machine account credentials (`agent-name$@AUTONOMY.LOCAL`). At launch, the agent runner calls `kinit` with the keytab to obtain a Kerberos ticket, then uses GSSAPI to authenticate LDAP reads against the DC. The DC's ACLs enforce what each agent is allowed to see.

This is not a broker model -- there is no privileged intermediary reading on behalf of agents. The agent's own Kerberos identity is the one making LDAP queries, and the DC enforces access control directly.

### Config Assembly Flow

When you run an agent, the `agent-broker.py` script orchestrates the full launch sequence:

```
make run-agent AGENT=claude-assistant-01
         |
         v
agent-broker.py
  1. kinit as claude-assistant-01$@AUTONOMY.LOCAL
     (uses /mnt/samba/keytabs/claude-assistant-01.keytab)
  2. LDAP reads via GSSAPI (DC authenticates agent)
     - Read agent identity (type, trust, model, mission, ...)
     - Resolve tool DNs -> tool identifiers
     - Resolve policy DNs -> policy JSON from SYSVOL
     - Resolve instruction GPO DNs -> markdown from SYSVOL
  3. ConfigAssembler merges everything:
     agent attrs + tools + policies + GPOs -> sealed config
  4. Writes sealed config JSON to /run/agent-config/{name}.json
     (mode 0400 -- read-only, current user only)
  5. exec pwsh Start-AgentFromConfig.ps1
     (agent runtime receives config, no LDAP access needed)
```

The ConfigAssembler (`enterprise/broker/config_assembler.py`) does the heavy lifting. It walks the LDAP tree starting from the agent object, resolves every linked tool, policy, and instruction GPO, reads their content from SYSVOL, maps AD tool identifiers to runtime tool names (via `tool-mapping.json`), merges policies by priority, and assembles the system prompt from instruction GPOs sorted by priority.

The sealed config JSON contains everything the agent runtime needs: identity, system prompt, tool configuration, merged policy, and connection string. Once written, the agent runtime operates without any LDAP access.

---

## Running Agents

### Launching an Agent

To launch an agent against the running DC:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
make run-agent AGENT=claude-assistant-01
```

This builds the agent runner container (if not already built), authenticates as the agent, assembles the config from the DC, and starts the agent runtime.

### Dry Run

To see what the assembled config looks like without actually launching the agent:

```bash
make dry-run AGENT=claude-assistant-01
```

This prints the full sealed config JSON to stdout. The output includes:

- **`agent`** -- identity block (name, type, trust level, model, mission, groups, NATS subjects, escalation path, LLM quota)
- **`system_prompt`** -- the merged system prompt from all instruction GPOs, including the identity header and tool authorization summary
- **`tools`** -- authorized tool IDs, denied tool IDs, enabled built-in tools, command prefixes, shell access flag
- **`policy`** -- merged policy from all linked policies (tool denials, execution limits, LLM limits, audit settings)
- **`connection_string`** -- provider/model string (e.g., `anthropic/claude-opus-4-5`)
- **`max_steps`** -- execution limit from merged policy

Example dry-run output (abbreviated):

```json
{
  "version": 1,
  "agent": {
    "name": "claude-assistant-01",
    "type": "assistant",
    "trust_level": 2,
    "model": "claude-opus-4-5",
    "mission": "General-purpose coding assistant for engineering team",
    ...
  },
  "system_prompt": "# Agent Identity\n\n- **Name:** claude-assistant-01\n...",
  "tools": {
    "authorized_ids": ["filesystem.read", "filesystem.write", "git.cli", ...],
    "enabled_builtin_tools": ["grep", "list_directory", "read_file", ...],
    ...
  },
  "policy": { ... },
  "connection_string": "anthropic/claude-opus-4-5",
  "max_steps": 50
}
```

### Environment Variables

The agent runner container uses these environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `ANTHROPIC_API_KEY` | (required) | API key for the LLM provider |
| `AGENT_AD_LDAP_URI` | `ldap://dc1.autonomy.local` | LDAP URI for the DC |
| `AGENT_AD_BASE_DN` | `DC=autonomy,DC=local` | LDAP base DN |
| `AGENT_SYSVOL_PATH` | `/mnt/samba/sysvol/autonomy.local` | Path to mounted SYSVOL |
| `AGENT_TOOL_MAPPING` | `/opt/agent-launcher/tool-mapping.json` | Path to tool mapping file |
| `AGENT_WORKING_DIR` | `/workspace` | Working directory for the agent |

These are set in `docker-compose.yml` for the `agent` service and do not need to be changed for the default dev environment.

### Shell Access

To get a shell inside the agent runner container (useful for debugging):

```bash
make agent-shell
```

This drops you into a PowerShell session inside the agent container with the SYSVOL volume mounted read-only at `/mnt/samba`.

---

## Sample Agents

The bootstrap creates three pre-provisioned agents with different roles, trust levels, and configurations.

### claude-assistant-01

| Property | Value |
|----------|-------|
| Type | `assistant` |
| Trust Level | 2 (Standard) |
| Model | `claude-opus-4-5` |
| Mission | General-purpose coding assistant for engineering team |
| Instruction GPOs | `base-agent-instructions` (priority 0), `type-assistant-instructions` (priority 100) |
| Policies | `base-security`, `base-behavior`, `base-resource`, `type-worker` |
| Tools | `filesystem.read`, `filesystem.write`, `git.cli`, `python.interpreter`, `llm.inference` |
| Groups | `Tier1-Workers`, `ToolAccess-Development` |
| NATS Subjects | `tasks.assistant.claude-assistant-01`, `escalations.team.engineering` |
| Escalation Path | `coordinator-main` |

### data-processor-01

| Property | Value |
|----------|-------|
| Type | `autonomous` |
| Trust Level | 2 (Standard) |
| Model | `claude-sonnet-4` |
| Mission | Autonomous data pipeline processor and ETL agent |
| Instruction GPOs | `base-agent-instructions` (priority 0), `type-autonomous-instructions` (priority 100) |
| Policies | `base-security`, `base-behavior`, `base-resource`, `type-worker` |
| Tools | `filesystem.read`, `filesystem.write`, `python.interpreter`, `database.postgresql`, `database.redis`, `jq.processor`, `api.http`, `llm.inference`, `nats.client` |
| Groups | `Tier1-Workers`, `ToolAccess-Development`, `ToolAccess-Network` |
| NATS Subjects | `tasks.data.pipeline`, `tasks.data.etl` |
| Escalation Path | `coordinator-main` |

### coordinator-main

| Property | Value |
|----------|-------|
| Type | `coordinator` |
| Trust Level | 3 (Elevated) |
| Model | `claude-opus-4-5` |
| Mission | Primary coordinator for multi-agent task orchestration |
| Instruction GPOs | `base-agent-instructions` (priority 0), `type-coordinator-instructions` (priority 100), `trust-elevated-instructions` (priority 200) |
| Policies | `base-security`, `base-behavior`, `base-resource`, `type-coordinator`, `trust-elevated` |
| Tools | `filesystem.read`, `git.cli`, `llm.inference`, `agent.spawn`, `agent.delegate`, `nats.client`, `ldap.search`, `ray.submit`, `ray.status` |
| Groups | `Tier3-Coordinators`, `ToolAccess-Management` |
| NATS Subjects | `tasks.coordination`, `escalations.all`, `system.health` |
| Escalation Path | (none -- top of hierarchy) |

---

## Creating Your Own Agents

### Quick Create

The Makefile wraps `agent-manager` for the most common operation:

```bash
make create-agent NAME=my-agent TYPE=assistant TRUST=2
```

This creates the user account, moves it to the `CN=Agents` container, adds the `x-agent` class, and sets the type, trust level, and a default model.

Available agent types: `autonomous`, `assistant`, `tool`, `orchestrator`, `coordinator`

Trust levels: `0` (Untrusted), `1` (Basic), `2` (Standard), `3` (Elevated), `4` (System)

You can optionally specify a model:

```bash
make create-agent NAME=my-agent TYPE=assistant TRUST=2 MODEL=claude-sonnet-4
```

### Grant Tools

After creating an agent, grant it the tools it needs:

```bash
make grant-tool AGENT=my-agent TOOL=filesystem.read
make grant-tool AGENT=my-agent TOOL=filesystem.write
make grant-tool AGENT=my-agent TOOL=git.cli
make grant-tool AGENT=my-agent TOOL=python.interpreter
make grant-tool AGENT=my-agent TOOL=llm.inference
```

To see what tools are available:

```bash
make list-tools
```

### Link Policies

Link policies to control the agent's behavior:

```bash
make link-policy AGENT=my-agent POLICY=base-security
make link-policy AGENT=my-agent POLICY=base-behavior
make link-policy AGENT=my-agent POLICY=base-resource
make link-policy AGENT=my-agent POLICY=type-worker
```

To see what policies are available:

```bash
make list-policies
```

### Link Instruction GPOs

Link instruction GPOs to define the agent's system prompt:

```bash
make link-gpo AGENT=my-agent GPO=base-agent-instructions
make link-gpo AGENT=my-agent GPO=type-assistant-instructions
```

To see what instruction GPOs are available:

```bash
make list-instructions
```

### Full Walkthrough Example

Here is a complete example creating a code review agent from scratch:

```bash
# 1. Create the agent
make create-agent NAME=code-reviewer TYPE=assistant TRUST=2 MODEL=claude-sonnet-4

# 2. Grant tools (read files, use git, run python for linting)
make grant-tool AGENT=code-reviewer TOOL=filesystem.read
make grant-tool AGENT=code-reviewer TOOL=git.cli
make grant-tool AGENT=code-reviewer TOOL=python.interpreter
make grant-tool AGENT=code-reviewer TOOL=llm.inference

# 3. Link base policies
make link-policy AGENT=code-reviewer POLICY=base-security
make link-policy AGENT=code-reviewer POLICY=base-behavior
make link-policy AGENT=code-reviewer POLICY=base-resource
make link-policy AGENT=code-reviewer POLICY=type-worker

# 4. Link instruction GPOs
make link-gpo AGENT=code-reviewer GPO=base-agent-instructions
make link-gpo AGENT=code-reviewer GPO=type-assistant-instructions

# 5. Verify the agent was created correctly
make get-agent AGENT=code-reviewer

# 6. Dry-run to see the assembled config
make dry-run AGENT=code-reviewer

# 7. Launch it (requires ANTHROPIC_API_KEY)
export ANTHROPIC_API_KEY=sk-ant-...
make run-agent AGENT=code-reviewer
```

Note that `make create-agent` runs `agent-manager agent create` inside the DC container. It handles creating the user account with the `$` suffix, moving it to the Agents container, adding the `x-agent` objectClass, and setting the specified attributes. The keytab is generated as part of the creation process so the agent can authenticate immediately.

---

## Customizing Agent Behavior

### How Instruction GPOs Work

Instruction GPOs are the primary mechanism for defining what an agent should do. They follow the Active Directory Group Policy pattern: metadata is stored in AD, and the actual content (markdown system prompts) is stored in SYSVOL.

Each instruction GPO has:

- **Priority** -- an integer that controls merge order (lower = applied first)
- **Merge strategy** -- `append` (default), `prepend`, or `replace`
- **Scope** -- can target agent types, trust levels, or groups
- **Enabled flag** -- GPOs can be disabled without deleting them
- **Instruction path** -- relative path to the markdown file in SYSVOL

At agent boot, the ConfigAssembler:

1. Reads the agent's `x-agent-InstructionGPOs` for directly linked GPOs
2. Sorts them by priority ascending (lowest first)
3. Reads each GPO's markdown content from SYSVOL
4. Merges them per their merge strategy
5. Prepends an auto-generated identity header and appends a tool authorization summary

The result is the agent's effective system prompt.

### Priority Ordering

| Priority Range | Layer | Description |
|----------------|-------|-------------|
| 0--99 | Base | Applies to all agents (`base-agent-instructions`) |
| 100--199 | Type | Applies by agent type (`type-assistant-instructions`, etc.) |
| 200--299 | Trust | Applies by trust level (`trust-elevated-instructions`) |
| 300+ | Custom | Team-specific, project-specific, or agent-specific |

Lower-priority instructions appear first in the merged prompt. Higher-priority instructions appear later and can override earlier ones (using the `replace` merge strategy) or augment them (using `append`).

### Creating a Custom Instruction GPO

Suppose you want to add engineering-team-specific instructions.

**Step 1: Write the markdown content.**

Connect to the DC container and create the file in SYSVOL:

```bash
make shell
```

Inside the container:

```bash
SYSVOL="/var/lib/samba/sysvol/autonomy.local"
mkdir -p "$SYSVOL/AgentInstructions/team-engineering"
cat > "$SYSVOL/AgentInstructions/team-engineering/instructions.md" <<'PROMPT'
# Engineering Team Instructions

You are assigned to the engineering team. Follow these guidelines:

## Code Standards

- Follow the team style guide.
- All code changes require tests. Do not submit changes without coverage.
- Use conventional commits for all commit messages.

## Scope

- You have access to repositories matching `myorg/engineering-*`.
- Always work on feature branches, never commit directly to main.

## Escalation

- For architecture decisions, escalate to the coordinator.
- For security concerns, escalate immediately.
PROMPT
exit
```

**Step 2: Create the GPO object in AD.**

From outside the container, use the Makefile's LDAP helpers. First, create a temporary LDIF:

```bash
LDAPTLS_REQCERT=allow ldapmodify -H ldaps://localhost \
    -x -D "CN=Administrator,CN=Users,DC=autonomy,DC=local" \
    -w "$(grep SAMBA_ADMIN_PASSWORD .env | cut -d= -f2)" <<'EOF'
dn: CN=team-engineering,CN=Agent Instructions,CN=System,DC=autonomy,DC=local
changetype: add
objectClass: x-agentInstructionGPO
cn: team-engineering
x-gpo-DisplayName: Engineering Team Instructions
x-gpo-InstructionPath: AgentInstructions/team-engineering/instructions.md
x-gpo-Priority: 300
x-gpo-MergeStrategy: append
x-gpo-Enabled: TRUE
x-gpo-Version: 1.0.0
description: Instructions for agents on the engineering team
EOF
```

**Step 3: Link to an agent.**

```bash
make link-gpo AGENT=my-agent GPO=team-engineering
```

**Step 4: Verify.**

```bash
make dry-run AGENT=my-agent
```

The output should show the engineering team instructions appearing in the system prompt after the base and type instructions.

### Merge Strategies

- **`append`** (default) -- the GPO's content is concatenated after all lower-priority content. This is the most common strategy.
- **`prepend`** -- the GPO's content is inserted before all lower-priority content.
- **`replace`** -- all lower-priority content is discarded and replaced with this GPO's content. Use this sparingly, typically for agent-specific overrides that need to completely redefine the prompt.

---

## Tool Mapping

### How AD Tool Identifiers Map to Runtime Capabilities

AD tool objects use canonical identifiers like `filesystem.read`, `git.cli`, `gnu.bash`. The agent runtime uses a different set of built-in tool names like `read_file`, `list_directory`, `run_command`. The file `tool-mapping.json` bridges these two namespaces.

The mapping file at `samba4/docker/tool-mapping.json` contains three sections:

**`tool_mapping`** -- maps an AD tool identifier to a list of runtime built-in tools:

```json
{
  "filesystem.read": ["read_file", "list_directory", "search_files", "grep"],
  "filesystem.write": ["write_file"],
  "gnu.bash": ["run_command"],
  ...
}
```

When an agent is granted `filesystem.read` in AD, the runtime enables `read_file`, `list_directory`, `search_files`, and `grep`.

**`command_tool_prefixes`** -- maps an AD tool identifier to allowed command prefixes for shell execution:

```json
{
  "git.cli": ["git "],
  "python.interpreter": ["python ", "python3 ", "pip ", "pip3 "],
  ...
}
```

When an agent is granted `git.cli`, the runtime enables `run_command` and restricts it to commands starting with `git `. This provides fine-grained shell access without granting unrestricted bash.

**`unrestricted_shell_tools`** -- lists AD tool identifiers that grant unrestricted shell access:

```json
["gnu.bash"]
```

An agent granted `gnu.bash` gets `run_command` with no prefix restrictions.

### Adding New Tool Mappings

To add a new tool:

1. Register the tool in AD (it will be available to all agents that get granted it):

```bash
make shell
# Inside the DC container:
ldapmodify -H ldaps://localhost -x \
    -D "CN=Administrator,CN=Users,DC=autonomy,DC=local" \
    -w "$SAMBA_ADMIN_PASSWORD" <<'EOF'
dn: CN=terraform.cli,CN=Agent Tools,CN=System,DC=autonomy,DC=local
changetype: add
objectClass: x-agentTool
cn: terraform.cli
x-tool-Identifier: terraform.cli
x-tool-DisplayName: Terraform CLI
x-tool-Category: infrastructure
x-tool-RiskLevel: 4
x-tool-RequiredTrust: 3
x-tool-AuditRequired: TRUE
EOF
```

2. Add the runtime mapping to `tool-mapping.json`:

```json
{
  "tool_mapping": {
    "terraform.cli": []
  },
  "command_tool_prefixes": {
    "terraform.cli": ["terraform "]
  }
}
```

3. Rebuild the agent container to pick up the new mapping:

```bash
make build-agent
```

4. Grant the tool to an agent:

```bash
make grant-tool AGENT=my-agent TOOL=terraform.cli
```

---

## Verification and Testing

The Makefile provides several targets for verifying the health of the DC and the correctness of the schema and data.

### make test-schema

Verifies that all custom schema classes and containers exist in the DC:

```bash
make test-schema
```

Expected output:

```
=== Checking x-agent class ===
OK: x-agent class exists

=== Checking x-agentSandbox class ===
OK: x-agentSandbox class exists

=== Checking x-agentTool class ===
OK: x-agentTool class exists

=== Checking x-agentPolicy class ===
OK: x-agentPolicy class exists

=== Checking x-agentInstructionGPO class ===
OK: x-agentInstructionGPO class exists

=== Checking containers ===
OK: Agents container exists
OK: Agent Sandboxes container exists
OK: Agent Tools container exists
OK: Agent Policies container exists
OK: Agent Instructions container exists
```

This performs schema lookups in `CN=Schema,CN=Configuration` and base searches on each container DN. If any check fails, the schema installation did not complete correctly.

### make verify-acls

Tests DC-enforced access control by authenticating as an agent and verifying it can read its own entry and the shared containers:

```bash
make verify-acls
```

Expected output:

```
=== Verifying DC-enforced ACLs ===
  OK: agent can read own entry
  OK: agent can read Agent Tools
  OK: agent can read Agent Policies
  OK: agent can read Agent Instructions
=== 0 failures ===
```

This uses `claude-assistant-01`'s keytab to kinit inside the DC container, then performs GSSAPI-authenticated LDAP searches. It verifies that the ACLs set by `bootstrap-acls.sh` are working correctly.

### make integration-test

Runs the full integration test suite inside the DC container:

```bash
make integration-test
```

This tests:

- All five schema classes exist
- All five containers exist
- All three sample agents exist and have the correct objectClass
- Keytab files exist for all agents
- Kerberos authentication (`kinit`) succeeds for all agents
- GSSAPI LDAP reads work (agent reads own entry and shared containers)
- `agent-manager` CLI works

The exit code is 0 if all tests pass, 1 if any fail.

### make status

Shows domain health information:

```bash
make status
```

This runs `samba-tool domain info autonomy.local` inside the DC container and reports the domain's LDAP, Kerberos, DNS, and replication status.

---

## Troubleshooting

### "kinit: Cannot find KDC for realm AUTONOMY.LOCAL"

The Kerberos client cannot locate the Key Distribution Center.

- Verify the DC container is running: `docker ps | grep agent-directory-dc`
- Check `/etc/krb5.conf` inside the container (`make shell`, then `cat /etc/krb5.conf`). It should have `kdc = localhost` under the `[realms]` section.
- If running the agent container, check that `/etc/krb5.conf` in the agent container has `kdc = dc1` and the DC container is reachable at that hostname.

### "SASL(-4): no mechanism available"

The GSSAPI SASL mechanism is not installed.

- Ensure `libsasl2-modules-gssapi-mit` is installed in the container. The agent Dockerfile includes this package. If you are running outside Docker, install it:
  ```bash
  apt-get install libsasl2-modules-gssapi-mit
  ```

### "Server not found in Kerberos database"

The LDAP URI hostname does not match a Kerberos principal.

- The LDAP URI must use the FQDN that matches the DC's Kerberos service principal. Use `ldap://dc1.autonomy.local`, not `ldap://localhost` or an IP address.
- When using `ldapsearch` with GSSAPI, include the `-N` flag to disable reverse DNS lookup. Without it, the client may resolve the hostname to an IP and then back to a different hostname, causing a principal mismatch.
  ```bash
  ldapsearch -N -H ldap://dc1.autonomy.local -Y GSSAPI ...
  ```

### "Agent not found"

The agent-broker or `make get-agent` cannot find the agent object.

- Agent objects use the `$` suffix on their `sAMAccountName` and `CN` (machine account convention). The agent `my-agent` is stored as `CN=my-agent$,CN=Agents,CN=System,DC=autonomy,DC=local`.
- Verify the agent exists: `make list-agents`
- If you created the agent manually (not via `agent-manager`), ensure it was moved from `CN=Users` to `CN=Agents,CN=System` and has the `x-agent` objectClass.

### Build hangs during apt-get

Docker build gets stuck during package installation.

- Ensure `DEBIAN_FRONTEND=noninteractive` is set in the Dockerfile (both Dockerfiles in this project already set it). Without it, `apt-get` may prompt for interactive input (e.g., timezone configuration for `krb5-user`).

### "Bootstrap complete" never appears

The first-boot provisioning is failing.

- Run `make logs` and look for errors before the "Bootstrap complete" line.
- Common causes:
  - The default `smb.conf` has `server role = standalone server`, which conflicts with AD DC provisioning. The Dockerfile removes it before provisioning, but if the image was built from a stale cache, the old `smb.conf` may persist. Rebuild without cache: `docker compose build --no-cache`
  - The admin password in `.env` does not meet Samba's complexity requirements (must include uppercase, lowercase, digit, and be at least 7 characters).
  - Port conflicts on the host. The compose file maps to non-standard host ports (e.g., `8888:88` for Kerberos, `4450:445` for SMB) to avoid conflicts with macOS services, but check that nothing else is bound to those ports.

### LDAP operations fail with "Can't contact LDAP server"

- The DC may not be running or not yet healthy. Check `docker ps` for the container status and health.
- The Makefile uses `ldaps://localhost` (port 636) for admin operations. Ensure port 636 is mapped: `docker port agent-directory-dc 636`.
- For self-signed certificates (the default in dev), ensure `LDAPTLS_REQCERT=allow` is set. The Makefile sets this automatically.

### Dry-run shows empty tools or policies

- The agent may not have any tools or policies linked. Use `make get-agent AGENT=...` to check the `x-agent-AuthorizedTools` and `x-agent-Policies` attributes.
- If the attributes are present but the dry-run shows empties, the tool or policy objects may not exist in their respective containers. Verify with `make list-tools` and `make list-policies`.

---

## Environment Reset

To destroy the entire environment and start over:

```bash
make reset
```

This runs `docker compose down -v`, which stops the container and deletes all volumes (including the Samba database). All agents, schema modifications, ACLs, keytabs, and sample data are gone.

The next `make up` will re-provision from scratch: domain provisioning, schema installation, sample data creation, ACL setup, and keytab generation. Any custom agents, tools, policies, or instruction GPOs you created will need to be recreated.

If you only want to stop the DC without losing data:

```bash
make down
```

Then `make up` will restart with all data intact.

---

## Next Steps

- **[Admin Guide](../samba4/docs/ADMIN-GUIDE.md)** -- managing agents in production: creating agents manually, LDAP operations, group management, Kerberos keytab rotation, monitoring, and auditing queries.
- **[Schema Documentation](../samba4/docs/SCHEMA.md)** -- full reference for all object classes, attributes, OIDs, and trust levels.
- **[Architecture Diagrams](ARCHITECTURE.md)** -- Mermaid diagrams showing the authentication flow, tool authorization logic, trust level hierarchy, container structure, and deployment architecture.
- **[Deployment Guide](DEPLOYMENT.md)** -- production deployment considerations for the schema extension.
