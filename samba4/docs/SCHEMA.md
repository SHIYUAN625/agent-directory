# Autonomous Enterprise AD Schema - Samba4

This document describes the Active Directory schema extension for autonomous AI agents, adapted for Samba4.

## Overview

The schema extends Active Directory to support AI agents as first-class identity principals. Agents inherit from the `user` class (identity/principal), while sandboxes inherit from the `computer` class (execution environment). This mirrors how AD already works: users log into computers; agents run in sandboxes.

### Key Differences from Windows AD Version

| Feature | Windows AD | Samba4 |
|---------|-----------|--------|
| Attribute prefix | `msDS-` | `x-agent-`, `x-tool-`, `x-policy-` |
| gMSA support | Yes | No (use provisioning service for keytab rotation) |
| Schema installation | PowerShell/LDIFDE | `ldbmodify` via install script |
| Management tools | PowerShell module | Python/shell scripts |

## Object Class Hierarchy

```
top
├── person
│   └── organizationalPerson
│       └── user
│           ├── x-agent              # AI Agent identity (who)
│           └── computer
│               └── x-agentSandbox   # Execution environment (where)
├── x-agentTool                      # Tool/capability definition
└── x-agentPolicy                    # Policy object (GPO-like)
```

## Schema Components

### Agent Class (`x-agent`)

**Inherits from:** `user`

**OID:** `1.3.6.1.4.1.99999.1.1`

Inheriting from `user` provides:
- `unicodePwd` - Password-based authentication
- `servicePrincipalName` - Kerberos SPNs
- `objectSid` / `sAMAccountName` - Security principal identity
- `altSecurityIdentities` - Certificate mapping
- `userAccountControl` - Account state management

#### Agent Attributes

| Attribute | Type | Multi | Description |
|-----------|------|-------|-------------|
| `x-agent-Type` | String | No | `autonomous`, `assistant`, `tool`, `orchestrator`, `coordinator` |
| `x-agent-TrustLevel` | Integer | No | 0-4 (Untrusted → System) |
| `x-agent-Owner` | DN | No | Responsible identity |
| `x-agent-Parent` | DN | No | Parent agent for hierarchy |
| `x-agent-Model` | String | No | AI model identifier |
| `x-agent-Capabilities` | String | Yes | URN-style capability IDs |
| `x-agent-AuthorizedTools` | DN | Yes | Links to authorized tools |
| `x-agent-DeniedTools` | DN | Yes | Explicitly denied tools |
| `x-agent-DelegationScope` | String | Yes | Allowed delegation SPNs |
| `x-agent-RuntimeEndpoint` | String | No | Agent URI (DEPRECATED) |
| `x-agent-Sandbox` | DN | Yes | Linked sandbox objects |
| `x-agent-NatsSubjects` | String | Yes | NATS subscription subjects |
| `x-agent-EscalationPath` | DN | No | Escalation target |
| `x-agent-Policies` | DN | Yes | Linked policy objects |
| `x-agent-AuditLevel` | Integer | No | 0-3 audit verbosity |
| `x-agent-LLMAccess` | String | Yes | Allowed LLM models |
| `x-agent-LLMQuota` | String | No | JSON token quota |
| `x-agent-GitHubRepos` | String | Yes | Allowed repo patterns |
| `x-agent-GitHubPermissions` | String | No | `read`, `write`, `admin` |
| `x-agent-Mission` | String | No | High-level mission |
| `x-agent-StateEndpoint` | String | No | Warm storage URI |

### Sandbox Class (`x-agentSandbox`)

**Inherits from:** `computer`

**OID:** `1.3.6.1.4.1.99999.1.4`

Sandboxes represent execution environments where agents run. Inheriting from `computer` provides network identity, RBCD support, and machine account semantics.

#### Sandbox Attributes

| Attribute | Type | Multi | Description |
|-----------|------|-------|-------------|
| `x-sandbox-Endpoint` | String | No | Sandbox runtime URI |
| `x-sandbox-Agents` | DN | Yes | Agents allowed to run here |
| `x-sandbox-ResourcePolicy` | String | No | JSON resource constraints |
| `x-sandbox-NetworkPolicy` | String | No | JSON network rules |
| `x-sandbox-SecurityProfile` | String | No | Isolation technology |
| `x-sandbox-Status` | String | No | `active`, `standby`, `terminated` |

### Tool Class (`x-agentTool`)

**Inherits from:** `top`

**OID:** `1.3.6.1.4.1.99999.1.2`

#### Tool Attributes

| Attribute | Type | Multi | Description |
|-----------|------|-------|-------------|
| `x-tool-Identifier` | String | No | Canonical ID (e.g., `gnu.bash`) |
| `x-tool-DisplayName` | String | No | Human-readable name |
| `x-tool-Category` | String | No | `shell`, `development`, `network`, etc. |
| `x-tool-RiskLevel` | Integer | No | 1-5 (Minimal → Critical) |
| `x-tool-RequiredTrust` | Integer | No | Minimum trust level (0-4) |
| `x-tool-Constraints` | String | Yes | Key=value restrictions |
| `x-tool-AuditRequired` | Boolean | No | Audit all usage |
| `x-tool-Executable` | String | No | Path to executable |
| `x-tool-Version` | String | No | Minimum version |
| `x-tool-Schema` | String | No | JSON Schema for I/O |

### Policy Class (`x-agentPolicy`)

**Inherits from:** `top`

**OID:** `1.3.6.1.4.1.99999.1.3`

Policies follow a GPO-like pattern: metadata in AD, content in SYSVOL.

#### Policy Attributes

| Attribute | Type | Multi | Description |
|-----------|------|-------|-------------|
| `x-policy-Identifier` | String | No | Unique policy name |
| `x-policy-Type` | String | No | `security`, `behavior`, `resource`, `network` |
| `x-policy-Priority` | Integer | No | 0-999 (higher wins) |
| `x-policy-Path` | String | No | SYSVOL path to JSON |
| `x-policy-AppliesToTypes` | String | Yes | Matching agent types |
| `x-policy-AppliesToTrustLevels` | Integer | Yes | Matching trust levels |
| `x-policy-Enabled` | Boolean | No | Policy active |
| `x-policy-Version` | String | No | Content version |

## Trust Levels

| Level | Name | Capabilities |
|-------|------|--------------|
| 0 | Untrusted | Read-only, no network, no delegation |
| 1 | Basic | Limited read/write, no delegation, basic tools |
| 2 | Standard | Normal operations, constrained delegation, most tools |
| 3 | Elevated | Broad access, protocol transition, management tools |
| 4 | System | Full trust, unconstrained delegation, all tools |

## Tool Authorization Logic

```
1. Check if tool in DeniedTools → DENY
2. Check if tool in AuthorizedTools → ALLOW
3. Check if agent in tool-grant group → ALLOW
4. Check if agent.TrustLevel >= tool.RequiredTrust → ALLOW
5. Evaluate tool constraints → ALLOW/DENY
6. Default: DENY
```

## Policy Inheritance

```
Base Policy (Priority 0-99)      → All agents
    ↓
Type Policy (Priority 100-199)   → By agent type
    ↓
Trust Policy (Priority 150)      → By trust level
    ↓
Agent-Specific (Priority 200+)   → Individual overrides
```

Higher priority wins on conflict. Policy JSON is fetched from SYSVOL and merged at agent boot.

## Container Structure

```
DC=autonomy,DC=local
├── CN=System
│   ├── CN=Agents                    # Agent identities (user objects)
│   │   ├── CN=coordinator-main
│   │   ├── CN=worker-pool-001
│   │   └── OU=Teams/
│   ├── CN=Agent Sandboxes           # Sandbox environments (computer objects)
│   │   ├── CN=sandbox-prod-001
│   │   └── CN=sandbox-dev-001
│   ├── CN=Agent Tools               # Tool registry
│   │   ├── CN=gnu.bash
│   │   └── CN=python.interpreter
│   └── CN=Agent Policies            # Policy metadata
│       ├── CN=base-security
│       └── CN=type-coordinator
└── OU=AgentGroups                   # Capability groups
    ├── CN=Tier1-Workers
    ├── CN=Tier2-Specialists
    ├── CN=Tier3-Coordinators
    └── CN=ToolAccess-Shell
```

## Installation

```bash
# On the Samba4 DC
sudo ./install-schema.sh autonomy.local
```

See `install-schema.sh` for details.

## OID Namespace

**IMPORTANT:** Replace `99999` with your IANA Private Enterprise Number before production use.

| Range | Purpose |
|-------|---------|
| `1.3.6.1.4.1.{PEN}.1.x` | Object classes |
| `1.3.6.1.4.1.{PEN}.2.1-29` | Agent attributes |
| `1.3.6.1.4.1.{PEN}.2.30-39` | Tool attributes |
| `1.3.6.1.4.1.{PEN}.2.40-49` | Policy attributes |
| `1.3.6.1.4.1.{PEN}.2.50-59` | Sandbox attributes |

To obtain a PEN (free): https://www.iana.org/assignments/enterprise-numbers/
