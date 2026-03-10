# Samba4 AD DC - Agent Directory Dev Environment
#
# Usage:
#   make up              Start DC (build + provision on first run)
#   make down            Stop (keeps data)
#   make reset           Destroy everything including volumes
#   make shell           Shell into container
#   make logs            Tail logs
#   make list-agents     List all agents
#   make list-sandboxes
#   make list-tools
#   make list-policies
#   make list-instructions  List all instruction GPOs
#   make get-agent AGENT=claude-assistant-01
#   make get-instructions AGENT=claude-assistant-01
#   make create-agent NAME=my-agent TYPE=assistant TRUST=2
#   make grant-tool AGENT=my-agent TOOL=git.cli
#   make link-policy AGENT=my-agent POLICY=base-security
#   make link-gpo AGENT=my-agent GPO=base-agent-instructions
#   make test-schema     Verify custom schema classes
#   make status          Domain info
#
# Agent Runner (Direct Auth):
#   make run-agent AGENT=claude-assistant-01    Launch agent (DC-enforced, agent's own identity)
#   make dry-run AGENT=claude-assistant-01      Show assembled config (no launch)
#   make agent-shell                            Shell into agent container
#   make verify-acls                            Test DC ACL enforcement
#   make submit-goal TITLE="Quarterly close automation" DESCRIPTION="Coordinate engineering + dataops"
#   make run-coordinator [AGENT=coordinator-main]
#   make run-worker AGENT=claude-assistant-01

# Read .env if present (same file docker-compose uses)
-include .env

COMPOSE = docker compose
CONTAINER = agent-directory-dc
DOMAIN = autonomy.local
BASE_DN = DC=autonomy,DC=local
ADMIN_PASSWORD := $(or $(SAMBA_ADMIN_PASSWORD),$(error SAMBA_ADMIN_PASSWORD not set. Copy .env.example to .env and set a password))
LDAP_URI = ldaps://localhost
DEFAULT_ROUTE_TEAMS = engineering,dataops

# TLS cert verification: 'allow' accepts Samba's self-signed cert.
# In production, use 'demand' with a proper CA cert.
LDAPTLS = LDAPTLS_REQCERT=allow

LDAPSEARCH = $(LDAPTLS) ldapsearch -H $(LDAP_URI) -x -D "CN=Administrator,CN=Users,$(BASE_DN)" -w "$(ADMIN_PASSWORD)"
LDAPMODIFY = $(LDAPTLS) ldapmodify -H $(LDAP_URI) -x -D "CN=Administrator,CN=Users,$(BASE_DN)" -w "$(ADMIN_PASSWORD)"

.PHONY: up down reset shell logs status \
        list-agents list-sandboxes list-tools list-policies list-instructions \
        get-agent get-instructions \
        create-agent grant-tool link-policy link-gpo test-schema \
        test-policies test-instructions test-all \
        run-agent dry-run agent-shell build-agent verify-acls integration-test \
        e2e-test submit-goal run-coordinator run-worker

# ============================================================================
# LIFECYCLE
# ============================================================================

up:
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

reset:
	$(COMPOSE) down -v
	@echo "All data destroyed. Next 'make up' will re-provision."

shell:
	docker exec -it $(CONTAINER) bash

logs:
	$(COMPOSE) logs -f

# ============================================================================
# QUERIES
# ============================================================================

status:
	docker exec $(CONTAINER) samba-tool domain info $(DOMAIN)

list-agents:
	@$(LDAPSEARCH) -b "CN=Agents,CN=System,$(BASE_DN)" \
		"(objectClass=x-agent)" \
		cn x-agent-Type x-agent-TrustLevel x-agent-Model 2>/dev/null \
		| grep -E "^(dn|cn|x-agent-)" || echo "No agents found (is the DC running?)"

list-sandboxes:
	@$(LDAPSEARCH) -b "CN=Agent Sandboxes,CN=System,$(BASE_DN)" \
		"(objectClass=x-agentSandbox)" \
		cn x-sandbox-SecurityProfile x-sandbox-Status x-sandbox-Agents 2>/dev/null \
		| grep -E "^(dn|cn|x-sandbox-)" || echo "No sandboxes found (is the DC running?)"

list-tools:
	@$(LDAPSEARCH) -b "CN=Agent Tools,CN=System,$(BASE_DN)" \
		"(objectClass=x-agentTool)" \
		cn x-tool-Identifier x-tool-Category x-tool-RiskLevel 2>/dev/null \
		| grep -E "^(dn|cn|x-tool-)" || echo "No tools found (is the DC running?)"

list-policies:
	@$(LDAPSEARCH) -b "CN=Agent Policies,CN=System,$(BASE_DN)" \
		"(objectClass=x-agentPolicy)" \
		cn x-policy-Identifier x-policy-Type x-policy-Priority x-policy-Enabled 2>/dev/null \
		| grep -E "^(dn|cn|x-policy-)" || echo "No policies found (is the DC running?)"

list-instructions:
	@$(LDAPSEARCH) -b "CN=Agent Instructions,CN=System,$(BASE_DN)" \
		"(objectClass=x-agentInstructionGPO)" \
		cn x-gpo-DisplayName x-gpo-Priority x-gpo-MergeStrategy \
		x-gpo-AppliesToTypes x-gpo-Enabled x-gpo-Version 2>/dev/null \
		| grep -E "^(dn|cn|x-gpo-)" || echo "No instruction GPOs found (is the DC running?)"

get-agent:
ifndef AGENT
	$(error AGENT is required. Usage: make get-agent AGENT=claude-assistant-01)
endif
	@$(LDAPSEARCH) -b "CN=$(AGENT)\$$,CN=Agents,CN=System,$(BASE_DN)" \
		"(objectClass=x-agent)" \
		cn x-agent-Type x-agent-TrustLevel x-agent-Model x-agent-Mission \
		x-agent-AuthorizedTools x-agent-Policies x-agent-InstructionGPOs \
		x-agent-NatsSubjects x-agent-LLMAccess x-agent-LLMQuota \
		x-agent-EscalationPath x-agent-Sandbox x-agent-AuditLevel memberOf 2>/dev/null \
		|| echo "Agent '$(AGENT)' not found"

get-instructions:
ifndef AGENT
	$(error AGENT is required. Usage: make get-instructions AGENT=claude-assistant-01)
endif
	@echo "=== Instruction GPOs linked to $(AGENT) ==="
	@$(LDAPSEARCH) -b "CN=$(AGENT)\$$,CN=Agents,CN=System,$(BASE_DN)" \
		"(objectClass=x-agent)" x-agent-InstructionGPOs 2>/dev/null \
		| grep "x-agent-InstructionGPOs" || echo "No instruction GPOs linked"
	@echo ""
	@echo "=== Instruction GPOs matching by scope ==="
	@$(LDAPSEARCH) -b "CN=Agent Instructions,CN=System,$(BASE_DN)" \
		"(&(objectClass=x-agentInstructionGPO)(x-gpo-Enabled=TRUE))" \
		cn x-gpo-DisplayName x-gpo-Priority x-gpo-MergeStrategy \
		x-gpo-InstructionPath x-gpo-AppliesToTypes 2>/dev/null \
		| grep -E "^(dn|cn|x-gpo-)" || echo "No instruction GPOs found"

# ============================================================================
# MUTATIONS
# ============================================================================

create-agent:
ifndef NAME
	$(error NAME is required. Usage: make create-agent NAME=my-agent TYPE=assistant TRUST=2)
endif
	docker exec $(CONTAINER) agent-manager agent create $(NAME) \
		--type $(or $(TYPE),autonomous) \
		--trust-level $(or $(TRUST),2) \
		$(if $(MODEL),--model $(MODEL)) \
		--domain $(DOMAIN) \
		--bind-pw "$(ADMIN_PASSWORD)"

grant-tool:
ifndef AGENT
	$(error AGENT is required. Usage: make grant-tool AGENT=my-agent TOOL=git.cli)
endif
ifndef TOOL
	$(error TOOL is required. Usage: make grant-tool AGENT=my-agent TOOL=git.cli)
endif
	docker exec $(CONTAINER) agent-manager tool grant $(AGENT) $(TOOL) \
		--domain $(DOMAIN) \
		--bind-pw "$(ADMIN_PASSWORD)"

link-policy:
ifndef AGENT
	$(error AGENT is required. Usage: make link-policy AGENT=my-agent POLICY=base-security)
endif
ifndef POLICY
	$(error POLICY is required. Usage: make link-policy AGENT=my-agent POLICY=base-security)
endif
	docker exec $(CONTAINER) agent-manager policy link $(AGENT) $(POLICY) \
		--domain $(DOMAIN) \
		--bind-pw "$(ADMIN_PASSWORD)"

link-gpo:
ifndef AGENT
	$(error AGENT is required. Usage: make link-gpo AGENT=my-agent GPO=base-agent-instructions)
endif
ifndef GPO
	$(error GPO is required. Usage: make link-gpo AGENT=my-agent GPO=base-agent-instructions)
endif
	docker exec $(CONTAINER) agent-manager gpo link $(AGENT) $(GPO) \
		--domain $(DOMAIN) \
		--bind-pw "$(ADMIN_PASSWORD)"

# ============================================================================
# VERIFICATION
# ============================================================================

test-schema:
	@echo "=== Checking x-agent class ==="
	@$(LDAPSEARCH) -b "CN=Schema,CN=Configuration,$(BASE_DN)" \
		"(cn=x-agent)" cn objectClass 2>/dev/null \
		| grep -q "cn: x-agent" && echo "OK: x-agent class exists" \
		|| echo "FAIL: x-agent class not found"
	@echo ""
	@echo "=== Checking x-agentSandbox class ==="
	@$(LDAPSEARCH) -b "CN=Schema,CN=Configuration,$(BASE_DN)" \
		"(cn=x-agentSandbox)" cn objectClass 2>/dev/null \
		| grep -q "cn: x-agentSandbox" && echo "OK: x-agentSandbox class exists" \
		|| echo "FAIL: x-agentSandbox class not found"
	@echo ""
	@echo "=== Checking x-agentTool class ==="
	@$(LDAPSEARCH) -b "CN=Schema,CN=Configuration,$(BASE_DN)" \
		"(cn=x-agentTool)" cn objectClass 2>/dev/null \
		| grep -q "cn: x-agentTool" && echo "OK: x-agentTool class exists" \
		|| echo "FAIL: x-agentTool class not found"
	@echo ""
	@echo "=== Checking x-agentPolicy class ==="
	@$(LDAPSEARCH) -b "CN=Schema,CN=Configuration,$(BASE_DN)" \
		"(cn=x-agentPolicy)" cn objectClass 2>/dev/null \
		| grep -q "cn: x-agentPolicy" && echo "OK: x-agentPolicy class exists" \
		|| echo "FAIL: x-agentPolicy class not found"
	@echo ""
	@echo "=== Checking x-agentInstructionGPO class ==="
	@$(LDAPSEARCH) -b "CN=Schema,CN=Configuration,$(BASE_DN)" \
		"(cn=x-agentInstructionGPO)" cn objectClass 2>/dev/null \
		| grep -q "cn: x-agentInstructionGPO" && echo "OK: x-agentInstructionGPO class exists" \
		|| echo "FAIL: x-agentInstructionGPO class not found"
	@echo ""
	@echo "=== Checking containers ==="
	@$(LDAPSEARCH) -b "CN=Agents,CN=System,$(BASE_DN)" -s base dn 2>/dev/null \
		| grep -q "dn:" && echo "OK: Agents container exists" \
		|| echo "FAIL: Agents container not found"
	@$(LDAPSEARCH) -b "CN=Agent Sandboxes,CN=System,$(BASE_DN)" -s base dn 2>/dev/null \
		| grep -q "dn:" && echo "OK: Agent Sandboxes container exists" \
		|| echo "FAIL: Agent Sandboxes container not found"
	@$(LDAPSEARCH) -b "CN=Agent Tools,CN=System,$(BASE_DN)" -s base dn 2>/dev/null \
		| grep -q "dn:" && echo "OK: Agent Tools container exists" \
		|| echo "FAIL: Agent Tools container not found"
	@$(LDAPSEARCH) -b "CN=Agent Policies,CN=System,$(BASE_DN)" -s base dn 2>/dev/null \
		| grep -q "dn:" && echo "OK: Agent Policies container exists" \
		|| echo "FAIL: Agent Policies container not found"
	@$(LDAPSEARCH) -b "CN=Agent Instructions,CN=System,$(BASE_DN)" -s base dn 2>/dev/null \
		| grep -q "dn:" && echo "OK: Agent Instructions container exists" \
		|| echo "FAIL: Agent Instructions container not found"

test-policies:
	@echo "=== Checking Default Policy Objects ==="
	@for policy in base-security base-behavior base-resource base-network \
	               type-worker type-coordinator type-tool \
	               trust-untrusted trust-elevated \
	               capability-code-review capability-security-analysis; do \
		$(LDAPSEARCH) -b "CN=$$policy,CN=Agent Policies,CN=System,$(BASE_DN)" \
			-s base "(objectClass=x-agentPolicy)" cn x-policy-Type x-policy-Priority 2>/dev/null \
			| grep -q "cn: $$policy" \
			&& echo "  OK: policy $$policy exists" \
			|| echo "  FAIL: policy $$policy not found"; \
	done
	@echo ""
	@echo "=== Checking Policy Linkage on Agents ==="
	@for agent in claude-assistant-01 data-processor-01 coordinator-main; do \
		echo "  Agent: $$agent"; \
		$(LDAPSEARCH) -b "CN=$${agent}\$$,CN=Agents,CN=System,$(BASE_DN)" \
			-s base "(objectClass=x-agent)" x-agent-Policies 2>/dev/null \
			| grep "x-agent-Policies:" || echo "    (no policies linked)"; \
	done

test-instructions:
	@echo "=== Checking Default Instruction GPO Objects ==="
	@for gpo in base-agent-instructions type-assistant-instructions \
	            type-autonomous-instructions type-coordinator-instructions \
	            type-tool-instructions trust-elevated-instructions; do \
		$(LDAPSEARCH) -b "CN=$$gpo,CN=Agent Instructions,CN=System,$(BASE_DN)" \
			-s base "(objectClass=x-agentInstructionGPO)" cn x-gpo-Priority x-gpo-MergeStrategy 2>/dev/null \
			| grep -q "cn: $$gpo" \
			&& echo "  OK: GPO $$gpo exists" \
			|| echo "  FAIL: GPO $$gpo not found"; \
	done
	@echo ""
	@echo "=== Checking GPO Linkage on Agents ==="
	@for agent in claude-assistant-01 data-processor-01 coordinator-main; do \
		echo "  Agent: $$agent"; \
		$(LDAPSEARCH) -b "CN=$${agent}\$$,CN=Agents,CN=System,$(BASE_DN)" \
			-s base "(objectClass=x-agent)" x-agent-InstructionGPOs 2>/dev/null \
			| grep "x-agent-InstructionGPOs:" || echo "    (no GPOs linked)"; \
	done
	@echo ""
	@echo "=== Checking SYSVOL Instruction Files ==="
	@for gpo in base-agent-instructions type-assistant-instructions \
	            type-autonomous-instructions type-coordinator-instructions \
	            type-tool-instructions trust-elevated-instructions; do \
		docker exec $(CONTAINER) test -s "/var/lib/samba/sysvol/$(DOMAIN)/AgentInstructions/$$gpo/instructions.md" \
			&& echo "  OK: SYSVOL instruction file exists: $$gpo" \
			|| echo "  FAIL: SYSVOL instruction file missing: $$gpo"; \
	done

test-all: test-schema test-policies test-instructions verify-acls integration-test e2e-test
	@echo "=== All test suites completed ==="

# ============================================================================
# AGENT RUNNER (Direct Auth)
# ============================================================================

build-agent:
	$(COMPOSE) --profile agent build agent

run-agent:
ifndef AGENT
	$(error AGENT is required. Usage: make run-agent AGENT=claude-assistant-01)
endif
ifndef ANTHROPIC_API_KEY
	$(error ANTHROPIC_API_KEY must be set. Export it in your shell first.)
endif
	$(COMPOSE) --profile agent run --rm \
		--entrypoint python3 agent \
		/opt/agent-launcher/agent-broker.py $(AGENT)

dry-run:
ifndef AGENT
	$(error AGENT is required. Usage: make dry-run AGENT=claude-assistant-01)
endif
	$(COMPOSE) --profile agent run --rm \
		--entrypoint python3 agent \
		/opt/agent-launcher/agent-broker.py $(AGENT) --dry-run

agent-shell:
	$(COMPOSE) --profile agent run --rm agent

# ============================================================================
# ACL VERIFICATION
# ============================================================================

verify-acls:
	@docker exec $(CONTAINER) bash -c '\
		set -uo pipefail; \
		FAIL=0; \
		check() { \
			if "$$@" >/dev/null 2>&1; then echo "  OK: $$1"; \
			else echo "  FAIL: $$1"; FAIL=$$((FAIL + 1)); fi; \
		}; \
		echo "=== Verifying DC-enforced ACLs ==="; \
		KRB5CCNAME=/tmp/krb5cc_acl_test kinit -kt /var/lib/samba/keytabs/claude-assistant-01.keytab claude-assistant-01\$$@AUTONOMY.LOCAL 2>/dev/null || { echo "FAIL: kinit"; exit 1; }; \
		export KRB5CCNAME=/tmp/krb5cc_acl_test; \
		ldapsearch -N -H ldap://dc1.autonomy.local -Y GSSAPI \
			-b "CN=claude-assistant-01\$$,CN=Agents,CN=System,DC=autonomy,DC=local" -s base "(objectClass=*)" cn 2>/dev/null | grep -q "^dn:" \
			&& echo "  OK: agent can read own entry" \
			|| { echo "  FAIL: agent cannot read own entry"; FAIL=$$((FAIL + 1)); }; \
		for container in "Agent Tools" "Agent Policies" "Agent Instructions"; do \
			ldapsearch -N -H ldap://dc1.autonomy.local -Y GSSAPI \
				-b "CN=$$container,CN=System,DC=autonomy,DC=local" -s one "(objectClass=*)" cn 2>/dev/null | grep -q "^dn:" \
				&& echo "  OK: agent can read $$container" \
				|| { echo "  FAIL: agent cannot read $$container"; FAIL=$$((FAIL + 1)); }; \
		done; \
		echo "=== $$FAIL failures ==="; \
		exit $$FAIL'

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

integration-test:
	@echo "Running integration tests against live DC..."
	docker exec $(CONTAINER) /opt/samba-ad/integration-test.sh

# ============================================================================
# E2E COORDINATION TEST
# ============================================================================

e2e-test:
	@echo "Running end-to-end coordination test..."
	$(COMPOSE) --profile e2e run --rm e2e

submit-goal:
ifndef TITLE
	$(error TITLE is required. Usage: make submit-goal TITLE="Quarterly close automation" [DESCRIPTION="..."])
endif
	@echo "Submitting goal to tasks.coordination..."
	$(COMPOSE) --profile e2e run --rm --entrypoint python3 e2e \
		/opt/e2e-test/submit-goal.py \
		--title "$(TITLE)" \
		--description "$(or $(DESCRIPTION),)" \
		--timeout-seconds "$(or $(TIMEOUT),60)" \
		--follow-seconds "$(or $(FOLLOW),20)"

run-coordinator:
ifndef NATS_COORDINATOR_PASSWORD
	$(error NATS_COORDINATOR_PASSWORD is required. Set it in .env before running.)
endif
	@echo "Starting coordinator runtime (Ctrl+C to stop)..."
	$(COMPOSE) --profile e2e run --rm --entrypoint python3 e2e \
		/opt/e2e-test/run-enterprise-agent.py \
		"$(or $(AGENT),coordinator-main)" \
		--mode coordinator \
		--route-teams "$(or $(ROUTE_TEAMS),$(DEFAULT_ROUTE_TEAMS))" \
		--nats-url "nats://coordinator:$(NATS_COORDINATOR_PASSWORD)@nats.autonomy.local:4222"

run-worker:
ifndef AGENT
	$(error AGENT is required. Usage: make run-worker AGENT=claude-assistant-01)
endif
ifndef NATS_WORKER_PASSWORD
	$(error NATS_WORKER_PASSWORD is required. Set it in .env before running.)
endif
	@echo "Starting worker runtime for $(AGENT) (Ctrl+C to stop)..."
	$(COMPOSE) --profile e2e run --rm --entrypoint python3 e2e \
		/opt/e2e-test/run-enterprise-agent.py \
		"$(AGENT)" \
		--mode worker \
		--nats-url "nats://worker:$(NATS_WORKER_PASSWORD)@nats.autonomy.local:4222"
