---
title: "Session Worktree Start Flow — Deterministic Hook + /do:start + Cleanup Algorithm"
type: feat
status: active
date: 2026-03-16
origin: docs/brainstorms/2026-03-15-session-worktree-start-flow-brainstorm.md
bead: hb4a
---

# Session Worktree Start Flow

## Problem

The v3.3.0 SessionStart hook *instructs* the model to create worktrees but doesn't *create* them. This produces a ~25% failure rate (3/4 sessions complied unprompted in integration testing). Additionally:

- No mechanism to distinguish fresh vs resumed sessions
- Orphan worktrees from crashed sessions accumulate with no cleanup algorithm
- Concurrent sessions can delete each other's active worktrees (`bd worktree remove --force` during abandon — reproduced 2026-03-16, JSONL forensics confirmed)
- PID files stored inside worktrees (cleanup friction) and single-writer (overwrite race)
- Pre-commit hook uses fragile path-heuristic detection
- `/do:work` conflates session and work worktree lifecycles

## Design Summary

Four-tier layered system (see brainstorm: Decisions 1-11):

1. **Hook** (deterministic) — creates worktree in bash, writes per-claimant PID, runs GC with combined PID+state algorithm
2. **AGENTS.md** (unconditional fallback) — `cd` into hook-created worktree, or create manually if hook didn't fire
3. **`/do:start`** (user-initiated) — interactive session manager for orphans, rename, switch, create
4. **Pre-commit hook** (deterministic backstop) — blocks main commits when managed worktrees exist

Key design principles carried forward from brainstorm:
- **Deterministic over probabilistic** — hook creates worktree in bash (100% reliable) instead of instructing model (~75% reliable)
- **Fail-closed** — cleanup only deletes when ALL indicators say safe (PID dead AND no uncommitted AND no unmerged)
- **Per-claimant PID** — concurrent hooks don't overwrite each other
- **Script-file delegation** — model calls `write-session-pid.sh`, never writes PIDs inline (avoids #31872 risk)

## Specflow Resolutions

Two critical findings from specflow analysis resolved during planning:

**CQ1: $PPID inconsistency between hook and model context.** In hook context, `$PPID` = Claude Code PID (verified). In model-invoked script context, `$PPID` = ephemeral shell PID (dies after command). Fix: `write-session-pid.sh` takes PID as a required second argument. Hook passes `$PPID` directly. Model captures Claude PID via `echo $PPID` (outer shell's $PPID = Claude Code process) then passes as argument. (see brainstorm: Decision 9)

**CQ2: Self-removal exception creates concurrent-session hole.** Original algorithm: "skip liveness check entirely" for self-removal. This lets session A remove a worktree while session B is active in it. Fix: Self-removal exception is scoped — remove own `pid.$PPID` from the glob, then check remaining PIDs. If ANY remaining PID alive → block removal. Only proceed to state checks if no other live sessions claim the worktree. (see brainstorm: Decision 9)

Additional specflow resolutions incorporated:
- Exit codes 3 (retry exhaustion) and 5 (file overlap) in `/do:work` transition → fall back to working in session worktree, warn user (same as exit 1)
- Pre-commit error message lists actual worktree names and types found, not generic "session worktree"
- Dead PID files pruned during hook GC even when worktree is retained
- `/do:start` uses "resume" as the single action (not separate "resume" vs "switch")
- `/do:start` deletes `.worktrees/.opted-out` sentinel when creating/switching to a worktree
- Hook step ordering: Hook-1 config check → Hook-2 sentinel deletion → Hook-3 worktree-in-worktree guard → ... → Hook-7 existing worktree scan → Hook-8 GC → Hook-9 create
- Hook retries once regardless of error type (collision detection not worth the complexity)
- `/do:start rename` requires being inside a session worktree (guard check)
- Unknown `/do:start` subcommands fall through to interactive mode
- `/do:start` removes own PID from old worktree when switching, writes to new worktree

## Red Team Resolutions

**Disagreed (user-decided during plan red team triage):**
- S4: "/do:work transition adds 5 failure modes for questionable benefit" [red-team--opus] — **Disagree.** Decision 8 (lifecycle separation) was user-decided in the brainstorm. The failure modes have safe fallbacks (work in session worktree). User reasoning: the failure modes are model-interpreted from deterministic exit codes; worst case is falling back to current behavior.
- S7: "Auto-invoking /do:start on every resume creates unnecessary friction" [red-team--opus] — **Disagree.** User wants the choice: "why would it auto-cd into an existing worktree and not offer to make a new one?" The user might be starting a new task. Always present the worktree choice via `/do:start` when existing worktrees are found.

## Implementation Steps

### Step 0: Preconditions — VALIDATED

**$PPID empirical validation** [red-team--opus, red-team--gemini, red-team--openai]:

**Validated during planning (2026-03-16).** Direct `echo $PPID` in a model Bash tool call returns the Claude Code PID (confirmed: PID 3412, process `claude`). However, `$PPID` *inside* a `bash script.sh` invocation returns the ephemeral zsh PID (dies immediately after the command). This confirms CQ1 — scripts MUST receive PID as an argument, not use `$PPID` internally.

- [x] `echo $PPID` from model Bash context → 3412 (claude process) ✓
- [x] `bash -c 'echo $PPID'` → ephemeral zsh PID (dead on arrival) ✗
- [x] Conclusion: "pass PID as argument" design is correct. No fallback needed.

### Step 1: Create `write-session-pid.sh` helper script

**File:** `plugins/compound-workflows/scripts/write-session-pid.sh`

**What it does:**
```
Usage: write-session-pid.sh <worktree-name> <pid>
```

- `mkdir -p .worktrees/.metadata/<worktree-name>`
- `echo <pid> > .worktrees/.metadata/<worktree-name>/pid.<pid>`
- Exit 0 on success, exit 1 on failure with diagnostic on stderr

**How it fails:** If `.worktrees/` doesn't exist, `mkdir -p` creates it. If filesystem permissions deny write, stderr shows the error. Callers (hook, `/do:start`) handle non-zero exit.

**Why PID is an argument, not `$PPID`:** In hook context, `$PPID` = Claude Code PID. In model Bash context, `$PPID` = ephemeral shell PID. Passing explicitly ensures consistency. (Specflow CQ1 resolution)

- [ ] Create script file with argument validation (exactly 2 args required)
- [ ] `chmod +x` in template
- [ ] Verify script works from both hook context and direct Bash invocation
- [ ] Depends on Step 0 ($PPID validation) completing first — interface may change if fallback is needed

### Step 2: Update `session-merge.sh` and `/do:merge` — metadata cleanup

**Files:** `plugins/compound-workflows/scripts/session-merge.sh`, `plugins/compound-workflows/skills/do-merge/SKILL.md`

**session-merge.sh** — after successful merge (exit 0 path), before final cleanup:

- [ ] Extract session worktree name from the branch being merged
- [ ] `rm -rf .worktrees/.metadata/<session-name>` after worktree removal succeeds
- [ ] Add comment explaining why (Decision 9 metadata lifecycle)

**`/do:merge`** — add metadata cleanup for manual resolution path [red-team--opus, minor triage #4]:

- [ ] After user manually resolves a merge conflict (exit 2 path) and completes the merge, `/do:merge` should run `rm -rf .worktrees/.metadata/<session-name>` as a final cleanup step
- [ ] If merge was not completed (user aborted), skip metadata cleanup (worktree still exists)

**How it fails:** If metadata directory doesn't exist, `rm -rf` is a no-op. Non-critical.

### Step 3: Rewrite SessionStart hook template

**File:** `plugins/compound-workflows/templates/session-worktree.sh`

This is the largest change. The hook moves from "instruct model to create" to "create deterministically in bash."

**Hook step ordering:**

1. **Hook-1: Read config** — `session_worktree` from `compound-workflows.local.md`. Missing = silent exit 0.
2. **Hook-2: Delete sentinel** — `rm -f .worktrees/.opted-out` (tidy up from prior session)
3. **Hook-3: Worktree-in-worktree guard** — `git rev-parse --git-dir` vs `--git-common-dir` (Decision 11). If inside any worktree → emit "Already inside a worktree. Skipping session worktree creation." → exit 0.
4. **Hook-4: Self-version check** — compare installed vs template version. Warn if stale, continue.
5. **Hook-5: bd availability check** — if `bd` unavailable, warn and exit 0.
6. **Hook-6: Feature disabled path** — if `session_worktree: false`, run GC (Hook-8) then exit 0.
7. **Hook-7: Existing worktree scan** — `ls -dt .worktrees/session-*` (sorted by mtime, newest first)
   - If existing worktrees found → **existing-worktree path** (Hook-7a)
   - If no existing worktrees → **happy path** (Hook-9)
8. **Hook-8: GC merged worktrees** — loop `.worktrees/session-*`, apply Decision 9 combined algorithm:
   - Glob `.worktrees/.metadata/<name>/pid.*`
   - `kill -0 $(cat file)` for each — if ANY alive → skip worktree
   - If all dead: prune dead PID files (`rm` each dead `pid.*` file)
   - Check `git -C <worktree> status --porcelain --untracked-files=no` — if output → skip + warn
   - Determine default branch: `git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||'` falling back to `main` if the symbolic ref is not set.
   - Check `git log <default-branch>..<branch> --oneline` — if output → skip + warn
   - Both clean → `bd worktree remove` (NO `--force`) + `rm -rf .worktrees/.metadata/<name>`
   - Report remaining worktrees with Inspect/Merge/Discard remediation hints
9. **Hook-9: Happy path (create worktree):**
   - Generate random 4-char hex ID via `openssl rand -hex 2`
   - `bd worktree create .worktrees/session-<id>`
   - If fails: retry once with new random ID
   - If both fail: emit stderr diagnostic, suggest model creates manually → exit 0
   - On success: call `write-session-pid.sh session-<id> $PPID`
   - If PID write fails (non-zero exit): remove the just-created worktree (`bd worktree remove .worktrees/session-<id>`) and emit warning: "Worktree created but PID protection failed. Removed worktree for safety. Model should create manually." [red-team--opus: fail-closed on PID write failure]
   - Emit: `MANDATORY: session worktree created at .worktrees/session-<id>. Your FIRST action must be: cd /absolute/path/.worktrees/session-<id>`

**Hook-7a: Existing-worktree path:**
- Read `session_worktree_stale_minutes` from `compound-workflows.local.md`; if the key is absent or unparseable, default to 60.
- For each existing worktree, gather:
  - Mtime via cross-platform wrapper: `stat -f '%m' <dir> 2>/dev/null || stat -c '%Y' <dir> 2>/dev/null`. If neither works, skip freshness analysis for this worktree (treat as unknown age). [red-team--gemini, red-team--opus: `stat -f` is macOS-only]
  - PID liveness: glob `.worktrees/.metadata/<name>/pid.*`, `kill -0` each
  - Uncommitted count: `git -C <path> status --porcelain --untracked-files=no | wc -l`
  - Unmerged count: `git log <default>..<branch> --oneline | wc -l`
- Call `write-session-pid.sh <most-recent-name> $PPID` (write PID to recommended worktree — safe-side behavior per brainstorm Q13)
- **1 recent worktree** (< stale threshold): emit resume suggestion with context
- **1 stale worktree** (≥ stale threshold): emit create-new suggestion, mention orphan
- **Multiple worktrees**: list all with stats
- All paths: emit "Run `/do:start` to manage session worktrees" suggestion
- emit MANDATORY: `if resuming a previous conversation, run cd <absolute-path>. If this is a new conversation, ask the user: resume this worktree or create a new one?`

**What to carry forward from v2:**
- stdout + exit 0 delivery (verified working)
- Self-version check logic
- bd availability check
- Config reading pattern

**What changes from v2:**
- Hook-7 now CREATES the worktree instead of instructing model
- PID files move from `.worktrees/session-<name>/.session.pid` to `.worktrees/.metadata/session-<name>/pid.$PPID`
- GC uses Decision 9 combined algorithm instead of merge-ancestry-only check
- Existing-worktree path adds mtime freshness, uncommitted count, suggests `/do:start`
- Sentinel deletion added at Hook-2
- Worktree-in-worktree guard added at Hook-3 (Decision 11)
- Name collision retry added at Hook-9

- [ ] Extract GC algorithm (Hook-8) into a separate script `plugins/compound-workflows/scripts/session-gc.sh` for independent testing and reuse by `/do:start cleanup` [red-team--opus, red-team--gemini: duplicated GC logic, testability]. Hook calls `session-gc.sh`, `/do:start cleanup` also calls it.
- [ ] Add `SESSION_WORKTREE_DEBUG=1` env var support: when set, log each hook step's decision to `.worktrees/.debug.log` (append, timestamped). Invaluable for debugging hook issues that fire before model interaction. [red-team--opus: no debugging strategy]
- [ ] Rewrite hook template with all steps above
- [ ] Bump template version to v3.0.0 (significant behavior change: deterministic creation, new PID location)
- [ ] Preserve backward compat: if old `.worktrees/session-<name>/.session.pid` found during GC, treat its single PID identically to new-format `pid.*` files in the Decision 9 algorithm (one PID, no per-claimant support). Remove this backward compat path after 2 minor versions or in the next major version (whichever comes first).
- [ ] Test: fresh session (no worktrees) → worktree created deterministically
- [ ] Test: resume session (existing worktree) → suggests resume or /do:start
- [ ] Test: multiple existing worktrees → suggests /do:start
- [ ] Test: already inside worktree → skips creation
- [ ] Test: `session_worktree: false` → only runs GC
- [ ] Test: bd unavailable → warns and exits cleanly
- [ ] Test: name collision → retries once
- [ ] Test: concurrent session → per-claimant PID files don't overwrite

### Step 4: Rewrite pre-commit hook template

**File:** `plugins/compound-workflows/templates/pre-commit-worktree-check.sh`

Decision 10: check filesystem reality, not path heuristics.

**Logic (in order, first match wins):**

1. Read `session_worktree` from `compound-workflows.local.md` — if not `true`, exit 0 (allow)
2. Worktree detection via git plumbing (Decision 11):
   ```
   git_dir=$(git rev-parse --git-dir 2>/dev/null)
   common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
   ```
   If `$git_dir != $common_dir` → inside a worktree → exit 0 (allow)
3. Check opt-out sentinel: if `.worktrees/.opted-out` exists → exit 0 (allow)
4. Check for managed worktrees on disk: `ls .worktrees/session-* .worktrees/work-* 2>/dev/null`
5. If none found on disk: secondary check `git worktree list --porcelain` for stale registry entries. If stale entries exist → exit 1 (block, inconsistent state). Retained despite red-team--opus questioning: stale entries indicate an inconsistent git state worth blocking, even if rare. Consistent with fail-closed philosophy.
6. If none found anywhere → exit 0 (allow, no worktrees at all)
7. If managed worktrees found on disk → exit 1 (block):
   ```
   Error: Committing to main while managed worktrees exist.
   Found: session-a7f2, work-fix-login
   Either cd into a worktree, or touch .worktrees/.opted-out to allow main commits.
   ```

**How it fails:** If git plumbing commands fail (corrupt repo), the commit itself would also fail. If `compound-workflows.local.md` is missing, first check exits (allow) — feature not configured.

- [ ] Rewrite template with Decision 10/11 logic
- [ ] Bump version to v2.0.0
- [ ] Error message lists actual worktree names found (specflow IQ2)
- [ ] Test: inside worktree → allow
- [ ] Test: on main + opted-out sentinel → allow
- [ ] Test: on main + no worktrees → allow
- [ ] Test: on main + session worktree exists → block with worktree name in message
- [ ] Test: on main + work worktree exists → block with worktree name in message
- [ ] Test: on main + stale git registry entry → block

### Step 5: Create `/do:start` skill

**File:** `plugins/compound-workflows/skills/do-start/SKILL.md`

New skill — interactive session worktree manager. (see brainstorm: Decision 5)

**Frontmatter:**
```yaml
---
name: do:start
description: Manage session worktrees — resume, cleanup, rename, switch, create
argument-hint: "[cleanup|rename <name>|status]"
---
```

**Argument parsing:**
- No arguments → interactive mode
- `cleanup` → skip to orphan cleanup
- `rename <new-name>` → rename current worktree
- `status` → display only, no action
- Unknown subcommand → interactive mode (specflow S1)

**Interactive mode flow:**

1. **Re-scan worktree state from scratch** (not hook output — state may have changed):
   - `ls -dt .worktrees/session-*`
   - For each: mtime (cross-platform: `stat -f '%m' 2>/dev/null || stat -c '%Y' 2>/dev/null`, skip freshness if neither works), PID liveness (glob `.metadata/<name>/pid.*`, `kill -0`), uncommitted tracked-file count, untracked file count, unmerged commit count

2. **Present single AskUserQuestion** with table:
   ```
   | Worktree | Age | PID | Uncommitted | Untracked | Unmerged | Actions |
   |----------|-----|-----|-------------|-----------|----------|---------|
   | session-a7f2 | 5m | alive | 3 | 1 | 2 | resume |
   | session-x3k9 | 2d | dead | 0 | 0 | 0 | remove, resume |
   ```
   Include untracked file count (`git ls-files --others --exclude-standard | wc -l`) in the table. [re-check: consistent with rename/transition untracked checks]
   - PID-alive worktrees: show "resume" only (NOT "remove" — Decision 9 blocks it anyway)
   - PID-dead + clean: show "remove" and "resume"
   - PID-dead + dirty: show "resume" only (with warning about uncommitted/unmerged)
   - Always show "create new" and "skip" as additional options

3. **Execute user choice:**
   - **Resume:** `cd <absolute-path>`, one-line summary
   - **Remove:** Apply Decision 9 refined algorithm (CQ2 fix: remove own PID from glob, check remaining). If safe → `bd worktree remove` (no `--force`) + `rm -rf .worktrees/.metadata/<name>`. If blocked → explain why.
   - **Create new:** generate random ID, `bd worktree create`, capture Claude PID (`echo $PPID`), call `write-session-pid.sh <name> <pid>`, `cd` into it
   - **Skip:** exit without action

4. **PID management on switch/create:**
   - Capture Claude PID: model runs `echo $PPID` in a separate Bash call
   - Remove own PID from old worktree: `rm -f .worktrees/.metadata/<old-name>/pid.<claude-pid>`
   - Write PID to new worktree: `bash write-session-pid.sh <new-name> <claude-pid>`

5. **Delete sentinel on opt-back-in:** If `.worktrees/.opted-out` exists and user creates/resumes a worktree, delete the sentinel (specflow IQ5).

**Cleanup subcommand:**
- Re-scan worktree state
- Apply Decision 9 to each worktree where all PIDs dead
- Report results: "Removed N worktrees. M retained (uncommitted/unmerged/PID alive)."
- If all PID-alive: "All worktrees have active sessions. Nothing to clean up." (specflow S3)

**Rename subcommand:**
- Guard: must be inside a session worktree (specflow S2). Check git plumbing (Decision 11). If not in session worktree → error and exit.
- Check for untracked files: `git ls-files --others --exclude-standard` [red-team--gemini, red-team--opus]. If any exist, warn: "N untracked files will be lost during rename. Stage them first?" Offer to `git add <files>` before proceeding.
- Commit all uncommitted changes (including any just-staged untracked files): `git add -u && git commit -m "session checkpoint before /do:start rename to <new-name>"`
- `git branch -m <old-name> <new-name>` (preserves commit hashes)
- `cd` to main repo root before removing worktree [red-team--gemini: CWD deletion detaches inode]
- `bd worktree remove` old worktree (deletes the working tree directory)
- `bd worktree create .worktrees/<new-name>` — creates a new worktree. Since the branch was already renamed to `<new-name>` via `git branch -m`, the branch and worktree directory names stay in sync (bd worktree create uses the worktree name as the branch name by default). `<new-name>` always applies to both the branch and directory.
- Update PID: `rm -rf .worktrees/.metadata/<old-name>`, `write-session-pid.sh <new-name> <claude-pid>`
- `cd` into new worktree path, one-line summary

**Status subcommand:**
- Display worktree table (same as interactive mode step 2)
- No AskUserQuestion — display only

- [ ] Create `plugins/compound-workflows/skills/do-start/SKILL.md`
- [ ] Create `plugins/compound-workflows/commands/compound/start.md` as a thin alias redirecting to `/do:start`, following the existing alias format in that directory
- [ ] Test: interactive mode with 0, 1, 2+ worktrees
- [ ] Test: cleanup with all-PID-alive worktrees
- [ ] Test: rename from inside session worktree
- [ ] Test: rename from main (should error)
- [ ] Test: status display
- [ ] Test: PID cleanup on switch (old PID removed, new PID written)
- [ ] Test: sentinel deletion on opt-back-in
- [ ] Test: invalid subcommand falls through to interactive

### Step 6: Update `/do:work` Phase 1.2 — session-to-work transition

**File:** `plugins/compound-workflows/skills/do-work/SKILL.md`

**Note:** "Phase 1.2" and "Step 1.2.x" below refer to sections in the target file `/do:work` SKILL.md, not steps in this plan.

Replace current Phase 1.2 (work inside session worktree) with transition flow (Decision 8):

**Detection:** Same git plumbing check (Decision 11). If CWD path resolves to a session worktree → trigger transition.

**Step 1.2.1 — Check uncommitted and untracked files:** [red-team--gemini, red-team--openai, red-team--opus]
- Check tracked changes: `git status --porcelain --untracked-files=no`
- Check untracked files: `git ls-files --others --exclude-standard`
- If tracked changes exist: AskUserQuestion — "Session worktree has N uncommitted changes. Commit with checkpoint message, or discard?"
  - Commit: `git add -u && git commit -m "session checkpoint before /do:work transition"`
  - Discard: `git checkout -- .`
- If untracked files exist: AskUserQuestion — "Session worktree has N untracked files (list first 5). Stage them before transition? They will be lost otherwise."
  - Stage: `git add <files> && git commit -m "session checkpoint: stage untracked files before /do:work transition"`
  - Skip: proceed (user accepts loss)

**Step 1.2.2 — Refined self-removal PID check (CQ2 fix):**
- Capture Claude PID: `echo $PPID` in a Bash call
- Check own PID file: `.worktrees/.metadata/session-xxx/pid.<claude-pid>`
- If own PID exists: remove it from the glob results
- Check remaining PID files: if ANY alive → **block** with message: "Another session (PID NNN) is using this worktree. Cannot transition. Working inside session worktree."
- If own PID missing (pid.<claude-pid> does not exist in metadata): warn "PID mismatch — session PID not found in metadata. This may indicate $PPID inconsistency. Continuing with full liveness checks." Pass `caller_pid=0` to the cleanup algorithm (no self-exclusion — all PIDs are checked for liveness). If any PID alive → block. If all dead → proceed to merge.
- If no other live PIDs: proceed to merge

**Step 1.2.3 — Merge session worktree to default branch:**
- `cd` to main repo root (extract from `git worktree list --porcelain` first line)
- Run `session-merge.sh <branch-name>`
- Handle ALL exit codes:
  - **Exit 0 (success):** continue to Step 1.2.4
  - **Exit 2 (conflict):** create work worktree from default branch directly, leave session worktree as-is. Warn: "Session worktree session-xxx has merge conflicts with main. Work worktree created from main. Resolve session-xxx separately via `/do:start`."
  - **Exit 3 (retry exhaustion):** fall back to working inside session worktree, warn about index.lock
  - **Exit 4 (dirty main):** fall back to working inside session worktree, warn about uncommitted main changes
  - **Exit 5 (file overlap):** fall back to working inside session worktree, warn about overlapping files
  - **Exit 1 (other error):** fall back, warn

**Step 1.2.4 — Remove session worktree (defensive only):** [red-team--openai, re-check reviewer: session-merge.sh is primary owner of removal + metadata cleanup on exit 0]
- session-merge.sh (Step 2) is the primary owner of worktree removal and metadata cleanup on exit 0. Step 1.2.4 is purely defensive — it catches cases where session-merge.sh's cleanup was incomplete.
- Check if worktree still exists: `ls -d .worktrees/session-xxx 2>/dev/null`
- If worktree exists: `bd worktree remove .worktrees/session-xxx` (NO `--force`). If removal fails: warn, continue.
- If worktree already removed by session-merge.sh: no-op.
- Check if metadata still exists: `ls -d .worktrees/.metadata/session-xxx 2>/dev/null`
- If metadata exists: `rm -rf .worktrees/.metadata/session-xxx`. If already removed: no-op.

**Step 1.2.5 — Create work worktree:**
- `bd worktree create .worktrees/work-<task-name>`
- `cd` into work worktree
- Create `.workflows/.work-in-progress.d/$RUN_ID` sentinel (fresh — `.workflows/` is per-worktree, gitignored)
- Continue to Phase 1.3

- [ ] Rewrite Phase 1.2 section in SKILL.md
- [ ] Add all 5 exit code handlers (including 3 and 5, per specflow IQ1)
- [ ] Add refined self-removal PID check (CQ2 fix)
- [ ] Remove old "if in session worktree, work directly" behavior
- [ ] Test: clean session worktree → smooth transition
- [ ] Test: dirty session worktree → commit-or-discard prompt
- [ ] Test: merge conflict → work worktree from main, session worktree preserved
- [ ] Test: concurrent session PID alive → blocks transition
- [ ] Test: PID mismatch warning

### Step 7: Update `/do:compact-prep` + AGENTS.md + `/do:setup`

*Merged from original Steps 7, 8, 9 — all are small, related changes.* [red-team--opus minor triage #3]

#### 7a: `/do:compact-prep` Step 4.5 — metadata cleanup

**File:** `plugins/compound-workflows/skills/do-compact-prep/SKILL.md`

Small addition after successful merge in Step 4.5.4 (exit 0 path):

- [ ] Add `rm -rf .worktrees/.metadata/<session-name>` after worktree removal
- [ ] Add same cleanup to the exit 2 (conflict) auto-resolution path in abandon mode (after `git commit --no-edit`)

#### 7b: AGENTS.md — Session Worktree Isolation section

**File:** `AGENTS.md`

Rewrite the `## Session Worktree Isolation` section to reflect the new design:

**Replacement text** (replaces the entire `## Session Worktree Isolation` section in AGENTS.md):

```markdown
## Session Worktree Isolation

**The SessionStart hook creates a session worktree automatically.** Your first action must be
`cd <path>` using the absolute path from the hook output. Do not read files, run commands, or
respond to the user before cd'ing into the worktree.

- The hook creates `.worktrees/session-<id>` and writes a PID file for concurrent-session protection
- If the hook reports existing worktrees and suggests `/do:start`, auto-invoke `/do:start` —
  the user can say "skip" to bypass
- If the hook didn't fire (not registered, bd unavailable, or settings misconfigured), create a
  worktree manually: `bd worktree create .worktrees/session-<name>` and `cd` into it
- If `/do:start` is unavailable (plugin not installed), manage worktrees manually via direct
  `bd` commands
- User can say "stay on main" / "skip worktree" to opt out — remove the hook-created worktree
  with `bd worktree remove` and create the `.worktrees/.opted-out` sentinel:
  `touch .worktrees/.opted-out`
- **After resume, do not trust your memory about CWD** — session exit resets CWD to the repo
  root. Run `pwd` to verify, and `cd` into the worktree if needed.
- If you're already in a worktree (post-compact resume), skip — you're already isolated
- If you pick a different worktree than the hook recommended, clean up the stale PID:
  `rm -f .worktrees/.metadata/<hook-recommended-name>/pid.<your-claude-pid>`
- If `bd worktree create` fails, warn the user and proceed on main
- At session end, `/do:compact-prep` merges back to the default branch
- Before committing, if session_worktree is enabled and you're NOT in a worktree,
  warn the user: "You're committing to main without worktree isolation. Continue?"

**Beads database (.beads/) is shared across all sessions.** Worktree isolation covers git state
only. Bead operations are concurrency-safe at the SQL level (Dolt) but not coordination-safe
at the business logic level.
```

- [ ] Replace the `## Session Worktree Isolation` section in AGENTS.md with the text above
- [ ] Verify the replacement preserves all existing guidance (CWD trust, resume, bd unavailable, beads shared)

#### 7c: `/do:setup` — config and template registration

**File:** `plugins/compound-workflows/skills/do-setup/SKILL.md`

- [ ] **Hook installation step:** Find the step that copies `session-worktree.sh` template to `.claude/hooks/` (search for `session-worktree` in the file). Update to use new v3.0.0 template. Version comparison triggers reinstall.
- [ ] **Pre-commit hook installation step:** Find the step that installs `pre-commit-worktree-check.sh` (search for `pre-commit` in the file). Update template to v2.0.0. Same three installation scenarios (no existing, existing with check, existing without check).
- [ ] **AGENTS.md injection step:** Find the step that writes the `Session Worktree Isolation` block into AGENTS.md (search for `Session Worktree Isolation` in the file). Update injection text to match Step 8's replacement text.
- [ ] **New config key:** Add `session_worktree_stale_minutes: 60` to `compound-workflows.local.md` template (Decision 4).
- [ ] Register `/do:start` in setup's skill inventory display (informational — skills auto-register via plugin.json).

### Step 8: Plugin QA + version bump

- [ ] Run full Tier 1 QA scripts (all 9)
- [ ] Run Tier 2 semantic agents (all 3)
- [ ] Fix any findings
- [ ] Bump version in `plugins/compound-workflows/.claude-plugin/plugin.json`
- [ ] Bump version in `.claude-plugin/marketplace.json`
- [ ] Update `plugins/compound-workflows/CHANGELOG.md`
- [ ] Update component counts in `plugins/compound-workflows/README.md` (new skill, new script)
- [ ] Update component counts in `plugins/compound-workflows/CLAUDE.md`

**Version:** This is a MINOR bump (new skill `/do:start`, new script, significant enhancements to existing hooks). Not MAJOR because hook delivery mechanism (stdout + exit 0) and config schema are backward compatible. Suggest: v3.4.0.

**Note:** Template versions (v3.0.0 for hook, v2.0.0 for pre-commit) are internal to the templates and independent of the plugin version.

## Refined Decision 9 Algorithm

The combined PID + state cleanup algorithm, with CQ1 and CQ2 fixes applied. ALL deletion paths (hook GC, `/do:start`, `/do:work`, abandon) MUST use this algorithm.

```
cleanup_worktree(worktree_name, caller_pid):
  0. Acquire GC lock: mkdir .worktrees/.gc-lock 2>/dev/null || return SKIP ("another GC in progress")
     [red-team--openai: TOCTOU mitigation via atomic mkdir]
  1. Glob: .worktrees/.metadata/<worktree_name>/pid.*
  2. For each pid file:
     a. Read PID from file
     b. If PID == caller_pid: mark as "self" (skip liveness check for this one)
     c. If PID != caller_pid: run kill -0 <PID>
        - If alive: RETURN SKIP ("another session active: PID <PID>")
        - If dead: rm <pid-file> (prune dead PID, per specflow IQ3)
  3. State checks (only reached if no other live PIDs):
     a. git -C <worktree> status --porcelain --untracked-files=no
        - If output: RETURN SKIP + WARN ("uncommitted tracked changes")
     b. branch=$(git -C <worktree> rev-parse --abbrev-ref HEAD)
        git log <default-branch>..$branch --oneline
        - If output: RETURN SKIP + WARN ("unmerged commits")
     c. Both clean: RETURN DELETE
  4. On DELETE:
     - bd worktree remove .worktrees/<worktree_name>  (NO --force)
     - rm -rf .worktrees/.metadata/<worktree_name>
  5. Release GC lock: rmdir .worktrees/.gc-lock
```

**Self-removal exception (CQ2 fix):** Step 2b — own PID is skipped in liveness check but other PIDs are still checked. This closes the concurrent-session hole while allowing `/do:work` and compact-prep to remove their own worktrees.

**caller_pid source:**
- Hook: `$PPID` (Claude Code process, verified)
- Model (via /do:start, /do:work): captured via `echo $PPID` in a separate Bash tool call (CQ1 fix)

## Pre-Commit Hook Error Path (specflow E1)

When the model never `cd`s into the hook-created worktree (#31872 risk), the pre-commit hook catches commits to main. The error message must guide the user to recovery:

```
Error: Committing to main while managed worktrees exist.
Found: session-a7f2 (5 min ago, 0 uncommitted)
Either:
  1. cd .worktrees/session-a7f2    (use the existing worktree)
  2. touch .worktrees/.opted-out   (allow main commits this session)
```

## Acceptance Criteria

- [ ] Fresh session with no worktrees → worktree created deterministically by hook, model only needs to `cd`
- [ ] Resume session with existing worktree → hook reports state, model resumes or invokes `/do:start`
- [ ] Concurrent sessions → per-claimant PID files prevent cross-session deletion
- [ ] Crashed session → orphan detected by next session's hook GC, cleaned if safe
- [ ] `/do:start` interactive mode → table of all worktrees with status, single AskUserQuestion
- [ ] `/do:start cleanup` → applies Decision 9 to all worktrees, reports results
- [ ] `/do:start rename` → preserves commit hashes, updates PID metadata
- [ ] `/do:work` transition → session worktree merged, removed, work worktree created
- [ ] Pre-commit hook → blocks main commits when managed worktrees exist, allows with sentinel
- [ ] User opt-out → sentinel created, pre-commit allows, cleaned up next session
- [ ] All plugin QA passes (Tier 1 + Tier 2)

## Inherited Risks

| Risk | Source | Mitigation |
|------|--------|------------|
| Model ignores `cd` instruction (#31872) | Upstream Claude Code | Pre-commit hook catches commits to main. Error message guides to worktree or sentinel. Hook emits deterministic fallback commands (not just `/do:start` suggestion). [red-team--openai] |
| Model doesn't auto-invoke `/do:start` | #31872 + model compliance | AGENTS.md fallback: manual `bd` commands. Hook provides full context AND specific `cd` commands in output so user can act without model compliance. [red-team--openai] |
| `$PPID` changes meaning in future Claude Code versions | Process tree assumption | `write-session-pid.sh` takes PID as argument — easily adapted. Validated empirically during planning (2026-03-16). |
| TOCTOU race in cleanup algorithm | Non-atomic check-then-delete | `session-gc.sh` uses `mkdir .worktrees/.gc-lock` as atomic test-and-set before cleanup operations. If lock exists, skip GC (another session is cleaning). Lock removed after GC completes. [red-team--openai] |
| `stat -f` syntax is macOS-only | Cross-platform gap | Cross-platform wrapper: `stat -f '%m' 2>/dev/null \|\| stat -c '%Y' 2>/dev/null`. Skip freshness if neither works. [red-team--gemini, red-team--opus] |
| Hook latency from git operations | Synchronous SessionStart hook | GC loop (session-gc.sh) processes max 5 worktrees per invocation. Typical: 0-2. [red-team--gemini] |
| `bd worktree` command changes | External dependency | bd is versioned. If commands change, hook fails fast (non-zero exit) → falls back to model creation. |

## Dependency Graph

```
Step 0 ($PPID validation) ── DONE (validated during planning)
  ↓
Step 1 (write-session-pid.sh + session-gc.sh)
  ↓
Step 2 (session-merge.sh + /do:merge) ────────────────────┐
  ↓                                                        │
Step 3 (hook template) ──┐                                 │
  ↓                      │ parallel                        │
Step 4 (pre-commit)  ────┘                                 │
  ↓                                                        │
Step 5 (/do:start) ───────────────────────────────────┐    │
  ↓                                                   │    │
Step 6 (/do:work) ────────────────────────────────────│────│
  ↓                                                   │    │
Step 7 (compact-prep + AGENTS.md + /do:setup) ─ depends on 3,4,5
  ↓
Step 8 (QA + version) ─── depends on all changes complete
```

Steps 3+4 can run in parallel. Step 7 waits for Steps 3, 4, and 5. Step 8 is always last. [red-team--opus minor triage: Steps 7/8/9 merged into Step 7]

**Red team MINOR triage:** **Fixed (batch):** 1 MINOR red team fix applied (stat syntax consistency). **Acknowledged (batch):** 3 MINOR red team findings, no action needed. **Manual review resolved:** 3 items — staged rollout disagreed (ship all at once), step consolidation applied, /do:merge metadata added. [see .workflows/plan-research/session-worktree-start-flow/minor-triage-redteam.md]

## Work Readiness Notes

- **Steps 3 and 5 are the largest** (hook rewrite ~200+ lines, /do:start skill ~150+ lines). Consider splitting each into sub-steps during `/do:work` setup.
- **Steps 2 and 7 are very small** (1-3 line additions each). Could be combined with adjacent steps.
- **Step 9 (/do:setup) modifies an already-large skill file.** Surgical edits to specific step numbers — provide exact section references to the subagent.
- **Learnings note:** Subagents cannot write to `.claude/hooks/` — hook installation steps in Step 9 must be validated carefully. The `/do:setup` skill handles hook installation in the main orchestrator context (already correct).
- **Learnings note:** Deepen-plan recommended for this scope (6+ files across infrastructure boundaries). Run before `/do:work`.

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-03-15-session-worktree-start-flow-brainstorm.md` — 11 Decisions (D1: deterministic hook, D2: random naming, D3: mtime freshness, D4: smart heuristic, D5: /do:start scope, D6: auto-invoke, D7: metadata outside worktree, D8: /do:work transition, D9: combined PID+state cleanup, D10: pre-commit reality check, D11: git plumbing detection), 23 Resolved Questions, 12 Inherited Assumptions (3 verified, 1 falsified)
- **Research files:** `.workflows/plan-research/session-worktree-start-flow/agents/` (repo-research.md, learnings.md, specflow.md)
- **v2 plan (completed):** `docs/plans/2026-03-15-fix-worktree-session-isolation-v2-plan.md`
- **Related solutions:** Framing bias in mechanism enumeration (2026-03-15), JSONL cross-session forensics (2026-03-16), assumption verification enforcement (2026-03-16), static rules suppress bash heuristics (2026-03-10), script-file shell substitution bypass (2026-03-11)
- **Upstream issues:** #31872 (model compliance in worktrees), #31969 (no ResumeWorktree), #29110 (agent worktree data loss), #26725 (stale worktree orphans)
