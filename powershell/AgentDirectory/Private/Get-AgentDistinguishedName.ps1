function Get-AgentDistinguishedName {
    <#
    .SYNOPSIS
        Resolves an agent identity to its distinguished name.

    .DESCRIPTION
        Takes various identity formats and returns the agent's distinguished name.

    .PARAMETER Identity
        Agent identity (name, DN, SID, or sAMAccountName).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Identity
    )

    # If already a DN
    if ($Identity -match '^CN=') {
        return $Identity
    }

    # Try to find the agent
    try {
        # Search by name in agent container first
        $agent = Get-ADObject -SearchBase $Script:AgentContainerDN `
            -Filter "objectClass -eq 'msDS-Agent' -and (cn -eq '$Identity' -or sAMAccountName -eq '$Identity' -or sAMAccountName -eq '$Identity$')" `
            -ErrorAction SilentlyContinue

        if ($agent) {
            return $agent.DistinguishedName
        }

        # Search domain-wide
        $agent = Get-ADObject -Filter "objectClass -eq 'msDS-Agent' -and (cn -eq '$Identity' -or sAMAccountName -eq '$Identity' -or sAMAccountName -eq '$Identity$')" `
            -ErrorAction SilentlyContinue

        if ($agent) {
            return $agent.DistinguishedName
        }

        # Try as user account (agents now inherit from user)
        $user = Get-ADUser -Identity $Identity -ErrorAction SilentlyContinue
        if ($user) {
            return $user.DistinguishedName
        }
    }
    catch {
        # Continue to throw below
    }

    throw "Agent not found: $Identity"
}
