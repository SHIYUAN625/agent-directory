function Set-ADAgentInstructionGPO {
    <#
    .SYNOPSIS
        Modifies an instruction GPO in the Agent Directory.

    .DESCRIPTION
        Updates properties of an existing msDS-AgentInstructionGPO object.

    .PARAMETER Identity
        The identity of the instruction GPO to modify.

    .PARAMETER DisplayName
        New display name.

    .PARAMETER InstructionPath
        New instruction path.

    .PARAMETER Priority
        New priority.

    .PARAMETER MergeStrategy
        New merge strategy.

    .PARAMETER AppliesToTypes
        New applies-to types (replaces existing).

    .PARAMETER AddAppliesToTypes
        Types to add.

    .PARAMETER RemoveAppliesToTypes
        Types to remove.

    .PARAMETER AppliesToTrustLevels
        New applies-to trust levels (replaces existing).

    .PARAMETER AppliesToGroups
        New applies-to groups (replaces existing).

    .PARAMETER Enabled
        New enabled state.

    .PARAMETER Version
        New version string.

    .PARAMETER Description
        New description.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .PARAMETER PassThru
        Return the modified instruction GPO object.

    .EXAMPLE
        Set-ADAgentInstructionGPO -Identity "base-agent-instructions" -Priority 5

    .OUTPUTS
        AgentDirectory.InstructionGPO (if PassThru is specified)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DisplayName', 'DistinguishedName', 'DN')]
        [string]$Identity,

        [Parameter()]
        [string]$GPODisplayName,

        [Parameter()]
        [string]$InstructionPath,

        [Parameter()]
        [ValidateRange(0, 999)]
        [int]$Priority,

        [Parameter()]
        [ValidateSet('prepend', 'append', 'replace')]
        [string]$MergeStrategy,

        [Parameter()]
        [string[]]$AppliesToTypes,

        [Parameter()]
        [string[]]$AddAppliesToTypes,

        [Parameter()]
        [string[]]$RemoveAppliesToTypes,

        [Parameter()]
        [int[]]$AppliesToTrustLevels,

        [Parameter()]
        [string[]]$AppliesToGroups,

        [Parameter()]
        [bool]$Enabled,

        [Parameter()]
        [string]$Version,

        [Parameter()]
        [string]$Description,

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
            $dn = Get-InstructionGPODistinguishedName -Identity $Identity

            $currentGPO = $null
            if ($AddAppliesToTypes -or $RemoveAppliesToTypes) {
                $currentGPO = Get-ADAgentInstructionGPO -Identity $dn @commonParams
            }

            $replace = @{}
            $clear = @()

            if ($GPODisplayName) {
                $replace['msDS-GPODisplayName'] = $GPODisplayName
            }

            if ($InstructionPath) {
                $replace['msDS-GPOInstructionPath'] = $InstructionPath
            }

            if ($PSBoundParameters.ContainsKey('Priority')) {
                $replace['msDS-GPOPriority'] = $Priority
            }

            if ($MergeStrategy) {
                $replace['msDS-GPOMergeStrategy'] = $MergeStrategy
            }

            if ($PSBoundParameters.ContainsKey('Enabled')) {
                $replace['msDS-GPOEnabled'] = $Enabled
            }

            if ($PSBoundParameters.ContainsKey('Version')) {
                if ($Version) {
                    $replace['msDS-GPOVersion'] = $Version
                }
                else {
                    $clear += 'msDS-GPOVersion'
                }
            }

            if ($PSBoundParameters.ContainsKey('AppliesToTrustLevels')) {
                if ($AppliesToTrustLevels) {
                    $replace['msDS-GPOAppliesToTrustLevels'] = $AppliesToTrustLevels
                }
                else {
                    $clear += 'msDS-GPOAppliesToTrustLevels'
                }
            }

            if ($PSBoundParameters.ContainsKey('AppliesToGroups')) {
                if ($AppliesToGroups) {
                    $replace['msDS-GPOAppliesToGroups'] = $AppliesToGroups
                }
                else {
                    $clear += 'msDS-GPOAppliesToGroups'
                }
            }

            # Handle AppliesToTypes
            if ($AppliesToTypes) {
                $replace['msDS-GPOAppliesToTypes'] = $AppliesToTypes
            }
            elseif ($AddAppliesToTypes -or $RemoveAppliesToTypes) {
                $types = @($currentGPO.AppliesToTypes)

                if ($AddAppliesToTypes) {
                    $types = @($types) + @($AddAppliesToTypes) | Select-Object -Unique
                }

                if ($RemoveAppliesToTypes) {
                    $types = $types | Where-Object { $_ -notin $RemoveAppliesToTypes }
                }

                if ($types.Count -gt 0) {
                    $replace['msDS-GPOAppliesToTypes'] = $types
                }
                else {
                    $clear += 'msDS-GPOAppliesToTypes'
                }
            }

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

            if ($replace.Count -gt 0 -or $clear.Count -gt 0 -or $Description) {
                if ($PSCmdlet.ShouldProcess($Identity, "Modify instruction GPO properties")) {
                    Set-ADObject @setParams
                    Write-Verbose "Instruction GPO '$Identity' updated successfully"
                }
            }

            if ($PassThru) {
                Get-ADAgentInstructionGPO -Identity $dn @commonParams
            }
        }
        catch {
            Write-Error "Failed to modify instruction GPO '$Identity': $_"
        }
    }
}
