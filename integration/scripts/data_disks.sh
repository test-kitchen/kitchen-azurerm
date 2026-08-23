#!/bin/bash
# Both configured data disks are attached, at the sizes asked for.
set -euo pipefail

echo "== data_disks =="
lsblk -dn -o NAME,SIZE

for size in 10G 20G; do
  lsblk -dn -o SIZE | tr -d ' ' | grep -qx "${size}" \
    || { echo "FAIL: no ${size} data disk is attached"; exit 1; }
done

echo "OK: data_disks"
