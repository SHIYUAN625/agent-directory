function Grant-ADAgentPolicyLink {
    <#
    .SYNOPSIS
        Links one or more policies to an agent.

    .DESCRIPTION
        Adds policy identifiers to the agent's msDS-AgentPolicies attribute.

    .PARAMETER Identity
        The identity of the agent.

    .PARAMETER Policy
        One or more policy identifiers to link.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .PARAMETER PassThru
        Return the modified agent object.

    .EXAMPLE
        Grant-ADAgentPolicyLink -Identity "claude-assistant-01" -Policy "base-security", "type-worker"

    .OUTPUTS
        AgentDirectory.Agent (if PassThru is specified)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DistinguishedName', 'DN')]
        [string]$Identity,

        [Parameter(Mandatory)]
        [string[]]$Policy,

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

            # Validate policies exist
            $validPolicies = @()
            foreach ($p in $Policy) {
                try {
                    $null = Get-PolicyDistinguishedName -Identity $p
                    $validPolicies += $p
                }
                catch {
                    Write-Warning "Policy not found: $p"
                }
            }

            if ($validPolicies.Count -eq 0) {
                Write-Warning "No valid policies specified"
                return
            }

            $existingPolicies = @($agent.Policies)
            $newPolicies = $validPolicies | Where-Object { $_ -notin $existingPolicies }

            if ($newPolicies.Count -eq 0) {
                Write-Verbose "All specified policies are already linked to agent '$Identity'"
            }
            else {
                $allPolicies = @($existingPolicies) + @($newPolicies)

                if ($PSCmdlet.ShouldProcess($Identity, "Link policies: $($Policy -join ', ')")) {
                    Set-ADObject -Identity $agentDn -Replace @{
                        'msDS-AgentPolicies' = $allPolicies
                    } @commonParams

                    Write-Verbose "Linked policies to agent '$Identity': $($newPolicies -join ', ')"
                }
            }

            if ($PassThru) {
                Get-ADAgent -Identity $agentDn @commonParams
            }
        }
        catch {
            Write-Error "Failed to link policies to agent '$Identity': $_"
        }
    }
}
