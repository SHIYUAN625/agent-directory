#Requires -Version 5.1
#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Agent Directory PowerShell Module

.DESCRIPTION
    This module provides cmdlets for managing AI Agent identities in Active Directory.
    It includes functions for agent lifecycle management, authentication configuration,
    tool authorization, and event logging.

.NOTES
    Requires the ActiveDirectory PowerShell module.
    Some operations require Domain Admin or Schema Admin privileges.
#>

# Module variables
$Script:AgentContainerDN = $null
$Script:ToolContainerDN = $null
$Script:SandboxContainerDN = $null
$Script:PolicyContainerDN = $null
$Script:InstructionGPOContainerDN = $null
$Script:DomainDN = $null

# Trust level names
$Script:TrustLevelNames = @{
    0 = 'Untrusted'
    1 = 'Basic'
    2 = 'Standard'
    3 = 'Elevated'
    4 = 'System'
}

# Agent types
$Script:ValidAgentTypes = @('autonomous', 'assistant', 'tool', 'orchestrator')

# Tool categories
$Script:ValidToolCategories = @('shell', 'office', 'management', 'development', 'network', 'security', 'filesystem', 'data')

# Policy types
$Script:ValidPolicyTypes = @('security', 'behavior', 'resource', 'network')

# Merge strategies
$Script:ValidMergeStrategies = @('prepend', 'append', 'replace')

# Event provider
$Script:EventProviderName = 'Microsoft-AgentDirectory'
$Script:EventLogOperational = 'Microsoft-AgentDirectory/Operational'
$Script:EventLogAdmin = 'Microsoft-AgentDirectory/Admin'

function Initialize-AgentDirectoryModule {
    <#
    .SYNOPSIS
        Initializes module variables with domain-specific values.
    #>
    [CmdletBinding()]
    param()

    try {
        $domain = Get-ADDomain -ErrorAction Stop
        $Script:DomainDN = $domain.DistinguishedName
        $Script:AgentContainerDN = "CN=Agents,CN=System,$($Script:DomainDN)"
        $Script:ToolContainerDN = "CN=Agent Tools,CN=System,$($Script:DomainDN)"
        $Script:SandboxContainerDN = "CN=Agent Sandboxes,CN=System,$($Script:DomainDN)"
        $Script:PolicyContainerDN = "CN=Agent Policies,CN=System,$($Script:DomainDN)"
        $Script:InstructionGPOContainerDN = "CN=Agent Instructions,CN=System,$($Script:DomainDN)"

        Write-Verbose "Initialized Agent Directory module for domain: $($domain.DNSRoot)"
    }
    catch {
        Write-Warning "Failed to initialize module. Ensure ActiveDirectory module is available and you are connected to a domain."
    }
}

# Initialize on module load
Initialize-AgentDirectoryModule

# Import public functions
$PublicPath = Join-Path $PSScriptRoot 'Public'
if (Test-Path $PublicPath) {
    Get-ChildItem -Path $PublicPath -Recurse -Filter '*.ps1' | ForEach-Object {
        try {
            . $_.FullName
            Write-Verbose "Loaded: $($_.Name)"
        }
        catch {
            Write-Error "Failed to load $($_.FullName): $_"
        }
    }
}

# Import private functions
$PrivatePath = Join-Path $PSScriptRoot 'Private'
if (Test-Path $PrivatePath) {
    Get-ChildItem -Path $PrivatePath -Recurse -Filter '*.ps1' | ForEach-Object {
        try {
            . $_.FullName
            Write-Verbose "Loaded private: $($_.Name)"
        }
        catch {
            Write-Error "Failed to load $($_.FullName): $_"
        }
    }
}

# Export module member
Export-ModuleMember -Function @(
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
