# 10-validate.sh — Verify entrypoint prerequisites
# Sourced by entrypoint.sh (inherits: set -euo pipefail)

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: entrypoint.sh must run as root" >&2
  exit 1
fi

if [ -z "${COPILOT_GITHUB_TOKEN:-}" ] && [ ! -f "/home/ubuntu/.config/gh/hosts.yml" ]; then
  echo "ERROR: No Copilot auth found. Set COPILOT_GITHUB_TOKEN or mount ~/.config/gh" >&2
  exit 1
fi
