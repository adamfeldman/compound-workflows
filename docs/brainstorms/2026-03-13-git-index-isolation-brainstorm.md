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

### Why not worktree-per-session

Discussed and ruled out:
- Changes the user's mental model — they're no longer "on main"
- Heavyweight — already used for `/do:work` subagents where it makes sense
- `GIT_INDEX_FILE` provides equivalent index isolation with less overhead

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

This brainstorm went through three major design iterations, each shaped by red team challenge:

| Version | Mechanism | Rejected Because |
|---------|-----------|-----------------|
| v1 | Lock-based `safe-commit.sh` (Python flock, stash recovery) | Red team v1: stash corrupts WD, lock timeout = blocking, index surgery risks |
| v2 | `git commit --only` (zero tooling) | Red team v2: only isolates disjoint files, 40% concurrent pairs have overlapping edits |
| v3 (final) | `GIT_INDEX_FILE` temp index wrapper | — (current design) |

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

## Open: Working Tree Isolation

**Status: Pending data analysis before decision.**

Red team v3 (Gemini) identified that GIT_INDEX_FILE solves **index contamination** but not **working tree conflicts** — when two sessions write different versions of the same file on disk, the temp index reads whatever's on disk (last writer wins).

**Scope expanded** to include working tree isolation. User reconsidering worktrees.

**Key question before proceeding:** The 40% overlap statistic measures sessions that edit the same file during overlapping time windows. This does NOT mean simultaneous disk writes. Two sessions can both edit `memory/project.md` without conflict if they do it at different moments within the session window.

**Next step:** Analyze session logs for truly simultaneous file writes (not just overlapping session windows). If simultaneous writes are common → worktrees needed. If rare → GIT_INDEX_FILE may be sufficient for the index problem, with working tree conflicts accepted as a separate/rarer issue.

**Candidate worktree models (if needed):**
1. Every session gets a worktree (maximum safety, merge overhead on every session)
2. Concurrent sessions only get worktrees (targeted, but detection has its own race)
3. GIT_INDEX_FILE for index + convention for shared files (simpler, partial coverage)

User leans toward model 2 (concurrent-only) but wants data first.
