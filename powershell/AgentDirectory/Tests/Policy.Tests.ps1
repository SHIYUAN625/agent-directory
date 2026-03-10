#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for Policy cmdlets.
#>

Describe 'Policy Cmdlets' {

    BeforeAll {
        . "$PSScriptRoot\Mocks\ADMocks.ps1"
    }

    BeforeEach {
        Reset-MockData
        Initialize-ADMocks
    }

    Context 'Get-ADAgentPolicy' {

        It 'Should get policy by identity' {
            $result = Get-ADAgentPolicy -Identity 'base-security'
            $result | Should -Not -BeNullOrEmpty
            $result.Identifier | Should -Be 'base-security'
        }

        It 'Should return correct properties' {
            $result = Get-ADAgentPolicy -Identity 'base-security'
            $result.Type | Should -Be 'security'
            $result.Priority | Should -Be 0
            $result.Enabled | Should -Be $true
            $result.Version | Should -Be '1.0.0'
        }

        It 'Should get all policies' {
            $results = Get-ADAgentPolicy
            $results.Count | Should -BeGreaterOrEqual 3
        }

        It 'Should filter by type' {
            $results = Get-ADAgentPolicy -Type 'security'
            $results | Should -Not -BeNullOrEmpty
            $results | ForEach-Object { $_.Type | Should -Be 'security' }
        }
    }

    Context 'New-ADAgentPolicy' {

        It 'Should create policy with required parameters' {
            $result = New-ADAgentPolicy -Identifier 'custom-security' -Type 'security' -Priority 200
            $result | Should -Not -BeNullOrEmpty
            $result.Identifier | Should -Be 'custom-security'
        }

        It 'Should set default Enabled to TRUE' {
            $result = New-ADAgentPolicy -Identifier 'test-policy' -Type 'behavior' -Priority 50
            $result.Enabled | Should -Be $true
        }

        It 'Should accept AppliesToTypes' {
            $result = New-ADAgentPolicy -Identifier 'type-specific' -Type 'behavior' -Priority 100 -AppliesToTypes @('autonomous', 'assistant')
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should accept Version' {
            $result = New-ADAgentPolicy -Identifier 'versioned' -Type 'resource' -Priority 50 -Version '2.0.0'
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should reject invalid type' {
            { New-ADAgentPolicy -Identifier 'bad' -Type 'invalid' -Priority 0 } | Should -Throw
        }

        It 'Should reject priority out of range' {
            { New-ADAgentPolicy -Identifier 'bad' -Type 'security' -Priority 1000 } | Should -Throw
            { New-ADAgentPolicy -Identifier 'bad' -Type 'security' -Priority -1 } | Should -Throw
        }
    }

    Context 'Set-ADAgentPolicy' {

        It 'Should modify priority' {
            Set-ADAgentPolicy -Identity 'base-security' -Priority 5
            $result = Get-ADAgentPolicy -Identity 'base-security'
            $result.Priority | Should -Be 5
        }

        It 'Should modify type' {
            Set-ADAgentPolicy -Identity 'base-security' -Type 'behavior'
            $result = Get-ADAgentPolicy -Identity 'base-security'
            $result.Type | Should -Be 'behavior'
        }

        It 'Should return modified object with PassThru' {
            $result = Set-ADAgentPolicy -Identity 'base-security' -Priority 10 -PassThru
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should modify AppliesToTypes' {
            Set-ADAgentPolicy -Identity 'base-security' -AppliesToTypes @('autonomous')
            $result = Get-ADAgentPolicy -Identity 'base-security'
            $result.AppliesToTypes | Should -Contain 'autonomous'
        }
    }

    Context 'Remove-ADAgentPolicy' {

        It 'Should remove policy' {
            Remove-ADAgentPolicy -Identity 'base-security' -Confirm:$false
            $result = Get-ADAgentPolicy -Identity 'base-security'
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Grant-ADAgentPolicyLink' {

        It 'Should link policy to agent' {
            # data-processor-01 starts with no policies
            Grant-ADAgentPolicyLink -Identity 'data-processor-01' -Policy 'base-security'
            $agent = Get-MockAgent -Identity 'data-processor-01'
            $agent.'msDS-AgentPolicies' | Should -Contain 'base-security'
        }

        It 'Should not duplicate existing links' {
            # claude-assistant-01 already has base-security
            Grant-ADAgentPolicyLink -Identity 'claude-assistant-01' -Policy 'base-security'
            $agent = Get-MockAgent -Identity 'claude-assistant-01'
            ($agent.'msDS-AgentPolicies' | Where-Object { $_ -eq 'base-security' }).Count | Should -Be 1
        }
    }

    Context 'Revoke-ADAgentPolicyLink' {

        It 'Should unlink policy from agent' {
            Revoke-ADAgentPolicyLink -Identity 'claude-assistant-01' -Policy 'type-worker'
            $agent = Get-MockAgent -Identity 'claude-assistant-01'
            $agent.'msDS-AgentPolicies' | Should -Not -Contain 'type-worker'
        }

        It 'Should unlink all policies with -All' {
            Revoke-ADAgentPolicyLink -Identity 'claude-assistant-01' -All
            $agent = Get-MockAgent -Identity 'claude-assistant-01'
            # After Clear, the key is removed entirely
            $agent.'msDS-AgentPolicies' | Should -BeNullOrEmpty
        }
    }
}
