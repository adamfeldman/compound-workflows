#!/usr/bin/env bash
# append-snapshot.sh — Atomic append of ccusage snapshot YAML documents
#
# Usage:
#   bash append-snapshot.sh <file> <timestamp> <cost> <input> <output> [key=value...]
#
# Exits 0 always — snapshot capture must never block compact-prep.

set -euo pipefail

FILE="${1:?missing snapshot file}"
TIMESTAMP="${2:?missing timestamp}"
COST="${3:?missing total_cost_usd}"
INPUT="${4:?missing input_tokens}"
OUTPUT="${5:?missing output_tokens}"
shift 5

# Ensure directory exists
mkdir -p "$(dirname "$FILE")"

# Core fields
cat >> "$FILE" <<EOF
---
type: ccusage-snapshot
timestamp: $TIMESTAMP
total_cost_usd: $COST
input_tokens: $INPUT
output_tokens: $OUTPUT
EOF

# Extensible fields (key=value pairs)
for kv in "$@"; do
  KEY="${kv%%=*}"
  VAL="${kv#*=}"
  echo "$KEY: $VAL" >> "$FILE"
done

exit 0
