# Mock data and helper functions for Active Directory cmdlet mocking
# Used by Pester tests to simulate AD environment

# Sample domain configuration
$Script:MockDomainDN = 'DC=corp,DC=contoso,DC=com'
$Script:MockAgentContainerDN = "CN=Agents,CN=System,$Script:MockDomainDN"
$Script:MockToolContainerDN = "CN=Agent Tools,CN=System,$Script:MockDomainDN"
$Script:MockSandboxContainerDN = "CN=Agent Sandboxes,CN=System,$Script:MockDomainDN"
$Script:MockPolicyContainerDN = "CN=Agent Policies,CN=System,$Script:MockDomainDN"
$Script:MockInstructionGPOContainerDN = "CN=Agent Instructions,CN=System,$Script:MockDomainDN"

# Sample agent data
$Script:MockAgents = @{
    'claude-assistant-01' = @{
        Name = 'claude-assistant-01'
        DistinguishedName = "CN=claude-assistant-01,$Script:MockAgentContainerDN"
        ObjectClass = 'msDS-Agent'
        ObjectGUID = [guid]::NewGuid()
        ObjectSid = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
        sAMAccountName = 'claude-assistant-01'
        userAccountControl = 512  # NORMAL_ACCOUNT
        'msDS-AgentType' = 'assistant'
        'msDS-AgentTrustLevel' = 2
        'msDS-AgentModel' = 'claude-opus-4-5'
        'msDS-AgentOwner' = "CN=John Smith,OU=Users,$Script:MockDomainDN"
        'msDS-AgentCapabilities' = @('urn:agent:capability:code-generation', 'urn:agent:capability:document-analysis')
        'msDS-AgentSandbox' = @("CN=sandbox-prod-001,$Script:MockSandboxContainerDN")
        'msDS-AgentAuthorizedTools' = @("CN=microsoft.word,$Script:MockToolContainerDN")
        'msDS-AgentDeniedTools' = @()
        'msDS-AgentPolicies' = @('base-security', 'type-worker')
        'msDS-AgentInstructionGPOs' = @("CN=base-agent-instructions,$Script:MockInstructionGPOContainerDN")
        servicePrincipalName = @('AGENT/claude-assistant-01', 'HOST/claude-assistant-01')
        Description = 'Test Claude assistant'
        whenCreated = (Get-Date).AddDays(-30)
        whenChanged = (Get-Date).AddDays(-1)
    }
    'data-processor-01' = @{
        Name = 'data-processor-01'
        DistinguishedName = "CN=data-processor-01,$Script:MockAgentContainerDN"
        ObjectClass = 'msDS-Agent'
        ObjectGUID = [guid]::NewGuid()
        ObjectSid = 'S-1-5-21-1234567890-1234567890-1234567890-1002'
        sAMAccountName = 'data-processor-01'
        userAccountControl = 514  # NORMAL_ACCOUNT + ACCOUNTDISABLE
        'msDS-AgentType' = 'tool'
        'msDS-AgentTrustLevel' = 1
        'msDS-AgentModel' = 'custom-model-v1'
        'msDS-AgentOwner' = "CN=Data Team,OU=Groups,$Script:MockDomainDN"
        'msDS-AgentCapabilities' = @('urn:agent:capability:data-transform')
        'msDS-AgentSandbox' = @()
        'msDS-AgentAuthorizedTools' = @()
        'msDS-AgentDeniedTools' = @()
        'msDS-AgentPolicies' = @()
        'msDS-AgentInstructionGPOs' = @()
        servicePrincipalName = @()
        Description = 'Data processing agent'
        whenCreated = (Get-Date).AddDays(-15)
        whenChanged = (Get-Date).AddDays(-5)
    }
}

# Sample policy data
$Script:MockPolicies = @{
    'base-security' = @{
        Name = 'base-security'
        DistinguishedName = "CN=base-security,$Script:MockPolicyContainerDN"
        ObjectClass = 'msDS-AgentPolicy'
        'msDS-PolicyIdentifier' = 'base-security'
        'msDS-PolicyType' = 'security'
        'msDS-PolicyPriority' = 0
        'msDS-PolicyPath' = 'AgentPolicies/base-security/policy.json'
        'msDS-PolicyAppliesToTypes' = @()
        'msDS-PolicyAppliesToTrustLevels' = @()
        'msDS-PolicyEnabled' = $true
        'msDS-PolicyVersion' = '1.0.0'
        Description = 'Base security policy applied to all agents'
        whenCreated = (Get-Date).AddDays(-60)
        whenChanged = (Get-Date).AddDays(-60)
    }
    'type-worker' = @{
        Name = 'type-worker'
        DistinguishedName = "CN=type-worker,$Script:MockPolicyContainerDN"
        ObjectClass = 'msDS-AgentPolicy'
        'msDS-PolicyIdentifier' = 'type-worker'
        'msDS-PolicyType' = 'behavior'
        'msDS-PolicyPriority' = 100
        'msDS-PolicyPath' = 'AgentPolicies/type-worker/policy.json'
        'msDS-PolicyAppliesToTypes' = @('autonomous', 'assistant')
        'msDS-PolicyAppliesToTrustLevels' = @()
        'msDS-PolicyEnabled' = $true
        'msDS-PolicyVersion' = '1.0.0'
        Description = 'Policy for worker agents'
        whenCreated = (Get-Date).AddDays(-60)
        whenChanged = (Get-Date).AddDays(-60)
    }
    'trust-elevated' = @{
        Name = 'trust-elevated'
        DistinguishedName = "CN=trust-elevated,$Script:MockPolicyContainerDN"
        ObjectClass = 'msDS-AgentPolicy'
        'msDS-PolicyIdentifier' = 'trust-elevated'
        'msDS-PolicyType' = 'security'
        'msDS-PolicyPriority' = 150
        'msDS-PolicyPath' = 'AgentPolicies/trust-elevated/policy.json'
        'msDS-PolicyAppliesToTypes' = @()
        'msDS-PolicyAppliesToTrustLevels' = @(3, 4)
        'msDS-PolicyEnabled' = $true
        'msDS-PolicyVersion' = '1.0.0'
        Description = 'Expanded permissions for elevated trust agents'
        whenCreated = (Get-Date).AddDays(-60)
        whenChanged = (Get-Date).AddDays(-60)
    }
}

# Sample instruction GPO data
$Script:MockInstructionGPOs = @{
    'base-agent-instructions' = @{
        Name = 'base-agent-instructions'
        DistinguishedName = "CN=base-agent-instructions,$Script:MockInstructionGPOContainerDN"
        ObjectClass = 'msDS-AgentInstructionGPO'
        'msDS-GPODisplayName' = 'Base Agent Instructions'
        'msDS-GPOInstructionPath' = 'AgentInstructions/base-agent-instructions/instructions.md'
        'msDS-GPOPriority' = 0
        'msDS-GPOMergeStrategy' = 'append'
        'msDS-GPOAppliesToTypes' = @()
        'msDS-GPOAppliesToTrustLevels' = @()
        'msDS-GPOAppliesToGroups' = @()
        'msDS-GPOEnabled' = $true
        'msDS-GPOVersion' = '1.0.0'
        Description = 'Foundation system prompt applied to every agent'
        whenCreated = (Get-Date).AddDays(-60)
        whenChanged = (Get-Date).AddDays(-60)
    }
    'type-assistant-instructions' = @{
        Name = 'type-assistant-instructions'
        DistinguishedName = "CN=type-assistant-instructions,$Script:MockInstructionGPOContainerDN"
        ObjectClass = 'msDS-AgentInstructionGPO'
        'msDS-GPODisplayName' = 'Assistant Agent Instructions'
        'msDS-GPOInstructionPath' = 'AgentInstructions/type-assistant-instructions/instructions.md'
        'msDS-GPOPriority' = 100
        'msDS-GPOMergeStrategy' = 'append'
        'msDS-GPOAppliesToTypes' = @('assistant')
        'msDS-GPOAppliesToTrustLevels' = @()
        'msDS-GPOAppliesToGroups' = @()
        'msDS-GPOEnabled' = $true
        'msDS-GPOVersion' = '1.0.0'
        Description = 'Instructions for interactive assistant agents'
        whenCreated = (Get-Date).AddDays(-60)
        whenChanged = (Get-Date).AddDays(-60)
    }
    'trust-elevated-instructions' = @{
        Name = 'trust-elevated-instructions'
        DistinguishedName = "CN=trust-elevated-instructions,$Script:MockInstructionGPOContainerDN"
        ObjectClass = 'msDS-AgentInstructionGPO'
        'msDS-GPODisplayName' = 'Elevated Trust Instructions'
        'msDS-GPOInstructionPath' = 'AgentInstructions/trust-elevated-instructions/instructions.md'
        'msDS-GPOPriority' = 200
        'msDS-GPOMergeStrategy' = 'append'
        'msDS-GPOAppliesToTypes' = @()
        'msDS-GPOAppliesToTrustLevels' = @(3, 4)
        'msDS-GPOAppliesToGroups' = @()
        'msDS-GPOEnabled' = $true
        'msDS-GPOVersion' = '1.0.0'
        Description = 'Additional instructions for elevated-trust agents'
        whenCreated = (Get-Date).AddDays(-60)
        whenChanged = (Get-Date).AddDays(-60)
    }
}

# Sample sandbox data
$Script:MockSandboxes = @{
    'sandbox-prod-001' = @{
        Name = 'sandbox-prod-001'
        DistinguishedName = "CN=sandbox-prod-001,$Script:MockSandboxContainerDN"
        ObjectClass = 'msDS-AgentSandbox'
        ObjectGUID = [guid]::NewGuid()
        ObjectSid = 'S-1-5-21-1234567890-1234567890-1234567890-2001'
        sAMAccountName = 'sandbox-prod-001$'
        userAccountControl = 4096  # WORKSTATION_TRUST_ACCOUNT
        'msDS-SandboxEndpoint' = 'https://sandbox-001.corp.contoso.com:8443'
        'msDS-SandboxAgents' = @("CN=claude-assistant-01,$Script:MockAgentContainerDN")
        'msDS-SandboxResourcePolicy' = '{"cpu": 4, "memory_gb": 16, "disk_gb": 100}'
        'msDS-SandboxNetworkPolicy' = '{"allow": ["*.corp.contoso.com"], "deny": ["*"]}'
        'msDS-SandboxSecurityProfile' = 'bwrap'
        'msDS-SandboxStatus' = 'active'
        servicePrincipalName = @('HOST/sandbox-prod-001', 'HOST/sandbox-prod-001.corp.contoso.com')
        Description = 'Production sandbox'
        whenCreated = (Get-Date).AddDays(-30)
        whenChanged = (Get-Date).AddDays(-1)
    }
}

# Sample tool data
$Script:MockTools = @{
    'microsoft.powershell' = @{
        Name = 'microsoft.powershell'
        DistinguishedName = "CN=microsoft.powershell,$Script:MockToolContainerDN"
        ObjectClass = 'msDS-AgentTool'
        'msDS-ToolIdentifier' = 'microsoft.powershell'
        'msDS-ToolDisplayName' = 'PowerShell'
        'msDS-ToolCategory' = 'shell'
        'msDS-ToolExecutable' = '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe'
        'msDS-ToolRiskLevel' = 4
        'msDS-ToolRequiredTrustLevel' = 2
        'msDS-ToolConstraints' = @('ExecutionPolicy=RemoteSigned', 'TranscriptLogging=Required')
        'msDS-ToolAuditRequired' = $true
        Description = 'Windows PowerShell'
        whenCreated = (Get-Date).AddDays(-60)
        whenChanged = (Get-Date).AddDays(-60)
    }
    'microsoft.word' = @{
        Name = 'microsoft.word'
        DistinguishedName = "CN=microsoft.word,$Script:MockToolContainerDN"
        ObjectClass = 'msDS-AgentTool'
        'msDS-ToolIdentifier' = 'microsoft.word'
        'msDS-ToolDisplayName' = 'Microsoft Word'
        'msDS-ToolCategory' = 'office'
        'msDS-ToolExecutable' = 'WINWORD.EXE'
        'msDS-ToolRiskLevel' = 2
        'msDS-ToolRequiredTrustLevel' = 1
        'msDS-ToolConstraints' = @('MacrosEnabled=False')
        'msDS-ToolAuditRequired' = $false
        Description = 'Microsoft Word document processor'
        whenCreated = (Get-Date).AddDays(-60)
        whenChanged = (Get-Date).AddDays(-60)
    }
    'microsoft.gpo' = @{
        Name = 'microsoft.gpo'
        DistinguishedName = "CN=microsoft.gpo,$Script:MockToolContainerDN"
        ObjectClass = 'msDS-AgentTool'
        'msDS-ToolIdentifier' = 'microsoft.gpo'
        'msDS-ToolDisplayName' = 'Group Policy Management'
        'msDS-ToolCategory' = 'management'
        'msDS-ToolExecutable' = 'GroupPolicy'
        'msDS-ToolRiskLevel' = 5
        'msDS-ToolRequiredTrustLevel' = 4
        'msDS-ToolConstraints' = @('GPOCreation=Prohibited', 'SecuritySettings=ReadOnly')
        'msDS-ToolAuditRequired' = $true
        Description = 'Group Policy Object management'
        whenCreated = (Get-Date).AddDays(-60)
        whenChanged = (Get-Date).AddDays(-60)
    }
}

function Get-MockAgent {
    <#
    .SYNOPSIS
        Returns mock agent data for testing.
    #>
    param(
        [string]$Identity
    )

    if ($Identity -and $Script:MockAgents.ContainsKey($Identity)) {
        return [PSCustomObject]$Script:MockAgents[$Identity]
    }
    elseif ($Identity) {
        # Try to find by DN
        foreach ($agent in $Script:MockAgents.Values) {
            if ($agent.DistinguishedName -eq $Identity) {
                return [PSCustomObject]$agent
            }
        }
        return $null
    }
    else {
        return $Script:MockAgents.Values | ForEach-Object { [PSCustomObject]$_ }
    }
}

function Get-MockSandbox {
    <#
    .SYNOPSIS
        Returns mock sandbox data for testing.
    #>
    param(
        [string]$Identity
    )

    if ($Identity -and $Script:MockSandboxes.ContainsKey($Identity)) {
        return [PSCustomObject]$Script:MockSandboxes[$Identity]
    }
    elseif ($Identity) {
        foreach ($sandbox in $Script:MockSandboxes.Values) {
            if ($sandbox.DistinguishedName -eq $Identity) {
                return [PSCustomObject]$sandbox
            }
        }
        return $null
    }
    else {
        return $Script:MockSandboxes.Values | ForEach-Object { [PSCustomObject]$_ }
    }
}

function Get-MockTool {
    <#
    .SYNOPSIS
        Returns mock tool data for testing.
    #>
    param(
        [string]$Identity
    )

    if ($Identity -and $Script:MockTools.ContainsKey($Identity)) {
        return [PSCustomObject]$Script:MockTools[$Identity]
    }
    elseif ($Identity) {
        # Try to find by DN
        foreach ($tool in $Script:MockTools.Values) {
            if ($tool.DistinguishedName -eq $Identity -or
                $tool.'msDS-ToolIdentifier' -eq $Identity) {
                return [PSCustomObject]$tool
            }
        }
        return $null
    }
    else {
        return $Script:MockTools.Values | ForEach-Object { [PSCustomObject]$_ }
    }
}

function Get-MockPolicy {
    <#
    .SYNOPSIS
        Returns mock policy data for testing.
    #>
    param(
        [string]$Identity
    )

    if ($Identity -and $Script:MockPolicies.ContainsKey($Identity)) {
        return [PSCustomObject]$Script:MockPolicies[$Identity]
    }
    elseif ($Identity) {
        foreach ($policy in $Script:MockPolicies.Values) {
            if ($policy.DistinguishedName -eq $Identity -or
                $policy.'msDS-PolicyIdentifier' -eq $Identity) {
                return [PSCustomObject]$policy
            }
        }
        return $null
    }
    else {
        return $Script:MockPolicies.Values | ForEach-Object { [PSCustomObject]$_ }
    }
}

function Get-MockInstructionGPO {
    <#
    .SYNOPSIS
        Returns mock instruction GPO data for testing.
    #>
    param(
        [string]$Identity
    )

    if ($Identity -and $Script:MockInstructionGPOs.ContainsKey($Identity)) {
        return [PSCustomObject]$Script:MockInstructionGPOs[$Identity]
    }
    elseif ($Identity) {
        foreach ($gpo in $Script:MockInstructionGPOs.Values) {
            if ($gpo.DistinguishedName -eq $Identity -or
                $gpo.'msDS-GPODisplayName' -eq $Identity) {
                return [PSCustomObject]$gpo
            }
        }
        return $null
    }
    else {
        return $Script:MockInstructionGPOs.Values | ForEach-Object { [PSCustomObject]$_ }
    }
}

function New-MockADObject {
    <#
    .SYNOPSIS
        Creates a mock AD object for testing.
    #>
    param(
        [hashtable]$Properties
    )

    return [PSCustomObject]$Properties
}

function Initialize-ADMocks {
    <#
    .SYNOPSIS
        Sets up Pester mocks for AD cmdlets.
    #>

    # Mock Get-ADDomain
    Mock Get-ADDomain {
        return [PSCustomObject]@{
            DistinguishedName = $Script:MockDomainDN
            DNSRoot = 'corp.contoso.com'
            NetBIOSName = 'CORP'
            PDCEmulator = 'DC01.corp.contoso.com'
        }
    }

    # Mock Get-ADForest
    Mock Get-ADForest {
        return [PSCustomObject]@{
            Name = 'corp.contoso.com'
            SchemaMaster = 'DC01.corp.contoso.com'
            RootDomain = 'corp.contoso.com'
        }
    }

    # Mock Get-ADObject for agents, sandboxes, and tools
    Mock Get-ADObject {
        param($Identity, $Filter, $LDAPFilter, $SearchBase, $SearchScope, $Properties)

        # Handle identity lookup
        if ($Identity) {
            $agent = Get-MockAgent -Identity $Identity
            if ($agent) { return $agent }

            $sandbox = Get-MockSandbox -Identity $Identity
            if ($sandbox) { return $sandbox }

            $tool = Get-MockTool -Identity $Identity
            if ($tool) { return $tool }

            $policy = Get-MockPolicy -Identity $Identity
            if ($policy) { return $policy }

            $gpo = Get-MockInstructionGPO -Identity $Identity
            if ($gpo) { return $gpo }

            return $null
        }

        # Handle LDAP filter
        if ($LDAPFilter -like "*msDS-AgentInstructionGPO*") {
            return Get-MockInstructionGPO
        }

        if ($LDAPFilter -like "*msDS-AgentPolicy*") {
            return Get-MockPolicy
        }

        if ($LDAPFilter -like "*msDS-AgentSandbox*") {
            return Get-MockSandbox
        }

        if ($LDAPFilter -like "*msDS-AgentTool*") {
            return Get-MockTool
        }

        if ($LDAPFilter -like "*msDS-Agent*") {
            return Get-MockAgent
        }

        return $null
    }

    # Mock New-ADUser (used for creating agents - agents inherit from user)
    Mock New-ADUser {
        param($Name, $SamAccountName, $Path, $Description, $OtherAttributes, $PassThru)

        $newAgent = @{
            Name = $Name
            DistinguishedName = "CN=$Name,$Path"
            sAMAccountName = $SamAccountName
            ObjectClass = 'msDS-Agent'
            ObjectGUID = [guid]::NewGuid()
            Description = $Description
            whenCreated = Get-Date
            whenChanged = Get-Date
        }

        foreach ($key in $OtherAttributes.Keys) {
            $newAgent[$key] = $OtherAttributes[$key]
        }

        $Script:MockAgents[$Name] = $newAgent

        if ($PassThru) {
            return [PSCustomObject]$newAgent
        }
    }

    # Mock New-ADComputer (used for creating sandboxes)
    Mock New-ADComputer {
        param($Name, $SamAccountName, $Path, $Description, $OtherAttributes, $PassThru, $Identity, $PrincipalsAllowedToDelegateToAccount)

        # Handle Set-ADComputer calls (delegation)
        if ($Identity) { return }

        $newSandbox = @{
            Name = $Name
            DistinguishedName = "CN=$Name,$Path"
            sAMAccountName = $SamAccountName
            ObjectClass = 'msDS-AgentSandbox'
            ObjectGUID = [guid]::NewGuid()
            Description = $Description
            whenCreated = Get-Date
            whenChanged = Get-Date
        }

        if ($OtherAttributes) {
            foreach ($key in $OtherAttributes.Keys) {
                $newSandbox[$key] = $OtherAttributes[$key]
            }
        }

        $Script:MockSandboxes[$Name] = $newSandbox

        if ($PassThru) {
            return [PSCustomObject]$newSandbox
        }
    }

    # Mock New-ADObject (used for creating tools, policies, instruction GPOs)
    Mock New-ADObject {
        param($Name, $Type, $Path, $Description, $OtherAttributes, $PassThru)

        if ($Type -eq 'msDS-AgentTool') {
            $newTool = @{
                Name = $Name
                DistinguishedName = "CN=$Name,$Path"
                ObjectClass = 'msDS-AgentTool'
                Description = $Description
                whenCreated = Get-Date
                whenChanged = Get-Date
            }

            foreach ($key in $OtherAttributes.Keys) {
                $newTool[$key] = $OtherAttributes[$key]
            }

            $Script:MockTools[$Name] = $newTool

            if ($PassThru) {
                return [PSCustomObject]$newTool
            }
        }
        elseif ($Type -eq 'msDS-AgentPolicy') {
            $newPolicy = @{
                Name = $Name
                DistinguishedName = "CN=$Name,$Path"
                ObjectClass = 'msDS-AgentPolicy'
                Description = $Description
                whenCreated = Get-Date
                whenChanged = Get-Date
            }

            foreach ($key in $OtherAttributes.Keys) {
                $newPolicy[$key] = $OtherAttributes[$key]
            }

            $Script:MockPolicies[$Name] = $newPolicy

            if ($PassThru) {
                return [PSCustomObject]$newPolicy
            }
        }
        elseif ($Type -eq 'msDS-AgentInstructionGPO') {
            $newGPO = @{
                Name = $Name
                DistinguishedName = "CN=$Name,$Path"
                ObjectClass = 'msDS-AgentInstructionGPO'
                Description = $Description
                whenCreated = Get-Date
                whenChanged = Get-Date
            }

            foreach ($key in $OtherAttributes.Keys) {
                $newGPO[$key] = $OtherAttributes[$key]
            }

            $Script:MockInstructionGPOs[$Name] = $newGPO

            if ($PassThru) {
                return [PSCustomObject]$newGPO
            }
        }
    }

    # Mock Set-ADObject
    Mock Set-ADObject {
        param($Identity, $Replace, $Clear, $Description)

        # Update mock data
        foreach ($agentName in $Script:MockAgents.Keys) {
            $agent = $Script:MockAgents[$agentName]
            if ($agent.DistinguishedName -eq $Identity) {
                if ($Replace) {
                    foreach ($key in $Replace.Keys) {
                        $agent[$key] = $Replace[$key]
                    }
                }
                if ($Clear) {
                    foreach ($key in $Clear) {
                        $agent.Remove($key)
                    }
                }
                $Script:MockAgents[$agentName] = $agent
                return
            }
        }

        foreach ($toolName in $Script:MockTools.Keys) {
            $tool = $Script:MockTools[$toolName]
            if ($tool.DistinguishedName -eq $Identity) {
                if ($Replace) {
                    foreach ($key in $Replace.Keys) {
                        $tool[$key] = $Replace[$key]
                    }
                }
                $Script:MockTools[$toolName] = $tool
                return
            }
        }

        foreach ($policyName in $Script:MockPolicies.Keys) {
            $policy = $Script:MockPolicies[$policyName]
            if ($policy.DistinguishedName -eq $Identity) {
                if ($Replace) {
                    foreach ($key in $Replace.Keys) {
                        $policy[$key] = $Replace[$key]
                    }
                }
                if ($Clear) {
                    foreach ($key in $Clear) {
                        $policy.Remove($key)
                    }
                }
                $Script:MockPolicies[$policyName] = $policy
                return
            }
        }

        foreach ($gpoName in $Script:MockInstructionGPOs.Keys) {
            $gpo = $Script:MockInstructionGPOs[$gpoName]
            if ($gpo.DistinguishedName -eq $Identity) {
                if ($Replace) {
                    foreach ($key in $Replace.Keys) {
                        $gpo[$key] = $Replace[$key]
                    }
                }
                if ($Clear) {
                    foreach ($key in $Clear) {
                        $gpo.Remove($key)
                    }
                }
                $Script:MockInstructionGPOs[$gpoName] = $gpo
                return
            }
        }
    }

    # Mock Remove-ADObject
    Mock Remove-ADObject {
        param($Identity, $Recursive)

        foreach ($agentName in @($Script:MockAgents.Keys)) {
            if ($Script:MockAgents[$agentName].DistinguishedName -eq $Identity) {
                $Script:MockAgents.Remove($agentName)
                return
            }
        }

        foreach ($sandboxName in @($Script:MockSandboxes.Keys)) {
            if ($Script:MockSandboxes[$sandboxName].DistinguishedName -eq $Identity) {
                $Script:MockSandboxes.Remove($sandboxName)
                return
            }
        }

        foreach ($toolName in @($Script:MockTools.Keys)) {
            if ($Script:MockTools[$toolName].DistinguishedName -eq $Identity) {
                $Script:MockTools.Remove($toolName)
                return
            }
        }

        foreach ($policyName in @($Script:MockPolicies.Keys)) {
            if ($Script:MockPolicies[$policyName].DistinguishedName -eq $Identity) {
                $Script:MockPolicies.Remove($policyName)
                return
            }
        }

        foreach ($gpoName in @($Script:MockInstructionGPOs.Keys)) {
            if ($Script:MockInstructionGPOs[$gpoName].DistinguishedName -eq $Identity) {
                $Script:MockInstructionGPOs.Remove($gpoName)
                return
            }
        }
    }

    # Mock Enable-ADAccount
    Mock Enable-ADAccount {
        param($Identity)

        foreach ($agentName in $Script:MockAgents.Keys) {
            $agent = $Script:MockAgents[$agentName]
            if ($agent.DistinguishedName -eq $Identity) {
                $agent.userAccountControl = $agent.userAccountControl -band (-bnot 2)
                $Script:MockAgents[$agentName] = $agent
                return
            }
        }
    }

    # Mock Disable-ADAccount
    Mock Disable-ADAccount {
        param($Identity)

        foreach ($agentName in $Script:MockAgents.Keys) {
            $agent = $Script:MockAgents[$agentName]
            if ($agent.DistinguishedName -eq $Identity) {
                $agent.userAccountControl = $agent.userAccountControl -bor 2
                $Script:MockAgents[$agentName] = $agent
                return
            }
        }
    }

    # Mock Get-ADComputer (used for sandbox lookups)
    Mock Get-ADComputer {
        param($Identity, $Filter, $Properties)

        return Get-MockSandbox -Identity $Identity
    }

    # Mock Get-ADUser (used for agent lookups)
    Mock Get-ADUser {
        param($Identity, $Filter, $Properties)

        return Get-MockAgent -Identity $Identity
    }

    # Mock Set-ADComputer (used for RBCD on sandboxes)
    Mock Set-ADComputer {
        param($Identity, $PrincipalsAllowedToDelegateToAccount)
        # No-op for tests
    }

    # Mock Set-ADAccountControl
    Mock Set-ADAccountControl {
        param($Identity, $TrustedToAuthForDelegation)
        # No-op for tests
    }

    # Mock Get-ADPrincipalGroupMembership
    Mock Get-ADPrincipalGroupMembership {
        return @()
    }
}

function Reset-MockData {
    <#
    .SYNOPSIS
        Resets mock data to initial state.
    #>

    # Re-initialize the mock data
    $Script:MockAgents = @{
        'claude-assistant-01' = @{
            Name = 'claude-assistant-01'
            DistinguishedName = "CN=claude-assistant-01,$Script:MockAgentContainerDN"
            ObjectClass = 'msDS-Agent'
            ObjectGUID = [guid]::NewGuid()
            ObjectSid = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            sAMAccountName = 'claude-assistant-01'
            userAccountControl = 512
            'msDS-AgentType' = 'assistant'
            'msDS-AgentTrustLevel' = 2
            'msDS-AgentModel' = 'claude-opus-4-5'
            'msDS-AgentOwner' = "CN=John Smith,OU=Users,$Script:MockDomainDN"
            'msDS-AgentCapabilities' = @('urn:agent:capability:code-generation', 'urn:agent:capability:document-analysis')
            'msDS-AgentSandbox' = @("CN=sandbox-prod-001,$Script:MockSandboxContainerDN")
            'msDS-AgentAuthorizedTools' = @("CN=microsoft.word,$Script:MockToolContainerDN")
            'msDS-AgentDeniedTools' = @()
            'msDS-AgentPolicies' = @('base-security', 'type-worker')
            'msDS-AgentInstructionGPOs' = @("CN=base-agent-instructions,$Script:MockInstructionGPOContainerDN")
            servicePrincipalName = @('AGENT/claude-assistant-01', 'HOST/claude-assistant-01')
            Description = 'Test Claude assistant'
            whenCreated = (Get-Date).AddDays(-30)
            whenChanged = (Get-Date).AddDays(-1)
        }
        'data-processor-01' = @{
            Name = 'data-processor-01'
            DistinguishedName = "CN=data-processor-01,$Script:MockAgentContainerDN"
            ObjectClass = 'msDS-Agent'
            ObjectGUID = [guid]::NewGuid()
            ObjectSid = 'S-1-5-21-1234567890-1234567890-1234567890-1002'
            sAMAccountName = 'data-processor-01'
            userAccountControl = 514
            'msDS-AgentType' = 'tool'
            'msDS-AgentTrustLevel' = 1
            'msDS-AgentModel' = 'custom-model-v1'
            'msDS-AgentOwner' = "CN=Data Team,OU=Groups,$Script:MockDomainDN"
            'msDS-AgentCapabilities' = @('urn:agent:capability:data-transform')
            'msDS-AgentSandbox' = @()
            'msDS-AgentAuthorizedTools' = @()
            'msDS-AgentDeniedTools' = @()
            'msDS-AgentPolicies' = @()
            'msDS-AgentInstructionGPOs' = @()
            servicePrincipalName = @()
            Description = 'Data processing agent'
            whenCreated = (Get-Date).AddDays(-15)
            whenChanged = (Get-Date).AddDays(-5)
        }
    }

    $Script:MockSandboxes = @{
        'sandbox-prod-001' = @{
            Name = 'sandbox-prod-001'
            DistinguishedName = "CN=sandbox-prod-001,$Script:MockSandboxContainerDN"
            ObjectClass = 'msDS-AgentSandbox'
            ObjectGUID = [guid]::NewGuid()
            ObjectSid = 'S-1-5-21-1234567890-1234567890-1234567890-2001'
            sAMAccountName = 'sandbox-prod-001$'
            userAccountControl = 4096
            'msDS-SandboxEndpoint' = 'https://sandbox-001.corp.contoso.com:8443'
            'msDS-SandboxAgents' = @("CN=claude-assistant-01,$Script:MockAgentContainerDN")
            'msDS-SandboxResourcePolicy' = '{"cpu": 4, "memory_gb": 16, "disk_gb": 100}'
            'msDS-SandboxNetworkPolicy' = '{"allow": ["*.corp.contoso.com"], "deny": ["*"]}'
            'msDS-SandboxSecurityProfile' = 'bwrap'
            'msDS-SandboxStatus' = 'active'
            servicePrincipalName = @('HOST/sandbox-prod-001', 'HOST/sandbox-prod-001.corp.contoso.com')
            Description = 'Production sandbox'
            whenCreated = (Get-Date).AddDays(-30)
            whenChanged = (Get-Date).AddDays(-1)
        }
    }

    $Script:MockTools = @{
        'microsoft.powershell' = @{
            Name = 'microsoft.powershell'
            DistinguishedName = "CN=microsoft.powershell,$Script:MockToolContainerDN"
            ObjectClass = 'msDS-AgentTool'
            'msDS-ToolIdentifier' = 'microsoft.powershell'
            'msDS-ToolDisplayName' = 'PowerShell'
            'msDS-ToolCategory' = 'shell'
            'msDS-ToolExecutable' = '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe'
            'msDS-ToolRiskLevel' = 4
            'msDS-ToolRequiredTrustLevel' = 2
            'msDS-ToolConstraints' = @('ExecutionPolicy=RemoteSigned', 'TranscriptLogging=Required')
            'msDS-ToolAuditRequired' = $true
            Description = 'Windows PowerShell'
            whenCreated = (Get-Date).AddDays(-60)
            whenChanged = (Get-Date).AddDays(-60)
        }
        'microsoft.word' = @{
            Name = 'microsoft.word'
            DistinguishedName = "CN=microsoft.word,$Script:MockToolContainerDN"
            ObjectClass = 'msDS-AgentTool'
            'msDS-ToolIdentifier' = 'microsoft.word'
            'msDS-ToolDisplayName' = 'Microsoft Word'
            'msDS-ToolCategory' = 'office'
            'msDS-ToolExecutable' = 'WINWORD.EXE'
            'msDS-ToolRiskLevel' = 2
            'msDS-ToolRequiredTrustLevel' = 1
            'msDS-ToolConstraints' = @('MacrosEnabled=False')
            'msDS-ToolAuditRequired' = $false
            Description = 'Microsoft Word document processor'
            whenCreated = (Get-Date).AddDays(-60)
            whenChanged = (Get-Date).AddDays(-60)
        }
        'microsoft.gpo' = @{
            Name = 'microsoft.gpo'
            DistinguishedName = "CN=microsoft.gpo,$Script:MockToolContainerDN"
            ObjectClass = 'msDS-AgentTool'
            'msDS-ToolIdentifier' = 'microsoft.gpo'
            'msDS-ToolDisplayName' = 'Group Policy Management'
            'msDS-ToolCategory' = 'management'
            'msDS-ToolExecutable' = 'GroupPolicy'
            'msDS-ToolRiskLevel' = 5
            'msDS-ToolRequiredTrustLevel' = 4
            'msDS-ToolConstraints' = @('GPOCreation=Prohibited', 'SecuritySettings=ReadOnly')
            'msDS-ToolAuditRequired' = $true
            Description = 'Group Policy Object management'
            whenCreated = (Get-Date).AddDays(-60)
            whenChanged = (Get-Date).AddDays(-60)
        }
    }

    $Script:MockPolicies = @{
        'base-security' = @{
            Name = 'base-security'
            DistinguishedName = "CN=base-security,$Script:MockPolicyContainerDN"
            ObjectClass = 'msDS-AgentPolicy'
            'msDS-PolicyIdentifier' = 'base-security'
            'msDS-PolicyType' = 'security'
            'msDS-PolicyPriority' = 0
            'msDS-PolicyPath' = 'AgentPolicies/base-security/policy.json'
            'msDS-PolicyAppliesToTypes' = @()
            'msDS-PolicyAppliesToTrustLevels' = @()
            'msDS-PolicyEnabled' = $true
            'msDS-PolicyVersion' = '1.0.0'
            Description = 'Base security policy applied to all agents'
            whenCreated = (Get-Date).AddDays(-60)
            whenChanged = (Get-Date).AddDays(-60)
        }
        'type-worker' = @{
            Name = 'type-worker'
            DistinguishedName = "CN=type-worker,$Script:MockPolicyContainerDN"
            ObjectClass = 'msDS-AgentPolicy'
            'msDS-PolicyIdentifier' = 'type-worker'
            'msDS-PolicyType' = 'behavior'
            'msDS-PolicyPriority' = 100
            'msDS-PolicyPath' = 'AgentPolicies/type-worker/policy.json'
            'msDS-PolicyAppliesToTypes' = @('autonomous', 'assistant')
            'msDS-PolicyAppliesToTrustLevels' = @()
            'msDS-PolicyEnabled' = $true
            'msDS-PolicyVersion' = '1.0.0'
            Description = 'Policy for worker agents'
            whenCreated = (Get-Date).AddDays(-60)
            whenChanged = (Get-Date).AddDays(-60)
        }
        'trust-elevated' = @{
            Name = 'trust-elevated'
            DistinguishedName = "CN=trust-elevated,$Script:MockPolicyContainerDN"
            ObjectClass = 'msDS-AgentPolicy'
            'msDS-PolicyIdentifier' = 'trust-elevated'
            'msDS-PolicyType' = 'security'
            'msDS-PolicyPriority' = 150
            'msDS-PolicyPath' = 'AgentPolicies/trust-elevated/policy.json'
            'msDS-PolicyAppliesToTypes' = @()
            'msDS-PolicyAppliesToTrustLevels' = @(3, 4)
            'msDS-PolicyEnabled' = $true
            'msDS-PolicyVersion' = '1.0.0'
            Description = 'Expanded permissions for elevated trust agents'
            whenCreated = (Get-Date).AddDays(-60)
            whenChanged = (Get-Date).AddDays(-60)
        }
    }

    $Script:MockInstructionGPOs = @{
        'base-agent-instructions' = @{
            Name = 'base-agent-instructions'
            DistinguishedName = "CN=base-agent-instructions,$Script:MockInstructionGPOContainerDN"
            ObjectClass = 'msDS-AgentInstructionGPO'
            'msDS-GPODisplayName' = 'Base Agent Instructions'
            'msDS-GPOInstructionPath' = 'AgentInstructions/base-agent-instructions/instructions.md'
            'msDS-GPOPriority' = 0
            'msDS-GPOMergeStrategy' = 'append'
            'msDS-GPOAppliesToTypes' = @()
            'msDS-GPOAppliesToTrustLevels' = @()
            'msDS-GPOAppliesToGroups' = @()
            'msDS-GPOEnabled' = $true
            'msDS-GPOVersion' = '1.0.0'
            Description = 'Foundation system prompt applied to every agent'
            whenCreated = (Get-Date).AddDays(-60)
            whenChanged = (Get-Date).AddDays(-60)
        }
        'type-assistant-instructions' = @{
            Name = 'type-assistant-instructions'
            DistinguishedName = "CN=type-assistant-instructions,$Script:MockInstructionGPOContainerDN"
            ObjectClass = 'msDS-AgentInstructionGPO'
            'msDS-GPODisplayName' = 'Assistant Agent Instructions'
            'msDS-GPOInstructionPath' = 'AgentInstructions/type-assistant-instructions/instructions.md'
            'msDS-GPOPriority' = 100
            'msDS-GPOMergeStrategy' = 'append'
            'msDS-GPOAppliesToTypes' = @('assistant')
            'msDS-GPOAppliesToTrustLevels' = @()
            'msDS-GPOAppliesToGroups' = @()
            'msDS-GPOEnabled' = $true
            'msDS-GPOVersion' = '1.0.0'
            Description = 'Instructions for interactive assistant agents'
            whenCreated = (Get-Date).AddDays(-60)
            whenChanged = (Get-Date).AddDays(-60)
        }
        'trust-elevated-instructions' = @{
            Name = 'trust-elevated-instructions'
            DistinguishedName = "CN=trust-elevated-instructions,$Script:MockInstructionGPOContainerDN"
            ObjectClass = 'msDS-AgentInstructionGPO'
            'msDS-GPODisplayName' = 'Elevated Trust Instructions'
            'msDS-GPOInstructionPath' = 'AgentInstructions/trust-elevated-instructions/instructions.md'
            'msDS-GPOPriority' = 200
            'msDS-GPOMergeStrategy' = 'append'
            'msDS-GPOAppliesToTypes' = @()
            'msDS-GPOAppliesToTrustLevels' = @(3, 4)
            'msDS-GPOAppliesToGroups' = @()
            'msDS-GPOEnabled' = $true
            'msDS-GPOVersion' = '1.0.0'
            Description = 'Additional instructions for elevated-trust agents'
            whenCreated = (Get-Date).AddDays(-60)
            whenChanged = (Get-Date).AddDays(-60)
        }
    }
}

Export-ModuleMember -Function @(
    'Get-MockAgent',
    'Get-MockSandbox',
    'Get-MockTool',
    'Get-MockPolicy',
    'Get-MockInstructionGPO',
    'New-MockADObject',
    'Initialize-ADMocks',
    'Reset-MockData'
) -Variable @(
    'MockDomainDN',
    'MockAgentContainerDN',
    'MockToolContainerDN',
    'MockSandboxContainerDN',
    'MockPolicyContainerDN',
    'MockInstructionGPOContainerDN',
    'MockAgents',
    'MockSandboxes',
    'MockTools',
    'MockPolicies',
    'MockInstructionGPOs'
)
