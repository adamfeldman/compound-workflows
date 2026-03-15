#!/usr/bin/env bash
# session-worktree v2.0.0
# SessionStart hook: detects worktree state and prompts for session isolation.
# Distributed as a template in the plugin, copied to .claude/hooks/ by /do:setup.
#
# Exit behavior:
#   stdout + exit 0  = output delivered as system-reminder
#   exit 0 (silent)  = feature disabled, no config, or non-error early return
#
# This hook does NOT: change CWD or block the session.
# It only reports state and suggests next steps.

set -euo pipefail

# ── Step 1: Read config ─────────────────────────────────────────────────────
CONFIG="compound-workflows.local.md"
if [[ ! -f "$CONFIG" ]]; then
  exit 0  # No config = feature not set up, silent skip
fi

VALUE=$(grep -m1 '^session_worktree:' "$CONFIG" | sed 's/#.*//' | awk -F: '{print $2}' | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' || true)

# ── Hook self-version check ─────────────────────────────────────────────────
# Compare installed hook version against the plugin template version.
# If stale, warn the user and exit early so they get the update prompt.
HOOK_VERSION=$(sed -n '2s/^# session-worktree v//p' "$0")
TEMPLATE_PATH="$HOME/.claude/plugins/marketplaces/compound-workflows-marketplace/plugins/compound-workflows/templates/session-worktree.sh"
if [[ -f "$TEMPLATE_PATH" ]]; then
  TEMPLATE_VERSION=$(sed -n '2s/^# session-worktree v//p' "$TEMPLATE_PATH")
  if [[ -n "$TEMPLATE_VERSION" && -n "$HOOK_VERSION" && "$HOOK_VERSION" != "$TEMPLATE_VERSION" ]]; then
    printf '%s\n' "Session worktree hook is outdated (v${HOOK_VERSION}, current: v${TEMPLATE_VERSION}). Run /do:setup to update."
    exit 0
  fi
fi

# ── bd availability check ───────────────────────────────────────────────────
if ! command -v bd >/dev/null 2>&1; then
  printf '%s\n' "Session worktree isolation requires bd (beads). Install beads or set session_worktree: false to disable this warning."
  exit 0
fi

# Detect default branch
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

# ── Step 2: Feature disabled — orphan GC only, then exit ────────────────────
if [[ "$VALUE" == "false" ]]; then
  # GC merged session worktrees to prevent silent orphaning
  if [[ -d ".worktrees" ]]; then
    for wt_dir in .worktrees/session-*/; do
      [ -d "$wt_dir" ] || continue
      wt_branch=$(git -C "$wt_dir" branch --show-current 2>/dev/null) || continue
      if git merge-base --is-ancestor "$wt_branch" "$DEFAULT_BRANCH" 2>/dev/null; then
        bd worktree remove "$wt_dir" 2>/dev/null || git worktree remove "$wt_dir" 2>/dev/null || true
        git branch -d "$wt_branch" 2>/dev/null || true
      fi
    done
  fi
  # Legacy .claude/worktrees/ one-time migration cleanup
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

# ── Step 3: Check for existing session worktrees (resume detection) ─────────
# Collect all session worktrees sorted by modification time (most recent first)
EXISTING_LIST=$(ls -dt .worktrees/session-* 2>/dev/null || true)

if [[ -n "$EXISTING_LIST" ]]; then
  EXISTING_COUNT=$(echo "$EXISTING_LIST" | wc -l | tr -d '[:space:]')
  MOST_RECENT=$(echo "$EXISTING_LIST" | head -1)
  MR_BRANCH=$(git -C "$MOST_RECENT" branch --show-current 2>/dev/null || echo "unknown")

  # PID-based active session detection
  PID_FILE="$MOST_RECENT/.session.pid"
  ACTIVE_WARNING=""
  if [[ -f "$PID_FILE" ]]; then
    STORED_PID=$(cat "$PID_FILE" 2>/dev/null || true)
    if [[ -n "$STORED_PID" ]] && kill -0 "$STORED_PID" 2>/dev/null; then
      ACTIVE_WARNING="Warning: another session may be actively using this worktree. Say 'skip worktree' to avoid conflicts."
    else
      # Process dead — stale PID file, safe to resume
      rm -f "$PID_FILE"
    fi
  fi

  OUTPUT="Session worktree exists at ${MOST_RECENT} (branch: ${MR_BRANCH}). Before doing anything else — before reading files, running commands, or responding to the user — run cd ${MOST_RECENT} to resume working in it."

  if [[ -n "$ACTIVE_WARNING" ]]; then
    OUTPUT="${OUTPUT}
${ACTIVE_WARNING}"
  fi

  # Multiple worktrees: list others
  if [[ "$EXISTING_COUNT" -gt 1 ]]; then
    OTHERS=""
    FIRST=true
    while IFS= read -r wt_path; do
      [[ -n "$wt_path" ]] || continue
      [[ "$wt_path" != "$MOST_RECENT" ]] || continue
      other_branch=$(git -C "$wt_path" branch --show-current 2>/dev/null || echo "unknown")
      if [[ "$FIRST" == "true" ]]; then
        OTHERS="${wt_path} (branch: ${other_branch})"
        FIRST=false
      else
        OTHERS="${OTHERS}, ${wt_path} (branch: ${other_branch})"
      fi
    done <<< "$EXISTING_LIST"
    OUTPUT="${OUTPUT}
${EXISTING_COUNT} session worktrees found. Resuming most recent: ${MOST_RECENT} (branch: ${MR_BRANCH}). Others: ${OTHERS}."
  fi

  # Write PID file for the session resuming this worktree
  echo "$PPID" > "$MOST_RECENT/.session.pid" 2>/dev/null || true

  printf '%s\n' "$OUTPUT"
  exit 0
fi

# ── Fresh session start: accumulate output buffer ───────────────────────────
OUTPUT=""

# ── Step 4: GC merged session worktrees ──────────────────────────────────────
if [[ -d ".worktrees" ]]; then
  for wt_dir in .worktrees/session-*/; do
    [ -d "$wt_dir" ] || continue
    wt_branch=$(git -C "$wt_dir" branch --show-current 2>/dev/null) || continue
    if git merge-base --is-ancestor "$wt_branch" "$DEFAULT_BRANCH" 2>/dev/null; then
      bd worktree remove "$wt_dir" 2>/dev/null || git worktree remove "$wt_dir" 2>/dev/null || true
      git branch -d "$wt_branch" 2>/dev/null || true
    fi
  done
fi

# Legacy .claude/worktrees/ one-time migration cleanup
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
ORPHAN_COUNT=0
ORPHAN_OUTPUT=""
MAX_DISPLAY=10

# Check .worktrees/session-* for orphan session worktrees
if [[ -d ".worktrees" ]]; then
  while IFS= read -r wt_name; do
    [[ -n "$wt_name" ]] || continue
    # Only process session-* worktrees
    [[ "$wt_name" == session-* ]] || continue

    wt_path=".worktrees/$wt_name"
    [[ -d "$wt_path" ]] || continue

    ORPHAN_COUNT=$((ORPHAN_COUNT + 1))

    if [[ $ORPHAN_COUNT -le $MAX_DISPLAY ]]; then
      wt_branch=$(git -C "$wt_path" branch --show-current 2>/dev/null || echo "unknown")
      uncommitted=$(git -C "$wt_path" status --short 2>/dev/null | wc -l | tr -d '[:space:]')
      unmerged=$(git log "$DEFAULT_BRANCH..$wt_branch" --oneline 2>/dev/null | wc -l | tr -d '[:space:]')

      ORPHAN_OUTPUT="${ORPHAN_OUTPUT}  - ${wt_name} (branch: ${wt_branch}, ${uncommitted} uncommitted files, ${unmerged} unmerged commits)
    Inspect: git -C .worktrees/${wt_name} status
    Merge:   /do:merge
    Discard: bd worktree remove .worktrees/${wt_name}
"
    fi
  done < <(ls ".worktrees/" 2>/dev/null)
fi

# Also check legacy .claude/worktrees/ for orphans (one-time migration)
if [[ -d ".claude/worktrees" ]]; then
  while IFS= read -r wt_name; do
    [[ -n "$wt_name" ]] || continue

    wt_path=".claude/worktrees/$wt_name"
    [[ -d "$wt_path" ]] || continue

    ORPHAN_COUNT=$((ORPHAN_COUNT + 1))

    if [[ $ORPHAN_COUNT -le $MAX_DISPLAY ]]; then
      wt_branch=$(git -C "$wt_path" branch --show-current 2>/dev/null || echo "unknown")
      uncommitted=$(git -C "$wt_path" status --short 2>/dev/null | wc -l | tr -d '[:space:]')
      unmerged=$(git log "$DEFAULT_BRANCH..$wt_branch" --oneline 2>/dev/null | wc -l | tr -d '[:space:]')

      ORPHAN_OUTPUT="${ORPHAN_OUTPUT}  - (legacy) ${wt_name} (branch: ${wt_branch}, ${uncommitted} uncommitted files, ${unmerged} unmerged commits)
    Inspect: git -C .claude/worktrees/${wt_name} status
    Merge:   /do:merge
    Discard: git worktree remove .claude/worktrees/${wt_name} && git branch -D ${wt_branch}
"
    fi
  done < <(ls ".claude/worktrees/" 2>/dev/null)
fi

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
OUTPUT="${OUTPUT}Session worktree isolation is enabled. Before doing anything else — before reading files, running commands, or responding to the user — create a session worktree: run bd worktree create .worktrees/session-<name> (pick a short descriptive name) then cd into it. If the user says 'stay on main' or 'skip worktree', skip it. If \`bd worktree create\` fails, warn the user and proceed on main."

# ── Step 8: Emit and exit ──────────────────────────────────────────────────
printf '%s\n' "$OUTPUT"
exit 0
