#!/usr/bin/env bash
# migrate-stats-keys.sh — Append stats_capture + stats_classify keys to local config
#
# Usage:
#   bash migrate-stats-keys.sh
#
# Reads/writes compound-workflows.local.md relative to CWD.
# Exits 0 always — migration is best-effort (file may not exist yet).

set -euo pipefail

LOCAL_CONFIG="compound-workflows.local.md"

# Nothing to migrate if local config doesn't exist
if [[ ! -f "$LOCAL_CONFIG" ]]; then
  exit 0
fi

# Already migrated if stats_capture key is present
if grep -q 'stats_capture' "$LOCAL_CONFIG"; then
  exit 0
fi

# Append stats keys
echo 'stats_capture: true' >> "$LOCAL_CONFIG"
echo 'stats_classify: true' >> "$LOCAL_CONFIG"

echo "STATS_KEYS_ADDED=true"

exit 0
