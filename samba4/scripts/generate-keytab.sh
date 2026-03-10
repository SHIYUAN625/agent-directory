#!/bin/bash
# Generate Kerberos keytab for an agent
#
# Usage:
#   ./generate-keytab.sh <agent-name> <output-path> [realm]
#
# Example:
#   ./generate-keytab.sh code-reviewer-001 /tmp/agent.keytab AUTONOMY.LOCAL

set -euo pipefail

AGENT_NAME="${1:-}"
OUTPUT_PATH="${2:-}"
REALM="${3:-AUTONOMY.LOCAL}"

if [[ -z "$AGENT_NAME" ]] || [[ -z "$OUTPUT_PATH" ]]; then
    echo "Usage: $0 <agent-name> <output-path> [realm]"
    exit 1
fi

# Ensure agent name ends with $ (machine account convention)
AGENT_NAME="${AGENT_NAME%\$}\$"

echo "Generating keytab for ${AGENT_NAME}@${REALM}"

# Use samba-tool to export keytab
samba-tool domain exportkeytab "$OUTPUT_PATH" \
    --principal "${AGENT_NAME}@${REALM}"

# Secure the keytab
chmod 600 "$OUTPUT_PATH"

echo "Keytab generated: $OUTPUT_PATH"

# Show keytab contents (for verification)
if command -v klist &> /dev/null; then
    echo ""
    echo "Keytab contents:"
    klist -k -t "$OUTPUT_PATH"
fi
