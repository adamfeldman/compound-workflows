---
topic: usage-pipe-isolation
date: 2026-03-12
status: complete
bead: 8one
---

# Usage-Pipe Isolation: Eliminate the Pipe File

## What We're Building

Replace the `.workflows/.usage-pipe` intermediary file pattern with a named-field string argument to `capture-stats.sh`. The model extracts values from `<usage>` notifications and formats them as a colon-delimited named-field string (e.g., `"total_tokens: N, tool_uses: N, duration_ms: N"`) — the script still does deterministic field extraction by name. Also scope `.work-in-progress` sentinel per-session to prevent concurrent workflow hook interference.

## Why This Approach

The `.usage-pipe` file was introduced in v3.0.4 to keep `<usage>` XML angle brackets out of Bash tool commands (avoiding Claude Code's redirection heuristic). It created two problems:

1. **Race condition**: `.usage-pipe` is a shared static file. Concurrent sessions overwrite each other's data, causing cross-contaminated stats. Stale data from prior sessions persists in the file (observed during this brainstorm session). Concurrent cross-contamination is architecturally inevitable though not yet documented as having occurred.
2. **UI noise**: Every stats capture requires a Write tool call that shows a diff in the Claude Code UI — noisy and distracting (a typical brainstorm run has ~4 research agents + 3 red team agents = ~14 extra Write+Bash tool calls just for stats capture; do-work with 5-10 dispatches adds 10-20).

The fix eliminates the `.usage-pipe` intermediary file entirely. The model extracts values and formats them as a colon-delimited named-field string (no angle brackets), and the script extracts values deterministically by field name — preserving the project's Command Robustness Principle #3 (deterministic verification over LLM judgment). No file means no race condition and no UI noise.

## Key Decisions

### 1. Named-field string as positional arg 9 (not CSV, not three separate args)
**Why**: Red team (all 3 providers) flagged CSV as violating Command Robustness Principle #3 — CSV moves number extraction from deterministic bash to LLM judgment. Named-field string `"total_tokens: 57504, tool_uses: 33, duration_ms: 240342"` lets the script parse by field name (transposition impossible). The model extracts the three values and formats as colon-delimited string (not "strip tags" — inner XML may still contain angle brackets). 9 total args.

### 2. Pure elimination, no stdin fallback — single-commit constraint
**Why**: Plugin versions are atomic — when the user updates, all skills and scripts update together. No mixed-version scenario for installed plugins. During development, all 11 files must change in one commit; QA catches mismatches. Rollback: `git revert <commit>`.

### 3. Model passes "null" as arg 9 when `<usage>` is absent
**Why**: Red team (all 3 providers) flagged skip-call as contradicting `validate-stats.sh` — can't distinguish "no data" from "model forgot." Passing `"null"` preserves the entry count and writes `status: failure`, maintaining diagnostic signal.

### 4. Guard fix is superseded
**Why**: The guard (line 66 in capture-stats.sh) checked for `<usage>` wrapper in stdin input. With stdin parsing removed, the guard is gone. The original issue (bare `<total_tokens>` elements without `<usage>` wrapper being rejected) ceases to exist.

### 5. Timeout variant unchanged
**Why**: The `--timeout` variant (8 args, no usage data) is already clean — no stdin, no pipe. No changes needed.

### 6. `.work-in-progress` scoped per-session via directory of sentinels
**Why**: Same class of bug as `.usage-pipe` — shared static sentinel file. One session clearing it removes hook suppression for other concurrent sessions. Fix: replace single file with `.workflows/.work-in-progress.d/` directory containing per-RUN_ID sentinel files. Hook iterates directory and suppresses if ANY file has a recent timestamp. Each session only clears its own file (`rm -f`). Stale sentinels from crashed sessions auto-expire via the existing 4-hour timeout.

## Scope of Changes

| File | Change |
|------|--------|
| `scripts/capture-stats.sh` | Remove stdin reading. Add named-field string arg 9 parsing (reuse existing `[>:]` regex). Handle `"null"` arg for absent usage. |
| `scripts/plugin-qa/capture-stats-format.sh` | Update QA tests: replace stdin pipe tests with arg 9 tests. |
| `skills/do-brainstorm/SKILL.md` | Replace Write+cat-pipe pattern with direct named-field string arg call. Remove `.usage-pipe` references. |
| `skills/do-plan/SKILL.md` | Same replacement — note: do-plan uses inline prose references, not code-fenced bash examples. Replacement technique differs from other skills. |
| `skills/do-deepen-plan/SKILL.md` | Same replacement across all capture-stats invocations. |
| `skills/do-review/SKILL.md` | Same replacement across all capture-stats invocations. |
| `skills/do-work/SKILL.md` | Same replacement across all capture-stats invocations. |
| `resources/stats-capture-schema.md` | Update caller pattern documentation. Remove `.usage-pipe` references. |
| `scripts/plugin-qa/unslugged-paths.sh` | Remove `.usage-pipe*` exemption. Update `.work-in-progress*` exemption for directory pattern. |
| `scripts/check-sentinel.sh` | Update to scan `.work-in-progress.d/` directory instead of single file. |
| `.claude/hooks/plugin-qa-check.sh` | Update `check_sentinel()` to iterate directory of per-RUN_ID sentinels. |
| `skills/do-work/SKILL.md` | Replace single-file sentinel with `mkdir -p .work-in-progress.d && date +%s > .work-in-progress.d/$RUN_ID`. Update clear to `rm -f`. |
| `CHANGELOG.md` | Document the change. |
| `plugin.json` + `marketplace.json` | Version bump. |

## New Calling Convention

```bash
# Standard call — model strips <usage> tags, passes inner content:
bash $PLUGIN_ROOT/scripts/capture-stats.sh "$STATS_FILE" "brainstorm" "agent" "step" "model" "stem" "null" "$RUN_ID" "total_tokens: 57504, tool_uses: 33, duration_ms: 240342"

# No usage data — model passes "null":
bash $PLUGIN_ROOT/scripts/capture-stats.sh "$STATS_FILE" "brainstorm" "agent" "step" "model" "stem" "null" "$RUN_ID" "null"

# Timeout call — unchanged:
bash $PLUGIN_ROOT/scripts/capture-stats.sh --timeout "$STATS_FILE" "brainstorm" "agent" "step" "model" "stem" "null" "$RUN_ID"
```

## What Gets Removed

- `.workflows/.usage-pipe` file and all references to it
- stdin reading in capture-stats.sh (`USAGE_LINE="$(cat)"` and all parsing logic)
- Write tool calls for usage data in all 5 skill files
- `unslugged-paths.sh` exemption for `.usage-pipe*`

## Alternatives Considered

- **Fix the pipe (subdirectory + per-RUN_ID + cleanup)**: `.workflows/.usage-pipes/$RUN_ID` with `rm` after read. Solves the race but Write tool UI noise remains. Adds directory creation and cleanup logic.
- **Hybrid (--values flag + stdin fallback)**: New `--values` flag for clean path, stdin for cached old versions. Adds code for zero practical benefit — plugin versions update atomically.
- **Three separate positional args (9-11)**: 11 total args. Higher positional error risk. CSV reduced to 9 args; named-field string eliminated ordering risk entirely.
- **CSV as arg 9**: Chosen initially, then replaced by named-field string after red team flagged it violates Deterministic Verification principle (Command Robustness Principle #3). CSV moves extraction from deterministic bash to LLM judgment.

## Open Questions

- ~~**`.work-in-progress` scoping**~~: Resolved — directory of per-RUN_ID sentinels in `.work-in-progress.d/`.
- ~~**do-plan prose pattern**~~: Resolved — verified do-plan uses inline prose but the replacement is equally mechanical. New prose: "extract total_tokens, tool_uses, and duration_ms values from the `<usage>` notification and pass as named-field string arg: `"total_tokens: N, tool_uses: N, duration_ms: N"`. If `<usage>` is absent, pass `"null"`." Must explicitly say to format as colon-delimited string — NOT "strip XML tags" (inner content may still contain angle brackets in XML sub-element format).

## Red Team Resolution Summary

**Fixed (batch):** 3 MINOR fixes applied (open questions section, do-plan scope note, UI noise quantification).

| # | Finding | Severity | Provider(s) | Resolution |
|---|---------|----------|-------------|------------|
| 1 | CSV violates Deterministic Verification principle | CRITICAL | All 3 | **Valid — updated.** Switched to named-field string. Script parses by field name. |
| 2 | Skip-call contradicts validate-stats | CRITICAL | All 3 | **Valid — updated.** Model passes `"null"` instead of skipping. |
| 3 | "Atomic update" ignores dev transition | SERIOUS | All 3 | **Valid — updated.** Document single-commit constraint. |
| 4 | Race condition overclaim | SERIOUS | OpenAI, Opus | **Valid — updated.** Narrowed claim; expanded to `.work-in-progress`. |
| 5 | No rollback plan | SERIOUS | Opus | **Valid — updated.** Added: git revert is the rollback. |
| 6 | "Open Questions: None" premature | MINOR | OpenAI, Opus | **Fixed.** Added open questions. |
| 7 | do-plan scope table misleading | MINOR | Opus | **Fixed.** Added prose-pattern note. |
| 8 | UI noise undersold | MINOR | Opus | **Fixed.** Added quantification. |
| 9 | Missing alternatives table | MINOR | OpenAI | **Valid — added** Alternatives Considered section. |
| 10 | Race condition evidence unsubstantiated | MINOR | Opus | **Valid — updated.** Softened to "architecturally inevitable, not yet documented." |
| 11 | CSV ordering still positional | MINOR | Gemini | **No action.** Mooted by named-field string decision. |
| 12 | "Hyper-specific fragile workaround" | MINOR | Gemini | **No action.** Mooted by named-field string decision. |

## Resolved Questions

1. **Should we fix the pipe or eliminate it?** → Eliminate. Simpler architecture, solves race condition AND UI noise in one change.
2. **Backwards compatibility with cached old versions?** → Not needed for installed plugins. During development: single-commit constraint.
3. **Will `--values` flag trigger heuristics?** → Moot — using named-field string as arg 9. No angle brackets in the string.
4. **Can the model handle 11 positional args?** → Avoided by using single arg 9 with named fields (9 total).
5. **Guard fix for bare XML elements?** → Superseded. Stdin parsing removed entirely.
6. **CSV vs named-field string?** → Named-field string. Red team flagged CSV as violating Deterministic Verification principle. Named fields let the script extract by name, not position.
7. **What when `<usage>` is absent?** → Model passes `"null"` as arg 9. Script writes `status: failure`. Preserves entry count for validate-stats.
8. **`.work-in-progress` scoping?** → Directory of per-RUN_ID sentinels in `.workflows/.work-in-progress.d/`. Hook iterates all files, suppresses if any active. Each session clears its own via `rm -f`. Stale files auto-expire (4h timeout).
