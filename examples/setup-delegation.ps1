<#
.SYNOPSIS
    Example: Configure Kerberos delegation for an AI agent.

.DESCRIPTION
    This script demonstrates how to configure constrained delegation
    and protocol transition for agents.

.NOTES
    Prerequisites:
    - AgentDirectory module installed
    - Agent already exists with appropriate trust level
    - SPNs installed on agent
#>

#Requires -Modules AgentDirectory

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AgentName,

    [Parameter(Mandatory)]
    [string[]]$TargetServices,

    [Parameter()]
    [string]$SandboxName,

    [Parameter()]
    [switch]$AllowProtocolTransition
)

Import-Module AgentDirectory -ErrorAction Stop

Write-Host "Configuring Kerberos Delegation for Agent: $AgentName" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

# Verify agent exists and check trust level
$agent = Get-ADAgent -Identity $AgentName -ErrorAction Stop
Write-Host "Agent found: $($agent.Name)" -ForegroundColor Green
Write-Host "  Trust Level: $($agent.TrustLevel) ($($agent.TrustLevelName))"
Write-Host "  Enabled: $($agent.Enabled)"
Write-Host ""

# Check trust level
if ($agent.TrustLevel -lt 2) {
    Write-Warning "Agent trust level is below 2 (Standard). Delegation is typically only allowed for Trust Level 2+."
    $continue = Read-Host "Continue anyway? (y/n)"
    if ($continue -ne 'y') {
        exit
    }
}

if ($AllowProtocolTransition -and $agent.TrustLevel -lt 3) {
    Write-Warning "Protocol transition typically requires Trust Level 3 (Elevated) or higher."
    $continue = Read-Host "Continue anyway? (y/n)"
    if ($continue -ne 'y') {
        exit
    }
}

# Check SPNs
Write-Host "Checking SPNs..." -ForegroundColor Yellow
if (-not $agent.ServicePrincipalNames -or $agent.ServicePrincipalNames.Count -eq 0) {
    Write-Warning "No SPNs registered. Installing default SPNs..."
    Install-ADAgentSPN -Identity $AgentName
    $agent = Get-ADAgent -Identity $AgentName
}

Write-Host "Current SPNs:" -ForegroundColor Cyan
$agent.ServicePrincipalNames | ForEach-Object { Write-Host "  $_" }
Write-Host ""

# Display target services
Write-Host "Target services for delegation:" -ForegroundColor Yellow
$TargetServices | ForEach-Object { Write-Host "  $_" }
Write-Host ""

# Validate target services exist
Write-Host "Validating target services..." -ForegroundColor Yellow
foreach ($spn in $TargetServices) {
    try {
        $result = Get-ADObject -Filter "servicePrincipalName -eq '$spn'"
        if ($result) {
            Write-Host "  [OK] $spn" -ForegroundColor Green
        }
        else {
            Write-Host "  [WARN] $spn - Not found in directory" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  [ERROR] $spn - $_" -ForegroundColor Red
    }
}
Write-Host ""

# Confirm
Write-Host "Configuration Summary:" -ForegroundColor Cyan
Write-Host "  Agent: $AgentName"
Write-Host "  Target Services: $($TargetServices -join ', ')"
Write-Host "  Protocol Transition: $AllowProtocolTransition"
Write-Host ""

$confirm = Read-Host "Apply this delegation configuration? (y/n)"
if ($confirm -ne 'y') {
    Write-Host "Aborted" -ForegroundColor Red
    exit
}

# Resolve sandbox for RBCD
if (-not $SandboxName) {
    # Check if agent has a sandbox linked
    $sandboxes = $agent.Sandboxes
    if ($sandboxes -and $sandboxes.Count -gt 0) {
        $SandboxName = ($sandboxes[0] -split ',')[0] -replace '^CN=',''
        Write-Host "Using linked sandbox: $SandboxName" -ForegroundColor Green
    }
}

# Apply delegation
Write-Host ""
Write-Host "Configuring delegation..." -ForegroundColor Yellow

$delegationParams = @{
    Identity = $AgentName
    TargetService = $TargetServices
    PassThru = $true
}

if ($SandboxName) {
    $delegationParams['SandboxIdentity'] = $SandboxName
    Write-Host "RBCD will be configured on sandbox: $SandboxName" -ForegroundColor Yellow
}

if ($AllowProtocolTransition) {
    $delegationParams['AllowProtocolTransition'] = $true
}

$updatedAgent = Grant-ADAgentDelegation @delegationParams -Verbose

Write-Host ""
Write-Host "Delegation configured successfully!" -ForegroundColor Green
Write-Host ""

# Display final configuration
Write-Host "Final Configuration:" -ForegroundColor Cyan
Write-Host "  Delegation Scope:"
$updatedAgent.DelegationScope | ForEach-Object { Write-Host "    $_" }
Write-Host ""

# Test delegation capability
Write-Host "Testing delegation capability:" -ForegroundColor Yellow

$authTest = Test-ADAgentAuthentication -Identity $AgentName -AuthType Kerberos
Write-Host "  Kerberos Auth: $($authTest.Success) - $($authTest.Message)"

foreach ($spn in $TargetServices) {
    $delegTest = Test-ADAgentAuthentication -Identity $AgentName -AuthType Kerberos -TargetService $spn
    $status = if ($delegTest.Details.DelegationConfigured) { "[OK]" } else { "[WARN]" }
    Write-Host "  Delegation to $spn`: $status"
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Ensure the agent has appropriate tool access"
Write-Host "  2. Configure the agent runtime with the delegation credentials"
Write-Host "  3. Test end-to-end delegation with a sample user"
Write-Host ""
