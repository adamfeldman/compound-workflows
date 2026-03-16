#!/usr/bin/env bash
# pre-commit-worktree-check v1.0.0
# Git pre-commit hook: blocks commits to the default branch when session_worktree is enabled.
# Defense-in-depth alongside AGENTS.md prose instruction — catches cases where the model
# forgot to create a worktree or the SessionStart hook failed to deliver.
#
# Install: copied to .git/hooks/pre-commit by /do:setup (or appended if hook exists).
# Bypass:  git commit --no-verify

set -e

# ── Read session_worktree config ──────────────────────────────────────────────
CONFIG="compound-workflows.local.md"
if [[ ! -f "$CONFIG" ]]; then
  exit 0  # No config = feature not set up, allow commit
fi

VALUE=$(grep -m1 '^session_worktree:' "$CONFIG" | sed 's/#.*//' | awk -F: '{print $2}' | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' || true)

if [[ "$VALUE" != "true" ]]; then
  exit 0  # Feature disabled or unset, allow commit
fi

# ── Check if CWD is inside a session worktree ─────────────────────────────────
# Walk up the path looking for a directory component matching session-*
CHECK_PATH="$PWD"
while [[ "$CHECK_PATH" != "/" ]]; do
  DIR_NAME=$(basename "$CHECK_PATH")
  if [[ "$DIR_NAME" == session-* ]]; then
    PARENT=$(dirname "$CHECK_PATH")
    PARENT_NAME=$(basename "$PARENT")
    if [[ "$PARENT_NAME" == ".worktrees" ]]; then
      exit 0  # Inside a session worktree, commit is safe
    fi
  fi
  CHECK_PATH=$(dirname "$CHECK_PATH")
done

# ── Not in a session worktree — block the commit ─────────────────────────────
# This error is seen by the MODEL during git commit in Claude Code sessions.
# The model should surface the choice to the user, not silently bypass or attempt recovery.
echo "session_worktree is enabled but you're not in a session worktree." >&2
echo "Ask the user: commit anyway (--no-verify) or create a worktree first?" >&2
exit 1
