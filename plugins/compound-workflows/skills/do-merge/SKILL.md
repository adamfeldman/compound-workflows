---
name: do:merge
description: Retry a deferred worktree merge — used when compact-prep's merge couldn't complete
argument-hint: "[branch-name (optional)]"
---

# Merge Deferred Worktree

Merge an unmerged session worktree branch into main. Used when compact-prep's merge step couldn't complete (dirty main, retry exhaustion, user aborted conflict resolution).

## Arguments

<branch_name> #$ARGUMENTS </branch_name>

## Execution

### 1. Detect unmerged worktrees

Run `git worktree list` and filter for entries whose path contains `.claude/worktrees/` (session worktrees only — NOT `.worktrees/` which are bd-managed). For each session worktree, check if its branch has unmerged commits:

    git worktree list
    # Filter output: only lines containing .claude/worktrees/
    # For each matching worktree, extract branch name and check:
    git log main..<branch> --oneline | head -1

Worktrees whose branch has unmerged commits (non-empty `git log` output) are candidates.

### 2. Select branch

- **Branch argument provided:** Use it directly (no confirmation needed).
- **No argument, exactly 1 unmerged worktree:** Auto-select with announcement:
  "Merging worktree branch `<name>` into main."
- **No argument, multiple unmerged worktrees:** AskUserQuestion:
  "Which worktree to merge?" with branch list + uncommitted/unmerged counts.
- **No unmerged worktrees found:** Announce "No unmerged worktree branches found." Stop.

### 3. Verify on main

Verify CWD is the main repo (not inside a worktree). If inside a worktree,
warn: "Cannot merge from inside a worktree. Exit the worktree first." Stop.

To check: `git rev-parse --show-toplevel` should NOT point to a `.claude/worktrees/` path.

### 4. Run merge script

    bash ${CLAUDE_SKILL_DIR}/../../scripts/session-merge.sh <branch>

Replace `<branch>` with the selected branch name from Step 2.

### 5. Handle result

- **Exit 0 (success):** Announce "Merged and cleaned up." Done.
- **Exit 2 (conflict):** Read conflicted files, auto-resolve additive markdown
  (e.g., both sides appended to the same file — keep both additions).
  Present resolution summary to the user. AskUserQuestion with choices:
  Accept / Review / Abort.
  If accepted: `git add .` then `git commit --no-edit` to finalize the merge.
  If aborted: `git merge --abort` and announce "Worktree preserved. Run `/do:merge` to retry."
- **Exit 3 (retry exhaustion):** Announce "Another session is currently merging. Try again shortly."
- **Exit 4 (dirty main):** Announce "Main has uncommitted changes. Commit or stash them,
  then run `/do:merge` again."
- **Exit 1 (other error):** Show the error output from the script.
