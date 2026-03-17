#!/usr/bin/env bash
# session-gc.sh v0.1.0 — Garbage-collect orphaned session worktrees using Decision 9 algorithm
#
# Usage: session-gc.sh [<worktree-name>] [--caller-pid <PID>] [--max <N>] [--skip-untracked]
#
# When <worktree-name> is provided, operate on that single worktree.
# When omitted, glob .worktrees/session-* and process up to --max (default 5, oldest first).
#
# Options:
#   --caller-pid <PID>   PID to skip in liveness checks (self-exclusion, CQ2 fix). Default: 0.
#   --max <N>            Maximum worktrees to process per invocation. Default: 5.
#   --skip-untracked     Bypass the untracked files check (used after user acknowledgment).
#
# Stdout: one line per worktree:
#   REMOVED <name>
#   SKIPPED <name> <reason>
#   ERROR <name> <detail>
#
# Exit codes:
#   0 = completed (0 or more worktrees processed)
#   1 = error
#
# Environment:
#   DEFAULT_BRANCH — override default branch detection (saves ~15ms)

set -euo pipefail

# ── Parse arguments ───────────────────────────────────────────────────────────
WORKTREE_NAME=""
CALLER_PID=0
MAX_WORKTREES=5
SKIP_UNTRACKED=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --caller-pid)
      if [[ $# -lt 2 ]]; then
        echo "Error: --caller-pid requires a PID argument" >&2
        exit 1
      fi
      CALLER_PID="$2"
      shift 2
      ;;
    --max)
      if [[ $# -lt 2 ]]; then
        echo "Error: --max requires a number argument" >&2
        exit 1
      fi
      MAX_WORKTREES="$2"
      shift 2
      ;;
    --skip-untracked)
      SKIP_UNTRACKED=true
      shift
      ;;
    -*)
      echo "Error: unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [[ -n "$WORKTREE_NAME" ]]; then
        echo "Error: only one worktree name allowed, got extra: $1" >&2
        exit 1
      fi
      WORKTREE_NAME="$1"
      shift
      ;;
  esac
done

# ── Resolve default branch ───────────────────────────────────────────────────
if [[ -z "${DEFAULT_BRANCH:-}" ]]; then
  DEFAULT_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||' || true)
  DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
fi

# ── Step 0: Stale lock recovery ──────────────────────────────────────────────
GC_LOCK=".worktrees/.gc-lock"

if [[ -d "$GC_LOCK" ]]; then
  # Check mtime — if >60s, assume stale from prior crash
  lock_stale=false
  if [[ "$(uname)" == "Darwin" ]]; then
    lock_mtime=$(stat -f '%m' "$GC_LOCK" 2>/dev/null || echo 0)
  else
    lock_mtime=$(stat -c '%Y' "$GC_LOCK" 2>/dev/null || echo 0)
  fi
  now=$(date +%s)
  lock_age=$(( now - lock_mtime ))
  if (( lock_age > 60 )); then
    lock_stale=true
  fi

  if [[ "$lock_stale" == "true" ]]; then
    rmdir "$GC_LOCK" 2>/dev/null || true
  fi
fi

# ── Acquire GC lock ──────────────────────────────────────────────────────────
# mkdir is atomic — if another GC is running, this fails and we exit cleanly
if ! mkdir "$GC_LOCK" 2>/dev/null; then
  # Another GC in progress — exit silently
  exit 0
fi
trap 'rmdir "$GC_LOCK" 2>/dev/null || true' EXIT

# ── cleanup_worktree function ────────────────────────────────────────────────
# Implements the Refined Decision 9 Algorithm for a single worktree.
# Assumes GC lock is held by caller.
# Outputs one line to stdout: REMOVED, SKIPPED, or ERROR.
cleanup_worktree() {
  local wt_name="$1"
  local caller_pid="$2"
  local wt_path=".worktrees/$wt_name"

  # Verify worktree directory exists
  if [[ ! -d "$wt_path" ]]; then
    echo "ERROR $wt_name worktree-directory-missing"
    return 0
  fi

  # ── Step 1: Glob PID files ──────────────────────────────────────────────
  local meta_dir=".worktrees/.metadata/$wt_name"
  local pid_files=()
  local pid_count_initial=0

  if [[ -d "$meta_dir" ]]; then
    while IFS= read -r f; do
      pid_files+=("$f")
    done < <(find "$meta_dir" -maxdepth 1 -name 'pid.*' -type f 2>/dev/null || true)
  fi

  # ── Step 1b: Backward compat — check old .session.pid ──────────────────
  local old_pid_file="$wt_path/.session.pid"
  local old_pid=""
  if [[ -f "$old_pid_file" ]]; then
    old_pid=$(cat "$old_pid_file" 2>/dev/null || true)
  fi

  local old_pid_count=0
  if [[ -n "$old_pid" ]]; then
    old_pid_count=1
  fi
  pid_count_initial=$(( ${#pid_files[@]} + old_pid_count ))

  # ── Step 2: Liveness checks ────────────────────────────────────────────
  for pf in "${pid_files[@]}"; do
    local pid_val
    pid_val=$(cat "$pf" 2>/dev/null || true)
    if [[ -z "$pid_val" ]]; then
      rm -f "$pf"
      continue
    fi

    if [[ "$pid_val" == "$caller_pid" ]] && [[ "$caller_pid" != "0" ]]; then
      # Self — skip liveness check (CQ2 fix)
      continue
    fi

    if kill -0 "$pid_val" 2>/dev/null; then
      # Alive — another session is active
      echo "SKIPPED $wt_name another-session-active:PID=$pid_val"
      return 0
    else
      # Dead — prune this PID file
      rm -f "$pf"
    fi
  done

  # Check old-format PID too
  if [[ -n "$old_pid" ]]; then
    if [[ "$old_pid" == "$caller_pid" ]] && [[ "$caller_pid" != "0" ]]; then
      : # Self — skip
    elif kill -0 "$old_pid" 2>/dev/null; then
      echo "SKIPPED $wt_name another-session-active:PID=$old_pid"
      return 0
    fi
    # Dead old PID — will be cleaned up on DELETE path
  fi

  # ── Step 3: State checks (only if no other live PIDs) ──────────────────
  # Ordered by most-actionable-first

  # 3a: Unmerged commits (cheapest check, most common SKIP reason)
  local branch
  branch=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  if [[ -n "$branch" ]]; then
    local unmerged
    unmerged=$(git log "${DEFAULT_BRANCH}..${branch}" --oneline 2>/dev/null || true)
    if [[ -n "$unmerged" ]]; then
      echo "SKIPPED $wt_name unmerged-commits"
      return 0
    fi
  fi

  # 3b: Tracked changes
  local tracked_changes
  tracked_changes=$(git -C "$wt_path" status --porcelain --untracked-files=no 2>/dev/null || true)
  if [[ -n "$tracked_changes" ]]; then
    echo "SKIPPED $wt_name uncommitted-tracked-changes"
    return 0
  fi

  # 3c: Untracked files (skip if --skip-untracked)
  if [[ "$SKIP_UNTRACKED" != "true" ]]; then
    local untracked
    untracked=$(git -C "$wt_path" ls-files --others --exclude-standard 2>/dev/null | head -1 || true)
    if [[ -n "$untracked" ]]; then
      echo "SKIPPED $wt_name untracked-files-present"
      return 0
    fi
  fi

  # 3d: .workflows/ artifacts (safety net for architectural fix regression)
  local wf_artifacts=""
  local wf_dir
  for wf_dir in stats brainstorm-research plan-research compound-research deepen-plan work compact-prep; do
    if [[ -d "$wt_path/.workflows/$wf_dir" ]]; then
      wf_artifacts=$(find "$wt_path/.workflows/$wf_dir" -maxdepth 0 -not -empty 2>/dev/null | head -1 || true)
      if [[ -n "$wf_artifacts" ]]; then
        break
      fi
    fi
  done
  if [[ -n "$wf_artifacts" ]]; then
    echo "SKIPPED $wt_name workflows-artifacts-present"
    return 0
  fi

  # 3d2: .claude/memory/ artifacts
  local mem_artifacts=""
  if [[ -d "$wt_path/.claude/memory" ]]; then
    mem_artifacts=$(find "$wt_path/.claude/memory" -maxdepth 1 -type f 2>/dev/null | head -1 || true)
  fi
  if [[ -n "$mem_artifacts" ]]; then
    echo "SKIPPED $wt_name claude-memory-artifacts-present"
    return 0
  fi

  # 3e: All clean → DELETE

  # ── Step 4: DELETE with TOCTOU re-check ────────────────────────────────

  # Re-count PID files — if count increased since step 2, a new session claimed this worktree
  local pid_count_now=0
  if [[ -d "$meta_dir" ]]; then
    while IFS= read -r _; do
      pid_count_now=$(( pid_count_now + 1 ))
    done < <(find "$meta_dir" -maxdepth 1 -name 'pid.*' -type f 2>/dev/null || true)
  fi
  # Include old-format PID if still present
  if [[ -f "$old_pid_file" ]]; then
    pid_count_now=$(( pid_count_now + 1 ))
  fi

  if (( pid_count_now > pid_count_initial )); then
    echo "SKIPPED $wt_name new-session-claimed-during-gc"
    return 0
  fi

  # Attempt removal: bd worktree remove (NO --force), fallback to git worktree remove
  local remove_ok=false
  if command -v bd >/dev/null 2>&1; then
    if bd worktree remove "$wt_path" 2>/dev/null; then
      remove_ok=true
    fi
  fi
  if [[ "$remove_ok" != "true" ]]; then
    if git worktree remove "$wt_path" 2>/dev/null; then
      remove_ok=true
    fi
  fi

  if [[ "$remove_ok" != "true" ]]; then
    echo "ERROR $wt_name worktree-remove-failed"
    return 0
  fi

  # Delete branch (safe delete — GC verified branch is merged; -d fails harmlessly if tracking mismatch)
  if [[ -n "${branch:-}" ]]; then
    git branch -d "$branch" 2>/dev/null || true
  fi

  # Clean up metadata
  if [[ -d "$meta_dir" ]]; then
    rm -rf "$meta_dir"
  fi

  # Clean up old-format PID file (backward compat)
  if [[ -f "$old_pid_file" ]]; then
    rm -f "$old_pid_file"
  fi

  echo "REMOVED $wt_name"
  return 0
}

# ── Build worktree list ──────────────────────────────────────────────────────
worktrees_to_process=()

if [[ -n "$WORKTREE_NAME" ]]; then
  # Single worktree mode
  worktrees_to_process+=("$WORKTREE_NAME")
else
  # Glob mode — .worktrees/session-*, oldest first (reverse mtime sort)
  # ls -dt sorts newest-first; we want oldest-first for GC, so reverse
  while IFS= read -r wt_dir; do
    if [[ -n "$wt_dir" ]]; then
      wt_basename=$(basename "$wt_dir")
      worktrees_to_process+=("$wt_basename")
    fi
  done < <(ls -drt .worktrees/session-* 2>/dev/null || true)
fi

# ── Process worktrees ────────────────────────────────────────────────────────
processed=0
for wt in "${worktrees_to_process[@]}"; do
  if (( processed >= MAX_WORKTREES )); then
    break
  fi
  cleanup_worktree "$wt" "$CALLER_PID"
  processed=$(( processed + 1 ))
done

# Report if we hit the cap and there are more
total=${#worktrees_to_process[@]}
if (( total > MAX_WORKTREES )); then
  remaining=$(( total - MAX_WORKTREES ))
  echo "SKIPPED $remaining additional worktrees not scanned (GC cap $MAX_WORKTREES). Run /do:start cleanup for full sweep." >&2
fi

exit 0
