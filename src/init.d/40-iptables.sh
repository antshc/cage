# 40-iptables.sh — Force all ubuntu (UBUNTU_UID) traffic through mitmproxy
# Sourced by entrypoint.sh (inherits: PROXY_PORT, UBUNTU_UID)

# --- NAT: Redirect outbound HTTP/HTTPS from ubuntu user to local mitmproxy ---
iptables -t nat -A OUTPUT -m owner --uid-owner "$UBUNTU_UID" -p tcp --dport 80 \
  -j REDIRECT --to-port "$PROXY_PORT"
iptables -t nat -A OUTPUT -m owner --uid-owner "$UBUNTU_UID" -p tcp --dport 443 \
  -j REDIRECT --to-port "$PROXY_PORT"

# FILTER: Allow loopback from ubuntu
iptables -A OUTPUT -o lo -m owner --uid-owner "$UBUNTU_UID" -j ACCEPT

# FILTER: Allow established/related (for redirected connections)
iptables -A OUTPUT -m owner --uid-owner "$UBUNTU_UID" -m state --state ESTABLISHED,RELATED -j ACCEPT

# FILTER: Allow ICMP (ping) from ubuntu (mitmproxy cannot proxy ICMP)
iptables -A OUTPUT -m owner --uid-owner "$UBUNTU_UID" -p icmp -j ACCEPT

# FILTER: Drop all other outbound from ubuntu (blocks raw TCP, UDP, DNS exfil, etc.)
iptables -A OUTPUT -m owner --uid-owner "$UBUNTU_UID" -j DROP

# --- DNAT: redirect 127.0.0.1:PORT(S) to host.docker.internal:PORT(S) ---
# Configure via HOST_DOCKER_DNAT_PORTS: comma-separated ports and/or dash ranges.
# Examples: "8000"  |  "8000,5432,6379"  |  "9200-9300"  |  "8000,9200-9300"
# Requires: --sysctl net.ipv4.conf.all.route_localnet=1 (set in docker-compose.yml)
if [ -n "${HOST_DOCKER_DNAT_PORTS:-}" ]; then
  HOST_DOCKER_IP=$(getent hosts host.docker.internal | awk '{ print $1 }')
  if [ -n "$HOST_DOCKER_IP" ]; then
    IFS=',' read -ra _DNAT_ENTRIES <<< "$HOST_DOCKER_DNAT_PORTS"
    for _entry in "${_DNAT_ENTRIES[@]}"; do
      _entry="${_entry// /}"   # trim spaces
      [ -z "$_entry" ] && continue
      if [[ "$_entry" == *-* ]]; then
        # Range: "8000-8010" → iptables dport "8000:8010", dest "8000-8010"
        _port_start="${_entry%-*}"
        _port_end="${_entry#*-}"
        _iptables_dport="${_port_start}:${_port_end}"
        _dest_port="${_port_start}-${_port_end}"
      else
        _iptables_dport="$_entry"
        _dest_port="$_entry"
      fi
      iptables -t nat -A OUTPUT \
        -p tcp -d 127.0.0.1 --dport "$_iptables_dport" \
        -j DNAT --to-destination "${HOST_DOCKER_IP}:${_dest_port}"
      iptables -t nat -A POSTROUTING \
        -p tcp -d "$HOST_DOCKER_IP" --dport "$_iptables_dport" \
        -j MASQUERADE
      # Allow UID to reach the DNAT destination after rewrite
      # (insert before the final DROP rule so re-addressed packets are not dropped)
      iptables -I OUTPUT \
        -m owner --uid-owner "$UBUNTU_UID" \
        -p tcp -d "$HOST_DOCKER_IP" --dport "$_iptables_dport" \
        -j ACCEPT
      echo "DNAT: 127.0.0.1:${_entry} -> ${HOST_DOCKER_IP}:${_entry}"
    done
  else
    echo "WARNING: host.docker.internal not resolved; HOST_DOCKER_DNAT_PORTS skipped" >&2
  fi
fi
