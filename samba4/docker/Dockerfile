FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install Samba4 AD DC and dependencies
RUN apt-get update && apt-get install -y \
    samba \
    samba-dsdb-modules \
    samba-vfs-modules \
    krb5-user \
    krb5-config \
    winbind \
    ldb-tools \
    ldap-utils \
    libsasl2-modules-gssapi-mit \
    python3 \
    python3-ldap \
    python3-pip \
    dnsutils \
    procps \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/samba/smb.conf

# Create working directories
RUN mkdir -p /opt/samba-ad/schema \
             /opt/samba-ad/scripts \
             /opt/samba-ad/policies \
             /opt/samba-ad/instructions

# Copy schema LDIF files
COPY schema/ /opt/samba-ad/schema/

# Copy management scripts
COPY scripts/ /opt/samba-ad/scripts/

# Copy policy definitions (JSON files for SYSVOL)
COPY policies/ /opt/samba-ad/policies/

# Copy instruction GPO content (markdown files for SYSVOL)
COPY instructions/ /opt/samba-ad/instructions/

# Copy agent-manager to PATH
RUN chmod +x /opt/samba-ad/scripts/agent-manager.py && \
    ln -s /opt/samba-ad/scripts/agent-manager.py /usr/local/bin/agent-manager

# Copy Docker-specific scripts
COPY docker/entrypoint.sh /opt/samba-ad/entrypoint.sh
COPY docker/bootstrap-schema.sh /opt/samba-ad/bootstrap-schema.sh
COPY docker/bootstrap-data.sh /opt/samba-ad/bootstrap-data.sh
COPY docker/bootstrap-acls.sh /opt/samba-ad/bootstrap-acls.sh
COPY docker/healthcheck.sh /opt/samba-ad/healthcheck.sh
COPY docker/integration-test.sh /opt/samba-ad/integration-test.sh

RUN chmod +x /opt/samba-ad/entrypoint.sh \
             /opt/samba-ad/bootstrap-schema.sh \
             /opt/samba-ad/bootstrap-data.sh \
             /opt/samba-ad/bootstrap-acls.sh \
             /opt/samba-ad/healthcheck.sh \
             /opt/samba-ad/integration-test.sh \
             /opt/samba-ad/schema/install-schema.sh

EXPOSE 389 636 88 445 3268 53/udp 53/tcp

ENTRYPOINT ["/opt/samba-ad/entrypoint.sh"]
