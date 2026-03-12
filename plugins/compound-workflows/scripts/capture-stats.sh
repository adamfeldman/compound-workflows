#!/usr/bin/env bash
# capture-stats.sh — Deterministic atomic append of per-dispatch stats entries
#
# Usage:
#   bash capture-stats.sh <stats-file> <command> <agent> <step> <model> <stem> <bead> <run_id> <usage_line>
#   bash capture-stats.sh --timeout <stats-file> <command> <agent> <step> <model> <stem> <bead> <run_id>
#
# Appends a YAML document to <stats-file> via >> (atomic for single writes).
# Exits 0 always — stats capture must never block command execution.

set -euo pipefail

# ── Timeout variant ──────────────────────────────────────────────────────────
if [[ "${1:-}" == "--timeout" ]]; then
  shift
  STATS_FILE="${1:?missing stats-file}"
  COMMAND="${2:?missing command}"
  AGENT="${3:?missing agent}"
  STEP="${4:?missing step}"
  MODEL="${5:?missing model}"
  STEM="${6:?missing stem}"
  BEAD="${7:?missing bead}"
  RUN_ID="${8:?missing run_id}"
  TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  cat >> "$STATS_FILE" <<EOF
---
command: $COMMAND
bead: ${BEAD:-null}
stem: $STEM
agent: $AGENT
step: "$STEP"
model: $MODEL
run_id: $RUN_ID
tokens: null
tools: null
duration_ms: null
timestamp: $TIMESTAMP
status: timeout
complexity: null
output_type: null
EOF
  exit 0
fi

# ── Standard variant ─────────────────────────────────────────────────────────
STATS_FILE="${1:?missing stats-file}"
COMMAND="${2:?missing command}"
AGENT="${3:?missing agent}"
STEP="${4:?missing step}"
MODEL="${5:?missing model}"
STEM="${6:?missing stem}"
BEAD="${7:?missing bead}"
RUN_ID="${8:?missing run_id}"
USAGE_LINE="${9:-}"

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
TOKENS="null"
TOOLS="null"
DURATION="null"
STATUS="success"

# ── Parse <usage> line ───────────────────────────────────────────────────────
if [[ -z "$USAGE_LINE" || "$USAGE_LINE" == "null" ]]; then
  STATUS="failure"
elif [[ "$USAGE_LINE" != *"<usage>"* ]]; then
  # Non-empty but no <usage> tag — e.g., orchestrator placeholder like "no-usage-data"
  STATUS="failure"
  echo "Stats capture: no <usage> data in response (normal for some dispatch types)" >&2
else
  # Health check: verify <usage> wrapper and at least one known field present
  # Accepts all known formats: space-delimited, comma-separated, newline-separated, XML tags
  if ! echo "$USAGE_LINE" | grep -qE '<usage>.*total_tokens' ; then
    echo "Stats capture: <usage> format may have changed — consider filing a bug" >&2
    echo "  Received: $USAGE_LINE" >&2
  fi

  # Format-agnostic extraction: [>:] matches both "field: val" and "<field>val"
  EXTRACTED_TOKENS="$(echo "$USAGE_LINE" | sed -n 's/.*total_tokens[>:] *\([0-9][0-9]*\).*/\1/p' | head -1)"
  EXTRACTED_TOOLS="$(echo "$USAGE_LINE" | sed -n 's/.*tool_uses[>:] *\([0-9][0-9]*\).*/\1/p' | head -1)"
  EXTRACTED_DURATION="$(echo "$USAGE_LINE" | sed -n 's/.*duration_ms[>:] *\([0-9][0-9]*\).*/\1/p' | head -1)"

  if [[ -n "$EXTRACTED_TOKENS" ]]; then
    TOKENS="$EXTRACTED_TOKENS"
  fi
  if [[ -n "$EXTRACTED_TOOLS" ]]; then
    TOOLS="$EXTRACTED_TOOLS"
  fi
  if [[ -n "$EXTRACTED_DURATION" ]]; then
    DURATION="$EXTRACTED_DURATION"
  fi

  # If none of the fields extracted, mark as failure
  if [[ "$TOKENS" == "null" && "$TOOLS" == "null" && "$DURATION" == "null" ]]; then
    STATUS="failure"
  fi
fi

# ── Write YAML entry ────────────────────────────────────────────────────────
cat >> "$STATS_FILE" <<EOF
---
command: $COMMAND
bead: ${BEAD:-null}
stem: $STEM
agent: $AGENT
step: "$STEP"
model: $MODEL
run_id: $RUN_ID
tokens: $TOKENS
tools: $TOOLS
duration_ms: $DURATION
timestamp: $TIMESTAMP
status: $STATUS
complexity: null
output_type: null
EOF

exit 0
