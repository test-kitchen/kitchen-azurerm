#!/bin/bash
# vm_tags reach the virtual machine itself, not just the resource group.
set -euo pipefail

echo "== vm_tags =="
tags="$(curl -sf -H 'Metadata: true' \
  'http://169.254.169.254/metadata/instance/compute/tags?api-version=2021-02-01&format=text')"
echo "tags: ${tags}"

for expected in "owner:kitchen-azurerm" "purpose:integration"; do
  case "${tags}" in
    *"${expected}"*) ;;
    *) echo "FAIL: tag '${expected}' was not applied"; exit 1 ;;
  esac
done

echo "OK: vm_tags"
