#!/usr/bin/env bash
set -euo pipefail

if [ ! -f /etc/mitmproxy/config/firewall.py ]; then
  echo "ERROR: /etc/mitmproxy/config/firewall.py not found" >&2
  exit 1
fi

if [ -z "${COPILOT_GITHUB_TOKEN:-}" ]; then
  echo "ERROR: COPILOT_GITHUB_TOKEN is not set" >&2
  exit 1
fi

mitmdump \
  --listen-host 127.0.0.1 \
  --listen-port 8080 \
  -s /etc/mitmproxy/config/firewall.py \
  --set block_global=false \
  >>/var/log/mitmproxy/mitmproxy_$(date +%Y%m%d).log 2>&1 &

sleep 1

export HTTP_PROXY=http://127.0.0.1:8080
export HTTPS_PROXY=http://127.0.0.1:8080
export ALL_PROXY=http://127.0.0.1:8080
export NO_PROXY=localhost,127.0.0.1
export NODE_EXTRA_CA_CERTS="$HOME/.mitmproxy/mitmproxy-ca-cert.pem"

exec "$@"