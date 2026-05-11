#!/usr/bin/env bash
set -euo pipefail

# entrypoint.sh — Root entrypoint orchestrator.
# Sources modular init scripts from /etc/mitmproxy/init.d/ in sorted order,
# then drops privileges to 'ubuntu' for the application.
#
# Requires: NET_ADMIN capability, iptables, gosu
#
# Shared variables (available to all init.d/ scripts):
#   PROXY_PORT  — mitmproxy listen port
#   UBUNTU_UID  — UID for the unprivileged user (may be remapped by 50-permissions.sh)
#   NODE_CA_BUNDLE — path to combined CA bundle for Node.js (set by 20-certs.sh)

PROXY_PORT=18080
UBUNTU_UID="${PUID:-1000}"

# --- Source init.d/ modules in sorted order ---
INIT_DIR=/etc/mitmproxy/init.d
for script in "$INIT_DIR"/*.sh; do
  [ -f "$script" ] || continue
  # shellcheck source=/dev/null
  source "$script"
done

# --- Export proxy environment for the unprivileged user ---
export HTTP_PROXY=http://127.0.0.1:$PROXY_PORT
export HTTPS_PROXY=http://127.0.0.1:$PROXY_PORT
export ALL_PROXY=http://127.0.0.1:$PROXY_PORT
export NO_PROXY=localhost,127.0.0.1
export NODE_EXTRA_CA_CERTS="${NODE_CA_BUNDLE:-/tmp/node-ca-bundle.pem}"

# --- Optional setup script (runs as ubuntu, after proxy is ready) ---
SETUP_SCRIPT=/etc/sandbox/setup.sh
if [ -f "$SETUP_SCRIPT" ]; then
  gosu ubuntu bash "$SETUP_SCRIPT"
fi

exec gosu ubuntu "$@"