#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for Sandbox cmdlets.
#>

Describe 'Sandbox Cmdlets' {

    BeforeAll {
        # Import mock helpers
        . "$PSScriptRoot\Mocks\ADMocks.ps1"
    }

    BeforeEach {
        Reset-MockData
        Initialize-ADMocks
    }

    Context 'Get-ADAgentSandbox' {

        It 'Should return sandbox by identity' {
            $result = Get-ADAgentSandbox -Identity 'sandbox-prod-001'

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'sandbox-prod-001'
        }

        It 'Should return sandbox properties correctly' {
            $result = Get-ADAgentSandbox -Identity 'sandbox-prod-001'

            $result.SecurityProfile | Should -Be 'bwrap'
            $result.Status | Should -Be 'active'
            $result.Endpoint | Should -Be 'https://sandbox-001.corp.contoso.com:8443'
        }

        It 'Should return all sandboxes when no identity specified' {
            $results = Get-ADAgentSandbox

            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context 'New-ADAgentSandbox' {

        It 'Should create sandbox with required parameters' {
            $result = New-ADAgentSandbox -Name 'test-sandbox-01'

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'test-sandbox-01'
        }

        It 'Should set security profile when specified' {
            $result = New-ADAgentSandbox -Name 'test-sandbox-02' -SecurityProfile 'hyperv'

            $result.SecurityProfile | Should -Be 'hyperv'
        }

        It 'Should set endpoint when specified' {
            $result = New-ADAgentSandbox -Name 'test-sandbox-03' -Endpoint 'https://sandbox:8443'

            $result.Endpoint | Should -Be 'https://sandbox:8443'
        }

        It 'Should set default status to standby' {
            $result = New-ADAgentSandbox -Name 'test-sandbox-04'

            $result.Status | Should -Be 'standby'
        }

        It 'Should create disabled sandbox by default' {
            $result = New-ADAgentSandbox -Name 'test-sandbox-05'

            $result.Enabled | Should -Be $false
        }

        It 'Should create enabled sandbox when specified' {
            $result = New-ADAgentSandbox -Name 'test-sandbox-06' -Enabled

            $result.Enabled | Should -Be $true
        }
    }

    Context 'Set-ADAgentSandbox' {

        It 'Should modify status' {
            Set-ADAgentSandbox -Identity 'sandbox-prod-001' -Status 'standby'

            $result = Get-ADAgentSandbox -Identity 'sandbox-prod-001'
            $result.Status | Should -Be 'standby'
        }

        It 'Should modify endpoint' {
            Set-ADAgentSandbox -Identity 'sandbox-prod-001' -Endpoint 'https://new-endpoint:9443'

            $result = Get-ADAgentSandbox -Identity 'sandbox-prod-001'
            $result.Endpoint | Should -Be 'https://new-endpoint:9443'
        }

        It 'Should return modified sandbox with PassThru' {
            $result = Set-ADAgentSandbox -Identity 'sandbox-prod-001' -Status 'terminated' -PassThru

            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be 'terminated'
        }
    }

    Context 'Remove-ADAgentSandbox' {

        It 'Should remove sandbox' {
            Remove-ADAgentSandbox -Identity 'sandbox-prod-001' -Confirm:$false

            { Get-ADAgentSandbox -Identity 'sandbox-prod-001' } | Should -Throw
        }
    }
}
