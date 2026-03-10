# Administrator's Guide: Samba4 Agent Directory

Deployment, agent management, and day-to-day operations for the Agent Directory schema extension on Samba4 AD.

## Table of Contents

1. [Deployment](#deployment)
   - [Prerequisites](#prerequisites)
   - [Docker Dev Environment](#docker-dev-environment)
   - [Production Deployment](#production-deployment)
   - [Schema Installation](#schema-installation)
   - [Post-Installation Verification](#post-installation-verification)
2. [Agent Management](#agent-management)
   - [Creating Agents](#creating-agents)
   - [Viewing Agents](#viewing-agents)
   - [Modifying Agents](#modifying-agents)
   - [Deleting Agents](#deleting-agents)
3. [Sandbox Management](#sandbox-management)
   - [Creating Sandboxes](#creating-sandboxes)
   - [Linking Agents to Sandboxes](#linking-agents-to-sandboxes)
4. [Tool Authorization](#tool-authorization)
   - [Granting Tools](#granting-tools)
   - [Revoking Tools](#revoking-tools)
   - [Group-Based Tool Grants](#group-based-tool-grants)
5. [Policy Management](#policy-management)
   - [Linking Policies](#linking-policies)
   - [Viewing Effective Policies](#viewing-effective-policies)
   - [Creating Custom Policies](#creating-custom-policies)
6. [Instruction GPOs](#instruction-gpos)
   - [How Instruction GPOs Work](#how-instruction-gpos-work)
   - [Listing Instruction GPOs](#listing-instruction-gpos)
   - [Linking Instruction GPOs to Agents](#linking-instruction-gpos-to-agents)
   - [Creating Custom Instruction GPOs](#creating-custom-instruction-gpos)
   - [Updating Instructions in SYSVOL](#updating-instructions-in-sysvol)
   - [Instruction Merge Order](#instruction-merge-order)
7. [Authentication and Kerberos](#authentication-and-kerberos)
   - [SPN Registration](#spn-registration)
   - [Keytab Generation](#keytab-generation)
   - [Password Rotation](#password-rotation)
8. [Group Management](#group-management)
9. [Monitoring and Troubleshooting](#monitoring-and-troubleshooting)
   - [Health Checks](#health-checks)
   - [Common Issues](#common-issues)
   - [LDAP Queries for Auditing](#ldap-queries-for-auditing)
10. [Reference](#reference)
    - [Container Structure](#container-structure)
    - [Trust Levels](#trust-levels)
    - [Tool Authorization Logic](#tool-authorization-logic)
    - [OID Namespace](#oid-namespace)

---

## Deployment

### Prerequisites

| Component | Requirement |
|-----------|-------------|
| Samba | 4.15+ with AD DC role |
| Privileges | Root on DC (for `ldbmodify` and `samba-tool`) |
| Tools | `ldb-tools`, `ldap-utils`, `python3`, `python3-ldap` |
| Network | Ports 389 (LDAP), 636 (LDAPS), 88 (Kerberos), 445 (SMB) |

**Pre-deployment checklist:**

- [ ] Samba4 AD DC is provisioned and healthy (`samba-tool domain info`)
- [ ] IANA Private Enterprise Number obtained (replace OID `99999` before production)
- [ ] Schema extension tested in lab environment
- [ ] Backup of `/var/lib/samba/private/sam.ldb` completed
- [ ] AD replication healthy (if multi-DC)

### Docker Dev Environment

For local development and testing, a Docker environment is provided:

```bash
cd samba4/docker
make up       # Build and start (provisions on first boot, ~60s)
make logs     # Watch provisioning — wait for "Bootstrap complete"
make status   # Verify domain health
```

The Docker environment creates a fully provisioned DC with 3 sample agents, 2 sandboxes, tool grants, policies, instruction GPOs, and group memberships. See `samba4/docker/Makefile` for all available targets.

To destroy and re-provision:

```bash
make reset    # Destroy volumes
make up       # Fresh provision
```

### Production Deployment

On an existing Samba4 AD DC:

```bash
# 1. Copy the schema and scripts to the DC
scp -r samba4/schema/ samba4/scripts/ samba4/instructions/ root@dc:/opt/agent-directory/

# 2. SSH to the DC
ssh root@dc

# 3. Install schema
cd /opt/agent-directory
./schema/install-schema.sh yourdomain.com

# 4. Deploy instruction content to SYSVOL
SYSVOL="/var/lib/samba/sysvol/yourdomain.com"
for f in instructions/*.md; do
    name=$(basename "$f" .md)
    mkdir -p "$SYSVOL/AgentInstructions/$name"
    cp "$f" "$SYSVOL/AgentInstructions/$name/instructions.md"
done

# 5. Make agent-manager available
chmod +x scripts/agent-manager.py
ln -s /opt/agent-directory/scripts/agent-manager.py /usr/local/bin/agent-manager
```

### Schema Installation

The `install-schema.sh` script runs 7 phases:

| Phase | Description | Files |
|-------|-------------|-------|
| 1 | Attribute definitions | `01-agent-attributes.ldif`, `01b-sandbox-attributes.ldif`, `01c-instruction-gpo-attributes.ldif`, `02-tool-attributes.ldif`, `03-policy-attributes.ldif` |
| 2 | Class definitions | `04-agent-class.ldif`, `04b-sandbox-class.ldif`, `04c-instruction-gpo-class.ldif`, `05-tool-class.ldif`, `06-policy-class.ldif` |
| 3 | Schema cache refresh | `samba-tool dbcheck` |
| 4 | Containers and groups | `07-containers.ldif` |
| 5 | Default tools | `08-default-tools.ldif` |
| 6 | Default policies | `09-default-policies.ldif` |
| 6b | Default instruction GPOs | `10-default-instruction-gpos.ldif` |
| 7 | SYSVOL directory setup | Creates `AgentPolicies/` and `AgentInstructions/` directories |

The script is idempotent — re-running it will skip objects that already exist.

### Post-Installation Verification

```bash
DOMAIN="yourdomain.com"
BASE_DN="DC=$(echo $DOMAIN | sed 's/\./,DC=/g')"
ADMIN_PW="your-admin-password"
LDAPSEARCH="ldapsearch -H ldap://localhost -x -D CN=Administrator,CN=Users,$BASE_DN -w $ADMIN_PW"

# Verify schema classes
for class in x-agent x-agentSandbox x-agentTool x-agentPolicy x-agentInstructionGPO; do
    $LDAPSEARCH -b "CN=Schema,CN=Configuration,$BASE_DN" "(cn=$class)" cn \
        | grep -q "cn: $class" && echo "OK: $class" || echo "FAIL: $class"
done

# Verify containers
for cn in "Agents" "Agent Sandboxes" "Agent Tools" "Agent Policies" "Agent Instructions"; do
    $LDAPSEARCH -b "CN=$cn,CN=System,$BASE_DN" -s base dn \
        | grep -q "dn:" && echo "OK: $cn" || echo "FAIL: $cn"
done
```

---

## Agent Management

Agents are user objects with the `x-agent` objectClass, stored in `CN=Agents,CN=System`. They use the `$` sAMAccountName suffix (machine account convention).

### Creating Agents

**Using agent-manager (recommended):**

```bash
agent-manager agent create my-agent-01 \
    --type assistant \
    --trust-level 2 \
    --model claude-opus-4-5 \
    --mission "Code review assistant for engineering team" \
    --domain yourdomain.com \
    --bind-pw "$ADMIN_PW"
```

Agent types: `autonomous`, `assistant`, `tool`, `orchestrator`, `coordinator`

Trust levels: `0` (Untrusted), `1` (Basic), `2` (Standard), `3` (Elevated), `4` (System)

**Using samba-tool + ldbmodify (manual):**

```bash
DOMAIN="yourdomain.com"
BASE_DN="DC=$(echo $DOMAIN | sed 's/\./,DC=/g')"
SAM_LDB="/var/lib/samba/private/sam.ldb"

# 1. Create user account
samba-tool user create 'my-agent-01$' --random-password \
    --description="AI Agent: assistant"

# 2. Move to Agents container
ldbmodify -H "$SAM_LDB" <<EOF
dn: CN=my-agent-01\$,CN=Users,$BASE_DN
changetype: modrdn
newrdn: CN=my-agent-01\$
deleteoldrdn: 1
newsuperior: CN=Agents,CN=System,$BASE_DN
EOF

# 3. Add x-agent objectClass and attributes
ldbmodify -H "$SAM_LDB" <<EOF
dn: CN=my-agent-01\$,CN=Agents,CN=System,$BASE_DN
changetype: modify
add: objectClass
objectClass: x-agent
-
add: x-agent-Type
x-agent-Type: assistant
-
add: x-agent-TrustLevel
x-agent-TrustLevel: 2
-
add: x-agent-Model
x-agent-Model: claude-opus-4-5
-
add: x-agent-Mission
x-agent-Mission: Code review assistant for engineering team
-
add: x-agent-AuditLevel
x-agent-AuditLevel: 1
EOF
```

**Using ldapmodify (remote, no sam.ldb access):**

If you don't have local access to `sam.ldb` (e.g., managing from a remote workstation), use standard LDAP operations. The `samba-tool` steps still require running on the DC, but subsequent modifications can be done remotely:

```bash
# After the agent account exists and is in the Agents container,
# set attributes via LDAP:
ldapmodify -H ldap://dc.yourdomain.com -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=my-agent-01\$,CN=Agents,CN=System,$BASE_DN
changetype: modify
add: x-agent-LLMAccess
x-agent-LLMAccess: claude-opus-4-5
x-agent-LLMAccess: claude-sonnet-4
-
add: x-agent-LLMQuota
x-agent-LLMQuota: {"daily_tokens": 2000000, "max_context": 200000}
-
add: x-agent-NatsSubjects
x-agent-NatsSubjects: tasks.assistant.my-agent-01
x-agent-NatsSubjects: escalations.team.engineering
EOF
```

### Viewing Agents

**List all agents:**

```bash
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=Agents,CN=System,$BASE_DN" \
    "(objectClass=x-agent)" \
    cn x-agent-Type x-agent-TrustLevel x-agent-Model
```

**Get full details for one agent:**

```bash
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=my-agent-01\$,CN=Agents,CN=System,$BASE_DN" \
    "(objectClass=x-agent)" '*'
```

**Using agent-manager:**

```bash
agent-manager agent list --domain yourdomain.com --bind-pw "$ADMIN_PW"
agent-manager agent get my-agent-01 --domain yourdomain.com --bind-pw "$ADMIN_PW"
agent-manager agent get my-agent-01 --json --domain yourdomain.com --bind-pw "$ADMIN_PW"
```

**Filter by type or trust level:**

```bash
# All coordinators
ldapsearch ... -b "CN=Agents,CN=System,$BASE_DN" \
    "(&(objectClass=x-agent)(x-agent-Type=coordinator))" cn

# All agents with trust level >= 3
ldapsearch ... -b "CN=Agents,CN=System,$BASE_DN" \
    "(&(objectClass=x-agent)(x-agent-TrustLevel>=3))" cn x-agent-Type
```

### Modifying Agents

**Update attributes via ldapmodify:**

```bash
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=my-agent-01\$,CN=Agents,CN=System,$BASE_DN
changetype: modify
replace: x-agent-TrustLevel
x-agent-TrustLevel: 3
-
replace: x-agent-Model
x-agent-Model: claude-sonnet-4
EOF
```

**Using agent-manager:**

```bash
agent-manager agent set my-agent-01 \
    --trust-level 3 \
    --model claude-sonnet-4 \
    --domain yourdomain.com --bind-pw "$ADMIN_PW"
```

**Set escalation path:**

```bash
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=my-agent-01\$,CN=Agents,CN=System,$BASE_DN
changetype: modify
add: x-agent-EscalationPath
x-agent-EscalationPath: CN=coordinator-main\$,CN=Agents,CN=System,$BASE_DN
EOF
```

### Deleting Agents

```bash
# Using agent-manager
agent-manager agent delete my-agent-01 --domain yourdomain.com --bind-pw "$ADMIN_PW"

# Using samba-tool
samba-tool user delete 'my-agent-01$'
```

**Warning:** Deleting an agent removes its identity, tool grants, policy links, and group memberships. Ensure the agent is not actively processing tasks before deletion.

---

## Sandbox Management

Sandboxes are computer objects with the `x-agentSandbox` objectClass, stored in `CN=Agent Sandboxes,CN=System`. They represent execution environments where agents run.

### Creating Sandboxes

```bash
# 1. Create computer account
samba-tool computer create my-sandbox-01 \
    --description="Agent Sandbox: bwrap"

# 2. Move to Agent Sandboxes container
ldbmodify -H "$SAM_LDB" <<EOF
dn: CN=my-sandbox-01,CN=Computers,$BASE_DN
changetype: modrdn
newrdn: CN=my-sandbox-01
deleteoldrdn: 1
newsuperior: CN=Agent Sandboxes,CN=System,$BASE_DN
EOF

# 3. Add x-agentSandbox objectClass and attributes
ldbmodify -H "$SAM_LDB" <<EOF
dn: CN=my-sandbox-01,CN=Agent Sandboxes,CN=System,$BASE_DN
changetype: modify
add: objectClass
objectClass: x-agentSandbox
-
add: x-sandbox-SecurityProfile
x-sandbox-SecurityProfile: bwrap
-
add: x-sandbox-Status
x-sandbox-Status: active
-
add: x-sandbox-Endpoint
x-sandbox-Endpoint: unix:///var/run/sandbox/my-sandbox-01.sock
-
add: x-sandbox-ResourcePolicy
x-sandbox-ResourcePolicy: {"cpu": "2.0", "memory": "4Gi", "disk": "20Gi"}
-
add: x-sandbox-NetworkPolicy
x-sandbox-NetworkPolicy: {"egress": "restricted", "ingress": "deny"}
EOF
```

Security profiles: `bwrap` (bubblewrap), `appcontainer`, `hyperv`, `vmware`, `none`

### Linking Agents to Sandboxes

The link is bidirectional: the agent references the sandbox, and the sandbox lists its authorized agents.

```bash
AGENT_DN="CN=my-agent-01\$,CN=Agents,CN=System,$BASE_DN"
SANDBOX_DN="CN=my-sandbox-01,CN=Agent Sandboxes,CN=System,$BASE_DN"

# Agent -> Sandbox
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: $AGENT_DN
changetype: modify
add: x-agent-Sandbox
x-agent-Sandbox: $SANDBOX_DN
EOF

# Sandbox -> Agent
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: $SANDBOX_DN
changetype: modify
add: x-sandbox-Agents
x-sandbox-Agents: $AGENT_DN
EOF
```

**List sandboxes and their agents:**

```bash
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=Agent Sandboxes,CN=System,$BASE_DN" \
    "(objectClass=x-agentSandbox)" \
    cn x-sandbox-SecurityProfile x-sandbox-Status x-sandbox-Agents
```

---

## Tool Authorization

Tools are registered in `CN=Agent Tools,CN=System` and granted to agents by adding DN references to `x-agent-AuthorizedTools`.

### Granting Tools

**Using agent-manager:**

```bash
agent-manager tool grant my-agent-01 git.cli \
    --domain yourdomain.com --bind-pw "$ADMIN_PW"
```

**Using ldapmodify:**

```bash
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=my-agent-01\$,CN=Agents,CN=System,$BASE_DN
changetype: modify
add: x-agent-AuthorizedTools
x-agent-AuthorizedTools: CN=git.cli,CN=Agent Tools,CN=System,$BASE_DN
EOF
```

**Grant multiple tools at once:**

```bash
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=my-agent-01\$,CN=Agents,CN=System,$BASE_DN
changetype: modify
add: x-agent-AuthorizedTools
x-agent-AuthorizedTools: CN=filesystem.read,CN=Agent Tools,CN=System,$BASE_DN
x-agent-AuthorizedTools: CN=filesystem.write,CN=Agent Tools,CN=System,$BASE_DN
x-agent-AuthorizedTools: CN=git.cli,CN=Agent Tools,CN=System,$BASE_DN
x-agent-AuthorizedTools: CN=python.interpreter,CN=Agent Tools,CN=System,$BASE_DN
x-agent-AuthorizedTools: CN=llm.inference,CN=Agent Tools,CN=System,$BASE_DN
EOF
```

### Revoking Tools

```bash
agent-manager tool revoke my-agent-01 git.cli \
    --domain yourdomain.com --bind-pw "$ADMIN_PW"
```

**Explicit deny (overrides all grants):**

```bash
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=my-agent-01\$,CN=Agents,CN=System,$BASE_DN
changetype: modify
add: x-agent-DeniedTools
x-agent-DeniedTools: CN=gnu.bash,CN=Agent Tools,CN=System,$BASE_DN
EOF
```

### Group-Based Tool Grants

Instead of granting tools to individual agents, use AD groups for consistent policies:

```bash
# Add agent to a tool-access group
samba-tool group addmembers "ToolAccess-Development" 'my-agent-01$'

# The runtime checks group membership during tool authorization
```

Pre-defined groups:

| Group | Purpose |
|-------|---------|
| `ToolAccess-Shell` | Shell execution tools (bash, restricted bash) |
| `ToolAccess-Network` | Network tools (ssh, curl, API calls) |
| `ToolAccess-Development` | Development tools (git, python, node, make) |
| `ToolAccess-Management` | Management tools (samba-tool, ldap, ray) |

**List available tools:**

```bash
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=Agent Tools,CN=System,$BASE_DN" \
    "(objectClass=x-agentTool)" \
    x-tool-Identifier x-tool-Category x-tool-RiskLevel x-tool-RequiredTrust
```

---

## Policy Management

Policies follow the GPO pattern: metadata in AD, content (JSON) in SYSVOL. They control security constraints, behavior rules, resource limits, and network access.

### Linking Policies

**Using agent-manager:**

```bash
agent-manager policy link my-agent-01 base-security \
    --domain yourdomain.com --bind-pw "$ADMIN_PW"
```

**Using ldapmodify:**

```bash
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=my-agent-01\$,CN=Agents,CN=System,$BASE_DN
changetype: modify
add: x-agent-Policies
x-agent-Policies: CN=base-security,CN=Agent Policies,CN=System,$BASE_DN
x-agent-Policies: CN=base-behavior,CN=Agent Policies,CN=System,$BASE_DN
x-agent-Policies: CN=base-resource,CN=Agent Policies,CN=System,$BASE_DN
x-agent-Policies: CN=type-worker,CN=Agent Policies,CN=System,$BASE_DN
EOF
```

### Viewing Effective Policies

```bash
agent-manager policy effective my-agent-01 \
    --domain yourdomain.com --bind-pw "$ADMIN_PW"
```

Or query LDAP for the agent's linked policies:

```bash
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=my-agent-01\$,CN=Agents,CN=System,$BASE_DN" \
    "(objectClass=x-agent)" x-agent-Policies
```

### Creating Custom Policies

**1. Create the policy JSON in SYSVOL:**

```bash
SYSVOL="/var/lib/samba/sysvol/yourdomain.com"
mkdir -p "$SYSVOL/AgentPolicies/custom-engineering"
cat > "$SYSVOL/AgentPolicies/custom-engineering/policy.json" <<'EOF'
{
  "policy": "custom-engineering",
  "version": "1.0.0",
  "rules": {
    "allowed_repos": ["myorg/*"],
    "max_file_size_mb": 50,
    "allowed_languages": ["python", "rust", "typescript"],
    "require_code_review": true
  }
}
EOF
```

**2. Create the policy object in AD:**

```bash
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=custom-engineering,CN=Agent Policies,CN=System,$BASE_DN
changetype: add
objectClass: x-agentPolicy
cn: custom-engineering
x-policy-Identifier: custom-engineering
x-policy-Type: behavior
x-policy-Priority: 200
x-policy-Path: AgentPolicies/custom-engineering/policy.json
x-policy-AppliesToTypes: assistant
x-policy-AppliesToTypes: autonomous
x-policy-Enabled: TRUE
x-policy-Version: 1.0.0
description: Engineering team policy for code-related agents
EOF
```

**3. Link to agents:**

```bash
agent-manager policy link my-agent-01 custom-engineering \
    --domain yourdomain.com --bind-pw "$ADMIN_PW"
```

Default policies and their priority ranges:

| Priority | Layer | Examples |
|----------|-------|---------|
| 0-99 | Base | `base-security`, `base-behavior`, `base-resource`, `base-network` |
| 100-199 | Type | `type-worker`, `type-coordinator`, `type-tool` |
| 150 | Trust | `trust-untrusted`, `trust-elevated` |
| 200+ | Custom | Agent-specific or team-specific overrides |

---

## Instruction GPOs

Instruction GPOs deliver system prompts to agents via the AD Group Policy pattern. They are the primary mechanism for defining what an agent should do, how it should behave, and what persona it should adopt.

### How Instruction GPOs Work

```
┌─────────────────────────────────────────────────────────┐
│                  AD (Metadata)                          │
│                                                         │
│  CN=Agent Instructions,CN=System                        │
│    ├── CN=base-agent-instructions     (priority 0)      │
│    ├── CN=type-assistant-instructions (priority 100)    │
│    ├── CN=type-coordinator-instructions (priority 100)  │
│    └── CN=trust-elevated-instructions (priority 200)    │
│                                                         │
├─────────────────────────────────────────────────────────┤
│                 SYSVOL (Content)                         │
│                                                         │
│  sysvol/domain/AgentInstructions/                       │
│    ├── base-agent-instructions/instructions.md          │
│    ├── type-assistant-instructions/instructions.md      │
│    ├── type-coordinator-instructions/instructions.md    │
│    └── trust-elevated-instructions/instructions.md      │
└─────────────────────────────────────────────────────────┘
```

At agent boot, the runtime:

1. Reads `x-agent-InstructionGPOs` for directly linked GPOs
2. Queries all instruction GPOs where `x-gpo-AppliesToTypes`, `x-gpo-AppliesToTrustLevels`, or `x-gpo-AppliesToGroups` matches the agent
3. Filters to `x-gpo-Enabled=TRUE` only
4. Sorts by `x-gpo-Priority` ascending (lowest first, highest last)
5. Fetches instruction markdown from SYSVOL via SMB at each GPO's `x-gpo-InstructionPath`
6. Merges per `x-gpo-MergeStrategy`:
   - `append` (default): concatenate after lower-priority instructions
   - `prepend`: insert before lower-priority instructions
   - `replace`: discard all lower-priority instructions
7. Result = the agent's effective system prompt

### Listing Instruction GPOs

```bash
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=Agent Instructions,CN=System,$BASE_DN" \
    "(objectClass=x-agentInstructionGPO)" \
    cn x-gpo-DisplayName x-gpo-Priority x-gpo-MergeStrategy \
    x-gpo-AppliesToTypes x-gpo-Enabled x-gpo-Version
```

### Linking Instruction GPOs to Agents

```bash
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=my-agent-01\$,CN=Agents,CN=System,$BASE_DN
changetype: modify
add: x-agent-InstructionGPOs
x-agent-InstructionGPOs: CN=base-agent-instructions,CN=Agent Instructions,CN=System,$BASE_DN
x-agent-InstructionGPOs: CN=type-assistant-instructions,CN=Agent Instructions,CN=System,$BASE_DN
EOF
```

**View an agent's linked instruction GPOs:**

```bash
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=my-agent-01\$,CN=Agents,CN=System,$BASE_DN" \
    "(objectClass=x-agent)" x-agent-InstructionGPOs
```

### Creating Custom Instruction GPOs

**1. Write the instruction content:**

```bash
SYSVOL="/var/lib/samba/sysvol/yourdomain.com"
mkdir -p "$SYSVOL/AgentInstructions/team-engineering-instructions"
cat > "$SYSVOL/AgentInstructions/team-engineering-instructions/instructions.md" <<'PROMPT'
# Engineering Team Instructions

You are assigned to the engineering team. Follow these additional guidelines:

## Code Standards

- Follow the team's style guide at /docs/style-guide.md.
- All code changes require tests. Do not submit changes without test coverage.
- Use conventional commits for all commit messages.

## Repository Access

- You have access to repositories matching `myorg/engineering-*`.
- Do not access repositories outside your authorized patterns.
- Always work on feature branches, never commit directly to main.

## Escalation

- For architecture decisions, escalate to the engineering coordinator.
- For security concerns, escalate immediately — do not attempt to fix security issues autonomously.
PROMPT
```

**2. Create the GPO object in AD:**

```bash
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=team-engineering-instructions,CN=Agent Instructions,CN=System,$BASE_DN
changetype: add
objectClass: x-agentInstructionGPO
cn: team-engineering-instructions
x-gpo-DisplayName: Engineering Team Instructions
x-gpo-InstructionPath: AgentInstructions/team-engineering-instructions/instructions.md
x-gpo-Priority: 300
x-gpo-MergeStrategy: append
x-gpo-AppliesToGroups: CN=ToolAccess-Development,OU=AgentGroups,$BASE_DN
x-gpo-Enabled: TRUE
x-gpo-Version: 1.0.0
description: Instructions for agents assigned to the engineering team
EOF
```

**3. Link to specific agents (or rely on group-based scoping):**

If the GPO uses `x-gpo-AppliesToGroups`, any agent in that group automatically receives the instructions. For explicit linking:

```bash
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=my-agent-01\$,CN=Agents,CN=System,$BASE_DN
changetype: modify
add: x-agent-InstructionGPOs
x-agent-InstructionGPOs: CN=team-engineering-instructions,CN=Agent Instructions,CN=System,$BASE_DN
EOF
```

### Updating Instructions in SYSVOL

To change an agent's instructions, update the markdown file in SYSVOL and bump the version:

```bash
# 1. Edit the instruction file
vi "$SYSVOL/AgentInstructions/team-engineering-instructions/instructions.md"

# 2. Bump the version in AD (agents use this for cache invalidation)
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=team-engineering-instructions,CN=Agent Instructions,CN=System,$BASE_DN
changetype: modify
replace: x-gpo-Version
x-gpo-Version: 1.1.0
EOF
```

**Disable a GPO without deleting it:**

```bash
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=team-engineering-instructions,CN=Agent Instructions,CN=System,$BASE_DN
changetype: modify
replace: x-gpo-Enabled
x-gpo-Enabled: FALSE
EOF
```

### Instruction Merge Order

For an assistant agent at trust level 2 in the `ToolAccess-Development` group:

```
Priority 0:   base-agent-instructions           (all agents)        [append]
Priority 100: type-assistant-instructions        (assistant type)    [append]
Priority 300: team-engineering-instructions       (group match)      [append]
───────────────────────────────────────────────────────────────────────────
Result:        base + assistant + engineering = effective system prompt
```

If a GPO at priority 300 uses `replace` instead of `append`, the effective prompt would contain only the engineering instructions — all lower-priority GPOs would be discarded.

**Agent-specific override (highest priority):**

```bash
# Create an agent-specific instruction GPO at priority 400+
mkdir -p "$SYSVOL/AgentInstructions/override-my-agent-01"
cat > "$SYSVOL/AgentInstructions/override-my-agent-01/instructions.md" <<'PROMPT'
# Agent-Specific Override

You have been assigned a special project. For the duration of this project:
- Focus exclusively on the migration task in myorg/engineering-migration.
- Report daily progress to the coordinator via the tasks.coordination NATS subject.
PROMPT

ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=override-my-agent-01,CN=Agent Instructions,CN=System,$BASE_DN
changetype: add
objectClass: x-agentInstructionGPO
cn: override-my-agent-01
x-gpo-DisplayName: my-agent-01 Project Override
x-gpo-InstructionPath: AgentInstructions/override-my-agent-01/instructions.md
x-gpo-Priority: 400
x-gpo-MergeStrategy: append
x-gpo-Enabled: TRUE
x-gpo-Version: 1.0.0
description: Temporary project-specific instructions for my-agent-01
EOF

# Link directly to the agent
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=my-agent-01\$,CN=Agents,CN=System,$BASE_DN
changetype: modify
add: x-agent-InstructionGPOs
x-agent-InstructionGPOs: CN=override-my-agent-01,CN=Agent Instructions,CN=System,$BASE_DN
EOF
```

---

## Authentication and Kerberos

Agents authenticate via Kerberos using machine account credentials (keytab) or password.

### SPN Registration

Register a Service Principal Name for Kerberos authentication:

```bash
samba-tool spn add "agent/my-agent-01.yourdomain.com" 'my-agent-01$'

# Verify
samba-tool spn list 'my-agent-01$'
```

### Keytab Generation

```bash
# Generate keytab
samba-tool domain exportkeytab /etc/krb5.keytabs/my-agent-01.keytab \
    --principal='my-agent-01$@YOURDOMAIN.COM'

# Secure it
chmod 600 /etc/krb5.keytabs/my-agent-01.keytab

# Verify
klist -k -t /etc/krb5.keytabs/my-agent-01.keytab
```

**Or use the helper script:**

```bash
./scripts/generate-keytab.sh my-agent-01 /etc/krb5.keytabs/my-agent-01.keytab YOURDOMAIN.COM
```

**Distribute keytab to the agent's sandbox:**

```bash
# Copy to the sandbox host
scp /etc/krb5.keytabs/my-agent-01.keytab sandbox-host:/var/run/sandbox/keytabs/
```

### Password Rotation

Samba4 does not support gMSA (Group Managed Service Accounts). Implement keytab rotation via a cron job or provisioning service:

```bash
#!/bin/bash
# /etc/cron.weekly/rotate-agent-keytabs.sh
AGENTS=$(samba-tool user list | grep '\$$')
for agent in $AGENTS; do
    samba-tool user setpassword "$agent" --random-password
    samba-tool domain exportkeytab "/etc/krb5.keytabs/${agent%.\\$}.keytab" \
        --principal="${agent}@YOURDOMAIN.COM"
    chmod 600 "/etc/krb5.keytabs/${agent%.\\$}.keytab"
done
```

---

## Group Management

Groups provide role-based access control for agents.

**Tier groups (by capability level):**

```bash
# Add to tier group
samba-tool group addmembers "Tier1-Workers" 'my-agent-01$'

# View group members
samba-tool group listmembers "Tier1-Workers"
```

| Group | Description |
|-------|-------------|
| `Tier1-Workers` | Basic worker agents |
| `Tier2-Specialists` | Specialist agents with standard capabilities |
| `Tier3-Coordinators` | Coordinator agents with elevated capabilities |

**Tool access groups:**

```bash
samba-tool group addmembers "ToolAccess-Development" 'my-agent-01$'
samba-tool group addmembers "ToolAccess-Network" 'my-agent-01$'
```

**Create custom groups:**

```bash
ldbmodify -H "$SAM_LDB" <<EOF
dn: CN=Team-Engineering,OU=AgentGroups,$BASE_DN
changetype: add
objectClass: group
cn: Team-Engineering
description: Engineering team agents
groupType: -2147483646
EOF

samba-tool group addmembers "Team-Engineering" 'my-agent-01$'
```

**View an agent's group memberships:**

```bash
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=my-agent-01\$,CN=Agents,CN=System,$BASE_DN" \
    "(objectClass=x-agent)" memberOf
```

---

## Monitoring and Troubleshooting

### Health Checks

**Domain health:**

```bash
samba-tool domain info yourdomain.com
samba-tool dbcheck --cross-ncs
```

**Agent count by type:**

```bash
for type in assistant autonomous coordinator tool orchestrator; do
    count=$(ldapsearch -H ldap://localhost -x \
        -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
        -b "CN=Agents,CN=System,$BASE_DN" \
        "(&(objectClass=x-agent)(x-agent-Type=$type))" dn 2>/dev/null \
        | grep -c "^dn:")
    echo "$type: $count"
done
```

**Sandbox status:**

```bash
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=Agent Sandboxes,CN=System,$BASE_DN" \
    "(objectClass=x-agentSandbox)" \
    cn x-sandbox-Status x-sandbox-SecurityProfile
```

### Common Issues

**"The specified class is not defined in the schema"**

The schema extension has not been installed or has not replicated to this DC.

```bash
# Force schema cache refresh
samba-tool dbcheck --cross-ncs --fix --yes
```

**Agent creation fails with "object already exists"**

The sAMAccountName is taken. Check for existing accounts:

```bash
samba-tool user show 'my-agent-01$'
```

**Tool grant fails with "no such object"**

The tool identifier does not match a registered tool. List available tools:

```bash
ldapsearch ... -b "CN=Agent Tools,CN=System,$BASE_DN" \
    "(objectClass=x-agentTool)" x-tool-Identifier
```

**Instruction GPO not applied**

Check that:
1. The GPO is enabled: `x-gpo-Enabled: TRUE`
2. The GPO is linked to the agent or matches by scope
3. The instruction file exists in SYSVOL at the path specified by `x-gpo-InstructionPath`
4. SYSVOL is accessible via SMB

```bash
# Verify GPO state
ldapsearch ... -b "CN=Agent Instructions,CN=System,$BASE_DN" \
    "(cn=my-gpo-name)" x-gpo-Enabled x-gpo-InstructionPath x-gpo-AppliesToTypes

# Verify file exists in SYSVOL
ls -la "/var/lib/samba/sysvol/yourdomain.com/AgentInstructions/my-gpo-name/instructions.md"
```

**ldapmodify: "no such attribute"**

You're trying to set an attribute that doesn't exist in the schema, or the objectClass hasn't been added:

```bash
# Verify the agent has x-agent objectClass
ldapsearch ... -b "CN=my-agent-01\$,CN=Agents,CN=System,$BASE_DN" \
    "(objectClass=*)" objectClass
```

### LDAP Queries for Auditing

**Agents with trust level 3+ (elevated risk):**

```bash
ldapsearch ... -b "CN=Agents,CN=System,$BASE_DN" \
    "(&(objectClass=x-agent)(x-agent-TrustLevel>=3))" \
    cn x-agent-Type x-agent-TrustLevel x-agent-Model x-agent-Owner
```

**Agents with no escalation path configured:**

```bash
ldapsearch ... -b "CN=Agents,CN=System,$BASE_DN" \
    "(&(objectClass=x-agent)(!(x-agent-EscalationPath=*)))" \
    cn x-agent-Type
```

**Agents with shell tool access:**

```bash
ldapsearch ... -b "CN=Agents,CN=System,$BASE_DN" \
    "(&(objectClass=x-agent)(x-agent-AuthorizedTools=CN=gnu.bash,CN=Agent Tools,CN=System,$BASE_DN))" \
    cn x-agent-TrustLevel
```

**Disabled instruction GPOs:**

```bash
ldapsearch ... -b "CN=Agent Instructions,CN=System,$BASE_DN" \
    "(&(objectClass=x-agentInstructionGPO)(x-gpo-Enabled=FALSE))" \
    cn x-gpo-DisplayName
```

**All sandboxes in standby:**

```bash
ldapsearch ... -b "CN=Agent Sandboxes,CN=System,$BASE_DN" \
    "(&(objectClass=x-agentSandbox)(x-sandbox-Status=standby))" \
    cn x-sandbox-SecurityProfile
```

---

## Reference

### Container Structure

```
DC=yourdomain,DC=com
├── CN=System
│   ├── CN=Agents                    # x-agent objects (user subclass)
│   ├── CN=Agent Sandboxes           # x-agentSandbox objects (computer subclass)
│   ├── CN=Agent Tools               # x-agentTool objects
│   ├── CN=Agent Policies            # x-agentPolicy objects
│   └── CN=Agent Instructions        # x-agentInstructionGPO objects
├── OU=AgentGroups
│   ├── CN=Tier1-Workers
│   ├── CN=Tier2-Specialists
│   ├── CN=Tier3-Coordinators
│   ├── CN=ToolAccess-Shell
│   ├── CN=ToolAccess-Network
│   ├── CN=ToolAccess-Development
│   └── CN=ToolAccess-Management
└── SYSVOL
    └── yourdomain.com
        ├── AgentPolicies/           # Policy JSON content
        │   ├── base-security/policy.json
        │   └── ...
        └── AgentInstructions/       # Instruction GPO markdown content
            ├── base-agent-instructions/instructions.md
            ├── type-assistant-instructions/instructions.md
            └── ...
```

### Trust Levels

| Level | Name | Capabilities |
|-------|------|-------------|
| 0 | Untrusted | Read-only, no network, no delegation |
| 1 | Basic | Limited read/write, no delegation, basic tools |
| 2 | Standard | Normal operations, constrained delegation, most tools |
| 3 | Elevated | Broad access, can spawn agents, management tools |
| 4 | System | Full trust, unconstrained delegation, all tools |

Start with the lowest level that enables required functionality. Escalate only with justification.

### Tool Authorization Logic

```
1. Tool in x-agent-DeniedTools?           → DENY
2. Tool in x-agent-AuthorizedTools?       → ALLOW
3. Agent in tool-grant group?             → ALLOW
4. Agent TrustLevel >= Tool RequiredTrust? → ALLOW
5. Default:                               → DENY
```

Denied tools always win. Explicit grants take precedence over trust-level matching.

### OID Namespace

| Range | Purpose |
|-------|---------|
| `1.3.6.1.4.1.{PEN}.1.1` | x-agent class |
| `1.3.6.1.4.1.{PEN}.1.2` | x-agentTool class |
| `1.3.6.1.4.1.{PEN}.1.3` | x-agentPolicy class |
| `1.3.6.1.4.1.{PEN}.1.4` | x-agentSandbox class |
| `1.3.6.1.4.1.{PEN}.1.5` | x-agentInstructionGPO class |
| `1.3.6.1.4.1.{PEN}.2.1-21` | Agent attributes |
| `1.3.6.1.4.1.{PEN}.2.22` | Agent instruction GPO linkage |
| `1.3.6.1.4.1.{PEN}.2.30-39` | Tool attributes |
| `1.3.6.1.4.1.{PEN}.2.40-49` | Policy attributes |
| `1.3.6.1.4.1.{PEN}.2.50-59` | Sandbox attributes |
| `1.3.6.1.4.1.{PEN}.2.60-68` | Instruction GPO attributes |

**Replace `99999` with your IANA Private Enterprise Number before production use.**
Register at: https://www.iana.org/assignments/enterprise-numbers/
