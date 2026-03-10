# Agent Directory for Active Directory

First-class AI agent identities in Active Directory. Agents authenticate with their own Kerberos principals, run in sandboxes, and have their access controlled by the DC -- the same way users and services work today.

Two deployment targets:

| | Windows AD | Samba4/Linux |
|---|---|---|
| Schema prefix | `msDS-*` | `x-agent-*` |
| Management | PowerShell module | Python CLI + Makefile |
| Environment | Production DC | Docker dev environment |
| Auth | Kerberos / NTLM / certs | Kerberos (keytab, direct) |
| Logging | Windows Event Log + SIEM | Samba logs |

## Architecture

### Object Model

| Concept | AD base class | Role |
|---------|--------------|------|
| **Agent** | User + auxiliary agent class | Identity -- "the who" |
| **Sandbox** | Computer + auxiliary sandbox class | Execution -- "the where" |
| **Tool** | Registered in AD | Capability -- granted per-agent or per-group |
| **Policy** | GPO pattern: metadata in AD, content (JSON) in SYSVOL | Configuration |
| **Instruction GPO** | GPO pattern: metadata in AD, content (markdown) in SYSVOL | System prompt |

Agents authenticate with their own Kerberos identity (keytab). No broker intermediary. DC ACLs enforce what each agent can see.

### Schema Inheritance

```
Agent:   Top -> Person -> Org-Person -> User   + auxiliary agent class
Sandbox: Top -> Person -> Org-Person -> User -> Computer   + auxiliary sandbox class
```

Auxiliary classes (objectClassCategory=3) are added to existing user/computer objects. This means agents and sandboxes work with all existing AD tooling -- GPOs, delegation, LDAP queries, replication.

### Schema Naming

| Object | Windows AD | Samba4 |
|--------|-----------|--------|
| Agent | msDS-Agent | x-agent |
| Sandbox | msDS-AgentSandbox | x-agentSandbox |
| Tool | msDS-AgentTool | x-agentTool |
| Policy | msDS-AgentPolicy | x-agentPolicy |
| Instruction GPO | -- | x-agentInstructionGPO |

### Trust Levels

| Level | Name | Description |
|-------|------|-------------|
| 0 | Untrusted | No delegation, heavily restricted |
| 1 | Basic | Read, limited write, no delegation |
| 2 | Standard | Normal operations, constrained delegation |
| 3 | Elevated | Broad access, protocol transition |
| 4 | System | Full trust, equivalent to service account |

Trust levels control delegation scope, tool access, and audit intensity.

## Quick Start: Samba4/Docker

This is the primary development path. Provisions a full Samba4 AD DC with custom schema, sample agents, tools, policies, and instruction GPOs.

```bash
cd samba4/docker
cp .env.example .env
# Edit .env -- set SAMBA_ADMIN_PASSWORD and NATS_* passwords

make up              # Build + provision (~90s first boot)
make logs            # Watch for "Bootstrap complete"
make list-agents     # Verify 3 sample agents
make dry-run AGENT=claude-assistant-01   # Test agent config assembly
make integration-test                    # Run full test suite
make e2e-test                            # Validate multi-agent coordination path

# Start persistent coordination runtime (use separate terminals)
make run-coordinator
make run-worker AGENT=claude-assistant-01
make run-worker AGENT=data-processor-01

make submit-goal TITLE="Quarterly close automation" DESCRIPTION="Coordinate engineering + dataops work"
```

## Quick Start: Windows AD

Requires a Windows Server 2016+ Domain Controller, Schema Admin membership, and PowerShell 5.1+.

```powershell
# Install schema (run as Schema Admin on Schema Master DC)
.\schema\install-schema.ps1 -Verbose

# Install event log provider
.\events\Install-EventLog.ps1

# Import module
Import-Module .\powershell\AgentDirectory

# Create an agent
New-ADAgent -Name "claude-assistant-01" `
    -Type "assistant" `
    -TrustLevel 2 `
    -Model "claude-opus-4-5"

# Create a sandbox and assign it
$sandbox = New-ADAgentSandbox -Name "claude-sbx-01" -SecurityProfile "bwrap"
Set-ADAgent -Identity "claude-assistant-01" -AddSandbox $sandbox.DistinguishedName

# Grant tool access
Grant-ADAgentToolAccess -Identity "claude-assistant-01" `
    -Tool "microsoft.powershell.constrained", "microsoft.word"
```

## Directory Structure

```
agent-directory/
├── docs/                          # Documentation (Windows AD)
├── schema/                        # Windows AD LDIF schema (msDS-*)
├── samba4/                        # Samba4 deployment
│   ├── schema/                    # Samba4 LDIF schema (x-agent-*)
│   ├── docker/                    # Docker dev environment
│   ├── scripts/                   # agent-manager.py CLI
│   ├── instructions/              # Instruction GPO markdown content
│   └── docs/                      # Samba4-specific docs
├── enterprise/                    # Python enterprise runtime
│   ├── agent/                     # Base agent class
│   ├── broker/                    # Config assembler, protocol
│   └── provisioner/               # Identity pool, LDAP client
├── powershell/AgentDirectory/     # PowerShell management module
├── events/                        # Windows Event Log manifests
└── examples/                      # Example scripts
```

## PowerShell Cmdlets

### Agent Management

| Cmdlet | Description |
|--------|-------------|
| `New-ADAgent` | Create a new agent identity (user object) |
| `Get-ADAgent` | Retrieve agent(s) from the directory |
| `Set-ADAgent` | Modify agent properties |
| `Remove-ADAgent` | Delete an agent account |

### Sandbox Management

| Cmdlet | Description |
|--------|-------------|
| `New-ADAgentSandbox` | Create a new sandbox (computer object) |
| `Get-ADAgentSandbox` | Retrieve sandbox(es) from the directory |
| `Set-ADAgentSandbox` | Modify sandbox properties |
| `Remove-ADAgentSandbox` | Delete a sandbox |

### Authentication

| Cmdlet | Description |
|--------|-------------|
| `Install-ADAgentSPN` | Register Kerberos Service Principal Name |
| `Grant-ADAgentDelegation` | Configure constrained delegation |
| `Revoke-ADAgentDelegation` | Remove delegation rights |
| `Test-ADAgentAuthentication` | Verify agent authentication |

### Tool Management

| Cmdlet | Description |
|--------|-------------|
| `New-ADAgentTool` | Register a new tool |
| `Get-ADAgentTool` | Query tool definitions |
| `Grant-ADAgentToolAccess` | Authorize agent to use a tool |
| `Revoke-ADAgentToolAccess` | Remove tool authorization |
| `Test-ADAgentToolAccess` | Check if agent can use a tool |

### Policy Management

| Cmdlet | Description |
|--------|-------------|
| `New-ADAgentPolicy` | Create a new agent policy (metadata in AD, content in SYSVOL) |
| `Get-ADAgentPolicy` | Retrieve policy definitions |
| `Set-ADAgentPolicy` | Modify policy properties or content |
| `Remove-ADAgentPolicy` | Delete a policy |
| `Grant-ADAgentPolicyLink` | Link a policy to an agent or OU |
| `Revoke-ADAgentPolicyLink` | Remove a policy link |
| `Get-ADAgentEffectivePolicy` | Compute the merged effective policy for an agent |

### Instruction GPO Management

| Cmdlet | Description |
|--------|-------------|
| `New-ADAgentInstructionGPO` | Create a new instruction GPO (metadata in AD, markdown in SYSVOL) |
| `Get-ADAgentInstructionGPO` | Retrieve instruction GPO definitions |
| `Set-ADAgentInstructionGPO` | Modify instruction GPO properties or content |
| `Remove-ADAgentInstructionGPO` | Delete an instruction GPO |
| `Grant-ADAgentInstructionGPOLink` | Link an instruction GPO to an agent or OU |
| `Revoke-ADAgentInstructionGPOLink` | Remove an instruction GPO link |
| `Get-ADAgentEffectiveInstructions` | Compute the merged effective instructions for an agent |

## Makefile Targets (samba4/docker/)

### Lifecycle

| Target | Description |
|--------|-------------|
| `make up` | Build and start DC (provisions on first run) |
| `make down` | Stop DC (keeps data) |
| `make reset` | Destroy everything including volumes |
| `make shell` | Shell into DC container |
| `make logs` | Tail container logs |

### Queries

| Target | Description |
|--------|-------------|
| `make list-agents` | List all agents |
| `make list-sandboxes` | List all sandboxes |
| `make list-tools` | List all tools |
| `make list-policies` | List all policies |
| `make list-instructions` | List all instruction GPOs |
| `make get-agent AGENT=name` | Show full agent details |
| `make get-instructions AGENT=name` | Show instruction GPOs for agent |

### Mutations

| Target | Description |
|--------|-------------|
| `make create-agent NAME=x TYPE=assistant TRUST=2` | Create an agent |
| `make grant-tool AGENT=x TOOL=git.cli` | Grant tool to agent |
| `make link-policy AGENT=x POLICY=base-security` | Link policy to agent |
| `make link-gpo AGENT=x GPO=base-agent-instructions` | Link instruction GPO to agent |

### Agent Runner

| Target | Description |
|--------|-------------|
| `make run-agent AGENT=name` | Launch agent (DC-enforced, agent's own identity) |
| `make dry-run AGENT=name` | Show assembled config without launching |
| `make agent-shell` | Shell into agent container |
| `make run-coordinator [AGENT=coordinator-main]` | Run persistent MissionCoordinator loop (Python runtime) |
| `make run-worker AGENT=name` | Run persistent worker loop (Python runtime) |

### Verification

| Target | Description |
|--------|-------------|
| `make test-schema` | Verify custom schema classes exist |
| `make verify-acls` | Test DC ACL enforcement |
| `make integration-test` | Run full integration test suite |
| `make e2e-test` | Run end-to-end multi-agent coordination test |
| `make submit-goal TITLE=... [DESCRIPTION=...]` | Submit a high-level enterprise goal to `tasks.coordination` |
| `make status` | Show domain info |

## Documentation

**Windows AD**:
- [AGENT-AD-SPEC.md](docs/AGENT-AD-SPEC.md) -- Complete specification
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) -- Architecture diagrams
- [DEPLOYMENT.md](docs/DEPLOYMENT.md) -- Deployment guide
- [SECURITY-HARDENING.md](docs/SECURITY-HARDENING.md) -- Security hardening guide
- [TOOL-CATALOG.md](docs/TOOL-CATALOG.md) -- Tool registry documentation
- [EVENT-REFERENCE.md](docs/EVENT-REFERENCE.md) -- Event ID reference guide

**Samba4/Linux**:
- [SCHEMA.md](samba4/docs/SCHEMA.md) -- Samba4 schema reference
- [ADMIN-GUIDE.md](samba4/docs/ADMIN-GUIDE.md) -- Samba4 administration guide

## Security

- **Schema changes are permanent and forest-wide.** AD schema objects can be deactivated but not deleted. Changes replicate to all DCs in the forest.
- **Obtain an IANA PEN before production.** The current OID base (99999) is a placeholder.
- **Test in a lab first.** Use the Samba4/Docker environment for development and validation.
- **DC container binds to 127.0.0.1 only.** Not exposed to the network by default.
- **Admin credentials via .env.** Never hardcoded. The `.env` file is gitignored.

## License

This project is provided as a reference implementation for extending Active Directory with agent identity support.

## Contributing

Contributions are welcome. Please ensure all changes are tested in a lab environment before submitting.
