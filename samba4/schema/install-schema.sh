#!/bin/bash
# Autonomous Enterprise AD Schema Installation for Samba4
#
# This script installs the custom schema extensions for autonomous agents.
# Run on the Samba4 DC with appropriate privileges.
#
# Usage:
#   sudo ./install-schema.sh [domain]
#
# Example:
#   sudo ./install-schema.sh autonomy.local
#
# Prerequisites:
#   - Samba4 AD DC must be running
#   - Script must run as root or with sudo
#   - samba-tool must be in PATH

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN="${1:-autonomy.local}"
REALM="${DOMAIN^^}"  # Uppercase for Kerberos realm

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Convert domain to DN format
domain_to_dn() {
    local domain="$1"
    echo "$domain" | sed 's/\./,DC=/g' | sed 's/^/DC=/'
}

BASE_DN="$(domain_to_dn "$DOMAIN")"
SCHEMA_DN="CN=Schema,CN=Configuration,$BASE_DN"

log_info "Installing Agent Directory Schema Extension for Samba4"
log_info "Domain: $DOMAIN"
log_info "Base DN: $BASE_DN"
log_info "Schema DN: $SCHEMA_DN"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root or with sudo"
    exit 1
fi

# Check if samba-tool is available
if ! command -v samba-tool &> /dev/null; then
    log_error "samba-tool not found. Is Samba4 installed?"
    exit 1
fi

# Locate sam.ldb
PRIVATE_DIR="${SAMBA_PRIVATE_DIR:-}"
if [[ -z "$PRIVATE_DIR" ]]; then
    PRIVATE_DIR=$(samba-tool testparm -s 2>/dev/null | grep "private dir" | cut -d= -f2 | tr -d ' ' || true)
fi
if [[ -z "$PRIVATE_DIR" ]]; then
    PRIVATE_DIR="/var/lib/samba/private"
fi
SAM_LDB="$PRIVATE_DIR/sam.ldb"

if [[ ! -f "$SAM_LDB" ]]; then
    log_error "Cannot find sam.ldb at $SAM_LDB"
    exit 1
fi

log_info "Using sam.ldb at: $SAM_LDB"

# Check connectivity: either Samba is running (live LDAP) or we're in offline mode
# (sam.ldb exists, Samba not running — used during Docker bootstrap)
if samba-tool domain info "$DOMAIN" &> /dev/null; then
    log_info "Samba DC is running (online mode)"
elif ldapsearch -H ldap://localhost -x -b "" -s base namingContexts &> /dev/null; then
    log_info "LDAP is available (online mode)"
elif [[ -f "$SAM_LDB" ]]; then
    log_info "sam.ldb found — running in offline mode (Samba not running)"
    log_info "Schema changes applied directly to sam.ldb will take effect on next Samba start"
else
    log_error "Cannot find sam.ldb and Samba is not running. Cannot install schema."
    exit 1
fi

# Create temporary directory for processed LDIF files
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Function to process LDIF file and replace domain placeholder
process_ldif() {
    local input_file="$1"
    local output_file="$TEMP_DIR/$(basename "$input_file")"

    # Replace DC=autonomy,DC=local with actual domain DN
    sed "s/DC=autonomy,DC=local/$BASE_DN/g" "$input_file" > "$output_file"

    echo "$output_file"
}

# Function to install schema using ldbmodify
install_schema_file() {
    local ldif_file="$1"
    local description="$2"

    log_info "Installing: $description"

    # Use ldbmodify to apply the LDIF (SAM_LDB computed at script start)
    # --option enables schema updates, which are blocked by default in the dsdb module
    if ldbmodify -H "$SAM_LDB" --option="dsdb:schema update allowed=true" < "$ldif_file" 2>&1; then
        log_info "Successfully installed: $description"
    else
        log_warn "Some objects may already exist in: $description"
    fi
}

# Install schema in order
log_info "Phase 1: Installing attribute definitions..."

# Process and install attribute files (including sandbox and instruction GPO attributes)
for attr_file in "$SCRIPT_DIR"/0{1,1b,1c,2,3}-*-attributes.ldif; do
    if [[ -f "$attr_file" ]]; then
        processed=$(process_ldif "$attr_file")
        install_schema_file "$processed" "$(basename "$attr_file")"
    fi
done

log_info "Phase 2: Installing class definitions..."

# Process and install class files (including sandbox and instruction GPO classes)
for class_file in "$SCRIPT_DIR"/0{4,4b,4c,5,6}-*-class.ldif; do
    if [[ -f "$class_file" ]]; then
        processed=$(process_ldif "$class_file")
        install_schema_file "$processed" "$(basename "$class_file")"
    fi
done

log_info "Phase 3: Refreshing schema cache..."
# Force schema reload
samba-tool dbcheck --cross-ncs --fix --yes 2>/dev/null || true

log_info "Phase 4: Creating containers and groups..."
processed=$(process_ldif "$SCRIPT_DIR/07-containers.ldif")
install_schema_file "$processed" "containers and groups"

log_info "Phase 5: Installing default tools..."
processed=$(process_ldif "$SCRIPT_DIR/08-default-tools.ldif")
install_schema_file "$processed" "default tools"

log_info "Phase 6: Installing default policies..."
processed=$(process_ldif "$SCRIPT_DIR/09-default-policies.ldif")
install_schema_file "$processed" "default policies"

log_info "Phase 6b: Installing default instruction GPOs..."
if [[ -f "$SCRIPT_DIR/10-default-instruction-gpos.ldif" ]]; then
    processed=$(process_ldif "$SCRIPT_DIR/10-default-instruction-gpos.ldif")
    install_schema_file "$processed" "default instruction GPOs"
fi

log_info "Phase 7: Setting up SYSVOL policy directories..."

# Get SYSVOL path
SYSVOL_PATH="/var/lib/samba/sysvol/$DOMAIN"
POLICIES_PATH="$SYSVOL_PATH/AgentPolicies"

if [[ -d "$SYSVOL_PATH" ]]; then
    mkdir -p "$POLICIES_PATH"

    # Create policy directories and initial JSON files
    for policy in base-security base-behavior base-resource base-network \
                  type-worker type-coordinator type-tool \
                  trust-untrusted trust-elevated \
                  capability-code-review capability-security-analysis; do
        mkdir -p "$POLICIES_PATH/$policy"
    done

    log_info "Created policy directories in $POLICIES_PATH"

    # Create instruction GPO directories in SYSVOL
    INSTRUCTIONS_PATH="$SYSVOL_PATH/AgentInstructions"
    mkdir -p "$INSTRUCTIONS_PATH"

    for gpo in base-agent-instructions \
               type-assistant-instructions type-autonomous-instructions \
               type-coordinator-instructions type-tool-instructions \
               trust-elevated-instructions; do
        mkdir -p "$INSTRUCTIONS_PATH/$gpo"
    done

    log_info "Created instruction directories in $INSTRUCTIONS_PATH"
else
    log_warn "SYSVOL not found at $SYSVOL_PATH. Create policy directories manually."
fi

log_info ""
log_info "=============================================="
log_info "Schema installation complete!"
log_info "=============================================="
log_info ""
log_info "Next steps:"
log_info "1. Create policy JSON files in $POLICIES_PATH/"
log_info "2. Create agents using samba-tool or the management scripts"
log_info "3. Configure NATS and Ray for agent orchestration"
log_info ""
log_info "Example: Create an agent"
log_info "  samba-tool user create code-reviewer-01\$ --random-password"
log_info "  # Then set agent-specific attributes via ldapmodify"
log_info ""

