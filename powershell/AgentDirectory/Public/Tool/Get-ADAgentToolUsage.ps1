function Get-ADAgentToolUsage {
    <#
    .SYNOPSIS
        Retrieves tool usage audit records for agents.

    .DESCRIPTION
        Queries the Agent Directory event log for tool execution events.

    .PARAMETER Agent
        Filter by agent name or identity.

    .PARAMETER Tool
        Filter by tool identifier.

    .PARAMETER StartTime
        Start of the time range.

    .PARAMETER EndTime
        End of the time range.

    .PARAMETER MaxEvents
        Maximum number of events to return.

    .PARAMETER ComputerName
        Computer to query events from.

    .PARAMETER Credential
        Credentials for remote event log access.

    .EXAMPLE
        Get-ADAgentToolUsage -Agent "claude-assistant-01" -StartTime (Get-Date).AddDays(-7)

    .EXAMPLE
        Get-ADAgentToolUsage -Tool "microsoft.powershell" -MaxEvents 100

    .OUTPUTS
        PSCustomObject with tool usage records
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Agent,

        [Parameter()]
        [string]$Tool,

        [Parameter()]
        [datetime]$StartTime,

        [Parameter()]
        [datetime]$EndTime,

        [Parameter()]
        [int]$MaxEvents = 1000,

        [Parameter()]
        [string]$ComputerName,

        [Parameter()]
        [pscredential]$Credential
    )

    try {
        # Build XPath filter
        $xpathParts = @()

        # Tool execution events: 4000-4099
        $xpathParts += "(EventID >= 4000 and EventID <= 4099)"

        if ($StartTime) {
            $startTimeUtc = $StartTime.ToUniversalTime().ToString('o')
            $xpathParts += "TimeCreated[@SystemTime >= '$startTimeUtc']"
        }

        if ($EndTime) {
            $endTimeUtc = $EndTime.ToUniversalTime().ToString('o')
            $xpathParts += "TimeCreated[@SystemTime <= '$endTimeUtc']"
        }

        $xpath = "*[System[$($xpathParts -join ' and ')]]"

        # Build Get-WinEvent parameters
        $eventParams = @{
            LogName = $Script:EventLogOperational
            FilterXPath = $xpath
            MaxEvents = $MaxEvents
            ErrorAction = 'SilentlyContinue'
        }

        if ($ComputerName) {
            $eventParams['ComputerName'] = $ComputerName
        }

        if ($Credential) {
            $eventParams['Credential'] = $Credential
        }

        # Query events
        $events = Get-WinEvent @eventParams

        if (-not $events) {
            Write-Verbose "No tool usage events found"
            return
        }

        # Process events
        foreach ($event in $events) {
            # Parse event data
            $xml = [xml]$event.ToXml()
            $data = @{}

            foreach ($node in $xml.Event.EventData.Data) {
                $data[$node.Name] = $node.'#text'
            }

            # Apply filters
            if ($Agent -and $data.AgentName -notlike "*$Agent*") {
                continue
            }

            if ($Tool -and $data.ToolId -ne $Tool) {
                continue
            }

            # Create output object
            [PSCustomObject]@{
                TimeCreated = $event.TimeCreated
                EventId = $event.Id
                AgentName = $data.AgentName
                AgentSid = $data.AgentSid
                ToolId = $data.ToolId
                ToolCategory = $data.ToolCategory
                OnBehalfOf = $data.OnBehalfOf
                SourceIP = $data.SourceIP
                TargetResource = $data.TargetResource
                CommandLine = $data.CommandLine
                ResultCode = $data.ResultCode
                Duration = $data.Duration
                CorrelationId = $data.CorrelationId
            }
        }
    }
    catch {
        if ($_.Exception.Message -like "*No events were found*") {
            Write-Verbose "No tool usage events found"
        }
        else {
            Write-Error "Failed to retrieve tool usage events: $_"
        }
    }
}
