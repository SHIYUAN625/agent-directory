@{
    # Module identification
    RootModule = 'AgentDirectory.psm1'
    ModuleVersion = '3.0.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'Agent Directory Team'
    CompanyName = 'Organization'
    Copyright = '(c) 2026. All rights reserved.'
    Description = 'PowerShell module for managing AI Agent identities in Active Directory'

    # PowerShell version requirements
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Required modules
    RequiredModules = @(
        @{ ModuleName = 'ActiveDirectory'; ModuleVersion = '1.0.0.0' }
    )

    # Functions to export
    FunctionsToExport = @(
        # Agent management
        'New-ADAgent',
        'Get-ADAgent',
        'Set-ADAgent',
        'Remove-ADAgent',

        # Agent authentication
        'Install-ADAgentSPN',
        'Grant-ADAgentDelegation',
        'Revoke-ADAgentDelegation',
        'Test-ADAgentAuthentication',

        # Sandbox management
        'New-ADAgentSandbox',
        'Get-ADAgentSandbox',
        'Set-ADAgentSandbox',
        'Remove-ADAgentSandbox',

        # Tool management
        'New-ADAgentTool',
        'Get-ADAgentTool',
        'Set-ADAgentTool',
        'Remove-ADAgentTool',
        'Grant-ADAgentToolAccess',
        'Revoke-ADAgentToolAccess',
        'Test-ADAgentToolAccess',
        'Get-ADAgentToolUsage',

        # Policy management
        'New-ADAgentPolicy',
        'Get-ADAgentPolicy',
        'Set-ADAgentPolicy',
        'Remove-ADAgentPolicy',
        'Grant-ADAgentPolicyLink',
        'Revoke-ADAgentPolicyLink',
        'Get-ADAgentEffectivePolicy',

        # Instruction GPO management
        'New-ADAgentInstructionGPO',
        'Get-ADAgentInstructionGPO',
        'Set-ADAgentInstructionGPO',
        'Remove-ADAgentInstructionGPO',
        'Grant-ADAgentInstructionGPOLink',
        'Revoke-ADAgentInstructionGPOLink',
        'Get-ADAgentEffectiveInstructions',

        # Event logging
        'Write-ADAgentEvent',
        'Get-ADAgentEvent',
        'Export-ADAgentEventLog',
        'Install-ADAgentEventLog'
    )

    # Cmdlets to export (none - this is a script module)
    CmdletsToExport = @()

    # Variables to export
    VariablesToExport = @()

    # Aliases to export
    AliasesToExport = @()

    # Private data
    PrivateData = @{
        PSData = @{
            Tags = @('ActiveDirectory', 'Agent', 'AI', 'Identity', 'Security')
            LicenseUri = ''
            ProjectUri = ''
            ReleaseNotes = @'
Version 3.0.0
- New msDS-AgentPolicy class and policy cmdlets
- New msDS-AgentInstructionGPO class and instruction GPO cmdlets
- Policy management: New/Get/Set/Remove-ADAgentPolicy
- Policy linking: Grant/Revoke-ADAgentPolicyLink
- Effective policy resolution: Get-ADAgentEffectivePolicy
- Instruction GPO management: New/Get/Set/Remove-ADAgentInstructionGPO
- Instruction GPO linking: Grant/Revoke-ADAgentInstructionGPOLink
- Effective instructions resolution: Get-ADAgentEffectiveInstructions
- Agent InstructionGPOs attribute (msDS-AgentInstructionGPOs)

Version 2.0.0
- Agent identity now inherits from User (was Computer)
- New msDS-AgentSandbox class for execution environments
- Sandbox cmdlets: New/Get/Set/Remove-ADAgentSandbox
- Agent-sandbox linkage via msDS-AgentSandbox attribute
- RBCD delegation moves to sandbox (computer) objects
- Deprecated: RuntimeEndpoint (use sandbox endpoint)

Version 1.0.0
- Initial release
- Agent lifecycle management (New/Get/Set/Remove-ADAgent)
- Authentication management (SPN, delegation)
- Tool authorization (Grant/Revoke/Test-ADAgentToolAccess)
- Event logging integration
'@
        }
    }
}
