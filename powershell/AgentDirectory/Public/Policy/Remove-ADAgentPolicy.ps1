function Remove-ADAgentPolicy {
    <#
    .SYNOPSIS
        Removes a policy from the Agent Directory.

    .DESCRIPTION
        Deletes an msDS-AgentPolicy object from Active Directory.

    .PARAMETER Identity
        The identity of the policy to remove.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .PARAMETER Confirm
        Prompts for confirmation before deletion.

    .EXAMPLE
        Remove-ADAgentPolicy -Identity "custom-security"

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
        $commonParams = @{}
        if ($Credential) { $commonParams['Credential'] = $Credential }
        if ($Server) { $commonParams['Server'] = $Server }
    }

    process {
        try {
            $dn = Get-PolicyDistinguishedName -Identity $Identity

            if ($PSCmdlet.ShouldProcess($Identity, "Remove policy")) {
                Write-Verbose "Removing policy: $dn"

                Remove-ADObject -Identity $dn @commonParams

                Write-Verbose "Policy '$Identity' removed successfully"
            }
        }
        catch {
            Write-Error "Failed to remove policy '$Identity': $_"
        }
    }
}
