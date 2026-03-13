# Git Index Isolation — Brainstorm

**Date:** 2026-03-13
**Bead:** s7qj
**Related:** Bead 8one (usage-pipe race + work-in-progress scoping — same class of shared-state concurrency bug)

## What We're Building

A `safe-commit.sh` wrapper script that replaces raw `git add` + `git commit` across all plugin workflow skills. The wrapper atomically stages only the specified files and commits them inside a cross-process lock, preventing concurrent Claude Code sessions from cross-contaminating each other's commits via the shared git index.

### The Problem

Two concurrent Claude Code sessions on the same branch share a single `.git/index` (staging area). Session A stages files, Session B commits, and Session B's commit accidentally includes Session A's staged files. This was observed on 2026-03-13 when compact-prep committed `.workflows/session-analysis/extract-timings.py` from a concurrent session despite only intending to commit memory files.

Session analysis (bead 3zr) found **74 concurrent session pairs** across 87 sessions — concurrent sessions are a daily pattern, not an edge case.

### How It Works

```
safe-commit.sh -m "commit message" file1.py file2.md
# OR
safe-commit.sh -F commit-msg.txt file1.py file2.md
# OR
safe-commit.sh --dry-run -m "msg" file1.py file2.md
```

Inside the lock:
1. Save current index state
2. Reset the index
3. `git add` ONLY the specified files
4. `git commit` with the provided message
5. Restore previous index state (re-stages any files that were staged before)
6. Release lock

Verbose logging at every step shows exactly what's happening.

## Why This Approach

### Goal: Detect and auto-recover, not just block

A pre-commit hook that blocks would require manual intervention, breaking automated workflows (compact-prep, /do:work subagents). The system needs to fix the contamination itself. *User reasoning: hooks need auto-recovery; blocking doesn't work for automated workflows.*

### Why atomic stage+commit (not detect-after-stage)

If staging and committing are separate steps, auto-recovery has its own race condition: two sessions unstaging each other's files simultaneously can leave both commits broken (TOCTOU). Making stage+commit atomic inside a lock eliminates this by design. *User reasoning: explored the race-in-the-race-fix and concluded serialization is required.*

### Why a custom lock (not git's index.lock)

Git's `index.lock` protects individual git operations (milliseconds) but our race happens between operations (between `git add` and `git commit`). `index.lock` is also too blunt — it blocks ALL git operations, not just our wrapper. *User reasoning: explored git's native locking and found it insufficient for this use case.*

### Why Python `fcntl.flock` (not bash `mkdir` or system `flock`)

- `flock` CLI is not available on macOS (not installed on this system)
- `mkdir`-based locks don't auto-release on `kill -9` (orphan risk requires stale-lock detection)
- Python's `fcntl.flock` is available on macOS, auto-releases on any process death (including kill -9), and requires ~10 lines of Python
- *User reasoning: accepted Python as a dependency given auto-approve.sh already uses Python as a fallback path.*

### Why not a pre-commit hook (Approach B)

Explored in detail and rejected:
1. **Session identification is hard** — hooks don't know which session invoked `git commit`
2. **Manifest maintenance is error-prone** — LLM instructions to update manifests are probabilistic; missed updates cause false positives
3. **Blocks instead of recovers** — hook can only reject the commit, not fix the staging area
4. **Bypassable** — `--no-verify` skips hooks entirely
5. **Hook installation** — `.git/hooks/` is local, requires setup step

*User reasoning: no callsite changes was the main appeal, but the problems outweighed the benefit given this project's preference for deterministic enforcement over probabilistic LLM instructions.*

### Why not worktree-per-session

Discussed and ruled out early. Worktrees give each session its own git index (true isolation), but:
- Changes the user's mental model — they're no longer "on main"
- Heavyweight for the problem — already used for `/do:work` subagents where it makes sense
- Goal is detect+recover, not prevent entirely

## Key Decisions

1. **Approach:** Atomic `safe-commit.sh` wrapper, not pre-commit hook or worktree isolation
2. **Lock mechanism:** Python `fcntl.flock` via small helper script (auto-releases on crash, works on macOS)
3. **Lock file location:** `.git/compound-commit.lock` (inside `.git/`, not tracked, per-repo)
4. **Expected file set:** Passed as arguments to wrapper (no separate manifest tracking)
5. **Transparency:** Verbose logging at every step + `--dry-run` mode. User sees what files are committed, what extras were temporarily unstaged, and that they were re-staged after
6. **Scope:** Replaces `git add` + `git commit` at all callsites in plugin workflow skills

## Open Questions

1. **Callsite inventory:** How many `git add` + `git commit` callsites exist across all skills? What's the migration scope?
2. **Non-plugin commits:** Should the wrapper also be used for commits outside of workflow skills (e.g., manual user commits, compact-prep commits)? Or is this plugin-only?
3. **Index restore on commit failure:** If `git commit` fails (pre-commit hook rejects, empty commit, etc.), how should the wrapper restore the original index state? Simple `git read-tree` from saved state, or replay the original `git add` commands?
4. **Lock timeout:** How long should the wrapper wait for the lock before failing? 30 seconds? Longer? What should the error message say?
5. **Hook interaction:** The PostToolUse hook (`plugin-qa-check.sh`) fires after `git commit` Bash commands. Does it need changes to work with `safe-commit.sh`?
