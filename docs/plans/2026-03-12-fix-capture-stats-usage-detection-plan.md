---
title: "fix: capture-stats.sh — distinguish missing usage from changed format"
type: fix
status: completed
date: 2026-03-12
bead: 4qc9
---

# Fix: capture-stats.sh — Distinguish Missing Usage from Changed Format

## Problem

`capture-stats.sh` has a single codepath (lines 64-72) for two distinct situations:

1. **No usage data available** — orchestrator passes a placeholder like `no-usage-data` because the background Agent completion notification didn't include parseable `<usage>` data. This is informational — nothing is broken.
2. **Usage data present but unparseable** — the `<usage>` tag is present but the format changed (e.g., field names renamed, delimiter changed). This is an actual warning that the parser needs updating.

Currently both hit the same `grep -qE '<usage>.*total_tokens'` check and emit: `Stats capture: <usage> format may have changed — consider filing a bug`. This is misleading for case 1.

## Fix

Add an early check: if `USAGE_LINE` does not contain `<usage>`, treat it as "no usage data" — set `STATUS="failure"`, emit an informational message (not a warning), and skip parsing. The existing format-change warning only fires when `<usage>` IS present but `total_tokens` is missing.

## Implementation

- [x] **Step 1: Add no-usage-data detection** — After the existing `if [[ -z "$USAGE_LINE" || "$USAGE_LINE" == "null" ]]` block (line 64), add a new branch: if `USAGE_LINE` does not contain the literal string `<usage>`, set `STATUS="failure"`, echo an informational message to stderr (`Stats capture: no <usage> data in response (normal for some dispatch types)`), and skip to the YAML write. The existing `else` block (lines 66-93) only runs when `<usage>` IS present.

- [x] **Step 2: Update QA test** — `scripts/plugin-qa/capture-stats-format.sh` tests the script. Add a test case that passes a non-usage string (e.g., `no-usage-data`) and verifies it produces `status: failure` WITHOUT the "format may have changed" warning. Also verify the existing format-change test still works for actual `<usage>` with missing fields.

## Acceptance Criteria

- Passing `no-usage-data` or any string without `<usage>` → `status: failure`, informational message, NO format-change warning
- Passing `<usage>total_tokens: 100, tool_uses: 5, duration_ms: 1000</usage>` → `status: success`, no warnings (existing behavior preserved)
- Passing `<usage>some_new_field: 42</usage>` → `status: failure`, format-change warning ("format may have changed")
- Passing empty string or `null` → `status: failure`, no message (existing behavior preserved)
- All existing QA tests pass
