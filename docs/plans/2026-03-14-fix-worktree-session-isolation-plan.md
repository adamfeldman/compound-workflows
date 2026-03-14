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
- Merge serialization: git's own `index.lock` handles it; retry loop (1-2s, 3 attempts). Tested empirically.
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
   - **Yes (post-compact resume):** Output via stderr (exit 2): "You are in worktree `<dirname>` on branch `<branch>`. Continue working here. At session end, compact-prep will merge your changes into main."
   - **No (fresh session start):** Continue to step 3.
3. Check for orphaned worktrees: `ls .claude/worktrees/` minus current CWD (if applicable).
   - For each orphan, gather: branch name (`git -C <path> branch --show-current`), uncommitted file count (`git -C <path> status --short | wc -l`), committed-but-unmerged count (`git log main..<branch> --oneline | wc -l`).
   - If orphans found: append detailed output per orphan:
     ```
     Warning: N orphaned worktrees from prior sessions:
       - <name> (branch: <branch>, N uncommitted files, M unmerged commits)
         Inspect: git -C .claude/worktrees/<name> status
         Merge:   git merge --no-ff <branch>
         Discard: git worktree remove .claude/worktrees/<name> && git branch -D <branch>
     ```
   - This covers the primary crash case: context exhaustion where compact-prep never ran. The user sees exactly what work is recoverable.
4. Check for dirty main: `git status --porcelain`.
   - If dirty: append to output: "Warning: main has uncommitted changes. These will NOT be visible in the worktree (branches from HEAD commit)."
5. Output via stderr (exit 2): "Session isolation active. Call `EnterWorktree` to work in an isolated worktree. Say 'stay on main' to skip."

**Output mechanism:** stderr with exit 2 (shown as feedback to model).

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

When the SessionStart hook instructs you to call `EnterWorktree`, do so immediately
unless the user says to skip. This isolates your session's git index and working tree
from concurrent sessions.

- Call `EnterWorktree` at session start (hook will prompt you)
- User can say "stay on main" / "skip worktree" to opt out for the session
- At session end, `/do:compact-prep` handles the merge back to main
- If you're already in a worktree (post-compact resume), continue working there
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
   - If ExitWorktree fails or is a no-op (post-compact session scope issue — see Assumption A1): fall back to `cd <main-repo-path>` using the path from `git worktree list` that has `(bare)` or is the main worktree.

3. **Run merge script:**
   ```bash
   bash $PLUGIN_ROOT/scripts/session-merge.sh <worktree-branch-name>
   ```

4. **Handle merge script result:**
   - **Exit 0 (success):** Announce "Session worktree merged and cleaned up." Proceed to Step 5.
   - **Exit 2 (conflict):** Claude reads conflicted files, auto-resolves (keep both sides for additive markdown, attempt semantic merge for others). Present resolution summary to user: "Resolved N conflicts: [file: resolution summary]." AskUserQuestion: "Accept merge resolutions?" Options: "Accept" / "Review specific files" / "Abort merge (keep worktree)". If accepted: `git add` resolved files + `git commit` (completes the merge). If aborted: warn user that worktree branch is unmerged.
   - **Exit 3 (retry exhaustion):** Warn: "Could not merge — another session is merging. Worktree branch `<name>` is unmerged. Merge manually with `git merge --no-ff <branch>` from main."
   - **Exit 1 (other error):** Show error, offer retry/skip/abort per compact-prep's standard per-step retry semantics.

5. **Branch guard before Step 6:** Verify `git branch --show-current` returns `main` before proceeding to push.

#### Modifications to existing steps:

- **Steps 1-4:** No changes. They run inside the worktree (commit to worktree branch). This is correct — memory updates, commits, and compound all happen in the isolated worktree.
- **Step 5 (version actions):** Now runs from main (after merge). Tags are created on main. Correct.
- **Step 6 (push):** Now pushes from main (after merge). Add branch guard: `git branch --show-current` must return `main`. If not, warn and skip push.

### Step 7: `/do:merge` Skill

Create `plugins/compound-workflows/skills/do-merge/SKILL.md`.

**Purpose:** Retry a deferred worktree merge. Used when compact-prep's merge step couldn't complete (dirty main, retry exhaustion, user aborted).

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

### Step 8: Modify `/do:work` Phase 1.2

Add session worktree detection to `/do:work`'s worktree setup:

```
# At start of Phase 1.2, before worktree creation:
bd worktree info 2>/dev/null
```

If `bd worktree info` reports the current directory is a worktree (specifically a session worktree in `.claude/worktrees/`):
- Skip worktree creation entirely
- Announce: "Already in session worktree — working directly here (no nested worktree)."
- Proceed with Phase 1.2's branch detection and sentinel setup as normal

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

- [ ] **A1: ExitWorktree post-compact** — Enter worktree → compact → call ExitWorktree. Does it work? (CRITICAL — see Assumptions)
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

**A1: ExitWorktree survives compact.** We assume "session" in ExitWorktree's scope means Claude Code process lifetime, not context window. Compact resets conversation context but doesn't restart the process. If wrong, the fallback is: compact-prep uses `cd <main-repo-path>` + manual git commands instead of ExitWorktree. The worktree branch name is stored in a sentinel file that persists across compact.

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
| `.claude/hooks/session-worktree.sh` | **New** — SessionStart hook script |
| `.claude/settings.json` | Add SessionStart hook registration |
| `plugins/compound-workflows/scripts/session-merge.sh` | **New** — Merge + retry + cleanup script |
| `plugins/compound-workflows/skills/do-compact-prep/SKILL.md` | Add Step 4.5 (worktree merge), branch guard on Step 6 |
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
| G4 ExitWorktree session scope | Assumption A1 — test empirically. Fallback path specified. |
| G5 Retry exhaustion | Leave worktree unmerged, warn user with branch name, suggest manual merge. |
| G6 Conflict resolution UX | Show diff summary in conversation. AskUserQuestion: "Accept resolutions?" with option to review specific files or abort. |
| G7 Dirty main at merge | Merge script refuses to merge if main is dirty — could be another session's in-progress work. Warns user, preserves worktree branch. |
| G8 Crash recovery | **In v1.** SessionStart hook shows per-orphan details (branch, uncommitted count, unmerged commits) with inspect/merge/discard commands. `/compound-workflows:recover` updated to handle worktree recovery. Primary case: context exhaustion where compact-prep never ran. |
| G9 Mixed isolation | Acceptable — user opted out knowing the risk. Merge script's dirty-main refusal (G7) prevents auto-committing another session's work. |
| G10 Nested worktrees | `/do:work` detects it's in a session worktree and skips its own worktree creation. Works directly in the session worktree. No nesting. |
| G11 Merge step placement | Steps 1-4 in worktree → Step 4.5 (exit + merge + resolve + cleanup) → Steps 5-6 from main. |
| G12 Cleanup method | `git worktree remove` + `git branch -d`. Fallback `-D` inside script if needed. |
| G13 AGENTS.md "backup" | Clarified: AGENTS.md instruction serves as backup for the hook (redundant trigger), not a file backup. |
| G14 Push branch guard | `git branch --show-current` check before Step 6 push. Must return `main`. |
| G15 Opt-out mechanism | Verbal per-session ("stay on main") + config toggle (`session_worktree: false`). |
| G16 .workflows/ state files | Committed as part of worktree commits, merge to main. Same as current behavior. |
| G17 Merge commit message | Accept default ("Merge branch 'worktree-X' into main"). |
| G18 Auto-approve | Merge script in `plugins/compound-workflows/scripts/`. Auto-approves via `bash <path>` rule. |
| G19 Branch deletion | `git branch -d` after --no-ff merge. Fallback `-D` inside script. |

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-03-13-git-index-isolation-brainstorm.md` — 4 design iterations (lock → --only → GIT_INDEX_FILE → worktree), 4 red team rounds, empirical collision data (1.3s tightest), merge serialization test
- **Research:** `.workflows/plan-research/worktree-session-isolation/agents/repo-research.md` — 6 git callsites, compact-prep flow, hook patterns
- **Learnings:** `.workflows/plan-research/worktree-session-isolation/agents/learnings.md` — "eliminate sharing" precedent pattern
- **SpecFlow:** `.workflows/plan-research/worktree-session-isolation/agents/specflow.md` — 7 user flows, 19 gaps resolved
- **Bead:** s7qj (bug), related: 8one (usage-pipe race — same class)
