function Get-ADAgentEffectivePolicy {
    <#
    .SYNOPSIS
        Resolves the effective policy set for an agent.

    .DESCRIPTION
        Retrieves all policies that apply to an agent based on direct links,
        agent type, and trust level, then returns them sorted by priority.

    .PARAMETER Identity
        The identity of the agent.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .EXAMPLE
        Get-ADAgentEffectivePolicy -Identity "claude-assistant-01"

    .OUTPUTS
        AgentDirectory.Policy[]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DistinguishedName', 'DN')]
        [string]$Identity,

        [Parameter()]
        [pscredential]$Credential,

        [Parameter()]
        [string]$Server
    )

    begin {
        $commonParams = @{}
        if ($Credential) { $commonParams['Credential'] = $Credential }
        if ($Server) { $commonParams['Server'] = $Server }
    }

    process {
        try {
            $agent = Get-ADAgent -Identity $Identity @commonParams

            if (-not $agent) {
                throw "Agent not found: $Identity"
            }

            # Get all policies
            $allPolicies = Get-ADAgentPolicy @commonParams

            $effectivePolicies = @()

            foreach ($policy in $allPolicies) {
                # Skip disabled policies
                if ($policy.Enabled -eq $false) {
                    continue
                }

                $applies = $true

                # Check type scope
                if ($policy.AppliesToTypes -and $policy.AppliesToTypes.Count -gt 0) {
                    if ($agent.Type -notin $policy.AppliesToTypes) {
                        $applies = $false
                    }
                }

                # Check trust level scope
                if ($applies -and $policy.AppliesToTrustLevels -and $policy.AppliesToTrustLevels.Count -gt 0) {
                    if ($agent.TrustLevel -notin $policy.AppliesToTrustLevels) {
                        $applies = $false
                    }
                }

                if ($applies) {
                    $effectivePolicies += $policy
                }
            }

            # Also include directly linked policies (by identifier)
            if ($agent.Policies) {
                foreach ($policyId in $agent.Policies) {
                    $alreadyIncluded = $effectivePolicies | Where-Object {
                        $_.Identifier -eq $policyId -or $_.DistinguishedName -eq $policyId
                    }

                    if (-not $alreadyIncluded) {
                        try {
                            $directPolicy = Get-ADAgentPolicy -Identity $policyId @commonParams
                            if ($directPolicy) {
                                $effectivePolicies += $directPolicy
                            }
                        }
                        catch {
                            Write-Warning "Linked policy not found: $policyId"
                        }
                    }
                }
            }

            # Return sorted by priority (ascending)
            $effectivePolicies | Sort-Object -Property Priority
        }
        catch {
            Write-Error "Failed to resolve effective policies for agent '$Identity': $_"
        }
    }
}
