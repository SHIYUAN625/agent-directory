<#
.SYNOPSIS
    Uninstalls the Agent Directory event log provider.

.DESCRIPTION
    This script unregisters the Agent Directory event provider from Windows Event Log
    and removes the installation files.

.PARAMETER InstallPath
    Path where the event log resources are installed.
    Default: C:\Windows\System32\AgentDirectory

.PARAMETER KeepLogs
    Do not clear existing event logs before uninstalling.

.EXAMPLE
    .\Uninstall-EventLog.ps1 -Verbose
    Uninstalls the event log provider.

.EXAMPLE
    .\Uninstall-EventLog.ps1 -KeepLogs
    Uninstalls but preserves existing events.

.NOTES
    Requires Administrator privileges.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InstallPath = "$env:SystemRoot\System32\AgentDirectory",
    [switch]$KeepLogs
)

$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Main execution
Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Agent Directory Event Log Uninstall" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Check administrator
if (-not (Test-Administrator)) {
    Write-Error "This script requires Administrator privileges. Please run as Administrator."
    exit 1
}

# Check for installation
$manifestPath = Join-Path $InstallPath "AgentDirectory.man"
if (-not (Test-Path $manifestPath)) {
    Write-Warning "Event provider does not appear to be installed at: $InstallPath"

    # Try to unregister anyway
    Write-Host "Attempting to unregister provider..." -ForegroundColor Yellow
}

# Export logs if requested
if (-not $KeepLogs) {
    Write-Host "Clearing event logs..." -ForegroundColor Yellow

    $logs = @(
        'Microsoft-AgentDirectory/Operational',
        'Microsoft-AgentDirectory/Admin',
        'Microsoft-AgentDirectory/Debug'
    )

    foreach ($log in $logs) {
        try {
            if ($PSCmdlet.ShouldProcess($log, "Clear event log")) {
                wevtutil cl $log 2>$null
                Write-Host "  Cleared: $log" -ForegroundColor White
            }
        }
        catch {
            # Log may not exist
        }
    }
}

# Unregister provider
Write-Host ""
Write-Host "Unregistering event provider..." -ForegroundColor Yellow

if (Test-Path $manifestPath) {
    if ($PSCmdlet.ShouldProcess("Microsoft-AgentDirectory", "Unregister event provider")) {
        $result = & wevtutil um $manifestPath 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Event provider unregistered" -ForegroundColor Green
        }
        else {
            Write-Warning "wevtutil returned: $result"
        }
    }
}
else {
    Write-Warning "Manifest not found, skipping unregister"
}

# Remove files
Write-Host ""
Write-Host "Removing installation files..." -ForegroundColor Yellow

if (Test-Path $InstallPath) {
    if ($PSCmdlet.ShouldProcess($InstallPath, "Remove installation directory")) {
        Remove-Item -Path $InstallPath -Recurse -Force
        Write-Host "[OK] Installation directory removed" -ForegroundColor Green
    }
}
else {
    Write-Host "Installation directory not found" -ForegroundColor Yellow
}

# Verify removal
Write-Host ""
Write-Host "Verifying removal..." -ForegroundColor Yellow

$remainingLogs = wevtutil el | Where-Object { $_ -like "Microsoft-AgentDirectory*" }

if ($remainingLogs) {
    Write-Warning "Some event logs may still be registered:"
    $remainingLogs | ForEach-Object { Write-Warning "  $_" }
    Write-Warning "A restart may be required to complete removal."
}
else {
    Write-Host "[OK] All event logs removed" -ForegroundColor Green
}

Write-Host ""
Write-Host "=====================================" -ForegroundColor Green
Write-Host "Uninstallation complete!" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host ""
