function Revoke-ADAgentDelegation {
    <#
    .SYNOPSIS
        Removes Kerberos delegation configuration from an agent.

    .DESCRIPTION
        Removes constrained and/or resource-based constrained delegation settings
        from an agent account.

    .PARAMETER Identity
        The identity of the agent.

    .PARAMETER All
        Remove all delegation settings.

    .PARAMETER TargetService
        Specific services to remove from constrained delegation.

    .PARAMETER SandboxIdentity
        The identity of the sandbox for RBCD cleanup.

    .PARAMETER DisableProtocolTransition
        Disable protocol transition (S4U2Self).

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .PARAMETER PassThru
        Return the modified agent object.

    .EXAMPLE
        Revoke-ADAgentDelegation -Identity "claude-assistant-01" -All

    .EXAMPLE
        Revoke-ADAgentDelegation -Identity "claude-assistant-01" -TargetService "cifs/fileserver.corp.contoso.com"

    .OUTPUTS
        AgentDirectory.Agent (if PassThru is specified)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DistinguishedName', 'DN')]
        [string]$Identity,

        [Parameter()]
        [switch]$All,

        [Parameter()]
        [string[]]$TargetService,

        [Parameter()]
        [string]$SandboxIdentity,

        [Parameter()]
        [switch]$DisableProtocolTransition,

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
            $dn = Get-AgentDistinguishedName -Identity $Identity

            if ($All) {
                if ($PSCmdlet.ShouldProcess($Identity, "Remove all delegation settings")) {
                    # Clear constrained delegation
                    Set-ADObject -Identity $dn -Clear 'msDS-AllowedToDelegateTo', 'msDS-AgentDelegationScope' @commonParams

                    # Clear RBCD on sandbox if specified
                    if ($SandboxIdentity) {
                        $sandboxDn = Get-SandboxDistinguishedName -Identity $SandboxIdentity
                        Set-ADComputer -Identity $sandboxDn -PrincipalsAllowedToDelegateToAccount $null @commonParams
                    }

                    # Disable protocol transition
                    Set-ADAccountControl -Identity $dn -TrustedToAuthForDelegation $false @commonParams

                    Write-Verbose "Removed all delegation settings from agent '$Identity'"
                }
            }
            else {
                # Remove specific services
                if ($TargetService) {
                    $agent = Get-ADAgent -Identity $dn @commonParams
                    $currentScope = @($agent.DelegationScope)
                    $newScope = $currentScope | Where-Object { $_ -notin $TargetService }

                    if ($PSCmdlet.ShouldProcess($Identity, "Remove delegation to: $($TargetService -join ', ')")) {
                        if ($newScope.Count -gt 0) {
                            Set-ADObject -Identity $dn -Replace @{
                                'msDS-AllowedToDelegateTo' = $newScope
                                'msDS-AgentDelegationScope' = $newScope
                            } @commonParams
                        }
                        else {
                            Set-ADObject -Identity $dn -Clear 'msDS-AllowedToDelegateTo', 'msDS-AgentDelegationScope' @commonParams
                        }

                        Write-Verbose "Removed delegation to specified services from agent '$Identity'"
                    }
                }

                # Disable protocol transition
                if ($DisableProtocolTransition) {
                    if ($PSCmdlet.ShouldProcess($Identity, "Disable protocol transition")) {
                        Set-ADAccountControl -Identity $dn -TrustedToAuthForDelegation $false @commonParams
                        Write-Verbose "Disabled protocol transition for agent '$Identity'"
                    }
                }
            }

            if ($PassThru) {
                Get-ADAgent -Identity $dn @commonParams
            }
        }
        catch {
            Write-Error "Failed to revoke delegation from agent '$Identity': $_"
        }
    }
}
