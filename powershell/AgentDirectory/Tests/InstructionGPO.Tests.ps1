#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for Instruction GPO cmdlets.
#>

Describe 'Instruction GPO Cmdlets' {

    BeforeAll {
        . "$PSScriptRoot\Mocks\ADMocks.ps1"
    }

    BeforeEach {
        Reset-MockData
        Initialize-ADMocks
    }

    Context 'Get-ADAgentInstructionGPO' {

        It 'Should get GPO by identity' {
            $result = Get-ADAgentInstructionGPO -Identity 'base-agent-instructions'
            $result | Should -Not -BeNullOrEmpty
            $result.DisplayName | Should -Be 'Base Agent Instructions'
        }

        It 'Should return correct properties' {
            $result = Get-ADAgentInstructionGPO -Identity 'base-agent-instructions'
            $result.Priority | Should -Be 0
            $result.MergeStrategy | Should -Be 'append'
            $result.Enabled | Should -Be $true
            $result.Version | Should -Be '1.0.0'
            $result.InstructionPath | Should -Be 'AgentInstructions/base-agent-instructions/instructions.md'
        }

        It 'Should get all GPOs' {
            $results = Get-ADAgentInstructionGPO
            $results.Count | Should -BeGreaterOrEqual 3
        }

        It 'Should filter by merge strategy' {
            $results = Get-ADAgentInstructionGPO -MergeStrategy 'append'
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context 'New-ADAgentInstructionGPO' {

        It 'Should create GPO with required parameters' {
            $result = New-ADAgentInstructionGPO -Name 'custom-instructions' -InstructionPath 'AgentInstructions/custom/instructions.md' -Priority 300
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'custom-instructions'
        }

        It 'Should default MergeStrategy to append' {
            $result = New-ADAgentInstructionGPO -Name 'test-gpo' -InstructionPath 'AgentInstructions/test/instructions.md' -Priority 50
            $result.MergeStrategy | Should -Be 'append'
        }

        It 'Should default Enabled to TRUE' {
            $result = New-ADAgentInstructionGPO -Name 'test-gpo2' -InstructionPath 'AgentInstructions/test2/instructions.md' -Priority 50
            $result.Enabled | Should -Be $true
        }

        It 'Should accept AppliesToTypes' {
            $result = New-ADAgentInstructionGPO -Name 'type-specific-gpo' -InstructionPath 'AgentInstructions/ts/instructions.md' -Priority 100 -AppliesToTypes @('assistant')
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should accept DisplayName' {
            $result = New-ADAgentInstructionGPO -Name 'named-gpo' -InstructionPath 'AgentInstructions/named/instructions.md' -Priority 50 -DisplayName 'My Custom GPO'
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should reject invalid merge strategy' {
            { New-ADAgentInstructionGPO -Name 'bad' -InstructionPath 'x' -Priority 0 -MergeStrategy 'invalid' } | Should -Throw
        }

        It 'Should reject priority out of range' {
            { New-ADAgentInstructionGPO -Name 'bad' -InstructionPath 'x' -Priority 1000 } | Should -Throw
            { New-ADAgentInstructionGPO -Name 'bad' -InstructionPath 'x' -Priority -1 } | Should -Throw
        }
    }

    Context 'Set-ADAgentInstructionGPO' {

        It 'Should modify priority' {
            Set-ADAgentInstructionGPO -Identity 'base-agent-instructions' -Priority 5
            $result = Get-ADAgentInstructionGPO -Identity 'base-agent-instructions'
            $result.Priority | Should -Be 5
        }

        It 'Should modify merge strategy' {
            Set-ADAgentInstructionGPO -Identity 'base-agent-instructions' -MergeStrategy 'replace'
            $result = Get-ADAgentInstructionGPO -Identity 'base-agent-instructions'
            $result.MergeStrategy | Should -Be 'replace'
        }

        It 'Should return modified object with PassThru' {
            $result = Set-ADAgentInstructionGPO -Identity 'base-agent-instructions' -Priority 10 -PassThru
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Remove-ADAgentInstructionGPO' {

        It 'Should remove GPO' {
            Remove-ADAgentInstructionGPO -Identity 'base-agent-instructions' -Confirm:$false
            $result = Get-ADAgentInstructionGPO -Identity 'base-agent-instructions'
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Grant-ADAgentInstructionGPOLink' {

        It 'Should link GPO to agent' {
            Grant-ADAgentInstructionGPOLink -Identity 'data-processor-01' -InstructionGPO 'base-agent-instructions'
            $agent = Get-MockAgent -Identity 'data-processor-01'
            $agent.'msDS-AgentInstructionGPOs' | Should -Not -BeNullOrEmpty
        }

        It 'Should not duplicate existing links' {
            # claude-assistant-01 already has base-agent-instructions linked
            $beforeCount = @((Get-MockAgent -Identity 'claude-assistant-01').'msDS-AgentInstructionGPOs').Count
            Grant-ADAgentInstructionGPOLink -Identity 'claude-assistant-01' -InstructionGPO 'base-agent-instructions'
            $afterCount = @((Get-MockAgent -Identity 'claude-assistant-01').'msDS-AgentInstructionGPOs').Count
            $afterCount | Should -Be $beforeCount
        }
    }

    Context 'Revoke-ADAgentInstructionGPOLink' {

        It 'Should unlink GPO from agent' {
            $gpoDn = "CN=base-agent-instructions,$Script:MockInstructionGPOContainerDN"
            Revoke-ADAgentInstructionGPOLink -Identity 'claude-assistant-01' -InstructionGPO 'base-agent-instructions'
            $agent = Get-MockAgent -Identity 'claude-assistant-01'
            $agent.'msDS-AgentInstructionGPOs' | Should -BeNullOrEmpty
        }

        It 'Should unlink all GPOs with -All' {
            Revoke-ADAgentInstructionGPOLink -Identity 'claude-assistant-01' -All
            $agent = Get-MockAgent -Identity 'claude-assistant-01'
            $agent.'msDS-AgentInstructionGPOs' | Should -BeNullOrEmpty
        }
    }

    Context 'Get-ADAgentEffectiveInstructions' {

        It 'Should return GPOs for an agent' {
            $results = Get-ADAgentEffectiveInstructions -Identity 'claude-assistant-01'
            $results | Should -Not -BeNullOrEmpty
        }

        It 'Should include base GPO (applies to all)' {
            $results = Get-ADAgentEffectiveInstructions -Identity 'claude-assistant-01'
            $results.Name | Should -Contain 'base-agent-instructions'
        }

        It 'Should include type-matched GPO' {
            $results = Get-ADAgentEffectiveInstructions -Identity 'claude-assistant-01'
            $results.Name | Should -Contain 'type-assistant-instructions'
        }

        It 'Should not include trust-level-mismatched GPO' {
            # claude-assistant-01 has trust level 2, trust-elevated applies to 3,4
            $results = Get-ADAgentEffectiveInstructions -Identity 'claude-assistant-01'
            $results.Name | Should -Not -Contain 'trust-elevated-instructions'
        }

        It 'Should return sorted by priority' {
            $results = Get-ADAgentEffectiveInstructions -Identity 'claude-assistant-01'
            if ($results.Count -ge 2) {
                for ($i = 1; $i -lt $results.Count; $i++) {
                    $results[$i].Priority | Should -BeGreaterOrEqual $results[$i-1].Priority
                }
            }
        }
    }
}
