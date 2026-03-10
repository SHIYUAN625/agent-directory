<#
.SYNOPSIS
    Example: Configure tool access for an AI agent.

.DESCRIPTION
    This script demonstrates how to grant and configure tool access
    for agents using the Agent Directory module.

.NOTES
    Prerequisites:
    - AgentDirectory module installed
    - Agent already exists
    - Default tools installed
#>

#Requires -Modules AgentDirectory

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AgentName,

    [Parameter()]
    [ValidateSet('BasicOffice', 'Developer', 'Administrator', 'Custom')]
    [string]$Profile = 'BasicOffice'
)

Import-Module AgentDirectory -ErrorAction Stop

Write-Host "Configuring Tool Access for Agent: $AgentName" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Verify agent exists
$agent = Get-ADAgent -Identity $AgentName -ErrorAction Stop
Write-Host "Agent found: $($agent.Name) (Trust Level: $($agent.TrustLevel))" -ForegroundColor Green
Write-Host ""

# Define tool profiles
$toolProfiles = @{
    'BasicOffice' = @(
        'microsoft.word',
        'microsoft.excel',
        'microsoft.powerpoint',
        'microsoft.teams',
        'filesystem.read'
    )
    'Developer' = @(
        'microsoft.vscode',
        'git.cli',
        'python.interpreter',
        'microsoft.powershell.constrained',
        'filesystem.read',
        'filesystem.write',
        'api.http'
    )
    'Administrator' = @(
        'microsoft.powershell',
        'microsoft.aduc',
        'microsoft.dns',
        'microsoft.dhcp',
        'network.winrm',
        'filesystem.read',
        'filesystem.write'
    )
}

# Get tools to grant
$toolsToGrant = if ($Profile -eq 'Custom') {
    Write-Host "Available tools:" -ForegroundColor Yellow
    Get-ADAgentTool | ForEach-Object {
        Write-Host "  $($_.Identifier) (Risk: $($_.RiskLevel), Requires Trust: $($_.RequiredTrustLevel))"
    }
    Write-Host ""

    $input = Read-Host "Enter tool identifiers (comma-separated)"
    $input -split ',' | ForEach-Object { $_.Trim() }
}
else {
    $toolProfiles[$Profile]
}

Write-Host "Tools to grant:" -ForegroundColor Yellow
$toolsToGrant | ForEach-Object { Write-Host "  $_" }
Write-Host ""

# Check trust level compatibility
$issues = @()
foreach ($toolId in $toolsToGrant) {
    try {
        $tool = Get-ADAgentTool -Identity $toolId
        if ($agent.TrustLevel -lt $tool.RequiredTrustLevel) {
            $issues += "  Tool '$toolId' requires trust level $($tool.RequiredTrustLevel), agent has $($agent.TrustLevel)"
        }
    }
    catch {
        Write-Warning "Tool not found: $toolId"
    }
}

if ($issues.Count -gt 0) {
    Write-Host ""
    Write-Host "Trust Level Warnings:" -ForegroundColor Yellow
    $issues | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    Write-Host ""

    $continue = Read-Host "Continue anyway? (y/n)"
    if ($continue -ne 'y') {
        Write-Host "Aborted" -ForegroundColor Red
        exit
    }
}

# Grant tool access
Write-Host ""
Write-Host "Granting tool access..." -ForegroundColor Yellow

Grant-ADAgentToolAccess -Identity $AgentName -Tool $toolsToGrant -Verbose

Write-Host ""
Write-Host "Tool access granted successfully!" -ForegroundColor Green
Write-Host ""

# Verify access
Write-Host "Verifying tool access:" -ForegroundColor Cyan
foreach ($toolId in $toolsToGrant) {
    try {
        $result = Test-ADAgentToolAccess -Identity $AgentName -Tool $toolId
        $status = if ($result.Allowed) { "[OK]" } else { "[DENIED]" }
        $color = if ($result.Allowed) { "Green" } else { "Red" }
        Write-Host "  $status $toolId - $($result.Reason)" -ForegroundColor $color
    }
    catch {
        Write-Host "  [ERROR] $toolId - $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Current authorized tools for agent:" -ForegroundColor Cyan
$updatedAgent = Get-ADAgent -Identity $AgentName
if ($updatedAgent.AuthorizedTools) {
    $updatedAgent.AuthorizedTools | ForEach-Object {
        $tool = Get-ADAgentTool -Identity $_
        Write-Host "  $($tool.Identifier) ($($tool.DisplayName))"
    }
}
else {
    Write-Host "  (none - access is based on trust level)"
}
Write-Host ""
