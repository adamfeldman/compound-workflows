---
title: "Worktree-Per-Session Isolation"
type: fix
status: active
date: 2026-03-14
origin: docs/brainstorms/2026-03-13-git-index-isolation-brainstorm.md
---

# Worktree-Per-Session Isolation

**Bead:** s7qj
**Problem:** Concurrent Claude Code sessions share `.git/index` — cross-contaminated commits. Empirical data: 74 concurrent session pairs across 87 sessions, 40% edit overlapping files, 1.3s tightest same-file collision on disk.

## Design Summary

Every Claude Code session enters a git worktree via `EnterWorktree` (Claude Code native tool) at session start. Sessions work in isolation — own branch, own index, own file copies. At session end (compact-prep/abandon), changes are committed in the worktree, then merged into main via `git merge --no-ff` with a retry loop. Claude auto-resolves conflicts and presents resolutions for user review before applying.

**Key decisions from brainstorm (see brainstorm: docs/brainstorms/2026-03-13-git-index-isolation-brainstorm.md):**
- Model 1 (always-worktree) — no detection race, solo merges fast-forward
- `EnterWorktree`/`ExitWorktree` (Claude Code native) — switches CWD, refreshes caches on exit
- Merge serialization: git's own `index.lock` handles it; retry loop (1-3s, 3 attempts). Tested empirically.
- `bd` auto-discovers beads DB from worktrees (tested empirically)
- `GIT_INDEX_FILE` wrapper deferred to follow-up (not v1)

## Configuration

### `compound-workflows.local.md`

```
session_worktree: true
```

| Key | Default | Effect |
|-----|---------|--------|
| `session_worktree` | `true` | When `false`: SessionStart hook skips EnterWorktree instruction, compact-prep skips merge step, no orphan/dirty-main warnings. Everything works exactly as today. |

**Per-session override:** When `session_worktree: true`, user can still say "skip worktree" / "stay on main" at session start to opt out for that session. Reasoning: user may know they're in a single non-concurrent session and want to skip the overhead — e.g., a quick CHANGELOG fix where the merge step at session end adds friction for zero safety benefit.

## Implementation Steps

### Step 1: SessionStart Hook Script

Create `.claude/hooks/session-worktree.sh`.

**Behavior:**

1. Read `session_worktree` from `compound-workflows.local.md`. If `false` or file missing, exit 0 (no output).
2. Check if CWD is inside `.claude/worktrees/`:
   - **Yes (post-compact resume):** Output resume message to stderr and **exit 2 immediately** — skip steps 3-5 (no orphan/dirty checks needed when already in a worktree): "You are in worktree `<dirname>` on branch `<branch>`. Continue working here. At session end, compact-prep will merge your changes into main."
   - **No (fresh session start):** Continue to step 3.
3. Check for orphaned worktrees: `ls .claude/worktrees/` minus current CWD (if applicable).
   - For each orphan, gather: branch name (`git -C <path> branch --show-current`), uncommitted file count (`git -C <path> status --short | wc -l`), committed-but-unmerged count (`git log main..<branch> --oneline | wc -l`).
   - If other worktrees found: append to output buffer:
     ```
     Note: N worktrees from other sessions detected (may be active or orphaned):
       - <name> (branch: <branch>, N uncommitted files, M unmerged commits)
         Inspect: git -C .claude/worktrees/<name> status
         Merge:   /do:merge
         Discard: git worktree remove .claude/worktrees/<name> && git branch -D <branch>
     ```
   - Uses "other sessions" not "orphaned" — the hook cannot distinguish active concurrent sessions from genuinely abandoned worktrees. The user decides. This covers the primary crash case (context exhaustion where compact-prep never ran) while avoiding false-alarm noise for active concurrent sessions.
4. Check for dirty main: `git status --porcelain`.
   - If dirty: append to output buffer: "Warning: main has uncommitted changes. These will NOT be visible in the worktree (branches from HEAD commit)."
5. Append to output buffer: "Session isolation active. Call `EnterWorktree` to work in an isolated worktree. Say 'stay on main' to skip."
6. **Output entire buffer to stderr and exit 2.** Single exit point for the fresh-start path (steps 3-5 accumulate output, step 6 emits it all).

**Output mechanism:** stderr with exit 2 (shown as feedback to model). Two exit points: step 2 (resume, early exit) and step 6 (fresh start, after all checks).

**Hook does NOT:** call EnterWorktree (can't — subprocess limitation), change CWD, or block the session.

### Step 2: Register SessionStart Hook

Add to `.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [{
      "matcher": "",
      "hooks": [{"type": "command", "command": "bash .claude/hooks/session-worktree.sh"}]
    }],
    ...existing hooks...
  }
}
```

### Step 3: AGENTS.md Worktree Instructions

Add to AGENTS.md Key Conventions section:

```markdown
## Session Worktree Isolation

When the SessionStart hook instructs you to call `EnterWorktree`, do so BEFORE any
other action — before reading files, running commands, or processing other tasks.
This isolates your session's git index and working tree from concurrent sessions.

- Call `EnterWorktree` as your FIRST action at session start (hook will prompt you)
- User can say "stay on main" / "skip worktree" to opt out for the session
- At session end, `/do:compact-prep` handles the merge back to main
- If you're already in a worktree (post-compact resume), continue working there
- Any git operations before EnterWorktree happen on main — the contamination scenario this exists to prevent
```

### Step 4: Merge Script

Create `plugins/compound-workflows/scripts/session-merge.sh`.

**Interface:**
```bash
bash session-merge.sh <worktree-branch-name>
```

**Behavior:**

1. **Verify on main:** `git branch --show-current` must return `main` (or the default branch). If not, exit 1 with error.

2. **Check for dirty main:** `git status --porcelain`
   - If dirty: **refuse to merge.** Exit with code 4 and message: "Main has uncommitted changes. Cannot merge safely — another session may be working on main. Clean up main and retry. Your worktree branch is preserved."
   - Reasoning: auto-committing could commit another concurrent session's in-progress work. The safe path is to refuse and let the user decide. (See G9 resolution.)

3. **Merge with retry loop:**
   ```
   for attempt in 1 2 3; do
     git merge --no-ff <branch> && break
     if error contains "index.lock"; then
       sleep $((attempt))  # 1s, 2s, 3s backoff
       continue
     fi
     # Non-lock error (conflict or other) — break and handle
     break
   done
   ```

4. **Handle merge result:**
   - **Success (exit 0):** Proceed to cleanup.
   - **Conflict:** Exit with code 2 and list of conflicted files. Caller (compact-prep) handles resolution.
   - **Retry exhaustion (3 index.lock failures):** Exit with code 3. Caller warns user, leaves worktree unmerged.
   - **Exit 4 (dirty main):** Warn: "Main has uncommitted changes (possibly from a concurrent session). Cannot merge safely. Worktree branch `<name>` preserved — clean up main and retry with `git merge --no-ff <branch>`."
   - **Exit 1 (other error):** Show error, offer retry/skip/abort per compact-prep's standard per-step retry semantics.

5. **Cleanup (on success only):**
   ```bash
   git worktree remove .claude/worktrees/<name>
   git branch -d <branch>  # Should work — branch is merged
   # Fallback if -d fails:
   git branch -D <branch>  # Inside script — bypasses auto-approve heuristics
   ```

**Location:** `plugins/compound-workflows/scripts/session-merge.sh` — auto-approves via `bash <path>` static rule.

### Step 5: Modify compact-prep/SKILL.md

**Changes to the execute phase:**

Insert new Step 4.5 between Step 4 (commit compound docs) and Step 5 (version actions):

#### Step 4.5: Session Worktree Merge

**Skip if:** `session_worktree: false` in config, OR session is NOT in a worktree (detected via `git worktree list` — if CWD is not a worktree, skip).

**Procedure:**

1. **Record worktree info before exiting:**
   - Worktree branch name: `git branch --show-current`
   - Worktree path: `pwd`

2. **Exit worktree:** Call `ExitWorktree(action: "keep")`.
   - If ExitWorktree fails or is a no-op: fall back to a model-level `cd <main-repo-path>` via the Bash tool (CWD persists between Bash calls — this is NOT a cd inside a script). Extract main repo path via `git worktree list | head -1 | awk '{print $1}'` (first listed worktree is always the main one).

3. **Run merge script:**
   ```bash
   bash $PLUGIN_ROOT/scripts/session-merge.sh <worktree-branch-name>
   ```

4. **Handle merge script result:**
   - **Exit 0 (success):** Announce "Session worktree merged and cleaned up." Proceed to Step 5.
   - **Exit 2 (conflict):** Claude reads conflicted files, auto-resolves (keep both sides for additive markdown, attempt semantic merge for others). Present resolution summary to user: "Resolved N conflicts: [file: resolution summary]." AskUserQuestion: "Accept merge resolutions?" Options: "Accept" / "Review specific files" / "Abort merge (keep worktree)". If accepted: `git add` resolved files + `git commit --no-edit` (completes the merge with the default merge commit message — this is a merge completion, not a fresh commit, so write-tool-discipline does not apply). If aborted: warn user that worktree branch is unmerged.
   - **Exit 3 (retry exhaustion):** Warn: "Could not merge — another session is merging. Worktree branch `<name>` is unmerged. Merge manually with `git merge --no-ff <branch>` from main."
   - **Exit 4 (dirty main):** Warn: "Main has uncommitted changes (possibly from a concurrent session). Cannot merge safely. Worktree branch `<name>` preserved — clean up main and retry with `/do:merge`."
   - **Exit 1 (other error):** Show error, offer retry/skip/abort per compact-prep's standard per-step retry semantics.

5. **Branch guard before compact-prep Step 6:** Verify `git branch --show-current` returns `main` before proceeding to push.

#### Modifications to existing steps:

- **Compact-prep Steps 1-4:** No changes. They run inside the worktree (commit to worktree branch). This is correct — memory updates, commits, and compound all happen in the isolated worktree.
- **Compact-prep Step 5 (version actions):** Now runs from main (after merge). Tags are created on main. Correct.
- **Compact-prep Step 6 (push):** Now pushes from main (after merge). Add branch guard: `git branch --show-current` must return `main`. If not, warn and skip push.

### Step 6: `/do:merge` Skill

Create `plugins/compound-workflows/skills/do-merge/SKILL.md`.

**YAML frontmatter:**
```yaml
---
name: do:merge
description: Retry a deferred worktree merge — used when compact-prep's merge couldn't complete
argument-hint: "[branch-name (optional)]"
---
```

**Purpose:** Retry a deferred worktree merge. Used when compact-prep's merge step couldn't complete (dirty main, retry exhaustion, user aborted). Single-phase skill (no check/execute split — the merge script handles validation internally).

**Behavior:**

1. Detect unmerged worktree branches: `git worktree list` + check for branches matching `worktree-*` that haven't been merged into main.
2. If multiple unmerged worktrees, AskUserQuestion: "Which worktree to merge?" with branch list.
3. If single unmerged worktree, confirm: "Merge worktree branch `<name>` into main?"
4. Run `session-merge.sh <branch>`. Handle results same as compact-prep Step 4.5 (conflict resolution, dirty main refusal, retry exhaustion).
5. On success: announce "Merged and cleaned up."

**Discoverability — hint to user in these contexts:**
- Compact-prep Step 4.5 merge failure (exit 1/3/4): "Run `/do:merge` to retry when ready."
- Compact-prep conflict abort: "Worktree preserved. Run `/do:merge` to retry."
- SessionStart orphan warning: "To merge an orphaned worktree: `/do:merge`"
- `/compound-workflows:recover` worktree detection: "Unmerged worktree found. Run `/do:merge` to merge."

### Step 7: Modify `/do:setup`

Add worktree isolation config to `/do:setup`'s generated `compound-workflows.local.md`.

**Changes to `plugins/compound-workflows/skills/do-setup/SKILL.md`:**

1. **Add `session_worktree` to the config generation step** that writes `compound-workflows.local.md`. Default value: `true`. Add alongside existing keys (`tracker`, `gh_cli`, `stats_capture`, etc.).

2. **Idempotent behavior:** If `session_worktree` already exists in `compound-workflows.local.md`, preserve the user's value — do not overwrite. Only add the key if missing. This follows the same pattern as all other setup config keys (check-then-add, never clobber).

3. **Add comment in generated config:**
   ```
   # Session worktree isolation (concurrent session safety)
   # Set to false to disable worktree-per-session — sessions work directly on main
   session_worktree: true
   ```

**Note (portability — deferred):** For users of the plugin in other repos, `/do:setup` would also need to install the hook script (`.claude/hooks/session-worktree.sh`) and register it in `.claude/settings.json`. For v1, the hook is committed directly to this repo. Hook installation via setup is a follow-up for plugin portability.

### Step 8: Modify `/do:work` Phase 1.2

Add session worktree detection to `/do:work`'s worktree setup:

```
# At start of Phase 1.2, before worktree creation:
bd worktree info 2>/dev/null
```

If `bd worktree info` reports the current directory is a worktree (specifically a session worktree in `.claude/worktrees/`):
- **Skip:** `bd worktree create` (or `worktree-manager.sh` fallback) and `cd` into worktree — already in one
- **Keep:** `.work-in-progress.d` sentinel setup in the session worktree's `.workflows/` directory
- **Keep:** Branch detection for informational purposes (report current branch name)
- Announce: "Already in session worktree — working directly here (no nested worktree)."

### Step 9: Modify `/compound-workflows:recover`

Add worktree recovery to the existing recover skill:

1. After existing JSONL-based session recovery, check for orphaned worktrees:
   ```bash
   git worktree list
   ```
2. For each worktree in `.claude/worktrees/` that isn't the current CWD:
   - Gather: branch name, uncommitted file count, unmerged commit count
   - Present to user with options: "Merge (`/do:merge`)" / "Inspect" / "Discard"
3. If user chooses discard: `git worktree remove <path> && git branch -D <branch>`
4. If user chooses merge: suggest running `/do:merge`

### Step 10: Test Matrix

Add test for `/do:merge`:

- [ ] **T14: /do:merge retry** — Dirty main blocks merge → user cleans main → runs `/do:merge` → merge succeeds
- [ ] **T15: /do:merge orphan** — Orphaned worktree from crashed session → `/do:merge` merges it

Verify these scenarios before shipping:

- [x] **A1: ExitWorktree post-compact** — Enter worktree → compact → call ExitWorktree. PASSED (2026-03-14). Tool-level session state survives compaction.
- [ ] **A2: EnterWorktree via hook instruction** — Does model call EnterWorktree when instructed by SessionStart hook despite tool description saying "only when user asks"?
- [ ] **T1: Solo session, no conflicts** — Enter worktree → edit files → compact-prep → merge (should fast-forward) → push from main
- [ ] **T2: Concurrent sessions, disjoint files** — Two worktrees, different files → both merge → clean
- [ ] **T3: Concurrent sessions, overlapping file** — Two worktrees both edit `memory/project.md` → first merges clean → second gets conflict → auto-resolve → user reviews
- [ ] **T4: index.lock contention** — Two sessions merge simultaneously → one fails → retry succeeds
- [ ] **T5: Dirty main at merge** — Uncommitted changes on main → merge script refuses (exit 4) → worktree branch preserved → user cleans main → retries merge
- [ ] **T6: Opt-out** — User says "stay on main" → no worktree → compact-prep skips merge step
- [ ] **T7: Config disable** — `session_worktree: false` → no hook output, no merge step, everything as before
- [ ] **T8: Orphaned worktree detection** — Leave a worktree from a prior session → new session warns
- [ ] **T9: `git branch -d` after --no-ff merge** — Verify merged branch deletes without `-D`
- [ ] **T10: `bd` operations in worktree** — `bd show`, `bd create`, `bd close` all work (already verified in brainstorm)
- [ ] **T11: /do:work in session worktree** — `/do:work` detects session worktree and skips its own worktree creation, works directly in session worktree
- [ ] **T12: Retry exhaustion** — 3 index.lock failures → warn user, leave worktree unmerged
- [ ] **T13: Conflict resolution rejection** — User says "abort merge" → worktree preserved, user warned

## Assumptions (Verify During Implementation)

**A1: ExitWorktree survives compact — VERIFIED.** Tested 2026-03-14: EnterWorktree → compact → ExitWorktree(remove) succeeded. Tool-level session state survives compaction (process lifetime, not context window). The test used `action: "remove"` while the implementation uses `action: "keep"` — both actions require the same session recognition; `keep` is the simpler operation (preserves worktree vs deleting it), so if `remove` works, `keep` certainly works. Fallback path below retained for documentation but not needed.

**A2: AGENTS.md overrides tool description.** EnterWorktree's tool description says "ONLY when user explicitly asks." AGENTS.md is system-prompt level and should override individual tool descriptions. If the model refuses, the user can say "enter worktree" once per session (minimal friction). The AGENTS.md instruction is the primary mechanism; the hook reinforces it.

## Fallback for A1 (ExitWorktree post-compact failure)

If testing shows ExitWorktree doesn't work after compact:

1. **Sentinel file:** On EnterWorktree, write worktree branch name and main repo path to `.claude/worktrees/.session-state`:
   ```
   branch=worktree-post-compact-test
   main_path=/Users/adamf/Dev/compound-workflows-marketplace
   ```

2. **Compact-prep reads sentinel** instead of relying on ExitWorktree:
   ```bash
   cd <main_path>  # Manual CWD change
   git merge --no-ff <branch>  # Manual merge
   ```

3. **Cache refresh:** Without ExitWorktree's automatic cache clearing, add explicit instruction in compact-prep: "Re-read CLAUDE.md and memory files after merge."

This fallback is functional but loses ExitWorktree's automatic cache refresh. The sentinel adds complexity but is deterministic (no model compliance dependency).

## Files Changed

| File | Change |
|------|--------|
| `.gitignore` | Add `.claude/worktrees/` (defense-in-depth — git worktrees have `.git` files preventing parent traversal, but explicit ignore is safer) |
| `.claude/hooks/session-worktree.sh` | **New** — SessionStart hook script |
| `.claude/settings.json` | Add SessionStart hook registration |
| `plugins/compound-workflows/scripts/session-merge.sh` | **New** — Merge + retry + cleanup script |
| `plugins/compound-workflows/skills/do-compact-prep/SKILL.md` | Add Step 4.5 (worktree merge), branch guard on compact-prep Step 6 |
| `AGENTS.md` | Add worktree isolation instructions |
| `compound-workflows.local.md` | Add `session_worktree` config key (via `/do:setup`) |
| `plugins/compound-workflows/skills/do-setup/SKILL.md` | Add `session_worktree: true` to generated config |
| `plugins/compound-workflows/skills/do-merge/SKILL.md` | **New** — Retry deferred worktree merge |
| `plugins/compound-workflows/skills/do-work/SKILL.md` | Phase 1.2: detect session worktree, skip own worktree creation |
| `plugins/compound-workflows/skills/recover/SKILL.md` | Add orphaned worktree detection and recovery flow |

## Scope Boundaries

**In scope (v1):**
- SessionStart hook + AGENTS.md instruction for worktree entry
- Compact-prep merge step with conflict resolution
- Merge script with retry loop and cleanup
- Config toggle (`session_worktree`)
- Per-session verbal opt-out
- Orphaned worktree warnings
- Dirty main detection — refuse merge if main is dirty, preserve worktree branch
- `/do:work` session worktree awareness — skip nested worktree creation
- `/compound-workflows:recover` worktree recovery — detect orphans, offer merge/discard

**Deferred to follow-up:**
- `GIT_INDEX_FILE` wrapper as defense-in-depth for non-worktree contexts
- Stale base mitigation (periodic `git merge main` during long sessions)
- Merge commit message customization

## Gap Resolutions

All gaps from specflow analysis resolved:

| Gap | Resolution |
|-----|-----------|
| G1 Hook output format | stderr with exit 2 — shown as feedback to model |
| G2 Model compliance | AGENTS.md instruction (system-prompt level) overrides tool description. Assumption A2. |
| G3 Post-compact disambiguation | If CWD is inside a worktree, suppress orphan warning for THAT worktree. Warn about others. |
| G4 ExitWorktree session scope | **VERIFIED** — A1 tested, ExitWorktree works post-compact. Fallback path retained but not needed. |
| G5 Retry exhaustion | Leave worktree unmerged, warn user with branch name, suggest manual merge. |
| G6 Conflict resolution UX | Show diff summary in conversation. AskUserQuestion: "Accept resolutions?" with option to review specific files or abort. |
| G7 Dirty main at merge | Merge script refuses to merge if main is dirty — could be another session's in-progress work. Warns user, preserves worktree branch. |
| G8 Crash recovery | **In v1.** SessionStart hook shows per-orphan details (branch, uncommitted count, unmerged commits) with inspect/merge/discard commands. `/compound-workflows:recover` updated to handle worktree recovery. Primary case: context exhaustion where compact-prep never ran. |
| G9 Mixed isolation | Acceptable — user opted out knowing the risk. Merge script's dirty-main refusal (G7) prevents auto-committing another session's work. |
| G10 Nested worktrees | `/do:work` detects it's in a session worktree and skips its own worktree creation. Works directly in the session worktree. No nesting. |
| G11 Merge step placement | Steps 1-4 in worktree → Step 4.5 (exit + merge + resolve + cleanup) → Steps 5-6 from main. |
| G12 Cleanup method | `git worktree remove` + `git branch -d`. Fallback `-D` inside script if needed. |
| G13 AGENTS.md "backup" | Clarified: AGENTS.md instruction serves as backup for the hook (redundant trigger), not a file backup. |
| G14 Push branch guard | `git branch --show-current` check before compact-prep Step 6 push. Must return `main`. |
| G15 Opt-out mechanism | Verbal per-session ("stay on main") + config toggle (`session_worktree: false`). |
| G16 .workflows/ state files | Committed as part of worktree commits, merge to main. Same as current behavior. |
| G17 Merge commit message | Accept default ("Merge branch 'worktree-X' into main"). |
| G18 Auto-approve | Merge script in `plugins/compound-workflows/scripts/`. Auto-approves via `bash <path>` rule. |
| G19 Branch deletion | `git branch -d` after --no-ff merge. Fallback `-D` inside script. |

## Red Team Resolution (Plan Phase)

Red team run with 3 providers (Opus, OpenAI, Gemini). Findings deduplicated and triaged:

| Finding | Provider(s) | Severity | Resolution |
|---------|-------------|----------|------------|
| EnterWorktree tool description contradicts automation | All 3 | CRITICAL | **Valid — strengthened.** AGENTS.md now says "BEFORE any other action." A2 remains blocking test. [red-team--opus, red-team--openai, red-team--gemini] |
| `.claude/worktrees/` not gitignored | Opus | CRITICAL | **Valid — fixed.** Added `.gitignore` entry to Files Changed. Defense-in-depth (git worktrees have `.git` files preventing parent traversal). [red-team--opus] |
| ExitWorktree session scoping ambiguous | Opus | CRITICAL | **Disagree.** Empirically tested 2026-03-14: EnterWorktree → compact → ExitWorktree succeeded. "Session" = process lifetime, verified. [red-team--opus] |
| CWD fallback via bash cd won't work | Gemini | CRITICAL | **Disagree (misread).** Fallback `cd` is a model-level Bash tool call (CWD persists), not inside a script. Clarified in plan. [red-team--gemini] |
| Hook not installed by /do:setup | Gemini | CRITICAL | **Defer.** Hook is committed to this repo. Portability to other repos via `/do:setup` is a follow-up. [red-team--gemini] |
| Dirty main creates persistent unmerged branches | Opus, OpenAI | SERIOUS | **Disagree with severity.** `/do:merge` handles recovery. Not unrecoverable, just deferred until user commits Session A's work. [red-team--opus, red-team--openai] |
| Orphan false positive on active sessions | Opus | SERIOUS | **Valid — fixed.** Changed warning language from "orphaned" to "worktrees from other sessions (may be active or orphaned)." [red-team--opus] |
| Auto-resolve conflicts in prompt files | OpenAI | SERIOUS | **Disagree.** Plan already gates: additive markdown auto-merge + user review via AskUserQuestion before committing. [red-team--openai] |
| Branch name `main` hardcoded | OpenAI | SERIOUS | **Disagree.** This repo only uses `main`. Portability not a v1 requirement. [red-team--openai] |
| Stale base / logically incorrect merges | Opus | SERIOUS | **Disagree.** Inherent to all branching models. Git handles correctly. Acceptable for additive markdown. [red-team--opus] |
| EnterWorktree version/availability gating | OpenAI | SERIOUS | **Disagree.** Over-engineering for v1. Core Claude Code tools. [red-team--openai] |
| Full worktrees overengineered vs GIT_INDEX_FILE | Gemini | SERIOUS | **Disagree.** Problem is BOTH index AND working tree (1.3s same-file collision). GIT_INDEX_FILE only solves index. Resolved in brainstorm v3→v4. [red-team--gemini] |
| **Fixed (batch):** 4 MINOR findings acknowledged. [see .workflows/plan-research/worktree-session-isolation/red-team--opus.md, red-team--openai.md, red-team--gemini.md] | | | |

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-03-13-git-index-isolation-brainstorm.md` — 4 design iterations (lock → --only → GIT_INDEX_FILE → worktree), 4 red team rounds, empirical collision data (1.3s tightest), merge serialization test
- **Research:** `.workflows/plan-research/worktree-session-isolation/agents/repo-research.md` — 6 git callsites, compact-prep flow, hook patterns
- **Learnings:** `.workflows/plan-research/worktree-session-isolation/agents/learnings.md` — "eliminate sharing" precedent pattern
- **SpecFlow:** `.workflows/plan-research/worktree-session-isolation/agents/specflow.md` — 7 user flows, 19 gaps resolved
- **Red team:** `.workflows/plan-research/worktree-session-isolation/red-team--opus.md`, `red-team--openai.md`, `red-team--gemini.md` — 3-provider challenge, 4 findings accepted, 8 disagreed with reasoning
- **Bead:** s7qj (bug), related: 8one (usage-pipe race — same class)
