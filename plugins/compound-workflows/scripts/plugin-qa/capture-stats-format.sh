#!/usr/bin/env bash
# capture-stats-format.sh — Verify capture-stats.sh handles arg 9 usage formats
#
# Tests capture-stats.sh with usage data passed as positional arg 9:
#   1. Comma-separated named fields (full extraction)
#   2. Empty string arg 9 (failure case)
#   3. "null" literal arg 9 (failure case)
#   4. Partial field extraction (single field — status: failure)
#   5. Timeout variant (--timeout flag, no arg 9)
#   6. Malformed content (random garbage — status: failure)
#
# Part of Tier 1 plugin QA. Exits 0 if all pass, 1 if any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/lib.sh"

resolve_plugin_root "${1:-}"
init_findings

CAPTURE_SCRIPT="$PLUGIN_ROOT/scripts/capture-stats.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# --- Test 1: Comma-separated (full extraction) ---
STATS_FILE="$TMPDIR/test1.yaml"

bash "$CAPTURE_SCRIPT" "$STATS_FILE" "plan" "test-agent" "1.1" "opus" "test" "none" "test-run" \
  "total_tokens: 40488, tool_uses: 16, duration_ms: 55379"

if grep -q 'tokens: 40488' "$STATS_FILE" && grep -q 'tools: 16' "$STATS_FILE" && grep -q 'duration_ms: 55379' "$STATS_FILE"; then
  : # pass
else
  add_finding "CRITICAL" "$CAPTURE_SCRIPT" "" "comma-format" "Failed to extract values from comma-separated format"
fi

# --- Test 2: Empty string arg 9 (failure case) ---
STATS_FILE="$TMPDIR/test2.yaml"

bash "$CAPTURE_SCRIPT" "$STATS_FILE" "brainstorm" "test-agent" "2.1" "sonnet" "test" "none" "test-run" ""

if grep -q 'status: failure' "$STATS_FILE"; then
  : # pass
else
  add_finding "SERIOUS" "$CAPTURE_SCRIPT" "" "empty-usage" "Empty string arg 9 should produce status: failure"
fi

if grep -q 'tokens: null' "$STATS_FILE"; then
  : # pass
else
  add_finding "SERIOUS" "$CAPTURE_SCRIPT" "" "empty-usage-tokens" "Empty string arg 9 should produce tokens: null"
fi

# --- Test 3: Null/absent usage (failure case) ---
STATS_FILE="$TMPDIR/test3.yaml"

bash "$CAPTURE_SCRIPT" "$STATS_FILE" "work" "test-agent" "3.1" "opus" "test" "none" "test-run" "null"

if grep -q 'status: failure' "$STATS_FILE"; then
  : # pass
else
  add_finding "SERIOUS" "$CAPTURE_SCRIPT" "" "null-usage" "Literal 'null' arg 9 should produce status: failure"
fi

# --- Test 4: Partial field extraction (single field — failure) ---
STATS_FILE="$TMPDIR/test4.yaml"

bash "$CAPTURE_SCRIPT" "$STATS_FILE" "review" "test-agent" "4.1" "opus" "test" "none" "test-run" \
  "total_tokens: 8500"

if grep -q 'tokens: 8500' "$STATS_FILE"; then
  : # pass
else
  add_finding "CRITICAL" "$CAPTURE_SCRIPT" "" "partial-tokens" "Failed to extract tokens from partial field input"
fi

if grep -q 'tools: null' "$STATS_FILE" && grep -q 'duration_ms: null' "$STATS_FILE"; then
  : # pass
else
  add_finding "SERIOUS" "$CAPTURE_SCRIPT" "" "partial-nulls" "Partial input should leave missing fields as null"
fi

if grep -q 'status: failure' "$STATS_FILE"; then
  : # pass
else
  add_finding "SERIOUS" "$CAPTURE_SCRIPT" "" "partial-status" "Partial extraction (missing fields) should produce status: failure"
fi

# --- Test 5: Timeout variant ---
STATS_FILE="$TMPDIR/test5.yaml"

bash "$CAPTURE_SCRIPT" --timeout "$STATS_FILE" "plan" "test-agent" "5.1" "opus" "test" "none" "test-run"

if grep -q 'status: timeout' "$STATS_FILE" && grep -q 'tokens: null' "$STATS_FILE"; then
  : # pass
else
  add_finding "SERIOUS" "$CAPTURE_SCRIPT" "" "timeout-variant" "Timeout variant should produce status: timeout with null tokens"
fi

# --- Test 6: Malformed content (random garbage) ---
STATS_FILE="$TMPDIR/test6.yaml"

bash "$CAPTURE_SCRIPT" "$STATS_FILE" "work" "test-agent" "6.1" "opus" "test" "none" "test-run" \
  "some random garbage with no fields"

if grep -q 'status: failure' "$STATS_FILE"; then
  : # pass
else
  add_finding "SERIOUS" "$CAPTURE_SCRIPT" "" "malformed-status" "Malformed content should produce status: failure"
fi

if grep -q 'tokens: null' "$STATS_FILE"; then
  : # pass
else
  add_finding "SERIOUS" "$CAPTURE_SCRIPT" "" "malformed-tokens" "Malformed content should produce tokens: null"
fi

emit_output "Capture Stats Format Check"
exit "$( [[ "$finding_count" -eq 0 ]] && echo 0 || echo 1 )"
