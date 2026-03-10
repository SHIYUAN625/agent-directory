#!/usr/bin/env bash
# Domain-join: authenticate to AD and create a local keytab.
# Works from anywhere with network access to DC (ports 88, 389).
set -euo pipefail

PRINCIPAL=""  PASSWORD=""  DC_IP=""  DC_HOST=""  REALM=""
KEYTAB_DIR="/etc/agent"  ENC_TYPE="aes256-cts-hmac-sha1-96"

while [[ $# -gt 0 ]]; do
  case $1 in
    --principal)  PRINCIPAL="$2"; shift 2;;
    --password)   PASSWORD="$2"; shift 2;;
    --dc-ip)      DC_IP="$2"; shift 2;;
    --dc-host)    DC_HOST="$2"; shift 2;;
    --realm)      REALM="$2"; shift 2;;
    --keytab-dir) KEYTAB_DIR="$2"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

if [[ -z "$PRINCIPAL" || -z "$PASSWORD" || -z "$DC_HOST" || -z "$REALM" ]]; then
  echo "Usage: domain-join.sh --principal USER\$@REALM --password PASS --dc-host HOST --realm REALM [--dc-ip IP] [--keytab-dir DIR]" >&2
  exit 1
fi

AGENT_NAME="${PRINCIPAL%%\$@*}"
KEYTAB_PATH="${KEYTAB_DIR}/${AGENT_NAME}.keytab"

# Step 1: Add DC to /etc/hosts (for .local resolution without mDNS)
if [[ -n "$DC_IP" ]]; then
  grep -q "$DC_HOST" /etc/hosts 2>/dev/null || echo "$DC_IP  $DC_HOST" >> /etc/hosts
fi

# Step 2: Write /etc/krb5.conf
cat > /etc/krb5.conf <<EOF
[libdefaults]
  default_realm = ${REALM}
  dns_lookup_realm = false
  dns_lookup_kdc = false

[realms]
  ${REALM} = {
    kdc = ${DC_HOST}
    admin_server = ${DC_HOST}
  }

[domain_realm]
  .${REALM,,} = ${REALM}
  ${REALM,,} = ${REALM}
EOF

# Step 3: kinit with password (via stdin, never CLI arg)
echo "$PASSWORD" | kinit "$PRINCIPAL"

# Step 4: Create keytab from password via ktutil
mkdir -p "$KEYTAB_DIR" && chmod 700 "$KEYTAB_DIR"
printf "addent -password -p %s -k 1 -e %s\n%s\nwkt %s\nq\n" \
  "$PRINCIPAL" "$ENC_TYPE" "$PASSWORD" "$KEYTAB_PATH" | ktutil
chmod 600 "$KEYTAB_PATH"

# Step 5: Wipe password from memory
PASSWORD=""; unset PASSWORD

# Step 6: Verify keytab works
kinit -kt "$KEYTAB_PATH" "$PRINCIPAL"
echo "Domain join complete: $(klist -kt "$KEYTAB_PATH" | tail -1)"
