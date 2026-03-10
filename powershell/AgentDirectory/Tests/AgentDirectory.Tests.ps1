#Requires -Modules Pester

<#
.SYNOPSIS
    Main Pester test file for Agent Directory module.

.DESCRIPTION
    This file sets up the testing environment and imports all test files.
    Run with: Invoke-Pester -Path .\Tests\AgentDirectory.Tests.ps1

.NOTES
    Requires Pester v5+
#>

BeforeAll {
    # Get module path
    $ModulePath = Split-Path -Parent $PSScriptRoot
    $ModuleName = 'AgentDirectory'

    # Remove module if loaded
    Get-Module $ModuleName -ErrorAction SilentlyContinue | Remove-Module -Force

    # Import module
    Import-Module "$ModulePath\$ModuleName.psd1" -Force

    # Import mock helpers
    . "$PSScriptRoot\Mocks\ADMocks.ps1"
}

Describe 'AgentDirectory Module' {

    Context 'Module Import' {

        It 'Should import without errors' {
            Get-Module AgentDirectory | Should -Not -BeNullOrEmpty
        }

        It 'Should export expected agent functions' {
            $expectedFunctions = @(
                'New-ADAgent',
                'Get-ADAgent',
                'Set-ADAgent',
                'Remove-ADAgent'
            )

            foreach ($func in $expectedFunctions) {
                Get-Command -Module AgentDirectory -Name $func -ErrorAction SilentlyContinue |
                    Should -Not -BeNullOrEmpty -Because "$func should be exported"
            }
        }

        It 'Should export expected authentication functions' {
            $expectedFunctions = @(
                'Install-ADAgentSPN',
                'Grant-ADAgentDelegation',
                'Revoke-ADAgentDelegation',
                'Test-ADAgentAuthentication'
            )

            foreach ($func in $expectedFunctions) {
                Get-Command -Module AgentDirectory -Name $func -ErrorAction SilentlyContinue |
                    Should -Not -BeNullOrEmpty -Because "$func should be exported"
            }
        }

        It 'Should export expected sandbox functions' {
            $expectedFunctions = @(
                'New-ADAgentSandbox',
                'Get-ADAgentSandbox',
                'Set-ADAgentSandbox',
                'Remove-ADAgentSandbox'
            )

            foreach ($func in $expectedFunctions) {
                Get-Command -Module AgentDirectory -Name $func -ErrorAction SilentlyContinue |
                    Should -Not -BeNullOrEmpty -Because "$func should be exported"
            }
        }

        It 'Should export expected tool functions' {
            $expectedFunctions = @(
                'New-ADAgentTool',
                'Get-ADAgentTool',
                'Set-ADAgentTool',
                'Remove-ADAgentTool',
                'Grant-ADAgentToolAccess',
                'Revoke-ADAgentToolAccess',
                'Test-ADAgentToolAccess',
                'Get-ADAgentToolUsage'
            )

            foreach ($func in $expectedFunctions) {
                Get-Command -Module AgentDirectory -Name $func -ErrorAction SilentlyContinue |
                    Should -Not -BeNullOrEmpty -Because "$func should be exported"
            }
        }

        It 'Should export expected policy functions' {
            $expectedFunctions = @(
                'New-ADAgentPolicy',
                'Get-ADAgentPolicy',
                'Set-ADAgentPolicy',
                'Remove-ADAgentPolicy',
                'Grant-ADAgentPolicyLink',
                'Revoke-ADAgentPolicyLink',
                'Get-ADAgentEffectivePolicy'
            )

            foreach ($func in $expectedFunctions) {
                Get-Command -Module AgentDirectory -Name $func -ErrorAction SilentlyContinue |
                    Should -Not -BeNullOrEmpty -Because "$func should be exported"
            }
        }

        It 'Should export expected instruction GPO functions' {
            $expectedFunctions = @(
                'New-ADAgentInstructionGPO',
                'Get-ADAgentInstructionGPO',
                'Set-ADAgentInstructionGPO',
                'Remove-ADAgentInstructionGPO',
                'Grant-ADAgentInstructionGPOLink',
                'Revoke-ADAgentInstructionGPOLink',
                'Get-ADAgentEffectiveInstructions'
            )

            foreach ($func in $expectedFunctions) {
                Get-Command -Module AgentDirectory -Name $func -ErrorAction SilentlyContinue |
                    Should -Not -BeNullOrEmpty -Because "$func should be exported"
            }
        }

        It 'Should export expected event functions' {
            $expectedFunctions = @(
                'Write-ADAgentEvent',
                'Get-ADAgentEvent',
                'Export-ADAgentEventLog',
                'Install-ADAgentEventLog'
            )

            foreach ($func in $expectedFunctions) {
                Get-Command -Module AgentDirectory -Name $func -ErrorAction SilentlyContinue |
                    Should -Not -BeNullOrEmpty -Because "$func should be exported"
            }
        }

        It 'Should have correct module version' {
            $module = Get-Module AgentDirectory
            $module.Version | Should -Be '3.0.0'
        }
    }

    Context 'Module Manifest' {

        BeforeAll {
            $ManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'AgentDirectory.psd1'
            $Manifest = Test-ModuleManifest -Path $ManifestPath
        }

        It 'Should have a valid manifest' {
            $Manifest | Should -Not -BeNullOrEmpty
        }

        It 'Should require ActiveDirectory module' {
            $Manifest.RequiredModules.Name | Should -Contain 'ActiveDirectory'
        }

        It 'Should have a description' {
            $Manifest.Description | Should -Not -BeNullOrEmpty
        }

        It 'Should have an author' {
            $Manifest.Author | Should -Not -BeNullOrEmpty
        }

        It 'Should specify PowerShell version requirement' {
            $Manifest.PowerShellVersion | Should -Not -BeNullOrEmpty
        }
    }
}

# Import individual test files
$TestFiles = @(
    'Private.Tests.ps1',
    'Agent.Tests.ps1',
    'Sandbox.Tests.ps1',
    'Tool.Tests.ps1',
    'Policy.Tests.ps1',
    'InstructionGPO.Tests.ps1'
)

foreach ($file in $TestFiles) {
    $testPath = Join-Path $PSScriptRoot $file
    if (Test-Path $testPath) {
        . $testPath
    }
}
