# Event Reference Guide

## Overview

Agent Directory uses a custom Windows Event Log provider for comprehensive auditing of all agent activities. Events integrate with Windows Event Forwarding (WEF), Azure Monitor, and SIEM solutions.

## Event Log Configuration

| Property | Value |
|----------|-------|
| Provider Name | Microsoft-AgentDirectory |
| Provider GUID | {A8B9C0D1-E2F3-4A5B-6C7D-8E9F0A1B2C3D} |
| Operational Log | Microsoft-AgentDirectory/Operational |
| Admin Log | Microsoft-AgentDirectory/Admin |
| Default Max Size | 100 MB |
| Retention | Overwrite as needed |

## Event Categories (Tasks)

| Task ID | Task Name | Description |
|---------|-----------|-------------|
| 1 | AgentLifecycle | Agent creation, modification, deletion |
| 2 | AgentAuthentication | Logon, logoff, credential events |
| 3 | ToolAccess | Tool authorization checks |
| 4 | ToolExecution | Tool usage and results |
| 5 | Delegation | Delegation grants, revocations, usage |
| 6 | PolicyViolation | Security policy violations |
| 7 | TrustChange | Trust level modifications |
| 8 | ResourceAccess | File, network, service access |
| 9 | SandboxLifecycle | Sandbox creation, modification, deletion |
| 10 | InstructionGPOApplication | Instruction GPO application and integrity |

## Event Levels

| Level | Name | Description |
|-------|------|-------------|
| 1 | Critical | Immediate attention required |
| 2 | Error | Operation failed |
| 3 | Warning | Potential issue detected |
| 4 | Information | Normal operation |
| 5 | Verbose | Detailed diagnostic info |

---

## Event Definitions

### Task 1: Agent Lifecycle Events

#### Event ID 1000 - AgentCreated

**Level:** Information

**Description:** A new agent account was created in Active Directory.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Security identifier of new agent |
| AgentName | String | sAMAccountName of agent |
| AgentDN | String | Distinguished name |
| AgentType | String | autonomous/assistant/tool/orchestrator |
| AgentTrustLevel | UInt32 | Initial trust level (0-4) |
| AgentModel | String | AI model identifier |
| OwnerDN | String | DN of responsible identity |
| CreatedBy | String | User who created the agent |
| SourceIP | String | IP where creation originated |

**Example:**
```xml
<EventData>
  <Data Name="AgentSid">S-1-5-21-1234567890-1234567890-1234567890-1001</Data>
  <Data Name="AgentName">claude-assistant-01$</Data>
  <Data Name="AgentDN">CN=claude-assistant-01,CN=Agents,CN=System,DC=corp,DC=contoso,DC=com</Data>
  <Data Name="AgentType">assistant</Data>
  <Data Name="AgentTrustLevel">2</Data>
  <Data Name="AgentModel">claude-opus-4-5</Data>
  <Data Name="OwnerDN">CN=John Smith,OU=Users,DC=corp,DC=contoso,DC=com</Data>
  <Data Name="CreatedBy">CORP\admin</Data>
  <Data Name="SourceIP">10.0.1.50</Data>
</EventData>
```

---

#### Event ID 1001 - AgentModified

**Level:** Information

**Description:** An agent account's properties were modified.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier |
| AgentName | String | sAMAccountName |
| AgentDN | String | Distinguished name |
| ModifiedBy | String | User who made changes |
| ModifiedAttributes | String | Comma-separated list of changed attributes |
| OldValues | String | Previous values (JSON) |
| NewValues | String | New values (JSON) |
| SourceIP | String | Source IP address |

---

#### Event ID 1002 - AgentDeleted

**Level:** Information

**Description:** An agent account was deleted from Active Directory.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier |
| AgentName | String | sAMAccountName |
| AgentDN | String | Distinguished name |
| DeletedBy | String | User who deleted agent |
| SourceIP | String | Source IP address |

---

#### Event ID 1003 - AgentEnabled

**Level:** Information

**Description:** A disabled agent account was enabled.

---

#### Event ID 1004 - AgentDisabled

**Level:** Information

**Description:** An agent account was disabled.

---

#### Event ID 1010 - AgentCreationFailed

**Level:** Warning

**Description:** Failed to create a new agent account.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AttemptedName | String | Requested agent name |
| AttemptedBy | String | User who attempted creation |
| ErrorCode | UInt32 | HRESULT error code |
| ErrorMessage | String | Error description |
| SourceIP | String | Source IP address |

---

#### Event ID 1011 - AgentCorrupted

**Level:** Error

**Description:** Agent object corruption was detected.

---

### Task 2: Authentication Events

#### Event ID 2000 - AgentLogonSuccess

**Level:** Information

**Description:** An agent successfully authenticated.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier |
| AgentName | String | sAMAccountName |
| AgentDN | String | Distinguished name |
| AuthType | String | Kerberos/NTLM/Certificate |
| SourceIP | String | Client IP address |
| SourceHost | String | Client hostname |
| TargetService | String | Service authenticated to |
| LogonType | UInt32 | Windows logon type |

---

#### Event ID 2001 - AgentLogonFailure

**Level:** Warning

**Description:** An agent authentication attempt failed.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentName | String | Attempted agent name |
| AuthType | String | Authentication type attempted |
| FailureReason | String | Reason for failure |
| ErrorCode | UInt32 | NTSTATUS error code |
| SourceIP | String | Client IP address |
| SourceHost | String | Client hostname |

**Common Failure Reasons:**
- `InvalidCredentials` - Wrong password/key
- `AccountDisabled` - Agent account is disabled
- `AccountExpired` - Agent account has expired
- `AccountLocked` - Account locked due to failed attempts
- `CertificateInvalid` - Certificate validation failed
- `CertificateExpired` - Certificate has expired
- `TrustLevelInsufficient` - Agent trust level too low
- `DelegationNotAllowed` - Delegation not permitted

---

#### Event ID 2002 - AgentLogoff

**Level:** Information

**Description:** An agent session ended.

---

#### Event ID 2003 - AgentKerberosTicket

**Level:** Information

**Description:** A Kerberos ticket was issued for an agent.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier |
| AgentName | String | sAMAccountName |
| TicketType | String | TGT/TGS |
| ServiceName | String | Target service SPN |
| TicketOptions | UInt32 | Kerberos ticket options |
| EncryptionType | String | Encryption algorithm |
| ClientIP | String | Client IP address |

---

#### Event ID 2004 - AgentCertAuth

**Level:** Information

**Description:** Agent authenticated using a certificate.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier |
| AgentName | String | sAMAccountName |
| CertThumbprint | String | Certificate SHA-1 thumbprint |
| CertSubject | String | Certificate subject |
| CertIssuer | String | Certificate issuer |
| CertSerialNumber | String | Certificate serial |
| MappingType | String | How cert mapped to agent |

---

#### Event ID 2010 - AgentCredentialExpired

**Level:** Warning

**Description:** Agent credentials have expired.

---

#### Event ID 2011 - AgentAccountLocked

**Level:** Warning

**Description:** Agent account was locked out.

---

#### Event ID 2020 - AgentCredentialCompromise

**Level:** Critical

**Description:** Potential credential compromise detected for an agent.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier |
| AgentName | String | sAMAccountName |
| DetectionType | String | Type of compromise detected |
| Evidence | String | Details of suspicious activity |
| RecommendedAction | String | Suggested remediation |

---

### Task 3: Tool Access Events

#### Event ID 3000 - ToolAccessGranted

**Level:** Information

**Description:** An agent was granted access to a tool.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier |
| AgentName | String | sAMAccountName |
| ToolId | String | Tool identifier |
| ToolDisplayName | String | Tool display name |
| GrantType | String | Direct/Group/Implicit |
| GrantedBy | String | User who granted access |
| SourceIP | String | Source IP address |

---

#### Event ID 3001 - ToolAccessDenied

**Level:** Warning

**Description:** An agent was denied access to a tool.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier |
| AgentName | String | sAMAccountName |
| ToolId | String | Tool identifier |
| DenialReason | String | Why access was denied |
| AgentTrustLevel | UInt32 | Agent's current trust level |
| RequiredTrustLevel | UInt32 | Tool's required trust level |

**Denial Reasons:**
- `ExplicitDeny` - Tool in agent's deny list
- `NoGrant` - No authorization found
- `TrustLevelInsufficient` - Trust level too low
- `ConstraintViolation` - Tool constraints not met

---

#### Event ID 3002 - ToolAccessRevoked

**Level:** Information

**Description:** Tool access was removed from an agent.

---

#### Event ID 3003 - ToolAccessChecked

**Level:** Verbose

**Description:** A tool authorization check was performed.

---

#### Event ID 3010 - ToolTrustLevelInsufficient

**Level:** Warning

**Description:** Agent's trust level is too low for requested tool.

---

#### Event ID 3011 - ToolExplicitlyDenied

**Level:** Warning

**Description:** Tool is explicitly in agent's denied list.

---

### Task 4: Tool Execution Events

#### Event ID 4000 - ToolExecutionStarted

**Level:** Information

**Description:** An agent started using a tool.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier |
| AgentName | String | sAMAccountName |
| AgentDN | String | Distinguished name |
| AgentType | String | Agent type |
| AgentTrustLevel | UInt32 | Current trust level |
| ToolId | String | Tool identifier |
| ToolCategory | String | Tool category |
| OnBehalfOf | String | User being impersonated (if any) |
| SourceIP | String | Execution source IP |
| TargetResource | String | Target of operation |
| CommandLine | String | Command or action details |
| CorrelationId | GUID | Correlation ID for tracking |

---

#### Event ID 4001 - ToolExecutionCompleted

**Level:** Information

**Description:** An agent finished using a tool.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier |
| AgentName | String | sAMAccountName |
| ToolId | String | Tool identifier |
| ResultCode | UInt32 | Exit/result code |
| Duration | UInt64 | Execution time in milliseconds |
| CorrelationId | GUID | Correlation ID |

---

#### Event ID 4002 - ToolExecutionFailed

**Level:** Warning

**Description:** Tool execution failed.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier |
| AgentName | String | sAMAccountName |
| ToolId | String | Tool identifier |
| ErrorCode | UInt32 | Error code |
| ErrorMessage | String | Error description |
| CorrelationId | GUID | Correlation ID |

---

#### Event ID 4003 - ToolExecutionAborted

**Level:** Warning

**Description:** Tool execution was terminated before completion.

---

#### Event ID 4010 - ToolConstraintViolation

**Level:** Warning

**Description:** Agent violated a tool constraint during execution.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier |
| AgentName | String | sAMAccountName |
| ToolId | String | Tool identifier |
| ViolatedConstraint | String | Constraint that was violated |
| AttemptedAction | String | What agent tried to do |
| CorrelationId | GUID | Correlation ID |

---

#### Event ID 4011 - ToolTimeoutExceeded

**Level:** Warning

**Description:** Tool execution exceeded the allowed time limit.

---

#### Event ID 4020 - ToolCommandExecuted

**Level:** Information

**Description:** Specific command logged for audit (PowerShell, etc.).

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier |
| AgentName | String | sAMAccountName |
| ToolId | String | Tool identifier |
| CommandLine | String | Full command executed |
| WorkingDirectory | String | Execution directory |
| CorrelationId | GUID | Correlation ID |

---

### Task 5: Delegation Events

#### Event ID 5000 - DelegationGranted

**Level:** Information

**Description:** Agent was granted delegation rights.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier |
| AgentName | String | sAMAccountName |
| DelegationType | String | Constrained/RBCD/Unconstrained |
| TargetServices | String | SPNs agent can delegate to |
| GrantedBy | String | User who granted delegation |

---

#### Event ID 5001 - DelegationRevoked

**Level:** Information

**Description:** Delegation rights were removed from agent.

---

#### Event ID 5002 - DelegationUsed

**Level:** Information

**Description:** Agent acted on behalf of a user.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier |
| AgentName | String | sAMAccountName |
| OnBehalfOfSid | SID | Delegated user's SID |
| OnBehalfOfName | String | Delegated user's name |
| TargetService | String | Service accessed |
| TargetResource | String | Resource accessed |
| CorrelationId | GUID | Correlation ID |

---

#### Event ID 5010 - DelegationDenied

**Level:** Warning

**Description:** Agent delegation attempt was blocked.

---

#### Event ID 5011 - DelegationScopeExceeded

**Level:** Warning

**Description:** Agent attempted to delegate beyond allowed scope.

---

#### Event ID 5020 - UnauthorizedDelegation

**Level:** Critical

**Description:** Unauthorized delegation attempt detected.

---

### Task 6: Policy Violation Events

#### Event ID 6000 - PolicyViolationMinor

**Level:** Warning

**Description:** Agent committed a minor policy violation.

---

#### Event ID 6001 - PolicyViolationMajor

**Level:** Error

**Description:** Agent committed a major policy violation.

---

#### Event ID 6002 - PolicyViolationCritical

**Level:** Critical

**Description:** Agent committed a critical security violation.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier |
| AgentName | String | sAMAccountName |
| ViolationType | String | Type of violation |
| PolicyName | String | Policy that was violated |
| ViolationDetails | String | Details of violation |
| RecommendedAction | String | Suggested response |
| AutomaticAction | String | Action taken automatically |

---

#### Event ID 6010 - RateLimitExceeded

**Level:** Warning

**Description:** Agent exceeded configured rate limits.

---

#### Event ID 6011 - GeofenceViolation

**Level:** Warning

**Description:** Agent accessed from unauthorized location.

---

#### Event ID 6020 - MaliciousBehaviorDetected

**Level:** Critical

**Description:** Potential malicious agent activity detected.

---

### Task 7: Trust Change Events

#### Event ID 7000 - TrustLevelIncreased

**Level:** Information

**Description:** Agent's trust level was elevated.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier |
| AgentName | String | sAMAccountName |
| OldTrustLevel | UInt32 | Previous trust level |
| NewTrustLevel | UInt32 | New trust level |
| ChangedBy | String | User who changed trust |
| Justification | String | Reason for change |

---

#### Event ID 7001 - TrustLevelDecreased

**Level:** Information

**Description:** Agent's trust level was reduced.

---

#### Event ID 7002 - TrustLevelResetRequired

**Level:** Warning

**Description:** Agent trust level requires re-evaluation.

---

#### Event ID 7010 - TrustElevationDenied

**Level:** Warning

**Description:** Request to elevate agent trust was denied.

---

### Task 8: Resource Access Events

#### Event ID 8000 - FileAccess

**Level:** Information

**Description:** Agent accessed a file.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier |
| AgentName | String | sAMAccountName |
| FilePath | String | File accessed |
| AccessType | String | Read/Write/Delete/Execute |
| OnBehalfOf | String | Delegated user (if any) |
| CorrelationId | GUID | Correlation ID |

---

#### Event ID 8001 - NetworkConnection

**Level:** Information

**Description:** Agent made a network connection.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier |
| AgentName | String | sAMAccountName |
| DestinationIP | String | Target IP address |
| DestinationPort | UInt32 | Target port |
| DestinationHost | String | Target hostname |
| Protocol | String | Network protocol |
| CorrelationId | GUID | Correlation ID |

---

#### Event ID 8002 - ServiceCall

**Level:** Information

**Description:** Agent called a service or API.

---

#### Event ID 8003 - DatabaseQuery

**Level:** Information

**Description:** Agent executed a database query.

---

#### Event ID 8010 - SensitiveResourceAccess

**Level:** Warning

**Description:** Agent accessed a sensitive resource.

---

#### Event ID 8020 - ResourceAccessDenied

**Level:** Warning

**Description:** Agent was denied access to a resource.

---

### Task 9: Sandbox Lifecycle Events

#### Event ID 9000 - SandboxCreated

**Level:** Information

**Description:** A new sandbox (computer object) was created in Active Directory.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| SandboxSid | SID | Security identifier of new sandbox |
| SandboxName | String | sAMAccountName of sandbox |
| SandboxDN | String | Distinguished name |
| SecurityProfile | String | Sandbox security profile (e.g., bwrap, docker) |
| AssignedAgent | String | DN of agent assigned to this sandbox |
| CreatedBy | String | User who created the sandbox |
| SourceIP | String | IP where creation originated |

---

#### Event ID 9001 - SandboxModified

**Level:** Information

**Description:** A sandbox's properties were modified.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| SandboxSid | SID | Sandbox security identifier |
| SandboxName | String | sAMAccountName |
| SandboxDN | String | Distinguished name |
| ModifiedBy | String | User who made changes |
| ModifiedAttributes | String | Comma-separated list of changed attributes |
| OldValues | String | Previous values (JSON) |
| NewValues | String | New values (JSON) |
| SourceIP | String | Source IP address |

---

#### Event ID 9002 - SandboxDeleted

**Level:** Information

**Description:** A sandbox was deleted from Active Directory.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| SandboxSid | SID | Sandbox security identifier |
| SandboxName | String | sAMAccountName |
| SandboxDN | String | Distinguished name |
| DeletedBy | String | User who deleted sandbox |
| SourceIP | String | Source IP address |

---

#### Event ID 9003 - SandboxActivated

**Level:** Information

**Description:** A sandbox was activated and is ready for agent execution.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| SandboxSid | SID | Sandbox security identifier |
| SandboxName | String | sAMAccountName |
| SecurityProfile | String | Active security profile |
| AssignedAgent | String | DN of agent using this sandbox |
| ActivatedBy | String | User or system that activated the sandbox |

---

#### Event ID 9004 - SandboxDeactivated

**Level:** Information

**Description:** A sandbox was deactivated and is no longer available for execution.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| SandboxSid | SID | Sandbox security identifier |
| SandboxName | String | sAMAccountName |
| Reason | String | Reason for deactivation |
| DeactivatedBy | String | User or system that deactivated the sandbox |

---

#### Event ID 9010 - SandboxCreationFailed

**Level:** Warning

**Description:** Failed to create a new sandbox.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AttemptedName | String | Requested sandbox name |
| AttemptedBy | String | User who attempted creation |
| ErrorCode | UInt32 | HRESULT error code |
| ErrorMessage | String | Error description |
| SourceIP | String | Source IP address |

---

### Task 10: Instruction GPO Application Events

#### Event ID 10000 - InstructionGPOApplied

**Level:** Information

**Description:** An instruction GPO was successfully applied to an agent.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier |
| AgentName | String | sAMAccountName |
| GPOName | String | Instruction GPO display name |
| GPODN | String | Distinguished name of the GPO object |
| GPOVersion | UInt32 | Version number applied |
| ContentHash | String | SHA-256 hash of instruction content |
| CorrelationId | GUID | Correlation ID |

---

#### Event ID 10001 - InstructionGPOFailed

**Level:** Warning

**Description:** An instruction GPO failed to apply to an agent.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier |
| AgentName | String | sAMAccountName |
| GPOName | String | Instruction GPO display name |
| GPODN | String | Distinguished name of the GPO object |
| ErrorCode | UInt32 | Error code |
| ErrorMessage | String | Error description |
| CorrelationId | GUID | Correlation ID |

---

#### Event ID 10002 - InstructionGPOUpdated

**Level:** Information

**Description:** An instruction GPO's content was updated in SYSVOL.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| GPOName | String | Instruction GPO display name |
| GPODN | String | Distinguished name of the GPO object |
| OldVersion | UInt32 | Previous version number |
| NewVersion | UInt32 | New version number |
| OldContentHash | String | SHA-256 hash of previous content |
| NewContentHash | String | SHA-256 hash of new content |
| UpdatedBy | String | User who updated the GPO |

---

#### Event ID 10003 - InstructionGPOLinked

**Level:** Information

**Description:** An instruction GPO was linked to an agent or OU.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| GPOName | String | Instruction GPO display name |
| GPODN | String | Distinguished name of the GPO object |
| TargetDN | String | DN of agent or OU the GPO was linked to |
| LinkedBy | String | User who created the link |
| LinkOrder | UInt32 | Order of the link (for precedence) |

---

#### Event ID 10004 - InstructionGPOUnlinked

**Level:** Information

**Description:** An instruction GPO was unlinked from an agent or OU.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| GPOName | String | Instruction GPO display name |
| GPODN | String | Distinguished name of the GPO object |
| TargetDN | String | DN of agent or OU the GPO was unlinked from |
| UnlinkedBy | String | User who removed the link |

---

#### Event ID 10010 - InstructionGPOIntegrityFailure

**Level:** Error

**Description:** Instruction GPO content failed integrity verification. The content hash in SYSVOL does not match the expected hash stored in the AD object metadata.

**Event Data:**
| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent security identifier (if during application) |
| AgentName | String | sAMAccountName (if during application) |
| GPOName | String | Instruction GPO display name |
| GPODN | String | Distinguished name of the GPO object |
| ExpectedHash | String | SHA-256 hash stored in AD metadata |
| ActualHash | String | SHA-256 hash of SYSVOL content |
| SYSVOLPath | String | Path to the content file in SYSVOL |
| RecommendedAction | String | Suggested remediation |

---

## Common Event Data Fields

All events include these standard fields:

| Field | Type | Description |
|-------|------|-------------|
| AgentSid | SID | Agent's security identifier |
| AgentName | String | Agent's sAMAccountName |
| AgentDN | String | Agent's distinguished name |
| CorrelationId | GUID | For tracking related events |
| TimeCreated | DateTime | Event timestamp (UTC) |

## SIEM Integration

### Windows Event Forwarding (WEF)

Sample subscription to collect all agent events:

```xml
<QueryList>
  <Query Id="0" Path="Microsoft-AgentDirectory/Operational">
    <Select Path="Microsoft-AgentDirectory/Operational">*</Select>
  </Query>
  <Query Id="1" Path="Microsoft-AgentDirectory/Admin">
    <Select Path="Microsoft-AgentDirectory/Admin">*[System[(Level=1 or Level=2 or Level=3)]]</Select>
  </Query>
</QueryList>
```

### Splunk

Use the Splunk Universal Forwarder with inputs.conf:

```ini
[WinEventLog://Microsoft-AgentDirectory/Operational]
disabled = 0
index = security
sourcetype = WinEventLog:AgentDirectory

[WinEventLog://Microsoft-AgentDirectory/Admin]
disabled = 0
index = security
sourcetype = WinEventLog:AgentDirectory
```

### Azure Monitor

Use Azure Monitor Agent with DCR:

```json
{
  "streams": ["Microsoft-Event"],
  "xPathQueries": [
    "Microsoft-AgentDirectory/Operational!*",
    "Microsoft-AgentDirectory/Admin!*[System[(Level=1 or Level=2 or Level=3)]]"
  ],
  "destination": "LogAnalytics"
}
```

### Elastic

Use Winlogbeat configuration:

```yaml
winlogbeat.event_logs:
  - name: Microsoft-AgentDirectory/Operational
    event_id: 1000-8020
  - name: Microsoft-AgentDirectory/Admin
    level: critical, error, warning
```

## PowerShell Queries

Query recent authentication failures:

```powershell
Get-ADAgentEvent -EventId 2001 -StartTime (Get-Date).AddHours(-24) |
    Select-Object TimeCreated, AgentName, FailureReason, SourceIP
```

Query tool executions for an agent:

```powershell
Get-ADAgentEvent -Agent "claude-01" -Task ToolExecution -StartTime (Get-Date).AddDays(-7)
```

Export events for analysis:

```powershell
Export-ADAgentEventLog -StartTime "2026-01-01" -EndTime "2026-01-31" -Path "C:\Exports\agent-events-jan.csv"
```
