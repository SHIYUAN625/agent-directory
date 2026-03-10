function Test-AgentTrustLevel {
    <#
    .SYNOPSIS
        Tests if an agent's trust level meets a requirement.

    .DESCRIPTION
        Compares an agent's trust level against a required level.

    .PARAMETER AgentTrustLevel
        The agent's current trust level.

    .PARAMETER RequiredLevel
        The minimum required trust level.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$AgentTrustLevel,

        [Parameter(Mandatory)]
        [int]$RequiredLevel
    )

    return $AgentTrustLevel -ge $RequiredLevel
}

function Get-AgentTrustLevelName {
    <#
    .SYNOPSIS
        Gets the name for a trust level.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Level
    )

    if ($Script:TrustLevelNames.ContainsKey($Level)) {
        return $Script:TrustLevelNames[$Level]
    }

    return "Unknown ($Level)"
}

function Test-ValidAgentType {
    <#
    .SYNOPSIS
        Validates an agent type string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Type
    )

    return $Script:ValidAgentTypes -contains $Type.ToLower()
}

function Test-ValidToolCategory {
    <#
    .SYNOPSIS
        Validates a tool category string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Category
    )

    return $Script:ValidToolCategories -contains $Category.ToLower()
}
