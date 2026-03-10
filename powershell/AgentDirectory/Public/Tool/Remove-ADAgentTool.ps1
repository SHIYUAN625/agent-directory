function Remove-ADAgentTool {
    <#
    .SYNOPSIS
        Removes a tool from the Agent Directory.

    .DESCRIPTION
        Deletes an msDS-AgentTool object from Active Directory.

    .PARAMETER Identity
        The identity of the tool to remove.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .PARAMETER Confirm
        Prompts for confirmation before deletion.

    .EXAMPLE
        Remove-ADAgentTool -Identity "contoso.erp"

    .OUTPUTS
        None
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Identifier', 'Name', 'DistinguishedName', 'DN')]
        [string]$Identity,

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
            # Resolve identity
            $dn = Get-ToolDistinguishedName -Identity $Identity

            if ($PSCmdlet.ShouldProcess($Identity, "Remove tool")) {
                Write-Verbose "Removing tool: $dn"

                Remove-ADObject -Identity $dn @commonParams

                Write-Verbose "Tool '$Identity' removed successfully"
            }
        }
        catch {
            Write-Error "Failed to remove tool '$Identity': $_"
        }
    }
}
