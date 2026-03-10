#!/bin/bash
# replace-oid.sh — Replace placeholder OID base with a real IANA PEN.
#
# The schema files ship with OID base 1.3.6.1.4.1.99999 which is a
# non-production placeholder. Before deploying to production, obtain a
# Private Enterprise Number from IANA (https://pen.iana.org/pen/PenApplication.page)
# and run this script to replace all occurrences.
#
# Usage:
#   ./scripts/replace-oid.sh <PEN>
#
# Example:
#   ./scripts/replace-oid.sh 12345
#   # Replaces 1.3.6.1.4.1.99999 → 1.3.6.1.4.1.12345 in all schema LDIFs
#
# The script is idempotent — running it twice with the same PEN is a no-op.
# Running it with a different PEN after the first replacement will NOT work;
# reset to the placeholder first with: git checkout -- samba4/schema/ schema/

set -euo pipefail

PLACEHOLDER="1.3.6.1.4.1.99999"

if [ $# -ne 1 ]; then
    echo "Usage: $0 <PEN>" >&2
    echo "  PEN: Your IANA Private Enterprise Number (digits only)" >&2
    exit 1
fi

PEN="$1"

# Validate: digits only, reasonable length
if ! [[ "$PEN" =~ ^[0-9]+$ ]]; then
    echo "Error: PEN must be digits only, got: $PEN" >&2
    exit 1
fi

if [ "$PEN" = "99999" ]; then
    echo "Error: 99999 is the placeholder — provide your real PEN" >&2
    exit 1
fi

NEW_OID="1.3.6.1.4.1.$PEN"

# Collect all schema LDIF files
FILES=()
for f in samba4/schema/*.ldif schema/*.ldif; do
    [ -f "$f" ] && FILES+=("$f")
done

if [ ${#FILES[@]} -eq 0 ]; then
    echo "Error: No LDIF files found in samba4/schema/ or schema/" >&2
    exit 1
fi

# Count current occurrences
TOTAL=0
for f in "${FILES[@]}"; do
    COUNT=$(grep -c "$PLACEHOLDER" "$f" 2>/dev/null || true)
    TOTAL=$((TOTAL + COUNT))
done

if [ "$TOTAL" -eq 0 ]; then
    echo "No occurrences of $PLACEHOLDER found — already replaced?" >&2
    exit 0
fi

echo "Replacing OID base in schema files:"
echo "  $PLACEHOLDER → $NEW_OID"
echo "  Files: ${#FILES[@]}"
echo "  Occurrences: $TOTAL"
echo ""

for f in "${FILES[@]}"; do
    COUNT=$(grep -c "$PLACEHOLDER" "$f" 2>/dev/null || true)
    if [ "$COUNT" -gt 0 ]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/$PLACEHOLDER/$NEW_OID/g" "$f"
        else
            sed -i "s/$PLACEHOLDER/$NEW_OID/g" "$f"
        fi
        echo "  $f ($COUNT replacements)"
    fi
done

echo ""
echo "Done. Verify with: grep -r '1.3.6.1.4.1.' samba4/schema/ schema/ | head"
