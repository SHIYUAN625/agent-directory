function Revoke-ADAgentInstructionGPOLink {
    <#
    .SYNOPSIS
        Unlinks one or more instruction GPOs from an agent.

    .DESCRIPTION
        Removes instruction GPO DNs from the agent's msDS-AgentInstructionGPOs attribute.

    .PARAMETER Identity
        The identity of the agent.

    .PARAMETER InstructionGPO
        One or more instruction GPO identities to unlink.

    .PARAMETER All
        Unlink all instruction GPOs.

    .PARAMETER Credential
        Credentials to use for the operation.

    .PARAMETER Server
        The domain controller to target.

    .PARAMETER PassThru
        Return the modified agent object.

    .EXAMPLE
        Revoke-ADAgentInstructionGPOLink -Identity "claude-assistant-01" -InstructionGPO "base-agent-instructions"

    .EXAMPLE
        Revoke-ADAgentInstructionGPOLink -Identity "claude-assistant-01" -All

    .OUTPUTS
        AgentDirectory.Agent (if PassThru is specified)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DistinguishedName', 'DN')]
        [string]$Identity,

        [Parameter(ParameterSetName = 'Specific')]
        [string[]]$InstructionGPO,

        [Parameter(ParameterSetName = 'All')]
        [switch]$All,

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

            if ($All) {
                if ($PSCmdlet.ShouldProcess($Identity, "Unlink all instruction GPOs")) {
                    Set-ADObject -Identity $agentDn -Clear 'msDS-AgentInstructionGPOs' @commonParams
                    Write-Verbose "Unlinked all instruction GPOs from agent '$Identity'"
                }
            }
            else {
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
                $remainingGPOs = $existingGPOs | Where-Object { $_ -notin $gpoDns }

                if ($PSCmdlet.ShouldProcess($Identity, "Unlink instruction GPOs: $($InstructionGPO -join ', ')")) {
                    if ($remainingGPOs.Count -gt 0) {
                        Set-ADObject -Identity $agentDn -Replace @{
                            'msDS-AgentInstructionGPOs' = $remainingGPOs
                        } @commonParams
                    }
                    else {
                        Set-ADObject -Identity $agentDn -Clear 'msDS-AgentInstructionGPOs' @commonParams
                    }

                    Write-Verbose "Unlinked instruction GPOs from agent '$Identity'"
                }
            }

            if ($PassThru) {
                Get-ADAgent -Identity $agentDn @commonParams
            }
        }
        catch {
            Write-Error "Failed to unlink instruction GPOs from agent '$Identity': $_"
        }
    }
}
