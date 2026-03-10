function Get-ADAgentPolicy {
    <#
    .SYNOPSIS
        Retrieves policies from the Agent Directory.

    .DESCRIPTION
        Gets one or more msDS-AgentPolicy objects from Active Directory.

    .PARAMETER Identity
        The identity of the policy (identifier, CN, or DN).

    .PARAMETER Filter
        An LDAP filter to find policies.

    .PARAMETER Type
        Filter by policy type.

    .PARAMETER Priority
        Filter by priority.

    .PARAMETER SearchBase
        The distinguished name of the search base.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .EXAMPLE
        Get-ADAgentPolicy -Identity "base-security"

    .EXAMPLE
        Get-ADAgentPolicy -Type "security"

    .OUTPUTS
        AgentDirectory.Policy
    #>
    [CmdletBinding(DefaultParameterSetName = 'Identity')]
    param(
        [Parameter(ParameterSetName = 'Identity', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Identifier', 'Name', 'DistinguishedName', 'DN')]
        [string]$Identity,

        [Parameter(ParameterSetName = 'Filter')]
        [string]$Filter,

        [Parameter()]
        [ValidateSet('security', 'behavior', 'resource', 'network')]
        [string]$Type,

        [Parameter()]
        [ValidateRange(0, 999)]
        [int]$Priority,

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
            'msDS-PolicyIdentifier',
            'msDS-PolicyType',
            'msDS-PolicyPriority',
            'msDS-PolicyPath',
            'msDS-PolicyAppliesToTypes',
            'msDS-PolicyAppliesToTrustLevels',
            'msDS-PolicyEnabled',
            'msDS-PolicyVersion',
            'description',
            'whenCreated',
            'whenChanged'
        )
    }

    process {
        try {
            $ldapFilter = "(objectClass=msDS-AgentPolicy)"

            if ($Identity) {
                try {
                    $dn = Get-PolicyDistinguishedName -Identity $Identity
                    $ldapFilter = "(&(objectClass=msDS-AgentPolicy)(distinguishedName=$dn))"
                }
                catch {
                    $ldapFilter = "(&(objectClass=msDS-AgentPolicy)(|(msDS-PolicyIdentifier=$Identity)(cn=$Identity)))"
                }
            }
            elseif ($Filter) {
                $ldapFilter = "(&(objectClass=msDS-AgentPolicy)($Filter))"
            }
            else {
                $filterParts = @("(objectClass=msDS-AgentPolicy)")

                if ($Type) {
                    $filterParts += "(msDS-PolicyType=$Type)"
                }

                if ($PSBoundParameters.ContainsKey('Priority')) {
                    $filterParts += "(msDS-PolicyPriority=$Priority)"
                }

                $ldapFilter = "(&$($filterParts -join ''))"
            }

            Write-Verbose "LDAP filter: $ldapFilter"

            if (-not $SearchBase) {
                $SearchBase = $Script:PolicyContainerDN

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
                ConvertTo-PolicyObject -ADObject $result
            }
        }
        catch {
            Write-Error "Failed to retrieve policy(s): $_"
        }
    }
}
