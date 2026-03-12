---
title: "Fix: capture-stats.sh reads usage line from stdin to avoid heuristic prompt"
type: fix
status: completed
date: 2026-03-12
bead: zwjg
---

# Fix: capture-stats.sh reads usage line from stdin

## Problem

`capture-stats.sh` takes the `<usage>` line as its 9th positional argument. The XML-style angle brackets (`<total_tokens>`, `</total_tokens>`, etc.) trigger Claude Code's shell redirection heuristic, causing a permission prompt every time stats are captured — even with `Bash(bash:*)` in static rules (angle brackets may be a "hard" heuristic like `<<` heredoc).

## Existing Pattern

`append-snapshot.sh` already solves the same class of problem: it hides heredoc content inside the script file so the heuristic inspector never sees it. The pattern: move content with heuristic-triggering characters out of the Bash tool command and into the script's internal processing.

## Solution

Read the usage line from **stdin** instead of positional arg 9. The script change is minimal. The caller pattern in skill files changes from a single bash call with inline arg to a two-step approach: Write tool saves the usage line to a temp file, then `cat` pipes it to capture-stats.sh.

### Why two-step (Write + cat-pipe) instead of inline echo

`echo '<usage>...' | bash capture-stats.sh` still places `<` characters in the Bash tool command — the heuristic would still fire. The two-step approach keeps all angle brackets out of any Bash tool command:

1. **Write tool** saves the usage line to `.workflows/.usage-pipe` (Write tool is not subject to Bash heuristics)
2. **`cat .workflows/.usage-pipe | bash capture-stats.sh <8 args>`** — `cat` is first token, `Bash(cat:*)` matches, heuristics suppressed. No `<` anywhere in the command.

Cleanup: each capture call overwrites the same `.usage-pipe` file (no accumulation). The file is left in place after workflow completion — it's harmless (single line, overwritten on next run) and not worth adding explicit cleanup logic.

## Changes

### 1. `scripts/capture-stats.sh` — Read from stdin

- [ ] Remove `USAGE_LINE="${9:-}"` (positional arg 9)
- [ ] Add `USAGE_LINE="$(cat)"` to read from stdin
- [ ] Update header comment: show new usage syntax with stdin
- [ ] Timeout variant: no change (no usage arg)

### 2. `scripts/plugin-qa/capture-stats-format.sh` — Update tests

QA tests run script-to-script (not via Bash tool), so heuristics don't apply. Use simple pipe syntax:

- [ ] Test 1 (comma format): `echo "$USAGE_COMMA" | bash "$CAPTURE_SCRIPT" "$STATS_FILE" ... (8 args)`
- [ ] Test 2 (newline format): `printf '%s' "$USAGE_NEWLINE" | bash "$CAPTURE_SCRIPT" ...`
- [ ] Test 3 (empty usage): `echo "" | bash "$CAPTURE_SCRIPT" ...`
- [ ] Test 4 (XML tags): `echo "$USAGE_XML" | bash "$CAPTURE_SCRIPT" ...`
- [ ] Test 5 (timeout): unchanged — no usage arg
- [ ] Test 6 (non-usage string): `echo "no-usage-data" | bash "$CAPTURE_SCRIPT" ...`

### 3. `resources/stats-capture-schema.md` — Update documentation

- [ ] Update "How to Call" section: show two-step caller pattern (Write tool + cat pipe)
- [ ] Update standard call example
- [ ] Update failure handling example
- [ ] Keep timeout call example unchanged

### 4. Skill files — Update caller instructions (5 files)

Every inline `capture-stats.sh` call that passes `"<usage-line>"` as arg 9 must change to the two-step pattern. All prose instructions that say "call `capture-stats.sh`" with usage as last arg must be updated.

The new caller pattern in skill prose:

```
After dispatch, extract the <usage>...</usage> line from the response. Save it using the Write tool
to `.workflows/.usage-pipe`, then capture stats:

cat .workflows/.usage-pipe | bash $PLUGIN_ROOT/scripts/capture-stats.sh "$STATS_FILE" "<command>" "<agent>" "<step>" "<model>" "<stem>" "<bead>" "$RUN_ID"
```

#### Concrete before/after example (do-review/SKILL.md)

**Before** (current — 9th arg with angle brackets):
```bash
bash $PLUGIN_ROOT/scripts/capture-stats.sh "$STATS_FILE" review "<agent-name>" "<agent-name>" "<model>" "$TOPIC_STEM" "null" "$RUN_ID" "<usage-line>"
```

**After** (two-step — Write tool + cat pipe, no angle brackets in Bash command):

> Save the extracted `<usage>...</usage>` line to `.workflows/.usage-pipe` using the Write tool, then:

```bash
cat .workflows/.usage-pipe | bash $PLUGIN_ROOT/scripts/capture-stats.sh "$STATS_FILE" review "<agent-name>" "<agent-name>" "<model>" "$TOPIC_STEM" "null" "$RUN_ID"
```

Apply this same transformation to all usage-bearing calls. Timeout calls (`--timeout`) have no usage arg and are unchanged.

#### Files and call counts

Call counts below are **code-fenced bash examples only** (not prose mentions). Prose mentions of `capture-stats.sh` (e.g., "call `capture-stats.sh`") also need updating to describe the two-step pattern, but are not counted here.

- [ ] `skills/do-brainstorm/SKILL.md` — 5 bash examples (research ×2, red team ×3)
- [ ] `skills/do-plan/SKILL.md` — prose-only references (no code-fenced bash examples with 9th arg; calls are described inline). Update all prose that says `"<usage-line>"` as last arg.
- [ ] `skills/do-deepen-plan/SKILL.md` — 10 bash examples (research batch ×1, synthesis ×2, red team ×3, readiness ×2, convergence ×1, minor-triage ×1)
- [ ] `skills/do-review/SKILL.md` — 1 bash example (standard call; timeout call has no usage arg)
- [ ] `skills/do-work/SKILL.md` — 1 bash example (inline prose reference; reviewer call is prose-only)

For each file:
1. Update the **Stats Capture** section prose to describe the two-step pattern
2. Update every code-fenced `bash` example to remove the 9th arg and show the cat-pipe pattern
3. Update prose mentions that describe passing `"<usage-line>"` as an argument
4. Leave `--timeout` calls unchanged (no usage arg)
5. Leave `validate-stats.sh` calls unchanged (no usage arg)

### 5. Non-changes

- `--timeout` variant: unchanged (no usage arg, no stdin needed)
- `validate-stats.sh`: unchanged (no usage involvement)
- `init-values.sh`: unchanged
- `append-snapshot.sh`: unchanged (already uses its own pattern)
- Static rules: no changes needed (`Bash(cat:*)` already exists)

## Verification

- [ ] Run `capture-stats-format.sh` — all 6 tests must pass
- [ ] Run full QA via `/compound-workflows:plugin-changes-qa` (Tier 1 scripts + Tier 2 semantic agents)
- [ ] Grep for any remaining `"<usage-line>"` as arg 9 patterns in skill files

## Sources

- Bead: zwjg — original bug report with diagnosis
- Existing pattern: `plugins/compound-workflows/scripts/append-snapshot.sh` — hides heuristic-triggering content inside script
- Memory: `.claude/memory/MEMORY.md` lines 57-67 — permission prompt heuristic rules (hard vs soft, static rule evaluation order)
- Solution: `docs/solutions/` — permission prompt optimization solution doc (bead ywug) established hard vs soft heuristic distinction
