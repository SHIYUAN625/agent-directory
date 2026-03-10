# Agent Active Directory Specification

## Overview

This document specifies the Active Directory schema extension for first-class Agent identity principals. Agents are AI/LLM systems that require authentication and authorization within enterprise environments.

## Schema Naming Conventions

This spec uses the `msDS-` prefix for Windows AD deployments. For Samba4/Linux deployments, the equivalent schema uses `x-agent-`, `x-tool-`, `x-policy-`, `x-sandbox-`, and `x-gpo-` prefixes. The mapping is:

| Windows AD (this doc) | Samba4 (`samba4/docs/SCHEMA.md`) | Notes |
|----------------------|----------------------------------|-------|
| `msDS-Agent` | `x-agent` | Auxiliary class on user objects |
| `msDS-AgentSandbox` | `x-agentSandbox` | Auxiliary class on computer objects |
| `msDS-AgentTool` | `x-agentTool` | Structural class |
| `msDS-AgentPolicy` | `x-agentPolicy` | Structural class |
| N/A | `x-agentInstructionGPO` | Samba4-only, GPO-style instructions |
| `msDS-AgentType` | `x-agent-Type` | Attribute naming pattern |

The semantic model is identical — only the OID prefix and attribute naming differ. See `samba4/docs/SCHEMA.md` for the Samba4 mapping and `schema/` vs `samba4/schema/` for the respective LDIF files.

## Design Goals

1. **First-class Identity**: Agents are peers to Users and Service Accounts, not second-class citizens
2. **Native Authentication**: Full Kerberos, NTLM, and certificate support
3. **Granular Authorization**: Fine-grained control over agent capabilities and tool access
4. **Comprehensive Auditing**: Complete audit trail of all agent activities
5. **Hierarchical Trust**: Support for agent-to-agent delegation and parent-child relationships
6. **Backward Compatibility**: Legacy systems see agents as user accounts and sandboxes as computer accounts

## Schema Inheritance

### Object Class Hierarchy

```
                    top                              top
                     │                                │
                  person                           person
                     │                                │
          organizationalPerson            organizationalPerson
                     │                                │
                   user                             user
                     │                                │
               msDS-Agent                         computer
              (identity)                              │
                                            msDS-AgentSandbox
                                              (execution)
```

Two inheritance chains:

- **Agent (identity):** top -> person -> organizationalPerson -> user -> msDS-Agent
- **Sandbox (execution):** top -> person -> organizationalPerson -> user -> computer -> msDS-AgentSandbox

### Rationale for Dual Inheritance

Agents inherit from **user** for identity, while sandboxes inherit from **computer** for execution environment. This mirrors how Active Directory already works: users log into computers; agents run in sandboxes.

| Concern | Object | Inherits From | sAMAccountName | UAC |
|---------|--------|---------------|----------------|-----|
| Identity | msDS-Agent | user | No `$` suffix (e.g. `claude-assistant-01`) | 0x0200 NORMAL_ACCOUNT |
| Execution | msDS-AgentSandbox | computer | With `$` suffix (e.g. `sbx-prod-001$`) | 0x1000 WORKSTATION_TRUST_ACCOUNT |

Following the gMSA (Group Managed Service Account) pattern provides:

| Feature | Benefit |
|---------|---------|
| unicodePwd attribute | Password-based authentication |
| servicePrincipalName | Kerberos authentication |
| msDS-ManagedPasswordInterval | Automatic credential rotation |
| objectSid | Security principal identity |
| sAMAccountName | Legacy authentication |
| altSecurityIdentities | Certificate mapping |
| userAccountControl | Account state management |

## Object Class: msDS-Agent

### Class Definition

| Property | Value |
|----------|-------|
| Common Name | msDS-Agent |
| LDAP Display Name | msDS-Agent |
| OID | 1.3.6.1.4.1.{PEN}.1.1 |
| Object Class Category | 1 (Structural) |
| Subclass Of | user |
| Default Security Descriptor | Inherited from user |
| System Only | FALSE |

### Mandatory Attributes (mustContain)

All mandatory attributes are inherited from the user class:
- cn
- objectCategory
- objectClass
- sAMAccountName

### Optional Attributes (mayContain)

In addition to inherited attributes, the following agent-specific attributes are available:

| Attribute | Description |
|-----------|-------------|
| msDS-AgentType | Agent classification |
| msDS-AgentCapabilities | Registered capabilities |
| msDS-AgentOwner | Responsible identity DN |
| msDS-AgentParent | Parent agent DN |
| msDS-AgentTrustLevel | Trust tier (0-4) |
| msDS-AgentRuntimeEndpoint | **Deprecated** - use msDS-SandboxEndpoint on sandbox object |
| msDS-AgentModel | AI model identifier |
| msDS-AgentSandbox | Assigned sandbox DNs |
| msDS-AgentPolicies | Applied policy DNs |
| msDS-AgentDelegationScope | Delegation permissions |
| msDS-AgentAuditLevel | Audit verbosity |
| msDS-AgentAuthorizedTools | Authorized tool DNs |
| msDS-AgentDeniedTools | Denied tool DNs |

## Custom Attributes

### msDS-AgentType

| Property | Value |
|----------|-------|
| OID | 1.3.6.1.4.1.{PEN}.2.1 |
| Syntax | 2.5.5.12 (Unicode String) |
| Single/Multi | Single-valued |
| Indexed | TRUE |

**Valid Values:**
- `autonomous` - Self-directed agents with independent goals
- `assistant` - Interactive agents working with humans
- `tool` - Specialized single-purpose agents
- `orchestrator` - Agents that coordinate other agents

### msDS-AgentCapabilities

| Property | Value |
|----------|-------|
| OID | 1.3.6.1.4.1.{PEN}.2.2 |
| Syntax | 2.5.5.12 (Unicode String) |
| Single/Multi | Multi-valued |
| Indexed | TRUE |

**Format:** URN-style capability identifiers
```
urn:agent:capability:code-execution
urn:agent:capability:file-access
urn:agent:capability:network-access
urn:agent:capability:user-interaction
```

### msDS-AgentOwner

| Property | Value |
|----------|-------|
| OID | 1.3.6.1.4.1.{PEN}.2.3 |
| Syntax | 2.5.5.1 (DN) |
| Single/Multi | Single-valued |
| Indexed | TRUE |
| Link ID | Forward link (generate pair) |

Links to the user or group responsible for the agent.

### msDS-AgentParent

| Property | Value |
|----------|-------|
| OID | 1.3.6.1.4.1.{PEN}.2.4 |
| Syntax | 2.5.5.1 (DN) |
| Single/Multi | Single-valued |
| Indexed | TRUE |

Links to a parent agent for hierarchical agent relationships.

### msDS-AgentTrustLevel

| Property | Value |
|----------|-------|
| OID | 1.3.6.1.4.1.{PEN}.2.5 |
| Syntax | 2.5.5.9 (Integer) |
| Single/Multi | Single-valued |
| Indexed | TRUE |
| Range | 0-4 |

**Trust Level Definitions:**

| Level | Name | Capabilities |
|-------|------|--------------|
| 0 | Untrusted | Read-only, no network, no delegation |
| 1 | Basic | Limited read/write, no delegation |
| 2 | Standard | Normal operations, constrained delegation |
| 3 | Elevated | Broad access, protocol transition |
| 4 | System | Full trust, equivalent to service account |

### msDS-AgentRuntimeEndpoint (Deprecated)

> **Deprecated:** This attribute is replaced by `msDS-SandboxEndpoint` on the `msDS-AgentSandbox` object. Existing values should be migrated to the corresponding sandbox object.

| Property | Value |
|----------|-------|
| OID | 1.3.6.1.4.1.{PEN}.2.6 |
| Syntax | 2.5.5.12 (Unicode String) |
| Single/Multi | Single-valued |
| Indexed | FALSE |

**Format:** URI pointing to agent runtime
```
https://agent-runtime.corp.contoso.com:8443/agents/claude-01
grpc://localhost:50051
```

### msDS-AgentModel

| Property | Value |
|----------|-------|
| OID | 1.3.6.1.4.1.{PEN}.2.7 |
| Syntax | 2.5.5.12 (Unicode String) |
| Single/Multi | Single-valued |
| Indexed | TRUE |

**Examples:**
- `claude-opus-4-5`
- `gpt-4-turbo`
- `gemini-ultra`
- `custom-fine-tuned-v1`

### msDS-AgentPolicies

| Property | Value |
|----------|-------|
| OID | 1.3.6.1.4.1.{PEN}.2.8 |
| Syntax | 2.5.5.12 (Unicode String) |
| Single/Multi | Multi-valued |
| Indexed | FALSE |

References to policy objects or policy identifiers applied to the agent.

### msDS-AgentDelegationScope

| Property | Value |
|----------|-------|
| OID | 1.3.6.1.4.1.{PEN}.2.9 |
| Syntax | 2.5.5.12 (Unicode String) |
| Single/Multi | Multi-valued |
| Indexed | FALSE |

Defines what resources the agent can access on behalf of users. Format is service-principal-based:
```
cifs/fileserver.corp.contoso.com
http/webapp.corp.contoso.com
MSSQLSvc/sqlserver.corp.contoso.com:1433
```

### msDS-AgentAuditLevel

| Property | Value |
|----------|-------|
| OID | 1.3.6.1.4.1.{PEN}.2.10 |
| Syntax | 2.5.5.9 (Integer) |
| Single/Multi | Single-valued |
| Indexed | FALSE |
| Range | 0-3 |

**Audit Levels:**
| Level | Description |
|-------|-------------|
| 0 | Minimal - Errors only |
| 1 | Standard - Authentication and authorization events |
| 2 | Detailed - All operations |
| 3 | Debug - Full trace including internal operations |

### msDS-AgentAuthorizedTools

| Property | Value |
|----------|-------|
| OID | 1.3.6.1.4.1.{PEN}.2.11 |
| Syntax | 2.5.5.1 (DN) |
| Single/Multi | Multi-valued |
| Indexed | TRUE |
| Link ID | Forward link |

Links to msDS-AgentTool objects the agent is authorized to use.

### msDS-AgentDeniedTools

| Property | Value |
|----------|-------|
| OID | 1.3.6.1.4.1.{PEN}.2.12 |
| Syntax | 2.5.5.1 (DN) |
| Single/Multi | Multi-valued |
| Indexed | TRUE |
| Link ID | Forward link |

Links to msDS-AgentTool objects explicitly denied to the agent (overrides group grants).

### msDS-AgentSandbox

| Property | Value |
|----------|-------|
| OID | 1.3.6.1.4.1.{PEN}.2.13 |
| Syntax | 2.5.5.1 (DN) |
| Single/Multi | Multi-valued |
| Indexed | TRUE |

Links to msDS-AgentSandbox objects the agent is assigned to run in. An agent may be assigned to multiple sandboxes (e.g. a production sandbox and a development sandbox).

## Object Class: msDS-AgentSandbox

### Class Definition

| Property | Value |
|----------|-------|
| Common Name | msDS-AgentSandbox |
| LDAP Display Name | msDS-AgentSandbox |
| OID | 1.3.6.1.4.1.{PEN}.1.3 |
| Object Class Category | 1 (Structural) |
| Subclass Of | computer |
| Default Security Descriptor | Inherited from computer |
| System Only | FALSE |

### Mandatory Attributes (mustContain)

All mandatory attributes are inherited from the computer class:
- cn
- objectCategory
- objectClass
- sAMAccountName

### Optional Attributes (mayContain)

In addition to inherited attributes, the following sandbox-specific attributes are available:

| Attribute | Description |
|-----------|-------------|
| msDS-SandboxEndpoint | Runtime endpoint URI for the sandbox |
| msDS-SandboxAgents | Agent DNs authorized to run in this sandbox |
| msDS-SandboxResourcePolicy | Resource limits and quotas (CPU, memory, storage) |
| msDS-SandboxNetworkPolicy | Network access rules and firewall policies |
| msDS-SandboxSecurityProfile | Security profile name (e.g. `restricted`, `standard`, `privileged`) |
| msDS-SandboxStatus | Current sandbox status (e.g. `provisioning`, `ready`, `suspended`, `decommissioned`) |

### Sandbox Attributes

#### msDS-SandboxEndpoint

| Property | Value |
|----------|-------|
| OID | 1.3.6.1.4.1.{PEN}.2.30 |
| Syntax | 2.5.5.12 (Unicode String) |
| Single/Multi | Single-valued |
| Indexed | FALSE |

URI pointing to the sandbox runtime environment.

#### msDS-SandboxAgents

| Property | Value |
|----------|-------|
| OID | 1.3.6.1.4.1.{PEN}.2.31 |
| Syntax | 2.5.5.1 (DN) |
| Single/Multi | Multi-valued |
| Indexed | TRUE |

Back-link to msDS-Agent objects authorized to execute in this sandbox.

#### msDS-SandboxResourcePolicy

| Property | Value |
|----------|-------|
| OID | 1.3.6.1.4.1.{PEN}.2.32 |
| Syntax | 2.5.5.12 (Unicode String) |
| Single/Multi | Single-valued |
| Indexed | FALSE |

JSON or structured string defining resource limits (CPU, memory, storage quotas).

#### msDS-SandboxNetworkPolicy

| Property | Value |
|----------|-------|
| OID | 1.3.6.1.4.1.{PEN}.2.33 |
| Syntax | 2.5.5.12 (Unicode String) |
| Single/Multi | Single-valued |
| Indexed | FALSE |

Network access rules and firewall policies applied to the sandbox.

#### msDS-SandboxSecurityProfile

| Property | Value |
|----------|-------|
| OID | 1.3.6.1.4.1.{PEN}.2.34 |
| Syntax | 2.5.5.12 (Unicode String) |
| Single/Multi | Single-valued |
| Indexed | TRUE |

Named security profile applied to the sandbox (e.g. `restricted`, `standard`, `privileged`).

#### msDS-SandboxStatus

| Property | Value |
|----------|-------|
| OID | 1.3.6.1.4.1.{PEN}.2.35 |
| Syntax | 2.5.5.12 (Unicode String) |
| Single/Multi | Single-valued |
| Indexed | TRUE |

Current operational status of the sandbox: `provisioning`, `ready`, `suspended`, `decommissioned`.

## Authentication

### Kerberos Authentication

Agents authenticate using Kerberos via Service Principal Names (SPNs).

**SPN Format:**
```
AGENT/<hostname>@REALM
AGENT/<hostname>.<domain>@REALM
```

**Example:**
```
AGENT/claude-01@CORP.CONTOSO.COM
AGENT/claude-01.corp.contoso.com@CORP.CONTOSO.COM
```

### NTLM Authentication

Agents can authenticate using NTLM via the inherited unicodePwd attribute from the User class.

### Certificate Authentication

Agents support certificate-based authentication via the altSecurityIdentities attribute.

**Mapping Format:**
```
X509:<I>DC=com,DC=contoso,DC=corp,CN=IssuingCA<S>CN=claude-01,OU=Agents,DC=corp,DC=contoso,DC=com
```

### Managed Password

Like gMSAs, agents can use managed passwords with automatic rotation:

```powershell
# Configure managed password
Set-ADAgent -Identity "claude-01" -ManagedPasswordIntervalInDays 30
```

## Authorization

### Constrained Delegation

Agents support Kerberos constrained delegation for acting on behalf of users.

**Configuration:**
```powershell
Set-ADAgent -Identity "claude-01" `
    -TrustedForDelegation $false `
    -TrustedToAuthForDelegation $true `
    -PrincipalsAllowedToDelegateToAccount @("user1", "user2")
```

### Resource-Based Constrained Delegation (RBCD)

RBCD is configured on the sandbox (computer) object, not the agent (user) object. This ensures delegation is scoped to the execution environment:

```powershell
$sandbox = Get-ADAgentSandbox -Identity "sandbox-prod-001"
Set-ADComputer -Identity $sandbox.DistinguishedName -PrincipalsAllowedToDelegateToAccount @($serviceAccount)
```

### Tool-Based Authorization

Agents must be explicitly authorized to use specific tools. See [TOOL-CATALOG.md](TOOL-CATALOG.md) for details.

## Container Structure

### Agent, Sandbox, and Tool Containers

```
DC=corp,DC=contoso,DC=com
└── CN=System
    ├── CN=Agents
    │   ├── CN=claude-assistant-01
    │   └── CN=orchestrator-main
    ├── CN=Agent Sandboxes
    │   ├── CN=sandbox-prod-001
    │   └── CN=sandbox-dev-001
    └── CN=Agent Tools
        ├── CN=microsoft.powershell
        └── CN=microsoft.word
```

### Sandbox Container

The `CN=Agent Sandboxes` container holds `msDS-AgentSandbox` (computer-derived) objects. Each sandbox represents an isolated execution environment that one or more agents can be assigned to run in.

## Security Considerations

### Account Flags

Default userAccountControl flags for **agents** (user-derived):

| Flag | Value | Description |
|------|-------|-------------|
| ACCOUNTDISABLE | 0x0002 | Initially disabled until configured |
| NORMAL_ACCOUNT | 0x0200 | Standard user account type |
| DONT_EXPIRE_PASSWORD | 0x10000 | For managed credentials |
| TRUSTED_FOR_DELEGATION | 0x80000 | Only for Trust Level 4 |

Default userAccountControl flags for **sandboxes** (computer-derived):

| Flag | Value | Description |
|------|-------|-------------|
| WORKSTATION_TRUST_ACCOUNT | 0x1000 | Computer account type |
| DONT_EXPIRE_PASSWORD | 0x10000 | For managed credentials |

### Protected Users Group

Agents with Trust Level 3+ should NOT be added to Protected Users group as this would disable delegation.

### AdminSDHolder

High-trust agents may be protected by AdminSDHolder depending on delegation configuration.

## Naming Conventions

### sAMAccountName

**Agents** (user objects):
- Maximum 20 characters, no `$` suffix
- Format: `{name}`
- Example: `claude-assistant-01`, `orchestrator-main`

**Sandboxes** (computer objects):
- Maximum 15 characters + `$` suffix
- Format: `sbx-{name}$`
- Example: `sbx-prod-001$`, `sbx-dev-001$`

### Distinguished Name

```
CN=claude-assistant-01,CN=Agents,CN=System,DC=corp,DC=contoso,DC=com
```

### User Principal Name (UPN)

```
claude-assistant-01@corp.contoso.com
```

### Service Principal Name (SPN)

```
AGENT/claude-assistant-01
AGENT/claude-assistant-01.corp.contoso.com
HOST/claude-assistant-01 (for NTLM fallback)
```

## Replication

### Partial Attribute Set (PAS)

The following agent attributes are recommended for the Global Catalog:
- msDS-AgentType
- msDS-AgentOwner
- msDS-AgentTrustLevel
- msDS-AgentModel

### Replication Metadata

Agent credential changes replicate with urgent priority (like user password changes).

## Schema Installation

### Prerequisites

1. Schema Admin group membership
2. Enterprise Admin group membership (for container creation)
3. Connectivity to Schema Master DC
4. IANA Private Enterprise Number for production OIDs

### Installation Order

1. Agent attributes (01-agent-attributes.ldif)
1b. Sandbox attributes (01b-sandbox-attributes.ldif)
2. Tool attributes (02-tool-attributes.ldif)
3. Agent class (03-agent-class.ldif)
3b. Sandbox class (03b-sandbox-class.ldif)
4. Tool class (04-tool-class.ldif)
5. Containers (05-containers.ldif)
6. Default tools (06-default-tools.ldif)

## Compliance Considerations

### SOX Compliance

- Agent activities logged to tamper-evident audit trail
- Owner accountability for all agent actions
- Segregation of duties via Trust Levels

### GDPR Compliance

- Agent access to personal data tracked via audit events
- Data access scope defined in msDS-AgentDelegationScope
- Owner responsible for agent's data processing activities

### HIPAA Compliance

- Healthcare agents require Trust Level 3+ for PHI access
- All PHI access logged at Audit Level 2+
- Break-glass procedures documented for emergency access

## Migration Path

### From Service Accounts

1. Document existing service account usage
2. Create corresponding agent with same permissions
3. Update SPN registrations
4. Migrate keytabs/passwords
5. Add tool authorizations
6. Update delegation settings
7. Disable old service account

### From gMSAs

1. Create agent with matching password interval
2. Configure same delegation settings
3. Add tool authorizations based on service usage
4. Update application configurations
5. Monitor during transition period
6. Disable old gMSA
