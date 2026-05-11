# 30-proxy.sh — Start mitmproxy as root (exempt from iptables UID rules)
# Sourced by entrypoint.sh (inherits: PROXY_PORT)

mitmdump \
  --listen-host 127.0.0.1 \
  --listen-port "$PROXY_PORT" \
  --set confdir=/etc/mitmproxy/certs \
  -s /etc/mitmproxy/config/firewall.py \
  --set block_global=false \
  --set block_private=false \
  --set ssl_verify_upstream_trusted_ca=/etc/ssl/certs/ca-certificates.crt \
  >>/var/log/mitmproxy/mitmproxy_$(date +%Y%m%d).log 2>&1 &

sleep 1
