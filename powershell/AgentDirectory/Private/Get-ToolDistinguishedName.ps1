function Get-ToolDistinguishedName {
    <#
    .SYNOPSIS
        Resolves a tool identity to its distinguished name.

    .DESCRIPTION
        Takes various identity formats and returns the tool's distinguished name.

    .PARAMETER Identity
        Tool identity (identifier, CN, or DN).
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

    # Try to find the tool
    try {
        # Search by identifier or CN
        $tool = Get-ADObject -SearchBase $Script:ToolContainerDN `
            -Filter "objectClass -eq 'msDS-AgentTool' -and (cn -eq '$Identity' -or msDS-ToolIdentifier -eq '$Identity')" `
            -ErrorAction SilentlyContinue

        if ($tool) {
            return $tool.DistinguishedName
        }

        # Try domain-wide search
        $tool = Get-ADObject -Filter "objectClass -eq 'msDS-AgentTool' -and (cn -eq '$Identity' -or msDS-ToolIdentifier -eq '$Identity')" `
            -ErrorAction SilentlyContinue

        if ($tool) {
            return $tool.DistinguishedName
        }
    }
    catch {
        # Continue to throw below
    }

    throw "Tool not found: $Identity"
}
