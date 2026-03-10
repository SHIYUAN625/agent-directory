#!/bin/bash
# Integration test suite for Samba4 AD DC agent directory.
#
# Runs inside the DC container (or via docker exec). Tests schema, data,
# ACLs, schema enforcement, CRUD lifecycles, default objects/linkage,
# and content validation against the live Samba instance.
#
# All queries use native Samba tooling: ldapsearch, ldapmodify, ldbsearch,
# samba-tool. No dependency on agent-manager.py or other wrappers.
#
# Exit code: 0 if all tests pass, 1 if any fail.
#
# Usage:
#   docker exec agent-directory-dc /opt/samba-ad/integration-test.sh
#   — or via Makefile: make integration-test

set -uo pipefail

# ── Configuration ──────────────────────────────────────────────────────────

DOMAIN="${SAMBA_REALM:-AUTONOMY.LOCAL}"
DOMAIN_LOWER=$(echo "$DOMAIN" | tr '[:upper:]' '[:lower:]')
BASE_DN=$(echo "$DOMAIN_LOWER" | sed 's/\./,DC=/g' | sed 's/^/DC=/')
ADMIN_PASSWORD="${SAMBA_ADMIN_PASSWORD:?SAMBA_ADMIN_PASSWORD must be set}"

export LDAPTLS_REQCERT=allow
LDAP_URI="ldaps://localhost"
BIND_ARGS=(-x -D "CN=Administrator,CN=Users,$BASE_DN" -w "$ADMIN_PASSWORD")

SYSVOL="/var/lib/samba/sysvol/${DOMAIN_LOWER}"
SAM_LDB="/var/lib/samba/private/sam.ldb"

# ── Counters and diagnostics ──────────────────────────────────────────────

PASS=0
FAIL=0
ERRORS=""

# DNs created by tests — cleaned up in reverse on EXIT
CLEANUP_DNS=()

cleanup() {
    local i
    for (( i=${#CLEANUP_DNS[@]}-1; i>=0; i-- )); do
        ldapmodify -H "$LDAP_URI" "${BIND_ARGS[@]}" <<EOF >/dev/null 2>&1
dn: ${CLEANUP_DNS[$i]}
changetype: delete
EOF
    done
}
trap cleanup EXIT

# ── OID preflight ─────────────────────────────────────────────────────────

if grep -rq '1\.3\.6\.1\.4\.1\.99999' /opt/samba-ad/schema/*.ldif 2>/dev/null; then
    echo "WARNING: Schema files contain placeholder OID base 1.3.6.1.4.1.99999"
    echo "         Replace with a real IANA PEN before production deployment."
    echo "         Run: scripts/replace-oid.sh <your-PEN>"
    echo ""
fi

# ── Test helpers ──────────────────────────────────────────────────────────

pass() {
    PASS=$((PASS + 1))
    echo "  PASS: $1"
}

fail() {
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $1"
    echo "  FAIL: $1"
}

# check runs a command and reports pass/fail.
# On failure, shows first 5 lines of combined stdout+stderr.
check() {
    local desc="$1"
    shift
    local output
    if output=$("$@" 2>&1); then
        pass "$desc"
    else
        fail "$desc"
        echo "$output" | head -5 | sed 's/^/    | /'
    fi
}

# check_fail passes when the command returns non-zero.
check_fail() {
    local desc="$1"
    shift
    local output
    if output=$("$@" 2>&1); then
        fail "$desc (expected failure, got success)"
        echo "$output" | head -5 | sed 's/^/    | /'
    else
        pass "$desc"
    fi
}

# ── LDAP helpers ──────────────────────────────────────────────────────────

# Raw ldapsearch with admin bind — returns LDIF text.
ldap_search_raw() {
    local base_dn="$1" scope="$2" filter="$3"
    shift 3
    local scope_arg
    case "$scope" in
        base)     scope_arg="base" ;;
        onelevel) scope_arg="one"  ;;
        subtree)  scope_arg="sub"  ;;
        *)        scope_arg="$scope" ;;
    esac
    ldapsearch -N -H "$LDAP_URI" "${BIND_ARGS[@]}" \
        -b "$base_dn" -s "$scope_arg" "$filter" "$@" 2>/dev/null
}

# Unfold LDIF continuation lines (lines starting with a space are continuations).
ldif_unfold() {
    sed ':a; N; $!ba; s/\n //g'
}

# Check if an LDAP entry exists.
ldap_entry_exists() {
    local dn="$1"
    ldap_search_raw "$dn" base "(objectClass=*)" dn 2>/dev/null | grep -q "^dn:"
}

# Check if an attribute has a specific value (exact match).
# Unfolds continuation lines before matching.
ldap_attr_eq() {
    local dn="$1" attr="$2" value="$3"
    ldap_search_raw "$dn" base "(objectClass=*)" "$attr" \
        | ldif_unfold \
        | grep -q "^${attr}: ${value}$"
}

# Check if an attribute contains a substring.
ldap_attr_contains() {
    local dn="$1" attr="$2" substring="$3"
    ldap_search_raw "$dn" base "(objectClass=*)" "$attr" \
        | ldif_unfold \
        | grep -q "$substring"
}

# Count multi-valued attribute occurrences.
ldap_attr_count() {
    local dn="$1" attr="$2"
    ldap_search_raw "$dn" base "(objectClass=*)" "$attr" \
        | ldif_unfold \
        | grep -c "^${attr}:" || true
}

# Count entries returned by a search.
ldap_count_entries() {
    local base_dn="$1" scope="$2" filter="$3"
    ldap_search_raw "$base_dn" "$scope" "$filter" dn \
        | grep -c "^dn:" || true
}

# ── Schema enforcement helpers ────────────────────────────────────────────

# Feed LDIF to ldapmodify, expect success.
schema_accept() {
    local desc="$1" ldif="$2"
    local output
    if output=$(echo "$ldif" | ldapmodify -H "$LDAP_URI" "${BIND_ARGS[@]}" 2>&1); then
        pass "$desc"
    else
        fail "$desc"
        echo "$output" | head -5 | sed 's/^/    | /'
    fi
}

# Feed LDIF to ldapmodify, expect failure.
schema_reject() {
    local desc="$1" ldif="$2"
    local output
    if output=$(echo "$ldif" | ldapmodify -H "$LDAP_URI" "${BIND_ARGS[@]}" 2>&1); then
        fail "$desc (expected rejection, got success)"
        echo "$output" | head -5 | sed 's/^/    | /'
    else
        pass "$desc"
    fi
}

# ── GSSAPI helpers ────────────────────────────────────────────────────────

# kinit for an agent, returns ccache path.
gssapi_kinit() {
    local agent="$1"
    local kt="/var/lib/samba/keytabs/${agent}.keytab"
    local ccache="/tmp/krb5cc_test_${agent}_$$"
    KRB5CCNAME="$ccache" kinit -kt "$kt" "${agent}\$@${DOMAIN}" 2>/dev/null || return 1
    echo "$ccache"
}

echo "=== Agent Directory Integration Tests ==="
echo "Domain: $DOMAIN | Base DN: $BASE_DN"
echo ""

# ══════════════════════════════════════════════════════════════════════════
# 1. SMOKE TESTS (7)
# ══════════════════════════════════════════════════════════════════════════
echo "--- 1. Smoke Tests ---"

# 1.1-1.5: Schema classes
for cls in x-agent x-agentSandbox x-agentTool x-agentPolicy x-agentInstructionGPO; do
    check "schema class $cls exists" \
        ldap_entry_exists "CN=$cls,CN=Schema,CN=Configuration,$BASE_DN"
done

# 1.6: All 5 containers exist (compound — one test, all must pass)
check "all 5 containers exist" bash -c '
    for cn in "Agents" "Agent Sandboxes" "Agent Tools" "Agent Policies" "Agent Instructions"; do
        ldapsearch -N -H "'"$LDAP_URI"'" '"${BIND_ARGS[*]}"' \
            -b "CN=$cn,CN=System,'"$BASE_DN"'" -s base dn 2>/dev/null \
            | grep -q "^dn:" || exit 1
    done
'

# 1.7: LDAPS bind works
check "LDAPS simple bind succeeds" \
    ldap_entry_exists "$BASE_DN"

echo ""

# ══════════════════════════════════════════════════════════════════════════
# 2. AGENT IDENTITY (18)
# ══════════════════════════════════════════════════════════════════════════
echo "--- 2. Agent Identity ---"

# 2.1-2.9: Type, trust, model for each agent
declare -A AGENT_TYPE=( [claude-assistant-01]=assistant [data-processor-01]=autonomous [coordinator-main]=coordinator )
declare -A AGENT_TRUST=( [claude-assistant-01]=2 [data-processor-01]=2 [coordinator-main]=3 )
declare -A AGENT_MODEL=( [claude-assistant-01]=claude-opus-4-5 [data-processor-01]=claude-sonnet-4 [coordinator-main]=claude-opus-4-5 )

for agent in claude-assistant-01 data-processor-01 coordinator-main; do
    dn="CN=${agent}\$,CN=Agents,CN=System,$BASE_DN"
    check "agent $agent type=${AGENT_TYPE[$agent]}" \
        ldap_attr_eq "$dn" "x-agent-Type" "${AGENT_TYPE[$agent]}"
    check "agent $agent trust=${AGENT_TRUST[$agent]}" \
        ldap_attr_eq "$dn" "x-agent-TrustLevel" "${AGENT_TRUST[$agent]}"
    check "agent $agent model=${AGENT_MODEL[$agent]}" \
        ldap_attr_eq "$dn" "x-agent-Model" "${AGENT_MODEL[$agent]}"
done

# 2.10-2.12: Tool counts
declare -A TOOL_COUNTS=( [claude-assistant-01]=5 [data-processor-01]=9 [coordinator-main]=9 )

for agent in claude-assistant-01 data-processor-01 coordinator-main; do
    dn="CN=${agent}\$,CN=Agents,CN=System,$BASE_DN"
    expected="${TOOL_COUNTS[$agent]}"
    actual=$(ldap_attr_count "$dn" "x-agent-AuthorizedTools")
    if [ "$actual" -eq "$expected" ]; then
        pass "agent $agent has $expected authorized tools"
    else
        fail "agent $agent tool count: expected $expected, got $actual"
    fi
done

# 2.13: claude-assistant-01 has git.cli
check "claude-assistant-01 has tool git.cli" \
    ldap_attr_contains "CN=claude-assistant-01\$,CN=Agents,CN=System,$BASE_DN" \
        "x-agent-AuthorizedTools" "git.cli"

# 2.14: claude-assistant-01 does NOT have agent.spawn
check_fail "claude-assistant-01 lacks tool agent.spawn" \
    ldap_attr_contains "CN=claude-assistant-01\$,CN=Agents,CN=System,$BASE_DN" \
        "x-agent-AuthorizedTools" "agent.spawn"

# 2.15: claude-assistant-01 linked to sandbox-prod-001
check "claude-assistant-01 sandbox linkage" \
    ldap_attr_contains "CN=claude-assistant-01\$,CN=Agents,CN=System,$BASE_DN" \
        "x-agent-Sandbox" "sandbox-prod-001"

# 2.16: data-processor-01 linked to sandbox-dev-001
check "data-processor-01 sandbox linkage" \
    ldap_attr_contains "CN=data-processor-01\$,CN=Agents,CN=System,$BASE_DN" \
        "x-agent-Sandbox" "sandbox-dev-001"

# 2.17: claude-assistant-01 in Team-Engineering group
check "claude-assistant-01 in Team-Engineering" bash -c '
    ldapsearch -N -H "'"$LDAP_URI"'" '"${BIND_ARGS[*]}"' \
        -b "CN=Team-Engineering,OU=AgentGroups,'"$BASE_DN"'" -s base member 2>/dev/null \
        | grep -iq "claude-assistant-01"
'

# 2.18: coordinator-main in Tier3-Coordinators group
# Groups with members live in CN=Users (samba-tool group addmembers default)
check "coordinator-main in Tier3-Coordinators" bash -c '
    ldapsearch -N -H "'"$LDAP_URI"'" '"${BIND_ARGS[*]}"' \
        -b "CN=Tier3-Coordinators,CN=Users,'"$BASE_DN"'" -s base member 2>/dev/null \
        | sed ":a; N; \$!ba; s/\n //g" \
        | grep -iq "coordinator-main"
'

echo ""

# ══════════════════════════════════════════════════════════════════════════
# 3. AUTHENTICATION (6)
# ══════════════════════════════════════════════════════════════════════════
echo "--- 3. Authentication ---"

# 3.1-3.3: kinit succeeds for all agents
for agent in claude-assistant-01 data-processor-01 coordinator-main; do
    kt="/var/lib/samba/keytabs/${agent}.keytab"
    ccache="/tmp/krb5cc_test_${agent}_auth"
    if KRB5CCNAME="$ccache" kinit -kt "$kt" "${agent}\$@${DOMAIN}" 2>/dev/null; then
        pass "kinit succeeds: $agent"
        kdestroy -c "$ccache" 2>/dev/null || true
    else
        fail "kinit succeeds: $agent"
    fi
done

# 3.4: kinit fails with wrong keytab (use data-processor keytab for claude principal)
check_fail "kinit fails with wrong keytab" bash -c '
    KRB5CCNAME=/tmp/krb5cc_test_wrong_$$ \
    kinit -kt /var/lib/samba/keytabs/data-processor-01.keytab \
        "claude-assistant-01\$@'"$DOMAIN"'" 2>/dev/null
'

# 3.5: kinit fails with nonexistent principal
check_fail "kinit fails with nonexistent principal" bash -c '
    KRB5CCNAME=/tmp/krb5cc_test_noexist_$$ \
    kinit -kt /var/lib/samba/keytabs/claude-assistant-01.keytab \
        "nonexistent-agent\$@'"$DOMAIN"'" 2>/dev/null
'

# 3.6: kinit fails with /dev/null keytab
check_fail "kinit fails with /dev/null keytab" bash -c '
    KRB5CCNAME=/tmp/krb5cc_test_devnull_$$ \
    kinit -kt /dev/null \
        "claude-assistant-01\$@'"$DOMAIN"'" 2>/dev/null
'

echo ""

# ══════════════════════════════════════════════════════════════════════════
# 4. AUTHORIZATION / ACL (12)
# ══════════════════════════════════════════════════════════════════════════
echo "--- 4. Authorization / ACL ---"

# Authenticate as claude-assistant-01
CLAUDE_CC=$(gssapi_kinit "claude-assistant-01") || { fail "kinit claude-assistant-01 for ACL tests"; }

# 4.1: Read own entry
check "agent reads own entry via GSSAPI" bash -c '
    KRB5CCNAME='"$CLAUDE_CC"' ldapsearch -N -H ldap://dc1.'"$DOMAIN_LOWER"' \
        -Y GSSAPI -b "CN=claude-assistant-01\$,CN=Agents,CN=System,'"$BASE_DN"'" \
        -s base "(objectClass=*)" cn 2>/dev/null | grep -q "^dn:"
'

# 4.2-4.4: List 3 containers
for container in "Agent Tools" "Agent Policies" "Agent Instructions"; do
    check "agent lists $container via GSSAPI" bash -c '
        KRB5CCNAME='"$CLAUDE_CC"' ldapsearch -N -H ldap://dc1.'"$DOMAIN_LOWER"' \
            -Y GSSAPI -b "CN='"$container"',CN=System,'"$BASE_DN"'" \
            -s one "(objectClass=*)" cn 2>/dev/null | grep -q "^dn:"
    '
done

# 4.5: CANNOT modify self
check_fail "agent CANNOT modify own entry" bash -c '
    echo "dn: CN=claude-assistant-01\$,CN=Agents,CN=System,'"$BASE_DN"'
changetype: modify
replace: x-agent-TrustLevel
x-agent-TrustLevel: 4" | KRB5CCNAME='"$CLAUDE_CC"' ldapmodify \
        -H ldap://dc1.'"$DOMAIN_LOWER"' -Y GSSAPI 2>/dev/null
'

# 4.6: CANNOT create in Agent Tools
check_fail "agent CANNOT create in Agent Tools" bash -c '
    echo "dn: CN=evil.tool,CN=Agent Tools,CN=System,'"$BASE_DN"'
changetype: add
objectClass: x-agentTool
cn: evil.tool
x-tool-Identifier: evil.tool" | KRB5CCNAME='"$CLAUDE_CC"' ldapmodify \
        -H ldap://dc1.'"$DOMAIN_LOWER"' -Y GSSAPI 2>/dev/null
'

# 4.7: CANNOT delete policy
check_fail "agent CANNOT delete policy" bash -c '
    echo "dn: CN=base-security,CN=Agent Policies,CN=System,'"$BASE_DN"'
changetype: delete" | KRB5CCNAME='"$CLAUDE_CC"' ldapmodify \
        -H ldap://dc1.'"$DOMAIN_LOWER"' -Y GSSAPI 2>/dev/null
'

# 4.8: CANNOT modify policy
check_fail "agent CANNOT modify policy" bash -c '
    echo "dn: CN=base-security,CN=Agent Policies,CN=System,'"$BASE_DN"'
changetype: modify
replace: x-policy-Priority
x-policy-Priority: 0" | KRB5CCNAME='"$CLAUDE_CC"' ldapmodify \
        -H ldap://dc1.'"$DOMAIN_LOWER"' -Y GSSAPI 2>/dev/null
'

# 4.9: CANNOT create in Agents container
check_fail "agent CANNOT create in Agents container" bash -c '
    echo "dn: CN=evil-agent\$,CN=Agents,CN=System,'"$BASE_DN"'
changetype: add
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: user
cn: evil-agent\$
sAMAccountName: evil-agent\$" | KRB5CCNAME='"$CLAUDE_CC"' ldapmodify \
        -H ldap://dc1.'"$DOMAIN_LOWER"' -Y GSSAPI 2>/dev/null
'

# 4.10: Coordinator can read Agent Tools (different agent)
COORD_CC=$(gssapi_kinit "coordinator-main") || { fail "kinit coordinator-main for ACL tests"; }

check "coordinator reads Agent Tools via GSSAPI" bash -c '
    KRB5CCNAME='"$COORD_CC"' ldapsearch -N -H ldap://dc1.'"$DOMAIN_LOWER"' \
        -Y GSSAPI -b "CN=Agent Tools,CN=System,'"$BASE_DN"'" \
        -s one "(objectClass=*)" cn 2>/dev/null | grep -q "^dn:"
'

# 4.11: CANNOT modify Agent Instructions container
check_fail "agent CANNOT modify Agent Instructions container" bash -c '
    echo "dn: CN=Agent Instructions,CN=System,'"$BASE_DN"'
changetype: modify
replace: description
description: hacked" | KRB5CCNAME='"$CLAUDE_CC"' ldapmodify \
        -H ldap://dc1.'"$DOMAIN_LOWER"' -Y GSSAPI 2>/dev/null
'

# 4.12: CANNOT modify other agent
check_fail "agent CANNOT modify other agent" bash -c '
    echo "dn: CN=data-processor-01\$,CN=Agents,CN=System,'"$BASE_DN"'
changetype: modify
replace: x-agent-Mission
x-agent-Mission: hacked" | KRB5CCNAME='"$CLAUDE_CC"' ldapmodify \
        -H ldap://dc1.'"$DOMAIN_LOWER"' -Y GSSAPI 2>/dev/null
'

# Clean up credential caches
kdestroy -c "$CLAUDE_CC" 2>/dev/null || true
kdestroy -c "$COORD_CC" 2>/dev/null || true

echo ""

# ══════════════════════════════════════════════════════════════════════════
# 5. SCHEMA ENFORCEMENT (8)
# ══════════════════════════════════════════════════════════════════════════
echo "--- 5. Schema Enforcement ---"

SCHEMA_TEST_DN_BASE="CN=Agent Policies,CN=System,$BASE_DN"
SCHEMA_TEST_TOOLS_DN_BASE="CN=Agent Tools,CN=System,$BASE_DN"
SCHEMA_TEST_GPO_DN_BASE="CN=Agent Instructions,CN=System,$BASE_DN"

# 5.1: Policy missing x-policy-Identifier
schema_reject "policy rejected: missing x-policy-Identifier" \
"dn: CN=schema-test-noid,${SCHEMA_TEST_DN_BASE}
changetype: add
objectClass: x-agentPolicy
cn: schema-test-noid
x-policy-Type: behavior
x-policy-Priority: 999"

# 5.2: Policy missing x-policy-Type
schema_reject "policy rejected: missing x-policy-Type" \
"dn: CN=schema-test-notype,${SCHEMA_TEST_DN_BASE}
changetype: add
objectClass: x-agentPolicy
cn: schema-test-notype
x-policy-Identifier: schema-test-notype
x-policy-Priority: 999"

# 5.3: Policy missing x-policy-Priority
schema_reject "policy rejected: missing x-policy-Priority" \
"dn: CN=schema-test-nopri,${SCHEMA_TEST_DN_BASE}
changetype: add
objectClass: x-agentPolicy
cn: schema-test-nopri
x-policy-Identifier: schema-test-nopri
x-policy-Type: behavior"

# 5.4: GPO missing x-gpo-InstructionPath
schema_reject "GPO rejected: missing x-gpo-InstructionPath" \
"dn: CN=schema-test-gpo-nopath,${SCHEMA_TEST_GPO_DN_BASE}
changetype: add
objectClass: x-agentInstructionGPO
cn: schema-test-gpo-nopath
x-gpo-Priority: 999"

# 5.5: GPO missing x-gpo-Priority
schema_reject "GPO rejected: missing x-gpo-Priority" \
"dn: CN=schema-test-gpo-nopri,${SCHEMA_TEST_GPO_DN_BASE}
changetype: add
objectClass: x-agentInstructionGPO
cn: schema-test-gpo-nopri
x-gpo-InstructionPath: AgentInstructions/test/instructions.md"

# 5.6: Tool missing x-tool-Identifier
schema_reject "tool rejected: missing x-tool-Identifier" \
"dn: CN=schema-test-tool-noid,${SCHEMA_TEST_TOOLS_DN_BASE}
changetype: add
objectClass: x-agentTool
cn: schema-test-tool-noid"

# 5.7: Invalid objectClass
schema_reject "rejected: invalid objectClass x-nonExistentClass" \
"dn: CN=schema-test-badclass,${SCHEMA_TEST_DN_BASE}
changetype: add
objectClass: x-nonExistentClass
cn: schema-test-badclass"

# 5.8: Positive control — policy with all MUST attrs succeeds
schema_accept "policy accepted: all required attrs present" \
"dn: CN=schema-test-ok,${SCHEMA_TEST_DN_BASE}
changetype: add
objectClass: x-agentPolicy
cn: schema-test-ok
x-policy-Identifier: schema-test-ok
x-policy-Type: behavior
x-policy-Priority: 999"
CLEANUP_DNS+=("CN=schema-test-ok,${SCHEMA_TEST_DN_BASE}")

echo ""

# ══════════════════════════════════════════════════════════════════════════
# 6. CRUD LIFECYCLE (14)
# ══════════════════════════════════════════════════════════════════════════
echo "--- 6. CRUD Lifecycle ---"

# ── Policy CRUD (7) ──

TEST_POLICY_DN="CN=test-crud-policy,CN=Agent Policies,CN=System,$BASE_DN"
TEST_AGENT_DN="CN=claude-assistant-01\$,CN=Agents,CN=System,$BASE_DN"

# 6.1: Create policy
schema_accept "CRUD: create policy" \
"dn: $TEST_POLICY_DN
changetype: add
objectClass: x-agentPolicy
cn: test-crud-policy
x-policy-Identifier: test-crud-policy
x-policy-Type: behavior
x-policy-Priority: 999
x-policy-Path: AgentPolicies/test-crud-policy/policy.json
x-policy-Enabled: TRUE
x-policy-Version: 1.0.0"
CLEANUP_DNS+=("$TEST_POLICY_DN")

# 6.2: Read policy
check "CRUD: read policy" \
    ldap_attr_eq "$TEST_POLICY_DN" "x-policy-Priority" "999"

# 6.3: Modify policy and verify
ldapmodify -H "$LDAP_URI" "${BIND_ARGS[@]}" <<EOF >/dev/null 2>&1
dn: $TEST_POLICY_DN
changetype: modify
replace: x-policy-Priority
x-policy-Priority: 998
EOF
check "CRUD: modify policy priority" \
    ldap_attr_eq "$TEST_POLICY_DN" "x-policy-Priority" "998"

# 6.4: Link policy to agent
schema_accept "CRUD: link policy to agent" \
"dn: $TEST_AGENT_DN
changetype: modify
add: x-agent-Policies
x-agent-Policies: $TEST_POLICY_DN"

# 6.5: Verify link is visible via ldapsearch
check "CRUD: policy link visible on agent" \
    ldap_attr_contains "$TEST_AGENT_DN" "x-agent-Policies" "test-crud-policy"

# 6.6: Unlink policy from agent
schema_accept "CRUD: unlink policy from agent" \
"dn: $TEST_AGENT_DN
changetype: modify
delete: x-agent-Policies
x-agent-Policies: $TEST_POLICY_DN"

# 6.7: Delete policy and verify
ldapmodify -H "$LDAP_URI" "${BIND_ARGS[@]}" <<EOF >/dev/null 2>&1
dn: $TEST_POLICY_DN
changetype: delete
EOF
unset 'CLEANUP_DNS[-1]'
check_fail "CRUD: delete policy (verify gone)" \
    ldap_entry_exists "$TEST_POLICY_DN"

# ── GPO CRUD (7) ──

TEST_GPO_DN="CN=test-crud-gpo,CN=Agent Instructions,CN=System,$BASE_DN"

# 6.8: Create GPO
schema_accept "CRUD: create GPO" \
"dn: $TEST_GPO_DN
changetype: add
objectClass: x-agentInstructionGPO
cn: test-crud-gpo
x-gpo-DisplayName: Test CRUD GPO
x-gpo-InstructionPath: AgentInstructions/test-crud-gpo/instructions.md
x-gpo-Priority: 999
x-gpo-MergeStrategy: append
x-gpo-Enabled: TRUE
x-gpo-Version: 1.0.0"
CLEANUP_DNS+=("$TEST_GPO_DN")

# 6.9: Read GPO
check "CRUD: read GPO" \
    ldap_attr_eq "$TEST_GPO_DN" "x-gpo-Priority" "999"

# 6.10: Modify GPO and verify
ldapmodify -H "$LDAP_URI" "${BIND_ARGS[@]}" <<EOF >/dev/null 2>&1
dn: $TEST_GPO_DN
changetype: modify
replace: x-gpo-Priority
x-gpo-Priority: 998
EOF
check "CRUD: modify GPO priority" \
    ldap_attr_eq "$TEST_GPO_DN" "x-gpo-Priority" "998"

# 6.11: Link GPO to agent
schema_accept "CRUD: link GPO to agent" \
"dn: $TEST_AGENT_DN
changetype: modify
add: x-agent-InstructionGPOs
x-agent-InstructionGPOs: $TEST_GPO_DN"

# 6.12: Verify link is visible via ldapsearch
check "CRUD: GPO link visible on agent" \
    ldap_attr_contains "$TEST_AGENT_DN" "x-agent-InstructionGPOs" "test-crud-gpo"

# 6.13: Unlink GPO from agent
schema_accept "CRUD: unlink GPO from agent" \
"dn: $TEST_AGENT_DN
changetype: modify
delete: x-agent-InstructionGPOs
x-agent-InstructionGPOs: $TEST_GPO_DN"

# 6.14: Delete GPO and verify
ldapmodify -H "$LDAP_URI" "${BIND_ARGS[@]}" <<EOF >/dev/null 2>&1
dn: $TEST_GPO_DN
changetype: delete
EOF
unset 'CLEANUP_DNS[-1]'
check_fail "CRUD: delete GPO (verify gone)" \
    ldap_entry_exists "$TEST_GPO_DN"

echo ""

# ══════════════════════════════════════════════════════════════════════════
# 7. DEFAULT OBJECTS & LINKAGE (16)
#
# Verify all bootstrapped policies, GPOs, and agent linkage using
# native Samba tooling (ldbsearch, samba-tool, ldapsearch).
# ══════════════════════════════════════════════════════════════════════════
echo "--- 7. Default Objects & Linkage ---"

POLICIES_DN="CN=Agent Policies,CN=System,$BASE_DN"
GPOS_DN="CN=Agent Instructions,CN=System,$BASE_DN"

# 7.1-7.4: Default policies — spot-check type + priority via ldbsearch
check "policy base-security: type=security priority=0" bash -c '
    ldbsearch -H '"$SAM_LDB"' -b "CN=base-security,'"$POLICIES_DN"'" \
        -s base "(objectClass=x-agentPolicy)" x-policy-Type x-policy-Priority 2>/dev/null \
        | grep -q "x-policy-Type: security" && \
    ldbsearch -H '"$SAM_LDB"' -b "CN=base-security,'"$POLICIES_DN"'" \
        -s base "(objectClass=x-agentPolicy)" x-policy-Priority 2>/dev/null \
        | grep -q "x-policy-Priority: 0"
'

check "policy type-worker: type=behavior priority=100" bash -c '
    ldbsearch -H '"$SAM_LDB"' -b "CN=type-worker,'"$POLICIES_DN"'" \
        -s base "(objectClass=x-agentPolicy)" x-policy-Type x-policy-Priority 2>/dev/null \
        | grep -q "x-policy-Type: behavior" && \
    ldbsearch -H '"$SAM_LDB"' -b "CN=type-worker,'"$POLICIES_DN"'" \
        -s base "(objectClass=x-agentPolicy)" x-policy-Priority 2>/dev/null \
        | grep -q "x-policy-Priority: 100"
'

check "policy trust-elevated: type=security priority=150" bash -c '
    ldbsearch -H '"$SAM_LDB"' -b "CN=trust-elevated,'"$POLICIES_DN"'" \
        -s base "(objectClass=x-agentPolicy)" x-policy-Type x-policy-Priority 2>/dev/null \
        | grep -q "x-policy-Type: security" && \
    ldbsearch -H '"$SAM_LDB"' -b "CN=trust-elevated,'"$POLICIES_DN"'" \
        -s base "(objectClass=x-agentPolicy)" x-policy-Priority 2>/dev/null \
        | grep -q "x-policy-Priority: 150"
'

check "policy capability-code-review: type=behavior priority=120" bash -c '
    ldbsearch -H '"$SAM_LDB"' -b "CN=capability-code-review,'"$POLICIES_DN"'" \
        -s base "(objectClass=x-agentPolicy)" x-policy-Type x-policy-Priority 2>/dev/null \
        | grep -q "x-policy-Type: behavior" && \
    ldbsearch -H '"$SAM_LDB"' -b "CN=capability-code-review,'"$POLICIES_DN"'" \
        -s base "(objectClass=x-agentPolicy)" x-policy-Priority 2>/dev/null \
        | grep -q "x-policy-Priority: 120"
'

# 7.5-7.7: Default GPOs — priority + merge via ldbsearch
check "GPO base-agent-instructions: priority=0 merge=append" bash -c '
    ldbsearch -H '"$SAM_LDB"' -b "CN=base-agent-instructions,'"$GPOS_DN"'" \
        -s base "(objectClass=x-agentInstructionGPO)" x-gpo-Priority x-gpo-MergeStrategy 2>/dev/null \
        | grep -q "x-gpo-Priority: 0" && \
    ldbsearch -H '"$SAM_LDB"' -b "CN=base-agent-instructions,'"$GPOS_DN"'" \
        -s base "(objectClass=x-agentInstructionGPO)" x-gpo-MergeStrategy 2>/dev/null \
        | grep -q "x-gpo-MergeStrategy: append"
'

check "GPO type-coordinator-instructions: priority=100" bash -c '
    ldbsearch -H '"$SAM_LDB"' -b "CN=type-coordinator-instructions,'"$GPOS_DN"'" \
        -s base "(objectClass=x-agentInstructionGPO)" x-gpo-Priority 2>/dev/null \
        | grep -q "x-gpo-Priority: 100"
'

check "GPO trust-elevated-instructions: priority=200" bash -c '
    ldbsearch -H '"$SAM_LDB"' -b "CN=trust-elevated-instructions,'"$GPOS_DN"'" \
        -s base "(objectClass=x-agentInstructionGPO)" x-gpo-Priority 2>/dev/null \
        | grep -q "x-gpo-Priority: 200"
'

# 7.8: All 6 GPOs have x-gpo-InstructionPath set (compound)
check "all 6 GPOs have InstructionPath" bash -c '
    for gpo in base-agent-instructions type-assistant-instructions \
               type-autonomous-instructions type-coordinator-instructions \
               type-tool-instructions trust-elevated-instructions; do
        ldbsearch -H '"$SAM_LDB"' -b "CN=$gpo,'"$GPOS_DN"'" \
            -s base "(objectClass=x-agentInstructionGPO)" x-gpo-InstructionPath 2>/dev/null \
            | grep -q "x-gpo-InstructionPath:" || exit 1
    done
'

# 7.9-7.11: Policy linkage per agent via ldapsearch
check "claude-assistant-01 linked to 4 policies" bash -c '
    for p in base-security base-behavior base-resource type-worker; do
        ldapsearch -N -H "'"$LDAP_URI"'" '"${BIND_ARGS[*]}"' \
            -b "CN=claude-assistant-01\$,CN=Agents,CN=System,'"$BASE_DN"'" \
            -s base "(objectClass=x-agent)" x-agent-Policies 2>/dev/null \
            | sed ":a; N; \$!ba; s/\n //g" \
            | grep -q "CN=$p" || exit 1
    done
'

check "data-processor-01 linked to 4 policies" bash -c '
    for p in base-security base-behavior base-resource type-worker; do
        ldapsearch -N -H "'"$LDAP_URI"'" '"${BIND_ARGS[*]}"' \
            -b "CN=data-processor-01\$,CN=Agents,CN=System,'"$BASE_DN"'" \
            -s base "(objectClass=x-agent)" x-agent-Policies 2>/dev/null \
            | sed ":a; N; \$!ba; s/\n //g" \
            | grep -q "CN=$p" || exit 1
    done
'

check "coordinator-main linked to 5 policies" bash -c '
    for p in base-security base-behavior base-resource type-coordinator trust-elevated; do
        ldapsearch -N -H "'"$LDAP_URI"'" '"${BIND_ARGS[*]}"' \
            -b "CN=coordinator-main\$,CN=Agents,CN=System,'"$BASE_DN"'" \
            -s base "(objectClass=x-agent)" x-agent-Policies 2>/dev/null \
            | sed ":a; N; \$!ba; s/\n //g" \
            | grep -q "CN=$p" || exit 1
    done
'

# 7.12-7.14: GPO linkage per agent
check "claude-assistant-01 GPOs: base-agent + type-assistant" bash -c '
    for g in base-agent-instructions type-assistant-instructions; do
        ldapsearch -N -H "'"$LDAP_URI"'" '"${BIND_ARGS[*]}"' \
            -b "CN=claude-assistant-01\$,CN=Agents,CN=System,'"$BASE_DN"'" \
            -s base "(objectClass=x-agent)" x-agent-InstructionGPOs 2>/dev/null \
            | sed ":a; N; \$!ba; s/\n //g" \
            | grep -q "CN=$g" || exit 1
    done
'

check "data-processor-01 GPOs: base-agent + type-autonomous" bash -c '
    for g in base-agent-instructions type-autonomous-instructions; do
        ldapsearch -N -H "'"$LDAP_URI"'" '"${BIND_ARGS[*]}"' \
            -b "CN=data-processor-01\$,CN=Agents,CN=System,'"$BASE_DN"'" \
            -s base "(objectClass=x-agent)" x-agent-InstructionGPOs 2>/dev/null \
            | sed ":a; N; \$!ba; s/\n //g" \
            | grep -q "CN=$g" || exit 1
    done
'

check "coordinator-main GPOs: base-agent + type-coordinator + trust-elevated" bash -c '
    for g in base-agent-instructions type-coordinator-instructions trust-elevated-instructions; do
        ldapsearch -N -H "'"$LDAP_URI"'" '"${BIND_ARGS[*]}"' \
            -b "CN=coordinator-main\$,CN=Agents,CN=System,'"$BASE_DN"'" \
            -s base "(objectClass=x-agent)" x-agent-InstructionGPOs 2>/dev/null \
            | sed ":a; N; \$!ba; s/\n //g" \
            | grep -q "CN=$g" || exit 1
    done
'

# 7.15: ldbsearch compound filter — all security-type policies
SECURITY_COUNT=$(ldbsearch -H "$SAM_LDB" \
    -b "$POLICIES_DN" -s one \
    "(&(objectClass=x-agentPolicy)(x-policy-Type=security))" dn 2>/dev/null \
    | grep -c "^dn:" || true)
if [ "$SECURITY_COUNT" -ge 4 ]; then
    pass "ldbsearch: at least 4 security-type policies (got $SECURITY_COUNT)"
else
    fail "ldbsearch: expected >= 4 security-type policies, got $SECURITY_COUNT"
fi

# 7.16: samba-tool user show displays custom x-agent attrs
check "samba-tool user show displays x-agent-Type" bash -c '
    samba-tool user show "coordinator-main\$" 2>/dev/null \
        | grep -q "x-agent-Type: coordinator"
'

echo ""

# ══════════════════════════════════════════════════════════════════════════
# 8. CONTENT VALIDATION (9)
# ══════════════════════════════════════════════════════════════════════════
echo "--- 8. Content Validation ---"

# 8.1-8.3: Policy JSON validity (3 representative files)
for policy in base-security base-behavior base-resource; do
    pfile="$SYSVOL/AgentPolicies/$policy/policy.json"
    if [ -f "$pfile" ]; then
        check "SYSVOL $policy: valid JSON" python3 -m json.tool "$pfile"
    else
        fail "SYSVOL $policy: file missing ($pfile)"
    fi
done

# 8.4-8.5: Policy JSON structure keys
check "base-security JSON has security-related settings" python3 -c "
import json, sys
with open('$SYSVOL/AgentPolicies/base-security/policy.json') as f:
    d = json.load(f)
s = d.get('settings', d)
assert any(k in s for k in ('security', 'sandbox', 'audit', 'credentials', 'tools')), \
    f'missing security settings, got: {list(s.keys())}'
"

check "base-resource JSON has resource-related settings" python3 -c "
import json, sys
with open('$SYSVOL/AgentPolicies/base-resource/policy.json') as f:
    d = json.load(f)
s = d.get('settings', d)
assert any(k in s for k in ('compute', 'storage', 'network', 'llm', 'resources', 'limits')), \
    f'missing resource settings, got: {list(s.keys())}'
"

# 8.6-8.7: Instruction markdown headings (2 representative files)
for gpo in base-agent-instructions type-coordinator-instructions; do
    ifile="$SYSVOL/AgentInstructions/$gpo/instructions.md"
    if [ -f "$ifile" ]; then
        check "SYSVOL $gpo: has markdown heading" \
            grep -q "^#" "$ifile"
    else
        fail "SYSVOL $gpo: file missing ($ifile)"
    fi
done

# 8.8: SYSVOL path resolution — GPO AD attribute → filesystem
check "SYSVOL path resolves for base-agent-instructions" bash -c '
    gpo_path=$(ldapsearch -N -H "'"$LDAP_URI"'" '"${BIND_ARGS[*]}"' \
        -b "CN=base-agent-instructions,CN=Agent Instructions,CN=System,'"$BASE_DN"'" \
        -s base "(objectClass=*)" x-gpo-InstructionPath 2>/dev/null \
        | sed ":a; N; \$!ba; s/\n //g" \
        | grep "^x-gpo-InstructionPath:" | sed "s/^x-gpo-InstructionPath: //")
    [ -n "$gpo_path" ] && [ -f "'"$SYSVOL"'/$gpo_path" ]
'

# 8.9: SYSVOL path resolution — policy AD attribute → filesystem
check "SYSVOL path resolves for base-security policy" bash -c '
    pol_path=$(ldapsearch -N -H "'"$LDAP_URI"'" '"${BIND_ARGS[*]}"' \
        -b "CN=base-security,CN=Agent Policies,CN=System,'"$BASE_DN"'" \
        -s base "(objectClass=*)" x-policy-Path 2>/dev/null \
        | grep "^x-policy-Path:" | sed "s/^x-policy-Path: //")
    [ -n "$pol_path" ] && [ -f "'"$SYSVOL"'/$pol_path" ]
'

echo ""

# ══════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    echo -e "\nFailures:$ERRORS"
    exit 1
fi
exit 0
