#!/usr/bin/env bash
set -euo pipefail

# entrypoint.sh — Root entrypoint that enforces network policy via iptables,
# then drops privileges to 'ubuntu' for the application.
#
# Requires: NET_ADMIN capability, iptables, gosu

PROXY_PORT=8080
UBUNTU_UID=1000

# --- Validate prerequisites ---
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: entrypoint.sh must run as root" >&2
  exit 1
fi

if [ -z "${COPILOT_GITHUB_TOKEN:-}" ]; then
  echo "ERROR: COPILOT_GITHUB_TOKEN is not set" >&2
  exit 1
fi

# --- Register user-supplied CA certificates (runs as root before proxy starts) ---
USER_CERTS_DIR=/etc/sandbox/certs
NODE_CA_BUNDLE=/tmp/node-ca-bundle.pem

# Always start the bundle with the mitmproxy CA (required for proxied HTTPS)
cat /etc/mitmproxy/certs/mitmproxy-ca-cert.pem > "$NODE_CA_BUNDLE"

if [ -d "$USER_CERTS_DIR" ]; then
  for cert in "$USER_CERTS_DIR"/*.crt "$USER_CERTS_DIR"/*.pem; do
    [ -f "$cert" ] || continue
    fname=$(basename "$cert")
    # Install into system store (covers dotnet, git, curl, gh CLI)
    cp "$cert" "/usr/local/share/ca-certificates/${fname%.*}.crt"
    # Append to Node bundle (Node does not use the system store)
    cat "$cert" >> "$NODE_CA_BUNDLE"
    echo "Registered CA certificate: $fname"
  done
  update-ca-certificates --fresh > /dev/null 2>&1
fi

# --- Start mitmproxy as root (exempt from iptables UID 1000 rules) ---
mitmdump \
  --listen-host 127.0.0.1 \
  --listen-port "$PROXY_PORT" \
  --set confdir=/etc/mitmproxy/certs \
  -s /etc/mitmproxy/config/firewall.py \
  --set block_global=false \
  --set ssl_verify_upstream_trusted_ca=/etc/ssl/certs/ca-certificates.crt \
  >>/var/log/mitmproxy/mitmproxy_$(date +%Y%m%d).log 2>&1 &

sleep 1

# --- iptables: force all ubuntu (UID 1000) traffic through mitmproxy ---

# NAT: Redirect outbound HTTP/HTTPS from ubuntu user to local mitmproxy
iptables -t nat -A OUTPUT -m owner --uid-owner "$UBUNTU_UID" -p tcp --dport 80 \
  -j REDIRECT --to-port "$PROXY_PORT"
iptables -t nat -A OUTPUT -m owner --uid-owner "$UBUNTU_UID" -p tcp --dport 443 \
  -j REDIRECT --to-port "$PROXY_PORT"

# FILTER: Allow loopback from ubuntu
iptables -A OUTPUT -o lo -m owner --uid-owner "$UBUNTU_UID" -j ACCEPT

# FILTER: Allow established/related (for redirected connections)
iptables -A OUTPUT -m owner --uid-owner "$UBUNTU_UID" -m state --state ESTABLISHED,RELATED -j ACCEPT

# FILTER: Drop all other outbound from ubuntu (blocks raw TCP, UDP, DNS exfil, etc.)
iptables -A OUTPUT -m owner --uid-owner "$UBUNTU_UID" -j DROP

# --- Ensure writable directories are accessible by ubuntu (covers host-mounted volumes) ---
mkdir -p /var/log/copilot /home/ubuntu/workspace
for dir in /var/log/copilot /home/ubuntu/workspace; do
  chown ubuntu:ubuntu "$dir" 2>/dev/null || chmod a+w "$dir" 2>/dev/null || true
done

# --- Fix Docker socket access (idempotent; no-op when socket is absent) ---
# CAP_CHOWN and group-db writes are unavailable (caps dropped), so we chmod the
# socket to 660 and rely on the entrypoint running as root (which owns the socket)
# to make it group-accessible, then set the group to ubuntu's primary GID.
if [ -S /var/run/docker.sock ]; then
  chgrp ubuntu /var/run/docker.sock 2>/dev/null || chmod 666 /var/run/docker.sock
fi

# --- Drop privileges and exec as ubuntu ---
export HTTP_PROXY=http://127.0.0.1:$PROXY_PORT
export HTTPS_PROXY=http://127.0.0.1:$PROXY_PORT
export ALL_PROXY=http://127.0.0.1:$PROXY_PORT
export NO_PROXY=localhost,127.0.0.1
export NODE_EXTRA_CA_CERTS="$NODE_CA_BUNDLE"
export GH_TOKEN="${GH_TOKEN:-${COPILOT_GITHUB_TOKEN}}"

# --- Optional setup script ---
SETUP_SCRIPT=/etc/sandbox/setup.sh
if [ -f "$SETUP_SCRIPT" ]; then
  gosu ubuntu bash "$SETUP_SCRIPT"
fi

exec gosu ubuntu "$@"