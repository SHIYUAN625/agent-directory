function ConvertTo-AgentObject {
    <#
    .SYNOPSIS
        Converts an AD object to a typed Agent object.

    .DESCRIPTION
        Takes a raw AD object and creates a custom PSObject with agent properties.

    .PARAMETER ADObject
        The AD object to convert.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $ADObject
    )

    process {
        $agent = [PSCustomObject]@{
            PSTypeName           = 'AgentDirectory.Agent'
            Name                 = $ADObject.Name
            DistinguishedName    = $ADObject.DistinguishedName
            SamAccountName       = $ADObject.sAMAccountName
            ObjectSid            = $ADObject.objectSid
            Enabled              = -not ($ADObject.userAccountControl -band 2) # ACCOUNTDISABLE flag
            Type                 = $ADObject.'msDS-AgentType'
            TrustLevel           = $ADObject.'msDS-AgentTrustLevel'
            TrustLevelName       = $Script:TrustLevelNames[[int]$ADObject.'msDS-AgentTrustLevel']
            Model                = $ADObject.'msDS-AgentModel'
            Owner                = $ADObject.'msDS-AgentOwner'
            Parent               = $ADObject.'msDS-AgentParent'
            Capabilities         = $ADObject.'msDS-AgentCapabilities'
            Sandboxes            = $ADObject.'msDS-AgentSandbox'
            AuditLevel           = $ADObject.'msDS-AgentAuditLevel'
            Policies             = $ADObject.'msDS-AgentPolicies'
            InstructionGPOs      = $ADObject.'msDS-AgentInstructionGPOs'
            DelegationScope      = $ADObject.'msDS-AgentDelegationScope'
            AuthorizedTools      = $ADObject.'msDS-AgentAuthorizedTools'
            DeniedTools          = $ADObject.'msDS-AgentDeniedTools'
            ServicePrincipalNames = $ADObject.servicePrincipalName
            Description          = $ADObject.Description
            Created              = $ADObject.whenCreated
            Modified             = $ADObject.whenChanged
        }

        # Add type data for formatting
        $agent.PSObject.TypeNames.Insert(0, 'AgentDirectory.Agent')

        return $agent
    }
}

function ConvertTo-SandboxObject {
    <#
    .SYNOPSIS
        Converts an AD object to a typed Sandbox object.

    .DESCRIPTION
        Takes a raw AD object and creates a custom PSObject with sandbox properties.

    .PARAMETER ADObject
        The AD object to convert.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $ADObject
    )

    process {
        $sandbox = [PSCustomObject]@{
            PSTypeName           = 'AgentDirectory.Sandbox'
            Name                 = $ADObject.Name
            DistinguishedName    = $ADObject.DistinguishedName
            SamAccountName       = $ADObject.sAMAccountName
            ObjectSid            = $ADObject.objectSid
            Enabled              = -not ($ADObject.userAccountControl -band 2)
            Endpoint             = $ADObject.'msDS-SandboxEndpoint'
            Agents               = $ADObject.'msDS-SandboxAgents'
            ResourcePolicy       = $ADObject.'msDS-SandboxResourcePolicy'
            NetworkPolicy        = $ADObject.'msDS-SandboxNetworkPolicy'
            SecurityProfile      = $ADObject.'msDS-SandboxSecurityProfile'
            Status               = $ADObject.'msDS-SandboxStatus'
            ServicePrincipalNames = $ADObject.servicePrincipalName
            Description          = $ADObject.Description
            Created              = $ADObject.whenCreated
            Modified             = $ADObject.whenChanged
        }

        $sandbox.PSObject.TypeNames.Insert(0, 'AgentDirectory.Sandbox')

        return $sandbox
    }
}

function ConvertTo-PolicyObject {
    <#
    .SYNOPSIS
        Converts an AD object to a typed Policy object.

    .DESCRIPTION
        Takes a raw AD object and creates a custom PSObject with policy properties.

    .PARAMETER ADObject
        The AD object to convert.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $ADObject
    )

    process {
        $policy = [PSCustomObject]@{
            PSTypeName            = 'AgentDirectory.Policy'
            Name                  = $ADObject.Name
            DistinguishedName     = $ADObject.DistinguishedName
            Identifier            = $ADObject.'msDS-PolicyIdentifier'
            Type                  = $ADObject.'msDS-PolicyType'
            Priority              = $ADObject.'msDS-PolicyPriority'
            Path                  = $ADObject.'msDS-PolicyPath'
            AppliesToTypes        = $ADObject.'msDS-PolicyAppliesToTypes'
            AppliesToTrustLevels  = $ADObject.'msDS-PolicyAppliesToTrustLevels'
            Enabled               = $ADObject.'msDS-PolicyEnabled'
            Version               = $ADObject.'msDS-PolicyVersion'
            Description           = $ADObject.Description
            Created               = $ADObject.whenCreated
            Modified              = $ADObject.whenChanged
        }

        # Add type data for formatting
        $policy.PSObject.TypeNames.Insert(0, 'AgentDirectory.Policy')

        return $policy
    }
}

function ConvertTo-InstructionGPOObject {
    <#
    .SYNOPSIS
        Converts an AD object to a typed Instruction GPO object.

    .DESCRIPTION
        Takes a raw AD object and creates a custom PSObject with instruction GPO properties.

    .PARAMETER ADObject
        The AD object to convert.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $ADObject
    )

    process {
        $gpo = [PSCustomObject]@{
            PSTypeName            = 'AgentDirectory.InstructionGPO'
            Name                  = $ADObject.Name
            DistinguishedName     = $ADObject.DistinguishedName
            DisplayName           = $ADObject.'msDS-GPODisplayName'
            InstructionPath       = $ADObject.'msDS-GPOInstructionPath'
            Priority              = $ADObject.'msDS-GPOPriority'
            MergeStrategy         = $ADObject.'msDS-GPOMergeStrategy'
            AppliesToTypes        = $ADObject.'msDS-GPOAppliesToTypes'
            AppliesToTrustLevels  = $ADObject.'msDS-GPOAppliesToTrustLevels'
            AppliesToGroups       = $ADObject.'msDS-GPOAppliesToGroups'
            Enabled               = $ADObject.'msDS-GPOEnabled'
            Version               = $ADObject.'msDS-GPOVersion'
            Description           = $ADObject.Description
            Created               = $ADObject.whenCreated
            Modified              = $ADObject.whenChanged
        }

        # Add type data for formatting
        $gpo.PSObject.TypeNames.Insert(0, 'AgentDirectory.InstructionGPO')

        return $gpo
    }
}

function ConvertTo-ToolObject {
    <#
    .SYNOPSIS
        Converts an AD object to a typed Tool object.

    .DESCRIPTION
        Takes a raw AD object and creates a custom PSObject with tool properties.

    .PARAMETER ADObject
        The AD object to convert.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $ADObject
    )

    process {
        $tool = [PSCustomObject]@{
            PSTypeName            = 'AgentDirectory.Tool'
            Name                  = $ADObject.Name
            DistinguishedName     = $ADObject.DistinguishedName
            Identifier            = $ADObject.'msDS-ToolIdentifier'
            DisplayName           = $ADObject.'msDS-ToolDisplayName'
            Category              = $ADObject.'msDS-ToolCategory'
            Executable            = $ADObject.'msDS-ToolExecutable'
            Version               = $ADObject.'msDS-ToolVersion'
            RiskLevel             = $ADObject.'msDS-ToolRiskLevel'
            RequiredTrustLevel    = $ADObject.'msDS-ToolRequiredTrustLevel'
            Constraints           = $ADObject.'msDS-ToolConstraints'
            AuditRequired         = $ADObject.'msDS-ToolAuditRequired'
            Description           = $ADObject.Description
            Created               = $ADObject.whenCreated
            Modified              = $ADObject.whenChanged
        }

        # Add type data for formatting
        $tool.PSObject.TypeNames.Insert(0, 'AgentDirectory.Tool')

        return $tool
    }
}
