#!/usr/bin/env bash
# setup.sh — Optional startup script example
#
# Mount this file into the container to run custom setup steps at startup:
#
#   docker-compose.yml volumes:
#     - ./setup.sh:/etc/sandbox/setup.sh:ro
#
# This script runs as the 'ubuntu' user after mitmproxy and iptables are
# configured (network access through the proxy is available). If it exits
# non-zero, the container aborts.
#
# Available environment variables:
#   COPILOT_GITHUB_TOKEN  — GitHub token for Copilot
#   GH_TOKEN              — GitHub token for gh CLI (same value)
#   HTTP_PROXY            — http://127.0.0.1:8080
#   HTTPS_PROXY           — http://127.0.0.1:8080
#   NODE_EXTRA_CA_CERTS   — path to mitmproxy CA cert (trusted by Node.js)
#
set -euo pipefail

# Example: install a Copilot plugin from a GitHub release
# gh extension install owner/gh-my-skill

# Example: Add copilot plugin marketplace and install a plugin from there
# copilot plugin marketplace add github/awesome-copilot

# example: install a Copilot plugin from the marketplace with a specific version
# copilot plugin install dotnet@awesome-copilot

# Example: Install skill
# gh skill install github/awesome-copilot git-commit

# Example: install an npm package globally
# npm install -g my-tool

# Example: configure git
# git config --global user.email "agent@example.com"
# git config --global user.name "Copilot Agent"

echo "setup.sh: custom setup complete"
