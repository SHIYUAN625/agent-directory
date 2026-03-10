function New-ADAgent {
    <#
    .SYNOPSIS
        Creates a new AI agent account in Active Directory.

    .DESCRIPTION
        Creates a new msDS-Agent object in Active Directory with the specified properties.
        The agent is created in the Agents container by default but can be placed in a
        custom organizational unit.

    .PARAMETER Name
        The name (CN) of the agent. Must be unique within the domain.

    .PARAMETER Type
        The agent type: autonomous, assistant, tool, or orchestrator.

    .PARAMETER TrustLevel
        The trust level (0-4). Default is 1 (Basic).

    .PARAMETER Owner
        The distinguished name of the owner (user or group) responsible for this agent.

    .PARAMETER Model
        The AI model identifier (e.g., "claude-opus-4-5").

    .PARAMETER Description
        A description of the agent's purpose.

    .PARAMETER Path
        The organizational unit or container where the agent will be created.
        Default is CN=Agents,CN=System,<domain>.

    .PARAMETER Capabilities
        Array of capability URNs the agent possesses.

    .PARAMETER Sandbox
        Distinguished name(s) of sandbox objects where this agent can run.

    .PARAMETER Enabled
        Whether to enable the agent immediately. Default is $false.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .EXAMPLE
        New-ADAgent -Name "claude-assistant-01" -Type "assistant" -TrustLevel 2 -Owner "CN=John Smith,OU=Users,DC=corp,DC=contoso,DC=com" -Model "claude-opus-4-5"

    .EXAMPLE
        New-ADAgent -Name "data-processor" -Type "tool" -TrustLevel 1 -Owner "CN=DataTeam,OU=Groups,DC=corp,DC=contoso,DC=com" -Capabilities @("urn:agent:capability:file-read", "urn:agent:capability:data-transform")

    .OUTPUTS
        AgentDirectory.Agent
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 64)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('autonomous', 'assistant', 'tool', 'orchestrator')]
        [string]$Type,

        [Parameter()]
        [ValidateRange(0, 4)]
        [int]$TrustLevel = 1,

        [Parameter()]
        [string]$Owner,

        [Parameter()]
        [string]$Model,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string]$Path,

        [Parameter()]
        [string[]]$Capabilities,

        [Parameter()]
        [string[]]$Sandbox,

        [Parameter()]
        [switch]$Enabled,

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
        # Determine path
        if (-not $Path) {
            $Path = $Script:AgentContainerDN
        }

        # Generate sAMAccountName (max 20 chars, no $ suffix for user objects)
        $samName = $Name
        if ($samName.Length -gt 20) {
            $samName = $samName.Substring(0, 20)
        }

        # Build other attributes
        $otherAttributes = @{
            'objectClass' = 'msDS-Agent'
            'msDS-AgentType' = $Type.ToLower()
            'msDS-AgentTrustLevel' = $TrustLevel
        }

        if ($Owner) {
            $otherAttributes['msDS-AgentOwner'] = $Owner
        }

        if ($Model) {
            $otherAttributes['msDS-AgentModel'] = $Model
        }

        if ($Capabilities) {
            $otherAttributes['msDS-AgentCapabilities'] = $Capabilities
        }

        if ($Sandbox) {
            $otherAttributes['msDS-AgentSandbox'] = $Sandbox
        }

        # User account control flags
        $uac = 0x0200  # NORMAL_ACCOUNT
        if (-not $Enabled) {
            $uac = $uac -bor 0x0002  # ACCOUNTDISABLE
        }
        $otherAttributes['userAccountControl'] = $uac

        # Create the agent
        if ($PSCmdlet.ShouldProcess($Name, "Create agent")) {
            try {
                Write-Verbose "Creating agent '$Name' in '$Path'"

                # Use New-ADUser as base since msDS-Agent inherits from user
                $newParams = @{
                    Name = $Name
                    SamAccountName = $samName
                    Path = $Path
                    Description = $Description
                    OtherAttributes = $otherAttributes
                    PassThru = $true
                } + $commonParams

                $agent = New-ADUser @newParams

                # Retrieve the created agent with all properties
                $createdAgent = Get-ADAgent -Identity $agent.DistinguishedName @commonParams

                Write-Verbose "Agent '$Name' created successfully"

                return $createdAgent
            }
            catch {
                throw "Failed to create agent '$Name': $_"
            }
        }
    }
}
