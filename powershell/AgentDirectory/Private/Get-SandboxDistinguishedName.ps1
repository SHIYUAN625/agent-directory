function Get-SandboxDistinguishedName {
    <#
    .SYNOPSIS
        Resolves a sandbox identity to its distinguished name.

    .DESCRIPTION
        Takes various identity formats and returns the sandbox's distinguished name.

    .PARAMETER Identity
        Sandbox identity (name, DN, SID, or sAMAccountName).
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

    # Try to find the sandbox
    try {
        # Search by name in sandbox container first
        $sandbox = Get-ADObject -SearchBase $Script:SandboxContainerDN `
            -Filter "objectClass -eq 'msDS-AgentSandbox' -and (cn -eq '$Identity' -or sAMAccountName -eq '$Identity' -or sAMAccountName -eq '$Identity$')" `
            -ErrorAction SilentlyContinue

        if ($sandbox) {
            return $sandbox.DistinguishedName
        }

        # Search domain-wide
        $sandbox = Get-ADObject -Filter "objectClass -eq 'msDS-AgentSandbox' -and (cn -eq '$Identity' -or sAMAccountName -eq '$Identity' -or sAMAccountName -eq '$Identity$')" `
            -ErrorAction SilentlyContinue

        if ($sandbox) {
            return $sandbox.DistinguishedName
        }

        # Try as computer account (sandboxes inherit from computer)
        $computer = Get-ADComputer -Identity $Identity -ErrorAction SilentlyContinue
        if ($computer) {
            return $computer.DistinguishedName
        }
    }
    catch {
        # Continue to throw below
    }

    throw "Sandbox not found: $Identity"
}
