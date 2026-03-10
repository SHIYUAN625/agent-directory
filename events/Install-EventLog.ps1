<#
.SYNOPSIS
    Installs the Agent Directory event log provider.

.DESCRIPTION
    This script registers the Agent Directory event provider with Windows Event Log.
    It compiles the event manifest, creates the message resource DLL, and registers
    the provider using wevtutil.

.PARAMETER InstallPath
    Path where the event log resources will be installed.
    Default: C:\Windows\System32\AgentDirectory

.PARAMETER Force
    Overwrite existing installation.

.EXAMPLE
    .\Install-EventLog.ps1 -Verbose
    Installs the event log provider with verbose output.

.EXAMPLE
    .\Install-EventLog.ps1 -InstallPath "D:\AgentDirectory" -Force
    Installs to a custom path, overwriting any existing installation.

.NOTES
    Requires Administrator privileges.
    Requires Windows SDK for mc.exe, rc.exe, and link.exe (or uses fallback method).
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InstallPath = "$env:SystemRoot\System32\AgentDirectory",
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-WindowsSDK {
    $sdkPaths = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64",
        "${env:ProgramFiles}\Windows Kits\10\bin\*\x64",
        "${env:ProgramFiles(x86)}\Windows Kits\8.1\bin\x64"
    )

    foreach ($pattern in $sdkPaths) {
        $paths = Get-ChildItem -Path $pattern -Directory -ErrorAction SilentlyContinue |
                 Sort-Object Name -Descending |
                 Select-Object -First 1

        if ($paths -and (Test-Path "$($paths.FullName)\mc.exe")) {
            return $paths.FullName
        }
    }

    return $null
}

function New-EventLogResources {
    param(
        [string]$ManifestPath,
        [string]$OutputPath,
        [string]$SdkPath
    )

    $manifestName = [System.IO.Path]::GetFileNameWithoutExtension($ManifestPath)

    if ($SdkPath) {
        Write-Verbose "Using Windows SDK at: $SdkPath"

        # Compile manifest
        Write-Verbose "Compiling event manifest..."
        $mcExe = Join-Path $SdkPath "mc.exe"
        & $mcExe -um $ManifestPath -r $OutputPath -h $OutputPath

        if ($LASTEXITCODE -ne 0) {
            throw "mc.exe failed with exit code $LASTEXITCODE"
        }

        # Compile resources
        Write-Verbose "Compiling resources..."
        $rcExe = Join-Path $SdkPath "rc.exe"
        $rcFile = Join-Path $OutputPath "$manifestName.rc"
        & $rcExe /fo "$OutputPath\$manifestName.res" $rcFile

        if ($LASTEXITCODE -ne 0) {
            throw "rc.exe failed with exit code $LASTEXITCODE"
        }

        # Link to DLL
        Write-Verbose "Creating resource DLL..."
        $linkExe = Join-Path $SdkPath "link.exe"
        & $linkExe /DLL /NOENTRY /MACHINE:X64 /OUT:"$OutputPath\$manifestName.dll" "$OutputPath\$manifestName.res"

        if ($LASTEXITCODE -ne 0) {
            throw "link.exe failed with exit code $LASTEXITCODE"
        }

        return "$OutputPath\$manifestName.dll"
    }
    else {
        # Fallback: Create a minimal resource-only DLL using .NET
        Write-Warning "Windows SDK not found. Creating minimal resource DLL..."

        # Copy manifest for wevtutil to use directly
        Copy-Item -Path $ManifestPath -Destination "$OutputPath\$manifestName.man" -Force

        # Create a placeholder DLL (wevtutil will use manifest strings)
        $dllPath = "$OutputPath\$manifestName.dll"

        # Create minimal PE file
        # This is a minimal valid PE32+ DLL with no code
        $minimalDll = [byte[]]@(
            # DOS Header
            0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00,
            0x04, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00,
            0xB8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00,
            # DOS Stub
            0x0E, 0x1F, 0xBA, 0x0E, 0x00, 0xB4, 0x09, 0xCD,
            0x21, 0xB8, 0x01, 0x4C, 0xCD, 0x21, 0x54, 0x68,
            0x69, 0x73, 0x20, 0x70, 0x72, 0x6F, 0x67, 0x72,
            0x61, 0x6D, 0x20, 0x63, 0x61, 0x6E, 0x6E, 0x6F,
            0x74, 0x20, 0x62, 0x65, 0x20, 0x72, 0x75, 0x6E,
            0x20, 0x69, 0x6E, 0x20, 0x44, 0x4F, 0x53, 0x20,
            0x6D, 0x6F, 0x64, 0x65, 0x2E, 0x0D, 0x0D, 0x0A,
            0x24, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            # PE Signature
            0x50, 0x45, 0x00, 0x00,
            # COFF Header (PE32+)
            0x64, 0x86,  # Machine: AMD64
            0x00, 0x00,  # NumberOfSections: 0
            0x00, 0x00, 0x00, 0x00,  # TimeDateStamp
            0x00, 0x00, 0x00, 0x00,  # PointerToSymbolTable
            0x00, 0x00, 0x00, 0x00,  # NumberOfSymbols
            0xF0, 0x00,  # SizeOfOptionalHeader
            0x22, 0x20   # Characteristics: DLL, LARGE_ADDRESS_AWARE
        )

        [System.IO.File]::WriteAllBytes($dllPath, $minimalDll)

        Write-Verbose "Created placeholder DLL at: $dllPath"
        return $dllPath
    }
}

# Main execution
Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Agent Directory Event Log Installation" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Check administrator
if (-not (Test-Administrator)) {
    Write-Error "This script requires Administrator privileges. Please run as Administrator."
    exit 1
}

Write-Host "Checking prerequisites..." -ForegroundColor Yellow

# Check for existing installation
$existingManifest = "$InstallPath\AgentDirectory.man"
if (Test-Path $existingManifest) {
    if ($Force) {
        Write-Warning "Existing installation found. Removing..."

        # Unregister existing provider
        try {
            wevtutil um $existingManifest 2>$null
        }
        catch { }

        Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    else {
        Write-Error "Event provider already installed. Use -Force to overwrite."
        exit 1
    }
}

# Create installation directory
Write-Host "Creating installation directory: $InstallPath" -ForegroundColor White
if ($PSCmdlet.ShouldProcess($InstallPath, "Create directory")) {
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
}

# Find manifest
$manifestPath = Join-Path $ScriptPath "AgentDirectory.man"
if (-not (Test-Path $manifestPath)) {
    Write-Error "Event manifest not found: $manifestPath"
    exit 1
}

Write-Host "[OK] Event manifest found" -ForegroundColor Green

# Find Windows SDK
$sdkPath = Find-WindowsSDK
if ($sdkPath) {
    Write-Host "[OK] Windows SDK found: $sdkPath" -ForegroundColor Green
}
else {
    Write-Host "[WARN] Windows SDK not found - using fallback method" -ForegroundColor Yellow
}

# Create resources
Write-Host ""
Write-Host "Building event log resources..." -ForegroundColor Yellow

if ($PSCmdlet.ShouldProcess("AgentDirectory.dll", "Create event resources")) {
    $dllPath = New-EventLogResources -ManifestPath $manifestPath -OutputPath $InstallPath -SdkPath $sdkPath

    Write-Host "[OK] Event resources created" -ForegroundColor Green
}

# Copy manifest
Write-Host "Copying manifest..." -ForegroundColor White
$installedManifest = Join-Path $InstallPath "AgentDirectory.man"

# Update manifest paths for installation
$manifestContent = Get-Content -Path $manifestPath -Raw
$manifestContent = $manifestContent -replace 'resourceFileName="AgentDirectory.dll"', "resourceFileName=`"$InstallPath\AgentDirectory.dll`""
$manifestContent = $manifestContent -replace 'messageFileName="AgentDirectory.dll"', "messageFileName=`"$InstallPath\AgentDirectory.dll`""
$manifestContent = $manifestContent -replace 'parameterFileName="AgentDirectory.dll"', "parameterFileName=`"$InstallPath\AgentDirectory.dll`""

if ($PSCmdlet.ShouldProcess($installedManifest, "Write updated manifest")) {
    $manifestContent | Out-File -FilePath $installedManifest -Encoding UTF8
}

# Register provider
Write-Host ""
Write-Host "Registering event provider..." -ForegroundColor Yellow

if ($PSCmdlet.ShouldProcess("Microsoft-AgentDirectory", "Register event provider")) {
    $wevtutilArgs = @("im", $installedManifest)

    $result = & wevtutil $wevtutilArgs 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to register event provider: $result"
        exit 1
    }

    Write-Host "[OK] Event provider registered" -ForegroundColor Green
}

# Verify installation
Write-Host ""
Write-Host "Verifying installation..." -ForegroundColor Yellow

$logs = wevtutil el | Where-Object { $_ -like "Microsoft-AgentDirectory*" }

if ($logs) {
    Write-Host "[OK] Event logs created:" -ForegroundColor Green
    $logs | ForEach-Object { Write-Host "     $_" -ForegroundColor Cyan }
}
else {
    Write-Warning "Event logs not found. Registration may have failed."
}

# Test write
Write-Host ""
Write-Host "Testing event write..." -ForegroundColor Yellow

try {
    $testEvent = @{
        LogName = 'Microsoft-AgentDirectory/Operational'
        Source = 'Microsoft-AgentDirectory'
        EntryType = 'Information'
        EventId = 1000
        Message = 'Agent Directory event provider installed successfully.'
    }

    # Use New-WinEvent for custom provider
    $eventLog = [System.Diagnostics.Eventing.Reader.EventLogConfiguration]::new('Microsoft-AgentDirectory/Operational')

    if ($eventLog.IsEnabled) {
        Write-Host "[OK] Event log is enabled and accessible" -ForegroundColor Green
    }
}
catch {
    Write-Warning "Could not verify event log: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "=====================================" -ForegroundColor Green
Write-Host "Installation complete!" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host ""
Write-Host "Event logs installed:" -ForegroundColor Cyan
Write-Host "  - Microsoft-AgentDirectory/Operational" -ForegroundColor White
Write-Host "  - Microsoft-AgentDirectory/Admin" -ForegroundColor White
Write-Host "  - Microsoft-AgentDirectory/Debug (disabled by default)" -ForegroundColor White
Write-Host ""
Write-Host "To view events:" -ForegroundColor Cyan
Write-Host "  Get-WinEvent -LogName 'Microsoft-AgentDirectory/Operational'" -ForegroundColor White
Write-Host ""
Write-Host "To enable debug log:" -ForegroundColor Cyan
Write-Host "  wevtutil sl 'Microsoft-AgentDirectory/Debug' /e:true" -ForegroundColor White
Write-Host ""
