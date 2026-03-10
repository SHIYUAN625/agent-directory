function Set-ADAgentPolicy {
    <#
    .SYNOPSIS
        Modifies a policy in the Agent Directory.

    .DESCRIPTION
        Updates properties of an existing msDS-AgentPolicy object.

    .PARAMETER Identity
        The identity of the policy to modify.

    .PARAMETER Type
        New policy type.

    .PARAMETER Priority
        New priority.

    .PARAMETER PolicyPath
        New policy path.

    .PARAMETER AppliesToTypes
        New applies-to types (replaces existing).

    .PARAMETER AddAppliesToTypes
        Types to add to the applies-to list.

    .PARAMETER RemoveAppliesToTypes
        Types to remove from the applies-to list.

    .PARAMETER AppliesToTrustLevels
        New applies-to trust levels (replaces existing).

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
        Return the modified policy object.

    .EXAMPLE
        Set-ADAgentPolicy -Identity "base-security" -Priority 5

    .OUTPUTS
        AgentDirectory.Policy (if PassThru is specified)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Identifier', 'Name', 'DistinguishedName', 'DN')]
        [string]$Identity,

        [Parameter()]
        [ValidateSet('security', 'behavior', 'resource', 'network')]
        [string]$Type,

        [Parameter()]
        [ValidateRange(0, 999)]
        [int]$Priority,

        [Parameter()]
        [string]$PolicyPath,

        [Parameter()]
        [string[]]$AppliesToTypes,

        [Parameter()]
        [string[]]$AddAppliesToTypes,

        [Parameter()]
        [string[]]$RemoveAppliesToTypes,

        [Parameter()]
        [int[]]$AppliesToTrustLevels,

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
            $dn = Get-PolicyDistinguishedName -Identity $Identity

            $currentPolicy = $null
            if ($AddAppliesToTypes -or $RemoveAppliesToTypes) {
                $currentPolicy = Get-ADAgentPolicy -Identity $dn @commonParams
            }

            $replace = @{}
            $clear = @()

            if ($Type) {
                $replace['msDS-PolicyType'] = $Type
            }

            if ($PSBoundParameters.ContainsKey('Priority')) {
                $replace['msDS-PolicyPriority'] = $Priority
            }

            if ($PSBoundParameters.ContainsKey('PolicyPath')) {
                if ($PolicyPath) {
                    $replace['msDS-PolicyPath'] = $PolicyPath
                }
                else {
                    $clear += 'msDS-PolicyPath'
                }
            }

            if ($PSBoundParameters.ContainsKey('Enabled')) {
                $replace['msDS-PolicyEnabled'] = $Enabled
            }

            if ($PSBoundParameters.ContainsKey('Version')) {
                if ($Version) {
                    $replace['msDS-PolicyVersion'] = $Version
                }
                else {
                    $clear += 'msDS-PolicyVersion'
                }
            }

            if ($PSBoundParameters.ContainsKey('AppliesToTrustLevels')) {
                if ($AppliesToTrustLevels) {
                    $replace['msDS-PolicyAppliesToTrustLevels'] = $AppliesToTrustLevels
                }
                else {
                    $clear += 'msDS-PolicyAppliesToTrustLevels'
                }
            }

            # Handle AppliesToTypes
            if ($AppliesToTypes) {
                $replace['msDS-PolicyAppliesToTypes'] = $AppliesToTypes
            }
            elseif ($AddAppliesToTypes -or $RemoveAppliesToTypes) {
                $types = @($currentPolicy.AppliesToTypes)

                if ($AddAppliesToTypes) {
                    $types = @($types) + @($AddAppliesToTypes) | Select-Object -Unique
                }

                if ($RemoveAppliesToTypes) {
                    $types = $types | Where-Object { $_ -notin $RemoveAppliesToTypes }
                }

                if ($types.Count -gt 0) {
                    $replace['msDS-PolicyAppliesToTypes'] = $types
                }
                else {
                    $clear += 'msDS-PolicyAppliesToTypes'
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
                if ($PSCmdlet.ShouldProcess($Identity, "Modify policy properties")) {
                    Set-ADObject @setParams
                    Write-Verbose "Policy '$Identity' updated successfully"
                }
            }

            if ($PassThru) {
                Get-ADAgentPolicy -Identity $dn @commonParams
            }
        }
        catch {
            Write-Error "Failed to modify policy '$Identity': $_"
        }
    }
}
