---
title: "Session Worktree Start Flow — Hook + /do:start Redesign"
type: improvement
status: ready-for-plan
date: 2026-03-15
origin: hb4a
related:
  - docs/brainstorms/2026-03-14-session-worktree-v2-brainstorm.md
  - docs/plans/2026-03-15-fix-worktree-session-isolation-v2-plan.md
---

# Session Worktree Start Flow

## What We're Building

A layered session start system that handles worktree creation, orphan detection, and session management through four tiers:

1. **Hook** (deterministic) — creates worktree in bash for the happy path (no existing session worktrees). Reports state and suggests `/do:start` for ambiguous cases.
2. **AGENTS.md** (unconditional fallback) — standalone instructions: cd into hook-created worktree, or create one if hook didn't.
3. **`/do:start`** (user-initiated) — full session manager for edge cases: orphan cleanup, rename, switch worktrees, interactive creation.
4. **Pre-commit hook** (deterministic backstop) — blocks commits to main when session_worktree enabled.

## Why This Approach

Integration testing of v2 (v3.3.0) revealed the SessionStart hook can't handle all cases when it only *instructs* the model:

- **Model compliance is probabilistic** — "MANDATORY" wording achieves ~75% compliance (3 of 4 tested sessions). Red team consensus: a 25% failure rate for a "mandatory" safety boundary is unacceptable.
- **Can't distinguish fresh vs resumed sessions** — no session ID persists across exit/resume
- **Can't interact with the user** — fires before any model response
- **Naming requires task context** — model doesn't know the task when the hook fires
- **PID detection has multiple problems** — doesn't survive exit/resume, writes inside worktree (cleanup friction), $PPID may not be Claude Code process

**Key red team insight (all 3 providers):** The hook should *create* the worktree deterministically in bash, not *ask* the model to create it. The model only needs to `cd` — a much simpler instruction with higher compliance. This changes the hook from reporter to actor for the happy path.

**Compliance note:** The 75% figure comes from 4 integration test sessions (3 complied unprompted, 1 required user prompt). Small sample — acknowledged. But the structural argument holds: deterministic bash > probabilistic model compliance for critical state initialization, regardless of the exact compliance rate.

The v2 brainstorm (Decision 7) rejected `/do:start` and chose "hook reports, model acts." Red team findings from this brainstorm challenge that: the hook can act deterministically for the common case, and `/do:start` handles the cases the hook cannot.

**Design philosophy:** zero friction + smart defaults. Automatic for common cases, interactive only when there's genuine ambiguity.

## Key Decisions

### Decision 1: Hook CREATES worktree deterministically for happy path

**Happy path** (fresh session, no existing session worktrees):
- Hook runs `bd worktree create .worktrees/session-<random-id>` in bash
- Hook outputs: "MANDATORY: session worktree created at .worktrees/session-<id>. Your FIRST action must be `cd .worktrees/session-<id>`."
- Model only needs to `cd` — simpler, higher compliance than "create + cd"

**Ambiguous path** (existing session worktrees found):
- Hook does NOT create a new worktree
- Hook reports existing worktrees with freshness info (stat mtime) and suggests "Run `/do:start` to manage session worktrees"
- Model auto-invokes `/do:start` (user can say "skip")

**Why this reverses v2 Decision 12 ("hook reports, model acts"):** The hook-as-reporter approach has a ~25% failure rate for worktree creation. The hook-as-actor approach is 100% deterministic for the happy path. The trade-off (hook has side effects) is acceptable because: (a) worktree creation is cheap and reversible, (b) `session_worktree: false` disables the hook entirely, (c) the user opted in via `/do:setup`.

### Decision 2: Random ID naming, model/user can refine

Hook creates worktree with random short ID: `session-a7f2`, `session-x3k9`.

After `cd`, the model can note the worktree name in its response. If the user states their task, the model can mention it but does NOT rename automatically. `/do:start` can rename if the user explicitly asks.

**Rename mechanism (revised per round 2+3 red team):** (1) Commit all uncommitted changes, (2) `git branch -m <old-name> <new-name>` (preserves all commit hashes and history), (3) `bd worktree remove` the old worktree, (4) `bd worktree create` with the new name pointing to the renamed branch. Do NOT use `git worktree move` — it leaves `.git/worktrees/` internal metadata with the old name (verified empirically 2026-03-16). Do NOT use cherry-pick — it rewrites hashes, breaking bead provenance.

AGENTS.md naming guidance for manual creation (when hook doesn't fire):
- Name after the task/bead if known: `session-hb4a`, `session-fix-login`
- Use a random short ID if no task context (NOT dates, NOT "general")

### Decision 3: Filesystem mtime for freshness, PID + state for cleanup safety

**Freshness heuristic:**
- Use `stat -f '%m'` on the worktree directory (macOS) for freshness
- No explicit write needed — filesystem tracks it automatically
- Survives crashes (no compact-prep dependency)
- **Empirically verified (2026-03-16):** `git status`, `git log`, and `git branch` do NOT update directory mtime on macOS/APFS. Round 2 Opus claimed hook reads gamify mtime — **tested and disproven**. Mtime accurately reflects real file activity (edits, commits), not observations.

**PID for concurrent-session detection:**
- PID stored at `.worktrees/.metadata/session-foo.pid` (outside the worktree)
- Written by hook at session start for ALL worktrees the hook creates or recommends (not by the model — see Decision 9)
- `kill -0` check determines liveness
- **$PPID verified (2026-03-16):** In a SessionStart hook context, `$PPID` resolves to the `claude` process (confirmed via `ps -o pid,ppid,comm`). Process tree: `zsh → claude → zsh → hook`. `$PPID` is Claude Code's PID — long-lived for the session, dies when session ends. tmux/bash concern resolved: Claude is the direct parent, not tmux.

**Combined cleanup algorithm (Decision 9):** See below. PID is the first check; state-based checks are the fallback.

**Why not explicit timestamp:** Red team round 1 (all 3 providers) flagged crash case. **Why not commit timestamp:** Round 2 proposed switching to `git log -1 --format=%ct`, but round 3 found new worktrees inherit base branch age (5-minute-old worktree appears days stale). Empirical testing disproved the mtime gamification claim that motivated the switch. Mtime restored.

### Decision 4: Smart heuristic with user confirmation for existing worktrees

When existing session worktrees are found, use filesystem mtime for freshness (see Decision 3):

- **1 recent worktree** (<N minutes, configurable) → suggest resume: "Found session-foo (5 min ago). Resume or create new?"
- **1 old worktree** (>N minutes) → suggest create new: "Orphan session-foo (2 days ago). Clean up, resume, or ignore?"
- **Multiple worktrees** → list all, suggest `/do:start`

Stale threshold configurable via `session_worktree_stale_minutes` in `compound-workflows.local.md`. Default: 60.

The hook outputs the recommendation and context. The model (or `/do:start`) presents the choice to the user.

### Decision 5: /do:start is a full session manager

Scope:
- **Orphan cleanup** — list orphan worktrees, offer merge/remove/ignore
- **Rename** current worktree (`git branch -m` + remove + recreate, per Decision 2)
- **Switch** between existing worktrees
- **Show session status** — current worktree, branch, uncommitted changes, other worktrees
- **Interactive worktree creation** — ask for task name, create, cd

Not a required first step — the hook handles the happy path deterministically. `/do:start` is for when the hook detects ambiguity, or when the user wants manual control.

**Internal flow (specflow M1, resolved):**

**Entry:** Re-scan worktree state from scratch (not parse hook output — state may have changed since hook fired). `ls .worktrees/session-*` + git commands for fresh data.

**Interaction:** Single AskUserQuestion with full picture — a table of all session worktrees with status (freshness via mtime, PID liveness, uncommitted tracked-file count, unmerged commit count). User picks action per worktree. Matches compact-prep's batch prompt pattern — one decision point, all context visible. For single-worktree cases (common): same table with one row. Options: resume / clean up / create new / skip.

**Argument handling:** Optional subcommand for direct action:
- `/do:start` — interactive (full table)
- `/do:start cleanup` — skip to orphan cleanup
- `/do:start rename <new-name>` — rename current worktree
- `/do:start status` — display only, no action
No arguments = interactive. Arguments skip the menu for power users.

**PID management:** When user switches worktrees or creates a new one, `/do:start` calls `write-session-pid.sh <worktree-name>` (helper script per Decision 9). When user removes a worktree, `/do:start` applies Decision 9 algorithm (PID liveness + state check), then `bd worktree remove` + `rm -rf .worktrees/.metadata/<name>`.

**Return-to-work:** After any action that changes the active worktree (switch, create, rename), `/do:start` ends with `cd <absolute-path>` and a one-line summary: "Now in session-xxx. N uncommitted changes, M unmerged commits."

**Justification vs v2 Decision 7:** Decision 7 rejected `/do:start` because the hook was sufficient. Testing revealed: (a) the hook can't handle existing-worktree cases interactively, (b) orphan cleanup requires user choices the hook can't present, (c) rename and switch require multi-step operations better structured as a skill. The model CAN do these via direct `bd` commands, but a skill provides structure and discoverability.

### Decision 6: Hook suggests /do:start for ambiguity, model auto-invokes

When the hook detects existing worktrees, output includes: "Run `/do:start` to manage session worktrees."

AGENTS.md instructs the model to auto-invoke `/do:start` when the hook suggests it. User can say "skip" to bypass.

### Decision 7: All metadata outside worktree

PID files stored at `.worktrees/.metadata/session-foo/pid.$PPID` (per-claimant, inside a directory per worktree). No files written inside the worktree's git tree. Multiple sessions can claim the same worktree without overwriting each other's PID. Cleanup globs all `pid.*` files — if ANY PID is alive, skip. Cleanup: when `bd worktree remove` or compact-prep removes a worktree, also remove its `.metadata/` directory. `/do:start` orphan cleanup handles stale metadata.

### Decision 8: /do:work cleans up session worktree before creating work worktree

**Rationale (red team — Gemini, Opus):** Session worktrees merge at compact-prep (session end). Work worktrees merge at Phase 4 (feature completion). These are different lifecycles. Running `/do:work` inside a session worktree conflates them — compact-prep would merge mid-task. Clean transition preserves lifecycle isolation.

**Phase 1.2 transition flow (specflow M6, resolved):**

**Step 1.2.1 — Check for uncommitted changes:**
- `git status --porcelain --untracked-files=no`
- If dirty: ask user — "Session worktree has N uncommitted changes. Commit with checkpoint message, or discard?"
- If commit: `git add -A && git commit -m "session checkpoint before /do:work transition"`
- If discard: `git checkout -- .`

**Step 1.2.2 — Self-removal PID check:**
- Verify own PID file exists: `.worktrees/.metadata/session-xxx/pid.$PPID`
- If yes: skip liveness check (self-removal exception, Decision 9), proceed to merge
- If no: warn "PID mismatch — this session may not own this worktree. Continue?" (defensive, shouldn't happen in normal flow)

**Step 1.2.3 — Merge session worktree to default branch:**
- `cd` to main repo root
- Run `session-merge.sh`
- Handle exit codes:
  - **Exit 0 (success):** Continue to step 1.2.4
  - **Exit 2 (conflict):** Create work worktree from default branch directly, leave session worktree as-is. Warn: "Session worktree session-xxx has merge conflicts with main. Work worktree created from main. Resolve session-xxx separately via `/do:start`." (Item 17 — lifecycle isolation preserved)
  - **Exit 4 (dirty main):** Warn: "Main has uncommitted changes from another source. Cannot transition cleanly. Working inside session worktree." Fall back to current behavior (no transition). User resolves dirty main later.
  - **Exit 1 (other error):** Same as exit 4 — fall back, warn.

**Step 1.2.4 — Remove session worktree:**
- `bd worktree remove .worktrees/session-xxx` (no `--force` — Decision 9)
- `rm -rf .worktrees/.metadata/session-xxx`
- If removal fails: warn, continue anyway (work worktree creation is independent)

**Step 1.2.5 — Create work worktree:**
- `bd worktree create .worktrees/work-<task-name>`
- `cd` into work worktree
- Recreate `.workflows/.work-in-progress.d/$RUN_ID` sentinel (was in session worktree's tree, needs to exist in work worktree)
- Continue to Phase 1.3

### Decision 9: Combined PID + state cleanup (round 2 red team)

**Context:** Round 2 red team (all 3 providers) found that PID-only, state-only, and lockfile-only cleanup strategies each fail at least one real scenario. Combined approach handles all six:

**The algorithm (applied by ALL deletion paths — abandon, hook GC, `/do:start`, `/do:work`):**
1. Glob all PID files: `.worktrees/.metadata/session-xxx/pid.*`
2. If ANY PID file exists where `kill -0 $(cat file)` succeeds → **SKIP** (at least one session is active, never delete)
3. If PID dead or missing → check worktree state:
   a. `git -C <worktree> status --porcelain --untracked-files=no` has output → **SKIP + warn** (uncommitted changes to tracked files)
   b. Determine branch: `branch=$(git -C <worktree> rev-parse --abbrev-ref HEAD)`. Then: `git log <default-branch>..$branch --oneline` has output → **SKIP + warn** (unmerged commits)
   c. Both clean → **DELETE** (truly orphaned, all work merged)

**Why combined beats alternatives:**

| Scenario | PID-only | State-only | Combined |
|----------|----------|------------|----------|
| Active session, no changes yet | ✓ skip | ✗ DELETE | ✓ skip |
| Crashed session, uncommitted work | ambiguous | ✓ skip | ✓ skip |
| Crashed session, unmerged commits | ambiguous | ✓ skip | ✓ skip |
| Truly abandoned, all merged | ambiguous | ✓ delete | ✓ delete |
| Concurrent session just created | ✓ skip | ✗ DELETE | ✓ skip |

**Default posture: fail-closed.** No PID + clean state is the ONLY path to deletion. Any ambiguity → skip + warn. Orphan accumulation is recoverable (user runs `/do:start`). Data loss is not.

**PID writing is deterministic (hook-only), per-claimant:**
- Happy path (Step 7): `mkdir -p .worktrees/.metadata/session-xxx && echo $PPID > .worktrees/.metadata/session-xxx/pid.$PPID`
- Existing-worktree path (Step 3): same pattern, for the recommended worktree
- Per-claimant files prevent concurrent hooks from overwriting each other (round 3 finding: two hooks claiming same worktree)
- If user later switches worktrees via `/do:start`, the skill invokes a helper script (`write-session-pid.sh <worktree-name>`) that writes the PID deterministically. The model calls the script, not the write itself — avoids #31872 model-compliance risk for the write operation while accepting model-compliance for script invocation (acceptable: script call is a single Bash tool use, much simpler than constructing the mkdir+echo sequence inline).
- The model NEVER writes PIDs directly (no inline echo/mkdir) — this avoids the #31872 risk for the critical write. Script invocation is the carve-out.
- Worst case of writing PID to a worktree the user doesn't choose: false "active" signal → prevents deletion → safe side

**Self-removal exception:** When the caller's own PID file exists (`.metadata/session-xxx/pid.$PPID` matches current `$PPID`), skip the liveness check and proceed directly to state checks (step 3). This allows `/do:work` and compact-prep to remove their own session worktrees while still protecting other sessions' worktrees.

**Never use `--force` on `bd worktree remove`.** Always use the standard safety checks, which align with this algorithm (uncommitted changes, unpushed commits).

### Decision 10: Pre-commit hook checks reality, not model memory (round 2 red team)

Round 2 red team found that Item 16's `--no-verify` approach (a) contradicts the repo's own bash generation rules, (b) depends on model compliance that #31872 says is unreliable, and (c) gives an unbounded escape hatch from the only deterministic commit guard.

**Fix:** The pre-commit hook checks filesystem state, not session config alone:
- If inside a worktree → **allow** (correct state)
- If NOT inside a worktree AND `.worktrees/.opted-out` exists → **allow** (user explicitly opted out this session)
- If NOT inside a worktree AND no managed worktrees exist (`.worktrees/session-*` or `.worktrees/work-*`) → **allow** (no worktrees at all)
- If NOT inside a worktree AND managed worktrees exist AND no `.opted-out` → **block** (forgot to cd)

Sentinel lifecycle: model creates `.worktrees/.opted-out` when user says "skip worktree." Hook deletes it on next session start (Step 1, before any other checks). This is fully deterministic. No `--no-verify`. No model involvement in the pre-commit check itself.

**Edge case:** If a worktree directory is manually deleted but still registered in `git worktree list`, the filesystem glob misses it. The pre-commit hook should also run `git worktree list --porcelain` as a secondary check if the glob finds nothing — stale git worktree entries indicate an inconsistent state worth blocking on.

Round 3 red team (Gemini): without sentinel, orphans from old crashed sessions block all main commits. Round 3 (Opus): `work-*` worktrees must be included. Round 3 (OpenAI): manually-deleted worktrees still in git registry bypass the glob check.

### Decision 11: Worktree detection via git plumbing, not path heuristic (round 2 red team)

Round 2 red team (all 3 providers) found that Item 21's path-contains-`.worktrees/` check is fragile:
- Breaks if repo itself is at a path containing `.worktrees/`
- Misses Claude-native worktrees at `.claude/worktrees/`
- Breaks with symlinks or renamed directories

**Fix:** Use git plumbing: `if [ "$(git rev-parse --git-dir 2>/dev/null)" != "$(git rev-parse --git-common-dir 2>/dev/null)" ]` — this definitively detects ANY worktree regardless of path. Stderr suppressed so the hook doesn't leak errors if accidentally triggered outside a git repo (round 3, Gemini observation).

## Inherited Assumptions

Per ytlk/fyg9 framework. Unverified assumptions must be verified before implementation or get explicit user sign-off.

| # | Assumption | Status | Risk if wrong |
|---|-----------|--------|---------------|
| 1 | `bd worktree create` works in a SessionStart hook context (bash, before model starts) | **Verified (2026-03-16)** | Tested in subshell — bd worktree create succeeds. SessionStart hooks run bash scripts. |
| 2 | `stat -f '%m'` on a directory gives reliable mtime on macOS | **Assumed (standard POSIX)** | Freshness heuristic gives wrong recommendations. Low risk — well-established behavior. |
| 3 | SessionStart hook fires on BOTH new sessions AND `/resume` | **Verified (2026-03-16)** | Confirmed via `SessionStart:resume` label in system-reminder. Hook MUST check for existing worktrees before creating (Step 3 before Step 7). |
| 4 | Model complies with `cd <path>` at higher rate than `bd worktree create + cd` | **Verified (2026-03-16, n=1)** | 1/1 cd-only compliance vs 3/4 create+cd. Small sample but structurally sound — simpler instruction → higher compliance. |
| 5 | Model auto-invokes `/do:start` when hook suggests it | **Unverified — HIGH RISK per #31872** | Model ignores suggestion, user sees orphan warning but no action. GitHub #31872 shows models systematically ignore skills and CLAUDE.md rules in worktree sessions. Both the auto-invocation AND the AGENTS.md fallback may fail for the same reason. Mitigation: deterministic hook behavior (Decision 1) reduces dependency on model compliance for the happy path. Edge cases (orphans, multi-worktree) remain model-dependent and at risk. |
| 6 | `session-merge.sh` works when called from `/do:work` Phase 1.2 (not just compact-prep) | **Assumed (same script, different caller)** | Session worktree merge fails mid-workflow. Low risk — the script is caller-agnostic. |
| 7 | Random 4-char hex IDs don't collide in practice | **Assumed (65536 possibilities, <100 sessions)** | `bd worktree create` fails on name collision. Hook retries or falls back to model creation. Negligible risk. |
| 8 | `.worktrees/.metadata/` directory persists and isn't cleaned by `bd worktree` or `git worktree` | **Assumed** | Metadata lost. Low risk — files are advisory, not load-bearing. |
| 10 | `$PPID` in a SessionStart hook resolves to the Claude Code process | **Verified (2026-03-16)** | Process tree: `zsh → claude ($PPID) → zsh ($$) → hook`. `$PPID` is Claude Code's PID — long-lived for session, dies on exit. PID protection system works as designed. |
| 11 | `git status` / `git log` do NOT update directory mtime on macOS/APFS | **Verified (2026-03-16)** | Three commands tested, mtime unchanged. Mtime freshness heuristic is safe from hook-read gamification. |
| 12 | `git worktree move` leaves `.git/worktrees/` internal metadata with old name | **Verified (2026-03-16)** | Confirmed mismatch. Design uses `git branch -m` + remove/recreate instead. |
| 9 | Concurrent Claude Code sessions in the same repo don't happen | **Falsified (2026-03-16)** | Item 22 dismissed the race as "negligible, unsupported." Reproduction proved it happens in normal usage: user starts a new session while prior session's `/do:abandon` is still running cleanup. Result: `bd worktree remove --force` deleted the new session's worktree, causing data loss. Concurrent sessions MUST be treated as a supported scenario. |

**All blockers verified (2026-03-16).** Assumption 3 was corrected: SessionStart fires on both new and resumed sessions (not "does NOT fire on resume" as originally assumed). This means the existing-worktree check (Step 3) is critical — it prevents the hook from creating duplicate worktrees on resume. Assumption 9 was falsified: concurrent sessions are a real scenario, not theoretical.

## Resolved Questions

> **Provenance tags:** Each resolution is tagged with how it was decided.
> - **user-decided** — user explicitly chose this resolution during brainstorm discussion
> - **model-resolved** — model proposed, user approved as a batch
> - **specflow-default** — specflow analyzer's "assumption if unanswered" was adopted without individual discussion

### Original brainstorm session

1. **Timestamp mechanism** `[user-decided, confirmed round 3]` — Use filesystem mtime (`stat -f '%m'`) on the worktree directory. Survives crashes, no compact-prep dependency. Red team round 1: explicit timestamps break in the crash case. Round 2 proposed commit timestamps; round 3 reverted — empirical testing (2026-03-16) disproved the mtime gamification claim, and commit timestamps have a fatal flaw (new worktrees inherit base branch age).

2. **Should /do:start auto-run when hook detects ambiguity?** `[user-decided]` — Auto-invoke with opt-out. AGENTS.md instructs the model to automatically invoke `/do:start` when the hook suggests it. User can say "skip" to bypass.

3. **How does /do:start interact with /do:work?** `[user-decided]` — /do:work Phase 1.2 cleans up the session worktree (merge + remove) before creating a work worktree. Two different lifecycles, two different worktrees. Current implementation (option a: work inside session worktree) is replaced by option b.

### Specflow-resolved questions (Q1-Q3)

4. **Hook vs template divergence (specflow Q1)** `[user-decided]` — Hook is source of truth. The installed hook (`.claude/hooks/session-worktree.sh`) has the tested deterministic creation code. Plan updates the template (`plugins/compound-workflows/templates/session-worktree.sh`) to match the hook, then adds new features (mtime, metadata dir, /do:start suggestion) on top. The hook IS the experiment that proved the design. *User: "why would the hook not be the truth?" — contradicts specflow default which assumed template is truth.*

5. **Uncommitted changes during /do:work transition (specflow Q2)** `[user-decided]` — Commit-or-prompt. /do:work Phase 1.2 checks for uncommitted changes in the session worktree before merging. If found, asks user: commit (with a session-checkpoint message) or discard. NOT stash — stash lives on the worktree's branch; when the branch is deleted, stash entries become dangling objects. Commit or discard are the only safe options. *User chose option 1 and caught the stash problem: "wouldn't stash lose the changes eventually since they're not on main?"*

6. **/do:start scope (specflow Q3)** `[user-decided]` — In scope. The brainstorm designed /do:start as part of the solution. Multi-worktree and orphan cleanup flows depend on it. Deferring would leave those flows without proper implementation. *User: "why wouldn't it be in scope?" — contradicts specflow default which assumed deferred.*

### Specflow-resolved gaps (first pass)

7. **Opt-out orphan cleanup (specflow G8)** `[specflow-default]` — AGENTS.md instructs: "If the user says 'skip worktree' after the hook created one, remove it with `bd worktree remove`." Model handles cleanup inline.

8. **bd failure diagnostics (specflow G6)** `[specflow-default]` — Remove stderr suppression on `bd worktree create` call. Capture stderr to variable, include first line in fallback message so model/user can diagnose.

9. **Metadata cleanup lifecycle (specflow G16)** `[model-resolved]` — Three cleanup points: (a) session-merge.sh removes metadata after successful merge, (b) hook GC (Step 4) removes metadata for worktrees it cleans up, (c) /do:start orphan cleanup removes stale metadata. *Specflow default specified two cleanup points; model added session-merge.sh as third.*

10. **CWD after session worktree removal in /do:work (specflow G12)** `[specflow-default]` — /do:work must cd to main repo root after session-merge.sh completes, before creating work worktree. Add explicit cd step.

### Specflow-resolved gaps (second pass — all remaining)

11. **No cleanup when user says "create new" (specflow G1)** `[model-resolved]` — AGENTS.md instructs: "When the user declines an existing worktree and requests a new one, offer to clean up the declined worktree (merge or remove). If the user doesn't respond, leave it — `/do:start` or next session's hook GC will handle it." Don't auto-remove because it may have uncommitted work the user wants to preserve.

12. **CWD after resume unreliable (specflow G2)** `[model-resolved]` — Already handled by existing mechanisms. AGENTS.md says "do not trust your memory about CWD" and the hook emits the absolute path. The structural risk (model ignores hook) is the same as any instruction compliance issue. No additional mechanism needed.

13. **PID written to wrong worktree before user confirms (specflow G3)** `[user-decided, revised round 2]` — Hook writes PID for ALL worktrees it creates or recommends — never delegated to the model (Decision 9). For happy path (Step 7): hook writes PID immediately after `bd worktree create`. For existing-worktree path (Step 3): hook writes PID to the recommended worktree before emitting instructions. If user later switches via `/do:start`, the skill rewrites the PID. False "active" signal on the non-chosen worktree errs on the safe side (prevents deletion).

14. **Model auto-invocation of /do:start unverified (specflow G5)** `[model-resolved]` — Accept as unverified with documented fallback. AGENTS.md already covers the fallback (manual worktree management via direct `bd` commands). If auto-invocation proves unreliable after `/do:start` is implemented, strengthen AGENTS.md wording or add an explicit hook instruction. **Risk compounded by GitHub #31872:** models systematically ignore skills and CLAUDE.md rules in worktree sessions. Both the auto-invocation and the fallback may be unreliable. Plan should bias toward deterministic hook behavior over model compliance for critical paths.

15. **No retry on name collision (specflow G7)** `[model-resolved]` — Hook retries once with a new random ID if `bd worktree create` fails with non-zero exit. Two attempts covers collision (1 in 65536 chance) without adding a retry loop. If both fail, fall through to model-creates fallback with stderr diagnostic (per item 8).

16. **Pre-commit blocks every commit after opt-out (specflow G9/Q5)** `[user-decided, revised round 3]` — Pre-commit hook checks filesystem reality (Decision 10), with opt-out sentinel. If not inside a worktree but `.worktrees/.opted-out` exists → allow (user explicitly opted out). Sentinel created by model when user says "skip worktree" and hook-created worktree is removed. Deleted by hook on next session start (fresh state). If #31872 prevents model from creating sentinel, user can `touch .worktrees/.opted-out` manually. Round 3 red team (Gemini): without sentinel, old orphans from crashed sessions block all main commits even when user explicitly opted out.

17. **Merge conflict during /do:work transition (specflow G11)** `[user-decided, revised round 3]` — If session-merge.sh returns exit 2 (conflict) during /do:work Phase 1.2: (1) leave session worktree as-is (do not merge), (2) create work worktree branching from the default branch directly (ignoring session worktree content), (3) warn user: "Session worktree session-foo has unmerged changes. Work worktree created from main. Resolve session-foo separately via `/do:start`." This preserves Decision 8's lifecycle isolation — session content persists as a separate branch for later reconciliation. Round 3 red team (Opus, carried from Gemini R2): continuing work inside the conflicted session worktree contaminates the work lifecycle.

18. **Rename destroys uncommitted changes and loses branch history (specflow G14/G15)** `[user-decided, revised round 3]` — `/do:start` rename protocol: (1) commit all uncommitted changes with a checkpoint message, (2) `git branch -m <old-name> <new-name>` (preserves all commit hashes), (3) `bd worktree remove` old worktree, (4) `bd worktree create` new worktree pointing to renamed branch, (5) update `.worktrees/.metadata/` PID entry. Round 2 rejected cherry-pick (rewrites hashes). Round 3 rejected `git worktree move` (leaves `.git/worktrees/` internal metadata mismatched — verified empirically).

19. **Existing worktree path missing uncommitted count (specflow G17/Q8)** `[model-resolved, revised round 3]` — Add `git -C <worktree-path> status --porcelain --untracked-files=no | wc -l` to hook Step 3's output. One extra line in the system-reminder. Helps users decide resume vs create new with better information. Round 3 red team: use `--untracked-files=no` so `.DS_Store` and editor swap files don't inflate the count.

20. **Worktree deleted externally between sessions (specflow G18)** `[model-resolved]` — No special handling needed. Hook Step 3 finds no existing worktrees, falls through to Step 7, creates new one. Model adapts when it sees the new path in hook output. Conversation history referencing old name is cosmetic — no data loss risk.

21. **Hook fires when CWD is inside a worktree (specflow G19)** `[user-decided, revised round 2]` — Add guard at hook start using git plumbing (Decision 11): `if [ "$(git rev-parse --git-dir 2>/dev/null)" != "$(git rev-parse --git-common-dir 2>/dev/null)" ]` — skip creation and emit: "Already inside a worktree. Skipping session worktree creation." Round 2 red team (all 3 providers) found the path-contains-`.worktrees/` heuristic is fragile. Round 3 (Gemini): suppress stderr for non-git-repo edge case.

22. **Cross-session cleanup race (specflow G20)** `[user-decided, revised round 2]` — **UPGRADED from MINOR to SERIOUS after reproduction.** Original resolution ("accept, negligible risk") was wrong. Reproduced in session hb4a (2026-03-16): prior session's `/do:abandon` ran `bd worktree remove --force` on session-fbbb while the current session was actively using a newly-created worktree at the same path. Uncommitted edits were lost. Root cause: abandon cleanup assumes any unknown `session-*` worktree is an orphan. **Fix: Decision 9 (combined PID + state cleanup).** All deletion paths use the same algorithm: PID alive → skip; PID dead → check uncommitted/unmerged → only delete if truly clean. Never use `--force` on `bd worktree remove`. Round 2 red team validated that PID-only and state-only each fail real scenarios; only the combined approach handles all six.

23. **Mtime threshold default (specflow Q9)** `[model-resolved]` — 60 minutes, configurable via `session_worktree_stale_minutes` in `compound-workflows.local.md`. Most sessions are either < 30 min (quick task) or > 2 hours (deep work). 60 minutes bisects well. Already stated in Decision 4.

## Red Team Resolution Summary

| # | Finding | Provider(s) | Severity | Resolution |
|---|---------|-------------|----------|------------|
| 1 | Model compliance is probabilistic (~75%) | All 3 | CRITICAL | **Valid — redesigned.** Hook now creates worktree deterministically in bash. Model only needs to `cd`. |
| 2 | Reversal of v2 Decision 7 without justification | Opus | CRITICAL | **Valid — justified.** Added explicit justification in Decisions 1 and 5. Decision 7 was based on hook-as-reporter being sufficient; testing proved otherwise. |
| 3 | Timestamp heuristic fails on crash | All 3 | SERIOUS | **Valid — redesigned.** Replaced explicit timestamp with filesystem mtime. No compact-prep dependency. |
| 4 | /do:work lifecycle conflict unresolved | Opus, Gemini | SERIOUS | **Valid — resolved.** Decision 8: /do:work cleans up session worktree before creating work worktree. |
| 5 | Four-tier architecture lacks evidence | Opus | SERIOUS | **Disagree.** Three of four tiers already exist (hook, AGENTS.md, pre-commit). Only addition is /do:start. The hook's role changed (reporter → actor) but it's still the same tier. Evidence: 4 integration test sessions, 3 bugs found. |
| 6 | 1-hour threshold arbitrary | OpenAI | SERIOUS | **Valid — configurable.** `session_worktree_stale_minutes` in config. Default 60. |
| 7 | PID reuse vulnerability | OpenAI | SERIOUS | **Accepted.** PID is advisory concurrent-session warning, not a security mechanism. False positive = extra warning, not data loss. |
| 8 | "Zero friction" contradicted by interactive questions | Opus | MINOR | **Valid — noted.** Fresh sessions are zero friction (hook creates, model cd's). Questions only appear when orphans exist (ambiguity requires interaction). |
| 9 | System-reminder disclaimer not analyzed | Opus | MINOR | **Deferred.** Claude Code architecture constraint. Workaround: MANDATORY wording + deterministic hook creation reduces dependency on model reading the system-reminder. |
| 10 | Metadata cleanup lifecycle missing | Opus | MINOR | **Valid — added to Decision 7.** Cleanup on worktree removal + /do:start orphan cleanup. |
| 11 | "Do nothing + fix bugs" not considered | Opus | MINOR | **Disagree.** The hook-creates-worktree change IS a targeted bug fix — it fixes the compliance problem at the root. /do:start addresses real gaps (orphan cleanup, rename, switch). This is not scope creep. |
| 12 | Deterministic launcher alternative | OpenAI, Gemini | SERIOUS | **Adopted.** This IS Decision 1 — the hook becomes the deterministic launcher. |

## Reproduction: Cross-Session Cleanup Race (2026-03-16)

**Trigger:** Session hb4a started while prior session (2232c062) was still running `/do:abandon`.

**Timeline (reconstructed from JSONL forensics):**
1. Prior session's hook had created worktrees during integration testing, but NOT session-fbbb
2. Prior session committed `8d6505e` at 12:53:30
3. **This session started** → hook generated random ID `fbbb` → `bd worktree create .worktrees/session-fbbb` → succeeded
4. This session's model ran `cd .worktrees/session-fbbb` → began editing brainstorm file
5. **Prior session's `/do:abandon`** (still running) → `git worktree list` discovered session-fbbb → misidentified it as "orphan from this session's hook (never used)" → ran `bd worktree remove .worktrees/session-fbbb --force`
6. This session's worktree directory deleted out from under active edits → uncommitted changes lost
7. This session re-did edits on main after discovering worktree was gone

**Key evidence:** The branch `session-fbbb` has HEAD at `8d6505e` (the commit made at step 2). This proves it was created AFTER that commit — by this session's hook, not by the prior session. No `bd worktree create session-fbbb` appears in the prior session's JSONL.

**Why `--force` was used:** `bd worktree remove` has safety checks (uncommitted changes, unpushed commits) that would have caught this. But the prior session's abandon cleanup used `--force` to bypass them, because orphan worktrees from crashed sessions often have unpushed commits that should be discarded.

**Fix requirements (resolved by Decision 9):**
- All deletion paths use combined PID + state algorithm
- Never use `--force` on `bd worktree remove`
- Hook writes PID deterministically for all worktrees (not model-dependent)

**Evidentiary note (round 2 red team — Opus):** The JSONL line 11334 evidence is cited but the reader cannot independently verify. The reconstruction is based on: (a) session-fbbb branch HEAD matching post-8d6505e, proving late creation, (b) absence of `bd worktree create session-fbbb` in the prior session's JSONL, (c) presence of `bd worktree remove` in the prior session's abandon phase. The fix requirements are valid regardless of the exact timeline — `--force` on unverified worktrees is unsafe in any scenario.

## Claude Code Native Worktree Architecture

**EnterWorktree/ExitWorktree tools** (confirmed via tool schema inspection, 2026-03-16):

- **EnterWorktree** creates worktrees at `.claude/worktrees/` — different directory from our `.worktrees/`. No collision.
- **ExitWorktree** explicitly scopes: "This tool ONLY operates on worktrees created by EnterWorktree in this session. It will NOT touch: worktrees you created manually with `git worktree add`, worktrees from a previous session."
- The Agent tool's `isolation: "worktree"` mode uses the same `.claude/worktrees/` infrastructure.
- **No interaction with our worktree system.** Safe to coexist.

## Upstream Claude Code Issues (Research, 2026-03-16)

| Issue | Relevance | Impact on our design |
|-------|-----------|---------------------|
| [#26725 — Stale worktrees never cleaned up](https://github.com/anthropics/claude-code/issues/26725) | Claude Code's native `.claude/worktrees/` have the same orphan problem we're solving. No upstream GC exists. | Validates our hook GC approach. Don't depend on upstream fixing this. |
| [#29110 — Agent worktree data loss](https://github.com/anthropics/claude-code/issues/29110) | Agent `isolation: "worktree"` silently deletes worktrees with uncommitted changes. | Same class of bug as our `--force` removal. Confirms the pattern: cleanup without checking for unsaved work = data loss. |
| [#31969 — Enter/resume existing worktrees](https://github.com/anthropics/claude-code/issues/31969) | EnterWorktree only creates new worktrees; no way to re-enter existing ones across sessions. | Confirms our hook-based resume approach is the right workaround. If upstream adds ResumeWorktree, we can migrate to it. |
| [#31872 — Model ignores skills/workflows in worktrees](https://github.com/anthropics/claude-code/issues/31872) | In git worktree sessions, model stops following CLAUDE.md, skills, and workflows. | **Risk for `/do:start` and any skill invocation inside worktrees.** Plan should note as inherited limitation. May explain some of the ~25% compliance failures from v2 testing. |
| [#31896 — Disable automatic worktree creation](https://github.com/anthropics/claude-code/issues/31896) | Users want to opt out of Claude Desktop's automatic worktree creation. | Validates our `session_worktree: false` config option design. |
| [#31488 — No worktree cleanup on VS Code tab close](https://github.com/anthropics/claude-code/issues/31488) | VS Code extension doesn't clean up worktrees on tab close. | Same orphan lifecycle problem. Confirms cleanup is a cross-platform gap, not unique to our plugin. |

**Key upstream pattern:** Claude Code's own worktree implementation has the same three problems we're solving: (1) orphan accumulation, (2) unsafe cleanup with data loss, (3) no resume mechanism. Our design is ahead of upstream on all three.

**Risk from #31872:** Model behavior degradation in worktree sessions is an upstream Claude Code issue that could affect our entire design. If the model ignores skills and CLAUDE.md rules inside worktrees, then `/do:start`, `/do:work`, and all other skill invocations may be unreliable when the model is cd'd into a worktree. This is NOT something we can fix — it's a Claude Code model-level issue. Plan should document this as an inherited risk and note that deterministic bash (hooks, scripts) is more reliable than model compliance in worktree sessions.

## Concurrency Implications (round 2 red team)

Round 2 red team (Opus) found that Assumption 9 falsification only updated abandon cleanup. All components that touch worktree creation/deletion must handle concurrent sessions:

| Component | Concurrent risk | Mitigation |
|-----------|----------------|------------|
| **Hook GC (Step 4)** | Removes merged worktrees without PID check. Double-remove with concurrent session's cleanup → confusing errors. | Apply Decision 9 algorithm. GC only deletes if PID dead AND clean. |
| **Hook Step 3 (existing-worktree)** | Two concurrent sessions both claim same worktree. | Per-claimant PID files (`pid.$PPID`) — each hook writes its own file, no overwrites. Cleanup globs all claimants, skips if ANY alive. |
| **`/do:start` orphan cleanup** | Lists another session's active worktree as orphan → user removes it. | `/do:start` shows PID liveness status per worktree. Warn: "PID alive — another session may be using this." |
| **session-merge.sh** | Two sessions merge concurrently → branch deletion fails or unexpected merge state. | session-merge.sh already checks for errors. Concurrent merge produces a clear git error (branch already deleted or merge conflict). No additional mitigation needed — the error is self-explaining. |
| **`/do:work` Phase 1.2** | Transition removes session worktree while concurrent session references it. | Decision 9 algorithm: check PID before removal. Concurrent session's PID would be alive → skip. |
| **Abandon cleanup** | **The reproduced bug.** Removes another session's active worktree. | Decision 9: PID alive → never delete. Never `--force`. |

## Model Compliance Degraded Modes (#31872)

Round 2 red team (all 3 providers) found that 8 of 13 new resolutions depend on model compliance, which #31872 says may fail in worktree sessions. For each, the degraded mode if the model ignores the instruction:

| Item | Instruction | Degraded mode | Acceptable? |
|------|-------------|---------------|-------------|
| 11 | Model offers cleanup of declined worktree | Orphan persists → hook GC or `/do:start` cleans up later | **Yes** — delayed cleanup, no data loss |
| 12 | Model trusts hook CWD over memory | Model operates in wrong directory → edits wrong files → could silently merge into main | **Serious** — baseline Claude Code behavior, not unique to us. Hook emits absolute path in system-reminder (higher-trust channel than AGENTS.md). Mitigated by deterministic hook creation (model only needs to `cd`, not create). Round 3 red team (OpenAI): severity understated because wrong-directory edits propagate to main via compact-prep. |
| 13 | ~~Model writes PID~~ | ~~No PID → cleanup can't verify ownership~~ | **N/A — moved to hook** (Decision 9). Model no longer responsible. |
| 14 | Model auto-invokes `/do:start` | User sees hook warning but no action → manages worktrees manually via `bd` commands | **Yes** — manual fallback works, just less structured |
| 16 | ~~Model passes `--no-verify`~~ | ~~Every commit blocked~~ | **N/A — moved to pre-commit hook** (Decision 10). Model no longer responsible. |
| 17 | Model warns user on merge conflict | /do:work transition fails → session-merge.sh returns non-zero → /do:work detects error programmatically | **Yes** — warning is UX, error detection is deterministic |
| 18 | Model follows rename protocol | Rename fails or is skipped → model reports failure → user can retry or use manual git commands | **Yes** — user-requested operation, failure is visible |
| 19 | Model uses uncommitted count in output | Count not shown to user → user decides resume/create-new with less information | **Yes** — UX degradation only, data safe |

**Summary:** After Decisions 9 and 10, zero critical-path operations depend on model compliance. The two items that were previously dangerous (PID writing, `--no-verify`) are now handled deterministically. Remaining model-dependent items all degrade gracefully.

## Sources

- **hb4a bead** — 16 accumulated findings from v2 integration testing
- **v2 brainstorm** — `docs/brainstorms/2026-03-14-session-worktree-v2-brainstorm.md` (Decisions 7, 10, 12)
- **v2 plan** — `docs/plans/2026-03-15-fix-worktree-session-isolation-v2-plan.md` (Assumption 7)
- **ytlk** — unverified assumption enforcement gap
- **b3by** — red-team-added steps bypass specflow
- **Repo research** — `.workflows/brainstorm-research/session-worktree-start-flow/repo-research.md`
- **Context research** — `.workflows/brainstorm-research/session-worktree-start-flow/context-research.md`
- **Red team (Gemini)** — `.workflows/brainstorm-research/session-worktree-start-flow/red-team--gemini.md`
- **Red team (OpenAI)** — `.workflows/brainstorm-research/session-worktree-start-flow/red-team--openai.md`
- **Red team (Opus)** — `.workflows/brainstorm-research/session-worktree-start-flow/red-team--opus.md`
- **GitHub issues** — system-reminder "may or may not be relevant" disclaimer undermines hook compliance
- **JSONL forensics** — session 2232c062 line 11334 (`bd worktree remove --force`), root cause of cross-session race
- **EnterWorktree/ExitWorktree tool schemas** — confirmed `.claude/worktrees/` path, no collision with `.worktrees/`
- **GitHub #26725** — upstream stale worktree orphan problem (validates our GC approach)
- **GitHub #29110** — upstream agent worktree data loss (same class as our `--force` bug)
- **GitHub #31969** — upstream resume worktree gap (validates our hook-based approach)
- **GitHub #31872** — model skill/workflow degradation in worktree sessions (inherited risk)
- **Red team round 2 (Gemini)** — `.workflows/brainstorm-research/session-worktree-start-flow/revalidation/red-team--gemini.md`
- **Red team round 2 (OpenAI)** — `.workflows/brainstorm-research/session-worktree-start-flow/revalidation/red-team--openai.md`
- **Red team round 2 (Opus)** — `.workflows/brainstorm-research/session-worktree-start-flow/revalidation/red-team--opus-direct.md`
