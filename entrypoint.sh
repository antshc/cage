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

if [ ! -f /etc/mitmproxy/config/firewall.py ]; then
  echo "ERROR: /etc/mitmproxy/config/firewall.py not found" >&2
  exit 1
fi

if [ -z "${COPILOT_GITHUB_TOKEN:-}" ]; then
  echo "ERROR: COPILOT_GITHUB_TOKEN is not set" >&2
  exit 1
fi

# --- Start mitmproxy as root (exempt from iptables UID 1000 rules) ---
mitmdump \
  --listen-host 127.0.0.1 \
  --listen-port "$PROXY_PORT" \
  --set confdir=/etc/mitmproxy/certs \
  -s /etc/mitmproxy/config/firewall.py \
  --set block_global=false \
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

# --- Drop privileges and exec as ubuntu ---
export HTTP_PROXY=http://127.0.0.1:$PROXY_PORT
export HTTPS_PROXY=http://127.0.0.1:$PROXY_PORT
export ALL_PROXY=http://127.0.0.1:$PROXY_PORT
export NO_PROXY=localhost,127.0.0.1
export NODE_EXTRA_CA_CERTS="/etc/mitmproxy/certs/mitmproxy-ca-cert.pem"

exec gosu ubuntu "$@"