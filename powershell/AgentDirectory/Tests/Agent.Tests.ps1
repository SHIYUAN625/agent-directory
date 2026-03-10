#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for Agent cmdlets.
#>

Describe 'Agent Cmdlets' {

    BeforeAll {
        # Import mock helpers
        . "$PSScriptRoot\Mocks\ADMocks.ps1"
    }

    BeforeEach {
        Reset-MockData
        Initialize-ADMocks
    }

    Context 'Get-ADAgent' {

        It 'Should return agent by identity' {
            $result = Get-ADAgent -Identity 'claude-assistant-01'

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'claude-assistant-01'
        }

        It 'Should return agent properties correctly' {
            $result = Get-ADAgent -Identity 'claude-assistant-01'

            $result.Type | Should -Be 'assistant'
            $result.TrustLevel | Should -Be 2
            $result.Model | Should -Be 'claude-opus-4-5'
        }

        It 'Should return all agents when no identity specified' {
            $results = Get-ADAgent

            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -BeGreaterOrEqual 2
        }

        It 'Should filter by Type' {
            $results = Get-ADAgent -Type 'assistant'

            $results | Should -Not -BeNullOrEmpty
            $results | ForEach-Object {
                $_.Type | Should -Be 'assistant'
            }
        }

        It 'Should filter by TrustLevel' {
            $results = Get-ADAgent -TrustLevel 2

            $results | Should -Not -BeNullOrEmpty
            $results | ForEach-Object {
                $_.TrustLevel | Should -Be 2
            }
        }
    }

    Context 'New-ADAgent' {

        It 'Should create agent with required parameters' {
            $result = New-ADAgent -Name 'test-agent-01' -Type 'assistant'

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'test-agent-01'
            $result.Type | Should -Be 'assistant'
        }

        It 'Should set default trust level to 1' {
            $result = New-ADAgent -Name 'test-agent-02' -Type 'tool'

            $result.TrustLevel | Should -Be 1
        }

        It 'Should accept custom trust level' {
            $result = New-ADAgent -Name 'test-agent-03' -Type 'orchestrator' -TrustLevel 3

            $result.TrustLevel | Should -Be 3
        }

        It 'Should set owner when specified' {
            $owner = "CN=Test Owner,OU=Users,DC=corp,DC=contoso,DC=com"
            $result = New-ADAgent -Name 'test-agent-04' -Type 'assistant' -Owner $owner

            $result.Owner | Should -Be $owner
        }

        It 'Should set model when specified' {
            $result = New-ADAgent -Name 'test-agent-05' -Type 'assistant' -Model 'gpt-4-turbo'

            $result.Model | Should -Be 'gpt-4-turbo'
        }

        It 'Should set capabilities when specified' {
            $caps = @('urn:agent:capability:read', 'urn:agent:capability:write')
            $result = New-ADAgent -Name 'test-agent-06' -Type 'tool' -Capabilities $caps

            $result.Capabilities | Should -Contain 'urn:agent:capability:read'
            $result.Capabilities | Should -Contain 'urn:agent:capability:write'
        }

        It 'Should create disabled agent by default' {
            $result = New-ADAgent -Name 'test-agent-07' -Type 'assistant'

            $result.Enabled | Should -Be $false
        }

        It 'Should create enabled agent when specified' {
            $result = New-ADAgent -Name 'test-agent-08' -Type 'assistant' -Enabled

            $result.Enabled | Should -Be $true
        }

        It 'Should reject invalid agent type' {
            { New-ADAgent -Name 'test-invalid' -Type 'invalid' } | Should -Throw
        }

        It 'Should reject trust level out of range' {
            { New-ADAgent -Name 'test-invalid' -Type 'assistant' -TrustLevel 5 } | Should -Throw
            { New-ADAgent -Name 'test-invalid' -Type 'assistant' -TrustLevel -1 } | Should -Throw
        }
    }

    Context 'Set-ADAgent' {

        It 'Should modify trust level' {
            Set-ADAgent -Identity 'claude-assistant-01' -TrustLevel 3

            $result = Get-ADAgent -Identity 'claude-assistant-01'
            $result.TrustLevel | Should -Be 3
        }

        It 'Should modify type' {
            Set-ADAgent -Identity 'claude-assistant-01' -Type 'orchestrator'

            $result = Get-ADAgent -Identity 'claude-assistant-01'
            $result.Type | Should -Be 'orchestrator'
        }

        It 'Should enable agent' {
            Set-ADAgent -Identity 'data-processor-01' -Enabled $true

            $result = Get-ADAgent -Identity 'data-processor-01'
            $result.Enabled | Should -Be $true
        }

        It 'Should disable agent' {
            Set-ADAgent -Identity 'claude-assistant-01' -Enabled $false

            $result = Get-ADAgent -Identity 'claude-assistant-01'
            $result.Enabled | Should -Be $false
        }

        It 'Should return modified agent with PassThru' {
            $result = Set-ADAgent -Identity 'claude-assistant-01' -TrustLevel 4 -PassThru

            $result | Should -Not -BeNullOrEmpty
            $result.TrustLevel | Should -Be 4
        }

        It 'Should add capabilities' {
            Set-ADAgent -Identity 'claude-assistant-01' -AddCapabilities 'urn:agent:capability:new-cap'

            $result = Get-ADAgent -Identity 'claude-assistant-01'
            $result.Capabilities | Should -Contain 'urn:agent:capability:new-cap'
        }
    }

    Context 'Remove-ADAgent' {

        It 'Should remove agent' {
            Remove-ADAgent -Identity 'data-processor-01' -Confirm:$false

            { Get-ADAgent -Identity 'data-processor-01' } | Should -Throw
        }

        It 'Should support pipeline input' {
            $agent = Get-ADAgent -Identity 'data-processor-01'
            $agent | Remove-ADAgent -Confirm:$false

            { Get-ADAgent -Identity 'data-processor-01' } | Should -Throw
        }
    }

    Context 'Install-ADAgentSPN' {

        It 'Should add AGENT/ SPN' {
            # Start with agent without SPNs
            $Script:MockAgents['data-processor-01'].servicePrincipalName = @()

            Install-ADAgentSPN -Identity 'data-processor-01'

            $result = Get-ADAgent -Identity 'data-processor-01'
            $result.ServicePrincipalNames | Should -Contain 'AGENT/data-processor-01'
        }

        It 'Should add HOST/ SPN for NTLM fallback' {
            $Script:MockAgents['data-processor-01'].servicePrincipalName = @()

            Install-ADAgentSPN -Identity 'data-processor-01'

            $result = Get-ADAgent -Identity 'data-processor-01'
            $result.ServicePrincipalNames | Should -Match 'HOST/'
        }

        It 'Should not duplicate existing SPNs' {
            $initialSpns = @('AGENT/claude-assistant-01', 'HOST/claude-assistant-01')
            $Script:MockAgents['claude-assistant-01'].servicePrincipalName = $initialSpns

            Install-ADAgentSPN -Identity 'claude-assistant-01'

            $result = Get-ADAgent -Identity 'claude-assistant-01'
            ($result.ServicePrincipalNames | Where-Object { $_ -eq 'AGENT/claude-assistant-01' }).Count | Should -Be 1
        }

        It 'Should add custom service classes' {
            $Script:MockAgents['data-processor-01'].servicePrincipalName = @()

            Install-ADAgentSPN -Identity 'data-processor-01' -ServiceClass 'HTTP'

            $result = Get-ADAgent -Identity 'data-processor-01'
            $result.ServicePrincipalNames | Should -Match 'HTTP/'
        }
    }

    Context 'Test-ADAgentAuthentication' {

        It 'Should pass Kerberos test when SPNs exist' {
            $result = Test-ADAgentAuthentication -Identity 'claude-assistant-01' -AuthType Kerberos

            $result.Success | Should -Be $true
            $result.AuthType | Should -Be 'Kerberos'
        }

        It 'Should fail Kerberos test when no SPNs' {
            $Script:MockAgents['data-processor-01'].servicePrincipalName = @()

            $result = Test-ADAgentAuthentication -Identity 'data-processor-01' -AuthType Kerberos

            $result.Success | Should -Be $false
            $result.Message | Should -Match 'SPN'
        }

        It 'Should pass NTLM test for enabled agent' {
            $result = Test-ADAgentAuthentication -Identity 'claude-assistant-01' -AuthType NTLM

            $result.Success | Should -Be $true
        }

        It 'Should fail for disabled agent' {
            $result = Test-ADAgentAuthentication -Identity 'data-processor-01' -AuthType Kerberos

            $result.Success | Should -Be $false
            $result.Message | Should -Match 'disabled'
        }
    }
}
