function Get-ADAgentTool {
    <#
    .SYNOPSIS
        Retrieves tools from the Agent Directory.

    .DESCRIPTION
        Gets one or more msDS-AgentTool objects from Active Directory.

    .PARAMETER Identity
        The identity of the tool (identifier, CN, or DN).

    .PARAMETER Filter
        An LDAP filter to find tools.

    .PARAMETER Category
        Filter by tool category.

    .PARAMETER RiskLevel
        Filter by risk level.

    .PARAMETER RequiredTrustLevel
        Filter by required trust level.

    .PARAMETER SearchBase
        The distinguished name of the search base.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .EXAMPLE
        Get-ADAgentTool -Identity "microsoft.powershell"

    .EXAMPLE
        Get-ADAgentTool -Category "shell"

    .EXAMPLE
        Get-ADAgentTool -RiskLevel 5

    .OUTPUTS
        AgentDirectory.Tool
    #>
    [CmdletBinding(DefaultParameterSetName = 'Identity')]
    param(
        [Parameter(ParameterSetName = 'Identity', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Identifier', 'Name', 'DistinguishedName', 'DN')]
        [string]$Identity,

        [Parameter(ParameterSetName = 'Filter')]
        [string]$Filter,

        [Parameter()]
        [ValidateSet('shell', 'office', 'management', 'development', 'network', 'security', 'filesystem', 'data')]
        [string]$Category,

        [Parameter()]
        [ValidateRange(1, 5)]
        [int]$RiskLevel,

        [Parameter()]
        [ValidateRange(0, 4)]
        [int]$RequiredTrustLevel,

        [Parameter()]
        [string]$SearchBase,

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
            'msDS-ToolIdentifier',
            'msDS-ToolDisplayName',
            'msDS-ToolCategory',
            'msDS-ToolExecutable',
            'msDS-ToolVersion',
            'msDS-ToolRiskLevel',
            'msDS-ToolRequiredTrustLevel',
            'msDS-ToolConstraints',
            'msDS-ToolAuditRequired',
            'description',
            'whenCreated',
            'whenChanged'
        )
    }

    process {
        try {
            # Build filter
            $ldapFilter = "(objectClass=msDS-AgentTool)"

            if ($Identity) {
                # Try to resolve
                try {
                    $dn = Get-ToolDistinguishedName -Identity $Identity
                    $ldapFilter = "(&(objectClass=msDS-AgentTool)(distinguishedName=$dn))"
                }
                catch {
                    # Search by identifier or name
                    $ldapFilter = "(&(objectClass=msDS-AgentTool)(|(msDS-ToolIdentifier=$Identity)(cn=$Identity)))"
                }
            }
            elseif ($Filter) {
                $ldapFilter = "(&(objectClass=msDS-AgentTool)($Filter))"
            }
            else {
                # Build filter from parameters
                $filterParts = @("(objectClass=msDS-AgentTool)")

                if ($Category) {
                    $filterParts += "(msDS-ToolCategory=$Category)"
                }

                if ($PSBoundParameters.ContainsKey('RiskLevel')) {
                    $filterParts += "(msDS-ToolRiskLevel=$RiskLevel)"
                }

                if ($PSBoundParameters.ContainsKey('RequiredTrustLevel')) {
                    $filterParts += "(msDS-ToolRequiredTrustLevel=$RequiredTrustLevel)"
                }

                $ldapFilter = "(&$($filterParts -join ''))"
            }

            Write-Verbose "LDAP filter: $ldapFilter"

            # Set search base
            if (-not $SearchBase) {
                $SearchBase = $Script:ToolContainerDN

                # If container doesn't exist, search domain-wide
                if (-not (Test-Path "AD:$SearchBase" -ErrorAction SilentlyContinue)) {
                    $SearchBase = $Script:DomainDN
                }
            }

            # Execute search
            $searchParams = @{
                LDAPFilter = $ldapFilter
                SearchBase = $SearchBase
                SearchScope = 'Subtree'
                Properties = $properties
            } + $commonParams

            $results = Get-ADObject @searchParams

            # Convert to tool objects
            foreach ($result in $results) {
                ConvertTo-ToolObject -ADObject $result
            }
        }
        catch {
            Write-Error "Failed to retrieve tool(s): $_"
        }
    }
}
