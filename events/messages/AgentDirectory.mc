; // Agent Directory Message Compiler Source
; //
; // This file defines message strings for the Agent Directory event provider.
; // Compile with: mc.exe -um AgentDirectory.mc
; //

MessageIdTypedef=DWORD

SeverityNames=(
    Success=0x0:STATUS_SEVERITY_SUCCESS
    Informational=0x1:STATUS_SEVERITY_INFORMATIONAL
    Warning=0x2:STATUS_SEVERITY_WARNING
    Error=0x3:STATUS_SEVERITY_ERROR
)

FacilityNames=(
    System=0x0:FACILITY_SYSTEM
    Agent=0x1:FACILITY_AGENT
)

LanguageNames=(
    English=0x409:MSG00409
)

; // Category definitions

MessageId=1
SymbolicName=CAT_AGENT_LIFECYCLE
Language=English
Agent Lifecycle
.

MessageId=2
SymbolicName=CAT_AGENT_AUTHENTICATION
Language=English
Agent Authentication
.

MessageId=3
SymbolicName=CAT_TOOL_ACCESS
Language=English
Tool Access
.

MessageId=4
SymbolicName=CAT_TOOL_EXECUTION
Language=English
Tool Execution
.

MessageId=5
SymbolicName=CAT_DELEGATION
Language=English
Delegation
.

MessageId=6
SymbolicName=CAT_POLICY_VIOLATION
Language=English
Policy Violation
.

MessageId=7
SymbolicName=CAT_TRUST_CHANGE
Language=English
Trust Change
.

MessageId=8
SymbolicName=CAT_RESOURCE_ACCESS
Language=English
Resource Access
.

MessageId=9
SymbolicName=CAT_SANDBOX_LIFECYCLE
Language=English
Sandbox Lifecycle
.

MessageId=10
SymbolicName=CAT_INSTRUCTION_GPO_APPLICATION
Language=English
Instruction GPO Application
.

; // Agent Lifecycle Events (1000-1099)

MessageId=1000
Severity=Informational
Facility=Agent
SymbolicName=MSG_AGENT_CREATED
Language=English
Agent '%1' was created.
Type: %2
Trust Level: %3
Model: %4
Owner: %5
Created by: %6
Source IP: %7
.

MessageId=1001
Severity=Informational
Facility=Agent
SymbolicName=MSG_AGENT_MODIFIED
Language=English
Agent '%1' was modified.
Modified by: %2
Modified attributes: %3
Source IP: %4
.

MessageId=1002
Severity=Informational
Facility=Agent
SymbolicName=MSG_AGENT_DELETED
Language=English
Agent '%1' was deleted.
Deleted by: %2
Source IP: %3
.

MessageId=1003
Severity=Informational
Facility=Agent
SymbolicName=MSG_AGENT_ENABLED
Language=English
Agent '%1' was enabled.
Enabled by: %2
.

MessageId=1004
Severity=Informational
Facility=Agent
SymbolicName=MSG_AGENT_DISABLED
Language=English
Agent '%1' was disabled.
Disabled by: %2
.

MessageId=1010
Severity=Warning
Facility=Agent
SymbolicName=MSG_AGENT_CREATION_FAILED
Language=English
Failed to create agent '%1'.
Attempted by: %2
Error: %3
Source IP: %4
.

MessageId=1011
Severity=Error
Facility=Agent
SymbolicName=MSG_AGENT_CORRUPTED
Language=English
Agent object corruption detected for '%1'.
Please investigate and repair the agent object.
.

; // Authentication Events (2000-2099)

MessageId=2000
Severity=Informational
Facility=Agent
SymbolicName=MSG_AGENT_LOGON_SUCCESS
Language=English
Agent '%1' successfully authenticated.
Authentication type: %2
Source IP: %3
Source host: %4
Target service: %5
.

MessageId=2001
Severity=Warning
Facility=Agent
SymbolicName=MSG_AGENT_LOGON_FAILURE
Language=English
Agent '%1' authentication failed.
Authentication type: %2
Failure reason: %3
Error code: %4
Source IP: %5
.

MessageId=2002
Severity=Informational
Facility=Agent
SymbolicName=MSG_AGENT_LOGOFF
Language=English
Agent '%1' session ended.
.

MessageId=2003
Severity=Informational
Facility=Agent
SymbolicName=MSG_AGENT_KERBEROS_TICKET
Language=English
Kerberos ticket issued for agent '%1'.
Ticket type: %2
Service: %3
Encryption: %4
.

MessageId=2004
Severity=Informational
Facility=Agent
SymbolicName=MSG_AGENT_CERT_AUTH
Language=English
Agent '%1' authenticated using certificate.
Thumbprint: %2
Subject: %3
Issuer: %4
.

MessageId=2010
Severity=Warning
Facility=Agent
SymbolicName=MSG_AGENT_CREDENTIAL_EXPIRED
Language=English
Agent '%1' credentials have expired.
Please rotate credentials or enable managed password.
.

MessageId=2011
Severity=Warning
Facility=Agent
SymbolicName=MSG_AGENT_ACCOUNT_LOCKED
Language=English
Agent '%1' account has been locked due to failed authentication attempts.
.

MessageId=2020
Severity=Error
Facility=Agent
SymbolicName=MSG_AGENT_CREDENTIAL_COMPROMISE
Language=English
SECURITY ALERT: Potential credential compromise detected for agent '%1'.
Detection type: %2
Evidence: %3
Recommended action: %4
.

; // Tool Access Events (3000-3099)

MessageId=3000
Severity=Informational
Facility=Agent
SymbolicName=MSG_TOOL_ACCESS_GRANTED
Language=English
Agent '%1' was granted access to tool '%2'.
Tool display name: %3
Grant type: %4
Granted by: %5
.

MessageId=3001
Severity=Warning
Facility=Agent
SymbolicName=MSG_TOOL_ACCESS_DENIED
Language=English
Agent '%1' was denied access to tool '%2'.
Denial reason: %3
Agent trust level: %4
Required trust level: %5
.

MessageId=3002
Severity=Informational
Facility=Agent
SymbolicName=MSG_TOOL_ACCESS_REVOKED
Language=English
Agent '%1' access to tool '%2' was revoked.
Revoked by: %3
.

MessageId=3003
Severity=Informational
Facility=Agent
SymbolicName=MSG_TOOL_ACCESS_CHECKED
Language=English
Tool authorization check performed for agent '%1'.
Tool: %2
Result: %3
.

MessageId=3010
Severity=Warning
Facility=Agent
SymbolicName=MSG_TOOL_TRUST_LEVEL_INSUFFICIENT
Language=English
Agent '%1' trust level insufficient for tool '%2'.
Agent trust level: %3
Required trust level: %4
.

MessageId=3011
Severity=Warning
Facility=Agent
SymbolicName=MSG_TOOL_EXPLICITLY_DENIED
Language=English
Tool '%1' is explicitly denied to agent '%2'.
The tool is in the agent's denied tools list.
.

; // Tool Execution Events (4000-4099)

MessageId=4000
Severity=Informational
Facility=Agent
SymbolicName=MSG_TOOL_EXECUTION_STARTED
Language=English
Agent '%1' started using tool '%2'.
Tool category: %3
On behalf of: %4
Target resource: %5
Source IP: %6
.

MessageId=4001
Severity=Informational
Facility=Agent
SymbolicName=MSG_TOOL_EXECUTION_COMPLETED
Language=English
Agent '%1' completed using tool '%2'.
Duration: %3 ms
Result code: %4
.

MessageId=4002
Severity=Warning
Facility=Agent
SymbolicName=MSG_TOOL_EXECUTION_FAILED
Language=English
Agent '%1' failed using tool '%2'.
Error code: %3
Error message: %4
.

MessageId=4003
Severity=Warning
Facility=Agent
SymbolicName=MSG_TOOL_EXECUTION_ABORTED
Language=English
Agent '%1' tool execution was aborted.
Tool: %2
Reason: %3
.

MessageId=4010
Severity=Warning
Facility=Agent
SymbolicName=MSG_TOOL_CONSTRAINT_VIOLATION
Language=English
Agent '%1' violated tool constraints.
Tool: %2
Violated constraint: %3
Attempted action: %4
.

MessageId=4011
Severity=Warning
Facility=Agent
SymbolicName=MSG_TOOL_TIMEOUT_EXCEEDED
Language=English
Agent '%1' tool execution exceeded timeout.
Tool: %2
Allowed timeout: %3 ms
.

MessageId=4020
Severity=Informational
Facility=Agent
SymbolicName=MSG_TOOL_COMMAND_EXECUTED
Language=English
Agent '%1' executed command.
Tool: %2
Command: %3
Working directory: %4
.

; // Delegation Events (5000-5099)

MessageId=5000
Severity=Informational
Facility=Agent
SymbolicName=MSG_DELEGATION_GRANTED
Language=English
Agent '%1' was granted delegation rights.
Delegation type: %2
Target services: %3
Granted by: %4
.

MessageId=5001
Severity=Informational
Facility=Agent
SymbolicName=MSG_DELEGATION_REVOKED
Language=English
Agent '%1' delegation rights were revoked.
Revoked by: %2
.

MessageId=5002
Severity=Informational
Facility=Agent
SymbolicName=MSG_DELEGATION_USED
Language=English
Agent '%1' acted on behalf of user '%2'.
Target service: %3
Target resource: %4
.

MessageId=5010
Severity=Warning
Facility=Agent
SymbolicName=MSG_DELEGATION_DENIED
Language=English
Agent '%1' delegation attempt was blocked.
Attempted to act as: %2
Target service: %3
Reason: %4
.

MessageId=5011
Severity=Warning
Facility=Agent
SymbolicName=MSG_DELEGATION_SCOPE_EXCEEDED
Language=English
Agent '%1' attempted to delegate beyond allowed scope.
Allowed scope: %2
Attempted service: %3
.

MessageId=5020
Severity=Error
Facility=Agent
SymbolicName=MSG_UNAUTHORIZED_DELEGATION
Language=English
SECURITY ALERT: Unauthorized delegation attempt detected.
Agent: %1
Attempted to impersonate: %2
Target service: %3
This incident has been logged for investigation.
.

; // Policy Violation Events (6000-6099)

MessageId=6000
Severity=Warning
Facility=Agent
SymbolicName=MSG_POLICY_VIOLATION_MINOR
Language=English
Agent '%1' committed a minor policy violation.
Violation type: %2
Policy: %3
Details: %4
.

MessageId=6001
Severity=Error
Facility=Agent
SymbolicName=MSG_POLICY_VIOLATION_MAJOR
Language=English
Agent '%1' committed a major policy violation.
Violation type: %2
Policy: %3
Details: %4
Recommended action: %5
.

MessageId=6002
Severity=Error
Facility=Agent
SymbolicName=MSG_POLICY_VIOLATION_CRITICAL
Language=English
SECURITY ALERT: Agent '%1' committed a critical security violation.
Violation type: %2
Policy: %3
Details: %4
Automatic action taken: %5
.

MessageId=6010
Severity=Warning
Facility=Agent
SymbolicName=MSG_RATE_LIMIT_EXCEEDED
Language=English
Agent '%1' exceeded rate limits.
Operation: %2
Limit: %3
Actual: %4
.

MessageId=6011
Severity=Warning
Facility=Agent
SymbolicName=MSG_GEOFENCE_VIOLATION
Language=English
Agent '%1' accessed from unauthorized location.
Source IP: %2
Allowed locations: %3
.

MessageId=6020
Severity=Error
Facility=Agent
SymbolicName=MSG_MALICIOUS_BEHAVIOR_DETECTED
Language=English
SECURITY ALERT: Potential malicious behavior detected from agent '%1'.
Behavior type: %2
Details: %3
Automatic action: %4
Investigate immediately.
.

; // Trust Change Events (7000-7099)

MessageId=7000
Severity=Informational
Facility=Agent
SymbolicName=MSG_TRUST_LEVEL_INCREASED
Language=English
Agent '%1' trust level was elevated.
Previous level: %2
New level: %3
Changed by: %4
Justification: %5
.

MessageId=7001
Severity=Informational
Facility=Agent
SymbolicName=MSG_TRUST_LEVEL_DECREASED
Language=English
Agent '%1' trust level was reduced.
Previous level: %2
New level: %3
Changed by: %4
Reason: %5
.

MessageId=7002
Severity=Warning
Facility=Agent
SymbolicName=MSG_TRUST_LEVEL_RESET_REQUIRED
Language=English
Agent '%1' trust level requires re-evaluation.
Current level: %2
Reason: %3
.

MessageId=7010
Severity=Warning
Facility=Agent
SymbolicName=MSG_TRUST_ELEVATION_DENIED
Language=English
Request to elevate agent '%1' trust was denied.
Requested level: %2
Current level: %3
Denied by: %4
Reason: %5
.

; // Resource Access Events (8000-8099)

MessageId=8000
Severity=Informational
Facility=Agent
SymbolicName=MSG_FILE_ACCESS
Language=English
Agent '%1' accessed file.
File path: %2
Access type: %3
On behalf of: %4
.

MessageId=8001
Severity=Informational
Facility=Agent
SymbolicName=MSG_NETWORK_CONNECTION
Language=English
Agent '%1' made network connection.
Destination: %2:%3
Protocol: %4
.

MessageId=8002
Severity=Informational
Facility=Agent
SymbolicName=MSG_SERVICE_CALL
Language=English
Agent '%1' called service.
Service: %2
Method: %3
.

MessageId=8003
Severity=Informational
Facility=Agent
SymbolicName=MSG_DATABASE_QUERY
Language=English
Agent '%1' executed database query.
Database: %2
Query type: %3
Rows affected: %4
.

MessageId=8010
Severity=Warning
Facility=Agent
SymbolicName=MSG_SENSITIVE_RESOURCE_ACCESS
Language=English
Agent '%1' accessed sensitive resource.
Resource: %2
Classification: %3
Access type: %4
.

MessageId=8020
Severity=Warning
Facility=Agent
SymbolicName=MSG_RESOURCE_ACCESS_DENIED
Language=English
Agent '%1' was denied access to resource.
Resource: %2
Access type: %3
Reason: %4
.

; // Sandbox Lifecycle Events (9000-9010)

MessageId=9000
Severity=Informational
Facility=Agent
SymbolicName=MSG_SANDBOX_CREATED
Language=English
Sandbox '%1' was created.
Security Profile: %2
Endpoint: %3
.

MessageId=9001
Severity=Informational
Facility=Agent
SymbolicName=MSG_SANDBOX_MODIFIED
Language=English
Sandbox '%1' was modified by %2 from %3.
.

MessageId=9002
Severity=Informational
Facility=Agent
SymbolicName=MSG_SANDBOX_DELETED
Language=English
Sandbox '%1' was deleted by %2 from %3.
.

MessageId=9003
Severity=Informational
Facility=Agent
SymbolicName=MSG_SANDBOX_ACTIVATED
Language=English
Sandbox '%1' was activated for agent '%2'.
.

MessageId=9004
Severity=Informational
Facility=Agent
SymbolicName=MSG_SANDBOX_DEACTIVATED
Language=English
Sandbox '%1' was deactivated.
.

MessageId=9010
Severity=Warning
Facility=Agent
SymbolicName=MSG_SANDBOX_CREATION_FAILED
Language=English
Failed to create sandbox '%1'.
Error: %2
.

; // Instruction GPO Application Events (10000-10010)

MessageId=10000
Severity=Informational
Facility=Agent
SymbolicName=MSG_INSTRUCTION_GPO_APPLIED
Language=English
Instruction GPO '%1' applied to agent '%2' with priority %3 using %4 merge strategy.
.

MessageId=10001
Severity=Warning
Facility=Agent
SymbolicName=MSG_INSTRUCTION_GPO_FAILED
Language=English
Instruction GPO '%1' failed to apply to agent '%2'.
Reason: %3
.

MessageId=10002
Severity=Informational
Facility=Agent
SymbolicName=MSG_INSTRUCTION_GPO_UPDATED
Language=English
Instruction GPO '%1' was updated.
Path: %2
.

MessageId=10003
Severity=Informational
Facility=Agent
SymbolicName=MSG_INSTRUCTION_GPO_LINKED
Language=English
Instruction GPO '%1' was linked to agent '%2'.
.

MessageId=10004
Severity=Informational
Facility=Agent
SymbolicName=MSG_INSTRUCTION_GPO_UNLINKED
Language=English
Instruction GPO '%1' was unlinked from agent '%2'.
.

MessageId=10010
Severity=Error
Facility=Agent
SymbolicName=MSG_INSTRUCTION_GPO_INTEGRITY_FAILURE
Language=English
INTEGRITY FAILURE: Instruction GPO '%1' content at '%2' failed integrity check.
Reason: %3
.
