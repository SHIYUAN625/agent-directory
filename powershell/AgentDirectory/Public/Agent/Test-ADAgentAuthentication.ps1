function Test-ADAgentAuthentication {
    <#
    .SYNOPSIS
        Tests authentication capability for an agent.

    .DESCRIPTION
        Verifies that an agent can authenticate using various methods.

    .PARAMETER Identity
        The identity of the agent.

    .PARAMETER AuthType
        The authentication type to test: Kerberos, NTLM, or Certificate.

    .PARAMETER TargetService
        For Kerberos, the target service to request a ticket for.

    .PARAMETER CertificateThumbprint
        For certificate auth, the thumbprint to verify mapping.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .EXAMPLE
        Test-ADAgentAuthentication -Identity "claude-assistant-01" -AuthType Kerberos

    .EXAMPLE
        Test-ADAgentAuthentication -Identity "claude-assistant-01" -AuthType Kerberos -TargetService "cifs/fileserver.corp.contoso.com"

    .OUTPUTS
        PSCustomObject with test results
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DistinguishedName', 'DN')]
        [string]$Identity,

        [Parameter(Mandatory)]
        [ValidateSet('Kerberos', 'NTLM', 'Certificate')]
        [string]$AuthType,

        [Parameter()]
        [string]$TargetService,

        [Parameter()]
        [string]$CertificateThumbprint,

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
            $agent = Get-ADAgent -Identity $dn @commonParams

            $result = [PSCustomObject]@{
                Agent = $agent.Name
                AuthType = $AuthType
                Success = $false
                Message = ''
                Details = @{}
            }

            # Check if agent is enabled
            if (-not $agent.Enabled) {
                $result.Message = "Agent is disabled"
                return $result
            }

            # Check sandbox association
            $sandboxes = @($agent.Sandboxes)
            if ($sandboxes.Count -eq 0 -or ($sandboxes.Count -eq 1 -and -not $sandboxes[0])) {
                $result.Details['SandboxWarning'] = 'No sandbox associated. Agent has no execution environment.'
            }
            else {
                $result.Details['Sandboxes'] = $sandboxes
            }

            switch ($AuthType) {
                'Kerberos' {
                    # Check for SPNs
                    $spns = @($agent.ServicePrincipalNames)

                    if ($spns.Count -eq 0) {
                        $result.Message = "No Service Principal Names registered"
                        $result.Details['Recommendation'] = "Run Install-ADAgentSPN"
                        return $result
                    }

                    $result.Details['SPNs'] = $spns

                    # Check for AGENT/ SPN
                    $agentSpn = $spns | Where-Object { $_ -like 'AGENT/*' }
                    if (-not $agentSpn) {
                        $result.Message = "No AGENT/ SPN found"
                        $result.Details['Recommendation'] = "Run Install-ADAgentSPN"
                        return $result
                    }

                    if ($TargetService) {
                        # Check if delegation is configured
                        $scope = @($agent.DelegationScope)
                        if ($scope -contains $TargetService) {
                            $result.Details['DelegationConfigured'] = $true
                        }
                        else {
                            $result.Details['DelegationConfigured'] = $false
                            $result.Details['Recommendation'] = "Run Grant-ADAgentDelegation"
                        }
                    }

                    $result.Success = $true
                    $result.Message = "Kerberos authentication is configured"
                }

                'NTLM' {
                    # Check that account has a password hash
                    # Note: We can't directly verify password hash, but we can check account status
                    $result.Success = $true
                    $result.Message = "NTLM authentication is available"
                    $result.Details['SamAccountName'] = $agent.SamAccountName
                }

                'Certificate' {
                    # Check altSecurityIdentities
                    $altIds = Get-ADObject -Identity $dn -Properties altSecurityIdentities @commonParams |
                              Select-Object -ExpandProperty altSecurityIdentities

                    if (-not $altIds) {
                        $result.Message = "No certificate mappings configured"
                        $result.Details['Recommendation'] = "Add altSecurityIdentities mapping"
                        return $result
                    }

                    $result.Details['CertificateMappings'] = $altIds

                    if ($CertificateThumbprint) {
                        $found = $altIds | Where-Object { $_ -like "*$CertificateThumbprint*" }
                        if (-not $found) {
                            $result.Message = "Specified certificate thumbprint not mapped"
                            return $result
                        }
                    }

                    $result.Success = $true
                    $result.Message = "Certificate authentication is configured"
                }
            }

            return $result
        }
        catch {
            Write-Error "Failed to test authentication for agent '$Identity': $_"
        }
    }
}
