#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for Tool cmdlets.
#>

Describe 'Tool Cmdlets' {

    BeforeAll {
        # Import mock helpers
        . "$PSScriptRoot\Mocks\ADMocks.ps1"
    }

    BeforeEach {
        Reset-MockData
        Initialize-ADMocks
    }

    Context 'Get-ADAgentTool' {

        It 'Should return tool by identifier' {
            $result = Get-ADAgentTool -Identity 'microsoft.powershell'

            $result | Should -Not -BeNullOrEmpty
            $result.Identifier | Should -Be 'microsoft.powershell'
        }

        It 'Should return tool properties correctly' {
            $result = Get-ADAgentTool -Identity 'microsoft.powershell'

            $result.DisplayName | Should -Be 'PowerShell'
            $result.Category | Should -Be 'shell'
            $result.RiskLevel | Should -Be 4
            $result.RequiredTrustLevel | Should -Be 2
        }

        It 'Should return all tools when no identity specified' {
            $results = Get-ADAgentTool

            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -BeGreaterOrEqual 3
        }

        It 'Should filter by Category' {
            $results = Get-ADAgentTool -Category 'shell'

            $results | Should -Not -BeNullOrEmpty
            $results | ForEach-Object {
                $_.Category | Should -Be 'shell'
            }
        }

        It 'Should filter by RiskLevel' {
            $results = Get-ADAgentTool -RiskLevel 5

            $results | Should -Not -BeNullOrEmpty
            $results | ForEach-Object {
                $_.RiskLevel | Should -Be 5
            }
        }
    }

    Context 'New-ADAgentTool' {

        It 'Should create tool with required parameters' {
            $result = New-ADAgentTool -Identifier 'contoso.custom-tool'

            $result | Should -Not -BeNullOrEmpty
            $result.Identifier | Should -Be 'contoso.custom-tool'
        }

        It 'Should set default risk level to 3' {
            $result = New-ADAgentTool -Identifier 'contoso.test-tool-1'

            $result.RiskLevel | Should -Be 3
        }

        It 'Should set default required trust level to 1' {
            $result = New-ADAgentTool -Identifier 'contoso.test-tool-2'

            $result.RequiredTrustLevel | Should -Be 1
        }

        It 'Should accept custom properties' {
            $result = New-ADAgentTool -Identifier 'contoso.test-tool-3' `
                -DisplayName 'Custom Tool' `
                -Category 'data' `
                -RiskLevel 4 `
                -RequiredTrustLevel 3

            $result.DisplayName | Should -Be 'Custom Tool'
            $result.Category | Should -Be 'data'
            $result.RiskLevel | Should -Be 4
            $result.RequiredTrustLevel | Should -Be 3
        }

        It 'Should set constraints when specified' {
            $constraints = @('Timeout=30', 'ReadOnly=true')
            $result = New-ADAgentTool -Identifier 'contoso.test-tool-4' -Constraints $constraints

            $result.Constraints | Should -Contain 'Timeout=30'
            $result.Constraints | Should -Contain 'ReadOnly=true'
        }

        It 'Should reject invalid category' {
            { New-ADAgentTool -Identifier 'contoso.invalid' -Category 'invalid' } | Should -Throw
        }

        It 'Should reject risk level out of range' {
            { New-ADAgentTool -Identifier 'contoso.invalid' -RiskLevel 0 } | Should -Throw
            { New-ADAgentTool -Identifier 'contoso.invalid' -RiskLevel 6 } | Should -Throw
        }
    }

    Context 'Set-ADAgentTool' {

        It 'Should modify risk level' {
            Set-ADAgentTool -Identity 'microsoft.word' -RiskLevel 3

            $result = Get-ADAgentTool -Identity 'microsoft.word'
            $result.RiskLevel | Should -Be 3
        }

        It 'Should modify required trust level' {
            Set-ADAgentTool -Identity 'microsoft.word' -RequiredTrustLevel 2

            $result = Get-ADAgentTool -Identity 'microsoft.word'
            $result.RequiredTrustLevel | Should -Be 2
        }

        It 'Should add constraints' {
            Set-ADAgentTool -Identity 'microsoft.word' -AddConstraints 'NewConstraint=value'

            $result = Get-ADAgentTool -Identity 'microsoft.word'
            $result.Constraints | Should -Contain 'NewConstraint=value'
        }

        It 'Should return modified tool with PassThru' {
            $result = Set-ADAgentTool -Identity 'microsoft.word' -RiskLevel 4 -PassThru

            $result | Should -Not -BeNullOrEmpty
            $result.RiskLevel | Should -Be 4
        }
    }

    Context 'Remove-ADAgentTool' {

        It 'Should remove tool' {
            Remove-ADAgentTool -Identity 'microsoft.gpo' -Confirm:$false

            { Get-ADAgentTool -Identity 'microsoft.gpo' } | Should -Throw
        }
    }

    Context 'Grant-ADAgentToolAccess' {

        It 'Should add tool to authorized list' {
            Grant-ADAgentToolAccess -Identity 'claude-assistant-01' -Tool 'microsoft.powershell'

            $result = Get-ADAgent -Identity 'claude-assistant-01'
            $result.AuthorizedTools | Should -Match 'microsoft.powershell'
        }

        It 'Should handle multiple tools' {
            Grant-ADAgentToolAccess -Identity 'data-processor-01' -Tool 'microsoft.word', 'microsoft.powershell'

            $result = Get-ADAgent -Identity 'data-processor-01'
            $result.AuthorizedTools | Should -Match 'microsoft.word'
            $result.AuthorizedTools | Should -Match 'microsoft.powershell'
        }

        It 'Should not duplicate existing grants' {
            # Grant same tool twice
            Grant-ADAgentToolAccess -Identity 'claude-assistant-01' -Tool 'microsoft.word'
            Grant-ADAgentToolAccess -Identity 'claude-assistant-01' -Tool 'microsoft.word'

            $result = Get-ADAgent -Identity 'claude-assistant-01'
            ($result.AuthorizedTools | Where-Object { $_ -match 'microsoft.word' }).Count | Should -Be 1
        }
    }

    Context 'Revoke-ADAgentToolAccess' {

        It 'Should remove tool from authorized list' {
            # First ensure tool is granted
            Grant-ADAgentToolAccess -Identity 'claude-assistant-01' -Tool 'microsoft.powershell'

            Revoke-ADAgentToolAccess -Identity 'claude-assistant-01' -Tool 'microsoft.powershell'

            $result = Get-ADAgent -Identity 'claude-assistant-01'
            $result.AuthorizedTools | Should -Not -Match 'microsoft.powershell'
        }

        It 'Should add to denied list when -Deny specified' {
            Revoke-ADAgentToolAccess -Identity 'claude-assistant-01' -Tool 'microsoft.gpo' -Deny

            $result = Get-ADAgent -Identity 'claude-assistant-01'
            $result.DeniedTools | Should -Match 'microsoft.gpo'
        }

        It 'Should revoke all tools with -All' {
            # Grant some tools first
            Grant-ADAgentToolAccess -Identity 'data-processor-01' -Tool 'microsoft.word', 'microsoft.powershell'

            Revoke-ADAgentToolAccess -Identity 'data-processor-01' -All

            $result = Get-ADAgent -Identity 'data-processor-01'
            $result.AuthorizedTools | Should -BeNullOrEmpty
        }
    }

    Context 'Test-ADAgentToolAccess' {

        It 'Should return allowed for directly authorized tool' {
            Grant-ADAgentToolAccess -Identity 'claude-assistant-01' -Tool 'microsoft.powershell'

            $result = Test-ADAgentToolAccess -Identity 'claude-assistant-01' -Tool 'microsoft.powershell'

            $result.Allowed | Should -Be $true
            $result.Reason | Should -Be 'DirectGrant'
        }

        It 'Should return denied for explicitly denied tool' {
            Revoke-ADAgentToolAccess -Identity 'claude-assistant-01' -Tool 'microsoft.gpo' -Deny

            $result = Test-ADAgentToolAccess -Identity 'claude-assistant-01' -Tool 'microsoft.gpo'

            $result.Allowed | Should -Be $false
            $result.Reason | Should -Be 'ExplicitDeny'
        }

        It 'Should return allowed when trust level is sufficient' {
            # Agent trust level 2, tool requires 1
            $result = Test-ADAgentToolAccess -Identity 'claude-assistant-01' -Tool 'microsoft.word'

            $result.Allowed | Should -Be $true
            # Could be DirectGrant or TrustLevelSufficient depending on prior state
        }

        It 'Should return denied when trust level is insufficient' {
            # Agent trust level 1, tool requires 4
            $result = Test-ADAgentToolAccess -Identity 'data-processor-01' -Tool 'microsoft.gpo'

            $result.Allowed | Should -Be $false
            $result.Reason | Should -Match 'TrustLevel|ExplicitDeny'
        }

        It 'Should include agent and tool trust levels in result' {
            $result = Test-ADAgentToolAccess -Identity 'claude-assistant-01' -Tool 'microsoft.powershell'

            $result.AgentTrustLevel | Should -Be 2
            $result.ToolRequiredTrustLevel | Should -Be 2
        }

        It 'Should include tool constraints in result' {
            $result = Test-ADAgentToolAccess -Identity 'claude-assistant-01' -Tool 'microsoft.powershell'

            $result.Constraints | Should -Not -BeNullOrEmpty
        }
    }
}
