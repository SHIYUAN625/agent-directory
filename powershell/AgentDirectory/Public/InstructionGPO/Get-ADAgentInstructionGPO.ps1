function Get-ADAgentInstructionGPO {
    <#
    .SYNOPSIS
        Retrieves instruction GPOs from the Agent Directory.

    .DESCRIPTION
        Gets one or more msDS-AgentInstructionGPO objects from Active Directory.

    .PARAMETER Identity
        The identity of the instruction GPO (name, display name, CN, or DN).

    .PARAMETER Filter
        An LDAP filter to find instruction GPOs.

    .PARAMETER MergeStrategy
        Filter by merge strategy.

    .PARAMETER SearchBase
        The distinguished name of the search base.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .EXAMPLE
        Get-ADAgentInstructionGPO -Identity "base-agent-instructions"

    .EXAMPLE
        Get-ADAgentInstructionGPO -MergeStrategy "replace"

    .OUTPUTS
        AgentDirectory.InstructionGPO
    #>
    [CmdletBinding(DefaultParameterSetName = 'Identity')]
    param(
        [Parameter(ParameterSetName = 'Identity', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DisplayName', 'DistinguishedName', 'DN')]
        [string]$Identity,

        [Parameter(ParameterSetName = 'Filter')]
        [string]$Filter,

        [Parameter()]
        [ValidateSet('prepend', 'append', 'replace')]
        [string]$MergeStrategy,

        [Parameter()]
        [string]$SearchBase,

        [Parameter()]
        [pscredential]$Credential,

        [Parameter()]
        [string]$Server
    )

    begin {
        $commonParams = @{}
        if ($Credential) { $commonParams['Credential'] = $Credential }
        if ($Server) { $commonParams['Server'] = $Server }

        $properties = @(
            'cn',
            'distinguishedName',
            'msDS-GPODisplayName',
            'msDS-GPOInstructionPath',
            'msDS-GPOPriority',
            'msDS-GPOMergeStrategy',
            'msDS-GPOAppliesToTypes',
            'msDS-GPOAppliesToTrustLevels',
            'msDS-GPOAppliesToGroups',
            'msDS-GPOEnabled',
            'msDS-GPOVersion',
            'description',
            'whenCreated',
            'whenChanged'
        )
    }

    process {
        try {
            $ldapFilter = "(objectClass=msDS-AgentInstructionGPO)"

            if ($Identity) {
                try {
                    $dn = Get-InstructionGPODistinguishedName -Identity $Identity
                    $ldapFilter = "(&(objectClass=msDS-AgentInstructionGPO)(distinguishedName=$dn))"
                }
                catch {
                    $ldapFilter = "(&(objectClass=msDS-AgentInstructionGPO)(|(cn=$Identity)(msDS-GPODisplayName=$Identity)))"
                }
            }
            elseif ($Filter) {
                $ldapFilter = "(&(objectClass=msDS-AgentInstructionGPO)($Filter))"
            }
            else {
                $filterParts = @("(objectClass=msDS-AgentInstructionGPO)")

                if ($MergeStrategy) {
                    $filterParts += "(msDS-GPOMergeStrategy=$MergeStrategy)"
                }

                $ldapFilter = "(&$($filterParts -join ''))"
            }

            Write-Verbose "LDAP filter: $ldapFilter"

            if (-not $SearchBase) {
                $SearchBase = $Script:InstructionGPOContainerDN

                if (-not (Test-Path "AD:$SearchBase" -ErrorAction SilentlyContinue)) {
                    $SearchBase = $Script:DomainDN
                }
            }

            $searchParams = @{
                LDAPFilter = $ldapFilter
                SearchBase = $SearchBase
                SearchScope = 'Subtree'
                Properties = $properties
            } + $commonParams

            $results = Get-ADObject @searchParams

            foreach ($result in $results) {
                ConvertTo-InstructionGPOObject -ADObject $result
            }
        }
        catch {
            Write-Error "Failed to retrieve instruction GPO(s): $_"
        }
    }
}
