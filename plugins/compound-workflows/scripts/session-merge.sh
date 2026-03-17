#!/usr/bin/env bash
# session-merge.sh — Merge a worktree session branch back into the default branch
#
# Usage: bash session-merge.sh <worktree-branch-name> [--skip-overlap]
#
# Merges the specified worktree branch into the current (default) branch using
# --no-ff --no-edit --log. Handles stale index.lock files, file-overlap warnings,
# bead ID extraction for merge messages, and cleanup on success.
#
# Environment:
#   CALLER_PID — PID of the calling session (for self-exclusion in GC liveness checks).
#                Set by compact-prep/do:work before invoking this script. Default: 0 (no self-exclusion).
#
# Exit codes:
#   0 = merge succeeded, worktree cleaned up
#   1 = not on default branch or other error
#   2 = merge conflict (conflicted files listed on stderr)
#   3 = retry exhaustion (index.lock persisted across 3 attempts)
#   4 = default branch has uncommitted changes
#   5 = file overlap detected (files modified on both sides)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse arguments ──────────────────────────────────────────────────────────
BRANCH="${1:-}"
SKIP_OVERLAP=false

if [[ -z "$BRANCH" ]]; then
  echo "Error: worktree branch name required" >&2
  echo "Usage: bash session-merge.sh <worktree-branch-name> [--skip-overlap]" >&2
  exit 1
fi

for arg in "$@"; do
  if [[ "$arg" == "--skip-overlap" ]]; then
    SKIP_OVERLAP=true
  fi
done

# ── Step 0: Detect default branch ───────────────────────────────────────────
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

# ── Step 0b: MERGE_HEAD crash detection ──────────────────────────────────────
# If a previous merge was interrupted (crash, Ctrl-C, etc.), .git/MERGE_HEAD
# persists and attempting a new merge on top of stale state causes confusion.
# Detect early and give actionable guidance.
GIT_DIR_EARLY=$(git rev-parse --git-dir 2>/dev/null || true)
if [[ -n "$GIT_DIR_EARLY" ]] && [[ -f "$GIT_DIR_EARLY/MERGE_HEAD" ]]; then
  echo "Interrupted merge detected (MERGE_HEAD exists). Run 'git merge --abort' to clean up, or 'git merge --continue' to complete." >&2
  exit 1
fi

# ── Step 1: Verify on default branch ────────────────────────────────────────
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]]; then
  echo "Error: must be on $DEFAULT_BRANCH to merge. Currently on: $CURRENT_BRANCH" >&2
  exit 1
fi

# ── Step 2: Check dirty default branch ───────────────────────────────────────
# Uses --untracked-files=no so that untracked files (common in repos) don't
# falsely trigger the dirty-main gate. Only tracked uncommitted changes matter.
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "$DEFAULT_BRANCH has uncommitted changes. Cannot merge safely — another session may be working on $DEFAULT_BRANCH. Clean up and retry. Your worktree branch is preserved." >&2
  exit 4
fi

# ── Step 3: Stale lock detection ─────────────────────────────────────────────
GIT_DIR=$(git rev-parse --git-dir)
REPO_ROOT=$(git rev-parse --show-toplevel)
LOCK_FILE="$GIT_DIR/index.lock"

if [[ -f "$LOCK_FILE" ]]; then
  if [[ "$(uname)" == "Darwin" ]]; then
    lock_mtime=$(stat -f %m "$LOCK_FILE")
  else
    lock_mtime=$(stat -c %Y "$LOCK_FILE")
  fi
  now=$(date +%s)
  lock_age_seconds=$(( now - lock_mtime ))
  if (( lock_age_seconds > 10 )); then
    echo "Warning: stale .git/index.lock detected (${lock_age_seconds}s old). Removing." >&2
    rm -f "$LOCK_FILE"
  fi
fi

# ── Step 4: File-intersection warning ────────────────────────────────────────
if [[ "$SKIP_OVERLAP" != "true" ]]; then
  WORKTREE_FILES=$(git diff --name-only "$DEFAULT_BRANCH"..."$BRANCH" 2>/dev/null || true)
  MAIN_FILES=$(git diff --name-only "$BRANCH"..."$DEFAULT_BRANCH" 2>/dev/null || true)
  if [[ -n "$WORKTREE_FILES" ]] && [[ -n "$MAIN_FILES" ]]; then
    OVERLAP=$(comm -12 <(echo "$WORKTREE_FILES" | sort) <(echo "$MAIN_FILES" | sort))
    if [[ -n "$OVERLAP" ]]; then
      OVERLAP_COUNT=$(echo "$OVERLAP" | wc -l | tr -d ' ')
      echo "WARNING: $OVERLAP_COUNT files modified in both this worktree and $DEFAULT_BRANCH:" >&2
      echo "$OVERLAP" >&2
      echo "Git may auto-merge cleanly, but review the result." >&2
      exit 5
    fi
  fi
fi

# ── Step 5: Build merge message ──────────────────────────────────────────────
BEAD_IDS=""
if command -v bd >/dev/null 2>&1; then
  BEAD_IDS=$(git log "$DEFAULT_BRANCH".."$BRANCH" --format="%s %b" | \
    grep -oE '\b[a-z0-9]{3,5}\b' | sort -u | \
    while read -r candidate; do
      bd show "$candidate" >/dev/null 2>&1 && echo "$candidate"
    done | tr '\n' ', ' | sed 's/, $//' || true)
fi

{
  printf "Merge session worktree %s\n" "$BRANCH"
  if [[ -n "$BEAD_IDS" ]]; then
    printf "\nBeads: %s\n" "$BEAD_IDS"
  fi
} > "$GIT_DIR/MERGE_MSG"

# ── Step 6: Merge with retry loop ───────────────────────────────────────────
merge_exit=0
for attempt in 1 2 3; do
  merge_output=$(git merge --no-ff --no-edit --log "$BRANCH" 2>&1) && merge_exit=0 && break || merge_exit=$?
  if echo "$merge_output" | grep -q "index.lock"; then
    echo "Merge attempt $attempt failed due to index.lock, retrying in ${attempt}s..." >&2
    sleep "$attempt"
    continue
  fi
  # Non-lock error — break and handle below
  break
done

# ── Step 7: Handle merge result ──────────────────────────────────────────────
if [[ "$merge_exit" -eq 0 ]]; then
  # Success — proceed to cleanup
  :
elif echo "$merge_output" | grep -qi "conflict"; then
  echo "Merge conflict detected. Conflicted files:" >&2
  git diff --name-only --diff-filter=U >&2 || true
  exit 2
elif echo "$merge_output" | grep -q "index.lock"; then
  echo "Error: index.lock persisted across 3 merge attempts. Another process may be holding it." >&2
  exit 3
else
  echo "Merge failed with exit code $merge_exit:" >&2
  echo "$merge_output" >&2
  exit 1
fi

# ── Step 8: Cleanup (on success only) ────────────────────────────────────────
# Extract worktree name from branch (convention: <id>-<name> or just <name>)
# Use absolute path for worktree removal
WORKTREE_DIR="$REPO_ROOT/.worktrees"

# Find the worktree directory associated with this branch
# Two-stage filter: match .worktrees/*, then only clean up session-* worktrees
worktree_path=""
session_name=""
while IFS= read -r line; do
  if [[ "$line" == "$WORKTREE_DIR"/* ]]; then
    current_wt_path="$line"
  fi
  if [[ "$line" == *"branch refs/heads/$BRANCH"* ]] && [[ -n "${current_wt_path:-}" ]]; then
    # Only clean up session worktrees — don't remove /do:work worktrees
    wt_basename="$(basename "$current_wt_path")"
    if [[ "$wt_basename" == session-* ]]; then
      worktree_path="$current_wt_path"
      session_name="$wt_basename"
    fi
    break
  fi
done < <(git worktree list --porcelain 2>/dev/null || true)

# If we couldn't find a session worktree via git worktree list, derive the
# session name from the branch name (branch name = worktree name for session worktrees)
if [[ -z "$session_name" ]] && [[ "$BRANCH" == session-* ]]; then
  session_name="$BRANCH"
fi

if [[ -n "$worktree_path" ]]; then
  # ── PID liveness gate (Decision 9) ──────────────────────────────────────
  # Before removing the worktree, verify no other session is actively using it.
  # Uses session-gc.sh in single-worktree mode to apply the full Decision 9
  # algorithm (PID liveness + state checks). This enforces the mandate that
  # ALL deletion paths use Decision 9 — session-merge.sh must not bypass it.
  caller_pid="${CALLER_PID:-0}"
  gc_output=""
  if [[ -n "$session_name" ]] && [[ -f "$SCRIPT_DIR/session-gc.sh" ]]; then
    gc_output=$(bash "$SCRIPT_DIR/session-gc.sh" "$session_name" --caller-pid "$caller_pid" 2>/dev/null || true)
  fi

  # If session-gc.sh reported SKIP with another-session-active, abort removal
  if echo "$gc_output" | grep -q "another-session-active"; then
    active_pid=$(echo "$gc_output" | grep -oE 'PID=[0-9]+' | head -1 | sed 's/PID=//')
    echo "Warning: Cannot remove worktree — another session (PID ${active_pid:-unknown}) is active. Merge succeeded; worktree preserved." >&2
    # Merge succeeded, just can't remove worktree — exit 0 still
    echo "Merged worktree branch: $BRANCH (worktree preserved — active session)" >&2
    exit 0
  fi

  # Proceed with worktree removal: bd worktree remove (preferred, includes safety
  # checks for uncommitted/unpushed/stashes), with git worktree remove as fallback
  if command -v bd >/dev/null 2>&1; then
    bd worktree remove "$worktree_path" 2>/dev/null || git worktree remove "$worktree_path" 2>/dev/null || true
  else
    git worktree remove "$worktree_path" 2>/dev/null || true
  fi

  # ── Metadata cleanup (Decision 9 lifecycle) ──────────────────────────────
  # Session metadata (.worktrees/.metadata/<session-name>/) contains PID files
  # and other per-session state. Cleanup happens here because session-merge.sh
  # is the final step in the session lifecycle — after merge + worktree removal,
  # the session is complete and its metadata is no longer needed.
  # This is intentionally belt-and-suspenders with session-gc.sh's own metadata
  # cleanup — both paths clean up to ensure no orphaned metadata accumulates.
  if [[ -n "$session_name" ]] && [[ -d "$REPO_ROOT/.worktrees/.metadata/$session_name" ]]; then
    rm -rf "$REPO_ROOT/.worktrees/.metadata/$session_name"
  fi
fi

# Delete the branch: -d first (safe, requires merge), -D fallback
git branch -d "$BRANCH" 2>/dev/null || git branch -D "$BRANCH" 2>/dev/null || true

echo "Merged and cleaned up worktree branch: $BRANCH" >&2
exit 0
