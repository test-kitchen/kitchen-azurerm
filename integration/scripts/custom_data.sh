#!/bin/bash
# custom_data reached cloud-init and ran. Boot-time work races the transport
# becoming available, so wait rather than sampling once.
set -euo pipefail

echo "== custom_data =="
for _ in $(seq 1 30); do
  [ -f /etc/kitchen-custom-data ] && break
  sleep 5
done

if [ ! -f /etc/kitchen-custom-data ]; then
  echo "FAIL: custom_data did not run. Last lines of cloud-init output:"
  tail -30 /var/log/cloud-init-output.log || true
  exit 1
fi

cat /etc/kitchen-custom-data
echo "OK: custom_data"
