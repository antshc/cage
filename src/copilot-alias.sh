#!/usr/bin/env bash
set -euo pipefail

# copiloty — unified wrapper around the copilot CLI
# Usage: copiloty              → interactive session

MODEL="${COPILOT_MODEL:-claude-sonnet-4.6}"
EFFORT="${COPILOT_EFFORT:-}"
OUTPUT_FORMAT="${COPILOT_OUTPUT_FORMAT:-json}" # FORMAT can be `text` or `json` (default, outputs JSONL: one JSON object per line).
LOG_LEVEL="${COPILOT_LOG_LEVEL:-debug}" # choices: none, error, warning, info, debug, all, default
LOG_DIR="${COPILOT_LOG_DIR:-/var/log/copilot}"
MAX_AUTOPILOT_CONTINUES="${COPILOT_MAX_AUTOPILOT_CONTINUES:-20}"

# Directories to add; comma-separated list of paths.
ADD_DIRS="${COPILOT_ADD_DIRS:-$HOME/workspace,$HOME/workspace.worktrees,$HOME/.copilot}"

# Deny-tool list; comma-separated shell(…) entries.
# Set COPILOT_DENY_TOOLS to enable deny-tools; leave unset or empty to pass none.
if [[ -n "${COPILOT_DENY_TOOLS:-}" ]]; then
  IFS=',' read -r -a deny_tools <<< "$COPILOT_DENY_TOOLS"
else
  deny_tools=()
fi

args=(
  --model "$MODEL"
  --output-format "$OUTPUT_FORMAT"
  --log-level "$LOG_LEVEL"
  --log-dir "$LOG_DIR"
  --autopilot
  --allow-all-tools
  --allow-all-urls
  --max-autopilot-continues "$MAX_AUTOPILOT_CONTINUES"
)

for tool in "${deny_tools[@]}"; do
  args+=(--deny-tool="$tool")
done

IFS=',' read -r -a add_dirs <<< "$ADD_DIRS"
for dir in "${add_dirs[@]}"; do
  args+=(--add-dir="$dir")
done

[[ -n "$EFFORT" ]] && args+=(--effort "$EFFORT")

exec copilot "${args[@]}" "$@"
