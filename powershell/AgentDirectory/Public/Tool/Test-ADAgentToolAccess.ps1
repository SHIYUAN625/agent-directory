function Test-ADAgentToolAccess {
    <#
    .SYNOPSIS
        Tests whether an agent can use a specific tool.

    .DESCRIPTION
        Checks the agent's tool authorization against the authorization model:
        1. Check denied list (explicit deny)
        2. Check authorized list (direct grant)
        3. Check group membership (group-based grant)
        4. Check trust level (implicit access)

    .PARAMETER Identity
        The identity of the agent.

    .PARAMETER Tool
        The tool identifier to check.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .EXAMPLE
        Test-ADAgentToolAccess -Identity "claude-assistant-01" -Tool "microsoft.powershell"

    .EXAMPLE
        Get-ADAgent | Test-ADAgentToolAccess -Tool "microsoft.word"

    .OUTPUTS
        PSCustomObject with access decision details
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DistinguishedName', 'DN')]
        [string]$Identity,

        [Parameter(Mandatory)]
        [string]$Tool,

        [Parameter()]
        [pscredential]$Credential,

        [Parameter()]
        [string]$Server
    )

    begin {
        # Build common parameters
        $commonParams = @{}
        if ($Credential) { $commonParams['Credential'] = $Credential }
        if ($Server) { $commonParams['Server'] = $Server }
    }

    process {
        try {
            # Resolve agent and tool
            $agentDn = Get-AgentDistinguishedName -Identity $Identity
            $agent = Get-ADAgent -Identity $agentDn @commonParams

            $toolDn = Get-ToolDistinguishedName -Identity $Tool
            $toolObj = Get-ADAgentTool -Identity $toolDn @commonParams

            # Create result object
            $result = [PSCustomObject]@{
                Agent = $agent.Name
                Tool = $toolObj.Identifier
                Allowed = $false
                Reason = ''
                AgentTrustLevel = $agent.TrustLevel
                ToolRequiredTrustLevel = $toolObj.RequiredTrustLevel
                Constraints = $toolObj.Constraints
            }

            # Check 1: Explicit deny
            $deniedTools = @($agent.DeniedTools)
            if ($toolDn -in $deniedTools) {
                $result.Reason = 'ExplicitDeny'
                return $result
            }

            # Check 2: Direct authorization
            $authorizedTools = @($agent.AuthorizedTools)
            if ($toolDn -in $authorizedTools) {
                $result.Allowed = $true
                $result.Reason = 'DirectGrant'
                return $result
            }

            # Check 3: Group-based authorization
            # Look for AG-Tools-* groups that contain both the agent and reference the tool
            try {
                $agentGroups = Get-ADPrincipalGroupMembership -Identity $agentDn @commonParams |
                               Where-Object { $_.Name -like 'AG-Tools-*' }

                # This is a simplified check - in production you'd have a more sophisticated
                # group-to-tool mapping system
                foreach ($group in $agentGroups) {
                    # Check if group name implies tool access
                    $toolId = $toolObj.Identifier
                    $toolCategory = $toolObj.Category

                    if ($group.Name -like "*$toolId*" -or
                        $group.Name -like "*$toolCategory*" -or
                        $group.Name -eq 'AG-Tools-All') {
                        $result.Allowed = $true
                        $result.Reason = "GroupGrant:$($group.Name)"
                        return $result
                    }
                }
            }
            catch {
                Write-Verbose "Could not check group memberships: $_"
            }

            # Check 4: Trust level comparison
            if ($agent.TrustLevel -ge $toolObj.RequiredTrustLevel) {
                $result.Allowed = $true
                $result.Reason = 'TrustLevelSufficient'
                return $result
            }

            # Default: not allowed
            $result.Reason = 'TrustLevelInsufficient'
            return $result
        }
        catch {
            Write-Error "Failed to test tool access: $_"
        }
    }
}
