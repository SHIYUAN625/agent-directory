function Set-ADAgentTool {
    <#
    .SYNOPSIS
        Modifies a tool in the Agent Directory.

    .DESCRIPTION
        Updates properties of an existing msDS-AgentTool object.

    .PARAMETER Identity
        The identity of the tool to modify.

    .PARAMETER DisplayName
        New display name.

    .PARAMETER Category
        New category.

    .PARAMETER Executable
        New executable path.

    .PARAMETER Version
        New version requirement.

    .PARAMETER RiskLevel
        New risk level.

    .PARAMETER RequiredTrustLevel
        New required trust level.

    .PARAMETER Constraints
        New constraints (replaces existing).

    .PARAMETER AddConstraints
        Constraints to add.

    .PARAMETER RemoveConstraints
        Constraints to remove.

    .PARAMETER AuditRequired
        New audit requirement.

    .PARAMETER Description
        New description.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .PARAMETER PassThru
        Return the modified tool object.

    .EXAMPLE
        Set-ADAgentTool -Identity "microsoft.powershell" -RiskLevel 5

    .EXAMPLE
        Set-ADAgentTool -Identity "contoso.erp" -AddConstraints "MaxConnections=10"

    .OUTPUTS
        AgentDirectory.Tool (if PassThru is specified)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Identifier', 'Name', 'DistinguishedName', 'DN')]
        [string]$Identity,

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
        [int]$RiskLevel,

        [Parameter()]
        [ValidateRange(0, 4)]
        [int]$RequiredTrustLevel,

        [Parameter()]
        [string[]]$Constraints,

        [Parameter()]
        [string[]]$AddConstraints,

        [Parameter()]
        [string[]]$RemoveConstraints,

        [Parameter()]
        [bool]$AuditRequired,

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
        # Build common parameters
        $commonParams = @{}
        if ($Credential) { $commonParams['Credential'] = $Credential }
        if ($Server) { $commonParams['Server'] = $Server }
    }

    process {
        try {
            # Resolve identity
            $dn = Get-ToolDistinguishedName -Identity $Identity

            # Get current tool for constraint modifications
            $currentTool = $null
            if ($AddConstraints -or $RemoveConstraints) {
                $currentTool = Get-ADAgentTool -Identity $dn @commonParams
            }

            # Build replace hashtable
            $replace = @{}
            $clear = @()

            if ($DisplayName) {
                $replace['msDS-ToolDisplayName'] = $DisplayName
            }

            if ($Category) {
                $replace['msDS-ToolCategory'] = $Category
            }

            if ($PSBoundParameters.ContainsKey('Executable')) {
                if ($Executable) {
                    $replace['msDS-ToolExecutable'] = $Executable
                }
                else {
                    $clear += 'msDS-ToolExecutable'
                }
            }

            if ($PSBoundParameters.ContainsKey('Version')) {
                if ($Version) {
                    $replace['msDS-ToolVersion'] = $Version
                }
                else {
                    $clear += 'msDS-ToolVersion'
                }
            }

            if ($PSBoundParameters.ContainsKey('RiskLevel')) {
                $replace['msDS-ToolRiskLevel'] = $RiskLevel
            }

            if ($PSBoundParameters.ContainsKey('RequiredTrustLevel')) {
                $replace['msDS-ToolRequiredTrustLevel'] = $RequiredTrustLevel
            }

            if ($PSBoundParameters.ContainsKey('AuditRequired')) {
                $replace['msDS-ToolAuditRequired'] = $AuditRequired
            }

            # Handle constraints
            if ($Constraints) {
                $replace['msDS-ToolConstraints'] = $Constraints
            }
            elseif ($AddConstraints -or $RemoveConstraints) {
                $cons = @($currentTool.Constraints)

                if ($AddConstraints) {
                    $cons = @($cons) + @($AddConstraints) | Select-Object -Unique
                }

                if ($RemoveConstraints) {
                    $cons = $cons | Where-Object { $_ -notin $RemoveConstraints }
                }

                if ($cons.Count -gt 0) {
                    $replace['msDS-ToolConstraints'] = $cons
                }
                else {
                    $clear += 'msDS-ToolConstraints'
                }
            }

            # Build Set-ADObject parameters
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

            # Apply changes
            if ($replace.Count -gt 0 -or $clear.Count -gt 0 -or $Description) {
                if ($PSCmdlet.ShouldProcess($Identity, "Modify tool properties")) {
                    Set-ADObject @setParams
                    Write-Verbose "Tool '$Identity' updated successfully"
                }
            }

            if ($PassThru) {
                Get-ADAgentTool -Identity $dn @commonParams
            }
        }
        catch {
            Write-Error "Failed to modify tool '$Identity': $_"
        }
    }
}
