#!/usr/bin/env bash
# capture-stats.sh — Deterministic atomic append of per-dispatch stats entries
#
# Usage:
#   bash capture-stats.sh <stats-file> <command> <agent> <step> <model> <stem> <bead> <run_id> <usage-data>
#   bash capture-stats.sh --timeout <stats-file> <command> <agent> <step> <model> <stem> <bead> <run_id>
#
# <usage-data>: Named-field string "total_tokens: N, tool_uses: N, duration_ms: N" or "null"
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
USAGE_DATA="${9:-null}"

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
TOKENS="null"
TOOLS="null"
DURATION="null"
STATUS="success"

# ── Parse named-field string or "null" ─────────────────────────────────────
if [[ "$USAGE_DATA" == "null" ]]; then
  STATUS="failure"
else
  # Format-agnostic extraction: [>:] matches "field: val" and "<field>val"
  # The > branch is defense-in-depth — models always produce colon format under
  # the new convention, but > guards against model formatting errors.
  EXTRACTED_TOKENS="$(echo "$USAGE_DATA" | sed -n 's/.*total_tokens[>:] *\([0-9][0-9]*\).*/\1/p' | head -1)"
  EXTRACTED_TOOLS="$(echo "$USAGE_DATA" | sed -n 's/.*tool_uses[>:] *\([0-9][0-9]*\).*/\1/p' | head -1)"
  EXTRACTED_DURATION="$(echo "$USAGE_DATA" | sed -n 's/.*duration_ms[>:] *\([0-9][0-9]*\).*/\1/p' | head -1)"

  if [[ -n "$EXTRACTED_TOKENS" ]]; then TOKENS="$EXTRACTED_TOKENS"; fi
  if [[ -n "$EXTRACTED_TOOLS" ]]; then TOOLS="$EXTRACTED_TOOLS"; fi
  if [[ -n "$EXTRACTED_DURATION" ]]; then DURATION="$EXTRACTED_DURATION"; fi

  # Require ALL three fields for success — partial extraction masks format drift
  if [[ "$TOKENS" == "null" || "$TOOLS" == "null" || "$DURATION" == "null" ]]; then
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
