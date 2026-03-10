function Get-ADAgentEvent {
    <#
    .SYNOPSIS
        Retrieves events from the Agent Directory event log.

    .DESCRIPTION
        Queries the Microsoft-AgentDirectory event logs for agent-related events.

    .PARAMETER EventId
        Filter by specific event ID(s).

    .PARAMETER Agent
        Filter by agent name.

    .PARAMETER Task
        Filter by task category: AgentLifecycle, AgentAuthentication, ToolAccess,
        ToolExecution, Delegation, PolicyViolation, TrustChange, ResourceAccess.

    .PARAMETER Level
        Filter by event level.

    .PARAMETER StartTime
        Start of the time range.

    .PARAMETER EndTime
        End of the time range.

    .PARAMETER MaxEvents
        Maximum number of events to return.

    .PARAMETER ComputerName
        Computer(s) to query events from.

    .PARAMETER Credential
        Credentials for remote event log access.

    .PARAMETER IncludeDebug
        Include events from the Debug log.

    .EXAMPLE
        Get-ADAgentEvent -Agent "claude-assistant-01" -StartTime (Get-Date).AddHours(-24)

    .EXAMPLE
        Get-ADAgentEvent -Task PolicyViolation -Level Error, Critical

    .EXAMPLE
        Get-ADAgentEvent -EventId 2001 -MaxEvents 50

    .OUTPUTS
        PSCustomObject with event details
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int[]]$EventId,

        [Parameter()]
        [string]$Agent,

        [Parameter()]
        [ValidateSet('AgentLifecycle', 'AgentAuthentication', 'ToolAccess', 'ToolExecution',
                     'Delegation', 'PolicyViolation', 'TrustChange', 'ResourceAccess')]
        [string]$Task,

        [Parameter()]
        [ValidateSet('Information', 'Warning', 'Error', 'Critical')]
        [string[]]$Level,

        [Parameter()]
        [datetime]$StartTime,

        [Parameter()]
        [datetime]$EndTime,

        [Parameter()]
        [int]$MaxEvents = 1000,

        [Parameter()]
        [string[]]$ComputerName,

        [Parameter()]
        [pscredential]$Credential,

        [Parameter()]
        [switch]$IncludeDebug
    )

    try {
        # Determine logs to query
        $logs = @($Script:EventLogOperational, $Script:EventLogAdmin)
        if ($IncludeDebug) {
            $logs += 'Microsoft-AgentDirectory/Debug'
        }

        # Map task to event ID ranges
        $taskRanges = @{
            'AgentLifecycle' = @{ Min = 1000; Max = 1099 }
            'AgentAuthentication' = @{ Min = 2000; Max = 2099 }
            'ToolAccess' = @{ Min = 3000; Max = 3099 }
            'ToolExecution' = @{ Min = 4000; Max = 4099 }
            'Delegation' = @{ Min = 5000; Max = 5099 }
            'PolicyViolation' = @{ Min = 6000; Max = 6099 }
            'TrustChange' = @{ Min = 7000; Max = 7099 }
            'ResourceAccess' = @{ Min = 8000; Max = 8099 }
        }

        # Map level to numeric values
        $levelValues = @{
            'Critical' = 1
            'Error' = 2
            'Warning' = 3
            'Information' = 4
        }

        # Build XPath filter parts
        $systemFilters = @()

        # Event ID filter
        if ($EventId) {
            $idFilters = $EventId | ForEach-Object { "EventID=$_" }
            $systemFilters += "($($idFilters -join ' or '))"
        }
        elseif ($Task) {
            $range = $taskRanges[$Task]
            $systemFilters += "(EventID >= $($range.Min) and EventID <= $($range.Max))"
        }

        # Level filter
        if ($Level) {
            $levelFilters = $Level | ForEach-Object { "Level=$($levelValues[$_])" }
            $systemFilters += "($($levelFilters -join ' or '))"
        }

        # Time filters
        if ($StartTime) {
            $startTimeUtc = $StartTime.ToUniversalTime().ToString('o')
            $systemFilters += "TimeCreated[@SystemTime >= '$startTimeUtc']"
        }

        if ($EndTime) {
            $endTimeUtc = $EndTime.ToUniversalTime().ToString('o')
            $systemFilters += "TimeCreated[@SystemTime <= '$endTimeUtc']"
        }

        # Build final XPath
        $xpath = "*"
        if ($systemFilters.Count -gt 0) {
            $xpath = "*[System[$($systemFilters -join ' and ')]]"
        }

        Write-Verbose "XPath filter: $xpath"

        # Query each log
        $allEvents = @()

        foreach ($log in $logs) {
            $eventParams = @{
                LogName = $log
                FilterXPath = $xpath
                MaxEvents = $MaxEvents
                ErrorAction = 'SilentlyContinue'
            }

            if ($ComputerName) {
                foreach ($computer in $ComputerName) {
                    $eventParams['ComputerName'] = $computer
                    if ($Credential) {
                        $eventParams['Credential'] = $Credential
                    }

                    $events = Get-WinEvent @eventParams
                    if ($events) {
                        $allEvents += $events
                    }
                }
            }
            else {
                $events = Get-WinEvent @eventParams
                if ($events) {
                    $allEvents += $events
                }
            }
        }

        if (-not $allEvents) {
            Write-Verbose "No events found"
            return
        }

        # Sort by time and limit
        $allEvents = $allEvents | Sort-Object TimeCreated -Descending | Select-Object -First $MaxEvents

        # Process events
        foreach ($event in $allEvents) {
            # Parse event data
            $xml = [xml]$event.ToXml()
            $data = @{}

            foreach ($node in $xml.Event.EventData.Data) {
                if ($node.Name) {
                    $data[$node.Name] = $node.'#text'
                }
            }

            # Apply agent filter
            if ($Agent -and $data.AgentName -notlike "*$Agent*") {
                continue
            }

            # Determine task from event ID
            $taskName = switch -Regex ($event.Id) {
                '10\d{2}' { 'AgentLifecycle' }
                '20\d{2}' { 'AgentAuthentication' }
                '30\d{2}' { 'ToolAccess' }
                '40\d{2}' { 'ToolExecution' }
                '50\d{2}' { 'Delegation' }
                '60\d{2}' { 'PolicyViolation' }
                '70\d{2}' { 'TrustChange' }
                '80\d{2}' { 'ResourceAccess' }
                default { 'Unknown' }
            }

            # Create output object
            [PSCustomObject]@{
                TimeCreated = $event.TimeCreated
                EventId = $event.Id
                Level = $event.LevelDisplayName
                Task = $taskName
                ComputerName = $event.MachineName
                AgentName = $data.AgentName
                AgentSid = $data.AgentSid
                Message = $event.Message
                EventData = $data
            }
        }
    }
    catch {
        if ($_.Exception.Message -like "*No events were found*") {
            Write-Verbose "No events found"
        }
        else {
            Write-Error "Failed to retrieve events: $_"
        }
    }
}
