<#
.SYNOPSIS
    Installs the Agent Directory schema extension into Active Directory.

.DESCRIPTION
    This script installs the msDS-Agent and msDS-AgentTool schema classes along with
    their associated attributes into Active Directory. It performs pre-flight checks,
    imports LDIF files in the correct order, and creates the necessary containers.

.PARAMETER PreflightOnly
    Only run pre-flight checks without making any changes.

.PARAMETER ToolsOnly
    Only install the default tool definitions (assumes schema is already installed).

.PARAMETER Force
    Skip confirmation prompts.

.PARAMETER DomainDN
    The distinguished name of the domain. Auto-detected if not specified.

.EXAMPLE
    .\install-schema.ps1 -Verbose
    Installs the complete schema extension with verbose output.

.EXAMPLE
    .\install-schema.ps1 -PreflightOnly
    Runs pre-flight checks only.

.EXAMPLE
    .\install-schema.ps1 -ToolsOnly
    Installs only the default tool definitions.

.NOTES
    Requires membership in Schema Admins and Enterprise Admins groups.
    Must be run on a Domain Controller or with RSAT installed.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$PreflightOnly,
    [switch]$ToolsOnly,
    [switch]$Force,
    [string]$DomainDN
)

$ErrorActionPreference = 'Stop'
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# LDIF files in installation order
$LdifFiles = @(
    '01-agent-attributes.ldif',
    '01b-sandbox-attributes.ldif',
    '02-tool-attributes.ldif',
    '02b-policy-attributes.ldif',
    '02c-gpo-attributes.ldif',
    '03-agent-class.ldif',
    '03b-sandbox-class.ldif',
    '03c-policy-class.ldif',
    '03d-gpo-class.ldif',
    '04-tool-class.ldif',
    '05-containers.ldif',
    '06-default-tools.ldif',
    '07-default-policies.ldif',
    '08-default-gpos.ldif'
)

$ToolsOnlyFiles = @(
    '06-default-tools.ldif',
    '07-default-policies.ldif',
    '08-default-gpos.ldif'
)

function Write-Status {
    param([string]$Status, [string]$Message, [ConsoleColor]$Color = 'White')
    $statusText = "[$Status]"
    Write-Host $statusText -ForegroundColor $Color -NoNewline
    Write-Host " $Message"
}

function Test-SchemaAdminMembership {
    Write-Verbose "Checking Schema Admins membership..."
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)

    # Schema Admins SID pattern: S-1-5-21-<domain>-518
    $schemaAdminsSid = (Get-ADGroup -Identity "Schema Admins").SID

    $isMember = $false
    foreach ($group in $identity.Groups) {
        if ($group.Value -eq $schemaAdminsSid.Value) {
            $isMember = $true
            break
        }
    }

    return $isMember
}

function Test-EnterpriseAdminMembership {
    Write-Verbose "Checking Enterprise Admins membership..."
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()

    # Enterprise Admins SID pattern: S-1-5-21-<domain>-519
    $enterpriseAdminsSid = (Get-ADGroup -Identity "Enterprise Admins").SID

    $isMember = $false
    foreach ($group in $identity.Groups) {
        if ($group.Value -eq $enterpriseAdminsSid.Value) {
            $isMember = $true
            break
        }
    }

    return $isMember
}

function Get-SchemaMasterDC {
    Write-Verbose "Identifying Schema Master DC..."
    $forest = Get-ADForest
    return $forest.SchemaMaster
}

function Test-SchemaMasterReachable {
    param([string]$SchemaMaster)
    Write-Verbose "Testing connectivity to Schema Master: $SchemaMaster"

    try {
        $null = Get-ADDomainController -Identity $SchemaMaster
        return $true
    }
    catch {
        return $false
    }
}

function Test-ReplicationHealth {
    Write-Verbose "Checking AD replication health..."

    try {
        $replStatus = repadmin /showrepl * /csv | ConvertFrom-Csv
        $failures = $replStatus | Where-Object { $_.'Number of Failures' -gt 0 }

        if ($failures) {
            Write-Warning "Replication failures detected:"
            $failures | ForEach-Object {
                Write-Warning "  Source: $($_.'Source DC') -> Dest: $($_.'Destination DC')"
            }
            return $false
        }
        return $true
    }
    catch {
        Write-Warning "Could not check replication status: $($_.Exception.Message)"
        return $true  # Don't block if we can't check
    }
}

function Test-SchemaObjectExists {
    param([string]$ObjectName, [string]$ConfigNC)

    try {
        $null = Get-ADObject -SearchBase "CN=Schema,$ConfigNC" -Filter "name -eq '$ObjectName'"
        return $true
    }
    catch {
        return $false
    }
}

function Update-LdifDomainDN {
    param(
        [string]$LdifContent,
        [string]$DomainDN
    )

    # Replace DC=X placeholder with actual domain DN
    $updatedContent = $LdifContent -replace 'DC=X', $DomainDN

    # Also handle Configuration NC references
    $configNC = "CN=Configuration,$DomainDN"

    return $updatedContent
}

function Import-LdifFile {
    param(
        [string]$FilePath,
        [string]$DomainDN,
        [string]$SchemaMaster
    )

    Write-Verbose "Processing LDIF file: $FilePath"

    # Read and update LDIF content
    $content = Get-Content -Path $FilePath -Raw
    $updatedContent = Update-LdifDomainDN -LdifContent $content -DomainDN $DomainDN

    # Create temp file with updated content
    $tempFile = [System.IO.Path]::GetTempFileName()
    $tempFile = [System.IO.Path]::ChangeExtension($tempFile, '.ldif')
    $updatedContent | Out-File -FilePath $tempFile -Encoding UTF8

    try {
        # Import using ldifde
        $result = ldifde -i -f $tempFile -s $SchemaMaster -j $env:TEMP -c "CN=Configuration,DC=X" "CN=Configuration,$DomainDN"

        if ($LASTEXITCODE -ne 0) {
            throw "LDIFDE import failed with exit code $LASTEXITCODE"
        }

        return $true
    }
    finally {
        # Cleanup temp file
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-SchemaRefresh {
    param([string]$SchemaMaster)

    Write-Verbose "Forcing schema cache refresh on $SchemaMaster"

    $rootDSE = [ADSI]"LDAP://$SchemaMaster/RootDSE"
    $rootDSE.Put("schemaUpdateNow", 1)
    $rootDSE.SetInfo()
}

# Main execution
Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Agent Directory Schema Installation" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Import AD module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Status "FAIL" "ActiveDirectory module not available. Install RSAT or run on a DC." -Color Red
    exit 1
}

# Get domain DN if not specified
if (-not $DomainDN) {
    $DomainDN = (Get-ADDomain).DistinguishedName
    Write-Verbose "Auto-detected Domain DN: $DomainDN"
}

$ConfigNC = "CN=Configuration,$DomainDN"

# Pre-flight checks
Write-Host "Running pre-flight checks..." -ForegroundColor Yellow
Write-Host ""

# Check Schema Admin membership
if (Test-SchemaAdminMembership) {
    Write-Status "OK" "Running as Schema Admin" -Color Green
}
else {
    Write-Status "FAIL" "Not a member of Schema Admins group" -Color Red
    if (-not $PreflightOnly) { exit 1 }
}

# Check Enterprise Admin membership (for container creation)
if (Test-EnterpriseAdminMembership) {
    Write-Status "OK" "Running as Enterprise Admin" -Color Green
}
else {
    Write-Status "WARN" "Not a member of Enterprise Admins (may not be able to create containers)" -Color Yellow
}

# Get Schema Master
$schemaMaster = Get-SchemaMasterDC
Write-Status "INFO" "Schema Master DC: $schemaMaster" -Color Cyan

# Test Schema Master connectivity
if (Test-SchemaMasterReachable -SchemaMaster $schemaMaster) {
    Write-Status "OK" "Schema Master DC is reachable" -Color Green
}
else {
    Write-Status "FAIL" "Cannot reach Schema Master DC: $schemaMaster" -Color Red
    if (-not $PreflightOnly) { exit 1 }
}

# Check replication health
if (Test-ReplicationHealth) {
    Write-Status "OK" "AD replication is healthy" -Color Green
}
else {
    Write-Status "WARN" "AD replication issues detected - proceed with caution" -Color Yellow
}

# Check for existing schema objects
$agentClassExists = Test-SchemaObjectExists -ObjectName "msDS-Agent" -ConfigNC $ConfigNC
$toolClassExists = Test-SchemaObjectExists -ObjectName "msDS-AgentTool" -ConfigNC $ConfigNC

if ($agentClassExists) {
    Write-Status "WARN" "msDS-Agent class already exists in schema" -Color Yellow
}
else {
    Write-Status "OK" "msDS-Agent class not found (will be created)" -Color Green
}

if ($toolClassExists) {
    Write-Status "WARN" "msDS-AgentTool class already exists in schema" -Color Yellow
}
else {
    Write-Status "OK" "msDS-AgentTool class not found (will be created)" -Color Green
}

$sandboxClassExists = Test-SchemaObjectExists -ObjectName "msDS-AgentSandbox" -ConfigNC $ConfigNC

if ($sandboxClassExists) {
    Write-Status "WARN" "msDS-AgentSandbox class already exists in schema" -Color Yellow
}
else {
    Write-Status "OK" "msDS-AgentSandbox class not found (will be created)" -Color Green
}

$policyClassExists = Test-SchemaObjectExists -ObjectName "msDS-AgentPolicy" -ConfigNC $ConfigNC

if ($policyClassExists) {
    Write-Status "WARN" "msDS-AgentPolicy class already exists in schema" -Color Yellow
}
else {
    Write-Status "OK" "msDS-AgentPolicy class not found (will be created)" -Color Green
}

$gpoClassExists = Test-SchemaObjectExists -ObjectName "msDS-AgentInstructionGPO" -ConfigNC $ConfigNC

if ($gpoClassExists) {
    Write-Status "WARN" "msDS-AgentInstructionGPO class already exists in schema" -Color Yellow
}
else {
    Write-Status "OK" "msDS-AgentInstructionGPO class not found (will be created)" -Color Green
}

# Check LDIF files exist
$missingFiles = @()
$filesToInstall = if ($ToolsOnly) { $ToolsOnlyFiles } else { $LdifFiles }

foreach ($file in $filesToInstall) {
    $filePath = Join-Path $ScriptPath $file
    if (Test-Path $filePath) {
        Write-Status "OK" "Found: $file" -Color Green
    }
    else {
        Write-Status "FAIL" "Missing: $file" -Color Red
        $missingFiles += $file
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Host ""
    Write-Host "Missing required LDIF files. Cannot proceed." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Pre-flight checks complete." -ForegroundColor Green
Write-Host ""

if ($PreflightOnly) {
    Write-Host "Pre-flight only mode - no changes made." -ForegroundColor Cyan
    exit 0
}

# Confirmation
if (-not $Force) {
    Write-Host "WARNING: Schema modifications are permanent and replicate to all DCs in the forest." -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "Type 'YES' to proceed with schema installation"

    if ($confirm -ne 'YES') {
        Write-Host "Installation cancelled." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""
Write-Host "Installing schema extension..." -ForegroundColor Cyan
Write-Host ""

# Install LDIF files in order
$installSuccess = $true

foreach ($file in $filesToInstall) {
    $filePath = Join-Path $ScriptPath $file

    Write-Host "Installing: $file" -ForegroundColor White

    try {
        if ($PSCmdlet.ShouldProcess($file, "Import LDIF")) {
            Import-LdifFile -FilePath $filePath -DomainDN $DomainDN -SchemaMaster $schemaMaster
            Write-Status "OK" "Imported $file" -Color Green
        }
    }
    catch {
        Write-Status "FAIL" "Failed to import $file`: $($_.Exception.Message)" -Color Red
        $installSuccess = $false

        # For attributes/classes, failure is critical
        if ($file -match '0[1-4]') {
            Write-Host "Critical schema file failed. Stopping installation." -ForegroundColor Red
            break
        }
    }

    # Brief pause between schema changes
    Start-Sleep -Seconds 2
}

if ($installSuccess) {
    Write-Host ""
    Write-Host "Refreshing schema cache..." -ForegroundColor Cyan
    Invoke-SchemaRefresh -SchemaMaster $schemaMaster

    Write-Host ""
    Write-Host "Waiting for schema replication..." -ForegroundColor Cyan
    Start-Sleep -Seconds 10

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "Schema installation complete!" -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Verify replication: repadmin /syncall /APed"
    Write-Host "  2. Refresh schema cache on other DCs"
    Write-Host "  3. Install event log provider: .\events\Install-EventLog.ps1"
    Write-Host "  4. Import PowerShell module: Import-Module AgentDirectory"
    Write-Host ""
}
else {
    Write-Host ""
    Write-Host "Schema installation completed with errors." -ForegroundColor Yellow
    Write-Host "Review the output above and check the ldifde logs in $env:TEMP" -ForegroundColor Yellow
    exit 1
}
