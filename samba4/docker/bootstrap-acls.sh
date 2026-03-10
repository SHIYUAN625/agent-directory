#!/bin/bash
# Bootstrap LDAP ACLs
#
# Sets DC-enforced access control on agent containers.
#
# Security model:
# - Agents authenticate with their OWN Kerberos identity (not admin)
# - Each agent gets read+list on the 4 agent containers (Agents, Tools,
#   Policies, Instructions) so it can resolve its linked objects
# - Each agent gets read on its own entry
# - DC ACLs are the enforcement boundary — no broker intermediary
#
# In production, you would block inheritance on these containers and
# re-add only DA/SY grants (using python-samba ndr_pack ACL
# manipulation, since samba-tool dsacl can only add ACEs, not remove them).
#
# Usage: bootstrap-acls.sh <domain> <admin-password>

set -uo pipefail

DOMAIN="${1:?Usage: bootstrap-acls.sh <domain> <admin-password>}"
ADMIN_PASSWORD="${2:?Usage: bootstrap-acls.sh <domain> <admin-password>}"
REALM="${DOMAIN^^}"
BASE_DN=$(echo "$DOMAIN" | sed 's/\./,DC=/g' | sed 's/^/DC=/')

AGENTS_DN="CN=Agents,CN=System,$BASE_DN"
TOOLS_DN="CN=Agent Tools,CN=System,$BASE_DN"
POLICIES_DN="CN=Agent Policies,CN=System,$BASE_DN"
INSTRUCTIONS_DN="CN=Agent Instructions,CN=System,$BASE_DN"

# TLS cert verification: 'allow' accepts self-signed certs but still
# requires TLS. Safe for localhost bootstrap; use 'demand' in production.
export LDAPTLS_REQCERT=allow

log() {
    echo "[$(date '+%H:%M:%S')] [acls] $1"
}

# Resolve string SID for a sAMAccountName using python-samba
# (wbinfo may not be ready during bootstrap, python-samba is reliable)
get_sid() {
    local sam_name="$1"
    python3 -c "
import ldb
from samba.auth import system_session
from samba.param import LoadParm
from samba.samdb import SamDB
lp = LoadParm()
lp.load_default()
samdb = SamDB(url='/var/lib/samba/private/sam.ldb', session_info=system_session(), lp=lp)
res = samdb.search(base='$BASE_DN', scope=ldb.SCOPE_SUBTREE,
    expression='(sAMAccountName=$sam_name)',
    attrs=['objectSid'])
if len(res) > 0:
    from samba.ndr import ndr_unpack
    from samba.dcerpc import security
    sid = ndr_unpack(security.dom_sid, res[0]['objectSid'][0])
    print(str(sid))
" 2>/dev/null
}

# Set ACL using samba-tool dsacl
set_acl() {
    local object_dn="$1"
    local sddl="$2"
    local description="$3"

    log "Setting ACL: $description"

    samba-tool dsacl set \
        --objectdn="$object_dn" \
        --sddl="$sddl" \
        --username=Administrator \
        --password="$ADMIN_PASSWORD" 2>&1 | grep -v "^WARNING:" || {
        log "  WARNING: dsacl set failed for $description"
        return 1
    }

    log "  OK"
}

# ============================================================================
# RESOLVE SIDS
# ============================================================================
log "=== Resolving SIDs ==="

declare -A AGENT_SIDS
for agent_name in claude-assistant-01 data-processor-01 coordinator-main; do
    sid=$(get_sid "${agent_name}\$")
    if [ -n "$sid" ]; then
        AGENT_SIDS[$agent_name]="$sid"
        log "  $agent_name: $sid"
    else
        log "  WARNING: Could not resolve SID for $agent_name"
    fi
done

# ============================================================================
# GRANT EACH AGENT READ+LIST ON SHARED CONTAINERS
# ============================================================================
#
# Do NOT grant read/list on CN=Agents to all agents: that permits cross-agent
# directory reads. Agents should only read their own entry in CN=Agents.
#
log "=== Granting Agent Shared Container Access ==="

for agent_name in claude-assistant-01 data-processor-01 coordinator-main; do
    agent_sid="${AGENT_SIDS[$agent_name]:-}"
    if [ -z "$agent_sid" ]; then
        log "  SKIPPED: No SID for $agent_name"
        continue
    fi

    for container_dn in "$TOOLS_DN" "$POLICIES_DN" "$INSTRUCTIONS_DN"; do
        container_name=$(echo "$container_dn" | sed 's/,.*//' | sed 's/CN=//')
        set_acl "$container_dn" \
            "(A;CI;RPLCLORC;;;$agent_sid)" \
            "$agent_name read+list on $container_name"
    done
done

# ============================================================================
# GRANT EACH AGENT READ ON OWN ENTRY
# ============================================================================
log "=== Granting Agent Self-Read ==="

for agent_name in claude-assistant-01 data-processor-01 coordinator-main; do
    agent_sid="${AGENT_SIDS[$agent_name]:-}"
    if [ -z "$agent_sid" ]; then
        log "  SKIPPED: No SID for $agent_name"
        continue
    fi

    agent_dn="CN=${agent_name}\$,$AGENTS_DN"

    # Grant agent read on its own entry only (no CI = not inherited)
    set_acl "$agent_dn" \
        "(A;;RPRC;;;$agent_sid)" \
        "$agent_name self-read"
done

# ============================================================================
# SUMMARY
# ============================================================================
log "=== ACL Bootstrap Summary ==="
log "Agent access:   READ+LIST on Tools, Policies, Instructions"
log "Agent access:   READ on own entry (via Kerberos identity)"
log "Admin access:   Full (DA/SY inherited from parent)"
log ""
log "Agents authenticate as themselves — DC ACLs are the enforcement boundary."
log ""
log "ACL bootstrap complete"
