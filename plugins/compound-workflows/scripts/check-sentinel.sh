#!/usr/bin/env bash
# check-sentinel.sh — Check .workflows/.work-in-progress sentinel staleness
#
# Usage: bash check-sentinel.sh [sentinel-path]
#
# Default sentinel path: .workflows/.work-in-progress (relative to cwd)
#
# Output (one line to stdout):
#   NOT_FOUND  — sentinel file does not exist
#   CLEARED    — sentinel exists but content is non-numeric (already cleared)
#   ACTIVE     — sentinel is fresh (less than 4 hours old)
#   STALE:<N>  — sentinel is stale, <N> = age in hours
#
# Exit codes:
#   0 = always (informational output, never blocks callers)

set -euo pipefail

SENTINEL="${1:-.workflows/.work-in-progress}"
STALENESS_THRESHOLD=14400  # 4 hours in seconds

if [[ ! -f "$SENTINEL" ]]; then
  echo "NOT_FOUND"
  exit 0
fi

sentinel_content="$(cat "$SENTINEL" 2>/dev/null)" || sentinel_content=""

# Check if content is a valid Unix timestamp (all digits)
if ! echo "$sentinel_content" | grep -qE '^[0-9]+$'; then
  echo "CLEARED"
  exit 0
fi

current_time="$(date +%s)"
sentinel_age=$((current_time - sentinel_content))

if [[ "$sentinel_age" -ge "$STALENESS_THRESHOLD" ]]; then
  age_hours=$((sentinel_age / 3600))
  echo "STALE:${age_hours}"
else
  echo "ACTIVE"
fi

exit 0
