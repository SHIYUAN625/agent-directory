#!/bin/bash
# Bootstrap Sample Data
#
# Creates sample agents, sandboxes, tool grants, policy links, and groups.
# All operations use LDAP (ldapmodify/ldapsearch) through the running Samba.
#
# Usage: bootstrap-data.sh <domain> <admin-password>

set -euo pipefail

DOMAIN="${1:?Usage: bootstrap-data.sh <domain> <admin-password>}"
ADMIN_PASSWORD="${2:?Usage: bootstrap-data.sh <domain> <admin-password>}"
REALM="${DOMAIN^^}"
BASE_DN=$(echo "$DOMAIN" | sed 's/\./,DC=/g' | sed 's/^/DC=/')

AGENTS_DN="CN=Agents,CN=System,$BASE_DN"
SANDBOXES_DN="CN=Agent Sandboxes,CN=System,$BASE_DN"
TOOLS_DN="CN=Agent Tools,CN=System,$BASE_DN"
POLICIES_DN="CN=Agent Policies,CN=System,$BASE_DN"
INSTRUCTIONS_DN="CN=Agent Instructions,CN=System,$BASE_DN"
GROUPS_DN="OU=AgentGroups,$BASE_DN"

LDAP_URI="ldaps://localhost"
BIND_DN="CN=Administrator,CN=Users,$BASE_DN"

# TLS cert verification: 'allow' accepts self-signed certs but still
# requires TLS. This is safe for localhost bootstrap (Samba auto-generates
# its cert during provisioning). Production should use 'demand' with a real CA.
export LDAPTLS_REQCERT="${LDAPTLS_REQCERT:-allow}"

log() {
    echo "[$(date '+%H:%M:%S')] [data] $1"
}

# LDAP modify helper — all data ops go through the running Samba over TLS
ldap_modify() {
    ldapmodify -H "$LDAP_URI" -x -D "$BIND_DN" -w "$ADMIN_PASSWORD" 2>&1
}

# LDAP search helper
ldap_search() {
    ldapsearch -H "$LDAP_URI" -x -D "$BIND_DN" -w "$ADMIN_PASSWORD" "$@" 2>/dev/null
}

# Helper: create agent via samba-tool, move to Agents container, apply x-agent attrs
create_agent() {
    local name="$1"
    local type="$2"
    local trust="$3"
    local model="$4"
    local mission="$5"

    local sam_name="${name}\$"
    local user_dn="CN=${sam_name},CN=Users,$BASE_DN"
    local agent_dn="CN=${sam_name},$AGENTS_DN"

    log "Creating agent: $name (type=$type, trust=$trust, model=$model)"

    # Create the user account with $ suffix (machine account convention)
    local output
    if output=$(samba-tool user create "$sam_name" --random-password \
        --description="AI Agent: $type" 2>&1); then
        :
    elif echo "$output" | grep -qiE 'already exists|NT_STATUS_USER_EXISTS'; then
        log "  Agent account already exists, continuing: $sam_name"
    else
        log "  ERROR: Failed to create agent account $sam_name"
        log "         $output"
        return 1
    fi

    # Move from Users to Agents container via LDAP ModifyDN
    if ldap_search -b "$user_dn" -s base dn | grep -q "^dn:"; then
        ldap_modify <<EOF
dn: $user_dn
changetype: modrdn
newrdn: CN=${sam_name}
deleteoldrdn: 1
newsuperior: $AGENTS_DN
EOF
    fi

    # Step 1: Add x-agent objectClass
    ldap_modify <<EOF
dn: $agent_dn
changetype: modify
add: objectClass
objectClass: x-agent
EOF

    # Step 2: Add agent attributes (separate operation so objectClass is committed first)
    ldap_modify <<EOF
dn: $agent_dn
changetype: modify
add: x-agent-Type
x-agent-Type: $type
-
add: x-agent-TrustLevel
x-agent-TrustLevel: $trust
-
add: x-agent-Model
x-agent-Model: $model
-
add: x-agent-Mission
x-agent-Mission: $mission
-
add: x-agent-AuditLevel
x-agent-AuditLevel: 1
EOF

    log "  Created agent: $agent_dn"
}

# Helper: create sandbox via samba-tool computer, move to Sandboxes, apply x-agentSandbox attrs
create_sandbox() {
    local name="$1"
    local profile="$2"
    local status="$3"
    local output

    local computer_dn="CN=${name},CN=Computers,$BASE_DN"
    local sandbox_dn="CN=${name},$SANDBOXES_DN"

    log "Creating sandbox: $name (profile=$profile, status=$status)"

    # Create the computer account
    if output=$(samba-tool computer create "$name" \
        --description="Agent Sandbox: $profile" 2>&1); then
        :
    elif echo "$output" | grep -qiE 'already exists|NT_STATUS_OBJECT_NAME_COLLISION'; then
        log "  Sandbox computer already exists, continuing: $name"
    else
        log "  ERROR: Failed to create sandbox computer $name"
        log "         $output"
        return 1
    fi

    # Move from Computers to Agent Sandboxes container
    if ldap_search -b "$computer_dn" -s base dn | grep -q "^dn:"; then
        ldap_modify <<EOF
dn: $computer_dn
changetype: modrdn
newrdn: CN=${name}
deleteoldrdn: 1
newsuperior: $SANDBOXES_DN
EOF
    fi

    # Step 1: Add x-agentSandbox objectClass
    ldap_modify <<EOF
dn: $sandbox_dn
changetype: modify
add: objectClass
objectClass: x-agentSandbox
EOF

    # Step 2: Add sandbox attributes
    ldap_modify <<EOF
dn: $sandbox_dn
changetype: modify
add: x-sandbox-SecurityProfile
x-sandbox-SecurityProfile: $profile
-
add: x-sandbox-Status
x-sandbox-Status: $status
-
add: x-sandbox-Endpoint
x-sandbox-Endpoint: unix:///var/run/sandbox/${name}.sock
-
add: x-sandbox-ResourcePolicy
x-sandbox-ResourcePolicy: {"cpu": "2.0", "memory": "4Gi", "disk": "20Gi"}
-
add: x-sandbox-NetworkPolicy
x-sandbox-NetworkPolicy: {"egress": "restricted", "ingress": "deny"}
EOF

    log "  Created sandbox: $sandbox_dn"
}

# Helper: grant tool to agent
grant_tool() {
    local agent_name="$1"
    local tool_id="$2"

    local sam_name="${agent_name}\$"
    local agent_dn="CN=${sam_name},$AGENTS_DN"
    local tool_dn="CN=${tool_id},$TOOLS_DN"

    ldap_modify <<EOF
dn: $agent_dn
changetype: modify
add: x-agent-AuthorizedTools
x-agent-AuthorizedTools: $tool_dn
EOF
}

# Helper: link policy to agent
link_policy() {
    local agent_name="$1"
    local policy_name="$2"

    local sam_name="${agent_name}\$"
    local agent_dn="CN=${sam_name},$AGENTS_DN"
    local policy_dn="CN=${policy_name},$POLICIES_DN"

    ldap_modify <<EOF
dn: $agent_dn
changetype: modify
add: x-agent-Policies
x-agent-Policies: $policy_dn
EOF
}

# Helper: link agent to sandbox (both directions)
link_agent_sandbox() {
    local agent_name="$1"
    local sandbox_name="$2"

    local sam_name="${agent_name}\$"
    local agent_dn="CN=${sam_name},$AGENTS_DN"
    local sandbox_dn="CN=${sandbox_name},$SANDBOXES_DN"

    # Agent -> Sandbox
    ldap_modify <<EOF
dn: $agent_dn
changetype: modify
add: x-agent-Sandbox
x-agent-Sandbox: $sandbox_dn
EOF

    # Sandbox -> Agent
    ldap_modify <<EOF
dn: $sandbox_dn
changetype: modify
add: x-sandbox-Agents
x-sandbox-Agents: $agent_dn
EOF
}

# Helper: link instruction GPO to agent
link_instruction_gpo() {
    local agent_name="$1"
    local gpo_name="$2"

    local sam_name="${agent_name}\$"
    local agent_dn="CN=${sam_name},$AGENTS_DN"
    local gpo_dn="CN=${gpo_name},$INSTRUCTIONS_DN"

    ldap_modify <<EOF
dn: $agent_dn
changetype: modify
add: x-agent-InstructionGPOs
x-agent-InstructionGPOs: $gpo_dn
EOF
}

# Helper: add agent to group
add_to_group() {
    local agent_name="$1"
    local group_name="$2"

    local sam_name="${agent_name}\$"
    local group_dn="CN=${group_name},$GROUPS_DN"
    local agent_dn="CN=${sam_name},$AGENTS_DN"
    local output

    if output=$(samba-tool group addmembers "$group_name" "$sam_name" 2>&1); then
        :
    else
        # Idempotent reruns may report that membership already exists.
        if echo "$output" | grep -qiE 'already.*member|NT_STATUS_MEMBER_IN_GROUP'; then
            :
        else
            log "  ERROR: Could not add $agent_name to $group_name"
            log "         $output"
            return 1
        fi
    fi

    # Verify membership so bootstrap cannot silently drift.
    if ldap_search -b "$group_dn" -s base member \
        | sed ':a; N; $!ba; s/\n //g' \
        | grep -Fq "$agent_dn"; then
        return 0
    fi

    log "  ERROR: Membership verification failed for $agent_name in $group_name"
    return 1
}

# ============================================================================
# CREATE AGENTS
# ============================================================================
log "=== Creating Agents ==="

create_agent "claude-assistant-01" "assistant" "2" "claude-opus-4-5" \
    "General-purpose coding assistant for engineering team"

create_agent "data-processor-01" "autonomous" "2" "claude-sonnet-4" \
    "Autonomous data pipeline processor and ETL agent"

create_agent "coordinator-main" "coordinator" "3" "claude-opus-4-5" \
    "Primary coordinator for multi-agent task orchestration"

# Set NATS subjects
log "Setting NATS subjects..."
ldap_modify <<EOF
dn: CN=claude-assistant-01\$,$AGENTS_DN
changetype: modify
add: x-agent-NatsSubjects
x-agent-NatsSubjects: tasks.assistant.claude-assistant-01
x-agent-NatsSubjects: escalations.team.engineering
EOF

ldap_modify <<EOF
dn: CN=data-processor-01\$,$AGENTS_DN
changetype: modify
add: x-agent-NatsSubjects
x-agent-NatsSubjects: tasks.data.pipeline
x-agent-NatsSubjects: tasks.data.etl
EOF

ldap_modify <<EOF
dn: CN=coordinator-main\$,$AGENTS_DN
changetype: modify
add: x-agent-NatsSubjects
x-agent-NatsSubjects: tasks.coordination
x-agent-NatsSubjects: escalations.all
x-agent-NatsSubjects: system.health
EOF

# Set LLM access
log "Setting LLM access..."
ldap_modify <<EOF
dn: CN=claude-assistant-01\$,$AGENTS_DN
changetype: modify
add: x-agent-LLMAccess
x-agent-LLMAccess: claude-opus-4-5
x-agent-LLMAccess: claude-sonnet-4
-
add: x-agent-LLMQuota
x-agent-LLMQuota: {"daily_tokens": 2000000, "max_context": 200000}
EOF

ldap_modify <<EOF
dn: CN=data-processor-01\$,$AGENTS_DN
changetype: modify
add: x-agent-LLMAccess
x-agent-LLMAccess: claude-sonnet-4
-
add: x-agent-LLMQuota
x-agent-LLMQuota: {"daily_tokens": 5000000, "max_context": 100000}
EOF

ldap_modify <<EOF
dn: CN=coordinator-main\$,$AGENTS_DN
changetype: modify
add: x-agent-LLMAccess
x-agent-LLMAccess: claude-opus-4-5
x-agent-LLMAccess: claude-sonnet-4
x-agent-LLMAccess: claude-haiku-4-5
-
add: x-agent-LLMQuota
x-agent-LLMQuota: {"daily_tokens": 10000000, "max_context": 200000}
EOF

# Set escalation paths
log "Setting escalation paths..."
ldap_modify <<EOF
dn: CN=claude-assistant-01\$,$AGENTS_DN
changetype: modify
add: x-agent-EscalationPath
x-agent-EscalationPath: CN=coordinator-main\$,$AGENTS_DN
EOF

ldap_modify <<EOF
dn: CN=data-processor-01\$,$AGENTS_DN
changetype: modify
add: x-agent-EscalationPath
x-agent-EscalationPath: CN=coordinator-main\$,$AGENTS_DN
EOF

# ============================================================================
# CREATE SANDBOXES
# ============================================================================
log "=== Creating Sandboxes ==="

create_sandbox "sandbox-prod-001" "bwrap" "active"
create_sandbox "sandbox-dev-001" "none" "active"

# ============================================================================
# LINK AGENTS TO SANDBOXES
# ============================================================================
log "=== Linking Agents to Sandboxes ==="

link_agent_sandbox "claude-assistant-01" "sandbox-prod-001"
link_agent_sandbox "coordinator-main" "sandbox-prod-001"
link_agent_sandbox "data-processor-01" "sandbox-dev-001"

# ============================================================================
# GRANT TOOLS
# ============================================================================
log "=== Granting Tools ==="

# claude-assistant-01: coding assistant tools
log "Granting tools to claude-assistant-01..."
for tool in filesystem.read filesystem.write git.cli python.interpreter llm.inference; do
    grant_tool "claude-assistant-01" "$tool"
done

# data-processor-01: data pipeline tools
log "Granting tools to data-processor-01..."
for tool in filesystem.read filesystem.write python.interpreter database.postgresql \
            database.redis jq.processor api.http llm.inference nats.client; do
    grant_tool "data-processor-01" "$tool"
done

# coordinator-main: coordination and management tools
log "Granting tools to coordinator-main..."
for tool in filesystem.read git.cli llm.inference agent.spawn agent.delegate \
            nats.client ldap.search ray.submit ray.status; do
    grant_tool "coordinator-main" "$tool"
done

# ============================================================================
# LINK POLICIES
# ============================================================================
log "=== Linking Policies ==="

# Base policies for all agents
for agent in claude-assistant-01 data-processor-01 coordinator-main; do
    log "Linking base policies to $agent..."
    for policy in base-security base-behavior base-resource; do
        link_policy "$agent" "$policy"
    done
done

# Type-specific policies
log "Linking type-specific policies..."
link_policy "claude-assistant-01" "type-worker"
link_policy "data-processor-01" "type-worker"
link_policy "coordinator-main" "type-coordinator"

# Trust-level policies
log "Linking trust-level policies..."
link_policy "coordinator-main" "trust-elevated"

# ============================================================================
# LINK INSTRUCTION GPOs
# ============================================================================
log "=== Linking Instruction GPOs ==="

# Base instructions for all agents
for agent in claude-assistant-01 data-processor-01 coordinator-main; do
    log "Linking base instruction GPO to $agent..."
    link_instruction_gpo "$agent" "base-agent-instructions"
done

# Type-specific instruction GPOs
log "Linking type-specific instruction GPOs..."
link_instruction_gpo "claude-assistant-01" "type-assistant-instructions"
link_instruction_gpo "data-processor-01" "type-autonomous-instructions"
link_instruction_gpo "coordinator-main" "type-coordinator-instructions"

# Trust-level instruction GPOs
log "Linking trust-level instruction GPOs..."
link_instruction_gpo "coordinator-main" "trust-elevated-instructions"

# ============================================================================
# ORGANIZATIONAL STRUCTURE (Groups)
# ============================================================================
#
# Groups model the agent company's org structure:
#
# Team groups (routing — determines which NATS task queue an agent subscribes to):
#   Team-Engineering    → tasks.engineering   (code review, development, testing)
#   Team-DataOps        → tasks.dataops       (data pipelines, ETL, analysis)
#   Team-Coordination   → tasks.coordination  (orchestration, workforce management)
#
# Tier groups (authorization — trust level classification):
#   Tier1-Workers       → standard workers, trust level 1-2
#   Tier3-Coordinators  → coordinators with elevated trust, level 3+
#
# ToolAccess groups (authorization — tool category grants):
#   ToolAccess-Development → filesystem, git, interpreters
#   ToolAccess-Network     → api.http, nats.client, database access
#   ToolAccess-Management  → agent.spawn, agent.delegate, ldap.search
#
# Within each team, individual agents bring different skillsets defined by
# their tools, model, trust level, and policies. The coordinator routes work
# to teams (not individuals), and JetStream work queues distribute within the team.
#
log "=== Creating Organizational Structure ==="

# --- Create AgentGroups OU ---
log "Creating AgentGroups OU..."
ldap_modify <<EOF
dn: $GROUPS_DN
changetype: add
objectClass: organizationalUnit
ou: AgentGroups
description: Agent team and capability groups
EOF

# Helper: create a group via samba-tool, then move to AgentGroups OU
create_group() {
    local name="$1"
    local description="$2"

    local users_dn="CN=${name},CN=Users,$BASE_DN"
    local group_dn="CN=${name},$GROUPS_DN"

    log "  Creating group: $name"
    local output
    if output=$(samba-tool group add "$name" --description="$description" 2>&1); then
        :
    else
        if echo "$output" | grep -qiE 'already exists|entry already exists'; then
            :
        else
            log "  ERROR: Could not create group $name"
            log "         $output"
            return 1
        fi
    fi

    # Move from CN=Users to OU=AgentGroups
    if ldap_search -b "$users_dn" -s base dn | grep -q "^dn:"; then
        ldap_modify <<EOF
dn: $users_dn
changetype: modrdn
newrdn: CN=${name}
deleteoldrdn: 1
newsuperior: $GROUPS_DN
EOF
    fi

    if ldap_search -b "$group_dn" -s base dn | grep -q "^dn:"; then
        return 0
    fi

    log "  ERROR: Group verification failed for $name"
    return 1
}

# --- Team groups (routing) ---
log "Creating team groups..."
create_group "Team-Engineering" \
    "Engineering team: code review, development, testing" || exit 1
create_group "Team-DataOps" \
    "Data operations team: data pipelines, ETL, analysis" || exit 1
create_group "Team-Coordination" \
    "Coordination team: orchestration, workforce management" || exit 1

# --- Tier groups (authorization) ---
log "Creating tier groups..."
create_group "Tier1-Workers" \
    "Standard worker agents, trust level 1-2" || exit 1
create_group "Tier3-Coordinators" \
    "Coordinator agents with elevated trust, level 3+" || exit 1

# --- ToolAccess groups (authorization) ---
log "Creating tool-access groups..."
create_group "ToolAccess-Development" \
    "Access to development tools: filesystem, git, interpreters" || exit 1
create_group "ToolAccess-Network" \
    "Access to network tools: api.http, nats.client, databases" || exit 1
create_group "ToolAccess-Management" \
    "Access to management tools: agent.spawn, agent.delegate, ldap.search" || exit 1

# --- Team memberships ---
# Each agent is assigned to the team whose work queue they pull from.
log "Assigning agents to teams..."
add_to_group "claude-assistant-01" "Team-Engineering" || exit 1
add_to_group "data-processor-01"   "Team-DataOps" || exit 1
add_to_group "coordinator-main"    "Team-Coordination" || exit 1

# --- Tier memberships ---
log "Assigning agents to tiers..."
add_to_group "claude-assistant-01" "Tier1-Workers" || exit 1
add_to_group "data-processor-01"   "Tier1-Workers" || exit 1
add_to_group "coordinator-main"    "Tier3-Coordinators" || exit 1

# --- ToolAccess memberships ---
# Individual skillsets: each agent has different tool capabilities within their team.
log "Assigning agents to tool-access groups..."
add_to_group "claude-assistant-01" "ToolAccess-Development" || exit 1

add_to_group "data-processor-01"   "ToolAccess-Development" || exit 1
add_to_group "data-processor-01"   "ToolAccess-Network" || exit 1

add_to_group "coordinator-main"    "ToolAccess-Management" || exit 1

# ============================================================================
# SPNs + KEYTABS for all agents
# ============================================================================
log "=== Setting up SPNs and Keytabs ==="

KEYTAB_DIR="/var/lib/samba/keytabs"
mkdir -p "$KEYTAB_DIR"

# Generate SPNs and keytabs for all agents
for agent_name in claude-assistant-01 data-processor-01 coordinator-main; do
    log "Registering SPN for $agent_name..."
    samba-tool spn add "agent/${agent_name}.${DOMAIN}" "${agent_name}\$" 2>&1 || true

    log "Generating keytab for $agent_name..."
    samba-tool domain exportkeytab "$KEYTAB_DIR/${agent_name}.keytab" \
        --principal="${agent_name}\$@$REALM" 2>&1 || true
    chmod 600 "$KEYTAB_DIR/${agent_name}.keytab" 2>/dev/null || true
done

# ============================================================================
# SUMMARY
# ============================================================================
log "=== Bootstrap Data Summary ==="
log "Agents created:      3 (claude-assistant-01, data-processor-01, coordinator-main)"
log "Sandboxes created:   2 (sandbox-prod-001, sandbox-dev-001)"
log "Tool grants:         applied to all agents"
log "Policy links:        base + type-specific per agent"
log "Instruction GPOs:    base + type-specific + trust-elevated per agent"
log "Teams:               Engineering, DataOps, Coordination"
log "Tier groups:         Tier1-Workers, Tier3-Coordinators"
log "ToolAccess groups:   Development, Network, Management"
log "SPN/Keytab:          all 3 agents"
log ""
log "Org structure:"
log "  Team-Engineering:   claude-assistant-01 (assistant, trust=2, coding tools)"
log "  Team-DataOps:       data-processor-01   (autonomous, trust=2, data tools)"
log "  Team-Coordination:  coordinator-main    (coordinator, trust=3, mgmt tools)"
log ""
log "Data bootstrap complete"
