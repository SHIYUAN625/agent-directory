<#
.SYNOPSIS
    Verifies Agent Directory schema deployment in Windows Active Directory.

.DESCRIPTION
    Post-deployment verification script that checks all schema attributes, classes,
    containers, and default objects are correctly installed. Produces a pass/fail
    report suitable for CI or manual validation.

.PARAMETER DomainDN
    The distinguished name of the domain. Auto-detected via Get-ADDomain if not specified.

.EXAMPLE
    .\verify-deployment.ps1
    Runs all verification checks with auto-detected domain.

.EXAMPLE
    .\verify-deployment.ps1 -DomainDN "DC=corp,DC=contoso,DC=com" -Verbose
    Runs checks against a specific domain with verbose output.

.NOTES
    Requires the ActiveDirectory PowerShell module (RSAT or run on a DC).
#>

[CmdletBinding()]
param(
    [string]$DomainDN
)

$ErrorActionPreference = 'Stop'

# Import AD module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Host "[FAIL] ActiveDirectory module not available. Install RSAT or run on a DC." -ForegroundColor Red
    exit 1
}

# Auto-detect domain DN
if (-not $DomainDN) {
    $DomainDN = (Get-ADDomain).DistinguishedName
    Write-Verbose "Auto-detected Domain DN: $DomainDN"
}

$ConfigNC = "CN=Configuration,$DomainDN"
$SchemaNC = "CN=Schema,$ConfigNC"
$SystemDN = "CN=System,$DomainDN"

# Counters
$script:PassCount = 0
$script:FailCount = 0

function Test-Check {
    param(
        [string]$Description,
        [scriptblock]$Test
    )

    try {
        $result = & $Test
        if ($result) {
            $script:PassCount++
            Write-Host "  PASS: $Description" -ForegroundColor Green
        }
        else {
            $script:FailCount++
            Write-Host "  FAIL: $Description" -ForegroundColor Red
        }
    }
    catch {
        $script:FailCount++
        Write-Host "  FAIL: $Description ($($_.Exception.Message))" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Agent Directory Deployment Verification" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Domain: $DomainDN"
Write-Host ""

# ============================================================================
# Category 1: Schema Attributes
# ============================================================================
Write-Host "--- Schema Attributes ---" -ForegroundColor Yellow

# Agent attributes (14)
$agentAttributes = @(
    'msDS-AgentType',
    'msDS-AgentCapabilities',
    'msDS-AgentOwner',
    'msDS-AgentParent',
    'msDS-AgentTrustLevel',
    'msDS-AgentRuntimeEndpoint',
    'msDS-AgentModel',
    'msDS-AgentPolicies',
    'msDS-AgentDelegationScope',
    'msDS-AgentAuditLevel',
    'msDS-AgentAuthorizedTools',
    'msDS-AgentDeniedTools',
    'msDS-AgentSandbox',
    'msDS-AgentInstructionGPOs'
)

foreach ($attr in $agentAttributes) {
    Test-Check "attribute $attr exists" {
        $null -ne (Get-ADObject -SearchBase $SchemaNC -Filter "name -eq '$attr'" -ErrorAction SilentlyContinue)
    }
}

# Sandbox attributes (6)
$sandboxAttributes = @(
    'msDS-SandboxEndpoint',
    'msDS-SandboxAgents',
    'msDS-SandboxResourcePolicy',
    'msDS-SandboxNetworkPolicy',
    'msDS-SandboxSecurityProfile',
    'msDS-SandboxStatus'
)

foreach ($attr in $sandboxAttributes) {
    Test-Check "attribute $attr exists" {
        $null -ne (Get-ADObject -SearchBase $SchemaNC -Filter "name -eq '$attr'" -ErrorAction SilentlyContinue)
    }
}

# Tool attributes (9)
$toolAttributes = @(
    'msDS-ToolIdentifier',
    'msDS-ToolDisplayName',
    'msDS-ToolCategory',
    'msDS-ToolExecutable',
    'msDS-ToolVersion',
    'msDS-ToolRiskLevel',
    'msDS-ToolRequiredTrustLevel',
    'msDS-ToolConstraints',
    'msDS-ToolAuditRequired'
)

foreach ($attr in $toolAttributes) {
    Test-Check "attribute $attr exists" {
        $null -ne (Get-ADObject -SearchBase $SchemaNC -Filter "name -eq '$attr'" -ErrorAction SilentlyContinue)
    }
}

# Policy attributes (8)
$policyAttributes = @(
    'msDS-PolicyIdentifier',
    'msDS-PolicyType',
    'msDS-PolicyPriority',
    'msDS-PolicyPath',
    'msDS-PolicyAppliesToTypes',
    'msDS-PolicyAppliesToTrustLevels',
    'msDS-PolicyEnabled',
    'msDS-PolicyVersion'
)

foreach ($attr in $policyAttributes) {
    Test-Check "attribute $attr exists" {
        $null -ne (Get-ADObject -SearchBase $SchemaNC -Filter "name -eq '$attr'" -ErrorAction SilentlyContinue)
    }
}

# GPO attributes (10)
$gpoAttributes = @(
    'msDS-GPODisplayName',
    'msDS-GPOInstructionPath',
    'msDS-GPOPriority',
    'msDS-GPOMergeStrategy',
    'msDS-GPOAppliesToTypes',
    'msDS-GPOAppliesToTrustLevels',
    'msDS-GPOAppliesToGroups',
    'msDS-GPOEnabled',
    'msDS-GPOVersion',
    'msDS-AgentInstructionGPOs'
)

foreach ($attr in $gpoAttributes) {
    Test-Check "attribute $attr exists" {
        $null -ne (Get-ADObject -SearchBase $SchemaNC -Filter "name -eq '$attr'" -ErrorAction SilentlyContinue)
    }
}

Write-Host ""

# ============================================================================
# Category 2: Schema Classes
# ============================================================================
Write-Host "--- Schema Classes ---" -ForegroundColor Yellow

$schemaClasses = @(
    'msDS-Agent',
    'msDS-AgentSandbox',
    'msDS-AgentTool',
    'msDS-AgentPolicy',
    'msDS-AgentInstructionGPO'
)

foreach ($cls in $schemaClasses) {
    Test-Check "class $cls exists" {
        $null -ne (Get-ADObject -SearchBase $SchemaNC -Filter "name -eq '$cls'" -ErrorAction SilentlyContinue)
    }
}

Write-Host ""

# ============================================================================
# Category 3: Containers
# ============================================================================
Write-Host "--- Containers ---" -ForegroundColor Yellow

$containers = @(
    @{ Name = 'Agents';             DN = "CN=Agents,$SystemDN" },
    @{ Name = 'Agent Tools';        DN = "CN=Agent Tools,$SystemDN" },
    @{ Name = 'Agent Sandboxes';    DN = "CN=Agent Sandboxes,$SystemDN" },
    @{ Name = 'Agent Policies';     DN = "CN=Agent Policies,$SystemDN" },
    @{ Name = 'Agent Instructions'; DN = "CN=Agent Instructions,$SystemDN" }
)

foreach ($container in $containers) {
    Test-Check "container '$($container.Name)' exists" {
        try {
            $null = Get-ADObject -Identity $container.DN -ErrorAction Stop
            $true
        }
        catch { $false }
    }
}

Write-Host ""

# ============================================================================
# Category 4: Default Tools (spot check)
# ============================================================================
Write-Host "--- Default Tools (spot check) ---" -ForegroundColor Yellow

$sampleTools = @(
    'microsoft.powershell',
    'microsoft.cmd',
    'git.cli',
    'python.interpreter',
    'filesystem.read'
)

foreach ($tool in $sampleTools) {
    Test-Check "tool '$tool' exists" {
        try {
            $null = Get-ADObject -Identity "CN=$tool,CN=Agent Tools,$SystemDN" -ErrorAction Stop
            $true
        }
        catch { $false }
    }
}

Write-Host ""

# ============================================================================
# Category 5: Default Policies
# ============================================================================
Write-Host "--- Default Policies ---" -ForegroundColor Yellow

$expectedPolicies = @(
    @{ Name = 'base-security';                Type = 'security'; Priority = 0 },
    @{ Name = 'base-behavior';                Type = 'behavior'; Priority = 10 },
    @{ Name = 'base-resource';                Type = 'resource'; Priority = 20 },
    @{ Name = 'base-network';                 Type = 'network';  Priority = 30 },
    @{ Name = 'type-worker';                  Type = 'behavior'; Priority = 100 },
    @{ Name = 'type-coordinator';             Type = 'behavior'; Priority = 100 },
    @{ Name = 'type-tool';                    Type = 'behavior'; Priority = 100 },
    @{ Name = 'trust-untrusted';              Type = 'security'; Priority = 150 },
    @{ Name = 'trust-elevated';               Type = 'security'; Priority = 150 },
    @{ Name = 'capability-code-review';       Type = 'behavior'; Priority = 120 },
    @{ Name = 'capability-security-analysis'; Type = 'security'; Priority = 120 }
)

foreach ($policy in $expectedPolicies) {
    $policyDN = "CN=$($policy.Name),CN=Agent Policies,$SystemDN"

    Test-Check "policy '$($policy.Name)' exists" {
        try {
            $null = Get-ADObject -Identity $policyDN -ErrorAction Stop
            $true
        }
        catch { $false }
    }

    Test-Check "policy '$($policy.Name)' type=$($policy.Type)" {
        try {
            $obj = Get-ADObject -Identity $policyDN -Properties 'msDS-PolicyType' -ErrorAction Stop
            $obj.'msDS-PolicyType' -eq $policy.Type
        }
        catch { $false }
    }

    Test-Check "policy '$($policy.Name)' priority=$($policy.Priority)" {
        try {
            $obj = Get-ADObject -Identity $policyDN -Properties 'msDS-PolicyPriority' -ErrorAction Stop
            [int]$obj.'msDS-PolicyPriority' -eq $policy.Priority
        }
        catch { $false }
    }
}

Write-Host ""

# ============================================================================
# Category 6: Default Instruction GPOs
# ============================================================================
Write-Host "--- Default Instruction GPOs ---" -ForegroundColor Yellow

$expectedGPOs = @(
    @{ Name = 'base-agent-instructions';       Priority = 0 },
    @{ Name = 'type-assistant-instructions';   Priority = 100 },
    @{ Name = 'type-autonomous-instructions';  Priority = 100 },
    @{ Name = 'type-coordinator-instructions'; Priority = 100 },
    @{ Name = 'type-tool-instructions';        Priority = 100 },
    @{ Name = 'trust-elevated-instructions';   Priority = 200 }
)

foreach ($gpo in $expectedGPOs) {
    $gpoDN = "CN=$($gpo.Name),CN=Agent Instructions,$SystemDN"

    Test-Check "GPO '$($gpo.Name)' exists" {
        try {
            $null = Get-ADObject -Identity $gpoDN -ErrorAction Stop
            $true
        }
        catch { $false }
    }

    Test-Check "GPO '$($gpo.Name)' priority=$($gpo.Priority)" {
        try {
            $obj = Get-ADObject -Identity $gpoDN -Properties 'msDS-GPOPriority' -ErrorAction Stop
            [int]$obj.'msDS-GPOPriority' -eq $gpo.Priority
        }
        catch { $false }
    }
}

Write-Host ""

# ============================================================================
# Summary
# ============================================================================
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Results: $($script:PassCount) passed, $($script:FailCount) failed" -ForegroundColor $(if ($script:FailCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "=====================================" -ForegroundColor Cyan

if ($script:FailCount -gt 0) {
    exit 1
}
exit 0
