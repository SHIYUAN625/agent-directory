#!/bin/bash
# Samba4 AD DC Entrypoint
#
# First boot: Provisions the domain, installs schema, creates sample data.
# Subsequent boots: Starts Samba in the foreground.
#
# Note: We do NOT use `set -e` globally. Provisioning and bootstrap steps
# handle errors individually to avoid partial state from Docker-specific
# issues (e.g., POSIX ACL failures on overlayfs).

set -uo pipefail

DOMAIN="${SAMBA_DOMAIN:-AUTONOMY}"
REALM="${SAMBA_REALM:-AUTONOMY.LOCAL}"
ADMIN_PASSWORD="${SAMBA_ADMIN_PASSWORD:?SAMBA_ADMIN_PASSWORD must be set in .env}"
DNS_FORWARDER="${SAMBA_DNS_FORWARDER:-8.8.8.8}"
DOMAIN_LOWER=$(echo "$REALM" | tr '[:upper:]' '[:lower:]')

PRIVATE_DIR="/var/lib/samba/private"
SAM_LDB="$PRIVATE_DIR/sam.ldb"
BOOTSTRAPPED="/var/lib/samba/.bootstrapped"

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

wait_for_ldap() {
    local max_attempts=30
    local attempt=0
    export LDAPTLS_REQCERT="${LDAPTLS_REQCERT:-allow}"
    log "Waiting for LDAPS to become ready..."
    while [ $attempt -lt $max_attempts ]; do
        if ldapsearch -H ldaps://localhost -x -b "" -s base namingContexts >/dev/null 2>&1; then
            log "LDAPS is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    log "ERROR: LDAPS did not become ready after $((max_attempts * 2))s"
    return 1
}

# ============================================================================
# FIRST BOOT: Provision domain
# ============================================================================
if [ ! -f "$SAM_LDB" ]; then
    log "First boot detected - provisioning domain $REALM"

    # Remove default smb.conf — samba-tool provision generates its own.
    # The package-installed smb.conf has "server role = standalone server"
    # which conflicts with AD DC provisioning.
    rm -f /etc/samba/smb.conf

    # Write initial krb5.conf
    cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = $REALM
    dns_lookup_realm = false
    dns_lookup_kdc = false
    rdns = false

[realms]
    $REALM = {
        kdc = localhost
        admin_server = localhost
    }

[domain_realm]
    .$DOMAIN_LOWER = $REALM
    $DOMAIN_LOWER = $REALM
EOF

    log "Provisioning Samba AD domain..."
    # --option="vfs objects=" disables the VFS ACL module which requires
    # POSIX ACL support that Docker's overlayfs does not provide.
    # This is safe for dev/test — the SYSVOL will lack NT ACLs but
    # LDAP and Kerberos function normally.
    samba-tool domain provision \
        --use-rfc2307 \
        --domain="$DOMAIN" \
        --realm="$REALM" \
        --server-role=dc \
        --dns-backend=SAMBA_INTERNAL \
        --adminpass="$ADMIN_PASSWORD" \
        --host-name=dc1 \
        --option="vfs objects="

    # Note: Do NOT overwrite /etc/krb5.conf with the provisioned one.
    # Samba's provisioned krb5.conf uses dns_lookup_kdc=true but Docker's
    # internal DNS (127.0.0.11) can't resolve Samba's SRV records.
    # Our initial krb5.conf has explicit kdc=localhost which works.

    log "Domain provisioned successfully"
fi

# ============================================================================
# BOOTSTRAP: Install schema and sample data (once)
# ============================================================================
if [ ! -f "$BOOTSTRAPPED" ]; then
    # --- Phase 1: Schema installation (Samba must be STOPPED) ---
    # Samba rejects schema_data_add while running. Apply schema
    # extensions directly to sam.ldb before starting the service.
    log "Installing schema extensions (offline)..."
    /opt/samba-ad/bootstrap-schema.sh "$DOMAIN_LOWER"

    # --- Phase 2: Start Samba so data bootstrap can use samba-tool ---
    log "Starting Samba in background for data bootstrap..."
    samba --foreground --no-process-group &
    SAMBA_PID=$!

    # Wait for LDAP to be ready
    if ! wait_for_ldap; then
        log "FATAL: Samba did not start. Check provisioning above."
        exit 1
    fi

    # --- Phase 3: Create sample data (agents, sandboxes, tools, etc.) ---
    log "Running data bootstrap..."
    if ! /opt/samba-ad/bootstrap-data.sh "$DOMAIN_LOWER" "$ADMIN_PASSWORD"; then
        log "FATAL: Data bootstrap failed"
        kill "$SAMBA_PID" 2>/dev/null || true
        wait "$SAMBA_PID" 2>/dev/null || true
        exit 1
    fi

    # --- Phase 4: Set LDAP ACLs for DC-enforced access control ---
    log "Running ACL bootstrap..."
    if ! /opt/samba-ad/bootstrap-acls.sh "$DOMAIN_LOWER" "$ADMIN_PASSWORD"; then
        log "FATAL: ACL bootstrap failed"
        kill "$SAMBA_PID" 2>/dev/null || true
        wait "$SAMBA_PID" 2>/dev/null || true
        exit 1
    fi

    log "Bootstrap complete"
    touch "$BOOTSTRAPPED"

    # Stop background Samba
    log "Stopping background Samba..."
    kill "$SAMBA_PID" 2>/dev/null || true
    wait "$SAMBA_PID" 2>/dev/null || true
    sleep 2
fi

# ============================================================================
# ALWAYS: Ensure runtime config before starting Samba
# ============================================================================

# Kerberos config — explicit KDC so we don't depend on DNS SRV lookups
# (Docker's internal DNS can't resolve Samba's SRV records)
cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = $REALM
    dns_lookup_realm = false
    dns_lookup_kdc = false
    rdns = false

[realms]
    $REALM = {
        kdc = localhost
        admin_server = localhost
    }

[domain_realm]
    .$DOMAIN_LOWER = $REALM
    $DOMAIN_LOWER = $REALM
EOF

# Ensure domain resolves locally
if ! grep -q "$DOMAIN_LOWER" /etc/hosts 2>/dev/null; then
    echo "127.0.0.1 dc1.${DOMAIN_LOWER} dc1 ${DOMAIN_LOWER}" >> /etc/hosts
fi

log "Starting Samba AD DC (foreground)..."
exec samba --foreground --no-process-group
