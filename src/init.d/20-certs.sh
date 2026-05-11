# 20-certs.sh — Register user-supplied CA certificates
# Sourced by entrypoint.sh (inherits: set -euo pipefail)
# Exports: NODE_CA_BUNDLE

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
