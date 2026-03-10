function Remove-ADAgent {
    <#
    .SYNOPSIS
        Removes an AI agent account from Active Directory.

    .DESCRIPTION
        Deletes an msDS-Agent object from Active Directory.

    .PARAMETER Identity
        The identity of the agent to remove.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .PARAMETER Confirm
        Prompts for confirmation before deletion.

    .EXAMPLE
        Remove-ADAgent -Identity "claude-assistant-01"

    .EXAMPLE
        Get-ADAgent -Type "tool" -TrustLevel 0 | Remove-ADAgent -Confirm:$false

    .OUTPUTS
        None
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DistinguishedName', 'DN')]
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
            $dn = Get-AgentDistinguishedName -Identity $Identity

            if ($PSCmdlet.ShouldProcess($Identity, "Remove agent")) {
                Write-Verbose "Removing agent: $dn"

                Remove-ADObject -Identity $dn -Recursive @commonParams

                Write-Verbose "Agent '$Identity' removed successfully"
            }
        }
        catch {
            Write-Error "Failed to remove agent '$Identity': $_"
        }
    }
}
