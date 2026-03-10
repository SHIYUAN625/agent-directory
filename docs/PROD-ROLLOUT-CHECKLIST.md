# Production Rollout Checklist

This project is not yet a production "autonomous enterprise." It is a strong enterprise autonomy platform prototype with AD-backed identity, policy, provisioning, and coordinator/worker orchestration.

Use this checklist to move from prototype to production.

## Current Baseline

- `enterprise/tests`: passing locally.
- `samba4/docker` integration tests: passing.
- `samba4/docker` e2e coordination test: passing with authenticated NATS.
- Remaining major gaps: secrets management, PKI/TLS trust posture, HA state backend, operational SLO/runbook maturity, governance controls.

## Phase 1: Security and Secret Hygiene (Blocker for Production)

### 1. Secrets must come from files/secret manager, not plain env

Code changes:

- Update secret loading in [enterprise/provisioner/config.py](/Users/moo/projects/agent-directory/enterprise/provisioner/config.py):
  - Add helper that resolves `FOO_FILE` first, then `FOO`.
  - Apply to `PROVISIONER_API_KEY`, `LDAP_BIND_PW`, `NATS_PASSWORD`, `NATS_*_PASSWORD`.
- Update [samba4/docker/docker-compose.yml](/Users/moo/projects/agent-directory/samba4/docker/docker-compose.yml):
  - Keep dev env support.
  - Add documented `_FILE` variant support for pre-prod/prod deployments.
- Add deployment docs in [docs/DEPLOYMENT.md](/Users/moo/projects/agent-directory/docs/DEPLOYMENT.md):
  - Secret source contract for each required secret.

Acceptance criteria:

- No required runtime secret appears in `docker inspect`, `ps`, or startup logs.
- Boot fails fast with explicit error when a required secret is missing.
- Rotation test: changing secret source and restarting service works without code change.

### 2. Enforce PKI-backed TLS trust

Code/config changes:

- Keep `LDAPTLS_REQCERT=demand` as production default.
- In [enterprise/provisioner/ldap_client.py](/Users/moo/projects/agent-directory/enterprise/provisioner/ldap_client.py):
  - Validate `LDAPTLS_CACERT` path exists when demand mode is used.
  - Fail startup if CA is missing or unreadable.
- In [samba4/docker/bootstrap-data.sh](/Users/moo/projects/agent-directory/samba4/docker/bootstrap-data.sh) and [samba4/docker/entrypoint.sh](/Users/moo/projects/agent-directory/samba4/docker/entrypoint.sh):
  - Keep override support, but document `allow` as dev-only.

Acceptance criteria:

- Connection with invalid/untrusted cert fails.
- Connection with signed cert and CA bundle succeeds.
- CI pre-prod job verifies `LDAPTLS_REQCERT=demand` and CA file presence.

### 3. Key and credential rotation policy

Code changes:

- Update API-key auth in [enterprise/provisioner/service.py](/Users/moo/projects/agent-directory/enterprise/provisioner/service.py):
  - Support active + next key window (ex: `PROVISIONER_API_KEYS=key1,key2`).
- Add rotation runbook to [docs/ADMIN-GUIDE.md](/Users/moo/projects/agent-directory/docs/ADMIN-GUIDE.md):
  - NATS role password rotation order.
  - Provisioner API key rotation order.

Acceptance criteria:

- During rotation window, both old and new key are accepted.
- After cutover, old key is rejected.
- No service interruption during rotation drill.

### 4. Log redaction and zero secret leakage

Code changes:

- Add logging redaction filter in a shared module (new file suggested: `enterprise/common/logging_redaction.py`).
- Wire filter into provisioning/coordinator service loggers.

Acceptance criteria:

- Automated test scans logs and finds no:
  - passwords
  - OTPs
  - NATS creds
  - API keys
- 500 responses never include raw exception strings with internals.

## Phase 2: Control-Plane Reliability

### 1. Durable HA stores for leases/checkpoints/credential refs

Code changes:

- Keep current file/sqlite stores for dev.
- Add Postgres-backed implementations for:
  - identity leases
  - checkpoint state
  - one-time credential references
- Switch via config-driven backend selection.

Acceptance criteria:

- Kill/restart provisioner and coordinator; state recovers correctly.
- No duplicate identity assignment under concurrent provision requests.
- Recovery test proves no credential replay after failover.

### 2. VM lifecycle reconciliation

Code changes:

- Add reconciliation loop in coordinator/workforce:
  - detect stale `STARTING` / `OFFLINE` agents
  - release stale identity leases
  - re-request agents when needed

Acceptance criteria:

- Simulated VM crash is healed automatically.
- Orphaned leases are cleaned within configured SLA.

## Phase 3: Governance and Operational Readiness

### 1. Human approval gates for high-risk actions

Code changes:

- Add policy-enforced approval requirement before dangerous tool classes (spawn/delete/network-wide ops).
- Persist approval decision in audit events.

Acceptance criteria:

- Restricted action without approval is denied and auditable.
- Approved action executes and audit trace is complete.

### 2. SLOs, alerts, and runbooks

Changes:

- Define SLOs (availability, task latency, escalation latency, provisioning success).
- Add alert thresholds and paging policies.
- Add incident playbooks in docs.

Acceptance criteria:

- Alert fire drill and on-call handoff tested.
- MTTR rehearsal completed and documented.

## Production Gate (Go/No-Go)

Do not call this production-ready until all are true:

- Phase 1 complete and verified.
- Phase 2 complete with failover drills.
- Phase 3 complete with on-call signoff.
- Placeholder OID/PEN replaced in schema (`scripts/replace-oid.sh <PEN>`).
- Security review and threat model signoff completed.

## Immediate Next Execution (Recommended Order)

1. Implement `_FILE` secret loading in provisioner config and update deployment docs.
2. Add CA-path startup validation and enforce demand mode in pre-prod.
3. Add dual-key API auth rotation and test it.
4. Add log redaction filter and leak-detection test.
5. Run full pre-prod suite: `pytest enterprise/tests`, Samba integration, and e2e with real secret source.
