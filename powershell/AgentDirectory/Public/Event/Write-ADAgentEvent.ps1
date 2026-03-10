function Write-ADAgentEvent {
    <#
    .SYNOPSIS
        Writes an event to the Agent Directory event log.

    .DESCRIPTION
        Creates a custom event in the Microsoft-AgentDirectory event log.

    .PARAMETER EventId
        The event ID (see EVENT-REFERENCE.md for valid IDs).

    .PARAMETER Message
        The event message.

    .PARAMETER AgentName
        The name of the agent related to this event.

    .PARAMETER AgentSid
        The SID of the agent.

    .PARAMETER ToolId
        The tool identifier (for tool-related events).

    .PARAMETER TargetResource
        The target resource being accessed.

    .PARAMETER OnBehalfOf
        The user the agent is acting on behalf of.

    .PARAMETER SourceIP
        The source IP address.

    .PARAMETER Level
        The event level: Information, Warning, Error, Critical.

    .PARAMETER AdditionalData
        Hashtable of additional event data.

    .EXAMPLE
        Write-ADAgentEvent -EventId 4000 -AgentName "claude-01" -ToolId "microsoft.powershell" -Message "Tool execution started"

    .EXAMPLE
        Write-ADAgentEvent -EventId 6002 -AgentName "rogue-agent" -Level Critical -Message "Critical policy violation detected"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$EventId,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [string]$AgentName,

        [Parameter()]
        [string]$AgentSid,

        [Parameter()]
        [string]$ToolId,

        [Parameter()]
        [string]$TargetResource,

        [Parameter()]
        [string]$OnBehalfOf,

        [Parameter()]
        [string]$SourceIP,

        [Parameter()]
        [ValidateSet('Information', 'Warning', 'Error', 'Critical')]
        [string]$Level = 'Information',

        [Parameter()]
        [hashtable]$AdditionalData
    )

    try {
        # Determine which log based on event ID and level
        $logName = $Script:EventLogOperational

        if ($Level -in @('Warning', 'Error', 'Critical')) {
            $logName = $Script:EventLogAdmin
        }

        # Map level to entry type
        $entryType = switch ($Level) {
            'Information' { 'Information' }
            'Warning' { 'Warning' }
            'Error' { 'Error' }
            'Critical' { 'Error' }  # Windows doesn't have Critical, use Error
            default { 'Information' }
        }

        # Build event data
        $eventData = @()

        if ($AgentSid) { $eventData += $AgentSid }
        if ($AgentName) { $eventData += $AgentName }
        if ($ToolId) { $eventData += $ToolId }
        if ($TargetResource) { $eventData += $TargetResource }
        if ($OnBehalfOf) { $eventData += $OnBehalfOf }
        if ($SourceIP) { $eventData += $SourceIP }

        if ($AdditionalData) {
            foreach ($key in $AdditionalData.Keys) {
                $eventData += "$key=$($AdditionalData[$key])"
            }
        }

        # Write event using .NET
        $eventLog = [System.Diagnostics.EventLog]::new()
        $eventLog.Source = $Script:EventProviderName
        $eventLog.Log = $logName

        # Check if source exists, if not try to create
        if (-not [System.Diagnostics.EventLog]::SourceExists($Script:EventProviderName)) {
            Write-Warning "Event source not registered. Install using Install-ADAgentEventLog."
            return
        }

        # Build message with data
        $fullMessage = $Message
        if ($eventData.Count -gt 0) {
            $fullMessage += "`n`nEvent Data:`n$($eventData -join "`n")"
        }

        $eventLog.WriteEntry($fullMessage, $entryType, $EventId)

        Write-Verbose "Wrote event $EventId to $logName"
    }
    catch {
        Write-Error "Failed to write event: $_"
    }
}
