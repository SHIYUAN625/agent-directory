function New-ADAgentTool {
    <#
    .SYNOPSIS
        Registers a new tool in the Agent Directory.

    .DESCRIPTION
        Creates a new msDS-AgentTool object that can be granted to agents.

    .PARAMETER Identifier
        The canonical tool identifier (e.g., "contoso.erp-client").

    .PARAMETER DisplayName
        Human-readable name for the tool.

    .PARAMETER Category
        Tool category: shell, office, management, development, network, security, filesystem, data.

    .PARAMETER Executable
        Path or identifier for the tool executable.

    .PARAMETER Version
        Minimum required version.

    .PARAMETER RiskLevel
        Risk classification (1-5).

    .PARAMETER RequiredTrustLevel
        Minimum agent trust level required (0-4).

    .PARAMETER Constraints
        Array of constraint strings (e.g., "Timeout=30", "ReadOnly=true").

    .PARAMETER AuditRequired
        Whether tool usage must be audited.

    .PARAMETER Description
        Description of the tool.

    .PARAMETER Path
        Container where the tool will be created.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .EXAMPLE
        New-ADAgentTool -Identifier "contoso.erp" -DisplayName "Contoso ERP Client" -Category "data" -RiskLevel 3 -RequiredTrustLevel 2

    .OUTPUTS
        AgentDirectory.Tool
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Identifier,

        [Parameter()]
        [string]$DisplayName,

        [Parameter()]
        [ValidateSet('shell', 'office', 'management', 'development', 'network', 'security', 'filesystem', 'data')]
        [string]$Category,

        [Parameter()]
        [string]$Executable,

        [Parameter()]
        [string]$Version,

        [Parameter()]
        [ValidateRange(1, 5)]
        [int]$RiskLevel = 3,

        [Parameter()]
        [ValidateRange(0, 4)]
        [int]$RequiredTrustLevel = 1,

        [Parameter()]
        [string[]]$Constraints,

        [Parameter()]
        [bool]$AuditRequired = $false,

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
        # Build common parameters
        $commonParams = @{}
        if ($Credential) { $commonParams['Credential'] = $Credential }
        if ($Server) { $commonParams['Server'] = $Server }
    }

    process {
        try {
            # Determine path
            if (-not $Path) {
                $Path = $Script:ToolContainerDN
            }

            # Use identifier as CN
            $cn = $Identifier

            # Build attributes
            $otherAttributes = @{
                'objectClass' = 'msDS-AgentTool'
                'msDS-ToolIdentifier' = $Identifier
                'msDS-ToolRiskLevel' = $RiskLevel
                'msDS-ToolRequiredTrustLevel' = $RequiredTrustLevel
                'msDS-ToolAuditRequired' = $AuditRequired
            }

            if ($DisplayName) {
                $otherAttributes['msDS-ToolDisplayName'] = $DisplayName
            }

            if ($Category) {
                $otherAttributes['msDS-ToolCategory'] = $Category
            }

            if ($Executable) {
                $otherAttributes['msDS-ToolExecutable'] = $Executable
            }

            if ($Version) {
                $otherAttributes['msDS-ToolVersion'] = $Version
            }

            if ($Constraints) {
                $otherAttributes['msDS-ToolConstraints'] = $Constraints
            }

            if ($PSCmdlet.ShouldProcess($Identifier, "Create tool")) {
                Write-Verbose "Creating tool '$Identifier' in '$Path'"

                $newParams = @{
                    Name = $cn
                    Type = 'msDS-AgentTool'
                    Path = $Path
                    Description = $Description
                    OtherAttributes = $otherAttributes
                    PassThru = $true
                } + $commonParams

                $tool = New-ADObject @newParams

                # Retrieve with all properties
                $createdTool = Get-ADAgentTool -Identity $tool.DistinguishedName @commonParams

                Write-Verbose "Tool '$Identifier' created successfully"

                return $createdTool
            }
        }
        catch {
            throw "Failed to create tool '$Identifier': $_"
        }
    }
}
