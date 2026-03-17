#!/usr/bin/env bash
# pre-commit-worktree-check v2.0.0
# Git pre-commit hook: blocks commits to the default branch when managed
# session/work worktrees exist and session_worktree is enabled.
#
# Uses git plumbing (Decision 11) for worktree detection instead of fragile
# path heuristics. Checks filesystem reality (Decision 10) for managed worktrees.
#
# Install: copied to .git/hooks/pre-commit by /do:setup (or appended if hook exists).
# Bypass:  git commit --no-verify

set -euo pipefail

# ── Step 1: Read session_worktree config ─────────────────────────────────────
CONFIG="compound-workflows.local.md"
if [[ ! -f "$CONFIG" ]]; then
  exit 0  # No config = feature not set up, allow commit
fi

VALUE=$(grep -m1 '^session_worktree:' "$CONFIG" | sed 's/#.*//' | awk -F: '{print $2}' | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' || true)

if [[ "$VALUE" != "true" ]]; then
  exit 0  # Feature disabled or unset, allow commit
fi

# ── Step 2: Worktree detection via git plumbing (Decision 11) ────────────────
# If git-dir differs from git-common-dir, we're inside a worktree — allow.
git_dir=$(git rev-parse --git-dir 2>/dev/null || true)
common_dir=$(git rev-parse --git-common-dir 2>/dev/null || true)

if [[ -n "$git_dir" && -n "$common_dir" && "$git_dir" != "$common_dir" ]]; then
  exit 0  # Inside a worktree, commit is safe
fi

# ── Step 3: Check opt-out sentinel ───────────────────────────────────────────
if [[ -f ".worktrees/.opted-out" ]]; then
  exit 0  # User opted out of worktree enforcement this session
fi

# ── Step 4: Check for managed worktrees on disk ─────────────────────────────
# Collect session-* and work-* worktree directories into an array.
managed_worktrees=()
for dir in .worktrees/session-* .worktrees/work-*; do
  if [[ -d "$dir" ]]; then
    managed_worktrees+=("$(basename "$dir")")
  fi
done

# ── Step 5/6: No managed worktrees on disk — check stale registry entries ────
if [[ ${#managed_worktrees[@]} -eq 0 ]]; then
  # Secondary check: look for stale worktree registry entries that reference
  # paths under .worktrees/session-* or .worktrees/work-*
  stale_entries=$(git worktree list --porcelain 2>/dev/null | grep '^worktree ' | grep -E '/\.worktrees/(session|work)-' || true)

  if [[ -z "$stale_entries" ]]; then
    exit 0  # No worktrees anywhere, allow commit
  fi

  # Stale registry entries found — auto-prune and re-check
  git worktree prune 2>/dev/null || true

  stale_entries_after=$(git worktree list --porcelain 2>/dev/null | grep '^worktree ' | grep -E '/\.worktrees/(session|work)-' || true)

  if [[ -z "$stale_entries_after" ]]; then
    exit 0  # Prune resolved it, allow commit
  fi

  # Entries persist after prune (locked worktrees or other issue)
  echo "Error: Stale worktree registry entries persist after prune. Investigate with \`git worktree list\`." >&2
  echo "Run \`git worktree prune\` to clean stale entries, then retry." >&2
  exit 1
fi

# ── Step 7: Managed worktrees found on disk — block the commit ───────────────
worktree_list=$(IFS=', '; echo "${managed_worktrees[*]}")
first_worktree="${managed_worktrees[0]}"

{
  echo "Error: Committing to main while managed worktrees exist."
  echo "Found: $worktree_list"
  echo "To move staged changes: git stash && cd .worktrees/$first_worktree && git stash pop"
  echo "Or: touch .worktrees/.opted-out to allow main commits this session."
} >&2

exit 1
