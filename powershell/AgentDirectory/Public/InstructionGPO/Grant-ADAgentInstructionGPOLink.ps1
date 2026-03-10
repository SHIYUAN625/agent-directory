function Grant-ADAgentInstructionGPOLink {
    <#
    .SYNOPSIS
        Links one or more instruction GPOs to an agent.

    .DESCRIPTION
        Adds instruction GPO DNs to the agent's msDS-AgentInstructionGPOs attribute.

    .PARAMETER Identity
        The identity of the agent.

    .PARAMETER InstructionGPO
        One or more instruction GPO identities to link.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .PARAMETER PassThru
        Return the modified agent object.

    .EXAMPLE
        Grant-ADAgentInstructionGPOLink -Identity "claude-assistant-01" -InstructionGPO "base-agent-instructions"

    .OUTPUTS
        AgentDirectory.Agent (if PassThru is specified)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DistinguishedName', 'DN')]
        [string]$Identity,

        [Parameter(Mandatory)]
        [string[]]$InstructionGPO,

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
            $agentDn = Get-AgentDistinguishedName -Identity $Identity
            $agent = Get-ADAgent -Identity $agentDn @commonParams

            # Resolve GPO identities to DNs
            $gpoDns = @()
            foreach ($g in $InstructionGPO) {
                try {
                    $gpoDn = Get-InstructionGPODistinguishedName -Identity $g
                    $gpoDns += $gpoDn
                }
                catch {
                    Write-Warning "Instruction GPO not found: $g"
                }
            }

            if ($gpoDns.Count -eq 0) {
                Write-Warning "No valid instruction GPOs specified"
                return
            }

            $existingGPOs = @($agent.InstructionGPOs)
            $newGPOs = $gpoDns | Where-Object { $_ -notin $existingGPOs }

            if ($newGPOs.Count -eq 0) {
                Write-Verbose "All specified instruction GPOs are already linked to agent '$Identity'"
            }
            else {
                $allGPOs = @($existingGPOs) + @($newGPOs)

                if ($PSCmdlet.ShouldProcess($Identity, "Link instruction GPOs: $($InstructionGPO -join ', ')")) {
                    Set-ADObject -Identity $agentDn -Replace @{
                        'msDS-AgentInstructionGPOs' = $allGPOs
                    } @commonParams

                    Write-Verbose "Linked instruction GPOs to agent '$Identity': $($newGPOs -join ', ')"
                }
            }

            if ($PassThru) {
                Get-ADAgent -Identity $agentDn @commonParams
            }
        }
        catch {
            Write-Error "Failed to link instruction GPOs to agent '$Identity': $_"
        }
    }
}
