#!/bin/bash
# Health check for Samba4 AD DC
# Returns 0 if LDAPS is responding, 1 otherwise

export LDAPTLS_REQCERT=allow
ldapsearch -H ldaps://localhost -x -b "" -s base namingContexts >/dev/null 2>&1
