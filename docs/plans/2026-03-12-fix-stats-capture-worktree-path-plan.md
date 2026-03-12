---
title: "fix: Stats capture worktree path — make STATS_FILE absolute"
type: fix
status: completed
date: 2026-03-12
bead: j6ui
---

# Stats Capture Worktree Path — Make STATS_FILE Absolute

## Summary

`init-values.sh` emits `STATS_FILE` as a relative path (`.workflows/stats/...`). When `/do:work` runs in a worktree and the orchestrator `cd`s into it, capture-stats.sh writes to a nonexistent directory. Two prose workarounds exist telling the model to `cd` back to repo root — fix the root cause instead.

## Acceptance Criteria

- [x] STATS_FILE output from init-values.sh is an absolute path (starts with `/`)
- [x] Prose workaround in do-work/SKILL.md removed
- [x] Prose workaround in stats-capture-schema.md rewritten
- [x] `capture-stats-format.sh` QA script passes

## Implementation

### Step 1: Fix init-values.sh (2 lines)

**File:** `plugins/compound-workflows/scripts/init-values.sh`

**Line 160** (brainstorm|plan|deepen-plan|review case):
```
# Before:
STATS_FILE_VAL=".workflows/stats/${DATE_VAL}-${CMD}-${STEM}.yaml"

# After:
STATS_FILE_VAL="$(compute_repo_root)/.workflows/stats/${DATE_VAL}-${CMD}-${STEM}.yaml"
```

**Line 181** (work case):
```
# Before:
STATS_FILE_VAL=".workflows/stats/${DATE_VAL}-work-${STEM}.yaml"

# After:
STATS_FILE_VAL="$(compute_repo_root)/.workflows/stats/${DATE_VAL}-work-${STEM}.yaml"
```

`compute_repo_root()` already exists at line 79 (`git rev-parse --show-toplevel || pwd`).

### Step 2: Remove prose workaround in do-work/SKILL.md

**File:** `plugins/compound-workflows/skills/do-work/SKILL.md`

**Delete line 303** (the entire paragraph):
> "Important: run capture-stats.sh from the main repo root, not from the worktree. The `$STATS_FILE` path is relative to the main repo's `.workflows/stats/` which does not exist in worktrees. If your cwd is a worktree, either `cd` back to the main repo root before calling, or use an absolute path for `$STATS_FILE`."

No replacement needed — with an absolute path, CWD doesn't matter.

### Step 3: Rewrite stats-capture-schema.md Worktree Handling section

**File:** `plugins/compound-workflows/resources/stats-capture-schema.md`

**Replace lines 139-149** (the entire `## Worktree Handling` section):

Before:
```
## Worktree Handling

`/compound:work` runs subagents inside git worktrees. The orchestrator (not the subagent) captures stats. Key points:

- The orchestrator runs in the main conversation context (main repo root), not the worktree.
- `.workflows/stats/` is relative to the orchestrator's cwd, which is the main repo.
- Subagent completion notifications arrive in the main conversation context regardless of where the subagent ran.
- Stats files are written to the main repo's `.workflows/stats/`, never to the worktree's `.workflows/stats/`.
- Worktree cleanup destroys the worktree's `.workflows/` but does not affect the main repo's stats.

**The orchestrator must never `cd` into the worktree before calling `capture-stats.sh`.** The script writes relative to its invocation directory.
```

After:
```
## Worktree Handling

`/do:work` runs subagents inside git worktrees. The orchestrator (not the subagent) captures stats. Key points:

- STATS_FILE is an absolute path to the main repo's `.workflows/stats/`. Works from any CWD including worktrees.
- Subagent completion notifications arrive in the main conversation context regardless of where the subagent ran.
- Stats files are written to the main repo's `.workflows/stats/`, never to the worktree's `.workflows/stats/`.
- Worktree cleanup destroys the worktree's `.workflows/` but does not affect the main repo's stats.
```

### Step 4: Validate

Run `capture-stats-format.sh` QA script. Verify STATS_FILE in init-values.sh output starts with `/`.

## Sources

- Bead j6ui description
- Observed in dj65 work session and ka3w work session
