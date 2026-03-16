---
title: "Session Worktree Start Flow — Hook + /do:start Redesign"
type: improvement
status: draft
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

After `cd`, the model can note the worktree name in its response. If the user states their task, the model can mention it but does NOT rename — renaming worktrees is destructive (requires remove + recreate). `/do:start` can rename if the user explicitly asks.

AGENTS.md naming guidance for manual creation (when hook doesn't fire):
- Name after the task/bead if known: `session-hb4a`, `session-fix-login`
- Use a random short ID if no task context (NOT dates, NOT "general")

### Decision 3: Filesystem mtime for freshness, PID for concurrency

**Replace explicit timestamp with stat mtime** on the worktree directory itself:
- `stat -f '%m' .worktrees/session-foo` (macOS) gives last-modified time
- No explicit write needed — filesystem tracks it automatically
- Survives crashes (no compact-prep dependency)
- Any git operation inside the worktree updates the directory mtime

**Keep PID for concurrent-session detection only:**
- PID stored at `.worktrees/.metadata/session-foo.pid` (outside the worktree)
- Written by hook at session start
- `kill -0` check warns about concurrent sessions
- Known limitation: $PPID may not be Claude Code process. Acceptable — PID is advisory, not blocking.

**Why not explicit timestamp:** Red team (all 3 providers) flagged that explicit timestamps break on crash because compact-prep doesn't run. Filesystem mtime doesn't have this problem — it updates on any file system activity in the worktree.

### Decision 4: Smart heuristic with user confirmation for existing worktrees

When existing session worktrees are found, use stat mtime for freshness:

- **1 recent worktree** (<N minutes, configurable) → suggest resume: "Found session-foo (5 min ago). Resume or create new?"
- **1 old worktree** (>N minutes) → suggest create new: "Orphan session-foo (2 days ago). Clean up, resume, or ignore?"
- **Multiple worktrees** → list all, suggest `/do:start`

Stale threshold configurable via `session_worktree_stale_minutes` in `compound-workflows.local.md`. Default: 60.

The hook outputs the recommendation and context. The model (or `/do:start`) presents the choice to the user.

### Decision 5: /do:start is a full session manager

Scope:
- **Orphan cleanup** — list orphan worktrees, offer merge/remove/ignore
- **Rename** current worktree (remove + recreate with new name)
- **Switch** between existing worktrees
- **Show session status** — current worktree, branch, uncommitted changes, other worktrees
- **Interactive worktree creation** — ask for task name, create, cd

Not a required first step — the hook handles the happy path deterministically. `/do:start` is for when the hook detects ambiguity, or when the user wants manual control.

**Justification vs v2 Decision 7:** Decision 7 rejected `/do:start` because the hook was sufficient. Testing revealed: (a) the hook can't handle existing-worktree cases interactively, (b) orphan cleanup requires user choices the hook can't present, (c) rename and switch require multi-step operations better structured as a skill. The model CAN do these via direct `bd` commands, but a skill provides structure and discoverability.

### Decision 6: Hook suggests /do:start for ambiguity, model auto-invokes

When the hook detects existing worktrees, output includes: "Run `/do:start` to manage session worktrees."

AGENTS.md instructs the model to auto-invoke `/do:start` when the hook suggests it. User can say "skip" to bypass.

### Decision 7: All metadata outside worktree

PID files stored at `.worktrees/.metadata/session-foo.pid`. No files written inside the worktree's git tree. Cleanup: when `bd worktree remove` or compact-prep removes a worktree, also remove its `.metadata/` entry. `/do:start` orphan cleanup handles stale metadata.

### Decision 8: /do:work cleans up session worktree before creating work worktree

When `/do:work` starts and the user is in a session worktree:
1. Merge session worktree back to default branch (via session-merge.sh)
2. Remove session worktree
3. Create work worktree with task-appropriate name

**Rationale (red team — Gemini, Opus):** Session worktrees merge at compact-prep (session end). Work worktrees merge at Phase 4 (feature completion). These are different lifecycles. Running `/do:work` inside a session worktree conflates them — compact-prep would merge mid-task. Clean transition preserves lifecycle isolation.

## Inherited Assumptions

Per ytlk/fyg9 framework. Unverified assumptions must be verified before implementation or get explicit user sign-off.

| # | Assumption | Status | Risk if wrong |
|---|-----------|--------|---------------|
| 1 | `bd worktree create` works in a SessionStart hook context (bash, before model starts) | **Verified (2026-03-16)** | Tested in subshell — bd worktree create succeeds. SessionStart hooks run bash scripts. |
| 2 | `stat -f '%m'` on a directory gives reliable mtime on macOS | **Assumed (standard POSIX)** | Freshness heuristic gives wrong recommendations. Low risk — well-established behavior. |
| 3 | SessionStart hook fires on BOTH new sessions AND `/resume` | **Verified (2026-03-16)** | Confirmed via `SessionStart:resume` label in system-reminder. Hook MUST check for existing worktrees before creating (Step 3 before Step 7). |
| 4 | Model complies with `cd <path>` at higher rate than `bd worktree create + cd` | **Verified (2026-03-16, n=1)** | 1/1 cd-only compliance vs 3/4 create+cd. Small sample but structurally sound — simpler instruction → higher compliance. |
| 5 | Model auto-invokes `/do:start` when hook suggests it | **Unverified** | Model ignores suggestion, user sees orphan warning but no action. Mitigation: AGENTS.md has fallback instructions for handling existing worktrees without `/do:start`. |
| 6 | `session-merge.sh` works when called from `/do:work` Phase 1.2 (not just compact-prep) | **Assumed (same script, different caller)** | Session worktree merge fails mid-workflow. Low risk — the script is caller-agnostic. |
| 7 | Random 4-char hex IDs don't collide in practice | **Assumed (65536 possibilities, <100 sessions)** | `bd worktree create` fails on name collision. Hook retries or falls back to model creation. Negligible risk. |
| 8 | `.worktrees/.metadata/` directory persists and isn't cleaned by `bd worktree` or `git worktree` | **Assumed** | Metadata lost. Low risk — files are advisory, not load-bearing. |

**All blockers verified (2026-03-16).** Assumption 3 was corrected: SessionStart fires on both new and resumed sessions (not "does NOT fire on resume" as originally assumed). This means the existing-worktree check (Step 3) is critical — it prevents the hook from creating duplicate worktrees on resume.

## Resolved Questions

1. **Timestamp mechanism** — Use filesystem mtime (`stat -f '%m'`) on the worktree directory, not explicit timestamp writes. Survives crashes, no compact-prep dependency. Red team finding: explicit timestamps break in the crash case (the primary orphan scenario).

2. **Should /do:start auto-run when hook detects ambiguity?** — Auto-invoke with opt-out. AGENTS.md instructs the model to automatically invoke `/do:start` when the hook suggests it. User can say "skip" to bypass.

3. **How does /do:start interact with /do:work?** — /do:work Phase 1.2 cleans up the session worktree (merge + remove) before creating a work worktree. Two different lifecycles, two different worktrees. Current implementation (option a: work inside session worktree) is replaced by option b.

### Specflow-resolved questions (Q1-Q3)

4. **Hook vs template divergence (specflow Q1)** — Hook is source of truth. The installed hook (`.claude/hooks/session-worktree.sh`) has the tested deterministic creation code. Plan updates the template (`plugins/compound-workflows/templates/session-worktree.sh`) to match the hook, then adds new features (mtime, metadata dir, /do:start suggestion) on top. The hook IS the experiment that proved the design.

5. **Uncommitted changes during /do:work transition (specflow Q2)** — Commit-or-prompt. /do:work Phase 1.2 checks for uncommitted changes in the session worktree before merging. If found, asks user: commit (with a session-checkpoint message) or discard. NOT stash — stash lives on the worktree's branch; when the branch is deleted, stash entries become dangling objects. Commit or discard are the only safe options.

6. **/do:start scope (specflow Q3)** — In scope. The brainstorm designed /do:start as part of the solution. Multi-worktree and orphan cleanup flows depend on it. Deferring would leave those flows without proper implementation.

### Specflow-resolved gaps (selected)

7. **Opt-out orphan cleanup (specflow G8)** — AGENTS.md instructs: "If the user says 'skip worktree' after the hook created one, remove it with `bd worktree remove`." Model handles cleanup inline.

8. **bd failure diagnostics (specflow G6)** — Remove stderr suppression on `bd worktree create` call. Capture stderr to variable, include first line in fallback message so model/user can diagnose.

9. **Metadata cleanup lifecycle (specflow G16)** — Three cleanup points: (a) session-merge.sh removes metadata after successful merge, (b) hook GC (Step 4) removes metadata for worktrees it cleans up, (c) /do:start orphan cleanup removes stale metadata.

10. **CWD after session worktree removal in /do:work (specflow G12)** — /do:work must cd to main repo root after session-merge.sh completes, before creating work worktree. Add explicit cd step.

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
