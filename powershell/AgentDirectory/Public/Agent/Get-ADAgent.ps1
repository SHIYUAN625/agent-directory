function Get-ADAgent {
    <#
    .SYNOPSIS
        Retrieves AI agent accounts from Active Directory.

    .DESCRIPTION
        Gets one or more msDS-Agent objects from Active Directory based on
        identity, filter, or search criteria.

    .PARAMETER Identity
        The identity of the agent to retrieve. Can be name, distinguished name,
        SID, or sAMAccountName.

    .PARAMETER Filter
        An LDAP filter to find agents.

    .PARAMETER SearchBase
        The distinguished name of the search base.

    .PARAMETER SearchScope
        The scope of the search: Base, OneLevel, or Subtree.

    .PARAMETER Type
        Filter by agent type.

    .PARAMETER TrustLevel
        Filter by trust level.

    .PARAMETER Owner
        Filter by owner DN.

    .PARAMETER Enabled
        Filter by enabled status.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .EXAMPLE
        Get-ADAgent -Identity "claude-assistant-01"

    .EXAMPLE
        Get-ADAgent -Type "assistant" -TrustLevel 2

    .EXAMPLE
        Get-ADAgent -Filter "msDS-AgentModel -eq 'claude-opus-4-5'"

    .OUTPUTS
        AgentDirectory.Agent
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
        [ValidateSet('autonomous', 'assistant', 'tool', 'orchestrator')]
        [string]$Type,

        [Parameter()]
        [ValidateRange(0, 4)]
        [int]$TrustLevel,

        [Parameter()]
        [string]$Owner,

        [Parameter()]
        [bool]$Enabled,

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

        # Properties to retrieve
        $properties = @(
            'cn',
            'distinguishedName',
            'sAMAccountName',
            'objectSid',
            'userAccountControl',
            'msDS-AgentType',
            'msDS-AgentCapabilities',
            'msDS-AgentOwner',
            'msDS-AgentParent',
            'msDS-AgentTrustLevel',
            'msDS-AgentSandbox',
            'msDS-AgentModel',
            'msDS-AgentPolicies',
            'msDS-AgentDelegationScope',
            'msDS-AgentAuditLevel',
            'msDS-AgentAuthorizedTools',
            'msDS-AgentDeniedTools',
            'servicePrincipalName',
            'description',
            'whenCreated',
            'whenChanged'
        )
    }

    process {
        try {
            # Build filter
            $ldapFilter = "(objectClass=msDS-Agent)"

            if ($Identity) {
                # Try to resolve to DN
                $dn = Get-AgentDistinguishedName -Identity $Identity
                $ldapFilter = "(&(objectClass=msDS-Agent)(distinguishedName=$dn))"
            }
            elseif ($Filter) {
                $ldapFilter = "(&(objectClass=msDS-Agent)($Filter))"
            }
            else {
                # Build filter from parameters
                $filterParts = @("(objectClass=msDS-Agent)")

                if ($Type) {
                    $filterParts += "(msDS-AgentType=$Type)"
                }

                if ($PSBoundParameters.ContainsKey('TrustLevel')) {
                    $filterParts += "(msDS-AgentTrustLevel=$TrustLevel)"
                }

                if ($Owner) {
                    $filterParts += "(msDS-AgentOwner=$Owner)"
                }

                if ($PSBoundParameters.ContainsKey('Enabled')) {
                    if ($Enabled) {
                        $filterParts += "(!(userAccountControl:1.2.840.113556.1.4.803:=2))"
                    }
                    else {
                        $filterParts += "(userAccountControl:1.2.840.113556.1.4.803:=2)"
                    }
                }

                $ldapFilter = "(&$($filterParts -join ''))"
            }

            Write-Verbose "LDAP filter: $ldapFilter"

            # Set search base
            if (-not $SearchBase) {
                $SearchBase = $Script:DomainDN
            }

            # Execute search
            $searchParams = @{
                LDAPFilter = $ldapFilter
                SearchBase = $SearchBase
                SearchScope = $SearchScope
                Properties = $properties
            } + $commonParams

            $results = Get-ADObject @searchParams

            # Convert to agent objects
            foreach ($result in $results) {
                ConvertTo-AgentObject -ADObject $result
            }
        }
        catch {
            Write-Error "Failed to retrieve agent(s): $_"
        }
    }
}
