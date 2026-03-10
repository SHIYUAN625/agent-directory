function Get-ADAgentSandbox {
    <#
    .SYNOPSIS
        Retrieves agent sandbox objects from Active Directory.

    .DESCRIPTION
        Gets one or more msDS-AgentSandbox objects from Active Directory based on
        identity, filter, or search criteria.

    .PARAMETER Identity
        The identity of the sandbox to retrieve.

    .PARAMETER Filter
        An LDAP filter to find sandboxes.

    .PARAMETER SearchBase
        The distinguished name of the search base.

    .PARAMETER SearchScope
        The scope of the search: Base, OneLevel, or Subtree.

    .PARAMETER Status
        Filter by sandbox status.

    .PARAMETER SecurityProfile
        Filter by security profile.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .EXAMPLE
        Get-ADAgentSandbox -Identity "sandbox-prod-001"

    .EXAMPLE
        Get-ADAgentSandbox -Status "active"

    .OUTPUTS
        AgentDirectory.Sandbox
    #>
    [CmdletBinding(DefaultParameterSetName = 'Identity')]
    param(
        [Parameter(ParameterSetName = 'Identity', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DistinguishedName', 'DN')]
        [string]$Identity,

        [Parameter(ParameterSetName = 'Filter')]
        [string]$Filter,

        [Parameter()]
        [string]$SearchBase,

        [Parameter()]
        [ValidateSet('Base', 'OneLevel', 'Subtree')]
        [string]$SearchScope = 'Subtree',

        [Parameter()]
        [ValidateSet('active', 'standby', 'terminated')]
        [string]$Status,

        [Parameter()]
        [ValidateSet('bwrap', 'appcontainer', 'hyperv', 'vmware', 'none')]
        [string]$SecurityProfile,

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
            'sAMAccountName',
            'objectSid',
            'userAccountControl',
            'msDS-SandboxEndpoint',
            'msDS-SandboxAgents',
            'msDS-SandboxResourcePolicy',
            'msDS-SandboxNetworkPolicy',
            'msDS-SandboxSecurityProfile',
            'msDS-SandboxStatus',
            'servicePrincipalName',
            'description',
            'whenCreated',
            'whenChanged'
        )
    }

    process {
        try {
            $ldapFilter = "(objectClass=msDS-AgentSandbox)"

            if ($Identity) {
                $dn = Get-SandboxDistinguishedName -Identity $Identity
                $ldapFilter = "(&(objectClass=msDS-AgentSandbox)(distinguishedName=$dn))"
            }
            elseif ($Filter) {
                $ldapFilter = "(&(objectClass=msDS-AgentSandbox)($Filter))"
            }
            else {
                $filterParts = @("(objectClass=msDS-AgentSandbox)")

                if ($Status) {
                    $filterParts += "(msDS-SandboxStatus=$Status)"
                }

                if ($SecurityProfile) {
                    $filterParts += "(msDS-SandboxSecurityProfile=$SecurityProfile)"
                }

                $ldapFilter = "(&$($filterParts -join ''))"
            }

            Write-Verbose "LDAP filter: $ldapFilter"

            if (-not $SearchBase) {
                $SearchBase = $Script:DomainDN
            }

            $searchParams = @{
                LDAPFilter = $ldapFilter
                SearchBase = $SearchBase
                SearchScope = $SearchScope
                Properties = $properties
            } + $commonParams

            $results = Get-ADObject @searchParams

            foreach ($result in $results) {
                ConvertTo-SandboxObject -ADObject $result
            }
        }
        catch {
            Write-Error "Failed to retrieve sandbox(es): $_"
        }
    }
}
