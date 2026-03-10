function Remove-ADAgentSandbox {
    <#
    .SYNOPSIS
        Removes an agent sandbox from Active Directory.

    .DESCRIPTION
        Deletes an msDS-AgentSandbox object and any child objects.

    .PARAMETER Identity
        The identity of the sandbox to remove.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .EXAMPLE
        Remove-ADAgentSandbox -Identity "sandbox-prod-001"

    .EXAMPLE
        Get-ADAgentSandbox -Status "terminated" | Remove-ADAgentSandbox
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
        $commonParams = @{}
        if ($Credential) { $commonParams['Credential'] = $Credential }
        if ($Server) { $commonParams['Server'] = $Server }
    }

    process {
        try {
            $dn = Get-SandboxDistinguishedName -Identity $Identity

            if ($PSCmdlet.ShouldProcess($Identity, "Remove sandbox")) {
                Remove-ADObject -Identity $dn -Recursive @commonParams
                Write-Verbose "Sandbox '$Identity' removed"
            }
        }
        catch {
            Write-Error "Failed to remove sandbox '$Identity': $_"
        }
    }
}
