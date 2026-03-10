function Revoke-ADAgentPolicyLink {
    <#
    .SYNOPSIS
        Unlinks one or more policies from an agent.

    .DESCRIPTION
        Removes policy identifiers from the agent's msDS-AgentPolicies attribute.

    .PARAMETER Identity
        The identity of the agent.

    .PARAMETER Policy
        One or more policy identifiers to unlink.

    .PARAMETER All
        Unlink all policies.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .PARAMETER PassThru
        Return the modified agent object.

    .EXAMPLE
        Revoke-ADAgentPolicyLink -Identity "claude-assistant-01" -Policy "type-worker"

    .EXAMPLE
        Revoke-ADAgentPolicyLink -Identity "claude-assistant-01" -All

    .OUTPUTS
        AgentDirectory.Agent (if PassThru is specified)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DistinguishedName', 'DN')]
        [string]$Identity,

        [Parameter(ParameterSetName = 'Specific')]
        [string[]]$Policy,

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
        $commonParams = @{}
        if ($Credential) { $commonParams['Credential'] = $Credential }
        if ($Server) { $commonParams['Server'] = $Server }
    }

    process {
        try {
            $agentDn = Get-AgentDistinguishedName -Identity $Identity
            $agent = Get-ADAgent -Identity $agentDn @commonParams

            if ($All) {
                if ($PSCmdlet.ShouldProcess($Identity, "Unlink all policies")) {
                    Set-ADObject -Identity $agentDn -Clear 'msDS-AgentPolicies' @commonParams
                    Write-Verbose "Unlinked all policies from agent '$Identity'"
                }
            }
            else {
                $existingPolicies = @($agent.Policies)
                $remainingPolicies = $existingPolicies | Where-Object { $_ -notin $Policy }

                if ($PSCmdlet.ShouldProcess($Identity, "Unlink policies: $($Policy -join ', ')")) {
                    if ($remainingPolicies.Count -gt 0) {
                        Set-ADObject -Identity $agentDn -Replace @{
                            'msDS-AgentPolicies' = $remainingPolicies
                        } @commonParams
                    }
                    else {
                        Set-ADObject -Identity $agentDn -Clear 'msDS-AgentPolicies' @commonParams
                    }

                    Write-Verbose "Unlinked policies from agent '$Identity'"
                }
            }

            if ($PassThru) {
                Get-ADAgent -Identity $agentDn @commonParams
            }
        }
        catch {
            Write-Error "Failed to unlink policies from agent '$Identity': $_"
        }
    }
}
