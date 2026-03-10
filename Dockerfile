FROM python:3.11-slim

# ldap-utils: ldapsearch/ldapmodify/ldapadd/ldapdelete (used by LDAPClient)
# krb5-user: Kerberos client utilities (kinit for connectivity checks)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ldap-utils \
    krb5-user \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python dependencies first (Docker layer cache)
COPY pyproject.toml .
RUN pip install --no-cache-dir "fastapi>=0.104.0" "uvicorn[standard]>=0.24.0" "pydantic>=2.0"

# Copy application source
COPY enterprise/ enterprise/

# Install the package itself (no-deps since we already installed deps above)
RUN pip install --no-cache-dir --no-deps .

EXPOSE 8080

CMD ["uvicorn", "enterprise.provisioner.service:app", "--host", "0.0.0.0", "--port", "8080"]
