function New-ADAgentSandbox {
    <#
    .SYNOPSIS
        Creates a new agent sandbox (execution environment) in Active Directory.

    .DESCRIPTION
        Creates a new msDS-AgentSandbox object in Active Directory. Sandboxes are
        computer objects that represent where agents run, separate from the agent
        identity itself.

    .PARAMETER Name
        The name (CN) of the sandbox. Must be unique within the domain.

    .PARAMETER Endpoint
        URI where the sandbox runtime is accessible.

    .PARAMETER SecurityProfile
        Sandbox isolation technology (bwrap, appcontainer, hyperv, vmware, none).

    .PARAMETER ResourcePolicy
        JSON-encoded resource constraints (CPU, memory, disk).

    .PARAMETER NetworkPolicy
        JSON-encoded network rules (allowed hosts, ports, protocols).

    .PARAMETER Status
        Initial sandbox status. Default is 'standby'.

    .PARAMETER Description
        A description of the sandbox.

    .PARAMETER Path
        Container where the sandbox will be created.
        Default is CN=Agent Sandboxes,CN=System,<domain>.

    .PARAMETER Enabled
        Whether to enable the sandbox immediately. Default is $false.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .EXAMPLE
        New-ADAgentSandbox -Name "sandbox-prod-001" -SecurityProfile "bwrap" -Endpoint "https://sandbox-001:8443"

    .OUTPUTS
        AgentDirectory.Sandbox
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 64)]
        [string]$Name,

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
        [string]$Status = 'standby',

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string]$Path,

        [Parameter()]
        [switch]$Enabled,

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
        if (-not $Path) {
            $Path = $Script:SandboxContainerDN
        }

        # Generate sAMAccountName (max 20 chars including $ for computer accounts)
        $samName = $Name
        if ($samName.Length -gt 15) {
            $samName = $samName.Substring(0, 15)
        }
        $samName = "$samName`$"

        # Build other attributes
        $otherAttributes = @{
            'objectClass' = 'msDS-AgentSandbox'
            'msDS-SandboxStatus' = $Status
        }

        if ($Endpoint) {
            $otherAttributes['msDS-SandboxEndpoint'] = $Endpoint
        }

        if ($SecurityProfile) {
            $otherAttributes['msDS-SandboxSecurityProfile'] = $SecurityProfile
        }

        if ($ResourcePolicy) {
            $otherAttributes['msDS-SandboxResourcePolicy'] = $ResourcePolicy
        }

        if ($NetworkPolicy) {
            $otherAttributes['msDS-SandboxNetworkPolicy'] = $NetworkPolicy
        }

        # User account control flags
        $uac = 0x1000  # WORKSTATION_TRUST_ACCOUNT
        if (-not $Enabled) {
            $uac = $uac -bor 0x0002  # ACCOUNTDISABLE
        }
        $otherAttributes['userAccountControl'] = $uac

        if ($PSCmdlet.ShouldProcess($Name, "Create sandbox")) {
            try {
                Write-Verbose "Creating sandbox '$Name' in '$Path'"

                # Use New-ADComputer since msDS-AgentSandbox inherits from computer
                $newParams = @{
                    Name = $Name
                    SamAccountName = $samName
                    Path = $Path
                    Description = $Description
                    OtherAttributes = $otherAttributes
                    PassThru = $true
                } + $commonParams

                $sandbox = New-ADComputer @newParams

                # Retrieve the created sandbox with all properties
                $createdSandbox = Get-ADAgentSandbox -Identity $sandbox.DistinguishedName @commonParams

                Write-Verbose "Sandbox '$Name' created successfully"

                return $createdSandbox
            }
            catch {
                throw "Failed to create sandbox '$Name': $_"
            }
        }
    }
}
