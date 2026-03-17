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

Run `git worktree list` and filter for entries whose path contains `.worktrees/session-` (session worktrees use the `session-` prefix). For each session worktree, check if its branch has unmerged commits:

    git worktree list
    # Filter output: only lines containing .worktrees/session-
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

To check: `git rev-parse --show-toplevel` should NOT contain `.worktrees/session-`.

### 4. Derive session name

Extract the session worktree name from the branch. For session worktrees, the branch name
IS the worktree name (e.g., branch `session-hb4a` = worktree `.worktrees/session-hb4a`).
Store this for metadata cleanup in Step 5.

### 5. Run merge script

    bash ${CLAUDE_SKILL_DIR}/../../scripts/session-merge.sh <branch>

Replace `<branch>` with the selected branch name from Step 2.

### 6. Handle result

- **Exit 0 (success):** Announce "Merged and cleaned up." Done. (Metadata cleanup is handled by the script.)
- **Exit 2 (conflict):** Read conflicted files, auto-resolve additive markdown
  (e.g., both sides appended to the same file — keep both additions).
  Present resolution summary to the user. AskUserQuestion with choices:
  Accept / Review / Abort.
  If accepted: `git add .` then `git commit --no-edit` to finalize the merge.
  Then clean up session metadata:
  `rm -rf .worktrees/.metadata/<session-name>` (where `<session-name>` is from Step 4).
  If aborted: `git merge --abort` and announce "Worktree preserved. Run `/do:merge` to retry."
  Skip metadata cleanup — the worktree still exists and may be resumed.
- **Exit 3 (retry exhaustion):** Announce "Another session is currently merging. Try again shortly."
- **Exit 4 (dirty main):** Announce "Main has uncommitted changes. Commit or stash them,
  then run `/do:merge` again."
- **Exit 5 (file overlap):** Warn the user about overlapping files (the script lists them on stderr).
  Do NOT auto-resolve — file overlap means both the worktree and the default branch modified the
  same files. Skip metadata cleanup (the merge did not complete). Offer two choices:
  1. Re-run with `--skip-overlap`: `bash ${CLAUDE_SKILL_DIR}/../../scripts/session-merge.sh <branch> --skip-overlap`
     (lets git attempt the merge; may still result in conflicts handled by exit 2)
  2. Abort (no action needed — worktree and branch are preserved)
- **Exit 1 (other error):** Show the error output from the script.
