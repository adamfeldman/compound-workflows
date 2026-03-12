#!/usr/bin/env bash
# capture-stats-format.sh — Verify capture-stats.sh handles both usage formats
#
# Tests capture-stats.sh with:
#   1. Comma-separated (Task tool format)
#   2. Newline-separated (Agent tool format)
#   3. Empty/null usage (failure case)
#   4. XML-style nested tags (<total_tokens>N</total_tokens>)
#   5. Timeout variant
#   6. Non-usage string (no <usage> tag — e.g., placeholder like "no-usage-data")
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

# --- Test 1: Comma-separated (Task tool format) ---
STATS_FILE="$TMPDIR/test1.yaml"
USAGE_COMMA='<usage>total_tokens: 40488, tool_uses: 16, duration_ms: 55379</usage>'
STDERR_OUT="$TMPDIR/test1.stderr"

echo "$USAGE_COMMA" | bash "$CAPTURE_SCRIPT" "$STATS_FILE" "plan" "test-agent" "1.1" "opus" "test" "none" "test-run" 2>"$STDERR_OUT"

if grep -q 'tokens: 40488' "$STATS_FILE" && grep -q 'tools: 16' "$STATS_FILE" && grep -q 'duration_ms: 55379' "$STATS_FILE"; then
  : # pass
else
  add_finding "CRITICAL" "$CAPTURE_SCRIPT" "" "comma-format" "Failed to extract values from comma-separated (Task) format"
fi

if grep -q 'format may have changed' "$STDERR_OUT"; then
  add_finding "SERIOUS" "$CAPTURE_SCRIPT" "" "comma-format-warning" "Health check warns on comma-separated format (should accept)"
fi

# --- Test 2: Newline-separated (Agent tool format) ---
STATS_FILE="$TMPDIR/test2.yaml"
USAGE_NEWLINE="$(printf '<usage>total_tokens: 12345\ntool_uses: 8\nduration_ms: 30000</usage>')"
STDERR_OUT="$TMPDIR/test2.stderr"

printf '%s' "$USAGE_NEWLINE" | bash "$CAPTURE_SCRIPT" "$STATS_FILE" "brainstorm" "test-agent" "2.1" "sonnet" "test" "none" "test-run" 2>"$STDERR_OUT"

if grep -q 'tokens: 12345' "$STATS_FILE" && grep -q 'tools: 8' "$STATS_FILE" && grep -q 'duration_ms: 30000' "$STATS_FILE"; then
  : # pass
else
  add_finding "CRITICAL" "$CAPTURE_SCRIPT" "" "newline-format" "Failed to extract values from newline-separated (Agent) format"
fi

if grep -q 'format may have changed' "$STDERR_OUT"; then
  add_finding "SERIOUS" "$CAPTURE_SCRIPT" "" "newline-format-warning" "Health check warns on newline-separated format (should accept)"
fi

# --- Test 3: Empty/null usage (failure case) ---
STATS_FILE="$TMPDIR/test3.yaml"

echo "" | bash "$CAPTURE_SCRIPT" "$STATS_FILE" "work" "test-agent" "3.1" "opus" "test" "none" "test-run" 2>/dev/null

if grep -q 'status: failure' "$STATS_FILE"; then
  : # pass
else
  add_finding "SERIOUS" "$CAPTURE_SCRIPT" "" "empty-usage" "Empty usage should produce status: failure"
fi

# --- Test 4: XML-style nested tags ---
STATS_FILE="$TMPDIR/test4.yaml"
USAGE_XML='<usage><total_tokens>8500</total_tokens><tool_uses>4</tool_uses><duration_ms>12000</duration_ms></usage>'
STDERR_OUT="$TMPDIR/test4.stderr"

echo "$USAGE_XML" | bash "$CAPTURE_SCRIPT" "$STATS_FILE" "review" "test-agent" "4.1" "opus" "test" "none" "test-run" 2>"$STDERR_OUT"

if grep -q 'tokens: 8500' "$STATS_FILE" && grep -q 'tools: 4' "$STATS_FILE" && grep -q 'duration_ms: 12000' "$STATS_FILE"; then
  : # pass
else
  add_finding "CRITICAL" "$CAPTURE_SCRIPT" "" "xml-format" "Failed to extract values from XML-style tag format"
fi

if grep -q 'format may have changed' "$STDERR_OUT"; then
  add_finding "SERIOUS" "$CAPTURE_SCRIPT" "" "xml-format-warning" "Health check warns on XML-style format (should accept)"
fi

# --- Test 5: Timeout variant ---
STATS_FILE="$TMPDIR/test5.yaml"

bash "$CAPTURE_SCRIPT" --timeout "$STATS_FILE" "plan" "test-agent" "5.1" "opus" "test" "none" "test-run" 2>/dev/null

if grep -q 'status: timeout' "$STATS_FILE" && grep -q 'tokens: null' "$STATS_FILE"; then
  : # pass
else
  add_finding "SERIOUS" "$CAPTURE_SCRIPT" "" "timeout-variant" "Timeout variant should produce status: timeout with null tokens"
fi

# --- Test 6: Non-usage string (no <usage> tag) ---
STATS_FILE="$TMPDIR/test6.yaml"
STDERR_OUT="$TMPDIR/test6.stderr"

echo "no-usage-data" | bash "$CAPTURE_SCRIPT" "$STATS_FILE" "work" "test-agent" "6.1" "opus" "test" "none" "test-run" 2>"$STDERR_OUT"

if grep -q 'status: failure' "$STATS_FILE"; then
  : # pass
else
  add_finding "SERIOUS" "$CAPTURE_SCRIPT" "" "no-usage-tag-status" "Non-usage string should produce status: failure"
fi

if grep -q 'format may have changed' "$STDERR_OUT"; then
  add_finding "SERIOUS" "$CAPTURE_SCRIPT" "" "no-usage-tag-false-warning" "Non-usage string should NOT emit 'format may have changed' warning"
fi

if grep -q 'no <usage> data in response' "$STDERR_OUT"; then
  : # pass
else
  add_finding "SERIOUS" "$CAPTURE_SCRIPT" "" "no-usage-tag-missing-info" "Non-usage string should emit informational 'no <usage> data' message to stderr"
fi

emit_output "Capture Stats Format Check"
exit "$( [[ "$finding_count" -eq 0 ]] && echo 0 || echo 1 )"
