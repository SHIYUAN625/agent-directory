<#
.SYNOPSIS
    Example: Create a Claude AI assistant agent in Active Directory.

.DESCRIPTION
    This script demonstrates how to create an AI agent account using the
    Agent Directory PowerShell module.

.NOTES
    Prerequisites:
    - AgentDirectory module installed
    - Schema extension installed
    - Appropriate permissions (Domain Admins or delegated)
#>

#Requires -Modules AgentDirectory

[CmdletBinding()]
param(
    [Parameter()]
    [string]$AgentName = "claude-assistant-01",

    [Parameter()]
    [string]$OwnerDN,

    [Parameter()]
    [int]$TrustLevel = 2
)

# Import module
Import-Module AgentDirectory -ErrorAction Stop

Write-Host "Creating Claude AI Agent" -ForegroundColor Cyan
Write-Host "========================" -ForegroundColor Cyan
Write-Host ""

# Determine owner
if (-not $OwnerDN) {
    # Use current user as default owner
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $user = Get-ADUser -Filter "sAMAccountName -eq '$($currentUser.Split('\')[1])'"
    $OwnerDN = $user.DistinguishedName
    Write-Host "Using current user as owner: $OwnerDN"
}

# Create the agent
Write-Host ""
Write-Host "Creating agent: $AgentName" -ForegroundColor Yellow

$agent = New-ADAgent -Name $AgentName `
    -Type "assistant" `
    -TrustLevel $TrustLevel `
    -Owner $OwnerDN `
    -Model "claude-opus-4-5" `
    -Description "Claude AI Assistant for enterprise operations" `
    -Capabilities @(
        "urn:agent:capability:code-generation",
        "urn:agent:capability:document-analysis",
        "urn:agent:capability:data-processing",
        "urn:agent:capability:user-interaction"
    ) `
    -Verbose

Write-Host ""
Write-Host "Agent created successfully!" -ForegroundColor Green
Write-Host ""

# Display agent details
Write-Host "Agent Details:" -ForegroundColor Cyan
Write-Host "  Name: $($agent.Name)"
Write-Host "  DN: $($agent.DistinguishedName)"
Write-Host "  SAM Account: $($agent.SamAccountName)"
Write-Host "  Type: $($agent.Type)"
Write-Host "  Trust Level: $($agent.TrustLevel) ($($agent.TrustLevelName))"
Write-Host "  Model: $($agent.Model)"
Write-Host "  Owner: $($agent.Owner)"
Write-Host "  Enabled: $($agent.Enabled)"
Write-Host ""

# Create a sandbox for this agent
Write-Host "Creating sandbox for agent..." -ForegroundColor Yellow
$sandboxName = "$AgentName-sandbox"

$sandbox = New-ADAgentSandbox -Name $sandboxName `
    -SecurityProfile "appcontainer" `
    -Description "Sandbox for $AgentName" `
    -Verbose

Write-Host "Sandbox created: $($sandbox.Name)" -ForegroundColor Green
Write-Host ""

# Link agent to sandbox
Write-Host "Linking agent to sandbox..." -ForegroundColor Yellow
Set-ADAgent -Identity $agent.Name -AddSandbox $sandbox.DistinguishedName

# Install SPNs
Write-Host "Installing Service Principal Names..." -ForegroundColor Yellow
Install-ADAgentSPN -Identity $agent.Name -Verbose

Write-Host ""
Write-Host "SPNs installed:" -ForegroundColor Green
$updatedAgent = Get-ADAgent -Identity $agent.Name
$updatedAgent.ServicePrincipalNames | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Grant tool access:"
Write-Host "     Grant-ADAgentToolAccess -Identity '$AgentName' -Tool 'microsoft.powershell.constrained', 'microsoft.word'"
Write-Host ""
Write-Host "  2. Configure delegation (if needed):"
Write-Host "     Grant-ADAgentDelegation -Identity '$AgentName' -TargetService 'cifs/fileserver.corp.contoso.com'"
Write-Host ""
Write-Host "  3. Enable the agent:"
Write-Host "     Set-ADAgent -Identity '$AgentName' -Enabled `$true"
Write-Host ""
Write-Host "  4. Generate keytab for authentication:"
Write-Host "     ktpass /princ AGENT/$AgentName@REALM /mapuser $($agent.SamAccountName) /pass * /out $AgentName.keytab /crypto AES256-SHA1"
Write-Host ""
