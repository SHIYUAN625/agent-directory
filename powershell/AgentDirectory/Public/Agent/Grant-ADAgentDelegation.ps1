function Grant-ADAgentDelegation {
    <#
    .SYNOPSIS
        Configures Kerberos delegation for an agent.

    .DESCRIPTION
        Sets up constrained or resource-based constrained delegation for an agent
        to act on behalf of users when accessing specific services.

    .PARAMETER Identity
        The identity of the agent.

    .PARAMETER TargetService
        Service Principal Names the agent can delegate to.

    .PARAMETER SandboxIdentity
        The identity of the sandbox for RBCD configuration. RBCD is set on the
        sandbox (computer object) rather than the agent (user object).

    .PARAMETER PrincipalsAllowedToDelegateToAccount
        For RBCD: Principals that can delegate to this agent's sandbox.

    .PARAMETER AllowProtocolTransition
        Allow protocol transition (S4U2Self).

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .PARAMETER PassThru
        Return the modified agent object.

    .EXAMPLE
        Grant-ADAgentDelegation -Identity "claude-assistant-01" -TargetService "cifs/fileserver.corp.contoso.com", "http/webapp.corp.contoso.com"

    .EXAMPLE
        Grant-ADAgentDelegation -Identity "claude-assistant-01" -AllowProtocolTransition

    .OUTPUTS
        AgentDirectory.Agent (if PassThru is specified)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DistinguishedName', 'DN')]
        [string]$Identity,

        [Parameter()]
        [string[]]$TargetService,

        [Parameter()]
        [string]$SandboxIdentity,

        [Parameter()]
        [string[]]$PrincipalsAllowedToDelegateToAccount,

        [Parameter()]
        [switch]$AllowProtocolTransition,

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

            # Get current agent
            $agent = Get-ADAgent -Identity $dn @commonParams

            # Check trust level
            if ($agent.TrustLevel -lt 2) {
                Write-Warning "Agent trust level ($($agent.TrustLevel)) is below recommended minimum (2) for delegation"
            }

            $changes = @{}

            # Configure constrained delegation
            if ($TargetService) {
                if ($PSCmdlet.ShouldProcess($Identity, "Set constrained delegation to: $($TargetService -join ', ')")) {
                    $changes['msDS-AllowedToDelegateTo'] = $TargetService

                    # Update delegation scope attribute
                    Set-ADObject -Identity $dn -Replace @{
                        'msDS-AgentDelegationScope' = $TargetService
                    } @commonParams

                    Write-Verbose "Configured constrained delegation for agent '$Identity'"
                }
            }

            # Configure RBCD on sandbox (computer object)
            if ($PrincipalsAllowedToDelegateToAccount) {
                if (-not $SandboxIdentity) {
                    Write-Error "SandboxIdentity is required for RBCD configuration. RBCD must be set on a sandbox (computer) object."
                    return
                }
                $sandboxDn = Get-SandboxDistinguishedName -Identity $SandboxIdentity
                if ($PSCmdlet.ShouldProcess($SandboxIdentity, "Set RBCD principals on sandbox")) {
                    Set-ADComputer -Identity $sandboxDn -PrincipalsAllowedToDelegateToAccount $PrincipalsAllowedToDelegateToAccount @commonParams
                    Write-Verbose "Configured RBCD on sandbox '$SandboxIdentity' for agent '$Identity'"
                }
            }

            # Configure protocol transition
            if ($AllowProtocolTransition) {
                if ($PSCmdlet.ShouldProcess($Identity, "Enable protocol transition")) {
                    # Set userAccountControl for protocol transition
                    # TRUSTED_TO_AUTH_FOR_DELEGATION = 0x1000000
                    Set-ADAccountControl -Identity $dn -TrustedToAuthForDelegation $true @commonParams
                    Write-Verbose "Enabled protocol transition for agent '$Identity'"
                }
            }

            if ($PassThru) {
                Get-ADAgent -Identity $dn @commonParams
            }
        }
        catch {
            Write-Error "Failed to configure delegation for agent '$Identity': $_"
        }
    }
}
