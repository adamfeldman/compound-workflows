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

### Step -1: `.workflows/` Root Resolution (Architectural Fix) [red-team--opus U1/M1: prerequisite must be a numbered step]

**Problem:** `.workflows/` is gitignored and per-worktree. When worktrees are removed (GC, `/do:work` transition, compact-prep merge), all `.workflows/` content is silently destroyed — research artifacts, agent outputs, stats, synthesis files. This contradicts the plugin's "diagnosable AI mistakes" design philosophy and creates dead reference links in plans and solutions. [specflow P1-25/3/13, deepen-plan run 1]

**Fix:** All skills must write `.workflows/` to the **main repo root**, not the current worktree. Implementation:
1. `init-values.sh` adds `compute_main_root()` using `git worktree list --porcelain | head -1 | sed 's/^worktree //'`. New output key: `WORKFLOWS_ROOT=<main-root>/.workflows`. Existing `STATS_FILE` and all `.workflows/`-referencing keys switch from `$(compute_repo_root)` to `$(compute_main_root)`. `REPO_ROOT` continues using `compute_repo_root()` for non-`.workflows/` purposes. [specflow pass 2, NEW-4]
2. All skills use `$WORKFLOWS_ROOT/<command>/...` instead of relative `.workflows/<command>/...`
3. Since `.workflows/` is at the main repo root (shared across all worktrees), artifacts survive worktree lifecycle transitions

**Exception: `.work-in-progress.d/` remains per-worktree.** The `/do:work` sentinel at `.workflows/.work-in-progress.d/$RUN_ID` is an ephemeral gate, not a diagnostic artifact. It must be per-worktree so that: (a) the P0-12 rename guard only blocks rename of the worktree running `/do:work`, not all worktrees; (b) the PostToolUse hook QA suppression only applies in the worktree running `/do:work`; (c) stale sentinels from crashed `/do:work` don't block operations in other worktrees. `/do:work` Step 1.2.5 creates this sentinel using a relative path (CWD's `.workflows/`), not `$WORKFLOWS_ROOT`. [specflow pass 2, NEW-1]

**Scope:** This change touches `init-values.sh` and every skill that writes to `.workflows/`.

- [ ] Add `compute_main_root()` to `init-values.sh` using `git worktree list --porcelain`
- [ ] Add `WORKFLOWS_ROOT` output key to `init-values.sh`
- [ ] Update `STATS_FILE` to use `compute_main_root()` instead of `compute_repo_root()`
- [ ] Audit all skills for `.workflows/` write paths — update to use `$WORKFLOWS_ROOT`
- [ ] Add concurrency safety: include `RUN_ID` in all `.workflows/` write paths to prevent collision when two sessions run the same command/stem/date. Stats files already use date+command+stem — add RUN_ID as a suffix or namespace within the file. [red-team--opus A1: shared-mutable-state concurrency]
- [ ] Verify `.work-in-progress.d/` exception works correctly (per-worktree, not `$WORKFLOWS_ROOT`)
- [ ] Test: two concurrent sessions writing to `$WORKFLOWS_ROOT` — no file collisions

**Safety net:** session-gc.sh should also check for `.workflows/` content in worktrees before deletion. If present (legacy path or bug), SKIP + WARN: "worktree contains .workflows/ artifacts that should have been written to main repo root." This catches regressions.

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

**How it fails:** If `.worktrees/` doesn't exist, `mkdir -p` creates it. If filesystem permissions deny write, stderr shows the error with diagnostic: "Permission denied: check ownership of .worktrees/.metadata/". Callers (hook, `/do:start`) handle non-zero exit. If `.worktrees/.metadata/` exists but is corrupt (wrong permissions), `mkdir -p` retries once after attempting to fix permissions (`chmod 755 .worktrees/.metadata 2>/dev/null`). [specflow P1-19]

**Why PID is an argument, not `$PPID`:** In hook context, `$PPID` = Claude Code PID. In model Bash context, `$PPID` = ephemeral shell PID. Passing explicitly ensures consistency. (Specflow CQ1 resolution)

- [ ] Create script file with argument validation (exactly 2 args required)
- [ ] `chmod +x` in template
- [ ] Verify script works from both hook context and direct Bash invocation
- [ ] Depends on Step 0 ($PPID validation) completing first — interface may change if fallback is needed

#### Review Findings

**Critical:**
- Move `session-gc.sh` creation to Step 1 — the dependency graph says "Step 1 (write-session-pid.sh + session-gc.sh)" but the plan text puts session-gc.sh in Step 3's checklist. Step 1 should become the "shared utility scripts" step so both scripts exist before Steps 3 and 5 consume them. [architecture-strategist, pattern-recognition-specialist, context-researcher]

**Recommendations:**
- Validate argument: PID must be a positive integer (`[[ "$2" =~ ^[0-9]+$ ]]`) and worktree name must not contain path separators (`[[ "$1" != */* ]]`) for safety. [best-practices-researcher]
- Use `#!/usr/bin/env bash` + `set -euo pipefail` + version comment on line 2, consistent with existing scripts. [repo-research-analyst]
- Run `shellcheck` on both new scripts before committing — catches pipe-subshell variable loss (SC2030/SC2031) statically. [learnings-researcher]
- Use process substitution (`while IFS= read; done < <(grep ... || true)`) in session-gc.sh for loops that accumulate state from grep output. [learnings-researcher]

**Implementation Details:**
- session-gc.sh exit codes: 0 = completed (0 or more worktrees removed), 1 = error. Per-worktree results via stdout lines (one line per worktree: `REMOVED <name>`, `SKIPPED <name> <reason>`, `ERROR <name> <detail>`). [pattern-recognition-specialist]
- session-gc.sh should accept `caller_pid` as an argument (default 0) so `/do:work` can pass its own PID for the self-exclusion path. [architecture-strategist]
- Pass `DEFAULT_BRANCH` as env var from hook to session-gc.sh to avoid redundant `git symbolic-ref` call (~15ms saved). [performance-oracle]

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

#### Review Findings

**Critical:**
- Change `git worktree remove` to `bd worktree remove` in session-merge.sh — current script (line 157) uses `git worktree remove` but the plan mandates `bd worktree remove (NO --force)` for all deletion paths. `bd worktree remove` includes additional safety checks (uncommitted, unpushed, stashes). Add `git worktree remove` as fallback if bd unavailable: `bd worktree remove "$worktree_path" 2>/dev/null || git worktree remove "$worktree_path" 2>/dev/null || true`. [repo-research-analyst, data-integrity-guardian, data-migration-expert, pattern-recognition-specialist]

**Recommendations:**
- `/do:merge` is missing an exit 5 (file overlap) handler — add for consistency with `/do:compact-prep` which handles all 5 exit codes. Low risk since exit 5 is rare. [repo-research-analyst]
- Redundant metadata cleanup between session-merge.sh and its callers (compact-prep, /do:work Step 1.2.4) is intentional belt-and-suspenders — document as such, not a bug. [pattern-recognition-specialist]

### Step 3: Rewrite SessionStart hook template

**File:** `plugins/compound-workflows/templates/session-worktree.sh`

This is the largest change. The hook moves from "instruct model to create" to "create deterministically in bash."

**Hook step ordering:**

1. **Hook-1: Read config** — `session_worktree` from `compound-workflows.local.md`. Missing = silent exit 0.
2. **Hook-2: Delete sentinel** — `rm -f .worktrees/.opted-out` (tidy up from prior session)
3. **Hook-3: Worktree-in-worktree guard** — `git rev-parse --git-dir` vs `--git-common-dir` (Decision 11). If inside any worktree → emit "Already inside a worktree. Skipping session worktree creation." → exit 0.
4. **Hook-4: Self-version check** — compare installed vs template version. If stale, emit prominent warning: "UPGRADE REQUIRED: Session hook v<installed> is installed but v<template> is available. Run `/do:setup` to upgrade." Continue (don't block). [specflow P1-15]
5. **Hook-5: bd availability check** — if `bd` unavailable, warn and exit 0.
6. **Hook-6: Feature disabled path** — if `session_worktree: false`, run GC (Hook-8) then exit 0.
7. **Hook-7: Existing worktree scan** — `ls -dt .worktrees/session-*` (sorted by mtime, newest first)
   - If existing worktrees found → **existing-worktree path** (Hook-7a)
   - If no existing worktrees → **happy path** (Hook-9)
8. **Hook-8: GC merged worktrees** — loop `.worktrees/session-*` (max 5, oldest first — cap enforced to bound hook latency at ~1s worst case [red-team--openai]), apply Decision 9 combined algorithm:
   - Glob `.worktrees/.metadata/<name>/pid.*`
   - `kill -0 $(cat file)` for each — if ANY alive → skip worktree
   - If all dead: prune dead PID files (`rm` each dead `pid.*` file)
   - Check `git -C <worktree> status --porcelain --untracked-files=no` — if output → skip + warn
   - Check `git -C <worktree> ls-files --others --exclude-standard | head -1` — if output → skip + warn ("untracked files present")
   - Determine default branch: `git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||'` falling back to `main` if the symbolic ref is not set.
   - Check `git log <default-branch>..<branch> --oneline` — if output → skip + warn
   - All clean → `bd worktree remove` (NO `--force`) + `rm -rf .worktrees/.metadata/<name>`
   - Report remaining worktrees with Inspect/Merge/Discard remediation hints
   - **If any worktrees survived GC with issues** (uncommitted, unmerged, or untracked): set `GC_ISSUES=1` flag. When the final MANDATORY directive is emitted (after Hook-7a or Hook-9), merge the GC issues into a single combined directive rather than stacking two separate MANDATORYs. Example: `MANDATORY: N existing session worktrees found (M have unresolved issues). Ask the user: resume <name>, or create a new one? After cd'ing into your worktree, invoke /do:start to resolve the M worktrees with issues.` This gives the model one clear sequence: ask → cd → /do:start. [specflow pass 2, NEW-6]
   - Also scan for orphan metadata: `ls .worktrees/.metadata/session-*` dirs whose corresponding worktree does not exist on disk. If found, clean up silently (`rm -rf`) — these are harmless leaks from prior crashes. [data-integrity-guardian]
9. **Hook-9: Happy path (create worktree):**
   - Generate random 4-char hex ID via `openssl rand -hex 2 2>/dev/null || printf '%04x' $RANDOM` (fallback for environments without openssl) [red-team--openai]
   - `bd worktree create .worktrees/session-<id>`
   - If fails: retry once with new random ID
   - If both fail: emit diagnostic suggesting `git worktree add .worktrees/session-<id>` as non-bd fallback, then model creates manually → exit 0 [specflow P1-17]
   - On success: call `write-session-pid.sh session-<id> $PPID`
   - If PID write fails (non-zero exit): remove the just-created worktree (`bd worktree remove .worktrees/session-<id>`) and emit warning: "Worktree created but PID protection failed. Removed worktree for safety. Check `.worktrees/.metadata/` permissions. Model should retry: `bd worktree create .worktrees/session-<id>`" [red-team--opus: fail-closed on PID write failure, specflow P1-18]
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
- emit MANDATORY: `existing session worktree at <absolute-path>. Ask the user: resume <worktree-name>, or create a new one?` (Model cannot detect fresh vs resumed session — always ask. [specflow P1-7])

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

#### Review Findings

**Critical:**
- Backward compat for old `.session.pid` must be centralized in `session-gc.sh`, not per-caller — the compat clause is only specified for the GC path in Step 3, but `/do:start`, `/do:work` Step 1.2.2, and `/do:compact-prep` also use the Decision 9 algorithm. If compat is only in hook GC code, a v3 session running `/do:work` could delete a worktree that a concurrent v2 session is actively using (v2 wrote `.session.pid`, v3 only checks `.metadata/`). Three live worktrees exist RIGHT NOW with old-format PID files. Fix: session-gc.sh step 1 should also check `.worktrees/<name>/.session.pid` as an additional PID source. [data-migration-expert, data-integrity-guardian]
- Hook-7a PID liveness display must also check old `.session.pid` as fallback — otherwise the first v3 hook run after upgrade shows "no PID" for all existing worktrees (`.metadata/` doesn't exist yet). Cosmetic/decision-quality impact, not data loss. [data-migration-expert]

**Recommendations:**
- Drop legacy `.claude/worktrees/` migration code from v3 hook — 3 versions old, single-user plugin. Current hook has ~55 lines for this migration. [context-researcher, deployment-verification-agent, code-simplicity-reviewer]
- Hook-7a per-worktree statistics gathering (mtime, uncommitted, unmerged) could be deferred to `/do:start` where the data is actually acted upon. Hook reports existence only, reducing latency by ~25 lines and ~65ms per worktree. [code-simplicity-reviewer, performance-oracle]
- Apply "max 5" cap to Hook-7a per-worktree git operations (same as GC cap) to prevent unbounded latency if orphans accumulate beyond the GC limit. List additional worktrees by name only. [performance-oracle]
- Redundant git operations between Hook-7a and Hook-8 waste ~55-65ms per worktree (~300ms with 5 worktrees). Consider single scan pass with state reuse. Deferred: optimize if latency is a problem in practice. [performance-oracle, deepen-plan run 1]
- Buffer debug log writes when `SESSION_WORKTREE_DEBUG=1` — accumulate in bash variable, write once at hook exit. Use `$SECONDS` for timing instead of `date` subprocesses. Saves ~60ms. [performance-oracle]
- Document a 1-second latency budget for the SessionStart hook. Typical case: ~135ms. Worst case (5 worktrees): ~810ms. [performance-oracle]
- Carry forward MERGE_HEAD detection from v2 hook — power loss during `session-merge.sh` can leave partial merge state on main. [data-integrity-guardian]
- GC warning output format should reuse the v2 hook's established Inspect/Merge/Discard format. Define in `session-gc.sh` for consistency across callers. [pattern-recognition-specialist]

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
5. If none found on disk: secondary check `git worktree list --porcelain` for stale registry entries. If stale entries exist → auto-prune: `git worktree prune`, then re-check. If entries persist after prune (locked worktrees) → exit 1 (block) with message: "Stale worktree registry entries persist after prune. Investigate with `git worktree list`." Retained despite red-team--opus questioning: stale entries indicate an inconsistent git state worth blocking, even if rare. Consistent with fail-closed philosophy.
6. If none found anywhere → exit 0 (allow, no worktrees at all)
7. If managed worktrees found on disk → exit 1 (block):
   ```
   Error: Committing to main while managed worktrees exist.
   Found: session-a7f2, work-fix-login
   To move staged changes: git stash && cd .worktrees/session-a7f2 && git stash pop
   Or: touch .worktrees/.opted-out to allow main commits this session.
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

#### Review Findings

**Critical:**
- `/do:setup` Step 7l cannot upgrade pre-commit hook from v1 to v2 — the `grep -q 'session_worktree'` marker matches both versions. Add version comparison (same pattern as Step 7i uses for session hook): compare `sed -n '2s/^# pre-commit-worktree-check v//p'` against template version. [deployment-verification-agent]

**Recommendations:**
- Stale registry error message (point 5) should include remediation command: "Run `git worktree prune` to clean stale entries, then retry." [data-integrity-guardian]
- Pre-commit v2 adds ~20-45ms latency over v1's pure string operations (~5ms). Acceptable — correctness gain from git plumbing detection outweighs the increase. [performance-oracle]

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
   - PID-dead + dirty: show "resume" and "cleanup" (with warning about uncommitted/unmerged/untracked)
   - Always show "create new" and "skip" as additional options
   - **Issue surfacing:** If any worktree has unresolved issues (uncommitted, unmerged, or untracked files), display a prominent warning above the table: "⚠ N worktrees have unsaved work. Choose 'resume' to continue working, or 'cleanup' to review and resolve." The user must explicitly choose an action for each issue worktree — `/do:start` does not silently proceed past them.

3. **Execute user choice:**
   - **Resume:** `cd <absolute-path>`, one-line summary. If resuming a *different* worktree than hook recommended, clean up hook-written PID from the recommended worktree (`rm -f .worktrees/.metadata/<hook-recommended-name>/pid.<claude-pid>`).
   - **Remove:** Apply Decision 9 refined algorithm (CQ2 fix: remove own PID from glob, check remaining). If safe → `bd worktree remove` (no `--force`) + `rm -rf .worktrees/.metadata/<name>`. If blocked → explain why.
   - **Create new:** generate random ID, `bd worktree create`, capture Claude PID (`echo $PPID`), call `write-session-pid.sh <name> <pid>`, `cd` into it
   - **Skip:** clean up hook-written PID if present (`rm -f .worktrees/.metadata/<hook-recommended-name>/pid.<claude-pid>`), then exit without action

4. **PID management on switch/create:**
   - Capture Claude PID: model runs `echo $PPID` in a separate Bash call
   - Remove own PID from old worktree: `rm -f .worktrees/.metadata/<old-name>/pid.<claude-pid>`
   - Write PID to new worktree: `bash write-session-pid.sh <new-name> <claude-pid>`

5. **Delete sentinel on opt-back-in:** If `.worktrees/.opted-out` exists and user creates/resumes a worktree, delete the sentinel (specflow IQ5).

**Cleanup subcommand:**
- Re-scan worktree state
- **Skip the worktree the user is currently inside** (compare CWD against worktree paths). The user's current worktree is never a cleanup candidate — use `/do:compact-prep` for that. [specflow P1-11]
- Apply Decision 9 (via `session-gc.sh`) to each remaining worktree, passing `caller_pid` = the model's captured `$PPID` value. This ensures the current session's PID is excluded from liveness checks across all worktrees. [specflow pass 2, NEW-7]
- If Decision 9 returns SKIP with "untracked files present": present to user via AskUserQuestion — "Worktree <name> has N untracked files (list first 5). Delete anyway?" If user acknowledges, re-run cleanup for that worktree with untracked check bypassed.
- Report results: "Removed N worktrees. M retained (uncommitted/unmerged/PID alive/untracked files)."
- If all PID-alive: "All worktrees have active sessions. Nothing to clean up." (specflow S3)

**Rename subcommand:**
- Guard: must be inside a session worktree (specflow S2). Check git plumbing (Decision 11). If not in session worktree → error and exit.
- Guard: check for active `/do:work` — if `.workflows/.work-in-progress.d/` contains any sentinel files, block rename: "Work execution is in progress (run ID: <id>). Complete or abort /do:work before renaming." [specflow P0-12: rename during active /do:work causes data loss in subagent outputs]
- Check for untracked files: `git ls-files --others --exclude-standard` [red-team--gemini, red-team--opus]. If any exist, warn: "N untracked files will be lost during rename. Stage them first?" Offer to `git add <files>` before proceeding.
- Commit all uncommitted changes (including any just-staged untracked files): `git add -u && git commit -m "session checkpoint before /do:start rename to <new-name>"`
- `git branch -m <old-name> <new-name>` (preserves commit hashes). Note: `git worktree move` was investigated and rejected — it leaves `.git/worktrees/` internal metadata with the old name (brainstorm Assumption 12, verified 2026-03-16). Remove+recreate is the correct approach. [red-team--opus A4, traceability fix]
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

#### Review Findings

**Critical:**
- Rename operation has non-atomic metadata transition window — crash between `rm -rf .metadata/<old-name>` (step 6 of rename) and `write-session-pid.sh <new-name>` (step 7) leaves the worktree unprotected. Next GC may delete it. Fix: reorder to write new PID FIRST, then delete old metadata. Worst case after reorder is stale metadata (minor leak), not data loss. [data-integrity-guardian, frontend-races-reviewer]
- Rename partial failure: if `bd worktree create` fails after old worktree removal, session is stranded. Add recovery path: emit "Worktree recreation failed. Your work is safe on branch <new-name>. Recover with: bd worktree create .worktrees/<new-name>." [data-integrity-guardian, frontend-races-reviewer, architecture-strategist]

**Recommendations:**
- `/do:start` interactive mode has no non-interactive equivalent for the single-worktree case. Consider `/do:start auto` subcommand: 1 fresh worktree + same PID = resume silently; 1 stale + dead PID = create new; multiple = fall through to interactive. Avoids unnecessary AskUserQuestion on every resumed session. [agent-native-reviewer]
- Hook-7a phantom PID on opt-out: when user says "skip" after hook wrote PID to the recommended worktree, no cleanup guidance exists for the PID. Add to AGENTS.md opt-out path: `rm -f .worktrees/.metadata/<hook-recommended-name>/pid.<your-claude-pid>`. [data-integrity-guardian]
- Cleanup subcommand should call `session-gc.sh` via `${CLAUDE_SKILL_DIR}/../../scripts/session-gc.sh` path convention. [repo-research-analyst]
- `/do:start` should NOT have `disable-model-invocation: true` — it is interactive, not reference-only. Correct by omission but verify during implementation. [pattern-recognition-specialist]
- Consider adding orphan metadata sweep to `/do:start cleanup` or `session-gc.sh`: scan `.worktrees/.metadata/session-*` for directories whose worktree does not exist on disk. Delete orphan metadata. [data-integrity-guardian]

**Simplicity Note (acknowledged, not accepted):**
- code-simplicity-reviewer recommends stripping to interactive-only for v1 (no rename/status/cleanup subcommands). This was considered but the brainstorm (Decision 5) explicitly included these features, and the red team disagreed with cutting scope (S7). Proceed as planned.

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

**Step 1.2.2 — PID liveness check via session-gc.sh (CQ2 fix):**
- Capture Claude PID: `echo $PPID` in a Bash call
- Call `session-gc.sh <worktree-name> <claude-pid>` in single-worktree mode. The script handles CQ2 self-exclusion, backward compat for old PID format, PID age heuristic, and process-name verification. [specflow P1-20: centralize instead of reimplementing inline]
- If session-gc.sh returns SKIP ("another session active") → **block** with message: "Another session (PID NNN) is using this worktree. Cannot transition. Working inside session worktree."
- If own PID missing (pid.<claude-pid> does not exist in metadata): warn "PID mismatch — session PID not found in metadata. This may indicate $PPID inconsistency. Continuing with full liveness checks." Pass `caller_pid=0` to the cleanup algorithm (no self-exclusion — all PIDs are checked for liveness). If any PID alive → check if those PIDs are Claude processes via `ps -p <PID> -o args=` piped through `grep -qi claude` (uses full command line — catches `node /path/to/claude-code/...` when `comm=` would only return `node`). [specflow pass 2, NEW-2]. If none are Claude processes → present AskUserQuestion: "PID check found live processes but none are Claude sessions. These are likely recycled PIDs. Force transition? (stale PID files will be cleaned.)" If user confirms → prune all PID files and re-run cleanup. If user declines → block. If any ARE Claude processes → block (genuine concurrent session). [specflow P0-16: PID mismatch dead-end escape hatch]. If all dead → proceed to merge.
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

#### Review Findings

**Critical:**
- AskUserQuestion gates in Step 1.2.1: **Resolved — keep prompts.** User decision: the transition involves potential data loss (uncommitted changes, untracked files). The user must explicitly choose what happens to their work. AskUserQuestion stays for both tracked changes and untracked files. The "automate, don't ask" principle does not override user control over data safety. [agent-native-reviewer finding, user-decided in deepen-plan run 1, specflow P1-21]

**Recommendations:**
- Session-vs-work worktree detection: Decision 11 git plumbing (`--git-dir != --git-common-dir`) tells you IF you're in a worktree but not WHICH TYPE. Clarify that detection chain is: (1) plumbing confirms "in a worktree", then (2) path or branch-name prefix matching (`session-*` vs `work-*`) determines type. [schema-drift-detector]
- PID mismatch warning (Step 1.2.2 `caller_pid=0`) should explain safety to user: "Proceeding with full liveness checks (safe). If ALL PIDs are dead, transition will continue." Currently the warning may alarm users unnecessarily. [data-integrity-guardian]
- PID mismatch dead-end: if the current session wrote a PID under a different value than `$PPID` returns, and that old PID is still alive, the algorithm blocks permanently with no escape. Add escape hatch: AskUserQuestion to force-proceed with user confirmation. [frontend-races-reviewer]
- Exit code handling simplification: exits 1, 3, 4, 5 all have the same fallback (work in session worktree + warn). Consider 3 handlers: success (0), conflict (2), everything else (fall back + warn with exit code). [code-simplicity-reviewer]
- Defensive Step 1.2.4 is intentional redundancy — `rm -rf` on non-existent directory is a no-op. Keep as documented. [architecture-strategist vs code-simplicity-reviewer]

### Step 7: Update `/do:compact-prep` + AGENTS.md + `/do:setup`

*Merged from original Steps 7, 8, 9 — all are small, related changes.* [red-team--opus minor triage #3]

#### 7a: `/do:compact-prep` Step 4.5 — metadata cleanup

**File:** `plugins/compound-workflows/skills/do-compact-prep/SKILL.md`

Small addition to Step 4.5:

- [ ] **Pre-merge gate (before calling session-merge.sh):** Run the first 3 checks from the standardized state-check pattern on the session worktree: (1) tracked changes, (2) untracked files, (3) `.workflows/` artifacts. If untracked files or `.workflows/` artifacts found, warn user via AskUserQuestion before proceeding. Tracked changes are already handled by compact-prep's commit step. [specflow pass 2, NEW-3]
- [ ] Add `rm -rf .worktrees/.metadata/<session-name>` after worktree removal (exit 0 path)
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
- **If the hook emits a MANDATORY to invoke `/do:start` for unresolved issues** (GC-surviving
  worktrees with uncommitted/unmerged/untracked files), you MUST invoke `/do:start` after cd'ing
  into your worktree. Do not skip this — the user needs to decide what to do with orphan worktrees
  that have unsaved work. `/do:start` will prompt the user for each issue.
- If the hook didn't fire (not registered, bd unavailable, or settings misconfigured), create a
  worktree manually: `bd worktree create .worktrees/session-<name>` and `cd` into it
- If `/do:start` is unavailable (plugin not installed), manage worktrees manually via direct
  `bd` commands
- User can say "stay on main" / "skip worktree" to opt out — remove the hook-created worktree
  with `bd worktree remove`, clean up the hook-written PID
  (`rm -f .worktrees/.metadata/<hook-worktree-name>/pid.<your-claude-pid>`),
  and create the `.worktrees/.opted-out` sentinel: `touch .worktrees/.opted-out`
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

#### Review Findings (Step 7)

**Critical:**
- `/do:setup` Step 8c cannot upgrade AGENTS.md from v2 to v3 — current migration detection checks for `EnterWorktree` (v1 marker) and skips everything else as "already v2 or user-customized." After Step 7b updates AGENTS.md to v3, re-running `/do:setup` on a v2 install will NOT upgrade. Fix: add v2 detection marker (`bd worktree create .worktrees/session-<name>` — the v2 primary instruction that v3 removes). Detection chain: v1 = `EnterWorktree`, v2 = `bd worktree create`, v3 = `hook creates a session worktree automatically`, else = user-customized (skip with warning). [deployment-verification-agent, repo-research-analyst]

**Recommendations:**
- Step 7c line 442 references "Step 8's replacement text" but should say "Step 7b's replacement text" — numbering error from pre-merge step numbering. [pattern-recognition-specialist]
- Add `session_worktree_stale_minutes` to `/do:setup` Step 8d's migration table (alongside the 6 existing keys). Default: 60. [deployment-verification-agent, repo-research-analyst]
- Add `session_worktree_stale_minutes` to CLAUDE.md config key list and document which skills read it. [pattern-recognition-specialist]
- AGENTS.md v3 text is 26 lines with 11 bullet points — consider restructuring so the first 2-3 lines contain the must-do action and remaining bullets are conditional refinements. [agent-native-reviewer]
- Step 7c modifies the setup SKILL.md, which subagents CAN write to (it is inside the plugin tree, not `.claude/`). But hook installation testing requires running `/do:setup` in the orchestrator context after the step completes. Add a note. [agent-native-reviewer]

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

#### Review Findings (Step 8)

**Recommendations:**
- Verify shebang is line 1 and version comment is line 2 in all templates (no blank lines between). `/do:setup` version extraction via `sed -n '2s/^# ...'` depends on this. [pattern-recognition-specialist]
- Run `shellcheck` on `write-session-pid.sh` and `session-gc.sh` before committing. [learnings-researcher]

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
  3. State checks (only reached if no other live PIDs — ordered by most-actionable-first):
     a. branch=$(git -C <worktree> rev-parse --abbrev-ref HEAD)
        git log <default-branch>..$branch --oneline
        - If output: RETURN SKIP + WARN ("unmerged commits") — cheapest check, most common SKIP reason
     b. git -C <worktree> status --porcelain --untracked-files=no
        - If output: RETURN SKIP + WARN ("uncommitted tracked changes")
     c. git -C <worktree> ls-files --others --exclude-standard | head -1
        - If output: RETURN SKIP + WARN ("untracked files present — requires user acknowledgment")
        - Note: In hook context (non-interactive), SKIP is the only option. In /do:start cleanup (interactive), the caller presents the untracked files and asks user to acknowledge before re-running with force.
     d. Check for plugin-specific .workflows/ content (not arbitrary gitignored files):
        `ls .worktrees/<worktree_name>/.workflows/{stats,brainstorm-research,plan-research,compound-research,deepen-plan,work,compact-prep} 2>/dev/null | head -1`
        - If output: RETURN SKIP + WARN (".workflows/ artifacts present — should have been written to main repo root")
        - Note: Safety net for the architectural fix. Only fires on regressions. Check last. Scoped to known plugin directories to avoid false positives from unrelated gitignored content in `.workflows/`. [red-team--opus C3]
     e. All clean: RETURN DELETE
  4. On DELETE:
     - TOCTOU re-check: `ls .worktrees/.metadata/<worktree_name>/pid.* 2>/dev/null | wc -l` — if PID count increased since step 2, a new session claimed this worktree between check and delete. Abort deletion, RETURN SKIP ("new session claimed worktree during GC"). [specflow pass 2, NEW-8]
     - bd worktree remove .worktrees/<worktree_name>  (NO --force)
     - git branch -d <branch_name> 2>/dev/null || true  (safe delete — GC already verified branch is merged; -d fails harmlessly if tracking mismatch)
     - rm -rf .worktrees/.metadata/<worktree_name>
  5. Release GC lock: rmdir .worktrees/.gc-lock
```

**Self-removal exception (CQ2 fix):** Step 2b — own PID is skipped in liveness check but other PIDs are still checked. This closes the concurrent-session hole while allowing `/do:work` and compact-prep to remove their own worktrees.

**caller_pid source:**
- Hook: `$PPID` (Claude Code process, verified)
- Model (via /do:start, /do:work): captured via `echo $PPID` in a separate Bash tool call (CQ1 fix)

**Standardized state-check pattern** (used consistently in session-gc.sh for all callers): [specflow P1-23, order per specflow pass 2 NEW-5]
1. `git log <default>..<branch> --oneline` — unmerged commits (cheapest check, most common SKIP reason — check first)
2. `git status --porcelain --untracked-files=no` — tracked changes
3. `git ls-files --others --exclude-standard | head -1` — untracked non-ignored files
4. `ls <worktree>/.workflows/ 2>/dev/null | head -1` — gitignored .workflows/ artifacts (safety net — check last, only fires on regressions)

All four checks run in this order. First non-empty result → SKIP + WARN with the specific reason. Most-actionable reasons first so users see the primary issue, not a secondary safety-net warning.

### Review Findings

**Critical:**
- Stale GC lock permanently disables garbage collection — if the process dies between step 0 (mkdir) and step 5 (rmdir), the `.gc-lock` directory persists forever. All subsequent GC is silently skipped. Fix: (a) Add `trap 'rmdir .worktrees/.gc-lock 2>/dev/null' EXIT` in session-gc.sh immediately after lock acquisition. (b) Before `mkdir`, check mtime of existing `.gc-lock` — if >60 seconds, remove as stale and retry. The 60-second threshold provides a 6x safety margin over worst-case GC duration (~10 seconds for 5 worktrees). [best-practices-researcher, context-researcher, framework-docs-researcher, learnings-researcher, agent-native-reviewer, architecture-strategist, data-integrity-guardian, data-migration-expert, frontend-races-reviewer, performance-oracle, security-sentinel, pattern-recognition-specialist — 12 of 19 agents flagged this]
- GC lock not released on SKIP/WARN return paths — the algorithm has multiple `RETURN SKIP` paths at steps 2c, 3a, 3b. None mention releasing the lock. Since `cleanup_worktree()` processes one worktree and the caller loops, a SKIP on the first worktree blocks GC of ALL subsequent worktrees in the same invocation. The `trap EXIT` approach fixes this automatically. [frontend-races-reviewer]
- Backward compat for old `.session.pid` must be in the shared algorithm — add after step 1: "ALSO check `.worktrees/<worktree_name>/.session.pid`. If found, read PID, treat as one additional pid file in liveness check. On DELETE, also `rm -f` the old file." [data-migration-expert]

**Recommendations:**
- TOCTOU between PID check (step 2) and worktree removal (step 4): a new session can claim the worktree during the state-check window (100ms-1s). Consider re-checking PID glob immediately before `bd worktree remove` in step 4 — if new PID files appeared since step 2, abort deletion. [frontend-races-reviewer, security-sentinel]
- Consider adding untracked file check to step 3 (insert between 3a and 3b): `git ls-files --others --exclude-standard | head -1`. If output, RETURN SKIP + WARN ("untracked files present"). Prevents silent data loss of untracked work. Performance cost negligible. Currently a deliberate trade-off (`--untracked-files=no` was added in v2 to prevent false positives from build artifacts). [security-sentinel, data-integrity-guardian]
- Add orphan metadata sweep after the GC loop: scan `.worktrees/.metadata/session-*` for directories whose worktree does not exist on disk, delete them. Handles manual `git worktree remove` that skipped metadata cleanup. [data-integrity-guardian]
- PID recycling is an inherent limitation of `kill -0` — document as known limitation. The fail-closed design means false-alive is safe (skip cleanup), but internal Claude Code restarts can cause false-dead. Optional enhancement: verify process name is `claude` after successful `kill -0`. [security-sentinel]

**Simplicity Note (acknowledged, not accepted):**
- code-simplicity-reviewer recommends removing the GC lock entirely ("the algorithm is idempotent — concurrent GC runs are harmless"). However, two concurrent GC runs could both prune the same PID file and then both attempt state checks, creating a race during the multi-step PID-prune-then-state-check-then-delete sequence. The lock's value is preventing race conditions, not duplicate deletion. Keep the lock, add stale recovery.
- code-simplicity-reviewer recommends eliminating CQ2 self-removal exception ("callers delete their own pid file, then run standard algorithm"). This is a valid simplification but changes the algorithm interface and requires all callers to manage PID cleanup pre-call. The `caller_pid` parameterization is architecturally cleaner. Defer to user preference.

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
- [ ] Concurrent session integration test: two Claude Code sessions in the same repo — both trigger hook, both GC, PID files don't collide, GC lock serializes properly [red-team--opus M4]
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
| Stale GC lock blocks all future GC | Crash during GC | Add `trap EXIT` + mtime-based stale detection (>60s) to `session-gc.sh`. [deepen-plan run 1 — highest-consensus finding, 12/19 agents] |
| PID recycling false-dead | OS PID namespace reuse | Document as known limitation. Fail-closed design means false-alive is safe. Optional: verify process name after `kill -0`. [security-sentinel] |
| Rename partial failure | `bd worktree create` fails after old removal | Emit recovery instructions with branch name. Branch exists under new name. [data-integrity-guardian, frontend-races-reviewer] |

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
- **Deepen-plan run 1:** `.workflows/deepen-plan/feat-session-worktree-start-flow/agents/run-1/` (19 agents: 6 research + 13 review). Synthesis: `.workflows/deepen-plan/feat-session-worktree-start-flow/run-1-synthesis.md`
