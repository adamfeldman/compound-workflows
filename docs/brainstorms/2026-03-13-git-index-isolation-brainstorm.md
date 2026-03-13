# Git Index Isolation — Brainstorm

**Date:** 2026-03-13
**Bead:** s7qj
**Related:** Bead 8one (usage-pipe race + work-in-progress scoping — same class of shared-state concurrency bug)

## What We're Building

A lightweight `safe-commit.sh` wrapper that commits files using a temporary `GIT_INDEX_FILE`, giving each commit operation its own private index. The shared `.git/index` is never read or written — complete isolation between concurrent sessions.

Enforcement: QA script (dev-time, scans .md and .sh files) + git pre-commit hook with env var detection (runtime).

### The Problem

Two concurrent Claude Code sessions on the same branch share a single `.git/index` (staging area). Session A stages files, Session B commits, and Session B's commit accidentally includes Session A's staged files. This was observed on 2026-03-13 when compact-prep committed `.workflows/session-analysis/extract-timings.py` from a concurrent session despite only intending to commit memory files.

Session analysis (bead 3zr) found **74 concurrent session pairs** across 87 sessions — concurrent sessions are a daily pattern, not an edge case. **40% of concurrent pairs (38 of 95) edit overlapping files**, with `memory/project.md` as the top collision file (28 pairs). This means file overlap is the norm, not an edge case.

### How It Works

```bash
safe-commit.sh -F commit-msg.txt file1.py file2.md
# OR
safe-commit.sh -m "commit message" file1.py file2.md
```

Inside the wrapper (~5 lines of core logic):
1. Create a temporary index file (`mktemp`)
2. Populate from HEAD (`GIT_INDEX_FILE=$tmp git read-tree HEAD`)
3. Stage specified files (`GIT_INDEX_FILE=$tmp git add <files>`)
4. Commit (`COMPOUND_SAFE_COMMIT=1 GIT_INDEX_FILE=$tmp git commit -F msg.txt`)
5. Clean up temp index (`rm $tmp`)

The shared `.git/index` is never touched. Each invocation gets its own private index populated from HEAD. No locks, no stash, no Python — pure bash + git.

The wrapper sets `COMPOUND_SAFE_COMMIT=1` env var so the pre-commit hook can detect compliant commits.

## Why This Approach

### Goal: Prevent via isolation, detect via enforcement

Two tiers:
- **Primary (prevention):** `GIT_INDEX_FILE` gives each commit its own private index. Sessions using the wrapper *cannot* contaminate each other, even for overlapping files.
- **Secondary (detection):** QA script catches raw `git commit` / `git add` patterns in plugin code at dev time. Git pre-commit hook warns at runtime when commits are made outside the wrapper (env var detection).

*Honest about coverage:* For plugin callsites (~6), enforcement is deterministic. For non-plugin sessions, enforcement is best-effort (AGENTS.md instructions + hook warning). The wrapper itself provides true isolation for all sessions that use it.

### Follows the "eliminate sharing" pattern

The repo has solved this class of bug twice:
1. `.usage-pipe` — **eliminated the shared file** (moved to arg passing)
2. `.work-in-progress` — **scoped per-session** (directory of per-RUN_ID files)

`GIT_INDEX_FILE` follows the same pattern: eliminate the shared index by giving each session its own. This is the strongest isolation guarantee — sessions never interact with the shared index at all.

### Why GIT_INDEX_FILE over git commit --only

Initially chose `git commit --only` (simpler — just a flag change, no wrapper). Red team v2 (all 3 providers) exposed a critical limitation: **`--only` only isolates disjoint files**. When two sessions edit the same file (e.g., `memory/project.md`), `--only` overwrites the other session's staged version in the shared index.

Empirical analysis confirmed: **40% of concurrent session pairs edit overlapping files**. `memory/project.md` alone appears in 28 of 38 overlapping pairs. `--only` is insufficient.

`GIT_INDEX_FILE` wrapper is ~5 lines of bash — far simpler than the lock-based wrapper rejected earlier (no locks, stash, Python, timeouts). The complexity objection was conflating this with the lock-based wrapper.

*User reasoning: checked overlap frequency empirically before pivoting. Data showed 40% overlap → --only insufficient → GIT_INDEX_FILE required.*

### Why not lock-based wrapper (original design, rejected in red team v1)

The initial brainstorm design used `safe-commit.sh` with Python `fcntl.flock`, stash-based recovery, and 30-second lock timeout. Red team v1 exposed fatal flaws:
- **Stash corrupts concurrent sessions** (Gemini, Opus): `git stash` modifies the working directory, not just the index
- **Lock timeout = blocking** (all 3): functionally identical to the blocking hook we rejected
- **Index surgery risks** (OpenAI, Opus): save/reset/restore doesn't preserve nuanced index states
- **Doesn't follow repo precedent** (Opus): serializes access instead of eliminating sharing

### Why not git commit --only (rejected in red team v2)

Simpler (just a flag, no wrapper) but insufficient:
- Only isolates disjoint files — overlapping files overwrite each other's staged versions
- 40% of concurrent sessions have overlapping edits (empirically verified)
- `git commit -a` in a concurrent session sweeps up intent-to-add files
- Demoted to documented alternative, not primary mechanism

### Why not a pre-commit hook as primary mechanism

Explored and rejected:
1. **Session identification is hard** — hooks don't know which session invoked `git commit`
2. **Manifest maintenance is error-prone** — LLM instructions are probabilistic
3. **Blocks instead of recovers** — hook can only reject, not fix
4. **Bypassable** — `--no-verify` skips hooks entirely

A pre-commit hook IS useful as a **warning/detection layer** (see Enforcement), just not as the primary isolation mechanism.

### Why not worktree-per-session (v1-v3 reasoning, later revisited)

Initially ruled out:
- Changes the user's mental model — they're no longer "on main"
- Heavyweight — already used for `/do:work` subagents where it makes sense
- `GIT_INDEX_FILE` provides equivalent index isolation with less overhead

**Revisited after red team v3 and simultaneous-writes analysis.** GIT_INDEX_FILE only provides *index* isolation, not *working tree* isolation. Empirical data confirmed 1.3s same-file collisions on disk. Discovery of Claude Code's native `EnterWorktree`/`ExitWorktree` tools drastically reduces implementation cost. See "Working Tree Isolation" section for the evolved design.

## Key Decisions

1. **Mechanism:** `GIT_INDEX_FILE` temporary index via `safe-commit.sh` wrapper. Each commit gets its own private index. Shared `.git/index` never touched.
2. **Scope:** ALL commit callsites — ~6 in plugin skills + AGENTS.md instructions for non-plugin commits. Migration pattern: replace `git add <files>` + `git commit -F msg.txt` with `safe-commit.sh -F msg.txt <files>`.
3. **Enforcement — QA script:** Tier 1 script scans all .md and .sh files for raw `git commit` / `git add` patterns (without the wrapper). Catches at dev time, deterministic.
4. **Enforcement — git pre-commit hook:** Wrapper sets `COMPOUND_SAFE_COMMIT=1` env var. Git pre-commit hook warns if this env var is absent (commit made outside wrapper). Real runtime detection. Installed via `/do:setup` or wrapper's first run.
5. **Coverage honesty:** Plugin callsites: deterministic enforcement. Non-plugin sessions: best-effort (AGENTS.md + hook warning). Sessions using the wrapper: true isolation regardless of enforcement.
6. **`git commit --only` as lightweight alternative:** For contexts where the wrapper isn't available (e.g., manual git usage), `git commit --only` with `--intent-to-add` for new files provides partial isolation (disjoint files only). Documented as a manual fallback, not the primary mechanism.

## Considered and Rejected

### Lock-based wrapper (v1 design, rejected red team v1)

Python `fcntl.flock` + stash-based recovery + 30s lock timeout. Fatal flaws: stash corrupts working directory, timeout = blocking, index surgery risks, doesn't follow "eliminate sharing" precedent.

### git commit --only (v2 design, rejected red team v2)

Zero-complexity flag change. But only isolates disjoint files — 40% of concurrent pairs edit overlapping files, making this insufficient. `git commit -a` also sweeps intent-to-add files.

### Locking mechanisms explored

All unnecessary with `GIT_INDEX_FILE`:
- Python `fcntl.flock` (works on macOS but adds dependency)
- bash `mkdir` lock (orphans on kill -9)
- system `flock` (not available on macOS)
- git `index.lock` (too granular, too blunt)

## Resolved Questions

1. **Callsite inventory:** ~6 callsites across 3 skills (`do-work`: 2, `do-compact-prep`: 3, `resolve-pr-parallel`: 1). Migration: replace `git add` + `git commit` with `safe-commit.sh` call.
2. **Non-plugin commits:** All Claude Code sessions via AGENTS.md instructions. *User reasoning: daily concurrent sessions, maximum protection everywhere.*
3. **Enforcement scope:** QA scans ALL file types (.md and .sh). Also scans for `git add` (not just `git commit`) — raw `git add` stages in the shared index, defeating isolation.
4. **Enforcement layers:** QA script (dev-time) + git pre-commit hook with env var detection (runtime). *User chose env var approach over PostToolUse hook for real detection capability.*
5. **Which native git mechanism?** `GIT_INDEX_FILE` (primary). Pivoted from `--only` after empirical analysis showed 40% overlapping-file frequency.
6. **Untracked file handling?** Wrapper handles via `git add` on the temp index — no special treatment needed since the temp index is private.
7. **Pre-commit hook detection:** Env var `COMPOUND_SAFE_COMMIT=1` set by wrapper. Hook checks for its presence. Real detection without needing to parse git command-line flags.
8. **Empirical verification of GIT_INDEX_FILE?** Deferred to plan phase. The `--only` tests (deleted with scratch repo) are moot. Plan should include a test matrix: concurrent overlapping-file commits, untracked file handling, post-commit shared index state, interaction with pre-commit hooks.

## Design Evolution

This brainstorm went through four major design iterations, each shaped by red team challenge and empirical analysis:

| Version | Mechanism | Status |
|---------|-----------|--------|
| v1 | Lock-based `safe-commit.sh` (Python flock, stash recovery) | Rejected — red team v1: stash corrupts WD, lock timeout = blocking, index surgery risks |
| v2 | `git commit --only` (zero tooling) | Rejected — red team v2: only isolates disjoint files, 40% concurrent pairs have overlapping edits |
| v3 | `GIT_INDEX_FILE` temp index wrapper | Valid for index isolation, insufficient for working tree (red team v3 + empirical data) |
| v4 (emerging) | Worktree-per-session via `EnterWorktree` + merge at session end | Under discussion — solves both index and working tree isolation |

## Red Team Resolution Summary

### Round 1 (pre-pivot, against lock-based design)

| Finding | Source | Severity | Resolution |
|---------|--------|----------|------------|
| Native git mechanisms not considered | All 3 | CRITICAL | **Valid — pivoted to native git.** |
| Stash corrupts concurrent sessions | Gemini, Opus | CRITICAL/SERIOUS | **Moot — no stash.** |
| AGENTS.md adoption is probabilistic | Opus, OpenAI | SERIOUS | **Valid — added enforcement layers.** |
| Lock timeout = blocking failure | All 3 | SERIOUS | **Moot — no lock.** |
| Index surgery risks | OpenAI, Opus | SERIOUS | **Moot — no index manipulation.** |
| Doesn't follow "eliminate sharing" pattern | Opus | SERIOUS | **Valid — GIT_INDEX_FILE follows the pattern.** |

### Round 2 (against git commit --only design)

| Finding | Source | Severity | Resolution |
|---------|--------|----------|------------|
| --only doesn't preserve staging for overlapping files | Opus, OpenAI | CRITICAL | **Valid — pivoted to GIT_INDEX_FILE.** 40% overlap rate confirmed empirically. |
| "Prevent without blocking" contradicts warning enforcement | Gemini, OpenAI | CRITICAL | **Valid — reframed goal.** "Prevent via isolation, detect via enforcement." |
| Pre-commit hook can't detect --only vs regular commit | Opus, Gemini | SERIOUS | **Valid — replaced with env var detection.** Wrapper sets COMPOUND_SAFE_COMMIT=1. |
| QA only covers plugin files; non-plugin is probabilistic | Opus, Gemini, OpenAI | SERIOUS | **Valid — stated honestly.** Plugin: deterministic. Non-plugin: best-effort. |
| git commit -a sweeps intent-to-add files | Opus, Gemini | SERIOUS | **Moot with GIT_INDEX_FILE** — temp index never touches shared index. |
| Migration requires removing git add too | Opus | SERIOUS | **Resolved** — wrapper replaces both git add + git commit. |
| GIT_INDEX_FILE unfairly dismissed | Gemini, OpenAI | SERIOUS | **Valid — promoted to primary.** |
| Empirical tests too narrow | Opus | MINOR | **Valid — added overlap analysis.** |
| Assumes disjoint file sets | Opus | SERIOUS | **Valid — overlap analysis disproved assumption.** |
| Fallback escalation criteria vague | Opus | MINOR | **Acknowledged — GIT_INDEX_FILE is now primary, not fallback.** |
| "Eliminate sharing" narrative inconsistent with --only | OpenAI | MINOR | **Moot — GIT_INDEX_FILE truly eliminates sharing.** |

### Round 3 (against GIT_INDEX_FILE design)

| Finding | Source | Severity | Resolution |
|---------|--------|----------|------------|
| Index isolation ≠ working tree isolation (shared working dir) | Gemini | CRITICAL | **Valid — scope expanded.** See "Open: Working Tree Isolation" below. |
| Worktree dismissal based on flawed equivalence | Gemini | CRITICAL | **Valid — reconsidering worktrees.** GIT_INDEX_FILE is NOT equivalent when files overlap on disk. |
| Pre-commit tools (husky/lint-staged) may break with GIT_INDEX_FILE | Gemini | CRITICAL | **Acknowledged — this project doesn't use them, but portability concern. Plan-phase test matrix item.** |
| "Complete isolation" unverified | OpenAI | CRITICAL | **Valid — language should be toned down to "index isolation" not "complete isolation."** |
| Wrapper only protects wrapper-using sessions | Opus, Gemini, OpenAI | SERIOUS | **Valid — highest-collision files committed by non-plugin sessions remain unprotected.** |
| Shared index staleness after wrapper commits (confusing git status) | Opus | SERIOUS | **Valid — plan must include mitigation (e.g., git read-tree HEAD after wrapper commits).** |
| Env var spoofable — LLM can set COMPOUND_SAFE_COMMIT=1 without wrapper | Opus, OpenAI | SERIOUS | **Valid — acknowledged as reminder, not enforcement.** |
| QA script can't distinguish wrapper git-add from raw git-add | Opus | SERIOUS | **Valid — needs exemption rules in QA script.** |
| Partial staging destroyed by wrapper | Gemini | SERIOUS | **Acknowledged — wrapper always stages full file. Acceptable for automated commits.** |
| Human friction — hook warns on every normal human commit | Gemini | SERIOUS | **Valid — hook needs to distinguish Claude sessions from human commits (or skip when not in Claude).** |
| Hook-mediated isolation (apply GIT_INDEX_FILE in pre-commit hook for ALL commits) not considered | Opus | SERIOUS | **Interesting alternative — not yet evaluated.** |
| Worktree commits already isolated, wrapper redundant for /do:work | Opus | MINOR | **Valid — worktree commits can be exempted.** |
| No trap cleanup for temp index on failure | Opus, OpenAI | MINOR | **Valid — add trap 'rm -f $tmp' EXIT.** |
| "No locks" ignores git's internal ref locking | Opus | MINOR | **Acknowledged — ref locking is desirable (prevents lost commits).** |

## Working Tree Isolation

**Status: Data confirms the problem. Leaning toward worktree-based isolation (option B). Design evolving.**

Red team v3 (Gemini) identified that GIT_INDEX_FILE solves **index contamination** but not **working tree conflicts** — when two sessions write different versions of the same file on disk, the temp index reads whatever's on disk (last writer wins). Scope expanded to include working tree isolation.

### Empirical Analysis: Simultaneous Disk Writes

Analyzed 93 session logs for truly simultaneous file writes (not just overlapping session windows). Full results in `.workflows/brainstorm-research/git-index-isolation/simultaneous-writes-results.md`.

**Confirmed: concurrent sessions DO write to the same file within seconds.**

| Gap | File | What happened |
|-----|------|---------------|
| **1.3s** | `memory/project.md` | Two Edit calls, 1.3s apart |
| **4.6s** | git index | `git add` in one session, `git commit` 4.6s later in another |
| **4.6s** | `.workflows/.usage-pipe` | Two Write calls |
| **5.3s** | brainstorm doc | Edit in one session, `git add` in another |

**Scale:** 14 collisions within 60s, 4 within 10s, 3 within 5s, 1 within 2s. Git index is the #1 collision target (4 of 14 sub-60s). `memory/project.md` is the #1 content file (28 of 38 overlapping pairs, 1.3s tightest gap).

**Hot file pattern:** Shared status files (`memory/project.md`, `.workflows/.usage-pipe`) and the git index attract the tightest collisions. Plugin files collide during release work.

### Two Confirmed Problems

1. **Git index contamination** — GIT_INDEX_FILE solves this completely. The 4.6s git-add→git-commit race is exactly the original bug (bead s7qj).

2. **Working tree conflicts** — The 1.3s Edit-vs-Edit on `memory/project.md` is a separate problem. Two sessions writing different content to the same file on disk. GIT_INDEX_FILE doesn't help — the second Edit either fails (old_string changed) or silently overwrites.

**Key nuance:** Worktrees don't fully solve problem #2 either. Divergent edits to `memory/project.md` still require merging. Worktrees defer the conflict from write-time to merge-time, which is safer (no silent data loss) but not zero-effort.

### Candidate Approaches

**A) GIT_INDEX_FILE only** — Solves the original bug (index contamination). Accepts working tree conflicts as a separate, rarer problem that worktrees wouldn't fully solve anyway.

**B) Worktree-based session isolation** (user's lean) — Solves both index and working tree problems. Each session operates in its own worktree with its own branch, own index, own file copies. Merges at session end.

**C) GIT_INDEX_FILE + convention for hot files** — Solves index contamination. For working tree conflicts, mitigate via convention (e.g., append-only patterns for memory/project.md, per-session scratch files that merge at session end).

User leans toward B after confirming simultaneous writes are real.

### Model Variants for Option B

Originally considered three worktree models:
1. **Every session gets a worktree** — maximum safety, merge overhead on every session. But solo-session merges are fast-forward (zero conflict, zero overhead). No detection race.
2. **Concurrent sessions only get worktrees** — targeted, but detection has its own race (two sessions starting simultaneously both think they're first, both skip worktree). Needs atomic sentinel/lock — the same class of problem we're trying to solve.
3. **GIT_INDEX_FILE for index + convention for shared files** — simpler, partial coverage.

Model 1 (always-worktree) may actually be simpler than model 2 because it avoids the detection race entirely. The merge overhead concern is mitigated by: (a) solo-session merges are fast-forward, and (b) Claude handles merge conflicts well (see below).

### Can Claude Handle Merge Conflicts?

Yes, and quite well. Assessed for this use case:

1. **Standard git conflicts** — Worktree merges produce normal `<<<<<<<` / `>>>>>>>` markers. Claude already resolves these routinely in PR workflows.
2. **Hot files are mostly additive** — `memory/project.md` conflicts are typically "both sessions appended different status updates." Easiest merge class — keep both sides. Same for CHANGELOG, brainstorm docs.
3. **Prose > code for LLM merges** — Most collision files in this repo are markdown, not code. No semantic dependency chains to reason about. The model combines two additions or picks the more complete version.
4. **Divergent rewrites are rare** — One session restructuring a section while another adds to the original structure. Based on the data, most collisions are append-style updates to status files.

### Merge Strategy

Worktree sessions merge at session end via `git merge --no-ff` so the merge commit is atomic. If it conflicts, Claude resolves before committing.

**Empirically tested: concurrent merges are safe.** Two sessions merging into main simultaneously → git's `index.lock` causes one to fail hard (`fatal: Unable to create index.lock: File exists`). The other succeeds cleanly. No data loss, no partial state, no corruption. The failing session retries and either gets a clean merge (disjoint files) or a standard conflict (overlapping files). Tested with both overlapping and disjoint file scenarios.

**No external lock needed.** Git's own ref/index locking prevents corruption. The merge step uses a retry loop:
1. Attempt `git merge --no-ff <worktree-branch>`
2. If fails with `index.lock` → wait 1-2s, retry (up to 3 attempts)
3. If merge has conflicts → Claude resolves (or asks user if non-trivial — see open question C2)
4. If succeeds → done

**Why `--no-ff`:** Creates a merge commit even for fast-forward-able branches. This preserves the worktree branch's identity in the history (visible as a topic branch) and makes the merge atomic (single commit point to revert if needed).

**Merge direction:** From main worktree, merge worktree branch into main. Explicit sequence: `ExitWorktree(keep)` → back in main → `git merge --no-ff worktree-<name>` → resolve → cleanup.

### Session UX: How to Enter/Exit Worktrees

Explored three UX models for entering worktrees at session start:

**Manual command** — User runs something like `/do:session-open` each time. Also needed after compact (which effectively restarts context). High friction.

**SessionStart hook** — Hook in `.claude/settings.json` auto-runs on session start. Can create worktree and output instructions, but **cannot change the session's working directory** (hooks run as subprocesses). The hook could create the worktree but the model would still need to `cd` into it — fragile, depends on model compliance.

**Native `EnterWorktree` tool** — Claude Code has built-in `EnterWorktree` / `ExitWorktree` tools (discovered during this brainstorm). These solve the hard problems:

### Discovery: Claude Code Native Worktree Tools

Claude Code provides `EnterWorktree` and `ExitWorktree` as built-in tools.

**`EnterWorktree`:**
- Creates a git worktree inside `.claude/worktrees/` with a new branch based on HEAD
- **Switches the session's working directory** to the worktree — solves the "hook can't cd" problem
- Session-scoped — only tracks worktrees created in the current session
- Accepts optional `name` parameter

**`ExitWorktree`:**
- Returns to the original working directory
- **Clears CWD-dependent caches** — system prompt sections, memory files, plans directory are refreshed from the original directory. This means AGENTS.md, CLAUDE.md, memory files are re-read after merge.
- Actions: `keep` (leave worktree on disk) or `remove` (delete worktree + branch)
- Safety: refuses to remove if there are uncommitted changes or unmerged commits (unless `discard_changes: true`)

**This changes the design significantly.** The plugin's role shrinks from "build worktree management" to "build a thin orchestration layer on top of existing tools":
1. **Detect concurrency** — SessionStart hook checks for a sentinel, instructs the model to call `EnterWorktree`
2. **Merge at session end** — compact-prep/abandon calls `ExitWorktree(action: "keep")`, then `git merge --no-ff <worktree-branch>` from main, resolves conflicts, cleans up
3. **Worktree lifecycle handled by Claude Code** — not custom scripts

**Staleness concern addressed:** `ExitWorktree` explicitly refreshes the session's view of CLAUDE.md, memory, etc. from the original directory. The merge-then-refresh flow means the session picks up any changes from the other session's merged work.

### Discovery: `bd worktree` (Beads Worktree Tool)

Beads has its own worktree management (`bd worktree create/list/remove/info`). Key differences from `EnterWorktree`:

| | `EnterWorktree` (Claude Code native) | `bd worktree` (beads) |
|--|--|--|
| **Location** | `.claude/worktrees/` | `./<name>` or custom path |
| **Session integration** | Switches session CWD, refreshes caches on exit | No session awareness — just creates a directory |
| **Beads DB** | No beads awareness | Sets up `.beads/redirect` so all worktrees share the same beads DB |
| **Cleanup** | ExitWorktree with session-scoped safety checks | `bd worktree remove` with safety checks |
| **Branch** | Auto-creates branch from HEAD | User specifies branch name |

**These are complementary, not competing:**
- `EnterWorktree` handles the **session** side — CWD switching, cache refresh, session-scoped lifecycle
- `bd worktree` handles the **beads** side — ensuring the worktree can read/write the same issue database

**Resolved: `bd` auto-discovers the beads DB from an `EnterWorktree`-created worktree.** Tested empirically — created a worktree via `EnterWorktree`, ran `bd worktree info` (detected worktree, reported "Beads: local (no redirect)"), `bd show` (read successfully), and `bd create` + `bd close` (write successfully). No `.beads/redirect` needed. `bd` follows the git worktree link back to the main repo's `.beads/` directory automatically.

This means `EnterWorktree` alone is sufficient — no need to also run `bd worktree create` or manually set up a redirect. The two tools are complementary but `bd worktree create` is not required for beads access.

### Staleness Analysis: What's Invisible Across Worktrees?

When sessions run in separate worktrees, changes in one are invisible to the other until merge. Impact assessment:

| Resource | Staleness risk | Frequency of cross-session reads | Impact |
|----------|---------------|----------------------------------|--------|
| **AGENTS.md / CLAUDE.md** | Low — changes rarely (weekly) | Read at session start | Low — already stale-by-design (loaded once) |
| **Memory files** | Low — captured at session end usually | Read at session start | Low |
| **`memory/project.md`** | Medium — both sessions update as status tracker | Mid-session reads uncommon | Low in practice — sessions read at start, write at end |
| **Plans / brainstorms** | Low — single-session workflows | Rare | Low |
| **Plugin files** | Low — only during release work | Rare | Low |

**Conclusion:** Staleness cost is low for the current workflow. The main risk — Session A captures a critical learning, Session B makes the wrong call because it doesn't see it — is real but infrequent. The merge-then-ExitWorktree-refresh flow addresses this at session end.

### Relationship to GIT_INDEX_FILE Wrapper

If worktrees are adopted, the `safe-commit.sh` wrapper becomes:
- **Redundant for worktree sessions** — each worktree has its own index natively
- **Still valuable for non-worktree contexts** — non-plugin sessions, manual commits, sessions that skip the worktree flow
- **Defense in depth** — even in a worktree, the wrapper's explicit file listing prevents accidental inclusion of unstaged files from the worktree's own index

The GIT_INDEX_FILE wrapper design (sections above) remains valid as a fallback/defense-in-depth layer. The worktree is the primary isolation mechanism; the wrapper is secondary.

### Design Evolution (Updated)

| Version | Mechanism | Status |
|---------|-----------|--------|
| v1 | Lock-based `safe-commit.sh` (Python flock, stash recovery) | Rejected — red team v1: stash corrupts WD, lock timeout = blocking |
| v2 | `git commit --only` (zero tooling) | Rejected — red team v2: only isolates disjoint files, 40% overlap |
| v3 | `GIT_INDEX_FILE` temp index wrapper | Valid for index isolation, insufficient for working tree |
| v4 (emerging) | Worktree-per-session via `EnterWorktree` + merge at session end | Under discussion — solves both index and working tree isolation |

### v3 Red Team SERIOUS Findings — Final Triage

Triaged against v4 (worktree-per-session) direction:

| Finding | Source | v4 Status | Resolution |
|---------|--------|-----------|------------|
| Shared index staleness (confusing git status after wrapper commits) | Opus S2 | **Moot** | Each worktree has its own index natively. No temp index, no staleness. |
| QA script false positives (can't distinguish wrapper git-add from raw) | Opus S4 | **Reduced scope** | Raw `git add` in a worktree is fine (isolated index). QA only needs to flag raw git operations in non-worktree contexts. Simpler rule. |
| Partial staging destroyed (wrapper stages full file) | Gemini S5 | **Moot** | Normal `git add` works fine in an isolated worktree. No wrapper needed for worktree sessions. |
| Human friction (hook warns on every human commit) | Gemini S6 | **Still relevant** | If env var hook kept as defense-in-depth, it fires on human commits too. Fix: hook checks if running inside a Claude Code session (env var guard) and skips warning for human commits. |
| Hook-mediated isolation (apply GIT_INDEX_FILE in pre-commit hook for ALL commits) | Opus S9 | **Optional** | Interesting for non-worktree fallback — hook could transparently apply GIT_INDEX_FILE to any commit outside a worktree. But complex (hook re-execs commit with temp index) and probably over-engineering given worktrees are primary. Noted as option, not adopted. |

**Summary:** 3 moot, 1 reduced scope, 1 still relevant (human friction — add session guard to hook), 1 optional (hook-mediated isolation — noted but not adopted).

### Decisions Made

- **Model 1 (always-worktree)** — Every session gets a worktree. No detection race, solo-session merges are fast-forward (zero overhead). Simpler than concurrent-only detection.
- **`bd worktree` integration** — **Resolved.** `bd` auto-discovers the beads DB from `EnterWorktree`-created worktrees without explicit redirect. Tested empirically. No `bd worktree create` needed.
- **Merge serialization** — **Resolved.** No external lock needed. Git's own `index.lock` prevents corruption — concurrent merges fail hard (one succeeds, one gets `fatal: index.lock exists`). Retry loop (wait 1-2s, up to 3 attempts) handles the race. Tested empirically with both overlapping and disjoint files.
- **Merge direction** — **Resolved.** ExitWorktree(keep) → from main → `git merge --no-ff worktree-<name>`.

### Red Team v4 — Resolution Status

| Finding | Confidence | Status |
|---------|-----------|--------|
| C1 Merge serialization | **Resolved** | No lock needed — git's index.lock handles it. Retry loop. Tested empirically. |
| C2 Conflict resolution fallback | **Defer to plan** | Where's the boundary between auto-resolve and ask-user? |
| C3 Orphaned worktrees GC | **Defer to plan** | Implementation detail — needs design for threshold/detection. |
| C4 Stale base mitigation | **Defer to plan** | Depends on session length patterns. |
| C5 Uncommitted state at merge | **Resolved** | Invariant: commit all changes in worktree before ExitWorktree. Merge sequence: commit → exit → merge → resolve → cleanup. |
| S1 Merge direction | **Resolved** | Explicit: exit worktree → from main → `git merge --no-ff worktree-branch`. |
| S2 Post-compact CWD | **Defer to plan** | SessionStart hook checks if CWD is inside `.claude/worktrees/`. |
| S3 Push strategy | **Defer to plan** | When does push happen relative to merge? |
| S4 Dirty main at start | **Defer to plan** | Warn, block, or ignore uncommitted changes at session start? |
| S5 Nested worktree path | **Resolved** | Accept — `.claude/` is gitignored, native tool behavior. |
| S6 Branch naming | **Resolved** | Accept — EnterWorktree generates random names, git errors on collision. |
| S7 Bidirectional cache | **Resolved** | Accept — inherent to isolation, already analyzed as low impact. |
| S8 Tooling assumptions | **Defer to plan** | Test matrix item. |

### Open Questions for Plan Phase

1. **Hook + EnterWorktree orchestration** — SessionStart hook always triggers (model 1), outputs instruction, model calls EnterWorktree. Is this reliable enough or does it need a skill wrapper?
2. **Compact behavior** — After compact, context resets. Does the session stay in the worktree (CWD persists across compact) or does it need to re-enter? If CWD persists, the worktree is still active but the model may not know it — needs a "you're in a worktree" indicator.
3. **Merge timing** — Merge at compact-prep/abandon, or also at push time? What if the user pushes mid-session?
4. **GIT_INDEX_FILE as defense-in-depth** — Keep the wrapper for non-worktree contexts, or simplify to worktrees-only?
5. **Test matrix** — Empirical verification needed: EnterWorktree + concurrent Edit/Write + merge resolution + ExitWorktree cache refresh. Plan should include this.
6. **Conflict resolution boundary (C2)** — When should Claude auto-resolve vs ask the user? Proposal: auto for additive markdown, ask for code or divergent rewrites.
7. **Orphaned worktree GC (C3)** — Threshold, detection mechanism, auto vs warn.
8. **Push timing (S3)** — Push after merge? At session end? User-initiated only?
9. **Dirty main handling (S4)** — Warn, block, or ignore uncommitted changes at session start?
