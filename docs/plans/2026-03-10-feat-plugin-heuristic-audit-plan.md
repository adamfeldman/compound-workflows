---
title: "feat: Plugin heuristic audit — eliminate mid-workflow permission prompts"
type: feat
status: active
date: 2026-03-10
origin: docs/brainstorms/2026-03-10-plugin-heuristic-audit-brainstorm.md
bead: jak
---

# Plugin Heuristic Audit

## Summary

Eliminate mid-workflow permission prompts caused by Claude Code's bash safety heuristics (`$()`, heredocs, `{"`, backticks) in plugin command files. Four deliverables:

1. **validate-stats.sh** — new script replacing 9 inline `ENTRY_COUNT=$(grep -c ...)` blocks across 5 command files
2. **P5 cleanup** — remove unnecessary `$(echo $VAR)` subshells (2 occurrences)
3. **Sentinel redesign** — replace `rm -f .workflows/.work-in-progress` with Write tool clear marker (2 occurrences in work.md)
4. **QA regression check** — new check in `context-lean-grep.sh` to prevent `$()` pattern regrowth, with `# heuristic-exempt` suppress markers on accepted init-block patterns

Init-block prompts (once per workflow phase start) are accepted. Only mid-workflow prompts that interrupt work momentum are targeted. (see brainstorm: Decision 1)

## Background

The brainstorm (see `docs/brainstorms/2026-03-10-plugin-heuristic-audit-brainstorm.md`) established that static `Bash(X:*)` rules suppress Claude Code's built-in heuristics entirely when the first token matches. This means most heuristic-triggering patterns (git commit heredocs, bd metadata JSON, cat heredocs) are already solved for users with `git:*`, `gh:*`, `bd:*`, `cat:*` static rules. The remaining prompts come from `VAR=$()` patterns where the first token is a variable assignment — no static rule can match these.

Key decisions carried forward from brainstorm:
- **Decision 1:** Target only mid-workflow prompts. Accept init-block prompts.
- **Decision 2:** P7 (git commit/gh pr heredocs) already solved by `git:*`/`gh:*` static rules. No plugin rewrite needed.
- **Decision 3:** Replace ENTRY_COUNT with validate-stats.sh. Preserve capture-stats.sh "exits 0 always" invariant.
- **Decision 4:** Fix P5 trivially — `$(echo $VAR)` → `$VAR`.
- **Decision 5:** QA regression check to prevent pattern regrowth.
- **Decision 6:** jak absorbs plugin-side items from msm. msm keeps hook/settings side.
- **Decision 7:** Sentinel redesign — clear marker via Write tool, not `rm`. User: "adding rm is a terrible idea."
- **Decision 8:** chmod one-time prompt accepted — no static rule for one-time setup operation.
- **Decision 9:** `ccusage:*` static rule already added (done).

### Scope

Plugin-side command file rewrites plus the sentinel-related changes in work.md. Other hook-side work (missing safe prefixes, Permissive profile rebuild, custom prefix support) stays in bead msm. (see brainstorm: Decision 6)

## Implementation Constraints

- **`bash:*` static rule dependency:** `bash validate-stats.sh` calls have `bash` as first token. With `Bash(bash:*)` in settings.local.json or Permissive profile, these auto-approve. Without it, each call prompts once — still a net improvement over 2-3 ENTRY_COUNT prompts per phase. Plan assumes `bash:*` exists but works without it.
- **capture-stats.sh invariant:** The `exits 0 always` design must be preserved. validate-stats.sh is a separate script with its own exit behavior. capture-stats.sh is NOT modified.
- **plugin-qa-check.sh sentinel check already handles "cleared" content:** The hook's `grep -qE '^[0-9]+$'` validation falls through for non-numeric content (e.g., "cleared"). No change needed to the hook's sentinel logic.
- **Command files are prose, not code:** Each edit must update both bash code blocks AND surrounding prose descriptions.
- **Init blocks:** All 5 command files with stats capture have init blocks containing `$()`. These are accepted prompts (Decision 1) and will be marked with `# heuristic-exempt`.
- **DISPATCH_COUNT is model-side:** The dispatch counter is tracked by the model in its context (not a bash variable). When calling `bash validate-stats.sh "$STATS_FILE" 5`, the model substitutes the literal count. No `$()` or `$((...))` appears in the actual bash command.
- **`$((...))` IS a heuristic trigger:** Empirically verified — `TEST_VAL=$((2 + 3))` prompts for permission. Arithmetic expansion `$((...))` triggers the same heuristic as command substitution `$(...)`. The QA regression check must catch both patterns. Any `$((...))` in command files needs `# heuristic-exempt` if intentional.
- **Sentinel creation stays bash:** `date +%s > .workflows/.work-in-progress` prompts due to `>` redirect, but this is at workflow start (Phase 1.2.1), not mid-workflow. The model cannot reliably produce Unix epoch timestamps, so Write tool is not viable for creation. Accept the one prompt.
- **Hook code runs in bash directly:** `plugin-qa-check.sh` runs as a bash subprocess, not through Claude Code. Its internal `$()` usage (e.g., `$(cat "$sentinel")`) does not trigger Claude Code heuristics. No changes needed to the hook's check_sentinel function.

## Prompt Count Analysis

### Before (representative /compound:brainstorm run with red team):
| Prompt Source | Count | Type |
|--------------|-------|------|
| Init block ($(), find, date, uuidgen) | 1 | Accepted |
| ENTRY_COUNT after research | 1 | **Mid-workflow** |
| ENTRY_COUNT after red team | 1 | **Mid-workflow** |
| ENTRY_COUNT after MINOR triage | 1 | **Mid-workflow** |
| **Total mid-workflow** | **3** | |

### After:
| Prompt Source | Count | Type |
|--------------|-------|------|
| Init block ($(), find, date, uuidgen) | 1 | Accepted |
| validate-stats.sh (with bash:*) | 0 | Eliminated |
| validate-stats.sh (without bash:*) | 1 | Net -2 |
| Recovery stale check ($() in sentinel_content, sentinel_age) | 0–2 | Accepted (recovery only) |
| **Total mid-workflow** | **0–1** | |

**Note:** Recovery block prompts (sentinel_content, sentinel_age) only appear when resuming a crashed/stale session. They are `$()` patterns in the recovery path — accepted because recovery runs once per resumed session, not mid-workflow.

### Per-command savings:
| Command | ENTRY_COUNT removed | Sentinel rm removed | Net prompts saved |
|---------|--------------------|--------------------|-------------------|
| brainstorm.md | 3 | 0 | 2–3 |
| plan.md | 2 | 0 | 1–2 |
| deepen-plan.md | 2 | 0 | 1–2 |
| work.md | 1 | 2 | 2–3 |
| review.md | 1 | 0 | 0–1 |
| **Total** | **9** | **2** | **6–11** |

## Implementation Steps

### Step 1: Create validate-stats.sh

**File:** `plugins/compound-workflows/scripts/validate-stats.sh` (NEW)

```bash
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
```

- [ ] Create the script file with the exact content above
- [ ] Verify `chmod +x` is NOT needed — script is called via `bash validate-stats.sh`, not `./validate-stats.sh`

**Design notes:**
- No `set -euo pipefail` — the script exits 0 by design at every path (diagnostic, never blocks). Using `set -e` would contradict this invariant and create latent bugs on future edits.
- `grep -c '^---$'` happens inside the script — hidden from Claude Code's heuristic scanner.
- `ACTUAL=${ACTUAL:-0}` handles the case where `grep` produces no output (file doesn't exist or error). This avoids the `|| echo 0` pattern which would produce `"0\n0"` (grep outputs "0" then echo outputs another "0").
- Mismatch warning goes to stderr. Match confirmation goes to stdout. The model reads both.
- No `$()` in the calling bash block: `bash $PLUGIN_ROOT/scripts/validate-stats.sh "$STATS_FILE" <EXPECTED_COUNT>` — first token `bash`, all arguments are literal variable expansions (no subshells). The model substitutes literal numbers for `<EXPECTED_COUNT>` (model-side tracking).
- **Report-only mode:** Call with explicit `report` keyword: `bash validate-stats.sh "$STATS_FILE" report`. Available for future use where report-only semantics are desired (no current call site uses it — brainstorm.md site 3 was upgraded to validation mode). Empty second argument triggers a WARNING — this catches model failures to substitute placeholders (especially important for Sonnet).
- **Placeholder convention:** `<DISPATCH_COUNT>`, `<EXPECTED_TOTAL>`, and `<EXPECTED_COUNT>` in bash templates are model-side placeholders — the model substitutes literal numbers at runtime (e.g., `bash validate-stats.sh "$STATS_FILE" 5`). They use angle-bracket syntax (not `$`) to make the model-side vs bash distinction clear and to cause a loud bash error if pasted verbatim. `$PLUGIN_ROOT` and `$STATS_FILE` ARE bash variables set in the init block — they use `$` syntax.

### Step 2: Update brainstorm.md — replace 3 ENTRY_COUNT blocks

**File:** `plugins/compound-workflows/commands/compound/brainstorm.md`

- [ ] **Line 94–102:** Replace the research-phase validation block.

**Old (lines 94–102):**
```
After both research agents complete, validate entry count:

```bash
ENTRY_COUNT=$(grep -c '^---$' "$STATS_FILE" 2>/dev/null || echo 0)
EXPECTED=2
if [ "$ENTRY_COUNT" -ne "$EXPECTED" ]; then
  echo "Stats capture: expected $EXPECTED entries but found $ENTRY_COUNT after research phase." >&2
fi
```
```

**New:**
```
After both research agents complete, validate entry count:

```bash
bash $PLUGIN_ROOT/scripts/validate-stats.sh "$STATS_FILE" 2
```
```

- [ ] **Lines 361–369:** Replace the red-team-phase validation block.

**Old (lines 361–369):**
```
Track the number of red team agents actually dispatched (2-3 depending on PAL availability). After all red team completions, validate:

```bash
ENTRY_COUNT=$(grep -c '^---$' "$STATS_FILE" 2>/dev/null || echo 0)
EXPECTED_TOTAL=$((2 + <red-team-count>))  # 2 research + N red team agents dispatched
if [ "$ENTRY_COUNT" -ne "$EXPECTED_TOTAL" ]; then
  echo "Stats capture: expected $EXPECTED_TOTAL entries but found $ENTRY_COUNT after red team phase." >&2
fi
```
```

**New:**
```
Track the number of red team agents actually dispatched (2-3 depending on PAL availability). After all red team completions, validate stats count. The expected total is 2 (research) + the number of red team agents dispatched. Note: the old `$((2 + N))` arithmetic was itself a heuristic trigger (empirically verified); model-side tracking eliminates it:

```bash
bash $PLUGIN_ROOT/scripts/validate-stats.sh "$STATS_FILE" <EXPECTED_TOTAL>
```

Where `<EXPECTED_TOTAL>` is tracked by incrementing a counter during dispatch (already described above). The model substitutes the literal number (e.g., `5`). If validate-stats.sh reports a mismatch, warn but do not fail.
```

- [ ] **Lines 477–482:** Replace the MINOR-triage validation block.

**Old (lines 477–482):**
```
Validate total entry count (2 research + N red team + 1 triage):

```bash
ENTRY_COUNT=$(grep -c '^---$' "$STATS_FILE" 2>/dev/null || echo 0)
echo "Stats capture: $ENTRY_COUNT total entries after MINOR triage."
```
```

**New:**
```
Validate total entry count (2 research + N red team + 1 triage). The expected total is tracked by the dispatch counter:

```bash
bash $PLUGIN_ROOT/scripts/validate-stats.sh "$STATS_FILE" <EXPECTED_TOTAL>
```
```

### Step 3: Update review.md — 1 ENTRY_COUNT + 1 P5 fix

**File:** `plugins/compound-workflows/commands/compound/review.md`

- [ ] **Line 43:** Fix P5 — remove unnecessary subshell.

**Old:** `CACHED_SUBAGENT_MODEL=$(echo $CLAUDE_CODE_SUBAGENT_MODEL)`
**New:** `CACHED_SUBAGENT_MODEL=$CLAUDE_CODE_SUBAGENT_MODEL`

- [ ] **Lines 132–139:** Replace the stats validation block.

**Old (lines 132–139):**
```
After all agents have completed (or timed out), if stats capture is enabled, validate that the stats file contains the expected number of entries:

```bash
ENTRY_COUNT=$(grep -c '^---$' "$STATS_FILE" 2>/dev/null || echo 0)
echo "Stats validation: $ENTRY_COUNT entries in $STATS_FILE (expected: $DISPATCH_COUNT)"
```

If `ENTRY_COUNT` does not match `DISPATCH_COUNT`, warn with the names of missing agents — do not fail the command. This is a diagnostic warning only. Compare the list of dispatched agent names against agents with stats entries to identify which agents are missing.
```

**New:**
```
After all agents have completed (or timed out), if stats capture is enabled, validate that the stats file contains the expected number of entries:

```bash
bash $PLUGIN_ROOT/scripts/validate-stats.sh "$STATS_FILE" <DISPATCH_COUNT>
```

If validate-stats.sh reports a mismatch, warn with the names of missing agents — do not fail the command. This is a diagnostic warning only. Compare the list of dispatched agent names against agents with stats entries to identify which agents are missing.
```

### Step 4: Update plan.md — 2 ENTRY_COUNT blocks

**File:** `plugins/compound-workflows/commands/compound/plan.md`

- [ ] **Lines 124–130:** Replace the post-dispatch validation.

**Old (lines 124–130):**
```
After all dispatches complete, validate entry count matches completed dispatch count:

```bash
ENTRY_COUNT=$(grep -c '^---$' "$STATS_FILE" 2>/dev/null || echo 0)
```

If ENTRY_COUNT does not match the dispatch counter, warn with the names of missing agents. Do not fail the command.
```

**New:**
```
After all dispatches complete, validate entry count matches completed dispatch count:

```bash
bash $PLUGIN_ROOT/scripts/validate-stats.sh "$STATS_FILE" <DISPATCH_COUNT>
```

If validate-stats.sh reports a mismatch, warn with the names of missing agents. Do not fail the command.
```

- [ ] **Lines 843–851:** Replace the Phase 6.95 Stats Validation.

**Old (lines 843–851):**
```
### 6.95. Stats Validation

If stats capture is enabled, validate entry count against dispatch counter:

```bash
ENTRY_COUNT=$(grep -c '^---$' "$STATS_FILE" 2>/dev/null || echo 0)
```

Compare `ENTRY_COUNT` to the dispatch counter. If they don't match, warn: "Stats capture: expected N entries but found M. Missing agents: [list agent names that were dispatched but not captured]." Do not fail the command. Account for conditional dispatches — only count agents that were actually dispatched (external research 0-2, consolidator 0-1, verify 0-2, red team 0-4, re-check 0-3).
```

**New:**
```
### 6.95. Stats Validation

If stats capture is enabled, validate entry count against dispatch counter:

```bash
bash $PLUGIN_ROOT/scripts/validate-stats.sh "$STATS_FILE" <DISPATCH_COUNT>
```

If validate-stats.sh reports a mismatch, warn with the names of missing agents (not just the count delta). Do not fail the command. Account for conditional dispatches — only count agents that were actually dispatched (external research 0-2, consolidator 0-1, verify 0-2, red team 0-4, re-check 0-3).
```

### Step 5: Update deepen-plan.md — 2 ENTRY_COUNT blocks

**File:** `plugins/compound-workflows/commands/compound/deepen-plan.md`

- [ ] **Lines 69–75:** Replace the post-dispatch validation.

**Old (lines 69–75):**
```
**Post-dispatch validation (end of command):**

```bash
ENTRY_COUNT=$(grep -c '^---$' "$STATS_FILE" 2>/dev/null || echo 0)
```

If ENTRY_COUNT does not match the dispatch counter, warn with the names of missing agents. Do not fail the command.
```

**New:**
```
**Post-dispatch validation (end of command):**

```bash
bash $PLUGIN_ROOT/scripts/validate-stats.sh "$STATS_FILE" <DISPATCH_COUNT>
```

If validate-stats.sh reports a mismatch, warn with the names of missing agents. Do not fail the command.
```

- [ ] **Lines 1276–1284:** Replace the Post-Dispatch Stats Validation.

**Old (lines 1276–1284):**
```
### Post-Dispatch Stats Validation

If stats capture is enabled: after all phases complete, validate the total entry count against the dispatch counter.

```bash
ENTRY_COUNT=$(grep -c '^---$' "$STATS_FILE" 2>/dev/null || echo 0)
```

If ENTRY_COUNT does not match the dispatch counter, warn with the names of missing agents (not just the count delta). Example: "Stats capture: expected 22 entries but found 20. Missing agents: review--performance-oracle, readiness--plan-consolidator". Do not fail the command — this is a diagnostic warning only.
```

**New:**
```
### Post-Dispatch Stats Validation

If stats capture is enabled: after all phases complete, validate the total entry count against the dispatch counter.

```bash
bash $PLUGIN_ROOT/scripts/validate-stats.sh "$STATS_FILE" <DISPATCH_COUNT>
```

If validate-stats.sh reports a mismatch, warn with the names of missing agents (not just the count delta). Example: "Stats capture: expected 22 entries but found 20. Missing agents: review--performance-oracle, readiness--plan-consolidator". Do not fail the command — this is a diagnostic warning only.
```

### Step 6: Update work.md — 1 ENTRY_COUNT + 1 P5 fix + sentinel redesign

**File:** `plugins/compound-workflows/commands/compound/work.md`

This is the most complex step — three change types in one file.

#### 6a: Fix P5 — remove unnecessary subshell

- [ ] **Line 64:** `CACHED_SUBAGENT_MODEL=$(echo $CLAUDE_CODE_SUBAGENT_MODEL)` → `CACHED_SUBAGENT_MODEL=$CLAUDE_CODE_SUBAGENT_MODEL`

#### 6b: Replace ENTRY_COUNT block

- [ ] **Lines 360–367:** Replace the stats validation block.

**Old (lines 360–367):**
```
After the dispatch loop completes (all issues closed or all TodoWrite tasks completed), if stats capture is enabled, validate that the stats file contains the expected number of entries:

```bash
ENTRY_COUNT=$(grep -c '^---$' "$STATS_FILE" 2>/dev/null || echo 0)
echo "Stats validation: $ENTRY_COUNT entries in $STATS_FILE (expected: $DISPATCH_COUNT)"
```

Track `DISPATCH_COUNT` by incrementing a counter after each successful `capture-stats.sh` call during the dispatch loop. If `ENTRY_COUNT` does not match `DISPATCH_COUNT`, warn with the names of missing agents — do not fail the command. This is a diagnostic warning only.
```

**New:**
```
After the dispatch loop completes (all issues closed or all TodoWrite tasks completed), if stats capture is enabled, validate that the stats file contains the expected number of entries:

```bash
bash $PLUGIN_ROOT/scripts/validate-stats.sh "$STATS_FILE" <DISPATCH_COUNT>
```

Track `DISPATCH_COUNT` by incrementing a counter after each successful `capture-stats.sh` call during the dispatch loop. If validate-stats.sh reports a mismatch, warn with the names of missing agents — do not fail the command. This is a diagnostic warning only.
```

#### 6c: Sentinel redesign — clear with Write tool instead of rm

The sentinel lifecycle changes from `rm -f` to Write tool "cleared" marker. The hook (`plugin-qa-check.sh`) already handles this correctly — its `grep -qE '^[0-9]+$'` validation falls through for non-numeric content, so "cleared" = not suppressed. No hook change needed.

- [ ] **Line 339 (recovery stale check):** Replace the stale sentinel cleanup block.

**Old (lines 333–341):**
```
3. Check for stale sentinel file and clean up if needed:
   ```bash
   if [ -f .workflows/.work-in-progress ]; then
     sentinel_age=$(( $(date +%s) - $(cat .workflows/.work-in-progress) ))
     if [ "$sentinel_age" -ge 14400 ]; then
       echo "Stale sentinel detected ($(( sentinel_age / 3600 ))h old) — removing to re-enable QA hook"
       rm -f .workflows/.work-in-progress
     fi
   fi
   ```
```

**New:**
```
3. Check for stale sentinel file and clean up if needed:
   ```bash
   if [ -f .workflows/.work-in-progress ]; then
     sentinel_content=$(cat .workflows/.work-in-progress 2>/dev/null || echo "")
     if echo "$sentinel_content" | grep -qE '^[0-9]+$' 2>/dev/null; then
       sentinel_age=$(( $(date +%s) - sentinel_content ))
       if [ "$sentinel_age" -ge 14400 ]; then
         echo "Stale sentinel detected ($(( sentinel_age / 3600 ))h old) — clearing to re-enable QA hook"
       fi
     fi
   fi
   ```
   If the above echo indicates a stale sentinel (age ≥ 4 hours), **IMMEDIATELY** use the **Write tool** to write `cleared` to `.workflows/.work-in-progress` before proceeding to Phase 3. Do not continue with stale sentinel active. If the content is already `cleared` or non-numeric, the sentinel is already inactive — skip.
```

**Design note:** The stale check still uses `$()` in `$(cat ...)` and `$(date +%s)`. These are VAR=$() patterns that prompt. This is acceptable — recovery runs once per resumed session, not mid-workflow. The `rm -f` is eliminated, which was the dangerous pattern. The sentinel is cleared by writing "cleared" via Write tool (prompt-free).

- [ ] **Lines 418–421 (Phase 4 Ship):** Replace `rm -f` sentinel clear.

**Old (lines 418–421):**
```
2. **Remove QA hook sentinel** (re-enable PostToolUse QA enforcement):
   ```bash
   rm -f .workflows/.work-in-progress
   ```
```

**New:**
```
2. **Clear QA hook sentinel** (re-enable PostToolUse QA enforcement):

   Use the **Write tool** to write `cleared` to `.workflows/.work-in-progress`. Do not use `rm` — the Write tool is prompt-free and the hook already handles non-numeric content correctly (falls through without suppressing QA).
```

- [ ] **Phase 1.2.1 sentinel description** (near line 137, after the `date +%s >` code block). Update the prose that describes the sentinel lifecycle.

**Old:** `This sentinel is checked by \`.claude/hooks/plugin-qa-check.sh\`. It is removed in Phase 4 (Ship) and cleaned up if stale in Phase 2.4 (Recovery).`

**New:** `This sentinel is checked by \`.claude/hooks/plugin-qa-check.sh\`. It is cleared (content set to "cleared" via Write tool) in Phase 4 (Ship) and cleaned up if stale in Phase 2.4 (Recovery). The hook validates numeric content — non-numeric content like "cleared" is treated as inactive.`

**Context:** This line immediately follows the `### 1.2.1 Create QA Hook Sentinel` section's `date +%s > .workflows/.work-in-progress` code block.

### Step 7: Add heuristic-exempt markers to init blocks

#### 7a: Automated discovery — scan for all remaining VAR=$() patterns

Before placing markers from the known inventory, run an automated discovery to find ALL `VAR=$()` and `VAR=$((...))` patterns remaining across command files after Steps 2–6:

```bash
grep -rnE '^\s*[A-Z_]+=.*\$\(' plugins/compound-workflows/commands/compound/*.md | grep -v 'heuristic-exempt'
```

Compare the results against the known inventory below. Any inventory items NOT found by discovery indicate they were already removed by Steps 2–6 — skip them. Any patterns found by discovery that are NOT in the inventory need classification:

- **Init/setup section** (Phase 0, Phase 1, or before first dispatch) → mark `# heuristic-exempt` with rationale "init-block, runs once before work"
- **Phase boundary** (one-time per workflow run, e.g., hash comparisons, manifest validation) → mark `# heuristic-exempt` with rationale "one-time at phase boundary"
- **Inside a dispatch loop or repeated mid-workflow** → do NOT mark exempt. Flag as a new mid-workflow pattern requiring replacement (same approach as Steps 2–6)

Add classified patterns to the marker list before proceeding.

#### 7b: Place markers from inventory

After Steps 2–6, the remaining `VAR=$()` and `VAR=$((...))` patterns in command files are all accepted init-block or recovery patterns. Mark each with `# heuristic-exempt` trailing comment so the QA regression check (Step 8) doesn't flag them.

**Pattern to mark:** Any line matching `^\s*[A-Z_]+=.*\$\(` that is NOT already replaced by Steps 2–6.

**Files and specific lines to mark (known inventory — verify against 7a discovery):**

- [ ] **brainstorm.md** — init block (Phase 1.1):
  - `PLUGIN_ROOT=$(find ...)` line → append `# heuristic-exempt`
  - `RUN_ID=$(uuidgen | cut -c1-8)` line → append `# heuristic-exempt`

  Note: `STATS_FILE=".workflows/stats/$(date ...)"` uses `$()` inside a string assignment. The QA regex `^\s*[A-Z_]+=.*\$\(` matches this. Mark it: `STATS_FILE="..." # heuristic-exempt`
  Note: `CACHED_MODEL="${CLAUDE_CODE_SUBAGENT_MODEL:-opus}"` has no `$()` — no marker needed.
  Note: `EXPECTED_TOTAL=$((2 + <red-team-count>))` uses `$((...))` arithmetic expansion. **Empirically verified: `$((...))` IS a heuristic trigger** (same as `$()`). The QA regex `\$\(` catches both — no exclusion needed. If this line is not removed by Step 2's replacement, mark it `# heuristic-exempt`.

- [ ] **plan.md** — Stats Setup section:
  - `PLUGIN_ROOT=$(find ...)` → `# heuristic-exempt`
  - `RUN_ID=$(uuidgen ...)` → `# heuristic-exempt`
  - `STATS_FILE="...$(date ...)"` → `# heuristic-exempt`

- [ ] **plan.md** — Phase 6.8.1 + Phase 6.9 (one-time hash comparisons at phase boundaries):
  - Line 398: `PLAN_HASH_BEFORE=$(shasum -a 256 <plan-path> | cut -d' ' -f1)` → `# heuristic-exempt`
  - Line 803: `PLAN_HASH_AFTER=$(shasum -a 256 <plan-path> | cut -d' ' -f1)` → `# heuristic-exempt`

- [ ] **deepen-plan.md** — Phase 0 setup + manifest validation:
  - `PLUGIN_ROOT=$(find ...)` → `# heuristic-exempt`
  - `RUN_ID=$(uuidgen ...)` → `# heuristic-exempt`
  - `STATS_FILE="...$(date ...)"` → `# heuristic-exempt`
  - Line 241: `AGENT_COUNT=$(echo "$VALIDATED" | jq '.agents | length')` → `# heuristic-exempt` (manifest validation, runs once before dispatch)

- [ ] **work.md** — Phase 1.1.1 + Phase 1.2 + recovery + Phase 4:
  - `PLUGIN_ROOT=$(find ...)` → `# heuristic-exempt`
  - `RUN_ID=$(uuidgen ...)` → `# heuristic-exempt`
  - `STATS_FILE="...$(date ...)"` → `# heuristic-exempt`
  - Recovery stale check: `sentinel_content=$(cat ...)` → `# heuristic-exempt`
  - Recovery stale check: `sentinel_age=$(( $(date +%s) - ... ))` → `# heuristic-exempt`
  - Line 115: `WORKTREE_MGR=$(find ...)` → `# heuristic-exempt` (worktree manager resolution, Phase 1.2)
  - Line 459: `WORKTREE_MGR=$(find ...)` → `# heuristic-exempt` (worktree cleanup, Phase 4)

- [ ] **review.md** — Phase 2.1 setup:
  - `PLUGIN_ROOT=$(find ...)` → `# heuristic-exempt`
  - `RUN_ID=$(uuidgen ...)` → `# heuristic-exempt`
  - `STATS_FILE="...$(date ...)"` → `# heuristic-exempt`

- [ ] **compact-prep.md** — 2 patterns to mark:
  - Line 140: `SNAPSHOT_FILE=".workflows/stats/$(date +%Y-%m-%d)-ccusage-snapshot.yaml"` → append `# heuristic-exempt`
  - Line 141: `TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"` → append `# heuristic-exempt`

- [ ] **setup.md** — 3 patterns to mark:
  - Line 353: `INSTALLED_VERSION=$(sed -n '2s/^# auto-approve v//p' .claude/hooks/auto-approve.sh)` → append `# heuristic-exempt`
  - Line 357: `TEMPLATE_VERSION=$(sed -n '2s/^# auto-approve v//p' "$HOOK_TEMPLATE")` → append `# heuristic-exempt`
  - Line 497: `EXACT_COUNT=$(jq -r '.permissions.allow[]? // empty' .claude/settings.local.json 2>/dev/null | grep -c -v '[:*?\[\{]' || echo "0")` → append `# heuristic-exempt`

**Marker format:** `# heuristic-exempt` as a trailing bash comment on the same line. Valid bash syntax — does not affect execution.

#### 7c: Verify marker completeness

After placing all markers, verify no unmarked patterns remain:

```bash
grep -rnE '^\s*[A-Z_]+=.*\$\(' plugins/compound-workflows/commands/compound/*.md | grep -v 'heuristic-exempt'
```

This should return empty. If any lines appear, they are gaps in the inventory — add `# heuristic-exempt` markers to each (if accepted init-block/recovery patterns) or investigate whether they are mid-workflow patterns that need replacement.

- [ ] Verify the grep returns empty before proceeding to Step 8.

### Step 8: Add QA regression check to context-lean-grep.sh

**File:** `plugins/compound-workflows/scripts/plugin-qa/context-lean-grep.sh`

Add a new Check 5 after the existing Check 4 (dispatch-missing-output-instructions), before the `emit_output` line.

- [ ] Add the following check:

```bash
# --- Check 5: VAR=$() patterns that trigger mid-workflow permission prompts ---
# Variable assignments with $() command substitution always prompt (first token
# is a variable assignment, no static rule can match). Accepted patterns
# (init blocks, recovery) must be marked with # heuristic-exempt.
# Catches both $() command substitution and $(()) arithmetic expansion
# (both are empirically verified heuristic triggers).

for f in "$cmd_dir"/*.md; do
  [[ -f "$f" ]] || continue
  matches="$(grep -nE '^\s*[A-Z_]+=.*\$\(' "$f" || true)"
  if [[ -n "$matches" ]]; then
    while IFS= read -r match; do
      line_text="$(echo "$match" | cut -d: -f2-)"
      # Skip lines with heuristic-exempt marker
      if echo "$line_text" | grep -qF 'heuristic-exempt' 2>/dev/null; then
        continue
      fi
      line_num="$(echo "$match" | cut -d: -f1)"
      add_finding "SERIOUS" "$f" "$line_num" "var-dollar-paren-heuristic" \
        "VAR=\$() pattern triggers mid-workflow permission prompt — add # heuristic-exempt if intentional"
    done <<< "$matches"
  fi
done
```

**Design notes:**
- Regex `^\s*[A-Z_]+=.*\$\(` matches both `VAR=$(command...)` and `VAR=$((...))` arithmetic — both are empirically verified heuristic triggers.
- Uses `grep -nE` for batch matching (not per-line — avoids Problem 2 from QA script patterns solution).
- Severity: SERIOUS — new mid-workflow `$()` patterns are significant prompt regressions.
- Suppress: `# heuristic-exempt` on the line. Same pattern as `context-lean-exempt` in Check 4.
- Only scans `$cmd_dir/*.md` (command files). Agent and skill files are not checked.

### Step 9: Version bump + CHANGELOG + file counts

- [ ] Bump version in `plugins/compound-workflows/.claude-plugin/plugin.json` — PATCH increment. validate-stats.sh replaces existing inline functionality (not net-new capability), and the QA check is a development guardrail, not a user-facing feature. No new commands, agents, or skills.
- [ ] Bump version in `.claude-plugin/marketplace.json` — match plugin.json
- [ ] Update `plugins/compound-workflows/CHANGELOG.md`:

```markdown
## v2.4.1 — Plugin Heuristic Audit

- **fix:** Replace 9 inline `ENTRY_COUNT=$(grep -c ...)` blocks with `validate-stats.sh` script — eliminates mid-workflow permission prompts across brainstorm, plan, deepen-plan, work, review commands
- **fix:** Remove unnecessary `$(echo $VAR)` subshells in work.md and review.md init blocks
- **fix:** Sentinel redesign — clear via Write tool marker instead of `rm -f` (work.md)
- **fix:** New `validate-stats.sh` script — extracts existing inline stats validation into a dedicated script (prompt-free, exits 0 always)
- **fix:** QA regression check (Check 5 in context-lean-grep.sh) prevents `$()` pattern regrowth with `# heuristic-exempt` suppress markers
```

- [ ] Verify `plugins/compound-workflows/README.md` — README does not list scripts by count or name. No update needed unless the README is changed to include script details.
- [ ] Update `plugins/compound-workflows/CLAUDE.md` scripts section. Add validate-stats.sh to the listing:

**Old:**
```
scripts/
├── capture-stats.sh         # Deterministic atomic append for per-dispatch YAML stats capture
├── plugin-qa/               # 5 bash scripts + lib.sh — serves both the QA command and the PostToolUse hook
└── version-check.sh         # 3-way version comparison (source vs installed vs release) — NOT in plugin-qa/ (makes network calls)
```

**New:**
```
scripts/
├── capture-stats.sh         # Deterministic atomic append for per-dispatch YAML stats capture
├── validate-stats.sh        # Diagnostic stats entry count validation — replaces inline ENTRY_COUNT=$(grep -c ...) blocks
├── plugin-qa/               # 5 bash scripts + lib.sh — serves both the QA command and the PostToolUse hook
└── version-check.sh         # 3-way version comparison (source vs installed vs release) — NOT in plugin-qa/ (makes network calls)
```

### Step 10: Run QA and verify

- [ ] Run full QA (Tier 1 + Tier 2) via `/compound-workflows:plugin-changes-qa` or manually:
  - **Tier 1 (scripts):** `bash plugins/compound-workflows/scripts/plugin-qa/stale-references.sh plugins/compound-workflows && bash plugins/compound-workflows/scripts/plugin-qa/file-counts.sh plugins/compound-workflows && bash plugins/compound-workflows/scripts/plugin-qa/truncation-check.sh plugins/compound-workflows && bash plugins/compound-workflows/scripts/plugin-qa/context-lean-grep.sh plugins/compound-workflows && bash plugins/compound-workflows/scripts/plugin-qa/version-sync.sh plugins/compound-workflows`
  - **Tier 2 (semantic agents):** Context-lean reviewer, role description reviewer, command completeness reviewer — validates semantic consistency of command file changes (Task dispatch patterns, inline role descriptions, AskUserQuestion usage, etc.)
- [ ] All Tier 1 scripts and Tier 2 agents report zero findings.
- [ ] Verify no ENTRY_COUNT patterns remain: `grep -rn 'ENTRY_COUNT=\$(' plugins/compound-workflows/commands/compound/` should return empty
- [ ] Verify no unmarked VAR=$() patterns: the new Check 5 in context-lean-grep.sh should report zero findings (all accepted patterns have `# heuristic-exempt`)
- [ ] Verify sentinel redesign: no `rm -f .workflows/.work-in-progress` in work.md: `grep -n 'rm.*work-in-progress' plugins/compound-workflows/commands/compound/work.md` should return empty

### Step 11: Sonnet appropriateness review

Review the modified command files for robustness when executed by Sonnet (or other weaker models) instead of Opus. This plan's changes introduce model-side tracking patterns that require the executing model to:
- Track a dispatch counter mentally and substitute literal numbers into bash commands
- Distinguish between `$PLUGIN_ROOT` (bash variable) and `<DISPATCH_COUNT>` (model-side placeholder)
- Use the `report` keyword explicitly for report-only validation

- [ ] Scan all 5 modified command files for model-side instructions. For each instruction that asks the model to track/substitute/compute:
  - Is the instruction explicit enough for Sonnet to follow?
  - Is there a silent failure mode if Sonnet misunderstands? (C3's warn-on-empty catches missing substitution, but are there other failure paths?)
  - Could the instruction be made more deterministic (e.g., pre-computed values, explicit examples)?
- [ ] Verify angle-bracket placeholders (`<DISPATCH_COUNT>`, `<EXPECTED_TOTAL>`) are used consistently — no remaining `$DISPATCH_COUNT` or `$EXPECTED_TOTAL` in replacement text
- [ ] Verify each validate-stats.sh call site either provides a literal/placeholder count or uses the `report` keyword — no ambiguous empty calls
- [ ] Note for implementers: unsubstituted angle-bracket placeholders (e.g., literal `<DISPATCH_COUNT>` in bash) produce `"No such file or directory"` errors from bash's `<` redirect parsing — recognize this as a placeholder substitution failure, not a missing file

## Work Execution Notes

**Parallel batching for `/compound:work`:**
- **Batch 1 (parallel):** Steps 1, 2, 3, 4, 5 — all modify different files. Step 6 (work.md) should be in this batch too but is the most complex; could be serialized if needed.
- **Batch 2:** Step 7 (7a discovery, 7b markers, 7c verification) — depends on Steps 2–6 complete
- **Batch 3:** Step 8 — depends on Step 7 (QA check must see markers)
- **Batch 4:** Step 9 — version bump after all edits
- **Batch 5:** Step 10 — full QA validation (Tier 1 + Tier 2)
- **Batch 6:** Step 11 — Sonnet appropriateness review (can run after Step 10, or in parallel if QA is clean)

**Step 6 complexity:** This step makes 3 types of changes to work.md (P5 fix, ENTRY_COUNT, sentinel). A single subagent handles all work.md edits to avoid merge conflicts. The sentinel redesign requires understanding both the code block changes AND the prose description changes.

## Edge Cases

- **Stale sentinel with "cleared" content + crash:** If a session crashes after writing "cleared" but before a new run writes an epoch, the file contains "cleared". The hook's numeric check (`grep -qE '^[0-9]+$'`) fails for "cleared" → falls through → QA runs normally. Correct behavior.
- **Concurrent runs:** Two `/compound:work` sessions in different terminals. First writes epoch, second writes epoch (overwrites). Both check the hook. Last writer wins. On clear, first writes "cleared", second still running. The hook sees "cleared" → QA runs on the first session's commits. Second session is unaffected (its sentinel was overwritten). **Concurrent runs were already unsupported** — the existing `rm` pattern has the same race condition. No regression.
- **Missing validate-stats.sh:** If the script doesn't exist when called (e.g., plugin not fully installed), `bash validate-stats.sh` fails. The model sees the error and continues (validation is diagnostic). Same degradation as today's ENTRY_COUNT pattern when the stats file doesn't exist.
- **Empty STATS_FILE:** validate-stats.sh handles this — `grep -c` on empty file returns 0, reports mismatch with expected count.
- **DISPATCH_COUNT variable not set:** The calling command must track DISPATCH_COUNT. This is already the convention — the prose says "Track DISPATCH_COUNT by incrementing a counter." If the variable is unset, bash expands it to empty string, and validate-stats.sh's `$2` parameter check fails with "missing expected-count". Existing behavior is the same — ENTRY_COUNT comparison with an unset EXPECTED fails too.

## Deferred Questions Resolved

**Q1 (from brainstorm): Scope of prose rewrite.**
Resolved: Each Step (2–6) specifies both the bash code block replacement AND the surrounding prose changes. The plan includes exact old/new text for both.

**Q2 (from brainstorm): QA check design.**
Resolved: Add to `context-lean-grep.sh` as Check 5 (not a new script). Suppress convention: `# heuristic-exempt` trailing comment on the bash line. Regex `\$\(` catches both `$()` and `$((...))` — empirically verified that arithmetic expansion IS a heuristic trigger.

## Red Team Resolution Summary

3-provider red team challenge (Gemini, OpenAI, Claude Opus). 4 CRITICAL, 7 SERIOUS, 9 MINOR findings across providers.

**CRITICAL resolved:**
- **C1 (Valid):** `set -euo pipefail` + `grep -c || echo 0` bug fixed in Step 1. [red-team--gemini, red-team--opus, see .workflows/plan-research/plugin-heuristic-audit/red-team--gemini.md]
- **C2 (Disagree):** Cross-session state loss — init blocks always run before recovery; re-hydration would add new $() prompts for zero benefit. [red-team--gemini, see .workflows/plan-research/plugin-heuristic-audit/red-team--gemini.md]
- **C3 (Valid):** Silent validation bypass — warn-on-empty + explicit `report` keyword for Sonnet robustness. User: "I want to make this robust for use with e.g. sonnet instead of opus." [red-team--openai, see .workflows/plan-research/plugin-heuristic-audit/red-team--openai.md]

**SERIOUS resolved:**
- **S1 (Disagree):** Script overengineered — brainstorm Decision 3 chose script extraction; Sonnet robustness justifies centralized guardrails. [red-team--gemini, see .workflows/plan-research/plugin-heuristic-audit/red-team--gemini.md]
- **S2 (Valid):** Step 10 updated to include Tier 2 semantic QA. [red-team--openai, see .workflows/plan-research/plugin-heuristic-audit/red-team--openai.md]
- **S3 (Valid):** $((...)) empirically verified as heuristic trigger. QA regex, constraint box, Step 7 notes, and Step 8 comments all updated. [red-team--opus, see .workflows/plan-research/plugin-heuristic-audit/red-team--opus.md]
- **S4 (Valid):** Step 7 split into 7a (discovery), 7b (markers), 7c (verification). [red-team--opus, see .workflows/plan-research/plugin-heuristic-audit/red-team--opus.md]
- **S5 (Valid):** Recovery block prompts added to Prompt Count Analysis table. [red-team--opus, see .workflows/plan-research/plugin-heuristic-audit/red-team--opus.md]
- **S6 (Valid):** Angle-bracket syntax for model-side placeholders — makes model-side vs bash distinction clear, causes loud bash error if not substituted. User chose this for Sonnet robustness. [red-team--gemini, red-team--openai, see .workflows/plan-research/plugin-heuristic-audit/red-team--gemini.md]
- **S7 (Valid):** Automated discovery step (7a) added before marker placement. [red-team--opus, see .workflows/plan-research/plugin-heuristic-audit/red-team--opus.md]

**User-initiated additions:**
- **Step 11 (Sonnet appropriateness review):** User requested analysis of command file templates for weaker-model robustness.
- **Specflow re-run:** Re-running specflow analysis after red team edits to verify flow completeness.

**MINOR triage:**
- **Fixed (batch):** Items 1-2 subsumed by S3 (regex and comment corrections).
- **Acknowledged (batch):** 7 MINOR findings — #3 disagree (scan-all consistent with convention), #4 addressed by C3+S6, #5 keep validation (stricter), #6-9 no action needed. [see .workflows/plan-research/plugin-heuristic-audit/minor-triage-redteam.md]

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-03-10-plugin-heuristic-audit-brainstorm.md` — 9 key decisions, patterns catalogue (P1–P13), red team findings (OpenAI + Opus)
- **Static rules finding:** `docs/solutions/claude-code-internals/2026-03-10-static-rules-suppress-bash-heuristics.md` — evaluation order, fragility assessment
- **QA script patterns:** `docs/solutions/qa-infrastructure/2026-03-08-bash-qa-script-patterns.md` — process substitution, batch-then-filter, self-referential detection
- **Research:** `.workflows/plan-research/plugin-heuristic-audit/agents/` — repo research, learnings, specflow analysis
- **Red team:** `.workflows/plan-research/plugin-heuristic-audit/red-team--{gemini,openai,opus}.md` — 3-provider challenge
- **MINOR triage:** `.workflows/plan-research/plugin-heuristic-audit/minor-triage-redteam.md` — categorization
