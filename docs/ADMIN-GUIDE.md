# Administrator's Guide: Agent Directory

Management of agent identities, sandboxes, tools, policies, and instruction GPOs in Active Directory.

This guide covers both **Windows AD** (using PowerShell cmdlets and `ldifde`) and **Samba4 AD** (using `agent-manager`, `ldapmodify`, and `samba-tool`). Where commands differ between platforms, both are shown.

For Samba4-specific deployment, Docker operations, and schema installation details, see [../samba4/docs/ADMIN-GUIDE.md](../samba4/docs/ADMIN-GUIDE.md).

---

## Table of Contents

1. [Overview](#1-overview)
2. [Agent Lifecycle](#2-agent-lifecycle)
3. [Sandbox Management](#3-sandbox-management)
4. [Tool Authorization](#4-tool-authorization)
5. [Policy Management](#5-policy-management)
6. [Instruction GPOs](#6-instruction-gpos)
7. [Authentication](#7-authentication)
8. [Group Management](#8-group-management)
9. [Access Control](#9-access-control)
10. [Monitoring](#10-monitoring)
11. [Security Checklist](#11-security-checklist)

---

## 1. Overview

### What the Administrator Manages

The Agent Directory extends Active Directory with five object types for managing AI agent identities and their runtime configuration:

| Object | Storage | Description |
|--------|---------|-------------|
| **Agents** | `CN=Agents,CN=System` | User objects with agent auxiliary class. The identity principal. |
| **Sandboxes** | `CN=Agent Sandboxes,CN=System` | Computer objects with sandbox auxiliary class. The execution environment. |
| **Tools** | `CN=Agent Tools,CN=System` | Tool definitions with risk levels and trust requirements. |
| **Policies** | `CN=Agent Policies,CN=System` | AD metadata objects; policy content (JSON) stored in SYSVOL. |
| **Instruction GPOs** | `CN=Agent Instructions,CN=System` | AD metadata objects; instruction content (markdown) stored in SYSVOL. |

### Container Structure

```
DC=yourdomain,DC=com
├── CN=System
│   ├── CN=Agents                    # Agent identity objects
│   ├── CN=Agent Sandboxes           # Sandbox execution objects
│   ├── CN=Agent Tools               # Tool registry
│   ├── CN=Agent Policies            # Policy objects
│   └── CN=Agent Instructions        # Instruction GPO objects
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
        └── AgentInstructions/       # Instruction GPO markdown content
```

### Trust Model

Agents authenticate via Kerberos using machine-account credentials. The DC enforces access control directly -- agents bind to LDAP with their own identity, not through an intermediary broker. Each agent is granted:

- Read and list on the Agents, Tools, Policies, and Instructions containers (to resolve its own linked objects).
- Read on its own entry.

Administrators and Domain Admins retain full control. All tool grants, policy links, and instruction GPOs flow from AD objects that only administrators can modify.

### Schema Naming Conventions

| Concept | Windows AD Prefix | Samba4 Prefix |
|---------|-------------------|---------------|
| Agent class | `msDS-Agent` | `x-agent` |
| Agent attributes | `msDS-AgentType`, `msDS-AgentTrustLevel`, etc. | `x-agent-Type`, `x-agent-TrustLevel`, etc. |
| Sandbox class | `msDS-AgentSandbox` | `x-agentSandbox` |
| Sandbox attributes | `msDS-SandboxEndpoint`, etc. | `x-sandbox-Endpoint`, etc. |
| Tool class | `msDS-AgentTool` | `x-agentTool` |
| Policy class | `msDS-AgentPolicy` | `x-agentPolicy` |
| Instruction GPO class | -- | `x-agentInstructionGPO` |

---

## 2. Agent Lifecycle

Agents are user objects with an agent auxiliary class applied. On Samba4, they use the `$` sAMAccountName suffix (machine account convention) and are stored in `CN=Agents,CN=System`.

### Agent Attributes Reference

| Attribute | Windows | Samba4 | Type | Description |
|-----------|---------|--------|------|-------------|
| Type | `msDS-AgentType` | `x-agent-Type` | String, single | `autonomous`, `assistant`, `tool`, `orchestrator`, `coordinator` |
| TrustLevel | `msDS-AgentTrustLevel` | `x-agent-TrustLevel` | Integer 0-4, single | See trust levels table below |
| Model | `msDS-AgentModel` | `x-agent-Model` | String, single | AI model identifier (e.g., `claude-opus-4-5`) |
| Mission | -- | `x-agent-Mission` | String, single | High-level mission statement |
| LLMAccess | -- | `x-agent-LLMAccess` | String, multi | Model names the agent can use for inference |
| LLMQuota | -- | `x-agent-LLMQuota` | String (JSON), single | `{"daily_tokens": 2000000, "max_context": 200000}` |
| NatsSubjects | -- | `x-agent-NatsSubjects` | String, multi | NATS subjects for task queues |
| EscalationPath | -- | `x-agent-EscalationPath` | DN, single | DN of agent/group to escalate to |
| AuditLevel | `msDS-AgentAuditLevel` | `x-agent-AuditLevel` | Integer 0-3, single | 0=Minimal, 1=Standard, 2=Detailed, 3=Debug |
| Owner | `msDS-AgentOwner` | `x-agent-Owner` | DN, single | DN of responsible identity |
| Capabilities | `msDS-AgentCapabilities` | `x-agent-Capabilities` | String, multi | URNs in `urn:agent:capability:{category}:{name}` format |
| AuthorizedTools | `msDS-AgentAuthorizedTools` | `x-agent-AuthorizedTools` | DN, multi | Links to tool objects |
| DeniedTools | `msDS-AgentDeniedTools` | `x-agent-DeniedTools` | DN, multi | Explicit deny (overrides all grants) |
| Policies | `msDS-AgentPolicies` | `x-agent-Policies` | DN, multi | Linked policy objects |
| Sandbox | `msDS-AgentSandbox` | `x-agent-Sandbox` | DN, multi | Linked sandbox objects |
| InstructionGPOs | -- | `x-agent-InstructionGPOs` | DN, multi | Linked instruction GPO objects |

### Trust Levels

| Level | Name | Capabilities |
|-------|------|-------------|
| 0 | Untrusted | Read-only, no network, no delegation |
| 1 | Basic | Limited read/write, no delegation, basic tools |
| 2 | Standard | Normal operations, constrained delegation, most tools |
| 3 | Elevated | Broad access, can spawn agents, management tools |
| 4 | System | Full trust, unconstrained delegation, all tools |

Start with the lowest level that enables required functionality. Escalate only with justification.

### Creating Agents

**Windows (PowerShell):**

```powershell
Import-Module AgentDirectory

New-ADAgent -Name "claude-assistant-01" `
    -Type "assistant" `
    -TrustLevel 2 `
    -Owner "CN=John Smith,OU=Users,DC=corp,DC=contoso,DC=com" `
    -Model "claude-opus-4-5" `
    -Description "Code review assistant for engineering team" `
    -Enabled
```

**Samba4 (agent-manager):**

```bash
agent-manager agent create claude-assistant-01 \
    --type assistant \
    --trust-level 2 \
    --model claude-opus-4-5 \
    --mission "Code review assistant for engineering team" \
    --domain yourdomain.com \
    --bind-pw "$ADMIN_PW"
```

**Samba4 (manual -- samba-tool + ldapmodify):**

```bash
DOMAIN="yourdomain.com"
BASE_DN="DC=$(echo $DOMAIN | sed 's/\./,DC=/g')"

# 1. Create user account
samba-tool user create 'claude-assistant-01$' --random-password \
    --description="AI Agent: assistant"

# 2. Move to Agents container
ldbmodify -H /var/lib/samba/private/sam.ldb <<EOF
dn: CN=claude-assistant-01\$,CN=Users,$BASE_DN
changetype: modrdn
newrdn: CN=claude-assistant-01\$
deleteoldrdn: 1
newsuperior: CN=Agents,CN=System,$BASE_DN
EOF

# 3. Add x-agent objectClass and attributes
ldbmodify -H /var/lib/samba/private/sam.ldb <<EOF
dn: CN=claude-assistant-01\$,CN=Agents,CN=System,$BASE_DN
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

**Samba4 (setting LLM and messaging attributes via LDAP):**

```bash
ldapmodify -H ldap://dc.yourdomain.com -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=claude-assistant-01\$,CN=Agents,CN=System,$BASE_DN
changetype: modify
add: x-agent-LLMAccess
x-agent-LLMAccess: claude-opus-4-5
x-agent-LLMAccess: claude-sonnet-4
-
add: x-agent-LLMQuota
x-agent-LLMQuota: {"daily_tokens": 2000000, "max_context": 200000}
-
add: x-agent-NatsSubjects
x-agent-NatsSubjects: tasks.assistant.claude-assistant-01
x-agent-NatsSubjects: escalations.team.engineering
-
add: x-agent-EscalationPath
x-agent-EscalationPath: CN=coordinator-main\$,CN=Agents,CN=System,$BASE_DN
EOF
```

### Viewing Agents

**Windows (PowerShell):**

```powershell
# Get a specific agent
Get-ADAgent -Identity "claude-assistant-01"

# List all agents
Get-ADAgent

# Filter by type
Get-ADAgent -Type "assistant"

# Filter by trust level
Get-ADAgent -TrustLevel 3

# Custom LDAP filter
Get-ADAgent -Filter "msDS-AgentModel -eq 'claude-opus-4-5'"
```

**Samba4 (agent-manager):**

```bash
agent-manager agent list --domain yourdomain.com --bind-pw "$ADMIN_PW"
agent-manager agent get claude-assistant-01 --domain yourdomain.com --bind-pw "$ADMIN_PW"
agent-manager agent get claude-assistant-01 --json --domain yourdomain.com --bind-pw "$ADMIN_PW"
```

**Samba4 (ldapsearch):**

```bash
# List all agents
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=Agents,CN=System,$BASE_DN" \
    "(objectClass=x-agent)" \
    cn x-agent-Type x-agent-TrustLevel x-agent-Model

# Full details for one agent
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=claude-assistant-01\$,CN=Agents,CN=System,$BASE_DN" \
    "(objectClass=x-agent)" '*'

# Filter by type
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=Agents,CN=System,$BASE_DN" \
    "(&(objectClass=x-agent)(x-agent-Type=coordinator))" cn

# Filter by trust level >= 3
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=Agents,CN=System,$BASE_DN" \
    "(&(objectClass=x-agent)(x-agent-TrustLevel>=3))" cn x-agent-Type
```

### Modifying Agents

**Windows (PowerShell):**

```powershell
# Update trust level and model
Set-ADAgent -Identity "claude-assistant-01" -TrustLevel 3 -Model "claude-sonnet-4"

# Add capabilities
Set-ADAgent -Identity "claude-assistant-01" -AddCapabilities "urn:agent:capability:network-access"

# Change audit level
Set-ADAgent -Identity "claude-assistant-01" -AuditLevel 2

# Disable an agent
Set-ADAgent -Identity "claude-assistant-01" -Enabled $false

# Pipeline: update all assistants
Get-ADAgent -Type "assistant" | Set-ADAgent -AuditLevel 1
```

**Samba4 (agent-manager):**

```bash
agent-manager agent set claude-assistant-01 \
    --trust-level 3 \
    --model claude-sonnet-4 \
    --domain yourdomain.com --bind-pw "$ADMIN_PW"
```

**Samba4 (ldapmodify):**

```bash
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=claude-assistant-01\$,CN=Agents,CN=System,$BASE_DN
changetype: modify
replace: x-agent-TrustLevel
x-agent-TrustLevel: 3
-
replace: x-agent-Model
x-agent-Model: claude-sonnet-4
-
replace: x-agent-AuditLevel
x-agent-AuditLevel: 2
EOF
```

### Disabling Agents

**Windows (PowerShell):**

```powershell
Set-ADAgent -Identity "claude-assistant-01" -Enabled $false
```

**Samba4:**

```bash
samba-tool user disable 'claude-assistant-01$'
```

Disabling an agent sets the `ACCOUNTDISABLE` bit in `userAccountControl`. The agent cannot authenticate but retains all configuration for re-enabling later.

### Deleting Agents

**Windows (PowerShell):**

```powershell
Remove-ADAgent -Identity "claude-assistant-01"
```

**Samba4:**

```bash
# Using agent-manager
agent-manager agent delete claude-assistant-01 --domain yourdomain.com --bind-pw "$ADMIN_PW"

# Using samba-tool
samba-tool user delete 'claude-assistant-01$'
```

**Warning:** Deleting an agent removes its identity, tool grants, policy links, instruction GPO links, and group memberships. Ensure the agent is not actively processing tasks before deletion. Consider disabling instead of deleting to preserve audit history.

---

## 3. Sandbox Management

Sandboxes are computer objects with a sandbox auxiliary class, stored in `CN=Agent Sandboxes,CN=System`. They represent the execution environment where agents run, separate from the agent identity itself. An agent references one or more sandboxes; a sandbox lists its authorized agents.

### Security Profiles

| Profile | Description |
|---------|-------------|
| `bwrap` | Bubblewrap (Linux user-namespace sandbox) |
| `appcontainer` | Windows AppContainer isolation |
| `hyperv` | Hyper-V VM isolation |
| `vmware` | VMware VM isolation |
| `none` | No isolation (development only) |

### Sandbox Attributes

| Attribute | Windows | Samba4 | Description |
|-----------|---------|--------|-------------|
| Endpoint | `msDS-SandboxEndpoint` | `x-sandbox-Endpoint` | URI where sandbox runtime is accessible |
| Agents | `msDS-SandboxAgents` | `x-sandbox-Agents` | DNs of agents authorized to run here |
| SecurityProfile | `msDS-SandboxSecurityProfile` | `x-sandbox-SecurityProfile` | Isolation technology |
| ResourcePolicy | `msDS-SandboxResourcePolicy` | `x-sandbox-ResourcePolicy` | JSON resource constraints |
| NetworkPolicy | `msDS-SandboxNetworkPolicy` | `x-sandbox-NetworkPolicy` | JSON network rules |
| Status | `msDS-SandboxStatus` | `x-sandbox-Status` | `active`, `standby`, `terminated` |

### Creating Sandboxes

**Windows (PowerShell):**

```powershell
New-ADAgentSandbox -Name "sandbox-prod-001" `
    -SecurityProfile "bwrap" `
    -Endpoint "https://sandbox-001:8443" `
    -ResourcePolicy '{"cpu": "2.0", "memory": "4Gi", "disk": "20Gi"}' `
    -NetworkPolicy '{"egress": "restricted", "ingress": "deny"}' `
    -Description "Production sandbox for engineering agents" `
    -Enabled
```

**Samba4 (manual):**

```bash
# 1. Create computer account
samba-tool computer create sandbox-prod-001 \
    --description="Agent Sandbox: bwrap"

# 2. Move to Agent Sandboxes container
ldbmodify -H /var/lib/samba/private/sam.ldb <<EOF
dn: CN=sandbox-prod-001,CN=Computers,$BASE_DN
changetype: modrdn
newrdn: CN=sandbox-prod-001
deleteoldrdn: 1
newsuperior: CN=Agent Sandboxes,CN=System,$BASE_DN
EOF

# 3. Add x-agentSandbox objectClass and attributes
ldbmodify -H /var/lib/samba/private/sam.ldb <<EOF
dn: CN=sandbox-prod-001,CN=Agent Sandboxes,CN=System,$BASE_DN
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
x-sandbox-Endpoint: unix:///var/run/sandbox/sandbox-prod-001.sock
-
add: x-sandbox-ResourcePolicy
x-sandbox-ResourcePolicy: {"cpu": "2.0", "memory": "4Gi", "disk": "20Gi"}
-
add: x-sandbox-NetworkPolicy
x-sandbox-NetworkPolicy: {"egress": "restricted", "ingress": "deny"}
EOF
```

### Linking Agents to Sandboxes

The link is bidirectional: the agent references the sandbox, and the sandbox lists its authorized agents.

**Windows (PowerShell):**

```powershell
# Link sandbox to agent at creation time
New-ADAgent -Name "claude-assistant-01" -Type "assistant" -TrustLevel 2 `
    -Sandbox "CN=sandbox-prod-001,CN=Agent Sandboxes,CN=System,DC=corp,DC=contoso,DC=com"

# Or add sandbox to existing agent
Set-ADAgent -Identity "claude-assistant-01" `
    -AddSandbox "CN=sandbox-prod-001,CN=Agent Sandboxes,CN=System,DC=corp,DC=contoso,DC=com"
```

**Samba4 (ldapmodify):**

```bash
AGENT_DN="CN=claude-assistant-01\$,CN=Agents,CN=System,$BASE_DN"
SANDBOX_DN="CN=sandbox-prod-001,CN=Agent Sandboxes,CN=System,$BASE_DN"

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

### Listing Sandboxes

**Samba4:**

```bash
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=Agent Sandboxes,CN=System,$BASE_DN" \
    "(objectClass=x-agentSandbox)" \
    cn x-sandbox-SecurityProfile x-sandbox-Status x-sandbox-Agents
```

**Windows (PowerShell):**

```powershell
Get-ADAgentSandbox
Get-ADAgentSandbox -Identity "sandbox-prod-001"
```

---

## 4. Tool Authorization

Tools are registered in `CN=Agent Tools,CN=System` and represent capabilities that agents can be authorized to use. Tools have risk levels and required trust levels.

### Tool Authorization Logic

The runtime evaluates tool access in this order:

```
1. Tool in DeniedTools?                 -> DENY
2. Tool in AuthorizedTools?             -> ALLOW
3. Agent in a tool-grant group?         -> ALLOW
4. Agent TrustLevel >= Tool RequiredTrust? -> ALLOW
5. Default:                             -> DENY
```

Denied tools always win. Explicit grants take precedence over trust-level-based access.

### Pre-Defined Tool-Access Groups

| Group | Purpose |
|-------|---------|
| `ToolAccess-Shell` | Shell execution tools (bash, restricted bash) |
| `ToolAccess-Network` | Network tools (ssh, curl, API calls) |
| `ToolAccess-Development` | Development tools (git, python, node, make) |
| `ToolAccess-Management` | Management tools (samba-tool, ldap, ray) |

### Granting Tools to an Agent

**Windows (PowerShell):**

```powershell
# Grant a single tool
Grant-ADAgentToolAccess -AgentIdentity "claude-assistant-01" -ToolIdentity "git.cli"

# Grant multiple tools
"git.cli", "python.interpreter", "filesystem.read" | ForEach-Object {
    Grant-ADAgentToolAccess -AgentIdentity "claude-assistant-01" -ToolIdentity $_
}
```

**Samba4 (agent-manager):**

```bash
agent-manager tool grant claude-assistant-01 git.cli \
    --domain yourdomain.com --bind-pw "$ADMIN_PW"
```

**Samba4 (ldapmodify):**

```bash
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=claude-assistant-01\$,CN=Agents,CN=System,$BASE_DN
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

**Windows (PowerShell):**

```powershell
Revoke-ADAgentToolAccess -AgentIdentity "claude-assistant-01" -ToolIdentity "git.cli"
```

**Samba4 (agent-manager):**

```bash
agent-manager tool revoke claude-assistant-01 git.cli \
    --domain yourdomain.com --bind-pw "$ADMIN_PW"
```

### Denied Tools (Explicit Deny Overrides All)

Adding a tool to the denied list prevents the agent from using it regardless of group membership, direct grants, or trust level.

**Samba4 (ldapmodify):**

```bash
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=claude-assistant-01\$,CN=Agents,CN=System,$BASE_DN
changetype: modify
add: x-agent-DeniedTools
x-agent-DeniedTools: CN=gnu.bash,CN=Agent Tools,CN=System,$BASE_DN
EOF
```

**Windows (PowerShell):**

```powershell
# Add to denied tools via Set-ADObject
Set-ADObject -Identity (Get-ADAgent "claude-assistant-01").DistinguishedName `
    -Add @{'msDS-AgentDeniedTools' = 'CN=gnu.bash,CN=Agent Tools,CN=System,DC=corp,DC=contoso,DC=com'}
```

### Group-Based Tool Grants

Instead of granting tools to individual agents, assign agents to tool-access groups. The runtime checks group membership during authorization.

**Samba4:**

```bash
samba-tool group addmembers "ToolAccess-Development" 'claude-assistant-01$'
```

**Windows (PowerShell):**

```powershell
Add-ADGroupMember -Identity "ToolAccess-Development" -Members "claude-assistant-01"
```

### Listing Available Tools

**Samba4:**

```bash
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=Agent Tools,CN=System,$BASE_DN" \
    "(objectClass=x-agentTool)" \
    x-tool-Identifier x-tool-Category x-tool-RiskLevel x-tool-RequiredTrust
```

**Windows (PowerShell):**

```powershell
Get-ADAgentTool
```

---

## 5. Policy Management

Policies follow the GPO pattern: metadata in AD, content in SYSVOL as JSON. They control security constraints, behavior rules, resource limits, and network access.

### Priority Layers

| Priority Range | Layer | Examples |
|----------------|-------|---------|
| 0-99 | Base | `base-security`, `base-behavior`, `base-resource`, `base-network` |
| 100-199 | Type | `type-worker`, `type-coordinator`, `type-tool` |
| 150 | Trust | `trust-untrusted`, `trust-elevated` |
| 200+ | Custom | Agent-specific or team-specific overrides |

Higher priority wins when policies conflict. Policies are merged at agent boot time by priority order.

### Linking Policies to Agents

**Samba4 (agent-manager):**

```bash
agent-manager policy link claude-assistant-01 base-security \
    --domain yourdomain.com --bind-pw "$ADMIN_PW"
```

**Samba4 (ldapmodify):**

```bash
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=claude-assistant-01\$,CN=Agents,CN=System,$BASE_DN
changetype: modify
add: x-agent-Policies
x-agent-Policies: CN=base-security,CN=Agent Policies,CN=System,$BASE_DN
x-agent-Policies: CN=base-behavior,CN=Agent Policies,CN=System,$BASE_DN
x-agent-Policies: CN=base-resource,CN=Agent Policies,CN=System,$BASE_DN
x-agent-Policies: CN=type-worker,CN=Agent Policies,CN=System,$BASE_DN
EOF
```

**Windows (PowerShell):**

```powershell
Set-ADObject -Identity (Get-ADAgent "claude-assistant-01").DistinguishedName `
    -Add @{'msDS-AgentPolicies' = @(
        'CN=base-security,CN=Agent Policies,CN=System,DC=corp,DC=contoso,DC=com',
        'CN=base-behavior,CN=Agent Policies,CN=System,DC=corp,DC=contoso,DC=com'
    )}
```

### Viewing Effective Policies

**Samba4 (agent-manager):**

```bash
agent-manager policy effective claude-assistant-01 \
    --domain yourdomain.com --bind-pw "$ADMIN_PW"
```

**Samba4 (ldapsearch):**

```bash
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=claude-assistant-01\$,CN=Agents,CN=System,$BASE_DN" \
    "(objectClass=x-agent)" x-agent-Policies
```

### Creating Custom Policies

**Step 1. Create the policy JSON in SYSVOL:**

```bash
# Samba4
SYSVOL="/var/lib/samba/sysvol/yourdomain.com"

# Windows
# SYSVOL = \\yourdomain.com\SYSVOL\yourdomain.com

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

**Step 2. Create the policy object in AD:**

Samba4:

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

**Step 3. Link to agents:**

```bash
agent-manager policy link claude-assistant-01 custom-engineering \
    --domain yourdomain.com --bind-pw "$ADMIN_PW"
```

---

## 6. Instruction GPOs

Instruction GPOs deliver system prompts to agents via the AD Group Policy pattern. They are the primary mechanism for defining what an agent should do, how it should behave, and what persona it should adopt.

### How Instruction GPOs Work

```
+-----------------------------------------------------------+
|                  AD (Metadata)                            |
|                                                           |
|  CN=Agent Instructions,CN=System                          |
|    +-- CN=base-agent-instructions     (priority 0)        |
|    +-- CN=type-assistant-instructions (priority 100)      |
|    +-- CN=type-coordinator-instructions (priority 100)    |
|    +-- CN=trust-elevated-instructions (priority 200)      |
|                                                           |
+-----------------------------------------------------------+
|                 SYSVOL (Content)                           |
|                                                           |
|  sysvol/domain/AgentInstructions/                         |
|    +-- base-agent-instructions/instructions.md            |
|    +-- type-assistant-instructions/instructions.md        |
|    +-- type-coordinator-instructions/instructions.md      |
|    +-- trust-elevated-instructions/instructions.md        |
+-----------------------------------------------------------+
```

At agent boot, the runtime:

1. Reads `x-agent-InstructionGPOs` for directly linked GPOs.
2. Queries all instruction GPOs where `x-gpo-AppliesToTypes`, `x-gpo-AppliesToTrustLevels`, or `x-gpo-AppliesToGroups` matches the agent.
3. Filters to `x-gpo-Enabled=TRUE` only.
4. Sorts by `x-gpo-Priority` ascending (lowest first, highest last).
5. Fetches instruction markdown from SYSVOL via SMB at each GPO's `x-gpo-InstructionPath`.
6. Merges per `x-gpo-MergeStrategy`.
7. Result = the agent's effective system prompt.

### Merge Strategies

| Strategy | Behavior |
|----------|----------|
| `append` (default) | Concatenate after lower-priority instructions |
| `prepend` | Insert before lower-priority instructions |
| `replace` | Discard all lower-priority instructions |

### Priority Ranges

| Priority | Scope | Description |
|----------|-------|-------------|
| 0-99 | Base | Apply to all agents |
| 100-199 | Type | Apply by agent type |
| 200-299 | Trust | Apply by trust level |
| 300-399 | Group | Apply by group membership |
| 400+ | Agent | Agent-specific overrides |

### Scope Matching

A GPO applies to an agent if any of the following match (OR logic across scope dimensions):

| Scope Attribute | Matches When |
|----------------|-------------|
| `x-gpo-AppliesToTypes` | Agent's type is in the list (empty = all types) |
| `x-gpo-AppliesToTrustLevels` | Agent's trust level is in the list (empty = all levels) |
| `x-gpo-AppliesToGroups` | Agent is a member of any listed group (empty = all agents) |
| Direct link via `x-agent-InstructionGPOs` | Always applies if linked |

### Merge Order Example

For an assistant agent at trust level 2 in the `ToolAccess-Development` group:

```
Priority 0:   base-agent-instructions           (all agents)        [append]
Priority 100: type-assistant-instructions        (assistant type)    [append]
Priority 300: team-engineering-instructions       (group match)      [append]
---
Result:        base + assistant + engineering = effective system prompt
```

If the GPO at priority 300 used `replace`, the effective prompt would contain only the engineering instructions.

### Listing Instruction GPOs

**Samba4:**

```bash
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=Agent Instructions,CN=System,$BASE_DN" \
    "(objectClass=x-agentInstructionGPO)" \
    cn x-gpo-DisplayName x-gpo-Priority x-gpo-MergeStrategy \
    x-gpo-AppliesToTypes x-gpo-Enabled x-gpo-Version
```

### Creating Custom Instruction GPOs

**Step 1. Write the instruction content:**

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
- For security concerns, escalate immediately.
PROMPT
```

**Step 2. Create the GPO object in AD (Samba4):**

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

**Step 3 (optional). Link directly to a specific agent:**

If the GPO uses `x-gpo-AppliesToGroups`, any agent in that group automatically receives the instructions. For explicit linking:

```bash
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=claude-assistant-01\$,CN=Agents,CN=System,$BASE_DN
changetype: modify
add: x-agent-InstructionGPOs
x-agent-InstructionGPOs: CN=team-engineering-instructions,CN=Agent Instructions,CN=System,$BASE_DN
EOF
```

### Updating Instruction Content

Update the markdown file in SYSVOL, then bump the version in AD so agents invalidate their cache:

```bash
# 1. Edit the instruction file
vi "$SYSVOL/AgentInstructions/team-engineering-instructions/instructions.md"

# 2. Bump the version in AD
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=team-engineering-instructions,CN=Agent Instructions,CN=System,$BASE_DN
changetype: modify
replace: x-gpo-Version
x-gpo-Version: 1.1.0
EOF
```

### Disabling a GPO Without Deleting It

```bash
ldapmodify -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" <<EOF
dn: CN=team-engineering-instructions,CN=Agent Instructions,CN=System,$BASE_DN
changetype: modify
replace: x-gpo-Enabled
x-gpo-Enabled: FALSE
EOF
```

---

## 7. Authentication

Agents authenticate via Kerberos using machine account credentials (keytab or password). The authentication flow is: `kinit` (obtain TGT) then GSSAPI bind to LDAP to read configuration.

### SPN Registration

**Windows (PowerShell):**

```powershell
# Register standard SPNs (AGENT/ and HOST/)
Install-ADAgentSPN -Identity "claude-assistant-01"

# With custom hostnames
Install-ADAgentSPN -Identity "claude-assistant-01" `
    -Hostname "claude-01", "claude-01.corp.contoso.com"

# With additional service classes
Install-ADAgentSPN -Identity "claude-assistant-01" -ServiceClass "HTTP"
```

**Samba4:**

```bash
samba-tool spn add "agent/claude-assistant-01.yourdomain.com" 'claude-assistant-01$'

# Verify
samba-tool spn list 'claude-assistant-01$'
```

### Keytab Generation

**Samba4:**

```bash
# Generate keytab
samba-tool domain exportkeytab /etc/krb5.keytabs/claude-assistant-01.keytab \
    --principal='claude-assistant-01$@YOURDOMAIN.COM'

# Secure permissions
chmod 600 /etc/krb5.keytabs/claude-assistant-01.keytab

# Verify contents
klist -k -t /etc/krb5.keytabs/claude-assistant-01.keytab
```

**Windows (PowerShell):**

```powershell
# Use ktpass on DC
ktpass -princ agent/claude-assistant-01.corp.contoso.com@CORP.CONTOSO.COM `
    -mapuser claude-assistant-01 `
    -pass * `
    -crypto AES256-SHA1 `
    -ptype KRB5_NT_PRINCIPAL `
    -out C:\Keytabs\claude-assistant-01.keytab
```

### Keytab Distribution

Distribute the keytab to the agent's sandbox securely:

```bash
scp /etc/krb5.keytabs/claude-assistant-01.keytab \
    sandbox-host:/var/run/sandbox/keytabs/
```

### Agent Authentication Flow

```
Agent                         DC (KDC)                    DC (LDAP)
  |                              |                            |
  |-- kinit -kt agent.keytab -->|                            |
  |<-------- TGT --------------|                            |
  |                              |                            |
  |-- GSSAPI bind (TGT) ------->|                            |
  |                              |<-- service ticket -------->|
  |                              |                            |
  |<------ LDAP session (authenticated as agent) ----------->|
  |                              |                            |
  | ldapsearch own entry, tools, policies, instructions       |
```

### Password Rotation

Samba4 does not support gMSA (Group Managed Service Accounts). Implement keytab rotation via a cron job:

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

On Windows AD, consider using Group Managed Service Accounts (gMSA) for automatic password rotation, or implement a similar scheduled rotation script.

### Testing Authentication

**Windows (PowerShell):**

```powershell
# Test Kerberos readiness
Test-ADAgentAuthentication -Identity "claude-assistant-01" -AuthType Kerberos

# Test delegation to a specific service
Test-ADAgentAuthentication -Identity "claude-assistant-01" `
    -AuthType Kerberos -TargetService "cifs/fileserver.corp.contoso.com"

# Test certificate auth
Test-ADAgentAuthentication -Identity "claude-assistant-01" `
    -AuthType Certificate -CertificateThumbprint "A1B2C3..."
```

**Samba4 (manual):**

```bash
# Test kinit with keytab
KRB5CCNAME=/tmp/test_cc kinit -kt /etc/krb5.keytabs/claude-assistant-01.keytab \
    'claude-assistant-01$@YOURDOMAIN.COM'

# Test GSSAPI LDAP bind
KRB5CCNAME=/tmp/test_cc ldapsearch -N -H ldap://dc.yourdomain.com -Y GSSAPI \
    -b "CN=claude-assistant-01\$,CN=Agents,CN=System,$BASE_DN" \
    -s base "(objectClass=*)" cn

# Clean up
kdestroy -c /tmp/test_cc
```

---

## 8. Group Management

Groups provide role-based organization for agents. They are standard AD security groups stored in `OU=AgentGroups`.

### Tier Groups

| Group | Description | Typical Trust |
|-------|-------------|---------------|
| `Tier1-Workers` | Basic worker agents | 1 (Basic) |
| `Tier2-Specialists` | Specialist agents with standard capabilities | 2 (Standard) |
| `Tier3-Coordinators` | Coordinator agents with elevated capabilities | 3 (Elevated) |

### Tool-Access Groups

| Group | Purpose |
|-------|---------|
| `ToolAccess-Shell` | Shell execution tools (bash, restricted bash) |
| `ToolAccess-Network` | Network tools (ssh, curl, API calls) |
| `ToolAccess-Development` | Development tools (git, python, node, make) |
| `ToolAccess-Management` | Management tools (samba-tool, ldap, ray) |

### Adding Agents to Groups

**Samba4:**

```bash
samba-tool group addmembers "Tier2-Specialists" 'claude-assistant-01$'
samba-tool group addmembers "ToolAccess-Development" 'claude-assistant-01$'
```

**Windows (PowerShell):**

```powershell
Add-ADGroupMember -Identity "Tier2-Specialists" -Members "claude-assistant-01"
Add-ADGroupMember -Identity "ToolAccess-Development" -Members "claude-assistant-01"
```

### Viewing Group Memberships

**Samba4:**

```bash
# View an agent's groups
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=claude-assistant-01\$,CN=Agents,CN=System,$BASE_DN" \
    "(objectClass=x-agent)" memberOf

# View group members
samba-tool group listmembers "Tier2-Specialists"
```

**Windows (PowerShell):**

```powershell
# View agent's groups
(Get-ADAgent "claude-assistant-01").MemberOf

# View group members
Get-ADGroupMember -Identity "Tier2-Specialists"
```

### Creating Custom Groups

**Samba4 (ldbmodify):**

```bash
ldbmodify -H /var/lib/samba/private/sam.ldb <<EOF
dn: CN=Team-Engineering,OU=AgentGroups,$BASE_DN
changetype: add
objectClass: group
cn: Team-Engineering
description: Engineering team agents
groupType: -2147483646
EOF

samba-tool group addmembers "Team-Engineering" 'claude-assistant-01$'
```

**Windows (PowerShell):**

```powershell
New-ADGroup -Name "Team-Engineering" `
    -Path "OU=AgentGroups,DC=corp,DC=contoso,DC=com" `
    -GroupScope Global `
    -GroupCategory Security `
    -Description "Engineering team agents"

Add-ADGroupMember -Identity "Team-Engineering" -Members "claude-assistant-01"
```

### Group-Based Policy and Tool Scoping

Groups serve as a scoping mechanism for both policies and instruction GPOs:

- **Policies:** Policy objects can target groups via `x-policy-AppliesToTypes` or similar scope attributes. Agents in matching groups receive the policy.
- **Instruction GPOs:** The `x-gpo-AppliesToGroups` attribute on a GPO means any agent who is a member of the listed group automatically receives that GPO's instructions.
- **Tools:** Adding an agent to a `ToolAccess-*` group grants access to all tools associated with that group during runtime authorization.

---

## 9. Access Control

### DC ACL Model

Each agent authenticates with its own Kerberos identity and binds to LDAP directly. The DC enforces access control via LDAP ACLs -- there is no broker intermediary.

**Per-agent ACLs:**

| Target | Permission | Scope |
|--------|-----------|-------|
| `CN=Agents,CN=System` | Read + List (RPLCLORC) | Container + children (CI) |
| `CN=Agent Tools,CN=System` | Read + List (RPLCLORC) | Container + children (CI) |
| `CN=Agent Policies,CN=System` | Read + List (RPLCLORC) | Container + children (CI) |
| `CN=Agent Instructions,CN=System` | Read + List (RPLCLORC) | Container + children (CI) |
| Agent's own entry | Read Properties + Read Control (RPRC) | Object only (no CI) |

Administrators retain full control via inherited Domain Admin / SYSTEM grants.

### Setting ACLs (Samba4)

The bootstrap script uses `samba-tool dsacl` with SDDL ACE strings:

```bash
# Resolve agent SID (using python-samba)
AGENT_SID=$(python3 -c "
import ldb
from samba.auth import system_session
from samba.param import LoadParm
from samba.samdb import SamDB
lp = LoadParm()
lp.load_default()
samdb = SamDB(url='/var/lib/samba/private/sam.ldb', session_info=system_session(), lp=lp)
res = samdb.search(base='$BASE_DN', scope=ldb.SCOPE_SUBTREE,
    expression='(sAMAccountName=claude-assistant-01\$)',
    attrs=['objectSid'])
from samba.ndr import ndr_unpack
from samba.dcerpc import security
sid = ndr_unpack(security.dom_sid, res[0]['objectSid'][0])
print(str(sid))
")

# Grant read+list on containers (CI = Container Inherit)
for CONTAINER in "CN=Agents,CN=System,$BASE_DN" \
                 "CN=Agent Tools,CN=System,$BASE_DN" \
                 "CN=Agent Policies,CN=System,$BASE_DN" \
                 "CN=Agent Instructions,CN=System,$BASE_DN"; do
    samba-tool dsacl set \
        --objectdn="$CONTAINER" \
        --sddl="(A;CI;RPLCLORC;;;$AGENT_SID)" \
        --username=Administrator \
        --password="$ADMIN_PW"
done

# Grant read on own entry (no CI)
samba-tool dsacl set \
    --objectdn="CN=claude-assistant-01\$,CN=Agents,CN=System,$BASE_DN" \
    --sddl="(A;;RPRC;;;$AGENT_SID)" \
    --username=Administrator \
    --password="$ADMIN_PW"
```

### Setting ACLs (Windows)

```powershell
# Get agent SID
$agent = Get-ADAgent -Identity "claude-assistant-01"
$sid = $agent.ObjectSid

# Set ACL on each container
$containers = @(
    "CN=Agents,CN=System",
    "CN=Agent Tools,CN=System",
    "CN=Agent Policies,CN=System",
    "CN=Agent Instructions,CN=System"
)

foreach ($container in $containers) {
    $containerDN = "$container,$((Get-ADDomain).DistinguishedName)"
    $acl = Get-Acl "AD:\$containerDN"
    $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $sid, "ReadProperty,ListChildren,ListObject,ReadControl",
        "Allow", "All", "All"
    )
    $acl.AddAccessRule($ace)
    Set-Acl "AD:\$containerDN" $acl
}
```

### Verifying ACLs

**Samba4:**

```bash
# Test that the agent can read its own entry via GSSAPI
KRB5CCNAME=/tmp/test_cc kinit -kt /etc/krb5.keytabs/claude-assistant-01.keytab \
    'claude-assistant-01$@YOURDOMAIN.COM'

KRB5CCNAME=/tmp/test_cc ldapsearch -N -H ldap://dc.yourdomain.com -Y GSSAPI \
    -b "CN=claude-assistant-01\$,CN=Agents,CN=System,$BASE_DN" \
    -s base "(objectClass=*)" cn

# Test that the agent can list tools
KRB5CCNAME=/tmp/test_cc ldapsearch -N -H ldap://dc.yourdomain.com -Y GSSAPI \
    -b "CN=Agent Tools,CN=System,$BASE_DN" \
    -s one "(objectClass=*)" cn

kdestroy -c /tmp/test_cc
```

---

## 10. Monitoring

### Health Checks

**Samba4:**

```bash
# Domain health
samba-tool domain info yourdomain.com
samba-tool dbcheck --cross-ncs

# Docker dev environment
cd samba4/docker
make status
make integration-test
```

**Windows:**

```powershell
# Domain health
Get-ADDomainController -Discover
repadmin /showrepl
dcdiag /v
```

### Useful LDAP Queries

These queries use `ldapsearch` on Samba4. On Windows, use `Get-ADAgent` with the corresponding filters.

**Agents by type:**

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

**High-trust agents (trust level >= 3):**

```bash
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=Agents,CN=System,$BASE_DN" \
    "(&(objectClass=x-agent)(x-agent-TrustLevel>=3))" \
    cn x-agent-Type x-agent-TrustLevel x-agent-Model x-agent-Owner
```

Windows equivalent:

```powershell
Get-ADAgent -TrustLevel 3  # Note: only exact match
# For >= 3, use:
Get-ADAgent | Where-Object { $_.TrustLevel -ge 3 }
```

**Agents without an escalation path:**

```bash
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=Agents,CN=System,$BASE_DN" \
    "(&(objectClass=x-agent)(!(x-agent-EscalationPath=*)))" \
    cn x-agent-Type
```

**Agents with shell tool access:**

```bash
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=Agents,CN=System,$BASE_DN" \
    "(&(objectClass=x-agent)(x-agent-AuthorizedTools=CN=gnu.bash,CN=Agent Tools,CN=System,$BASE_DN))" \
    cn x-agent-TrustLevel
```

**Disabled instruction GPOs:**

```bash
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=Agent Instructions,CN=System,$BASE_DN" \
    "(&(objectClass=x-agentInstructionGPO)(x-gpo-Enabled=FALSE))" \
    cn x-gpo-DisplayName
```

**Sandboxes in standby:**

```bash
ldapsearch -H ldap://localhost -x \
    -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PW" \
    -b "CN=Agent Sandboxes,CN=System,$BASE_DN" \
    "(&(objectClass=x-agentSandbox)(x-sandbox-Status=standby))" \
    cn x-sandbox-SecurityProfile
```

### Integration Test Suite

The Docker dev environment includes a full integration test suite:

```bash
cd samba4/docker
make integration-test
```

This tests:

- Schema class existence (all 5 classes)
- Container existence (all 5 containers)
- Sample agent creation and attribute verification
- Keytab generation and Kerberos authentication (`kinit`)
- GSSAPI LDAP reads (agent reads own entry, tools, policies, instructions)
- `agent-manager` CLI operations

---

## 11. Security Checklist

Production readiness checklist for the Agent Directory.

### Before Going to Production

| Item | Status | Notes |
|------|--------|-------|
| **OID Registration** | | Replace `99999` with your IANA Private Enterprise Number ([register here](https://www.iana.org/assignments/enterprise-numbers/)) |
| **TLS Certificates** | | Deploy proper CA-signed certificates for LDAPS (port 636); do not use self-signed in production |
| **Password Rotation** | | Implement automated keytab rotation (weekly cron or provisioning service); Samba4 has no gMSA |
| **ACL Verification** | | Verify each agent can only read its own entry and the 4 containers; test with GSSAPI binds |
| **Port Binding** | | Bind LDAP (389), LDAPS (636), Kerberos (88), SMB (445) to internal interfaces only |
| **Schema Backup** | | Backup `sam.ldb` (Samba4) or System State (Windows) before schema modifications |
| **Replication Health** | | Confirm AD replication is healthy before and after schema installation |
| **SYSVOL Permissions** | | Restrict SYSVOL write access to administrators; agents need only SMB read |
| **Audit Logging** | | Set `x-agent-AuditLevel` >= 1 on all production agents |
| **Escalation Paths** | | Verify all agents with TrustLevel >= 2 have `x-agent-EscalationPath` set |
| **Denied Tools** | | Review and explicitly deny dangerous tools for low-trust agents (e.g., bash for trust 0-1) |
| **Group Membership** | | Audit `ToolAccess-*` group memberships; ensure no over-provisioning |
| **Sandbox Isolation** | | Verify all production sandboxes use `bwrap`, `appcontainer`, `hyperv`, or `vmware` (never `none`) |
| **Network Policies** | | Set `x-sandbox-NetworkPolicy` with explicit egress rules on all production sandboxes |
| **Resource Limits** | | Set `x-sandbox-ResourcePolicy` with CPU, memory, and disk limits on all production sandboxes |
| **Instruction GPO Review** | | Review all enabled GPOs; disable unused ones; verify SYSVOL paths exist |
| **Disabled Agent Cleanup** | | Audit and remove long-disabled agents to reduce attack surface |

### Periodic Maintenance

| Task | Frequency | Command |
|------|-----------|---------|
| Rotate agent keytabs | Weekly | `/etc/cron.weekly/rotate-agent-keytabs.sh` |
| Audit high-trust agents | Weekly | Query for `TrustLevel >= 3` and verify justification |
| Verify ACLs | Monthly | Run integration test suite or manual GSSAPI tests |
| Review tool grants | Monthly | Query agents with shell/management tools |
| Check agents without escalation path | Monthly | See LDAP query above |
| Review instruction GPO versions | Monthly | Bump stale GPO versions; clean up disabled GPOs |
| Full schema backup | Before any change | `cp /var/lib/samba/private/sam.ldb` (Samba4) or Windows System State backup |
| Replication health check | Daily | `samba-tool dbcheck` or `repadmin /showrepl` |
