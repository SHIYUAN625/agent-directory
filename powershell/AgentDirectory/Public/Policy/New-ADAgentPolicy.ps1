function New-ADAgentPolicy {
    <#
    .SYNOPSIS
        Creates a new policy in the Agent Directory.

    .DESCRIPTION
        Creates a new msDS-AgentPolicy object that controls agent behavior.

    .PARAMETER Identifier
        The unique policy identifier (e.g., "base-security", "type-worker").

    .PARAMETER Type
        Policy type: security, behavior, resource, network.

    .PARAMETER Priority
        Policy priority (0-999). Higher priority wins on conflict.

    .PARAMETER PolicyPath
        Path to JSON policy content in SYSVOL.

    .PARAMETER AppliesToTypes
        Agent types this policy applies to (empty = all).

    .PARAMETER AppliesToTrustLevels
        Trust levels this policy applies to (empty = all).

    .PARAMETER Enabled
        Whether the policy is active. Defaults to TRUE.

    .PARAMETER Version
        Version string for the policy content.

    .PARAMETER Description
        Description of the policy.

    .PARAMETER Path
        Container where the policy will be created.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .EXAMPLE
        New-ADAgentPolicy -Identifier "custom-security" -Type "security" -Priority 200

    .OUTPUTS
        AgentDirectory.Policy
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Identifier,

        [Parameter(Mandatory)]
        [ValidateSet('security', 'behavior', 'resource', 'network')]
        [string]$Type,

        [Parameter(Mandatory)]
        [ValidateRange(0, 999)]
        [int]$Priority,

        [Parameter()]
        [string]$PolicyPath,

        [Parameter()]
        [string[]]$AppliesToTypes,

        [Parameter()]
        [int[]]$AppliesToTrustLevels,

        [Parameter()]
        [bool]$Enabled = $true,

        [Parameter()]
        [string]$Version,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string]$Path,

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
            if (-not $Path) {
                $Path = $Script:PolicyContainerDN
            }

            $cn = $Identifier

            $otherAttributes = @{
                'objectClass' = 'msDS-AgentPolicy'
                'msDS-PolicyIdentifier' = $Identifier
                'msDS-PolicyType' = $Type
                'msDS-PolicyPriority' = $Priority
                'msDS-PolicyEnabled' = $Enabled
            }

            if ($PolicyPath) {
                $otherAttributes['msDS-PolicyPath'] = $PolicyPath
            }

            if ($AppliesToTypes) {
                $otherAttributes['msDS-PolicyAppliesToTypes'] = $AppliesToTypes
            }

            if ($AppliesToTrustLevels) {
                $otherAttributes['msDS-PolicyAppliesToTrustLevels'] = $AppliesToTrustLevels
            }

            if ($Version) {
                $otherAttributes['msDS-PolicyVersion'] = $Version
            }

            if ($PSCmdlet.ShouldProcess($Identifier, "Create policy")) {
                Write-Verbose "Creating policy '$Identifier' in '$Path'"

                $newParams = @{
                    Name = $cn
                    Type = 'msDS-AgentPolicy'
                    Path = $Path
                    Description = $Description
                    OtherAttributes = $otherAttributes
                    PassThru = $true
                } + $commonParams

                $policy = New-ADObject @newParams

                $createdPolicy = Get-ADAgentPolicy -Identity $policy.DistinguishedName @commonParams

                Write-Verbose "Policy '$Identifier' created successfully"

                return $createdPolicy
            }
        }
        catch {
            throw "Failed to create policy '$Identifier': $_"
        }
    }
}
