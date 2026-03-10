<#
.SYNOPSIS
    Creates an agent.

.EXAMPLE
    .\create-agent.ps1 -Name "my-agent" -TrustLevel 2

.EXAMPLE
    .\create-agent.ps1 -Name "my-agent" -TrustLevel 2 -CanCall @("pdf-converter", "summarizer")
#>

#Requires -Modules AgentDirectory

param(
    [Parameter(Mandatory)]
    [string]$Name,

    [Parameter()]
    [ValidateRange(0, 4)]
    [int]$TrustLevel = 1,

    [Parameter()]
    [string[]]$Tools = @('filesystem.read'),

    [Parameter()]
    [string[]]$CanCall = @(),

    [Parameter()]
    [string]$Owner
)

Import-Module AgentDirectory -ErrorAction Stop

# Resolve owner
if (-not $Owner) {
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $user = Get-ADUser -Filter "sAMAccountName -eq '$($currentUser.Split('\')[1])'"
    $Owner = $user.DistinguishedName
}

# Create agent (user object)
$agent = New-ADAgent -Name $Name -TrustLevel $TrustLevel -Owner $Owner -Verbose
Install-ADAgentSPN -Identity $Name

# Create sandbox (computer object) and link to agent
$sandboxName = "$Name-sandbox"
$sandbox = New-ADAgentSandbox -Name $sandboxName -SecurityProfile "bwrap" -Verbose
Set-ADAgent -Identity $Name -AddSandbox $sandbox.DistinguishedName

# Tools
if ($Tools) {
    Grant-ADAgentToolAccess -Identity $Name -Tool $Tools
}

# Delegation scope (agents this one can call)
if ($CanCall) {
    $scope = $CanCall | ForEach-Object { "AGENT/$_" }
    Set-ADAgent -Identity $Name -DelegationScope $scope
}

# Enable
Set-ADAgent -Identity $Name -Enabled $true

# Done
Write-Host "`nAgent created:" -ForegroundColor Green
Write-Host "  Name:       $Name"
Write-Host "  Trust:      $TrustLevel"
Write-Host "  Sandbox:    $sandboxName"
Write-Host "  Tools:      $($Tools -join ', ')"
Write-Host "  Can call:   $(if ($CanCall) { $CanCall -join ', ' } else { '(none)' })"
