#!/bin/bash
# os_disk_size_gb resized the OS disk rather than leaving the image default.
set -euo pipefail

echo "== os_disk_size_gb =="
lsblk -dn -o NAME,SIZE

root_device="$(lsblk -no PKNAME "$(findmnt -no SOURCE /)")"
size="$(lsblk -dn -o SIZE "/dev/${root_device}" | tr -d ' ')"
echo "root disk ${root_device}: ${size}"

case "${size}" in
  6[0-9]G) echo "OK: os_disk_size_gb" ;;
  *) echo "FAIL: expected an OS disk of about 64G, got ${size}"; exit 1 ;;
esac
