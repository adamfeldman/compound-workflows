#!/usr/bin/env bash
# check-sentinel.sh — Check .workflows/.work-in-progress.d sentinel directory
#
# Usage: bash check-sentinel.sh [sentinel-dir]
# Default sentinel dir: .workflows/.work-in-progress.d (relative to cwd)
#
# Output (one line to stdout):
#   NOT_FOUND  — directory does not exist, is empty, or contains only non-numeric files
#   ACTIVE     — at least one sentinel is fresh (< 4 hours)
#   STALE:<N>  — all sentinels are stale, N = count of stale files
#
# Exit codes: 0 = always (informational output, never blocks callers)

set -euo pipefail

SENTINEL_DIR="${1:-.workflows/.work-in-progress.d}"
STALENESS_THRESHOLD=14400  # 4 hours in seconds

if [[ ! -d "$SENTINEL_DIR" ]]; then
  echo "NOT_FOUND"
  exit 0
fi

# Collect files in the directory
shopt -s nullglob
files=("$SENTINEL_DIR"/*)
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  echo "NOT_FOUND"
  exit 0
fi

current_time="$(date +%s)"
stale_count=0
has_valid_file=false

for file in "${files[@]}"; do
  [[ -f "$file" ]] || continue

  content="$(cat "$file" 2>/dev/null)" || content=""

  # Skip non-numeric content (cleared/corrupt)
  if ! echo "$content" | grep -qE '^[0-9]+$'; then
    continue
  fi

  has_valid_file=true
  age=$((current_time - content))

  if [[ "$age" -lt "$STALENESS_THRESHOLD" ]]; then
    echo "ACTIVE"
    exit 0
  fi

  stale_count=$((stale_count + 1))
done

if [[ "$has_valid_file" == true ]]; then
  echo "STALE:${stale_count}"
else
  # All files had non-numeric content — treat as NOT_FOUND
  echo "NOT_FOUND"
fi

exit 0
