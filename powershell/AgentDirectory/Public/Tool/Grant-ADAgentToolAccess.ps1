function Grant-ADAgentToolAccess {
    <#
    .SYNOPSIS
        Grants an agent access to one or more tools.

    .DESCRIPTION
        Adds tool DNs to the agent's msDS-AgentAuthorizedTools attribute.

    .PARAMETER Identity
        The identity of the agent.

    .PARAMETER Tool
        One or more tool identifiers to grant access to.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .PARAMETER PassThru
        Return the modified agent object.

    .EXAMPLE
        Grant-ADAgentToolAccess -Identity "claude-assistant-01" -Tool "microsoft.powershell", "microsoft.word"

    .EXAMPLE
        Get-ADAgent -Type "assistant" | Grant-ADAgentToolAccess -Tool "microsoft.teams"

    .OUTPUTS
        AgentDirectory.Agent (if PassThru is specified)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DistinguishedName', 'DN')]
        [string]$Identity,

        [Parameter(Mandatory)]
        [string[]]$Tool,

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
            # Resolve agent identity
            $agentDn = Get-AgentDistinguishedName -Identity $Identity
            $agent = Get-ADAgent -Identity $agentDn @commonParams

            # Resolve tool identities
            $toolDns = @()
            foreach ($t in $Tool) {
                try {
                    $toolDn = Get-ToolDistinguishedName -Identity $t
                    $toolDns += $toolDn
                }
                catch {
                    Write-Warning "Tool not found: $t"
                }
            }

            if ($toolDns.Count -eq 0) {
                Write-Warning "No valid tools specified"
                return
            }

            # Get existing authorized tools
            $existingTools = @($agent.AuthorizedTools)

            # Add new tools
            $newTools = $toolDns | Where-Object { $_ -notin $existingTools }

            if ($newTools.Count -eq 0) {
                Write-Verbose "All specified tools are already authorized for agent '$Identity'"
            }
            else {
                $allTools = @($existingTools) + @($newTools)

                if ($PSCmdlet.ShouldProcess($Identity, "Grant access to tools: $($Tool -join ', ')")) {
                    Set-ADObject -Identity $agentDn -Replace @{
                        'msDS-AgentAuthorizedTools' = $allTools
                    } @commonParams

                    Write-Verbose "Granted tool access to agent '$Identity': $($newTools -join ', ')"
                }
            }

            if ($PassThru) {
                Get-ADAgent -Identity $agentDn @commonParams
            }
        }
        catch {
            Write-Error "Failed to grant tool access to agent '$Identity': $_"
        }
    }
}
