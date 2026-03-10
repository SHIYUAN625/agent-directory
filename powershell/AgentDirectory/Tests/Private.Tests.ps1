#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for private helper functions.
#>

Describe 'Private Helper Functions' {

    BeforeAll {
        # Import mock helpers
        . "$PSScriptRoot\Mocks\ADMocks.ps1"

        # Initialize mocks
        Initialize-ADMocks
    }

    BeforeEach {
        Reset-MockData
    }

    Context 'Get-AgentDistinguishedName' {

        It 'Should return DN when given a DN' {
            $dn = "CN=claude-assistant-01,CN=Agents,CN=System,DC=corp,DC=contoso,DC=com"
            $result = Get-AgentDistinguishedName -Identity $dn
            $result | Should -Be $dn
        }

        It 'Should find agent by name' {
            $result = Get-AgentDistinguishedName -Identity 'claude-assistant-01'
            $result | Should -Match 'claude-assistant-01'
        }

        It 'Should throw for non-existent agent' {
            { Get-AgentDistinguishedName -Identity 'nonexistent-agent' } | Should -Throw
        }
    }

    Context 'Get-ToolDistinguishedName' {

        It 'Should return DN when given a DN' {
            $dn = "CN=microsoft.powershell,CN=Agent Tools,CN=System,DC=corp,DC=contoso,DC=com"
            $result = Get-ToolDistinguishedName -Identity $dn
            $result | Should -Be $dn
        }

        It 'Should find tool by identifier' {
            $result = Get-ToolDistinguishedName -Identity 'microsoft.powershell'
            $result | Should -Match 'microsoft.powershell'
        }

        It 'Should throw for non-existent tool' {
            { Get-ToolDistinguishedName -Identity 'nonexistent-tool' } | Should -Throw
        }
    }

    Context 'Test-AgentTrustLevel' {

        It 'Should return true when agent level equals required' {
            $result = Test-AgentTrustLevel -AgentTrustLevel 2 -RequiredLevel 2
            $result | Should -Be $true
        }

        It 'Should return true when agent level exceeds required' {
            $result = Test-AgentTrustLevel -AgentTrustLevel 4 -RequiredLevel 2
            $result | Should -Be $true
        }

        It 'Should return false when agent level is below required' {
            $result = Test-AgentTrustLevel -AgentTrustLevel 1 -RequiredLevel 3
            $result | Should -Be $false
        }

        It 'Should handle level 0 correctly' {
            Test-AgentTrustLevel -AgentTrustLevel 0 -RequiredLevel 0 | Should -Be $true
            Test-AgentTrustLevel -AgentTrustLevel 0 -RequiredLevel 1 | Should -Be $false
        }
    }

    Context 'Get-AgentTrustLevelName' {

        It 'Should return Untrusted for level 0' {
            Get-AgentTrustLevelName -Level 0 | Should -Be 'Untrusted'
        }

        It 'Should return Basic for level 1' {
            Get-AgentTrustLevelName -Level 1 | Should -Be 'Basic'
        }

        It 'Should return Standard for level 2' {
            Get-AgentTrustLevelName -Level 2 | Should -Be 'Standard'
        }

        It 'Should return Elevated for level 3' {
            Get-AgentTrustLevelName -Level 3 | Should -Be 'Elevated'
        }

        It 'Should return System for level 4' {
            Get-AgentTrustLevelName -Level 4 | Should -Be 'System'
        }

        It 'Should handle unknown levels' {
            Get-AgentTrustLevelName -Level 99 | Should -Match 'Unknown'
        }
    }

    Context 'Test-ValidAgentType' {

        It 'Should accept valid agent types' {
            Test-ValidAgentType -Type 'autonomous' | Should -Be $true
            Test-ValidAgentType -Type 'assistant' | Should -Be $true
            Test-ValidAgentType -Type 'tool' | Should -Be $true
            Test-ValidAgentType -Type 'orchestrator' | Should -Be $true
        }

        It 'Should be case-insensitive' {
            Test-ValidAgentType -Type 'ASSISTANT' | Should -Be $true
            Test-ValidAgentType -Type 'Assistant' | Should -Be $true
        }

        It 'Should reject invalid agent types' {
            Test-ValidAgentType -Type 'invalid' | Should -Be $false
            Test-ValidAgentType -Type 'bot' | Should -Be $false
        }
    }

    Context 'Test-ValidToolCategory' {

        It 'Should accept valid tool categories' {
            Test-ValidToolCategory -Category 'shell' | Should -Be $true
            Test-ValidToolCategory -Category 'office' | Should -Be $true
            Test-ValidToolCategory -Category 'management' | Should -Be $true
            Test-ValidToolCategory -Category 'development' | Should -Be $true
            Test-ValidToolCategory -Category 'network' | Should -Be $true
            Test-ValidToolCategory -Category 'security' | Should -Be $true
            Test-ValidToolCategory -Category 'filesystem' | Should -Be $true
            Test-ValidToolCategory -Category 'data' | Should -Be $true
        }

        It 'Should be case-insensitive' {
            Test-ValidToolCategory -Category 'SHELL' | Should -Be $true
            Test-ValidToolCategory -Category 'Shell' | Should -Be $true
        }

        It 'Should reject invalid categories' {
            Test-ValidToolCategory -Category 'invalid' | Should -Be $false
            Test-ValidToolCategory -Category 'application' | Should -Be $false
        }
    }

    Context 'ConvertTo-AgentObject' {

        It 'Should convert AD object to Agent object' {
            $adObject = Get-MockAgent -Identity 'claude-assistant-01'
            $result = ConvertTo-AgentObject -ADObject $adObject

            $result.Name | Should -Be 'claude-assistant-01'
            $result.Type | Should -Be 'assistant'
            $result.TrustLevel | Should -Be 2
            $result.TrustLevelName | Should -Be 'Standard'
            $result.Model | Should -Be 'claude-opus-4-5'
        }

        It 'Should include Sandboxes property' {
            $adObject = Get-MockAgent -Identity 'claude-assistant-01'
            $result = ConvertTo-AgentObject -ADObject $adObject

            $result.Sandboxes | Should -Not -BeNullOrEmpty
        }

        It 'Should include type name' {
            $adObject = Get-MockAgent -Identity 'claude-assistant-01'
            $result = ConvertTo-AgentObject -ADObject $adObject

            $result.PSObject.TypeNames | Should -Contain 'AgentDirectory.Agent'
        }

        It 'Should calculate Enabled status from userAccountControl' {
            $enabledAgent = Get-MockAgent -Identity 'claude-assistant-01'
            $disabledAgent = Get-MockAgent -Identity 'data-processor-01'

            $enabledResult = ConvertTo-AgentObject -ADObject $enabledAgent
            $disabledResult = ConvertTo-AgentObject -ADObject $disabledAgent

            $enabledResult.Enabled | Should -Be $true
            $disabledResult.Enabled | Should -Be $false
        }
    }

    Context 'ConvertTo-SandboxObject' {

        It 'Should convert AD object to Sandbox object' {
            $adObject = Get-MockSandbox -Identity 'sandbox-prod-001'
            $result = ConvertTo-SandboxObject -ADObject $adObject

            $result.Name | Should -Be 'sandbox-prod-001'
            $result.SecurityProfile | Should -Be 'bwrap'
            $result.Status | Should -Be 'active'
            $result.Endpoint | Should -Be 'https://sandbox-001.corp.contoso.com:8443'
        }

        It 'Should include type name' {
            $adObject = Get-MockSandbox -Identity 'sandbox-prod-001'
            $result = ConvertTo-SandboxObject -ADObject $adObject

            $result.PSObject.TypeNames | Should -Contain 'AgentDirectory.Sandbox'
        }

        It 'Should calculate Enabled status' {
            $adObject = Get-MockSandbox -Identity 'sandbox-prod-001'
            $result = ConvertTo-SandboxObject -ADObject $adObject

            $result.Enabled | Should -Be $true
        }
    }

    Context 'Get-SandboxDistinguishedName' {

        It 'Should return DN when given a DN' {
            $dn = "CN=sandbox-prod-001,CN=Agent Sandboxes,CN=System,DC=corp,DC=contoso,DC=com"
            $result = Get-SandboxDistinguishedName -Identity $dn
            $result | Should -Be $dn
        }

        It 'Should find sandbox by name' {
            $result = Get-SandboxDistinguishedName -Identity 'sandbox-prod-001'
            $result | Should -Match 'sandbox-prod-001'
        }

        It 'Should throw for non-existent sandbox' {
            { Get-SandboxDistinguishedName -Identity 'nonexistent-sandbox' } | Should -Throw
        }
    }

    Context 'Get-PolicyDistinguishedName' {

        It 'Should return DN when given a DN' {
            $dn = "CN=base-security,CN=Agent Policies,CN=System,DC=corp,DC=contoso,DC=com"
            $result = Get-PolicyDistinguishedName -Identity $dn
            $result | Should -Be $dn
        }

        It 'Should find policy by identifier' {
            $result = Get-PolicyDistinguishedName -Identity 'base-security'
            $result | Should -Match 'base-security'
        }

        It 'Should throw for non-existent policy' {
            { Get-PolicyDistinguishedName -Identity 'nonexistent-policy' } | Should -Throw
        }
    }

    Context 'Get-InstructionGPODistinguishedName' {

        It 'Should return DN when given a DN' {
            $dn = "CN=base-agent-instructions,CN=Agent Instructions,CN=System,DC=corp,DC=contoso,DC=com"
            $result = Get-InstructionGPODistinguishedName -Identity $dn
            $result | Should -Be $dn
        }

        It 'Should find GPO by name' {
            $result = Get-InstructionGPODistinguishedName -Identity 'base-agent-instructions'
            $result | Should -Match 'base-agent-instructions'
        }

        It 'Should throw for non-existent GPO' {
            { Get-InstructionGPODistinguishedName -Identity 'nonexistent-gpo' } | Should -Throw
        }
    }

    Context 'ConvertTo-PolicyObject' {

        It 'Should convert AD object to Policy object' {
            $adObject = Get-MockPolicy -Identity 'base-security'
            $result = ConvertTo-PolicyObject -ADObject $adObject

            $result.Identifier | Should -Be 'base-security'
            $result.Type | Should -Be 'security'
            $result.Priority | Should -Be 0
        }

        It 'Should include type name' {
            $adObject = Get-MockPolicy -Identity 'base-security'
            $result = ConvertTo-PolicyObject -ADObject $adObject

            $result.PSObject.TypeNames | Should -Contain 'AgentDirectory.Policy'
        }
    }

    Context 'ConvertTo-InstructionGPOObject' {

        It 'Should convert AD object to InstructionGPO object' {
            $adObject = Get-MockInstructionGPO -Identity 'base-agent-instructions'
            $result = ConvertTo-InstructionGPOObject -ADObject $adObject

            $result.DisplayName | Should -Be 'Base Agent Instructions'
            $result.Priority | Should -Be 0
            $result.MergeStrategy | Should -Be 'append'
        }

        It 'Should include type name' {
            $adObject = Get-MockInstructionGPO -Identity 'base-agent-instructions'
            $result = ConvertTo-InstructionGPOObject -ADObject $adObject

            $result.PSObject.TypeNames | Should -Contain 'AgentDirectory.InstructionGPO'
        }
    }

    Context 'ConvertTo-ToolObject' {

        It 'Should convert AD object to Tool object' {
            $adObject = Get-MockTool -Identity 'microsoft.powershell'
            $result = ConvertTo-ToolObject -ADObject $adObject

            $result.Identifier | Should -Be 'microsoft.powershell'
            $result.DisplayName | Should -Be 'PowerShell'
            $result.Category | Should -Be 'shell'
            $result.RiskLevel | Should -Be 4
            $result.RequiredTrustLevel | Should -Be 2
        }

        It 'Should include type name' {
            $adObject = Get-MockTool -Identity 'microsoft.powershell'
            $result = ConvertTo-ToolObject -ADObject $adObject

            $result.PSObject.TypeNames | Should -Contain 'AgentDirectory.Tool'
        }

        It 'Should include constraints array' {
            $adObject = Get-MockTool -Identity 'microsoft.powershell'
            $result = ConvertTo-ToolObject -ADObject $adObject

            $result.Constraints | Should -Contain 'ExecutionPolicy=RemoteSigned'
            $result.Constraints | Should -Contain 'TranscriptLogging=Required'
        }
    }
}
