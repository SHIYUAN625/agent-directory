function Set-ADAgent {
    <#
    .SYNOPSIS
        Modifies an AI agent account in Active Directory.

    .DESCRIPTION
        Updates properties of an existing msDS-Agent object.

    .PARAMETER Identity
        The identity of the agent to modify.

    .PARAMETER Type
        The new agent type.

    .PARAMETER TrustLevel
        The new trust level (0-4).

    .PARAMETER Owner
        The new owner distinguished name.

    .PARAMETER Model
        The new AI model identifier.

    .PARAMETER Description
        The new description.

    .PARAMETER Capabilities
        New set of capabilities (replaces existing).

    .PARAMETER AddCapabilities
        Capabilities to add to existing set.

    .PARAMETER RemoveCapabilities
        Capabilities to remove from existing set.

    .PARAMETER Sandbox
        New set of sandbox DNs (replaces existing).

    .PARAMETER AddSandbox
        Sandbox DNs to add to existing set.

    .PARAMETER RemoveSandbox
        Sandbox DNs to remove from existing set.

    .PARAMETER AuditLevel
        The new audit level (0-3).

    .PARAMETER Enabled
        Enable or disable the agent.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .PARAMETER PassThru
        Return the modified agent object.

    .EXAMPLE
        Set-ADAgent -Identity "claude-assistant-01" -TrustLevel 3 -Description "Elevated assistant"

    .EXAMPLE
        Set-ADAgent -Identity "data-processor" -AddCapabilities "urn:agent:capability:network-access"

    .EXAMPLE
        Get-ADAgent -Type "assistant" | Set-ADAgent -Enabled $true

    .OUTPUTS
        AgentDirectory.Agent (if PassThru is specified)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DistinguishedName', 'DN')]
        [string]$Identity,

        [Parameter()]
        [ValidateSet('autonomous', 'assistant', 'tool', 'orchestrator')]
        [string]$Type,

        [Parameter()]
        [ValidateRange(0, 4)]
        [int]$TrustLevel,

        [Parameter()]
        [string]$Owner,

        [Parameter()]
        [string]$Model,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string[]]$Capabilities,

        [Parameter()]
        [string[]]$AddCapabilities,

        [Parameter()]
        [string[]]$RemoveCapabilities,

        [Parameter()]
        [string[]]$Sandbox,

        [Parameter()]
        [string[]]$AddSandbox,

        [Parameter()]
        [string[]]$RemoveSandbox,

        [Parameter()]
        [ValidateRange(0, 3)]
        [int]$AuditLevel,

        [Parameter()]
        [bool]$Enabled,

        [Parameter()]
        [pscredential]$Credential,

        [Parameter()]
        [string]$Server,

        [Parameter()]
        [switch]$PassThru
    )

    begin {
        # Build common parameters
        $commonParams = @{}
        if ($Credential) { $commonParams['Credential'] = $Credential }
        if ($Server) { $commonParams['Server'] = $Server }
    }

    process {
        try {
            # Resolve identity
            $dn = Get-AgentDistinguishedName -Identity $Identity

            # Get current agent for capability modifications
            $currentAgent = $null
            if ($AddCapabilities -or $RemoveCapabilities) {
                $currentAgent = Get-ADAgent -Identity $dn @commonParams
            }

            # Build replace hashtable
            $replace = @{}
            $clear = @()

            if ($Type) {
                $replace['msDS-AgentType'] = $Type.ToLower()
            }

            if ($PSBoundParameters.ContainsKey('TrustLevel')) {
                $replace['msDS-AgentTrustLevel'] = $TrustLevel
            }

            if ($PSBoundParameters.ContainsKey('Owner')) {
                if ($Owner) {
                    $replace['msDS-AgentOwner'] = $Owner
                }
                else {
                    $clear += 'msDS-AgentOwner'
                }
            }

            if ($PSBoundParameters.ContainsKey('Model')) {
                if ($Model) {
                    $replace['msDS-AgentModel'] = $Model
                }
                else {
                    $clear += 'msDS-AgentModel'
                }
            }

            # Handle sandboxes
            if ($Sandbox) {
                $replace['msDS-AgentSandbox'] = $Sandbox
            }
            elseif ($AddSandbox -or $RemoveSandbox) {
                if (-not $currentAgent) {
                    $currentAgent = Get-ADAgent -Identity $dn @commonParams
                }
                $sboxes = @($currentAgent.Sandboxes)

                if ($AddSandbox) {
                    $sboxes = @($sboxes) + @($AddSandbox) | Select-Object -Unique
                }

                if ($RemoveSandbox) {
                    $sboxes = $sboxes | Where-Object { $_ -notin $RemoveSandbox }
                }

                if ($sboxes.Count -gt 0) {
                    $replace['msDS-AgentSandbox'] = $sboxes
                }
                else {
                    $clear += 'msDS-AgentSandbox'
                }
            }

            if ($PSBoundParameters.ContainsKey('AuditLevel')) {
                $replace['msDS-AgentAuditLevel'] = $AuditLevel
            }

            # Handle capabilities
            if ($Capabilities) {
                $replace['msDS-AgentCapabilities'] = $Capabilities
            }
            elseif ($AddCapabilities -or $RemoveCapabilities) {
                $caps = @($currentAgent.Capabilities)

                if ($AddCapabilities) {
                    $caps = @($caps) + @($AddCapabilities) | Select-Object -Unique
                }

                if ($RemoveCapabilities) {
                    $caps = $caps | Where-Object { $_ -notin $RemoveCapabilities }
                }

                if ($caps.Count -gt 0) {
                    $replace['msDS-AgentCapabilities'] = $caps
                }
                else {
                    $clear += 'msDS-AgentCapabilities'
                }
            }

            # Build Set-ADObject parameters
            $setParams = @{
                Identity = $dn
            } + $commonParams

            if ($replace.Count -gt 0) {
                $setParams['Replace'] = $replace
            }

            if ($clear.Count -gt 0) {
                $setParams['Clear'] = $clear
            }

            if ($Description) {
                $setParams['Description'] = $Description
            }

            # Handle enabled status separately
            if ($PSBoundParameters.ContainsKey('Enabled')) {
                if ($PSCmdlet.ShouldProcess($Identity, "Set enabled to $Enabled")) {
                    if ($Enabled) {
                        Enable-ADAccount -Identity $dn @commonParams
                    }
                    else {
                        Disable-ADAccount -Identity $dn @commonParams
                    }
                }
            }

            # Apply changes
            if ($replace.Count -gt 0 -or $clear.Count -gt 0 -or $Description) {
                if ($PSCmdlet.ShouldProcess($Identity, "Modify agent properties")) {
                    Set-ADObject @setParams
                    Write-Verbose "Agent '$Identity' updated successfully"
                }
            }

            if ($PassThru) {
                Get-ADAgent -Identity $dn @commonParams
            }
        }
        catch {
            Write-Error "Failed to modify agent '$Identity': $_"
        }
    }
}
