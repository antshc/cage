# 55-copilot-config.sh — Write $COPILOT_HOME/config.json with trustedFolders at runtime.
# Sourced by entrypoint.sh (runs as root, before gosu drop to ubuntu).
#
# Reads COPILOT_ADD_DIRS (same var used by copilot-alias.sh for --add-dir flags).
# COPILOT_ADD_DIRS extends COPILOT_DEFAULT_ADD_DIRS — never replaces them.
# COPILOT_HOME defaults to ~/.copilot in the CLI; the init.d script runs as root
# so $HOME=/root — fall back to the ubuntu user's path if unset.
_COPILOT_HOME="${COPILOT_HOME:-/home/ubuntu/.copilot}"

_DEFAULT_DIRS="${COPILOT_DEFAULT_ADD_DIRS}"

# Build the combined comma-separated list
if [[ -n "${COPILOT_ADD_DIRS:-}" ]]; then
  _ALL_DIRS="${_DEFAULT_DIRS},${COPILOT_ADD_DIRS}"
else
  _ALL_DIRS="${_DEFAULT_DIRS}"
fi

mkdir -p "$_COPILOT_HOME"

# Build JSON using jq: split on commas, trim whitespace, write config
tr ',' '\n' <<< "$_ALL_DIRS" \
  | jq -Rs '[split("\n")[] | gsub("^\\s+|\\s+$";"") | select(length > 0)] | {trustedFolders: .}' \
  > "$_COPILOT_HOME/config.json"

chown ubuntu:ubuntu "$_COPILOT_HOME/config.json"
chmod 600 "$_COPILOT_HOME/config.json"

unset _COPILOT_HOME _DEFAULT_DIRS _ALL_DIRS
