# Security Hardening Guide

This guide provides security best practices for deploying and operating the Agent Directory system.

## Table of Contents

1. [Principle of Least Privilege](#principle-of-least-privilege)
2. [Credential Protection](#credential-protection)
3. [Access Control](#access-control)
4. [Network Security](#network-security)
5. [Monitoring and Alerting](#monitoring-and-alerting)
6. [Attack Surface Reduction](#attack-surface-reduction)
7. [Sandbox Isolation](#sandbox-isolation)
8. [Instruction GPO Content Integrity](#instruction-gpo-content-integrity)
9. [Incident Response](#incident-response)
10. [Compliance Considerations](#compliance-considerations)

---

## Principle of Least Privilege

### Agent Trust Levels

**Always start with the lowest trust level that enables required functionality.**

| Scenario | Recommended Trust Level |
|----------|-------------------------|
| Read-only data access | 0 (Untrusted) |
| Document processing | 1 (Basic) |
| General assistant tasks | 2 (Standard) |
| IT operations automation | 3 (Elevated) |
| Infrastructure management | 4 (System) - Use sparingly |

```powershell
# Create agents with minimal trust
New-ADAgent -Name "reader-agent" -Type "tool" -TrustLevel 0

# Only elevate when necessary and justified
Set-ADAgent -Identity "reader-agent" -TrustLevel 1 -Description "Elevated for document editing"
```

### Tool Authorization

**Explicitly authorize only required tools. Never rely solely on trust level matching.**

```powershell
# Good: Explicit tool grants
Grant-ADAgentToolAccess -Identity "assistant-01" -Tool "microsoft.word", "microsoft.excel"

# Better: Use tool groups for consistent policies
Add-ADGroupMember -Identity "AG-Tools-Office-Basic" -Members "assistant-01"

# Best: Deny high-risk tools explicitly
Revoke-ADAgentToolAccess -Identity "assistant-01" -Tool "microsoft.powershell" -Deny
```

### Delegation Scope

**Limit delegation to specific services, never use unconstrained delegation.**

```powershell
# Good: Constrained delegation to specific services
Grant-ADAgentDelegation -Identity "file-agent" `
    -TargetService "cifs/fileserver.corp.contoso.com"

# Bad: Unconstrained delegation (never do this)
# Set-ADAgent -Identity "file-agent" -TrustedForDelegation $true

# Best: Resource-based constrained delegation
Set-ADComputer -Identity "fileserver" `
    -PrincipalsAllowedToDelegateToAccount "file-agent"
```

---

## Credential Protection

### Password Management

**Use managed passwords (gMSA-style) whenever possible.**

```powershell
# Configure managed password rotation
Set-ADAgent -Identity "assistant-01" -ManagedPasswordIntervalInDays 30
```

### Keytab Security

**Keytab files contain credentials and must be protected.**

| Control | Implementation |
|---------|----------------|
| File permissions | Owner-only read (chmod 400 on Linux, NTFS ACL on Windows) |
| Storage location | Encrypted volume or secrets manager |
| Rotation | Rotate at least every 90 days |
| Monitoring | Alert on unauthorized access attempts |

```bash
# Linux: Secure keytab permissions
chmod 400 /etc/security/agent.keytab
chown agent-service:agent-service /etc/security/agent.keytab

# Store in secrets manager instead
vault kv put secret/agents/assistant-01 keytab=@agent.keytab
```

### Certificate Management

**Use short-lived certificates and proper PKI practices.**

| Control | Recommendation |
|---------|----------------|
| Certificate lifetime | 30-90 days maximum |
| Key length | RSA 2048+ or ECC P-256+ |
| Key storage | TPM or HSM where possible |
| Revocation | Enable CRL/OCSP checking |

```powershell
# Request agent certificate with appropriate settings
$certParams = @{
    Subject = "CN=assistant-01,OU=Agents,DC=corp,DC=contoso,DC=com"
    Template = "AgentAuthentication"
    KeyLength = 2048
    NotAfter = (Get-Date).AddDays(90)
}
```

### Secrets in Memory

**Minimize credential exposure in memory.**

- Clear credentials from memory after use
- Use SecureString for password handling
- Avoid logging credential-related data
- Implement secure memory wiping on agent shutdown

---

## Access Control

### Container Permissions

**Lock down the Agents and Tools containers.**

```powershell
# Recommended ACL for Agents container
$agentsContainer = "AD:CN=Agents,CN=System,DC=corp,DC=contoso,DC=com"

# Remove Authenticated Users default permissions
$acl = Get-Acl $agentsContainer
$authUsers = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-11")
$acl.Access | Where-Object { $_.IdentityReference -eq $authUsers } | ForEach-Object {
    $acl.RemoveAccessRule($_)
}

# Grant specific admin groups
$agentAdmins = Get-ADGroup "AG-Admins-Agents"
$rule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
    $agentAdmins.SID,
    "GenericAll",
    "Allow",
    "Descendents",
    [guid]"INSERT-AGENT-CLASS-GUID"
)
$acl.AddAccessRule($rule)
Set-Acl $agentsContainer $acl
```

### Administrative Tiering

**Separate agent administration from regular IT administration.**

| Tier | Accounts | Can Manage |
|------|----------|------------|
| Tier 0 | Domain Admins | Schema, Trust Level 4 agents |
| Tier 1 | Agent Admins | Trust Level 0-3 agents, tools |
| Tier 2 | Agent Operators | Specific agent OUs only |

### Just-In-Time Access

**Use temporary elevation for sensitive operations.**

```powershell
# Request temporary admin access
Request-AgentAdminAccess -Identity "operator@corp.contoso.com" `
    -Scope "OU=Production-Agents,CN=Agents,CN=System,DC=corp,DC=contoso,DC=com" `
    -Duration "4h" `
    -Justification "Ticket INC001234"
```

---

## Network Security

### Segmentation

**Isolate agent runtimes from sensitive networks.**

```
+-------------------+     +-------------------+     +-------------------+
|   Agent Zone      |     |   Application     |     |   Management      |
|                   |     |   Zone            |     |   Zone            |
| Agent Runtimes    |<--->| App Servers       |<--->| Domain Controllers|
| Tool Gateway      |     | Databases         |     | SCCM              |
+-------------------+     +-------------------+     +-------------------+
        |                         |                         |
        v                         v                         v
    [Firewall]               [Firewall]               [Firewall]
    Allow: 88,389            Allow: 443,1433          Allow: 135,445
    Deny: All else           Deny: All else           Deny: Agent Zone
```

### Firewall Rules

**Restrict agent network access to required services only.**

| Source | Destination | Port | Protocol | Purpose |
|--------|-------------|------|----------|---------|
| Agent Zone | DCs | 88 | TCP/UDP | Kerberos |
| Agent Zone | DCs | 389/636 | TCP | LDAP/LDAPS |
| Agent Zone | DCs | 464 | TCP/UDP | Kerberos password |
| Agent Zone | Approved Services | Varies | TCP | Delegated access |
| Agent Zone | Internet | DENY | ALL | Block outbound |

### TLS Configuration

**Enforce strong TLS for all agent communications.**

```powershell
# Require TLS 1.2+ for LDAP
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LDAP" `
    -Name "LdapClientIntegrity" -Value 2

# Configure LDAPS
Set-ADAgent -Identity "assistant-01" -RuntimeEndpoint "ldaps://dc01.corp.contoso.com:636"
```

---

## Monitoring and Alerting

### Critical Events to Monitor

| Event ID | Severity | Alert Threshold | Response |
|----------|----------|-----------------|----------|
| 2001 | Warning | >5/hour/agent | Investigate failed logins |
| 2020 | Critical | Any | Immediate investigation |
| 3001 | Warning | >10/hour | Review tool access policies |
| 5020 | Critical | Any | Block agent, investigate |
| 6002 | Critical | Any | Disable agent immediately |
| 6020 | Critical | Any | Incident response |
| 7000 | Info | Trust 3+ | Manager approval required |

### SIEM Integration

**Forward all agent events to your SIEM.**

```xml
<!-- Splunk inputs.conf -->
[WinEventLog://Microsoft-AgentDirectory/Operational]
disabled = 0
index = security
sourcetype = WinEventLog:AgentDirectory
blacklist = EventCode="4020" Message="routine"

[WinEventLog://Microsoft-AgentDirectory/Admin]
disabled = 0
index = security
sourcetype = WinEventLog:AgentDirectory
```

### Alert Rules

**Example Splunk correlation rules:**

```spl
# Multiple failed authentications
index=security sourcetype="WinEventLog:AgentDirectory" EventCode=2001
| stats count by AgentName, src_ip
| where count > 5

# Trust level elevation without approval
index=security sourcetype="WinEventLog:AgentDirectory" EventCode=7000
| where NewTrustLevel >= 3
| lookup approved_elevations AgentName OUTPUT approved
| where isnull(approved)

# Tool constraint violations
index=security sourcetype="WinEventLog:AgentDirectory" EventCode=4010
| stats count by AgentName, ToolId, ViolatedConstraint
| where count > 1
```

### Dashboard Metrics

Monitor these key indicators:

- Active agents by trust level
- Tool usage by category
- Failed authentication rate
- Delegation usage patterns
- Policy violation trends
- Agent creation/deletion rate

---

## Attack Surface Reduction

### Disable Unused Features

```powershell
# Disable agents that are not in active use
Get-ADAgent -Enabled $true | Where-Object {
    $_.Modified -lt (Get-Date).AddDays(-30)
} | Set-ADAgent -Enabled $false

# Remove unused tool authorizations
Get-ADAgent | ForEach-Object {
    $usage = Get-ADAgentToolUsage -Agent $_.Name -StartTime (Get-Date).AddDays(-90)
    $authorized = $_.AuthorizedTools

    $unused = $authorized | Where-Object {
        $toolId = (Get-ADAgentTool -Identity $_).Identifier
        $toolId -notin $usage.ToolId
    }

    if ($unused) {
        Write-Warning "Agent $($_.Name) has unused tool authorizations: $unused"
    }
}
```

### Limit Tool Capabilities

**Apply tool constraints aggressively.**

```powershell
# PowerShell: Constrained language mode
Set-ADAgentTool -Identity "microsoft.powershell" -AddConstraints @(
    "LanguageMode=ConstrainedLanguage",
    "ExecutionPolicy=AllSigned",
    "TranscriptLogging=Required",
    "ScriptBlockLogging=Required"
)

# SQL: Limit query scope
Set-ADAgentTool -Identity "database.sql" -AddConstraints @(
    "AllowedDatabases=AppDB,ReportDB",
    "DenyDDL=true",
    "QueryTimeout=30",
    "RowLimit=10000"
)

# File system: Restrict paths
Set-ADAgentTool -Identity "filesystem.write" -AddConstraints @(
    "AllowedPaths=C:\AgentData\*,\\fileserver\agentshare\*",
    "DenyPaths=C:\Windows\*,C:\Program Files\*",
    "DenyExtensions=.exe,.dll,.ps1,.bat"
)
```

### Periodic Access Review

**Review agent permissions quarterly.**

```powershell
# Generate access review report
$report = Get-ADAgent | ForEach-Object {
    [PSCustomObject]@{
        Agent = $_.Name
        Type = $_.Type
        TrustLevel = $_.TrustLevel
        Owner = $_.Owner
        LastModified = $_.Modified
        ToolCount = ($_.AuthorizedTools).Count
        DelegationScope = ($_.DelegationScope -join "; ")
        Enabled = $_.Enabled
    }
}

$report | Export-Csv "AgentAccessReview-$(Get-Date -Format 'yyyy-MM').csv"
```

---

## Sandbox Isolation

### Minimum Profile by Trust Level

**Every agent must run inside a sandbox. The sandbox security profile must match or exceed the restrictions appropriate for the agent's trust level.**

| Trust Level | Minimum Security Profile | Allowed Capabilities |
|-------------|--------------------------|----------------------|
| 0 (Untrusted) | `bwrap` (bubblewrap) | No network, read-only filesystem, no IPC |
| 1 (Basic) | `bwrap` | Loopback network only, limited write paths |
| 2 (Standard) | `bwrap` or `docker` | Filtered network, scoped filesystem write |
| 3 (Elevated) | `docker` | Controlled network egress, broader filesystem |
| 4 (System) | `docker` with host access | Per-policy; requires explicit approval |

```powershell
# Enforce minimum profile at creation
New-ADAgentSandbox -Name "sbx-untrusted-01" -SecurityProfile "bwrap" `
    -NetworkPolicy "none" -FilesystemPolicy "readonly"

# Verify sandbox meets trust level requirements
Test-ADAgentSandbox -Identity "sbx-untrusted-01" -RequiredTrustLevel 0
```

### Network and Resource Policy

**Sandbox network and resource policies are enforced independently of tool-level constraints.**

- **Network policy:** Defines allowed egress (none, loopback, allowlist, filtered). Applied at the sandbox level, not overridable by tool constraints.
- **Resource limits:** CPU, memory, and disk quotas prevent a compromised agent from consuming host resources.
- **Mount policy:** SYSVOL, keytabs, and tool binaries are mounted read-only. Writable paths are scoped to agent-specific directories.

### Escape Monitoring

**Monitor for sandbox escape attempts and treat them as critical incidents.**

| Indicator | Detection Method | Response |
|-----------|-----------------|----------|
| Unexpected host PID namespace access | seccomp audit log | Disable sandbox, Event ID 6002 |
| Mount outside allowed paths | AppArmor/SELinux denial | Alert, Event ID 8020 |
| Network connection to disallowed host | iptables log / nftables | Block, Event ID 6000 |
| Privilege escalation attempt | Kernel audit (auditd) | Disable agent, Event ID 6020 |

---

## Instruction GPO Content Integrity

### SYSVOL Protection

**Instruction GPO content (markdown files) is stored in SYSVOL and replicated across DCs. Unauthorized modification of SYSVOL content can inject arbitrary instructions into agents.**

- **NTFS/POSIX ACLs:** Only Agent Admins (Tier 1) and Domain Admins (Tier 0) should have write access to the SYSVOL instruction GPO directories.
- **Content hashing:** Each instruction GPO stores a SHA-256 hash in its AD metadata (`msDS-AgentInstructionHash` / `x-agentInstructionHash`). The runtime must verify the hash before applying instructions.
- **Integrity failure response:** If the hash does not match, log Event ID 10010 (InstructionGPOIntegrityFailure) and refuse to apply the GPO. Do not fall back to stale content.

```powershell
# Verify instruction GPO integrity manually
Test-ADAgentInstructionGPO -Identity "base-agent-instructions" -VerifyHash

# Re-sign after authorized update
Set-ADAgentInstructionGPO -Identity "base-agent-instructions" `
    -ContentPath "\\dc01\SYSVOL\corp.contoso.com\AgentInstructions\base-agent.md" `
    -UpdateHash
```

### Version Tracking

**Every content update must increment the GPO version. The runtime applies only the version recorded in the AD metadata object.**

- Store `msDS-AgentInstructionVersion` / `x-agentInstructionVersion` as a monotonically increasing integer.
- Reject version decrements (potential rollback attack).
- Audit all version changes via Event ID 10002.

### Merge Strategy Risks

**When multiple instruction GPOs are linked to an agent, they are merged in link-order precedence. Be aware of the following risks:**

- **Conflicting instructions:** Later GPOs override earlier ones for the same directive. Document link order explicitly.
- **Injection via low-priority GPO:** An attacker with write access to a low-priority GPO can still inject content that does not conflict with higher-priority GPOs. Audit all linked GPOs, not just the highest-priority one.
- **Unbounded instruction size:** Large instruction payloads can degrade agent performance. Enforce a maximum content size per GPO (recommended: 64 KB).

---

## Incident Response

### Containment Procedures

**Immediate response to suspected compromise:**

```powershell
# 1. Disable the agent immediately
Disable-ADAccount -Identity "compromised-agent"

# 2. Revoke all delegations
Revoke-ADAgentDelegation -Identity "compromised-agent" -All

# 3. Revoke all tool access
Revoke-ADAgentToolAccess -Identity "compromised-agent" -All

# 4. Reset credentials
Set-ADAccountPassword -Identity "compromised-agent" -Reset -NewPassword (
    ConvertTo-SecureString -AsPlainText (
        [System.Web.Security.Membership]::GeneratePassword(32, 8)
    ) -Force
)

# 5. Log the incident
Write-ADAgentEvent -EventId 6020 -AgentName "compromised-agent" `
    -Level Critical -Message "Agent disabled due to suspected compromise" `
    -AdditionalData @{IncidentId = "INC001234"; DisabledBy = $env:USERNAME}
```

### Evidence Collection

```powershell
# Export all events for the agent
$startTime = (Get-Date).AddDays(-7)
Export-ADAgentEventLog -Path "C:\Evidence\$agentName-events.csv" `
    -Agent "compromised-agent" `
    -StartTime $startTime

# Export agent configuration
Get-ADAgent -Identity "compromised-agent" | ConvertTo-Json -Depth 10 |
    Out-File "C:\Evidence\$agentName-config.json"

# Capture tool usage
Get-ADAgentToolUsage -Agent "compromised-agent" -StartTime $startTime |
    Export-Csv "C:\Evidence\$agentName-tool-usage.csv"
```

### Recovery Steps

1. Investigate root cause
2. Review all agent activities during compromise window
3. Identify any lateral movement or data access
4. Patch vulnerability or configuration issue
5. Create new agent with fresh credentials (do not re-enable old agent)
6. Implement additional monitoring
7. Document lessons learned

---

## Compliance Considerations

### SOX Compliance

| Requirement | Implementation |
|-------------|----------------|
| Segregation of duties | Separate agent admin roles |
| Access logging | All events to immutable log |
| Change management | Agent changes require approval |
| Periodic review | Quarterly access reviews |

### GDPR Compliance

| Requirement | Implementation |
|-------------|----------------|
| Data access logging | AuditLevel=2 for agents accessing personal data |
| Purpose limitation | Restrict tools to required functions |
| Accountability | Owner attribute for all agents |
| Data minimization | Limit delegation scope to necessary systems |

### HIPAA Compliance

| Requirement | Implementation |
|-------------|----------------|
| Access controls | TrustLevel 3+ for PHI systems |
| Audit trails | Comprehensive event logging |
| Emergency access | Documented break-glass procedures |
| Workforce training | Owner training on agent responsibilities |

### PCI-DSS Compliance

| Requirement | Implementation |
|-------------|----------------|
| Unique IDs | Each agent has unique sAMAccountName |
| Password management | Managed passwords with rotation |
| Access restriction | Segment agents from cardholder data |
| Monitoring | Real-time alerting on policy violations |

---

## Security Checklist

Use this checklist for security reviews:

### Agent Configuration
- [ ] Trust level is minimum necessary
- [ ] Owner is assigned and valid
- [ ] Description documents purpose
- [ ] Disabled when not in active use

### Authentication
- [ ] SPNs configured correctly
- [ ] Keytab stored securely
- [ ] Certificate (if used) has appropriate lifetime
- [ ] No password in scripts or code

### Authorization
- [ ] Only required tools authorized
- [ ] High-risk tools explicitly denied
- [ ] Delegation scope is minimal
- [ ] No unconstrained delegation

### Monitoring
- [ ] Events forwarded to SIEM
- [ ] Alerts configured for critical events
- [ ] Audit level appropriate for sensitivity
- [ ] Dashboard metrics reviewed regularly

### Operations
- [ ] Access reviews completed quarterly
- [ ] Unused agents disabled
- [ ] Credentials rotated per policy
- [ ] Incident response procedures documented
