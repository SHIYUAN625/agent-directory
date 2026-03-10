function New-ADAgentInstructionGPO {
    <#
    .SYNOPSIS
        Creates a new instruction GPO in the Agent Directory.

    .DESCRIPTION
        Creates a new msDS-AgentInstructionGPO object that delivers system prompt instructions to agents.

    .PARAMETER Name
        The CN of the instruction GPO (e.g., "type-assistant-instructions").

    .PARAMETER InstructionPath
        SYSVOL-relative path to instruction content (markdown).

    .PARAMETER Priority
        Priority for instruction merge ordering (0-999).

    .PARAMETER DisplayName
        Human-readable display name.

    .PARAMETER MergeStrategy
        How instructions merge with lower-priority GPOs: prepend, append, replace.

    .PARAMETER AppliesToTypes
        Agent types this GPO applies to (empty = all).

    .PARAMETER AppliesToTrustLevels
        Trust levels this GPO applies to (empty = all).

    .PARAMETER AppliesToGroups
        AD group DNs this GPO applies to.

    .PARAMETER Enabled
        Whether the GPO is active. Defaults to TRUE.

    .PARAMETER Version
        Version string for instruction content.

    .PARAMETER Description
        Description of the instruction GPO.

    .PARAMETER Path
        Container where the GPO will be created.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .EXAMPLE
        New-ADAgentInstructionGPO -Name "custom-instructions" -InstructionPath "AgentInstructions/custom/instructions.md" -Priority 300

    .OUTPUTS
        AgentDirectory.InstructionGPO
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$InstructionPath,

        [Parameter(Mandatory)]
        [ValidateRange(0, 999)]
        [int]$Priority,

        [Parameter()]
        [string]$DisplayName,

        [Parameter()]
        [ValidateSet('prepend', 'append', 'replace')]
        [string]$MergeStrategy = 'append',

        [Parameter()]
        [string[]]$AppliesToTypes,

        [Parameter()]
        [int[]]$AppliesToTrustLevels,

        [Parameter()]
        [string[]]$AppliesToGroups,

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
                $Path = $Script:InstructionGPOContainerDN
            }

            $otherAttributes = @{
                'objectClass' = 'msDS-AgentInstructionGPO'
                'msDS-GPOInstructionPath' = $InstructionPath
                'msDS-GPOPriority' = $Priority
                'msDS-GPOMergeStrategy' = $MergeStrategy
                'msDS-GPOEnabled' = $Enabled
            }

            if ($DisplayName) {
                $otherAttributes['msDS-GPODisplayName'] = $DisplayName
            }

            if ($AppliesToTypes) {
                $otherAttributes['msDS-GPOAppliesToTypes'] = $AppliesToTypes
            }

            if ($AppliesToTrustLevels) {
                $otherAttributes['msDS-GPOAppliesToTrustLevels'] = $AppliesToTrustLevels
            }

            if ($AppliesToGroups) {
                $otherAttributes['msDS-GPOAppliesToGroups'] = $AppliesToGroups
            }

            if ($Version) {
                $otherAttributes['msDS-GPOVersion'] = $Version
            }

            if ($PSCmdlet.ShouldProcess($Name, "Create instruction GPO")) {
                Write-Verbose "Creating instruction GPO '$Name' in '$Path'"

                $newParams = @{
                    Name = $Name
                    Type = 'msDS-AgentInstructionGPO'
                    Path = $Path
                    Description = $Description
                    OtherAttributes = $otherAttributes
                    PassThru = $true
                } + $commonParams

                $gpo = New-ADObject @newParams

                $createdGPO = Get-ADAgentInstructionGPO -Identity $gpo.DistinguishedName @commonParams

                Write-Verbose "Instruction GPO '$Name' created successfully"

                return $createdGPO
            }
        }
        catch {
            throw "Failed to create instruction GPO '$Name': $_"
        }
    }
}
