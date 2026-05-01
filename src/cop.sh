#!/usr/bin/env bash
set -euo pipefail

# cop — wrapper around the copilot CLI with env-var-configurable defaults.
# Usage: cop "your prompt here"
# All positional arguments are joined into the -p prompt string.

MODEL="${COPILOT_MODEL:-claude-sonnet-4.6}"
EFFORT="${COPILOT_EFFORT:-}"
OUTPUT_FORMAT="${COPILOT_OUTPUT_FORMAT:-text}" # FORMAT can be `text` (default) or `json` (outputs JSONL: one JSON object per line).
ALLOW_ALL_TOOLS="${COPILOT_ALLOW_ALL_TOOLS:-true}"
NO_ASK_USER="${COPILOT_NO_ASK_USER:-true}"
LOG_LEVEL="${COPILOT_LOG_LEVEL:-info}" # choices: none, error, warning, info, debug, all, default
LOG_DIR="${COPILOT_LOG_DIR:-/var/log/copilot}"

args=(
  --model "$MODEL"
  --output-format "$OUTPUT_FORMAT"
  --log-level "$LOG_LEVEL"
  --log-dir "$LOG_DIR"
)

[[ -n "$EFFORT" ]] && args+=(--effort "$EFFORT")

[[ "$ALLOW_ALL_TOOLS" == "true" ]] && args+=(--allow-all-tools)
[[ "$NO_ASK_USER"     == "true" ]] && args+=(--no-ask-user)

ALIAS=$(basename "$0")

if [[ "$ALIAS" == "copiloty" ]]; then
  # Interactive session — no prompt, no positional args
  exec copilot "${args[@]}"
else
  # cop — run prompt directly
  if [[ $# -gt 0 ]]; then
    args+=(-p "$*")
  fi
  exec copilot "${args[@]}"
fi
