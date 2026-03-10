function Get-InstructionGPODistinguishedName {
    <#
    .SYNOPSIS
        Resolves an instruction GPO identity to its distinguished name.

    .DESCRIPTION
        Takes various identity formats and returns the instruction GPO's distinguished name.

    .PARAMETER Identity
        Instruction GPO identity (name, display name, CN, or DN).
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

    # Try to find the instruction GPO
    try {
        # Search by CN or display name
        $gpo = Get-ADObject -SearchBase $Script:InstructionGPOContainerDN `
            -Filter "objectClass -eq 'msDS-AgentInstructionGPO' -and (cn -eq '$Identity' -or msDS-GPODisplayName -eq '$Identity')" `
            -ErrorAction SilentlyContinue

        if ($gpo) {
            return $gpo.DistinguishedName
        }

        # Try domain-wide search
        $gpo = Get-ADObject -Filter "objectClass -eq 'msDS-AgentInstructionGPO' -and (cn -eq '$Identity' -or msDS-GPODisplayName -eq '$Identity')" `
            -ErrorAction SilentlyContinue

        if ($gpo) {
            return $gpo.DistinguishedName
        }
    }
    catch {
        # Continue to throw below
    }

    throw "Instruction GPO not found: $Identity"
}
