#!/usr/bin/env bash
# validate-stats.sh — Validate stats entry count after a dispatch phase
#
# Usage:
#   bash validate-stats.sh <stats-file> <expected-count>   # validate mode
#   bash validate-stats.sh <stats-file>                     # report-only mode
#
# Exits 0 always — validation is diagnostic, never blocks execution.

STATS_FILE="${1:?missing stats-file}"
EXPECTED="${2:-}"

if [[ ! -f "$STATS_FILE" ]]; then
  if [[ -n "$EXPECTED" ]]; then
    echo "Stats validation: file not found ($STATS_FILE) — expected $EXPECTED entries" >&2
  else
    echo "Stats validation: file not found ($STATS_FILE)" >&2
  fi
  exit 0
fi

ACTUAL=$(grep -c '^---$' "$STATS_FILE" 2>/dev/null)
ACTUAL=${ACTUAL:-0}

if [[ "$EXPECTED" == "report" ]]; then
  # Explicit report-only mode
  echo "Stats validation: $ACTUAL entries in $STATS_FILE"
elif [[ -z "$EXPECTED" ]]; then
  # Missing expected count — warn (model may have failed to substitute placeholder)
  echo "Stats validation: WARNING — expected count not provided (model may have failed to substitute)" >&2
  echo "Stats validation: $ACTUAL entries in $STATS_FILE (unvalidated)" >&2
elif [ "$ACTUAL" -eq "$EXPECTED" ]; then
  echo "Stats validation: $ACTUAL entries (expected $EXPECTED)"
else
  echo "Stats validation: $ACTUAL entries (expected $EXPECTED) — MISMATCH" >&2
fi

exit 0
