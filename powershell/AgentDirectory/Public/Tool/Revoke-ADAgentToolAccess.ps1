function Revoke-ADAgentToolAccess {
    <#
    .SYNOPSIS
        Revokes an agent's access to one or more tools.

    .DESCRIPTION
        Removes tool DNs from the agent's msDS-AgentAuthorizedTools attribute
        or adds them to msDS-AgentDeniedTools.

    .PARAMETER Identity
        The identity of the agent.

    .PARAMETER Tool
        One or more tool identifiers to revoke access to.

    .PARAMETER Deny
        Instead of just removing authorization, explicitly deny the tool.

    .PARAMETER All
        Revoke access to all tools.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .PARAMETER PassThru
        Return the modified agent object.

    .EXAMPLE
        Revoke-ADAgentToolAccess -Identity "claude-assistant-01" -Tool "microsoft.powershell"

    .EXAMPLE
        Revoke-ADAgentToolAccess -Identity "claude-assistant-01" -Tool "microsoft.gpo" -Deny

    .EXAMPLE
        Revoke-ADAgentToolAccess -Identity "claude-assistant-01" -All

    .OUTPUTS
        AgentDirectory.Agent (if PassThru is specified)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DistinguishedName', 'DN')]
        [string]$Identity,

        [Parameter(ParameterSetName = 'Specific')]
        [string[]]$Tool,

        [Parameter(ParameterSetName = 'Specific')]
        [switch]$Deny,

        [Parameter(ParameterSetName = 'All')]
        [switch]$All,

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

            if ($All) {
                if ($PSCmdlet.ShouldProcess($Identity, "Revoke all tool access")) {
                    Set-ADObject -Identity $agentDn -Clear 'msDS-AgentAuthorizedTools' @commonParams
                    Write-Verbose "Revoked all tool access from agent '$Identity'"
                }
            }
            else {
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

                # Remove from authorized list
                $existingTools = @($agent.AuthorizedTools)
                $remainingTools = $existingTools | Where-Object { $_ -notin $toolDns }

                if ($PSCmdlet.ShouldProcess($Identity, "Revoke access to tools: $($Tool -join ', ')")) {
                    if ($remainingTools.Count -gt 0) {
                        Set-ADObject -Identity $agentDn -Replace @{
                            'msDS-AgentAuthorizedTools' = $remainingTools
                        } @commonParams
                    }
                    else {
                        Set-ADObject -Identity $agentDn -Clear 'msDS-AgentAuthorizedTools' @commonParams
                    }

                    # If Deny is specified, add to denied list
                    if ($Deny) {
                        $existingDenied = @($agent.DeniedTools)
                        $newDenied = $toolDns | Where-Object { $_ -notin $existingDenied }

                        if ($newDenied.Count -gt 0) {
                            $allDenied = @($existingDenied) + @($newDenied)
                            Set-ADObject -Identity $agentDn -Replace @{
                                'msDS-AgentDeniedTools' = $allDenied
                            } @commonParams
                            Write-Verbose "Explicitly denied tools for agent '$Identity': $($newDenied -join ', ')"
                        }
                    }

                    Write-Verbose "Revoked tool access from agent '$Identity'"
                }
            }

            if ($PassThru) {
                Get-ADAgent -Identity $agentDn @commonParams
            }
        }
        catch {
            Write-Error "Failed to revoke tool access from agent '$Identity': $_"
        }
    }
}
