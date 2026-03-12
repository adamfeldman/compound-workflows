---
title: "fix: Eliminate usage-pipe race + scope work-in-progress per-session"
type: fix
status: active
date: 2026-03-12
bead: 8one
origin: docs/brainstorms/2026-03-12-usage-pipe-isolation-brainstorm.md
---

# Eliminate Usage-Pipe Race + Scope Work-In-Progress Per-Session

## Summary

Two shared static files in `.workflows/` have race conditions under concurrent sessions:

1. **`.usage-pipe`** — single shared file used by all 5 workflow skills for stats capture. Concurrent sessions overwrite each other's data. Also produces noisy Write tool diffs in the UI (~14 extra tool calls per brainstorm, ~20 per do-work). **Fix:** eliminate the file entirely. The model extracts values from `<usage>` notifications and passes them as a named-field string arg 9 to `capture-stats.sh`.

2. **`.work-in-progress`** — single shared sentinel file. One session clearing it removes QA hook suppression for other concurrent sessions. **Fix:** replace single file with `.workflows/.work-in-progress.d/$RUN_ID` directory of per-session sentinels. Hook iterates directory, suppresses if ANY file is active.

All changes ship in one atomic commit (see brainstorm: Decision 2 — plugin versions update atomically, no mixed-version scenario for installed plugins).

## Acceptance Criteria

- [ ] `capture-stats.sh` accepts named-field string as arg 9 (no stdin reading)
- [ ] `capture-stats.sh` handles `"null"` arg 9 with `status: failure`
- [ ] `capture-stats.sh` `<usage>` guard (line 66 block) fully removed — not commented out, not dead code
- [ ] Timeout variant (`--timeout`, 8 args) unchanged and passing
- [ ] `capture-stats-format.sh` QA tests rewritten for arg 9 interface (6 test cases)
- [ ] All 5 skill files use direct `bash capture-stats.sh ... "named-field-string"` — no Write tool, no `.usage-pipe`
- [ ] `do-plan/SKILL.md` prose-style capture instructions updated (not code-fenced)
- [ ] `do-work/SKILL.md` sentinel creation uses `.work-in-progress.d/$RUN_ID`
- [ ] `do-work/SKILL.md` sentinel clearing uses `rm -f` (not Write tool)
- [ ] `check-sentinel.sh` scans `.work-in-progress.d/` directory
- [ ] `plugin-qa-check.sh` hook iterates directory of sentinels (both CWD and git-root)
- [ ] `unslugged-paths.sh` removes `.usage-pipe*` exemption, updates `.work-in-progress*` for directory pattern
- [ ] `stats-capture-schema.md` documents new arg 9 calling convention
- [ ] No `$()` in any new Bash tool command strings across all 5 skill files
- [ ] No angle brackets in arg 9 — skill file instructions must say "extract numeric VALUES", not "pass inner content" [red-team--gemini, red-team--opus]
- [ ] No `.usage-pipe` references remain anywhere in the plugin
- [ ] Version bumped in `plugin.json` + `marketplace.json`
- [ ] CHANGELOG documents user benefit
- [ ] All Tier 1 QA scripts pass with zero findings
- [ ] All Tier 2 semantic agents pass with zero findings

## Implementation

### Phase 1: capture-stats.sh — Remove stdin, add arg 9

**File:** `plugins/compound-workflows/scripts/capture-stats.sh`

The script currently reads usage data via stdin (`USAGE_LINE="$(cat)"` at line 55). Replace with positional arg 9.

- [ ] **1.1** Add arg 9 to the standard variant's parameter block (after `RUN_ID`):
  ```bash
  USAGE_DATA="${9:-null}"
  ```
  Default to `"null"` if arg 9 is missing — preserves fire-and-forget invariant (script always exits 0, always writes an entry). If model forgets arg 9, we get `status: failure` instead of a missing entry. Remove `USAGE_LINE="$(cat)"` (line 55). [red-team--opus: Finding 1, resolved]

- [ ] **1.2** Replace the entire 3-stage guard block (lines 64-97) — including the `<usage>` presence check (line 66), the health check (lines 72-76), and all extraction logic — with named-field parsing. The old block has three branches: empty/null, no-`<usage>`-tag, has-`<usage>`. ALL three are replaced by a single `"null"` check + field extraction:
  ```bash
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
  ```

  **Critical:** The old guard checked for `<usage>` wrapper (line 66) and the health check (lines 72-76) verified `<usage>.*total_tokens`. Under named-field string input, valid data never contains `<usage>`, so both checks would silently misclassify all valid entries as failures or emit spurious warnings. The entire lines 64-97 block must be **fully removed and replaced**, not preserved as dead code (see brainstorm: Decision 4; specflow: Q4).

- [ ] **1.3** Update the script header comment to reflect the new interface:
  ```bash
  # Usage:
  #   bash capture-stats.sh <stats-file> <command> <agent> <step> <model> <stem> <bead> <run_id> <usage-data>
  #   bash capture-stats.sh --timeout <stats-file> <command> <agent> <step> <model> <stem> <bead> <run_id>
  #
  # <usage-data>: Named-field string "total_tokens: N, tool_uses: N, duration_ms: N" or "null"
  ```

- [ ] **1.4** Timeout variant (lines 14-44) — **no changes needed**. Already takes 8 args with no stdin (see brainstorm: Decision 5).

### Phase 2: check-sentinel.sh — Directory scanning

**File:** `plugins/compound-workflows/scripts/check-sentinel.sh`

Replace single-file check with directory iteration.

- [ ] **2.0** Verify only 2 consumers of check-sentinel.sh exist: `grep -r 'check-sentinel' plugins/compound-workflows/ .claude/hooks/`. Expected: `do-work/SKILL.md` (recovery) and `plugin-qa-check.sh` (hook). If other consumers exist, update them too. [red-team--opus: Finding 5, resolved]

- [ ] **2.1** Change default sentinel path from single file to directory:
  ```bash
  SENTINEL_DIR="${1:-.workflows/.work-in-progress.d}"
  ```

- [ ] **2.2** Replace single-file logic with directory scan:
  - If directory doesn't exist → `NOT_FOUND`
  - If directory is empty (no files) → `NOT_FOUND`
  - For each file in the directory:
    - Read content; skip if non-numeric (cleared/corrupt)
    - Compute age from timestamp content
    - If age < 14400 seconds → `ACTIVE` (exit immediately — any active file suppresses)
  - If all files are stale → `STALE:<count>` (count = number of stale files; the hook doesn't need hours, just the signal)
  - `CLEARED` state is eliminated — under the directory scheme, files are removed (`rm -f`), not neutralized. A directory with only non-numeric files is treated as `NOT_FOUND`.

- [ ] **2.3** Update the script header comment:
  ```bash
  # Usage: bash check-sentinel.sh [sentinel-dir]
  # Default sentinel dir: .workflows/.work-in-progress.d (relative to cwd)
  #
  # Output (one line to stdout):
  #   NOT_FOUND  — directory does not exist, is empty, or contains only non-numeric files
  #   ACTIVE     — at least one sentinel is fresh (< 4 hours)
  #   STALE:<N>  — all sentinels are stale, N = count of stale files
  #
  # Exit codes: 0 = always (informational output, never blocks callers)
  ```

### Phase 3: plugin-qa-check.sh hook — Directory iteration

**File:** `.claude/hooks/plugin-qa-check.sh`

**Constraint:** This is a protected path — changes must be made by the orchestrator, not dispatched to a subagent (see learnings: Bash QA Script Patterns, point 4).

- [ ] **3.1** Remove the inline `check_sentinel()` function (lines 34-47) entirely. Replace with a call to `check-sentinel.sh` as a shared helper — single source of truth, eliminates the duplication invariant. The hook already resolves `$plugin_root` for QA scripts; use the same path resolution for check-sentinel.sh:
  ```bash
  check_script="$plugin_root/../scripts/check-sentinel.sh"
  ```

- [ ] **3.2** Replace the call sites (lines 50-54) with:
  ```bash
  # Check sentinel directory (suppress during /do:work)
  if [ -f "$check_script" ]; then
    result="$(bash "$check_script" ".workflows/.work-in-progress.d")"
    if [ "$result" = "ACTIVE" ]; then
      exit 0
    fi
    git_root="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
    if [ -n "$git_root" ] && [ "$git_root" != "$(pwd)" ]; then
      result="$(bash "$check_script" "$git_root/.workflows/.work-in-progress.d")"
      if [ "$result" = "ACTIVE" ]; then
        exit 0
      fi
    fi
  fi
  ```
  [red-team--openai: Finding 6 (duplication), resolved — shared helper eliminates sync risk]

- [ ] **3.3** Remove old `.work-in-progress` single file if it exists — one-time migration cleanup:
  ```bash
  rm -f .workflows/.work-in-progress
  ```
  Add this to the sentinel check block (runs on every commit, `rm -f` is idempotent and fast). After the first commit post-update, the old file is gone. [red-team--opus: Finding 6, resolved]

### Phase 4: QA test updates

#### 4a. capture-stats-format.sh — Arg 9 tests

**File:** `plugins/compound-workflows/scripts/plugin-qa/capture-stats-format.sh`

Replace all 6 stdin-pipe tests with arg 9 invocations. Same test structure (TMPDIR, assertions), only the invocation pattern changes.

- [ ] **4a.1** Test 1 (comma-separated): Replace `echo "$USAGE_COMMA" | bash "$CAPTURE_SCRIPT" ... 8args` with:
  ```bash
  bash "$CAPTURE_SCRIPT" "$STATS_FILE" "plan" "test-agent" "1.1" "opus" "test" "none" "test-run" \
    "total_tokens: 40488, tool_uses: 16, duration_ms: 55379"
  ```
  Same assertions (grep for tokens/tools/duration values).

- [ ] **4a.2** Test 2 (empty string arg 9): Test that an empty string arg defaults gracefully (since `${9:-null}` converts to `"null"`). Pass empty string explicitly:
  ```bash
  bash "$CAPTURE_SCRIPT" "$STATS_FILE" "brainstorm" "test-agent" "2.1" "sonnet" "test" "none" "test-run" ""
  ```
  Assert: `status: failure`, all token fields null. (Replaces old newline-format test — the model always normalizes to comma format, so a second happy-path test was redundant.) [red-team--opus: Finding 3, resolved]

- [ ] **4a.3** Test 3 (null/absent usage): Replace `echo "" | ...` with:
  ```bash
  bash "$CAPTURE_SCRIPT" "$STATS_FILE" "work" "test-agent" "3.1" "opus" "test" "none" "test-run" "null"
  ```
  Assert `status: failure`.

- [ ] **4a.4** Test 4 (partial field extraction edge case): Under the new convention, the model always emits all 3 fields. But test defense-in-depth: what if only 1-2 fields are present? Verify the script extracts what's available and nulls the rest:
  ```bash
  bash "$CAPTURE_SCRIPT" "$STATS_FILE" "review" "test-agent" "4.1" "opus" "test" "none" "test-run" \
    "total_tokens: 8500"
  ```
  Assert: `tokens: 8500`, `tools: null`, `duration_ms: null`, `status: failure` (partial extraction = failure, all 3 fields required for success). This replaces the old XML-format test — XML inner content never reaches the script under the new scheme. [red-team--openai: partial metrics, resolved]

- [ ] **4a.5** Test 5 (timeout variant): **No changes** — already uses `--timeout` with 8 args, no stdin.

- [ ] **4a.6** Test 6 (malformed content): Test arg 9 with unexpected content that has no parseable fields:
  ```bash
  bash "$CAPTURE_SCRIPT" "$STATS_FILE" "work" "test-agent" "6.1" "opus" "test" "none" "test-run" \
    "some random garbage with no fields"
  ```
  Assert: `status: failure`, all token fields null. Remove old stderr checks for `no <usage> data in response` message (that stderr path no longer exists). (Replaces old test 6 which was identical to test 3 — both passed `"null"`.) [red-team--opus: Finding 3, resolved]

- [ ] **4a.7** Update script header comment to describe the new test cases (arg 9 instead of stdin pipe).

- [ ] **4a.8** Remove stderr checks for `format may have changed` warnings from Tests 1, 2, 4 — the health check that emitted those warnings is gone (it checked for `<usage>` wrapper which no longer exists).

#### 4b. unslugged-paths.sh — Exemption updates

**File:** `plugins/compound-workflows/scripts/plugin-qa/unslugged-paths.sh`

- [ ] **4b.1** Remove `.usage-pipe*` from the exemption list (line 84). The file is eliminated — no exemption needed.

- [ ] **4b.2** Update `.work-in-progress*` to `.work-in-progress.d/*` in the exemption:
  ```bash
  case "$workflows_path" in
    .workflows/.work-in-progress.d/*|.workflows/scratch/*) continue ;;
  esac
  ```

- [ ] **4b.3** Update the comment on line 11 to reflect the directory pattern:
  ```bash
  #   - .workflows/.work-in-progress.d/ (sentinel directory, per-session files intentionally overwrite)
  ```

### Phase 5: Skill file updates — Replace Write+cat-pipe with arg 9

All 5 skill files follow the same replacement pattern. The model reads the `<usage>` notification, extracts the three numeric values, and formats as `"total_tokens: N, tool_uses: N, duration_ms: N"`. If `<usage>` is absent, passes `"null"`.

**New calling convention (code-fenced skills):**
```bash
bash $PLUGIN_ROOT/scripts/capture-stats.sh "$STATS_FILE" "<command>" "<agent>" "<step>" "<model>" "<stem>" "<bead>" "$RUN_ID" "total_tokens: N, tool_uses: N, duration_ms: N"
```

**New calling convention (no-usage case):**
```bash
bash $PLUGIN_ROOT/scripts/capture-stats.sh "$STATS_FILE" "<command>" "<agent>" "<step>" "<model>" "<stem>" "<bead>" "$RUN_ID" "null"
```

For each skill file: find every occurrence of the Write+cat-pipe pattern ("save it to `.workflows/.usage-pipe` using the Write tool, then run `cat .workflows/.usage-pipe | bash ...`") and replace with the new direct invocation.

#### 5a. do-brainstorm/SKILL.md

- [ ] **5a.1** Replace 6 capture-stats call sites (2 research, 3 red team, 1 triage). Each currently says: "extract the `<usage>...</usage>` line, save it to `.workflows/.usage-pipe` using the Write tool, then call `capture-stats.sh`". Replace with: "extract `total_tokens`, `tool_uses`, and `duration_ms` values from the `<usage>` notification and pass as arg 9: `bash $PLUGIN_ROOT/scripts/capture-stats.sh ... "total_tokens: N, tool_uses: N, duration_ms: N"`. If `<usage>` is absent, pass `"null"` as arg 9."

- [ ] **5a.2** Remove the generic Stats Capture instruction paragraph that mentions `.usage-pipe` (near line 80).

- [ ] **5a.3** Update code-fenced `cat .workflows/.usage-pipe | bash ...` examples to `bash ... "total_tokens: N, tool_uses: N, duration_ms: N"`.

#### 5b. do-plan/SKILL.md

**Important:** do-plan uses **inline prose** for capture-stats instructions, not code-fenced bash blocks (see brainstorm: Open Questions, resolved). The replacement technique differs from other skills.

- [ ] **5b.1** Replace the generic Stats Capture section (near line 111) with:
  > If stats_capture ≠ false in compound-workflows.local.md: after each Task/Agent completion, extract `total_tokens`, `tool_uses`, and `duration_ms` values from the `<usage>` notification and format as a named-field string `"total_tokens: N, tool_uses: N, duration_ms: N"`. Pass this as the 9th argument to capture-stats.sh. If `<usage>` is absent, pass `"null"` as the 9th argument. Run: `bash $PLUGIN_ROOT/scripts/capture-stats.sh "$STATS_FILE" plan <agent> <step> <model> <stem> null $RUN_ID "<usage-string-or-null>"`. See `$PLUGIN_ROOT/resources/stats-capture-schema.md` for field derivation rules. Increment the dispatch counter for each capture call.

- [ ] **5b.2** Replace all inline prose references to Write+cat-pipe throughout the file. Search for `.usage-pipe` and `cat .workflows/.usage-pipe` to locate all call sites. Each instance currently reads: "extract `<usage>`, save it to `.workflows/.usage-pipe` using the Write tool, then run `cat .workflows/.usage-pipe | bash capture-stats.sh ...`". Replace with: "extract `total_tokens`, `tool_uses`, and `duration_ms` values from the `<usage>` notification and run `bash ... "total_tokens: N, tool_uses: N, duration_ms: N"`. If `<usage>` is absent, pass `"null"`." Verify zero `.usage-pipe` references remain in the file after all replacements.

- [ ] **5b.3** Remove the `cat .workflows/.usage-pipe |` prefix from any code-fenced bash examples that appear within the prose.

#### 5c. do-deepen-plan/SKILL.md

- [ ] **5c.1** Replace the generic Stats Capture section (near line 64) with the same arg 9 instruction pattern.

- [ ] **5c.2** Replace all capture-stats call sites. Search for `.usage-pipe` and `cat .workflows/.usage-pipe` to locate all call sites. Each currently says "save it to `.workflows/.usage-pipe` using the Write tool". Remove all Write tool references and replace with arg 9 pattern. Verify zero `.usage-pipe` references remain in the file after all replacements.

- [ ] **5c.3** Update all code-fenced `cat .workflows/.usage-pipe | bash ...` examples to `bash ... "total_tokens: N, tool_uses: N, duration_ms: N"`.

#### 5d. do-review/SKILL.md

- [ ] **5d.1** Replace the generic Stats Capture instruction (near line 109) and the 2 capture-stats patterns (per-agent loop + timeout variant).

- [ ] **5d.2** Update code-fenced examples to the new arg 9 format.

#### 5e. do-work/SKILL.md

- [ ] **5e.0** Pre-edit verification: confirm the worktree prose workaround (removed in v3.1.2) is NOT present in `do-work/SKILL.md`. Search for "cd back to repo root" or similar worktree-related prose. If found, do not proceed — report to orchestrator. [red-team--opus: Finding 9, resolved]

- [ ] **5e.1** Replace all capture-stats Write+cat-pipe patterns with arg 9 format (3 call sites: main dispatch loop, optional reviewer, Phase 3 reviewer).

- [ ] **5e.2** Update sentinel creation (Phase 1.2.1, line ~140):
  ```bash
  mkdir -p .workflows/.work-in-progress.d
  date +%s > .workflows/.work-in-progress.d/$RUN_ID
  ```
  Update the prose explanation: "This sentinel directory is checked by `.claude/hooks/plugin-qa-check.sh`. Each session creates its own sentinel file using `$RUN_ID`. It is cleared via `rm -f` in Phase 4 (Ship) and cleaned up if stale in Phase 2.4 (Recovery). The hook iterates all files in the directory — QA is suppressed if ANY file has a recent timestamp."

- [ ] **5e.3** Update sentinel clearing (Phase 4.2, line ~418):
  Replace: "Use the **Write tool** to write `cleared` to `.workflows/.work-in-progress`"
  With: "Clear the QA hook sentinel: `rm -f .workflows/.work-in-progress.d/$RUN_ID`"
  Note: `rm -f` is simpler than the Write tool approach. The old Write-to-neutralize pattern was needed because the single file was shared and couldn't be deleted. With per-session files, deletion is correct — it only affects this session.

- [ ] **5e.4** Update recovery check (Phase 2.4, line ~343):
  Replace: "bash check-sentinel.sh" with "bash check-sentinel.sh .workflows/.work-in-progress.d"
  Update the prose: if output is `STALE:<N>`, remove stale sentinel files using age-based deletion: `find .workflows/.work-in-progress.d -type f -mmin +240 -delete`. This avoids a TOCTOU race where `rm -f *` could delete a newly-created active sentinel from a concurrent session that started between the check and the delete. `find -mmin +240` checks each file's age at deletion time, so only genuinely stale files (> 4h) are removed. Rationale: after compaction, the model may not have the original `$RUN_ID` in context (`init-values.sh` generates a new RUN_ID each invocation — it cannot recover the old one). Since stale files are by definition from crashed/abandoned sessions (> 4 hours old), clearing them is safe. Active files (< 4h) from other concurrent sessions are never touched. [red-team--gemini, red-team--openai, red-team--opus: TOCTOU race, resolved]

- [ ] **5e.5** Update any prose that references the sentinel file pattern. Search for `.work-in-progress` and update each reference to reflect the directory pattern.

### Phase 6: Documentation

#### 6a. stats-capture-schema.md

**File:** `plugins/compound-workflows/resources/stats-capture-schema.md`

- [ ] **6a.1** Replace "How to Call capture-stats.sh" section (lines 64-101). New standard call:
  ```bash
  bash $PLUGIN_ROOT/scripts/capture-stats.sh \
    "<stats-file>" "<command>" "<agent>" "<step>" "<model>" "<stem>" "<bead>" "$RUN_ID" "<usage-data>"
  ```
  Where `<usage-data>` is `"total_tokens: N, tool_uses: N, duration_ms: N"` or `"null"`.

- [ ] **6a.2** Remove the `.usage-pipe` explanation paragraph ("Extract the full `<usage>...</usage>` line... and save it to `.workflows/.usage-pipe`...").

- [ ] **6a.3** Update the "Failure Handling" subsection: replace `echo "" | bash capture-stats.sh ...` with `bash capture-stats.sh ... "null"`.

- [ ] **6a.4** Add a note to "Where to Find `<usage>`" section: "The model extracts `total_tokens`, `tool_uses`, and `duration_ms` values from the `<usage>` notification and formats them as a named-field string. The model does NOT pass raw `<usage>` XML to the script — it extracts numeric values and formats as `"total_tokens: N, tool_uses: N, duration_ms: N"`. This keeps angle brackets out of Bash tool commands."

#### 6b. CHANGELOG.md

- [ ] **6b.1** Add entry under new version. Lead with user benefit:
  > **Fixed:** Stats capture no longer uses a shared pipe file — eliminates race conditions under concurrent sessions and removes noisy Write tool diffs from the UI. Work-in-progress sentinel is now scoped per-session, so concurrent `/do:work` runs don't interfere with each other's QA hook suppression.

### Phase 7: Version bump + commit

- [ ] **7.1** Bump version in `plugins/compound-workflows/.claude-plugin/plugin.json` (PATCH — bug fix)
- [ ] **7.2** Bump version in `.claude-plugin/marketplace.json` (same version)
- [ ] **7.3** Verify README.md component counts are unchanged (no new agents/skills/commands)
- [ ] **7.4** Run full QA — both tiers are mandatory per AGENTS.md:
  - **Tier 1**: `bash plugins/compound-workflows/scripts/plugin-qa/<script>.sh plugins/compound-workflows` for all 9 scripts. All must pass with zero findings.
  - **Tier 2**: Run `/compound-workflows:plugin-changes-qa` for the 3 semantic agents (context-lean reviewer, role description reviewer, command completeness reviewer). All must return zero findings.
  [red-team--openai: QA gate incomplete, resolved]
- [ ] **7.5** Stage all 13+ changed files and commit atomically

## Invariants

- **Orchestrator runs from repo root**: Sentinel creation/clearing always happens from the orchestrator's CWD, which is the main repo root — never from a worktree. The relative path `.workflows/.work-in-progress.d/` is correct for the orchestrator. The hook independently checks both CWD and `$git_root` for worktree support. (see specflow: Gap 1)
- **Single sentinel-checking implementation**: The hook calls `check-sentinel.sh` directly (shared helper) instead of duplicating the logic inline. This eliminates the sync risk identified in specflow Gap 4 and red-team--openai Finding 6. Changes to sentinel logic only need to happen in one place.

## Constraints

- **Single-commit constraint**: All files must change in one commit. Plugin versions update atomically — no mixed-version scenario for installed plugins. During development, QA catches mismatches. Rollback: `git revert <commit>`. (see brainstorm: Decision 2)
- **No `$()` in Bash tool commands**: The new calling convention uses `bash capture-stats.sh ... "named-field-string"` — no shell substitution in the Bash tool input. All 5 skill files must be verified. (see learnings: Script-File Shell Substitution Bypass)
- **No heredoc patterns in skill files**: `<<` is a "hard" heuristic not suppressible by static rules. The new convention uses quoted string args only. (see learnings: Static Allow Rules)
- **`plugin-qa-check.sh` is a protected path**: Changes to `.claude/hooks/` must be made by the orchestrator, not dispatched to a subagent. Phase 3 cannot be delegated. (see learnings: Bash QA Script Patterns, point 4)
- **Guard removal is critical**: The `<usage>` guard on line 66 of capture-stats.sh must be fully removed. Under named-field string input, valid data never contains `<usage>` — preserving the guard would silently misclassify all valid entries as `status: failure`. (see brainstorm: Decision 4)

## Execution Notes for `/do:work`

- **Phase ordering**: Phases 1-3 (scripts + hook) must execute before Phase 5 (skill files) because skill files reference the script interface. Phase 4a (capture-stats-format.sh) MUST run after Phase 1 to self-validate the script changes. Phase 4b (unslugged-paths.sh) has no dependency on Phase 1 and may run in any order.
- **Phase 5 parallelism**: The 5 skill file updates (5a-5e) touch separate files with no dependencies — they can run in parallel as separate subagent dispatches.
- **Phase 3 is orchestrator-only**: `plugin-qa-check.sh` cannot be modified by a subagent (protected path). The orchestrator must make this edit directly.
- **Phase 5b requires extra care**: `do-plan/SKILL.md` uses inline prose for capture-stats instructions (not code-fenced). The replacement technique differs from other skills. Provide the exact replacement prose in the dispatch prompt.
- **Verify step**: After all phases complete, run `grep -r 'usage-pipe' plugins/compound-workflows/` to confirm zero remaining references.

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-03-12-usage-pipe-isolation-brainstorm.md` — key decisions: named-field string arg 9, pure elimination (no fallback), "null" for absent usage, guard removal, per-session sentinel directory, single-commit constraint
- **Repo research:** `.workflows/plan-research/fix-usage-pipe-isolation/agents/repo-research.md`
- **Learnings:** `.workflows/plan-research/fix-usage-pipe-isolation/agents/learnings.md` — protected path constraint, pipe-subshell variable loss in QA, heuristic-safe patterns
- **SpecFlow:** `.workflows/plan-research/fix-usage-pipe-isolation/agents/specflow.md`
