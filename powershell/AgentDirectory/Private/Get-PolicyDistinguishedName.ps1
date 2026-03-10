function Get-PolicyDistinguishedName {
    <#
    .SYNOPSIS
        Resolves a policy identity to its distinguished name.

    .DESCRIPTION
        Takes various identity formats and returns the policy's distinguished name.

    .PARAMETER Identity
        Policy identity (identifier, CN, or DN).
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

    # Try to find the policy
    try {
        # Search by identifier or CN
        $policy = Get-ADObject -SearchBase $Script:PolicyContainerDN `
            -Filter "objectClass -eq 'msDS-AgentPolicy' -and (cn -eq '$Identity' -or msDS-PolicyIdentifier -eq '$Identity')" `
            -ErrorAction SilentlyContinue

        if ($policy) {
            return $policy.DistinguishedName
        }

        # Try domain-wide search
        $policy = Get-ADObject -Filter "objectClass -eq 'msDS-AgentPolicy' -and (cn -eq '$Identity' -or msDS-PolicyIdentifier -eq '$Identity')" `
            -ErrorAction SilentlyContinue

        if ($policy) {
            return $policy.DistinguishedName
        }
    }
    catch {
        # Continue to throw below
    }

    throw "Policy not found: $Identity"
}
