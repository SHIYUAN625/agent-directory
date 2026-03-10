<#
.SYNOPSIS
    Example: Generate a keytab file for agent Kerberos authentication.

.DESCRIPTION
    This script demonstrates how to generate a keytab file for an agent
    to authenticate using Kerberos without interactive credentials.

.NOTES
    Prerequisites:
    - AgentDirectory module installed
    - Agent already exists with SPNs
    - Running on a domain-joined machine
    - ktpass.exe available (part of RSAT)
#>

#Requires -Modules AgentDirectory

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AgentName,

    [Parameter()]
    [string]$OutputPath = ".\$AgentName.keytab",

    [Parameter()]
    [ValidateSet('AES256', 'AES128', 'RC4')]
    [string]$EncryptionType = 'AES256',

    [Parameter()]
    [switch]$ResetPassword
)

Import-Module AgentDirectory -ErrorAction Stop

Write-Host "Keytab Generation for Agent: $AgentName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verify agent exists
$agent = Get-ADAgent -Identity $AgentName -ErrorAction Stop
Write-Host "Agent found: $($agent.Name)" -ForegroundColor Green
Write-Host "  SAM Account: $($agent.SamAccountName)"
Write-Host ""

# Check SPNs
if (-not $agent.ServicePrincipalNames -or $agent.ServicePrincipalNames.Count -eq 0) {
    Write-Error "No SPNs registered for agent. Run Install-ADAgentSPN first."
    exit 1
}

Write-Host "Registered SPNs:" -ForegroundColor Yellow
$agent.ServicePrincipalNames | ForEach-Object { Write-Host "  $_" }
Write-Host ""

# Get domain info
$domain = Get-ADDomain
$realm = $domain.DNSRoot.ToUpper()
$dcFqdn = $domain.PDCEmulator

Write-Host "Domain: $($domain.DNSRoot)"
Write-Host "Realm: $realm"
Write-Host "DC: $dcFqdn"
Write-Host ""

# Map encryption type
$cryptoArg = switch ($EncryptionType) {
    'AES256' { 'AES256-SHA1' }
    'AES128' { 'AES128-SHA1' }
    'RC4' { 'RC4-HMAC-NT' }
}

# Select principal for keytab
$agentSpn = $agent.ServicePrincipalNames | Where-Object { $_ -like 'AGENT/*' } | Select-Object -First 1
if (-not $agentSpn) {
    $agentSpn = $agent.ServicePrincipalNames | Select-Object -First 1
}

$principal = "$agentSpn@$realm"

Write-Host "Keytab Configuration:" -ForegroundColor Cyan
Write-Host "  Principal: $principal"
Write-Host "  Encryption: $EncryptionType"
Write-Host "  Output: $OutputPath"
Write-Host ""

# Generate password or prompt
if ($ResetPassword) {
    # Generate a random password
    Add-Type -AssemblyName System.Web
    $password = [System.Web.Security.Membership]::GeneratePassword(32, 8)
    Write-Host "Generated new password for agent" -ForegroundColor Yellow
}
else {
    Write-Host "Enter password for agent (or press Enter to generate new):" -ForegroundColor Yellow
    $securePassword = Read-Host -AsSecureString

    if ($securePassword.Length -eq 0) {
        Add-Type -AssemblyName System.Web
        $password = [System.Web.Security.Membership]::GeneratePassword(32, 8)
        Write-Host "Generated new password" -ForegroundColor Yellow
    }
    else {
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
        $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    }
}

Write-Host ""
Write-Host "Generating keytab..." -ForegroundColor Yellow
Write-Host ""

# Build ktpass command
# Note: ktpass updates the password in AD and generates the keytab
$ktpassArgs = @(
    "/princ", $principal,
    "/mapuser", $agent.SamAccountName,
    "/pass", $password,
    "/out", $OutputPath,
    "/crypto", $cryptoArg,
    "/ptype", "KRB5_NT_PRINCIPAL",
    "/target", $dcFqdn
)

Write-Verbose "ktpass $($ktpassArgs -join ' ')"

# Execute ktpass
try {
    $result = & ktpass $ktpassArgs 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Error "ktpass failed: $result"
        exit 1
    }

    Write-Host $result
    Write-Host ""
    Write-Host "Keytab generated successfully!" -ForegroundColor Green
    Write-Host "  File: $(Resolve-Path $OutputPath)"
    Write-Host ""
}
catch {
    Write-Error "Failed to generate keytab: $_"
    exit 1
}

# Verify keytab
Write-Host "Verifying keytab..." -ForegroundColor Yellow

# Use klist to verify (if available)
try {
    $klist = & klist -k -t $OutputPath 2>&1
    Write-Host $klist
}
catch {
    Write-Warning "Could not verify keytab with klist"
}

Write-Host ""
Write-Host "Usage Instructions:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Linux/Unix (kinit):" -ForegroundColor Yellow
Write-Host "    export KRB5_CLIENT_KTNAME=$OutputPath"
Write-Host "    kinit -k -t $OutputPath $principal"
Write-Host ""
Write-Host "  Python (gssapi):" -ForegroundColor Yellow
Write-Host "    import os"
Write-Host "    os.environ['KRB5_CLIENT_KTNAME'] = '$OutputPath'"
Write-Host ""
Write-Host "  PowerShell (SPNEGO):" -ForegroundColor Yellow
Write-Host "    # Keytab is used automatically when running as the agent"
Write-Host ""

Write-Host "Security Notes:" -ForegroundColor Red
Write-Host "  - Store the keytab securely (it contains the agent's credential)"
Write-Host "  - Restrict file permissions to the agent runtime only"
Write-Host "  - Do not commit keytab files to source control"
Write-Host "  - Rotate the password periodically using this script with -ResetPassword"
Write-Host ""
