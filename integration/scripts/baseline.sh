#!/bin/bash
# The instance exists, is reachable over the transport, and runs as the
# configured admin user.
set -euo pipefail

echo "== baseline =="
uname -a

# The shell provisioner runs under sudo, so check who logged in rather than
# who is executing.
login_user="${SUDO_USER:-$(whoami)}"
echo "login user: ${login_user}"
[ "${login_user}" = "azure" ] || { echo "FAIL: expected to log in as 'azure', got '${login_user}'"; exit 1; }
[ -d /home/azure ] || { echo "FAIL: /home/azure was not created"; exit 1; }

# A name Azure accepted is at most 15 characters and ends with a word
# character; the network interface is named after it.
host="$(hostname)"
echo "hostname: ${host}"
[ "${#host}" -le 15 ] || { echo "FAIL: hostname '${host}' is longer than 15 characters"; exit 1; }
[[ "${host}" =~ [[:alnum:]]$ ]] || { echo "FAIL: hostname '${host}' does not end with a word character"; exit 1; }

echo "OK: baseline"
