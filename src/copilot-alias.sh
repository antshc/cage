#!/usr/bin/env bash
set -euo pipefail

# copiloty — unified wrapper around the copilot CLI
# Usage: copiloty              → interactive session

MODEL="${COPILOT_MODEL:-claude-sonnet-4.6}"
EFFORT="${COPILOT_EFFORT:-}"
OUTPUT_FORMAT="${COPILOT_OUTPUT_FORMAT:-json}" # FORMAT can be `text` or `json` (default, outputs JSONL: one JSON object per line).
LOG_LEVEL="${COPILOT_LOG_LEVEL:-info}" # choices: none, error, warning, info, debug, all, default
LOG_DIR="${COPILOT_LOG_DIR:-/var/log/copilot}"

args=(
  --model "$MODEL"
  --output-format "$OUTPUT_FORMAT"
  --log-level "$LOG_LEVEL"
  --log-dir "$LOG_DIR"
  --autopilot
  --yolo
)

[[ -n "$EFFORT" ]] && args+=(--effort "$EFFORT")

exec copilot "${args[@]}" "$@"
