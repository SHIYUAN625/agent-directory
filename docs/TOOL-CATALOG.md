# Tool Catalog

## Overview

The Tool Catalog defines all registered tools and applications that agents can be authorized to use. Each tool is represented as an `msDS-AgentTool` object in Active Directory.

## Tool Object Class: msDS-AgentTool

### Class Definition

| Property | Value |
|----------|-------|
| Common Name | msDS-AgentTool |
| LDAP Display Name | msDS-AgentTool |
| OID | 1.3.6.1.4.1.{PEN}.1.2 |
| Object Class Category | 1 (Structural) |
| Subclass Of | top |
| System Only | FALSE |

### Tool Attributes

| Attribute | OID | Syntax | Multi | Description |
|-----------|-----|--------|-------|-------------|
| msDS-ToolIdentifier | .2.20 | Unicode String | No | Canonical tool ID |
| msDS-ToolDisplayName | .2.21 | Unicode String | No | Human-readable name |
| msDS-ToolCategory | .2.22 | Unicode String | No | Tool category |
| msDS-ToolExecutable | .2.23 | Unicode String | No | Path or identifier |
| msDS-ToolVersion | .2.24 | Unicode String | No | Minimum version |
| msDS-ToolRiskLevel | .2.25 | Integer | No | Risk classification (1-5) |
| msDS-ToolRequiredTrustLevel | .2.26 | Integer | No | Minimum agent trust |
| msDS-ToolConstraints | .2.27 | Unicode String | Yes | Usage restrictions |
| msDS-ToolAuditRequired | .2.28 | Boolean | No | Audit requirement |

## Tool Categories

| Category | Description |
|----------|-------------|
| shell | Command-line interpreters and scripting environments |
| office | Productivity applications (documents, spreadsheets, etc.) |
| management | System and infrastructure management tools |
| development | Software development tools and IDEs |
| network | Network access and remote connectivity tools |
| security | Security-related utilities |
| filesystem | File system access capabilities |
| data | Database and data access tools |

## Risk Levels

| Level | Name | Description | Examples |
|-------|------|-------------|----------|
| 1 | Minimal | Read-only, no system impact | File read, PowerPoint view |
| 2 | Low | Limited write, confined scope | Word, Excel (no macros) |
| 3 | Moderate | System access, network capable | Bash, SSH, Git |
| 4 | High | Administrative potential, broad access | PowerShell, Docker |
| 5 | Critical | Full system control, security sensitive | GPO, SCCM, Cert utilities |

## Trust Level Requirements

Agents must have a trust level equal to or greater than the tool's required trust level.

| Tool Risk Level | Minimum Agent Trust Level |
|-----------------|---------------------------|
| 1 | 0 (Untrusted) |
| 2 | 1 (Basic) |
| 3 | 2 (Standard) |
| 4 | 2 (Standard) |
| 5 | 3 (Elevated) |

---

## Pre-Defined Tool Registry

### Shell & Scripting Tools

#### microsoft.powershell

| Property | Value |
|----------|-------|
| Display Name | PowerShell |
| Category | shell |
| Executable | %SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe |
| Risk Level | 4 |
| Required Trust | 2 |
| Audit Required | TRUE |

**Constraints:**
- ExecutionPolicy must be RemoteSigned or AllSigned
- Transcript logging required
- Module restrictions may apply

#### microsoft.powershell.constrained

| Property | Value |
|----------|-------|
| Display Name | PowerShell (Constrained Language) |
| Category | shell |
| Executable | %SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe |
| Risk Level | 2 |
| Required Trust | 1 |
| Audit Required | TRUE |

**Constraints:**
- LanguageMode=ConstrainedLanguage
- Limited cmdlets available
- No Add-Type or custom .NET

#### microsoft.cmd

| Property | Value |
|----------|-------|
| Display Name | Command Prompt |
| Category | shell |
| Executable | %SystemRoot%\System32\cmd.exe |
| Risk Level | 3 |
| Required Trust | 2 |
| Audit Required | TRUE |

#### gnu.bash

| Property | Value |
|----------|-------|
| Display Name | Bash Shell |
| Category | shell |
| Executable | /bin/bash or WSL |
| Risk Level | 3 |
| Required Trust | 2 |
| Audit Required | TRUE |

#### python.interpreter

| Property | Value |
|----------|-------|
| Display Name | Python Interpreter |
| Category | development |
| Executable | python.exe / python3 |
| Risk Level | 3 |
| Required Trust | 2 |
| Audit Required | TRUE |

---

### Microsoft Office Applications

#### microsoft.word

| Property | Value |
|----------|-------|
| Display Name | Microsoft Word |
| Category | office |
| Executable | WINWORD.EXE |
| Risk Level | 2 |
| Required Trust | 1 |
| Audit Required | FALSE |

**Constraints:**
- Macros disabled by default
- External content blocked

#### microsoft.excel

| Property | Value |
|----------|-------|
| Display Name | Microsoft Excel |
| Category | office |
| Executable | EXCEL.EXE |
| Risk Level | 2 |
| Required Trust | 1 |
| Audit Required | FALSE |

**Constraints:**
- Macros disabled by default
- External data connections require approval

#### microsoft.outlook

| Property | Value |
|----------|-------|
| Display Name | Microsoft Outlook |
| Category | office |
| Executable | OUTLOOK.EXE |
| Risk Level | 3 |
| Required Trust | 2 |
| Audit Required | TRUE |

**Constraints:**
- Send-on-behalf requires delegation
- Calendar access may be restricted
- Attachment handling policies apply

#### microsoft.powerpoint

| Property | Value |
|----------|-------|
| Display Name | Microsoft PowerPoint |
| Category | office |
| Executable | POWERPNT.EXE |
| Risk Level | 1 |
| Required Trust | 1 |
| Audit Required | FALSE |

#### microsoft.access

| Property | Value |
|----------|-------|
| Display Name | Microsoft Access |
| Category | office |
| Executable | MSACCESS.EXE |
| Risk Level | 3 |
| Required Trust | 2 |
| Audit Required | TRUE |

**Constraints:**
- VBA execution restricted
- External database connections require approval

#### microsoft.teams

| Property | Value |
|----------|-------|
| Display Name | Microsoft Teams |
| Category | office |
| Executable | Teams.exe |
| Risk Level | 2 |
| Required Trust | 1 |
| Audit Required | FALSE |

**Constraints:**
- Bot framework integration required
- Channel posting may require approval

---

### Management Tools

#### microsoft.sccm

| Property | Value |
|----------|-------|
| Display Name | SCCM / ConfigMgr |
| Category | management |
| Executable | ConfigurationManager module |
| Risk Level | 5 |
| Required Trust | 3 |
| Audit Required | TRUE |

**Constraints:**
- Collection targeting restrictions
- Deployment approval required
- Query-only mode available

#### microsoft.intune

| Property | Value |
|----------|-------|
| Display Name | Microsoft Intune |
| Category | management |
| Executable | Graph API / Intune module |
| Risk Level | 5 |
| Required Trust | 3 |
| Audit Required | TRUE |

**Constraints:**
- Device targeting restrictions
- Policy deployment requires approval

#### microsoft.azuread

| Property | Value |
|----------|-------|
| Display Name | Azure AD / Entra ID |
| Category | management |
| Executable | AzureAD / Microsoft.Graph modules |
| Risk Level | 5 |
| Required Trust | 3 |
| Audit Required | TRUE |

**Constraints:**
- User/group modification restrictions
- Role assignment prohibited without approval
- Conditional Access read-only

#### microsoft.exchange

| Property | Value |
|----------|-------|
| Display Name | Exchange Management |
| Category | management |
| Executable | ExchangeOnlineManagement module |
| Risk Level | 5 |
| Required Trust | 3 |
| Audit Required | TRUE |

**Constraints:**
- Mailbox access restrictions
- Transport rule modification prohibited
- Distribution list management only

#### microsoft.aduc

| Property | Value |
|----------|-------|
| Display Name | AD Users & Computers |
| Category | management |
| Executable | ActiveDirectory module |
| Risk Level | 4 |
| Required Trust | 3 |
| Audit Required | TRUE |

**Constraints:**
- OU scope restrictions
- Password reset requires approval
- Group membership changes logged

#### microsoft.gpo

| Property | Value |
|----------|-------|
| Display Name | Group Policy Management |
| Category | management |
| Executable | GroupPolicy module |
| Risk Level | 5 |
| Required Trust | 4 |
| Audit Required | TRUE |

**Constraints:**
- GPO creation prohibited without approval
- Link operations restricted
- Security settings read-only

#### microsoft.dns

| Property | Value |
|----------|-------|
| Display Name | DNS Management |
| Category | management |
| Executable | DnsServer module |
| Risk Level | 4 |
| Required Trust | 3 |
| Audit Required | TRUE |

**Constraints:**
- Zone modifications restricted
- Record creation requires approval for specific zones

#### microsoft.dhcp

| Property | Value |
|----------|-------|
| Display Name | DHCP Management |
| Category | management |
| Executable | DhcpServer module |
| Risk Level | 4 |
| Required Trust | 3 |
| Audit Required | TRUE |

**Constraints:**
- Scope modifications restricted
- Reservation management only

---

### Development Tools

#### microsoft.vscode

| Property | Value |
|----------|-------|
| Display Name | Visual Studio Code |
| Category | development |
| Executable | Code.exe |
| Risk Level | 2 |
| Required Trust | 1 |
| Audit Required | FALSE |

**Constraints:**
- Extension installation restricted
- Terminal access separate authorization

#### microsoft.visualstudio

| Property | Value |
|----------|-------|
| Display Name | Visual Studio |
| Category | development |
| Executable | devenv.exe |
| Risk Level | 2 |
| Required Trust | 1 |
| Audit Required | FALSE |

#### git.cli

| Property | Value |
|----------|-------|
| Display Name | Git CLI |
| Category | development |
| Executable | git.exe |
| Risk Level | 2 |
| Required Trust | 1 |
| Audit Required | FALSE |

**Constraints:**
- Push access requires additional authorization
- Credential helper restrictions

#### docker.cli

| Property | Value |
|----------|-------|
| Display Name | Docker CLI |
| Category | development |
| Executable | docker.exe |
| Risk Level | 4 |
| Required Trust | 2 |
| Audit Required | TRUE |

**Constraints:**
- Privileged containers prohibited
- Host mount restrictions
- Network mode restrictions

#### kubernetes.kubectl

| Property | Value |
|----------|-------|
| Display Name | Kubectl |
| Category | development |
| Executable | kubectl.exe |
| Risk Level | 4 |
| Required Trust | 3 |
| Audit Required | TRUE |

**Constraints:**
- Namespace restrictions
- Secret access prohibited without approval
- Deployment modifications restricted

---

### Network & Security Tools

#### network.ssh

| Property | Value |
|----------|-------|
| Display Name | SSH Client |
| Category | network |
| Executable | ssh.exe / OpenSSH |
| Risk Level | 3 |
| Required Trust | 2 |
| Audit Required | TRUE |

**Constraints:**
- Destination whitelist required
- Key-based auth only
- Port forwarding prohibited

#### network.rdp

| Property | Value |
|----------|-------|
| Display Name | Remote Desktop |
| Category | network |
| Executable | mstsc.exe |
| Risk Level | 4 |
| Required Trust | 2 |
| Audit Required | TRUE |

**Constraints:**
- Destination whitelist required
- Clipboard disabled
- Drive redirection prohibited

#### network.winrm

| Property | Value |
|----------|-------|
| Display Name | WinRM / PS Remoting |
| Category | network |
| Executable | WinRM service |
| Risk Level | 4 |
| Required Trust | 3 |
| Audit Required | TRUE |

**Constraints:**
- Destination whitelist required
- JEA endpoints preferred
- Full language mode requires approval

#### security.certutil

| Property | Value |
|----------|-------|
| Display Name | Certificate Utilities |
| Category | security |
| Executable | certutil.exe |
| Risk Level | 4 |
| Required Trust | 3 |
| Audit Required | TRUE |

**Constraints:**
- CA operations prohibited
- Certificate request only
- Key export prohibited

#### security.secretstore

| Property | Value |
|----------|-------|
| Display Name | Secret Store Access |
| Category | security |
| Executable | SecretManagement module |
| Risk Level | 5 |
| Required Trust | 3 |
| Audit Required | TRUE |

**Constraints:**
- Read-only by default
- Write requires additional approval
- Specific secret scope restrictions

---

### File System & Data

#### filesystem.read

| Property | Value |
|----------|-------|
| Display Name | File System Read |
| Category | filesystem |
| Executable | N/A (capability) |
| Risk Level | 1 |
| Required Trust | 0 |
| Audit Required | FALSE |

**Constraints:**
- Path whitelist may apply
- Sensitive directories excluded

#### filesystem.write

| Property | Value |
|----------|-------|
| Display Name | File System Write |
| Category | filesystem |
| Executable | N/A (capability) |
| Risk Level | 3 |
| Required Trust | 1 |
| Audit Required | TRUE |

**Constraints:**
- Path whitelist required
- Executable creation prohibited
- System directories excluded

#### filesystem.delete

| Property | Value |
|----------|-------|
| Display Name | File System Delete |
| Category | filesystem |
| Executable | N/A (capability) |
| Risk Level | 4 |
| Required Trust | 2 |
| Audit Required | TRUE |

**Constraints:**
- Path whitelist required
- Recursive delete requires approval
- System directories excluded

#### database.sql

| Property | Value |
|----------|-------|
| Display Name | SQL Query Execution |
| Category | data |
| Executable | sqlcmd / SQL modules |
| Risk Level | 4 |
| Required Trust | 2 |
| Audit Required | TRUE |

**Constraints:**
- Connection string whitelist
- DDL operations prohibited
- Query timeout enforced
- Row limit enforced

#### api.http

| Property | Value |
|----------|-------|
| Display Name | HTTP/REST API Calls |
| Category | network |
| Executable | Invoke-RestMethod / curl |
| Risk Level | 2 |
| Required Trust | 1 |
| Audit Required | FALSE |

**Constraints:**
- Destination whitelist may apply
- Internal APIs only by default
- Request rate limiting

---

## Tool Authorization Model

### Direct Assignment

Tools are assigned directly to agents via the `msDS-AgentAuthorizedTools` attribute.

```powershell
Grant-ADAgentToolAccess -Identity "claude-01" -Tool "microsoft.word", "microsoft.excel"
```

### Group-Based Assignment

Create AD security groups that grant tool access:

| Group Name | Grants Access To |
|------------|------------------|
| AG-Tools-Shell-Basic | microsoft.cmd, gnu.bash |
| AG-Tools-Shell-PowerShell | microsoft.powershell, microsoft.powershell.constrained |
| AG-Tools-Office-Basic | microsoft.word, microsoft.excel, microsoft.powerpoint |
| AG-Tools-Office-Full | All Office applications |
| AG-Tools-Management-ReadOnly | ADUC (read), DNS (read), DHCP (read) |
| AG-Tools-Management-Full | All management tools |
| AG-Tools-Development | VS Code, Visual Studio, Git, Docker |

### Deny List

Explicitly denied tools via `msDS-AgentDeniedTools` override any grants:

```powershell
# Even if agent is in AG-Tools-Management-Full, deny GPO access
Set-ADAgent -Identity "claude-01" -DeniedTools "microsoft.gpo"
```

### Authorization Flow

```
1. Agent requests tool access
         │
         ▼
2. Check msDS-AgentDeniedTools
         │
    ┌────┴────┐
    │ DENIED? │
    └────┬────┘
         │ No
         ▼
3. Check msDS-AgentAuthorizedTools
         │
    ┌────┴────┐
    │ GRANTED?│──Yes──▶ ALLOW
    └────┬────┘
         │ No
         ▼
4. Check group memberships for tool grants
         │
    ┌────┴────┐
    │ GRANTED?│──Yes──▶ ALLOW
    └────┬────┘
         │ No
         ▼
5. Check trust level vs tool requirement
         │
    ┌────┴────────┐
    │ SUFFICIENT? │──Yes──▶ ALLOW (implicit)
    └────┬────────┘
         │ No
         ▼
      DENY
```

## Custom Tool Registration

Organizations can register custom tools:

```powershell
New-ADAgentTool -Identifier "contoso.erp-client" `
    -DisplayName "Contoso ERP Client" `
    -Category "data" `
    -Executable "C:\Program Files\Contoso\ERP\Client.exe" `
    -RiskLevel 3 `
    -RequiredTrustLevel 2 `
    -AuditRequired $true `
    -Constraints "ConnectionTimeout=30", "ReadOnlyMode=true"
```

## Tool Constraints

Constraints are key-value pairs that define runtime restrictions:

| Constraint | Description | Example |
|------------|-------------|---------|
| LanguageMode | PowerShell language mode | ConstrainedLanguage |
| ExecutionPolicy | PowerShell execution policy | RemoteSigned |
| MacrosEnabled | Office macro execution | false |
| ExternalContent | Office external content | false |
| ConnectionTimeout | Maximum connection time | 30 |
| RowLimit | Maximum database rows | 10000 |
| PathWhitelist | Allowed file paths | C:\Data\* |
| DestinationWhitelist | Allowed network targets | *.corp.contoso.com |
| ReadOnlyMode | Prevent modifications | true |

## Tool Usage Auditing

All tool usage is logged to the Agent Directory event log:

- Event ID 4000: Tool execution started
- Event ID 4001: Tool execution completed
- Event ID 4002: Tool execution failed
- Event ID 4020: Specific command logged

Query tool usage:

```powershell
Get-ADAgentToolUsage -Agent "claude-01" -Tool "microsoft.powershell" -StartTime (Get-Date).AddDays(-7)
```

---

## Relationship to Sandboxes

Sandbox security profiles directly affect which tools an agent can use at runtime, independent of AD-level tool authorization.

### Profile-Based Tool Filtering

Even if an agent is authorized for a tool in AD, the sandbox security profile may prevent the tool from functioning. The sandbox enforces hard boundaries that tool grants cannot override.

| Sandbox Profile | Effect on Tools |
|-----------------|-----------------|
| `bwrap` (no network) | Network tools (SSH, RDP, WinRM, HTTP) are non-functional |
| `bwrap` (read-only FS) | filesystem.write, filesystem.delete are blocked |
| `docker` (filtered network) | Network tools limited to allowlisted destinations |
| `docker` (no host mounts) | Tools requiring host paths (SCCM, GPO) are unavailable |

### Runtime Resolution

The effective tool set for an agent is the intersection of:

1. **AD authorization** -- tools granted via direct assignment, group membership, or trust level
2. **Sandbox capability** -- tools that can physically execute within the sandbox's security profile
3. **Tool constraints** -- per-tool restrictions (path whitelists, connection limits, etc.)

```powershell
# Check effective tools considering sandbox restrictions
Get-ADAgentEffectiveTools -Identity "claude-01" -IncludeSandboxFiltering
```

If a tool is authorized in AD but blocked by the sandbox profile, the agent receives a clear denial (Event ID 3001 with DenialReason `SandboxRestriction`) rather than an opaque execution failure.

---

## Relationship to Instruction GPOs

Instruction GPOs define agent behavior through markdown-formatted system prompts stored in SYSVOL. These instructions can reference tool capabilities to guide agent behavior.

### Tool References in Instructions

Instruction GPO content can reference tools by their canonical identifier to provide context-aware guidance:

- **Permitted tool lists:** Instructions may enumerate which tools the agent should prefer for specific tasks, aligning behavioral guidance with AD-level authorization.
- **Tool-specific directives:** Instructions can include usage patterns, safety rules, or escalation procedures for individual tools (e.g., "always use `microsoft.powershell.constrained` instead of `microsoft.powershell` unless elevated access is explicitly required").
- **Fallback behavior:** Instructions can define what the agent should do when a preferred tool is unavailable due to sandbox restrictions or revoked access.

### Consistency Considerations

Instruction GPOs are authored independently of tool grants. Administrators should ensure that:

- Instructions do not reference tools the agent is not authorized to use. Use `Get-ADAgentEffectivePolicy` to audit alignment.
- When tool access is revoked, review linked instruction GPOs for stale references.
- Tool constraint changes (e.g., tightening a path whitelist) may invalidate assumptions in instruction content.
