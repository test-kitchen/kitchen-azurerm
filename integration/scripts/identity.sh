#!/bin/bash
# A system-assigned identity is attached and can actually mint ARM tokens.
set -euo pipefail

echo "== system_assigned_identity =="
token="$(curl -sf -H 'Metadata: true' \
  'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/')"

case "${token}" in
  *access_token*) ;;
  *) echo "FAIL: the instance metadata service issued no token: ${token}"; exit 1 ;;
esac

echo "OK: system_assigned_identity"
