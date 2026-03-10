function Install-ADAgentSPN {
    <#
    .SYNOPSIS
        Registers Service Principal Names for an agent.

    .DESCRIPTION
        Adds AGENT/hostname SPNs to an agent account for Kerberos authentication.
        Also adds HOST/hostname for NTLM fallback.
        SPNs work on User objects (agents inherit from user).

    .PARAMETER Identity
        The identity of the agent.

    .PARAMETER Hostname
        Custom hostname(s) for the SPN. If not specified, uses the agent name.

    .PARAMETER ServiceClass
        Additional service classes to register (e.g., HTTP, CIFS).

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .PARAMETER PassThru
        Return the modified agent object.

    .EXAMPLE
        Install-ADAgentSPN -Identity "claude-assistant-01"

    .EXAMPLE
        Install-ADAgentSPN -Identity "claude-assistant-01" -Hostname "claude-01", "claude-01.corp.contoso.com"

    .EXAMPLE
        Install-ADAgentSPN -Identity "api-agent" -ServiceClass "HTTP"

    .OUTPUTS
        AgentDirectory.Agent (if PassThru is specified)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DistinguishedName', 'DN')]
        [string]$Identity,

        [Parameter()]
        [string[]]$Hostname,

        [Parameter()]
        [string[]]$ServiceClass = @(),

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
            # Resolve identity and get agent
            $dn = Get-AgentDistinguishedName -Identity $Identity
            $agent = Get-ADAgent -Identity $dn @commonParams

            # Determine hostnames
            if (-not $Hostname) {
                $domain = (Get-ADDomain @commonParams).DNSRoot
                $Hostname = @(
                    $agent.Name,
                    "$($agent.Name).$domain"
                )
            }

            # Build SPN list
            $spns = @()

            # Standard service classes
            $allClasses = @('AGENT', 'HOST') + $ServiceClass

            foreach ($class in $allClasses) {
                foreach ($host in $Hostname) {
                    $spns += "$class/$host"
                }
            }

            # Get existing SPNs
            $existingSpns = @($agent.ServicePrincipalNames)

            # Determine new SPNs
            $newSpns = $spns | Where-Object { $_ -notin $existingSpns }

            if ($newSpns.Count -eq 0) {
                Write-Verbose "All SPNs already registered for agent '$Identity'"
            }
            else {
                if ($PSCmdlet.ShouldProcess($Identity, "Add SPNs: $($newSpns -join ', ')")) {
                    $allSpns = $existingSpns + $newSpns

                    Set-ADObject -Identity $dn -Replace @{
                        servicePrincipalName = $allSpns
                    } @commonParams

                    Write-Verbose "Added SPNs to agent '$Identity': $($newSpns -join ', ')"
                }
            }

            if ($PassThru) {
                Get-ADAgent -Identity $dn @commonParams
            }
        }
        catch {
            Write-Error "Failed to install SPNs for agent '$Identity': $_"
        }
    }
}
