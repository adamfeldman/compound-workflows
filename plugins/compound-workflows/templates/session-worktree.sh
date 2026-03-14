#!/usr/bin/env bash
# session-worktree v1.0.0
# SessionStart hook: detects worktree state and prompts for session isolation.
# Distributed as a template in the plugin, copied to .claude/hooks/ by /do:setup.
#
# Exit behavior:
#   exit 0               = silent pass-through (feature disabled or no config)
#   stderr + exit 2      = feedback shown to model (worktree status/instructions)
#
# This hook does NOT: call EnterWorktree, change CWD, or block the session.
# It only reports state and suggests next steps.

set -euo pipefail

# ── Step 1: Read config ─────────────────────────────────────────────────────
CONFIG="compound-workflows.local.md"
if [[ ! -f "$CONFIG" ]]; then
  exit 0  # No config = feature not set up, silent skip
fi

VALUE=$(grep -m1 '^session_worktree:' "$CONFIG" | sed 's/#.*//' | awk -F: '{print $2}' | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' || true)

# Detect default branch
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

# ── Step 2: Feature disabled — orphan GC only, then exit ────────────────────
if [[ "$VALUE" == "false" ]]; then
  # Still GC merged worktrees to prevent silent orphaning
  if [[ -d ".claude/worktrees" ]]; then
    for wt_dir in .claude/worktrees/*/; do
      [ -d "$wt_dir" ] || continue
      wt_branch=$(git -C "$wt_dir" branch --show-current 2>/dev/null) || continue
      if git merge-base --is-ancestor "$wt_branch" "$DEFAULT_BRANCH" 2>/dev/null; then
        git worktree remove "$wt_dir" 2>/dev/null || true
        git branch -d "$wt_branch" 2>/dev/null || true
      fi
    done
  fi
  exit 0
fi

# Parsing contract: Only explicit "false" disables.
# Missing key, empty value, "true", or any other value = enabled.

# ── Step 3: Check if already in a worktree (post-compact resume) ────────────
CURRENT_DIR="$(pwd)"
case "$CURRENT_DIR" in
  */.claude/worktrees/*)
    WT_DIRNAME=$(basename "$CURRENT_DIR")
    WT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
    cat >&2 <<RESUME
You are in worktree \`$WT_DIRNAME\` on branch \`$WT_BRANCH\`. Continue working here. At session end, compact-prep will merge your changes into main.
RESUME
    exit 2
    ;;
esac

# ── Fresh session start: accumulate output buffer ───────────────────────────
OUTPUT=""

# ── Step 4: GC merged worktrees ────────────────────────────────────────────
if [[ -d ".claude/worktrees" ]]; then
  for wt_dir in .claude/worktrees/*/; do
    [ -d "$wt_dir" ] || continue
    wt_branch=$(git -C "$wt_dir" branch --show-current 2>/dev/null) || continue
    if git merge-base --is-ancestor "$wt_branch" "$DEFAULT_BRANCH" 2>/dev/null; then
      git worktree remove "$wt_dir" 2>/dev/null || true
      git branch -d "$wt_branch" 2>/dev/null || true
    fi
  done
fi

# ── Step 5: Check for remaining worktrees from other sessions ───────────────
if [[ -d ".claude/worktrees" ]]; then
  ORPHAN_COUNT=0
  ORPHAN_OUTPUT=""
  MAX_DISPLAY=10

  # CRITICAL: Use process substitution to avoid pipe-subshell trap
  # (pipe-to-while loses variable modifications in bash)
  while IFS= read -r wt_name; do
    [[ -n "$wt_name" ]] || continue

    wt_path=".claude/worktrees/$wt_name"
    [[ -d "$wt_path" ]] || continue

    # Skip if this IS our current directory
    wt_abs=$(cd "$wt_path" 2>/dev/null && pwd) || continue
    [[ "$wt_abs" != "$CURRENT_DIR" ]] || continue

    ORPHAN_COUNT=$((ORPHAN_COUNT + 1))

    if [[ $ORPHAN_COUNT -le $MAX_DISPLAY ]]; then
      wt_branch=$(git -C "$wt_path" branch --show-current 2>/dev/null || echo "unknown")
      uncommitted=$(git -C "$wt_path" status --short 2>/dev/null | wc -l | tr -d '[:space:]')
      unmerged=$(git log "$DEFAULT_BRANCH..$wt_branch" --oneline 2>/dev/null | wc -l | tr -d '[:space:]')

      ORPHAN_OUTPUT="${ORPHAN_OUTPUT}  - ${wt_name} (branch: ${wt_branch}, ${uncommitted} uncommitted files, ${unmerged} unmerged commits)
    Inspect: git -C .claude/worktrees/${wt_name} status
    Merge:   /do:merge
    Discard: git worktree remove .claude/worktrees/${wt_name} && git branch -D ${wt_branch}
"
    fi
  done < <(ls ".claude/worktrees/" 2>/dev/null)

  if [[ $ORPHAN_COUNT -gt 0 ]]; then
    if [[ $ORPHAN_COUNT -gt $MAX_DISPLAY ]]; then
      OUTPUT="${OUTPUT}Note: ${ORPHAN_COUNT} worktrees from other sessions detected (showing first ${MAX_DISPLAY}):
${ORPHAN_OUTPUT}  ... and $((ORPHAN_COUNT - MAX_DISPLAY)) more
"
    else
      OUTPUT="${OUTPUT}Note: ${ORPHAN_COUNT} worktree(s) from other sessions detected (may be active or orphaned):
${ORPHAN_OUTPUT}"
    fi
  fi
fi

# ── Step 6: Check for mid-merge state and dirty main ───────────────────────
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || true)
if [[ -n "$GIT_DIR" ]] && [[ -f "$GIT_DIR/MERGE_HEAD" ]]; then
  OUTPUT="${OUTPUT}Warning: an incomplete merge is in progress on main. Run \`git merge --abort\` to cancel or \`git merge --continue\` to complete it.
"
fi

PORCELAIN=$(git status --porcelain 2>/dev/null || true)
if [[ -n "$PORCELAIN" ]]; then
  OUTPUT="${OUTPUT}Warning: main has uncommitted changes. These will NOT be visible in the worktree (worktrees branch from HEAD commit).
"
fi

# ── Step 7: Append instruction ──────────────────────────────────────────────
OUTPUT="${OUTPUT}Session isolation active. Call \`EnterWorktree\` to work in an isolated worktree. Say 'stay on main' to skip."

# ── Step 8: Emit and exit ──────────────────────────────────────────────────
printf '%s\n' "$OUTPUT" >&2
exit 2
