# 41-iptables-passthrough.sh — Allow direct HTTPS to GitHub (bypass mitmproxy)
# Sourced by entrypoint.sh (inherits: PROXY_PORT, UBUNTU_UID)
#
# GitHub domains are excluded from the mitmproxy proxy entirely so that tools
# like `gh` CLI can connect with the real GitHub TLS certificate.
# This script resolves GitHub hosts at container start and inserts iptables rules
# BEFORE the REDIRECT/DROP rules to let port-443 traffic pass directly.

PASSTHROUGH_HOSTS=(
  "github.com"
  "api.github.com"
)

for _host in "${PASSTHROUGH_HOSTS[@]}"; do
  while IFS= read -r _ip; do
    [ -z "$_ip" ] && continue
    # NAT: skip REDIRECT for this IP on port 443 (must be before the REDIRECT rule)
    iptables -t nat -I OUTPUT \
      -m owner --uid-owner "$UBUNTU_UID" -p tcp -d "$_ip" --dport 443 \
      -j RETURN
    # FILTER: allow direct connection (must be before the DROP rule)
    iptables -I OUTPUT \
      -m owner --uid-owner "$UBUNTU_UID" -p tcp -d "$_ip" --dport 443 \
      -j ACCEPT
  done < <(dig +short A "$_host" 2>/dev/null || getent hosts "$_host" | awk '{ print $1 }')
  echo "PASSTHROUGH: $_host :443 bypasses mitmproxy"
done
