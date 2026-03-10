<#
.SYNOPSIS
    Example: Create and manage an Agent Sandbox in Active Directory.

.DESCRIPTION
    This script demonstrates the full lifecycle of an msDS-AgentSandbox
    object: creation, linking to agents, configuration, and teardown.

    Sandboxes are computer objects that represent the execution environment
    where agents run. Agents (user objects) are linked to sandboxes via
    the msDS-AgentSandbox attribute.

.NOTES
    Prerequisites:
    - AgentDirectory module installed
    - Schema extension installed (v2.0+)
    - Appropriate permissions (Domain Admins or delegated)
#>

#Requires -Modules AgentDirectory

[CmdletBinding()]
param(
    [Parameter()]
    [string]$SandboxName = "sandbox-prod-001",

    [Parameter()]
    [string]$SecurityProfile = "bwrap",

    [Parameter()]
    [string]$Endpoint = "https://sandbox-001.corp.contoso.com:8443"
)

Import-Module AgentDirectory -ErrorAction Stop

Write-Host "Agent Sandbox Lifecycle Example" -ForegroundColor Cyan
Write-Host "===============================" -ForegroundColor Cyan
Write-Host ""

# --- Step 1: Create the sandbox ---
Write-Host "Step 1: Creating sandbox..." -ForegroundColor Yellow

$sandbox = New-ADAgentSandbox -Name $SandboxName `
    -SecurityProfile $SecurityProfile `
    -Endpoint $Endpoint `
    -ResourcePolicy '{"cpu_limit":"2","memory_limit":"4Gi"}' `
    -NetworkPolicy '{"egress":"restricted","allowed_hosts":["*.corp.contoso.com"]}' `
    -Description "Production sandbox for AI agents" `
    -Verbose

Write-Host "Sandbox created: $($sandbox.Name)" -ForegroundColor Green
Write-Host "  DN: $($sandbox.DistinguishedName)"
Write-Host "  SAM Account: $($sandbox.SamAccountName)"
Write-Host "  Security Profile: $($sandbox.SecurityProfile)"
Write-Host "  Endpoint: $($sandbox.Endpoint)"
Write-Host ""

# --- Step 2: Link agents to this sandbox ---
Write-Host "Step 2: Linking agents to sandbox..." -ForegroundColor Yellow

# Find agents to link (example: all assistants)
$agents = Get-ADAgent -Filter "msDS-AgentType -eq 'assistant'"
foreach ($agent in $agents) {
    Write-Host "  Linking $($agent.Name) -> $SandboxName"
    Set-ADAgent -Identity $agent.Name -AddSandbox $sandbox.DistinguishedName
}

Write-Host "Linked $($agents.Count) agent(s) to sandbox" -ForegroundColor Green
Write-Host ""

# --- Step 3: Activate the sandbox ---
Write-Host "Step 3: Activating sandbox..." -ForegroundColor Yellow

Set-ADAgentSandbox -Identity $SandboxName -Status "active"
Write-Host "Sandbox status set to 'active'" -ForegroundColor Green
Write-Host ""

# --- Step 4: Query sandbox details ---
Write-Host "Step 4: Querying sandbox..." -ForegroundColor Yellow

$details = Get-ADAgentSandbox -Identity $SandboxName
Write-Host "  Name:             $($details.Name)"
Write-Host "  Security Profile: $($details.SecurityProfile)"
Write-Host "  Status:           $($details.Status)"
Write-Host "  Endpoint:         $($details.Endpoint)"
Write-Host "  Linked Agents:    $($details.Agents -join ', ')"
Write-Host ""

# --- Step 5: Configure RBCD on sandbox ---
Write-Host "Step 5: Configuring RBCD delegation..." -ForegroundColor Yellow
Write-Host "  (Sandbox computer objects can be targets of RBCD)" -ForegroundColor DarkGray

# Example: Allow a specific agent to delegate to a file server via this sandbox
# Grant-ADAgentDelegation -Identity "claude-assistant-01" `
#     -TargetService "cifs/fileserver.corp.contoso.com" `
#     -SandboxIdentity $SandboxName

Write-Host "  (Uncomment RBCD commands for your environment)" -ForegroundColor DarkGray
Write-Host ""

# --- Step 6: Teardown (optional) ---
Write-Host "Step 6: Teardown example (not executed)..." -ForegroundColor Yellow
Write-Host "  To decommission a sandbox:" -ForegroundColor DarkGray
Write-Host "    # Unlink agents first" -ForegroundColor DarkGray
Write-Host "    Set-ADAgent -Identity 'agent-name' -RemoveSandbox '$($sandbox.DistinguishedName)'" -ForegroundColor DarkGray
Write-Host "    # Set status to terminated" -ForegroundColor DarkGray
Write-Host "    Set-ADAgentSandbox -Identity '$SandboxName' -Status 'terminated'" -ForegroundColor DarkGray
Write-Host "    # Remove sandbox object" -ForegroundColor DarkGray
Write-Host "    Remove-ADAgentSandbox -Identity '$SandboxName'" -ForegroundColor DarkGray
Write-Host ""

Write-Host "Done!" -ForegroundColor Green
