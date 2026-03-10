function Set-ADAgentSandbox {
    <#
    .SYNOPSIS
        Modifies an agent sandbox in Active Directory.

    .DESCRIPTION
        Updates properties of an existing msDS-AgentSandbox object.

    .PARAMETER Identity
        The identity of the sandbox to modify.

    .PARAMETER Endpoint
        The new endpoint URI.

    .PARAMETER SecurityProfile
        The new security profile.

    .PARAMETER ResourcePolicy
        The new resource policy JSON.

    .PARAMETER NetworkPolicy
        The new network policy JSON.

    .PARAMETER Status
        The new sandbox status.

    .PARAMETER Description
        The new description.

    .PARAMETER Enabled
        Enable or disable the sandbox.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .PARAMETER PassThru
        Return the modified sandbox object.

    .EXAMPLE
        Set-ADAgentSandbox -Identity "sandbox-prod-001" -Status "active" -Enabled $true

    .OUTPUTS
        AgentDirectory.Sandbox (if PassThru is specified)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DistinguishedName', 'DN')]
        [string]$Identity,

        [Parameter()]
        [string]$Endpoint,

        [Parameter()]
        [ValidateSet('bwrap', 'appcontainer', 'hyperv', 'vmware', 'none')]
        [string]$SecurityProfile,

        [Parameter()]
        [string]$ResourcePolicy,

        [Parameter()]
        [string]$NetworkPolicy,

        [Parameter()]
        [ValidateSet('active', 'standby', 'terminated')]
        [string]$Status,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [bool]$Enabled,

        [Parameter()]
        [pscredential]$Credential,

        [Parameter()]
        [string]$Server,

        [Parameter()]
        [switch]$PassThru
    )

    begin {
        $commonParams = @{}
        if ($Credential) { $commonParams['Credential'] = $Credential }
        if ($Server) { $commonParams['Server'] = $Server }
    }

    process {
        try {
            $dn = Get-SandboxDistinguishedName -Identity $Identity

            $replace = @{}
            $clear = @()

            if ($PSBoundParameters.ContainsKey('Endpoint')) {
                if ($Endpoint) {
                    $replace['msDS-SandboxEndpoint'] = $Endpoint
                }
                else {
                    $clear += 'msDS-SandboxEndpoint'
                }
            }

            if ($SecurityProfile) {
                $replace['msDS-SandboxSecurityProfile'] = $SecurityProfile
            }

            if ($PSBoundParameters.ContainsKey('ResourcePolicy')) {
                if ($ResourcePolicy) {
                    $replace['msDS-SandboxResourcePolicy'] = $ResourcePolicy
                }
                else {
                    $clear += 'msDS-SandboxResourcePolicy'
                }
            }

            if ($PSBoundParameters.ContainsKey('NetworkPolicy')) {
                if ($NetworkPolicy) {
                    $replace['msDS-SandboxNetworkPolicy'] = $NetworkPolicy
                }
                else {
                    $clear += 'msDS-SandboxNetworkPolicy'
                }
            }

            if ($Status) {
                $replace['msDS-SandboxStatus'] = $Status
            }

            # Handle enabled status
            if ($PSBoundParameters.ContainsKey('Enabled')) {
                if ($PSCmdlet.ShouldProcess($Identity, "Set enabled to $Enabled")) {
                    if ($Enabled) {
                        Enable-ADAccount -Identity $dn @commonParams
                    }
                    else {
                        Disable-ADAccount -Identity $dn @commonParams
                    }
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

            if ($replace.Count -gt 0 -or $clear.Count -gt 0 -or $Description) {
                if ($PSCmdlet.ShouldProcess($Identity, "Modify sandbox properties")) {
                    Set-ADObject @setParams
                    Write-Verbose "Sandbox '$Identity' updated successfully"
                }
            }

            if ($PassThru) {
                Get-ADAgentSandbox -Identity $dn @commonParams
            }
        }
        catch {
            Write-Error "Failed to modify sandbox '$Identity': $_"
        }
    }
}
