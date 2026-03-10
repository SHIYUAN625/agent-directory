#!/bin/bash
# Bootstrap Schema
#
# Installs custom schema extensions and copies policy JSONs to SYSVOL.
#
# Usage: bootstrap-schema.sh <domain>
# Example: bootstrap-schema.sh autonomy.local

set -euo pipefail

DOMAIN="${1:-autonomy.local}"
SCHEMA_DIR="/opt/samba-ad/schema"
POLICIES_SRC="/opt/samba-ad/policies"
INSTRUCTIONS_SRC="/opt/samba-ad/instructions"
SYSVOL_PATH="/var/lib/samba/sysvol/$DOMAIN"
POLICIES_DEST="$SYSVOL_PATH/AgentPolicies"
INSTRUCTIONS_DEST="$SYSVOL_PATH/AgentInstructions"

log() {
    echo "[$(date '+%H:%M:%S')] [schema] $1"
}

# Install custom schema via the existing install script
log "Installing custom schema extensions..."
"$SCHEMA_DIR/install-schema.sh" "$DOMAIN"

# Copy policy JSON files to SYSVOL if any exist
if [ -d "$POLICIES_SRC" ] && [ "$(ls -A "$POLICIES_SRC" 2>/dev/null)" ]; then
    log "Copying policy definitions to SYSVOL..."
    mkdir -p "$POLICIES_DEST"

    # Policies are stored as subdirectories: base-security/policy.json
    for policy_dir in "$POLICIES_SRC"/*/; do
        if [ -f "$policy_dir/policy.json" ]; then
            policy_name=$(basename "$policy_dir")
            mkdir -p "$POLICIES_DEST/$policy_name"
            cp "$policy_dir/policy.json" "$POLICIES_DEST/$policy_name/policy.json"
            log "  Installed policy: $policy_name"
        fi
    done
else
    log "No policy definitions found in $POLICIES_SRC (will use LDIF-defined defaults)"
fi

# Copy instruction GPO content (markdown) to SYSVOL
if [ -d "$INSTRUCTIONS_SRC" ] && [ "$(ls -A "$INSTRUCTIONS_SRC" 2>/dev/null)" ]; then
    log "Copying instruction GPO content to SYSVOL..."
    mkdir -p "$INSTRUCTIONS_DEST"

    for instruction_file in "$INSTRUCTIONS_SRC"/*.md; do
        if [ -f "$instruction_file" ]; then
            gpo_name=$(basename "$instruction_file" .md)
            # Map filename to GPO directory name
            # e.g., base-agent-instructions.md -> base-agent-instructions/instructions.md
            gpo_dir="$INSTRUCTIONS_DEST/${gpo_name}-instructions"
            # Handle files already named with -instructions suffix
            if echo "$gpo_name" | grep -q -- "-instructions$"; then
                gpo_dir="$INSTRUCTIONS_DEST/$gpo_name"
            fi
            mkdir -p "$gpo_dir"
            cp "$instruction_file" "$gpo_dir/instructions.md"
            log "  Installed instruction GPO: $(basename "$gpo_dir")"
        fi
    done
else
    log "No instruction files found in $INSTRUCTIONS_SRC"
fi

log "Schema bootstrap complete"
