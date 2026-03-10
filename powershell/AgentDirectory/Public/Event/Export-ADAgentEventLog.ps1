function Export-ADAgentEventLog {
    <#
    .SYNOPSIS
        Exports Agent Directory events to a file.

    .DESCRIPTION
        Exports events from the Agent Directory logs to CSV, JSON, or EVTX format.

    .PARAMETER Path
        Output file path.

    .PARAMETER Format
        Output format: CSV, JSON, or EVTX.

    .PARAMETER StartTime
        Start of the time range.

    .PARAMETER EndTime
        End of the time range.

    .PARAMETER EventId
        Filter by event ID(s).

    .PARAMETER Agent
        Filter by agent name.

    .PARAMETER Task
        Filter by task category.

    .PARAMETER IncludeDebug
        Include events from Debug log.

    .PARAMETER ComputerName
        Computer to export from.

    .PARAMETER Credential
        Credentials for remote access.

    .EXAMPLE
        Export-ADAgentEventLog -Path "C:\Exports\agent-events.csv" -StartTime "2026-01-01" -EndTime "2026-01-31"

    .EXAMPLE
        Export-ADAgentEventLog -Path "C:\Exports\events.json" -Format JSON -Agent "claude-01"

    .EXAMPLE
        Export-ADAgentEventLog -Path "C:\Exports\security.evtx" -Format EVTX -Task PolicyViolation
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [ValidateSet('CSV', 'JSON', 'EVTX')]
        [string]$Format = 'CSV',

        [Parameter()]
        [datetime]$StartTime,

        [Parameter()]
        [datetime]$EndTime,

        [Parameter()]
        [int[]]$EventId,

        [Parameter()]
        [string]$Agent,

        [Parameter()]
        [ValidateSet('AgentLifecycle', 'AgentAuthentication', 'ToolAccess', 'ToolExecution',
                     'Delegation', 'PolicyViolation', 'TrustChange', 'ResourceAccess')]
        [string]$Task,

        [Parameter()]
        [switch]$IncludeDebug,

        [Parameter()]
        [string]$ComputerName,

        [Parameter()]
        [pscredential]$Credential
    )

    try {
        Write-Verbose "Exporting events to $Path in $Format format"

        if ($Format -eq 'EVTX') {
            # Use wevtutil for EVTX export
            $logs = @($Script:EventLogOperational, $Script:EventLogAdmin)
            if ($IncludeDebug) {
                $logs += 'Microsoft-AgentDirectory/Debug'
            }

            # Build query
            $queryParts = @()
            foreach ($log in $logs) {
                $queryParts += "<Query Id='0' Path='$log'><Select Path='$log'>*</Select></Query>"
            }
            $query = "<QueryList>$($queryParts -join '')</QueryList>"

            # Create temp query file
            $queryFile = [System.IO.Path]::GetTempFileName()
            $query | Out-File -FilePath $queryFile -Encoding UTF8

            try {
                $wevtutilParams = @('epl', '/lf:true', "/sq:$queryFile", $Path)

                if ($ComputerName) {
                    $wevtutilParams += "/r:$ComputerName"
                }

                & wevtutil $wevtutilParams

                if ($LASTEXITCODE -ne 0) {
                    throw "wevtutil failed with exit code $LASTEXITCODE"
                }

                Write-Verbose "Exported events to EVTX file: $Path"
            }
            finally {
                Remove-Item $queryFile -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            # Get events using Get-ADAgentEvent
            $getParams = @{
                MaxEvents = [int]::MaxValue
            }

            if ($StartTime) { $getParams['StartTime'] = $StartTime }
            if ($EndTime) { $getParams['EndTime'] = $EndTime }
            if ($EventId) { $getParams['EventId'] = $EventId }
            if ($Agent) { $getParams['Agent'] = $Agent }
            if ($Task) { $getParams['Task'] = $Task }
            if ($IncludeDebug) { $getParams['IncludeDebug'] = $true }
            if ($ComputerName) { $getParams['ComputerName'] = $ComputerName }
            if ($Credential) { $getParams['Credential'] = $Credential }

            $events = Get-ADAgentEvent @getParams

            if (-not $events) {
                Write-Warning "No events found to export"
                return
            }

            # Flatten event data for export
            $exportData = $events | ForEach-Object {
                $flat = [ordered]@{
                    TimeCreated = $_.TimeCreated
                    EventId = $_.EventId
                    Level = $_.Level
                    Task = $_.Task
                    ComputerName = $_.ComputerName
                    AgentName = $_.AgentName
                    AgentSid = $_.AgentSid
                    Message = $_.Message -replace "`r`n", " " -replace "`n", " "
                }

                # Add event data fields
                foreach ($key in $_.EventData.Keys) {
                    $flat["Data_$key"] = $_.EventData[$key]
                }

                [PSCustomObject]$flat
            }

            switch ($Format) {
                'CSV' {
                    $exportData | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
                }
                'JSON' {
                    $exportData | ConvertTo-Json -Depth 10 | Out-File -Path $Path -Encoding UTF8
                }
            }

            Write-Verbose "Exported $($exportData.Count) events to $Path"
        }

        # Return file info
        Get-Item $Path
    }
    catch {
        Write-Error "Failed to export events: $_"
    }
}
