---
title: "fix: Consolidate mkdir and env caching into init-values.sh"
type: fix
status: completed
date: 2026-03-13
---

# Consolidate mkdir and Env Caching into init-values.sh

## Problem

Skill init code blocks contain multiple commands (mkdir, bash init-values.sh, env var caching) that models chain with `&&`, triggering compound-command heuristics even when each individual command has a static allow rule. User observed a permission prompt for `mkdir -p ... && mkdir -p ... && bash .../init-values.sh ...` despite having both `Bash(mkdir:*)` and `Bash(bash:*)` rules.

Root cause: static rules match the first token of the compound command, but `&&` chains trigger separate heuristic evaluation. Per CLAUDE.md Robustness Principle 10: consolidate multi-command setup into scripts, not code blocks.

## Solution

Move two categories of lines from skill code blocks into init-values.sh:

1. **`mkdir -p .workflows/stats`** — needed by all STATS_FILE commands. init-values.sh already computes the path.
2. **`CACHED_MODEL` env var capture** — reads `$CLAUDE_CODE_SUBAGENT_MODEL`, defaults to `opus`. Currently scattered across 4 skills with slight naming variations.

After the change, each skill's init block becomes a single line: `bash ${CLAUDE_SKILL_DIR}/../../scripts/init-values.sh <cmd> <stem>`. One first-token match, no compound chain, no prompt.

## Changes

### Step 1: init-values.sh — add mkdir and CACHED_MODEL emission

In `plugins/compound-workflows/scripts/init-values.sh`:

**1a. Stats directory creation.** In each case branch that computes `STATS_FILE_VAL` (`brainstorm|plan|deepen-plan|review`, `work`, `compact-prep`), add `mkdir -p "$(dirname "$STATS_FILE_VAL")"` after the STATS_FILE_VAL computation, before validation. This creates `.workflows/stats/` (or whatever path STATS_FILE resolves to). For `compact-prep`, add `mkdir -p "$(dirname "$SNAPSHOT_FILE_VAL")"` — redundant with `append-snapshot.sh`'s own mkdir, but establishes the invariant that init-values.sh creates directories it references.

**1b. CACHED_MODEL emission.** After the existing `echo` block in each agent-dispatching branch (`brainstorm|plan|deepen-plan|review`, `work`), add:

```bash
# Subagent model for inherit-model agents
_csm="${CLAUDE_CODE_SUBAGENT_MODEL:-}"
echo "CACHED_MODEL=${_csm:-opus}"
if [[ -n "$_csm" ]]; then
  echo "NOTE=CLAUDE_CODE_SUBAGENT_MODEL is set — agents with model: inherit will use the override. Agents with explicit model: sonnet are unaffected."
fi
```

Do NOT add CACHED_MODEL to branches that don't dispatch agents (`compact-prep`, `setup`, `plugin-changes-qa`, `classify-stats`, `version`).

**Design note (S1):** Emitting `opus` directly (rather than `unset`) is intentional. The prior `unset` sentinel was display-only — all downstream model-resolution prose already said "if unset, default to opus." No downstream logic distinguishes "env var was set to opus" from "env var was absent, defaulted to opus." This snippet is identical for both the `brainstorm|plan|deepen-plan|review` and `work` case branches — place it after the last `echo` in each branch.

### Step 2: Skill file updates — remove mkdir and env caching from init blocks

For each skill, the init code block should contain ONLY `bash ${CLAUDE_SKILL_DIR}/../../scripts/init-values.sh <cmd> <stem>`. Remove all other lines. Adjust the prose instructions to say "Track the values PLUGIN_ROOT, RUN_ID, DATE, STATS_FILE, CACHED_MODEL" (adding CACHED_MODEL to the tracked values list).

**do-brainstorm/SKILL.md** (lines 38-45):
- Remove: `mkdir -p .workflows/brainstorm-research/<topic-stem>` (line 39)
- Remove: `mkdir -p .workflows/stats` (line 40)
- Remove: `[[ -n "$CLAUDE_CODE_SUBAGENT_MODEL" ]] && echo "Note: ..."` (line 41)
- Remove: `CACHED_MODEL="${CLAUDE_CODE_SUBAGENT_MODEL:-opus}"` (line 43)
- Remove: `echo "CACHED_MODEL=$CACHED_MODEL"` (line 44)
- Keep: `bash ${CLAUDE_SKILL_DIR}/../../scripts/init-values.sh brainstorm <topic-stem>` (line 42)
- Add separate code block BEFORE init block: `mkdir -p .workflows/brainstorm-research/<topic-stem>`

**do-plan/SKILL.md** (lines 97-101):
- Remove: `mkdir -p .workflows/stats` (line 98)
- Remove: `echo $CLAUDE_CODE_SUBAGENT_MODEL` (line 100)
- Keep: `bash ${CLAUDE_SKILL_DIR}/../../scripts/init-values.sh plan <plan-stem>` (line 99)

**do-work/SKILL.md** (lines 63-66 and 70-73):
- Block 1 (with stem): Remove `mkdir -p .workflows/stats` (line 64). Keep `bash ... work <stem>` (line 65).
- Block 2 (no stem): Remove `mkdir -p .workflows/stats` (line 71). Keep `bash ... work` (line 72).
- Remove the separate env capture block (lines 79-81): `echo "CACHED_SUBAGENT_MODEL=${CLAUDE_CODE_SUBAGENT_MODEL:-unset}"` — replaced by CACHED_MODEL from init-values.sh.

**do-deepen-plan/SKILL.md** (lines 40-44 and 50-54):
- Init block: Remove `mkdir -p .workflows/deepen-plan/<plan-stem>/agents/run-<N>` (line 41) and `mkdir -p .workflows/stats` (line 42). Keep `bash ... deepen-plan <plan-stem>` (line 43).
- Add separate code block BEFORE init block: `mkdir -p .workflows/deepen-plan/<plan-stem>/agents/run-<N>`
- Remove the separate env capture block (lines 50-54): the `CACHED_MODEL=...`, `echo ...`, and `[[ -n ... ]] && echo "Note: ..."` lines — replaced by CACHED_MODEL from init-values.sh.

**do-review/SKILL.md** (lines 40-45):
- Remove: `mkdir -p .workflows/stats` (line 41)
- Remove: `CACHED_SUBAGENT_MODEL=$CLAUDE_CODE_SUBAGENT_MODEL` (line 43)
- Remove: `echo "SUBAGENT_MODEL=${CACHED_SUBAGENT_MODEL:-unset}"` (line 44)
- Keep: `bash ${CLAUDE_SKILL_DIR}/../../scripts/init-values.sh review <topic-stem>` (line 42)

### Step 3: Update tracked values in prose

Each skill says "Track the values PLUGIN_ROOT, RUN_ID, DATE, STATS_FILE." Update to include CACHED_MODEL (and NOTE if emitted). The skills that currently reference `CACHED_MODEL` or `CACHED_SUBAGENT_MODEL` elsewhere in their text should be updated to use the value from init-values.sh output.

Update tracked values lists to: "Track the values PLUGIN_ROOT, RUN_ID, DATE, STATS_FILE, CACHED_MODEL (and NOTE if emitted) for use in subsequent steps." For model-resolution prose, replace references to `CACHED_SUBAGENT_MODEL` with `CACHED_MODEL` and remove any "if unset, default to opus" logic since CACHED_MODEL already resolves the default. Use the CACHED_MODEL value from init-values.sh output as the default model for inherit-model agents.

- [x] do-brainstorm: update tracked values list, update references to CACHED_MODEL
- [x] do-plan: update tracked values list, replace "Cache the model value: if `CLAUDE_CODE_SUBAGENT_MODEL` is set..." paragraph with: "Use the CACHED_MODEL value from init-values.sh output as the default model for inherit-model agents."
- [x] do-work: update tracked values list, replace `CACHED_SUBAGENT_MODEL` reference with CACHED_MODEL
- [x] do-deepen-plan: update tracked values list, remove "Also capture the subagent model setting" prose block
- [x] do-review: update tracked values list, replace `CACHED_SUBAGENT_MODEL`/`SUBAGENT_MODEL` references with CACHED_MODEL

### Step 4: Update CLAUDE.md script description

In `plugins/compound-workflows/CLAUDE.md`, update the init-values.sh description from:
> `init-values.sh — Shared init-value computation — PLUGIN_ROOT, RUN_ID, DATE, STATS_FILE (auto-approved)`

To:
> `init-values.sh — Shared init-value computation + directory creation — PLUGIN_ROOT, RUN_ID, DATE, STATS_FILE, CACHED_MODEL (auto-approved)`

Also update the supported commands table in init-values.sh's header comment. The relevant lines become: `brainstorm, plan, deepen-plan, review -> PLUGIN_ROOT, RUN_ID, DATE, STATS_FILE, CACHED_MODEL[, NOTE]` and `work -> PLUGIN_ROOT, RUN_ID, DATE, STEM, STATS_FILE, WORKTREE_MGR, CACHED_MODEL[, NOTE]`.

### Step 5: QA and verification

- [x] Run `/compound-workflows:plugin-changes-qa` (both Tier 1 and Tier 2)
- [ ] Manually test: invoke `/do:brainstorm` and verify the init block runs without a permission prompt
- [x] Verify init-values.sh exit behavior: `set -euo pipefail` means mkdir failure = exit 1, which skills already handle ("if init-values.sh fails, warn and stop")

## Out of Scope

- Defensive `mkdir -p` in `capture-stats.sh` (follow-up — defense-in-depth, not required for this fix)
- Updating CLAUDE.md Principle 10 example text (after fix lands)
- Other non-init mkdir calls in separate code blocks (already clean)

## Acceptance Criteria

- [x] Every skill init code block contains exactly one line: `bash ${CLAUDE_SKILL_DIR}/../../scripts/init-values.sh <cmd> <stem>`
- [x] init-values.sh creates `.workflows/stats/` for all STATS_FILE-emitting branches
- [x] init-values.sh emits `CACHED_MODEL=` for all agent-dispatching branches
- [ ] No permission prompt on init block execution (with `Bash(bash:*)` static rule)
- [x] QA passes (Tier 1 + Tier 2)

## Sources

- Conversation analysis: user screenshot of permission prompt on `mkdir -p ... && mkdir -p ... && bash .../init-values.sh`
- CLAUDE.md Robustness Principle 10: "Consolidate multi-command setup into scripts, not code blocks"
- Research: `.workflows/plan-research/consolidate-mkdir-into-init-values/agents/`
- Solution: `docs/solutions/claude-code-internals/2026-03-11-script-file-shell-substitution-bypass.md` — init-values.sh auto-approves universally because `$()` heuristic only inspects Bash tool input string
