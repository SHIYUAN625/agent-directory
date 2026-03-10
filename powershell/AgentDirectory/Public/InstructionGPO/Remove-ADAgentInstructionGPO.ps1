function Remove-ADAgentInstructionGPO {
    <#
    .SYNOPSIS
        Removes an instruction GPO from the Agent Directory.

    .DESCRIPTION
        Deletes an msDS-AgentInstructionGPO object from Active Directory.

    .PARAMETER Identity
        The identity of the instruction GPO to remove.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .PARAMETER Confirm
        Prompts for confirmation before deletion.

    .EXAMPLE
        Remove-ADAgentInstructionGPO -Identity "custom-instructions"

    .OUTPUTS
        None
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DisplayName', 'DistinguishedName', 'DN')]
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
            $dn = Get-InstructionGPODistinguishedName -Identity $Identity

            if ($PSCmdlet.ShouldProcess($Identity, "Remove instruction GPO")) {
                Write-Verbose "Removing instruction GPO: $dn"

                Remove-ADObject -Identity $dn @commonParams

                Write-Verbose "Instruction GPO '$Identity' removed successfully"
            }
        }
        catch {
            Write-Error "Failed to remove instruction GPO '$Identity': $_"
        }
    }
}
