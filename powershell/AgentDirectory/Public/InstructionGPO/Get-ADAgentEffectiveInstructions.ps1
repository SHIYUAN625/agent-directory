function Get-ADAgentEffectiveInstructions {
    <#
    .SYNOPSIS
        Resolves the effective instruction set for an agent.

    .DESCRIPTION
        Retrieves all instruction GPOs that apply to an agent based on direct links,
        agent type, trust level, and group membership. Returns them sorted by priority
        with merge strategy metadata.

    .PARAMETER Identity
        The identity of the agent.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .EXAMPLE
        Get-ADAgentEffectiveInstructions -Identity "claude-assistant-01"

    .OUTPUTS
        AgentDirectory.InstructionGPO[]
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

            # Get all instruction GPOs
            $allGPOs = Get-ADAgentInstructionGPO @commonParams

            # Get agent group memberships for group-scoped GPOs
            $agentGroups = @()
            try {
                $agentDn = Get-AgentDistinguishedName -Identity $Identity
                $groupMemberships = Get-ADPrincipalGroupMembership -Identity $agentDn @commonParams
                $agentGroups = $groupMemberships | ForEach-Object { $_.DistinguishedName }
            }
            catch {
                Write-Verbose "Could not retrieve group memberships: $_"
            }

            $effectiveGPOs = @()

            foreach ($gpo in $allGPOs) {
                # Skip disabled GPOs
                if ($gpo.Enabled -eq $false) {
                    continue
                }

                $applies = $true

                # Check type scope
                if ($gpo.AppliesToTypes -and $gpo.AppliesToTypes.Count -gt 0) {
                    if ($agent.Type -notin $gpo.AppliesToTypes) {
                        $applies = $false
                    }
                }

                # Check trust level scope
                if ($applies -and $gpo.AppliesToTrustLevels -and $gpo.AppliesToTrustLevels.Count -gt 0) {
                    if ($agent.TrustLevel -notin $gpo.AppliesToTrustLevels) {
                        $applies = $false
                    }
                }

                # Check group scope
                if ($applies -and $gpo.AppliesToGroups -and $gpo.AppliesToGroups.Count -gt 0) {
                    $groupMatch = $false
                    foreach ($groupDn in $gpo.AppliesToGroups) {
                        if ($groupDn -in $agentGroups) {
                            $groupMatch = $true
                            break
                        }
                    }
                    if (-not $groupMatch) {
                        $applies = $false
                    }
                }

                if ($applies) {
                    $effectiveGPOs += $gpo
                }
            }

            # Also include directly linked GPOs
            if ($agent.InstructionGPOs) {
                foreach ($gpoDn in $agent.InstructionGPOs) {
                    $alreadyIncluded = $effectiveGPOs | Where-Object {
                        $_.DistinguishedName -eq $gpoDn
                    }

                    if (-not $alreadyIncluded) {
                        try {
                            $directGPO = Get-ADAgentInstructionGPO -Identity $gpoDn @commonParams
                            if ($directGPO -and $directGPO.Enabled -ne $false) {
                                $effectiveGPOs += $directGPO
                            }
                        }
                        catch {
                            Write-Warning "Linked instruction GPO not found: $gpoDn"
                        }
                    }
                }
            }

            # Return sorted by priority (ascending - lowest first, highest last)
            $effectiveGPOs | Sort-Object -Property Priority
        }
        catch {
            Write-Error "Failed to resolve effective instructions for agent '$Identity': $_"
        }
    }
}
