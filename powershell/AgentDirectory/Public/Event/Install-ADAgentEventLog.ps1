function Install-ADAgentEventLog {
    <#
    .SYNOPSIS
        Installs the Agent Directory event log provider.

    .DESCRIPTION
        Registers the event source and creates the event logs for Agent Directory.
        This is a wrapper around the Install-EventLog.ps1 script.

    .PARAMETER InstallPath
        Path where event log resources will be installed.

    .PARAMETER Force
        Overwrite existing installation.

    .EXAMPLE
        Install-ADAgentEventLog

    .EXAMPLE
        Install-ADAgentEventLog -Force
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$InstallPath = "$env:SystemRoot\System32\AgentDirectory",

        [Parameter()]
        [switch]$Force
    )

    try {
        # Check for admin privileges
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw "This function requires Administrator privileges"
        }

        # Find the installation script
        $modulePath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $installScript = Join-Path (Split-Path -Parent $modulePath) "events\Install-EventLog.ps1"

        if (Test-Path $installScript) {
            Write-Verbose "Running installation script: $installScript"

            if ($PSCmdlet.ShouldProcess("Agent Directory Event Provider", "Install")) {
                $scriptParams = @{
                    InstallPath = $InstallPath
                }

                if ($Force) {
                    $scriptParams['Force'] = $true
                }

                & $installScript @scriptParams
            }
        }
        else {
            # Fallback: Create minimal event source
            Write-Verbose "Installation script not found, creating minimal event source"

            $logNames = @(
                'Microsoft-AgentDirectory/Operational',
                'Microsoft-AgentDirectory/Admin'
            )

            if ($PSCmdlet.ShouldProcess($Script:EventProviderName, "Create event source")) {
                # Check if source exists
                if ([System.Diagnostics.EventLog]::SourceExists($Script:EventProviderName)) {
                    if ($Force) {
                        [System.Diagnostics.EventLog]::DeleteEventSource($Script:EventProviderName)
                        Write-Verbose "Removed existing event source"
                    }
                    else {
                        Write-Warning "Event source already exists. Use -Force to recreate."
                        return
                    }
                }

                # Create the event source
                # Note: This creates a basic Application log source
                # For full functionality, use the Install-EventLog.ps1 script
                [System.Diagnostics.EventLog]::CreateEventSource($Script:EventProviderName, 'Application')

                Write-Verbose "Created event source: $($Script:EventProviderName)"
                Write-Warning "Basic event source created in Application log. For full functionality, run events\Install-EventLog.ps1"
            }
        }
    }
    catch {
        Write-Error "Failed to install event log provider: $_"
    }
}
