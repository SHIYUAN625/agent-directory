# Deployment Guide

## Overview

This guide covers the deployment of the Agent Directory schema extension, event log provider, and PowerShell management module in Active Directory environments.

## Prerequisites

### Required Permissions

| Component | Required Membership |
|-----------|---------------------|
| Schema Extension | Schema Admins |
| Container Creation | Enterprise Admins |
| Tool Registration | Domain Admins |
| Event Log Provider | Local Administrator (on each DC) |
| PowerShell Module | None (user-level) |

### Environment Requirements

- Windows Server 2016 or later Domain Controllers
- Active Directory Forest Functional Level: Windows Server 2016+
- PowerShell 5.1 or later
- .NET Framework 4.7.2 or later

### Pre-Deployment Checklist

- [ ] IANA Private Enterprise Number (PEN) obtained for production OIDs
- [ ] Schema extension tested in isolated lab environment
- [ ] Change management approval obtained
- [ ] Rollback plan documented
- [ ] Backup of System State on all DCs completed
- [ ] AD replication health verified
- [ ] Schema Master DC identified and accessible

## Phase 1: Lab Testing

### Create Isolated Test Environment

1. **Deploy Test Forest**
   - Create an isolated test forest with at least 2 DCs
   - Do NOT create trusts with production environment

2. **Import Test Data**
   ```powershell
   # Create test OUs and users for delegation testing
   New-ADOrganizationalUnit -Name "Test-Agents" -Path "DC=test,DC=local"
   New-ADUser -Name "TestOwner" -Path "OU=Users,DC=test,DC=local"
   ```

3. **Install Schema Extension**
   ```powershell
   .\schema\install-schema.ps1 -Verbose
   ```

4. **Verify Schema Objects**
   ```powershell
   # Check attributes exist
   Get-ADObject -SearchBase "CN=Schema,CN=Configuration,DC=test,DC=local" `
       -Filter "name -like 'msDS-Agent*' -or name -like 'msDS-Sandbox*'" | Select-Object Name

   # Check classes exist
   Get-ADObject -SearchBase "CN=Schema,CN=Configuration,DC=test,DC=local" `
       -Filter "name -eq 'msDS-Agent' -or name -eq 'msDS-AgentTool'" | Select-Object Name
   ```

5. **Test Agent Creation**
   ```powershell
   Import-Module .\powershell\AgentDirectory

   # Create agent (user object)
   New-ADAgent -Name "test-agent-01" `
       -Type "assistant" `
       -TrustLevel 2 `
       -Owner "CN=TestOwner,OU=Users,DC=test,DC=local"

   # Create sandbox (computer object) and link
   $sandbox = New-ADAgentSandbox -Name "test-sandbox-01" -SecurityProfile "bwrap"
   Set-ADAgent -Identity "test-agent-01" -AddSandbox $sandbox.DistinguishedName

   Get-ADAgent -Identity "test-agent-01"
   ```

6. **Test Tool Access**
   ```powershell
   Grant-ADAgentToolAccess -Identity "test-agent-01" -Tool "microsoft.powershell"
   Test-ADAgentToolAccess -Identity "test-agent-01" -Tool "microsoft.powershell"
   ```

7. **Test Authentication**
   ```powershell
   Install-ADAgentSPN -Identity "test-agent-01"
   Test-ADAgentAuthentication -Identity "test-agent-01" -AuthType Kerberos
   ```

## Phase 2: Schema Installation

### Pre-Installation Checks

```powershell
# Run pre-flight checks
.\schema\install-schema.ps1 -PreflightOnly

# Expected output:
# [OK] Running as Schema Admin
# [OK] Schema Master DC reachable: DC01.corp.contoso.com
# [OK] AD replication healthy
# [OK] No conflicting schema objects found
# [OK] OID range available
```

### Installation Steps

1. **Connect to Schema Master DC**
   ```powershell
   # Identify Schema Master
   $schemaMaster = (Get-ADForest).SchemaMaster
   Enter-PSSession -ComputerName $schemaMaster
   ```

2. **Run Schema Installation**
   ```powershell
   # On Schema Master DC
   cd C:\AgentDirectory
   .\schema\install-schema.ps1 -Verbose
   ```

3. **Verify Installation**
   ```powershell
   # Check schema version
   $schema = Get-ADObject -Identity "CN=Schema,CN=Configuration,DC=corp,DC=contoso,DC=com" -Properties objectVersion
   Write-Host "Schema Version: $($schema.objectVersion)"

   # List agent attributes
   Get-ADObject -SearchBase "CN=Schema,CN=Configuration,DC=corp,DC=contoso,DC=com" `
       -Filter "name -eq 'msDS-Agent' -or name -eq 'msDS-AgentTool' -or name -eq 'msDS-AgentSandbox'" |
       Select-Object Name, ObjectClass
   ```

4. **Force Schema Cache Refresh**
   ```powershell
   # On all DCs
   $dcs = (Get-ADDomainController -Filter *).HostName
   foreach ($dc in $dcs) {
       Invoke-Command -ComputerName $dc -ScriptBlock {
           $root = [ADSI]"LDAP://RootDSE"
           $root.Put("schemaUpdateNow", 1)
           $root.SetInfo()
       }
   }
   ```

5. **Wait for Replication**
   ```powershell
   # Check replication status
   repadmin /syncall /APed

   # Monitor until complete
   repadmin /showrepl * | Select-String "Last attempt"
   ```

### Create Containers

```powershell
# Create Agent container
$systemDN = "CN=System,DC=corp,DC=contoso,DC=com"
New-ADObject -Name "Agents" -Type "container" -Path $systemDN

# Create Agent Tools container
New-ADObject -Name "Agent Tools" -Type "container" -Path $systemDN

# Create Agent Sandboxes container
New-ADObject -Name "Agent Sandboxes" -Type "container" -Path $systemDN

# Set permissions on containers
$agentContainer = "CN=Agents,CN=System,DC=corp,DC=contoso,DC=com"
# Add appropriate ACLs...
```

### Install Default Tools

```powershell
# Import default tool definitions
.\schema\install-schema.ps1 -ToolsOnly
```

## Phase 3: Event Log Provider

### Install on Domain Controllers

```powershell
# On each DC
.\events\Install-EventLog.ps1 -Verbose

# Verify installation
Get-WinEvent -ListLog "Microsoft-AgentDirectory/*"
```

### Configure via Group Policy

1. **Create GPO for Event Log Settings**
   ```powershell
   New-GPO -Name "Agent Directory - Event Log Settings"
   ```

2. **Import ADMX Template**
   - Copy `events\GPO\AgentAuditPolicy.admx` to `C:\Windows\PolicyDefinitions`
   - Copy `events\GPO\en-US\AgentAuditPolicy.adml` to `C:\Windows\PolicyDefinitions\en-US`

3. **Configure Settings**
   - Computer Configuration → Administrative Templates → Agent Directory
   - Set log size, retention, and audit levels

4. **Link GPO**
   ```powershell
   New-GPLink -Name "Agent Directory - Event Log Settings" `
       -Target "OU=Domain Controllers,DC=corp,DC=contoso,DC=com"
   ```

### Configure Event Forwarding

```powershell
# On collector server
.\examples\configure-event-forwarding.ps1 -CollectorMode

# On DCs (source)
.\examples\configure-event-forwarding.ps1 -SourceMode -CollectorServer "collector.corp.contoso.com"
```

## Phase 4: PowerShell Module Deployment

### Option A: Manual Installation

```powershell
# Copy module to PowerShell modules path
Copy-Item -Path ".\powershell\AgentDirectory" `
    -Destination "$env:ProgramFiles\WindowsPowerShell\Modules" `
    -Recurse

# Verify installation
Get-Module -ListAvailable AgentDirectory
```

### Option B: PSGallery (Internal)

```powershell
# Publish to internal gallery
Publish-Module -Path ".\powershell\AgentDirectory" `
    -Repository InternalGallery `
    -NuGetApiKey $apiKey

# Install from gallery
Install-Module -Name AgentDirectory -Repository InternalGallery
```

### Option C: SCCM/Intune Deployment

Package the module for deployment via configuration management:

```powershell
# Create package
$packagePath = "C:\Packages\AgentDirectory"
Copy-Item -Path ".\powershell\AgentDirectory" -Destination $packagePath -Recurse

# Create install script
@'
$targetPath = "$env:ProgramFiles\WindowsPowerShell\Modules\AgentDirectory"
if (Test-Path $targetPath) { Remove-Item $targetPath -Recurse -Force }
Copy-Item -Path ".\AgentDirectory" -Destination "$env:ProgramFiles\WindowsPowerShell\Modules" -Recurse
'@ | Out-File "$packagePath\Install.ps1"
```

## Phase 5: Initial Configuration

### Create Administrative Groups

```powershell
# Agent Administrators - Full control over agents
New-ADGroup -Name "AG-Admins-Agents" `
    -GroupScope Global `
    -GroupCategory Security `
    -Path "OU=Admin Groups,DC=corp,DC=contoso,DC=com"

# Agent Operators - Create and manage agents
New-ADGroup -Name "AG-Operators-Agents" `
    -GroupScope Global `
    -GroupCategory Security `
    -Path "OU=Admin Groups,DC=corp,DC=contoso,DC=com"

# Tool grants groups
New-ADGroup -Name "AG-Tools-Office-Basic" -GroupScope Global -GroupCategory Security
New-ADGroup -Name "AG-Tools-PowerShell" -GroupScope Global -GroupCategory Security
New-ADGroup -Name "AG-Tools-Management" -GroupScope Global -GroupCategory Security
```

### Set Container Permissions

```powershell
$agentContainer = "AD:CN=Agents,CN=System,DC=corp,DC=contoso,DC=com"

# Grant AG-Admins-Agents full control
$acl = Get-Acl $agentContainer
$admins = Get-ADGroup "AG-Admins-Agents"
$rule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
    $admins.SID, "GenericAll", "Allow", "Descendents"
)
$acl.AddAccessRule($rule)
Set-Acl $agentContainer $acl
```

### Create First Agent

```powershell
Import-Module AgentDirectory

# Create a test agent (user object)
$agent = New-ADAgent -Name "pilot-agent-01" `
    -Type "assistant" `
    -Owner "CN=IT Admins,OU=Groups,DC=corp,DC=contoso,DC=com" `
    -TrustLevel 1 `
    -Model "claude-opus-4-5" `
    -Description "Pilot AI assistant for IT operations"

# Create sandbox (computer object) for the agent
$sandbox = New-ADAgentSandbox -Name "pilot-sbx-01" `
    -SecurityProfile "bwrap" `
    -Description "Sandbox for pilot agent"
Set-ADAgent -Identity "pilot-agent-01" -AddSandbox $sandbox.DistinguishedName

# Grant basic tool access
Grant-ADAgentToolAccess -Identity $agent -Tool "filesystem.read", "microsoft.teams"

# Enable the agent
Enable-ADAccount -Identity $agent.DistinguishedName
```

## Post-Deployment Verification

### Schema Verification

```powershell
# Verify agent class
$agentClass = Get-ADObject -SearchBase "CN=Schema,CN=Configuration,DC=corp,DC=contoso,DC=com" `
    -Filter "name -eq 'msDS-Agent'" -Properties *
$agentClass | Select-Object Name, subClassOf, systemMustContain, systemMayContain

# Verify tool class
$toolClass = Get-ADObject -SearchBase "CN=Schema,CN=Configuration,DC=corp,DC=contoso,DC=com" `
    -Filter "name -eq 'msDS-AgentTool'" -Properties *
$toolClass | Select-Object Name, subClassOf

# Verify sandbox class
$sandboxClass = Get-ADObject -SearchBase "CN=Schema,CN=Configuration,DC=corp,DC=contoso,DC=com" `
    -Filter "name -eq 'msDS-AgentSandbox'" -Properties *
$sandboxClass | Select-Object Name, subClassOf
```

### Replication Verification

```powershell
# Check all DCs have schema changes
$dcs = (Get-ADDomainController -Filter *).HostName
foreach ($dc in $dcs) {
    $result = Get-ADObject -Server $dc `
        -SearchBase "CN=Schema,CN=Configuration,DC=corp,DC=contoso,DC=com" `
        -Filter "name -eq 'msDS-Agent' -or name -eq 'msDS-AgentSandbox'"
    Write-Host "$dc : $(if ($result) {'OK'} else {'MISSING'})"
}
```

### Event Log Verification

```powershell
# Create a test event
Write-ADAgentEvent -EventId 1000 -Message "Test event" -AgentName "test"

# Verify event logged
Get-WinEvent -LogName "Microsoft-AgentDirectory/Operational" -MaxEvents 1
```

### Module Verification

```powershell
# List all cmdlets
Get-Command -Module AgentDirectory

# Test basic operations
Get-ADAgent | Select-Object Name, Type, TrustLevel
Get-ADAgentTool | Select-Object Identifier, DisplayName, RiskLevel
Get-ADAgentSandbox | Select-Object Name, SecurityProfile, Status
```

## Rollback Procedures

### Schema Rollback (Limited)

Schema objects cannot be deleted, only deactivated:

```powershell
# Deactivate agent class (will prevent new agent creation)
$agentClass = Get-ADObject -SearchBase "CN=Schema,CN=Configuration,DC=corp,DC=contoso,DC=com" `
    -Filter "name -eq 'msDS-Agent'"
Set-ADObject $agentClass -Replace @{isDefunct=$true}
```

### Container Removal

```powershell
# Remove agents first
Get-ADAgent | Remove-ADAgent -Confirm:$false

# Remove tools
Get-ADAgentTool | Remove-ADAgentTool -Confirm:$false

# Remove sandboxes
Get-ADAgentSandbox | Remove-ADAgentSandbox -Confirm:$false

# Remove containers
Remove-ADObject "CN=Agents,CN=System,DC=corp,DC=contoso,DC=com" -Recursive
Remove-ADObject "CN=Agent Tools,CN=System,DC=corp,DC=contoso,DC=com" -Recursive

# Remove sandbox container
Remove-ADObject "CN=Agent Sandboxes,CN=System,DC=corp,DC=contoso,DC=com" -Recursive
```

### Event Log Removal

```powershell
.\events\Uninstall-EventLog.ps1
```

### Module Removal

```powershell
Remove-Item "$env:ProgramFiles\WindowsPowerShell\Modules\AgentDirectory" -Recurse -Force
```

## Monitoring Recommendations

### Key Events to Monitor

| Event ID | Severity | Alert Threshold |
|----------|----------|-----------------|
| 2001 | Warning | >5 per hour per agent |
| 2020 | Critical | Any occurrence |
| 5020 | Critical | Any occurrence |
| 6002 | Critical | Any occurrence |
| 6020 | Critical | Any occurrence |

### Health Check Script

```powershell
# Run daily health check
.\examples\health-check.ps1 | Export-Csv "C:\Logs\agent-health-$(Get-Date -Format 'yyyyMMdd').csv"
```

### Performance Counters

Monitor these counters on DCs:
- LDAP searches for Agent container
- Authentication events for agent accounts
- Kerberos ticket issuance for AGENT/* SPNs

## Troubleshooting

### Common Issues

#### Schema Installation Fails

```
Error: Insufficient permissions to modify schema
Solution: Verify membership in Schema Admins group. Log off and on to refresh token.
```

#### Agent Creation Fails

```
Error: The specified class is not defined in the schema
Solution: Force schema cache refresh on target DC:
  $root = [ADSI]"LDAP://RootDSE"
  $root.Put("schemaUpdateNow", 1)
  $root.SetInfo()
```

#### Event Log Not Created

```
Error: The specified channel was not found
Solution: Re-run Install-EventLog.ps1 with -Force parameter
```

#### Tool Access Denied Unexpectedly

```
Error: Agent trust level insufficient
Solution: Check both agent trust level and tool required trust level:
  Get-ADAgent -Identity <agent> | Select TrustLevel
  Get-ADAgentTool -Identity <tool> | Select RequiredTrustLevel
```

### Log Locations

| Component | Log Location |
|-----------|--------------|
| Schema Installation | Event Log: Directory Service |
| Agent Operations | Event Log: Microsoft-AgentDirectory/Operational |
| PowerShell Module | $env:LOCALAPPDATA\AgentDirectory\Logs |

## Support

For issues with the Agent Directory extension:

1. Check troubleshooting guide above
2. Review event logs for specific error messages
3. Collect diagnostic information:
   ```powershell
   .\examples\collect-diagnostics.ps1 -OutputPath "C:\Support\diag-$(Get-Date -Format 'yyyyMMddHHmm')"
   ```
