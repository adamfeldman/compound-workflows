#!/usr/bin/env bash
# session-worktree v3.0.0
# SessionStart hook: deterministically creates session worktrees, runs GC, detects existing sessions.
# Distributed as a template in the plugin, copied to .claude/hooks/ by /do:setup.
#
# Exit behavior:
#   stdout + exit 0  = output delivered as system-reminder
#   exit 0 (silent)  = feature disabled, no config, or non-error early return
#
# This hook CREATES worktrees (deterministic) and writes PID files.
# It does NOT: change model CWD or block the session.
#
# Environment:
#   SESSION_WORKTREE_DEBUG=1  — log each hook step to .worktrees/.debug.log

set -euo pipefail

# ── Resolve helper script directory ───────────────────────────────────────────
# Helper scripts (session-gc.sh, write-session-pid.sh) are in the plugin's scripts/ directory.
# Installed hook lives in .claude/hooks/ — resolve via the marketplace installation path.
PLUGIN_SCRIPTS="$HOME/.claude/plugins/marketplaces/compound-workflows-marketplace/plugins/compound-workflows/scripts"
if [[ ! -d "$PLUGIN_SCRIPTS" ]]; then
  # Fallback: try sibling scripts/ directory (template development / testing)
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
  PLUGIN_SCRIPTS="$(cd "$SCRIPT_DIR/../scripts" 2>/dev/null && pwd -P)" || PLUGIN_SCRIPTS=""
fi

# ── Debug logging infrastructure ──────────────────────────────────────────────
DEBUG_ENABLED="${SESSION_WORKTREE_DEBUG:-0}"
DEBUG_BUF=""

debug_log() {
  if [[ "$DEBUG_ENABLED" == "1" ]]; then
    DEBUG_BUF="${DEBUG_BUF}[${SECONDS}s] $1
"
  fi
}

flush_debug() {
  if [[ "$DEBUG_ENABLED" == "1" ]] && [[ -n "$DEBUG_BUF" ]]; then
    mkdir -p .worktrees 2>/dev/null || true
    printf '%s' "$DEBUG_BUF" >> .worktrees/.debug.log 2>/dev/null || true
  fi
}

# Ensure debug log is flushed on any exit path
trap flush_debug EXIT

sweep_orphan_metadata() {
  if [[ -d ".worktrees/.metadata" ]]; then
    debug_log "Sweeping orphan metadata"
    for meta_dir in .worktrees/.metadata/session-*/; do
      [[ -d "$meta_dir" ]] || continue
      local meta_name
      meta_name=$(basename "$meta_dir")
      if [[ ! -d ".worktrees/$meta_name" ]]; then
        rm -rf "$meta_dir"
        debug_log "Removed orphan metadata for $meta_name"
      fi
    done
  fi
}

debug_log "Hook start. PID=$$, PPID=$PPID, CWD=$(pwd)"

# ── Helper: cross-platform stat mtime ─────────────────────────────────────────
get_mtime() {
  local target="$1"
  stat -f '%m' "$target" 2>/dev/null || stat -c '%Y' "$target" 2>/dev/null || echo ""
}

# ── Helper: read config value ─────────────────────────────────────────────────
read_config_value() {
  local key="$1"
  local config_file="$2"
  grep -m1 "^${key}:" "$config_file" | sed 's/#.*//' | awk -F: '{print $2}' | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' || true
}

# ── Output buffer ─────────────────────────────────────────────────────────────
OUTPUT=""
VERSION_WARNING=""
GC_ISSUES_COUNT=0
GC_OUTPUT=""

# ══════════════════════════════════════════════════════════════════════════════
# Hook-1: Read config
# ══════════════════════════════════════════════════════════════════════════════
debug_log "Hook-1: Reading config"

CONFIG="compound-workflows.local.md"
if [[ ! -f "$CONFIG" ]]; then
  debug_log "Hook-1: No config file, silent exit"
  exit 0
fi

VALUE=$(read_config_value "session_worktree" "$CONFIG")

if [[ -z "$VALUE" ]]; then
  debug_log "Hook-1: session_worktree key not found, silent exit"
  exit 0
fi

debug_log "Hook-1: session_worktree=$VALUE"

# ══════════════════════════════════════════════════════════════════════════════
# Hook-2: Delete sentinel
# ══════════════════════════════════════════════════════════════════════════════
debug_log "Hook-2: Deleting opt-out sentinel"
rm -f .worktrees/.opted-out

# ══════════════════════════════════════════════════════════════════════════════
# Hook-3: Worktree-in-worktree guard
# ══════════════════════════════════════════════════════════════════════════════
debug_log "Hook-3: Worktree-in-worktree guard"

GIT_DIR_VAL=$(git rev-parse --git-dir 2>/dev/null || true)
GIT_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null || true)

if [[ -n "$GIT_DIR_VAL" ]] && [[ -n "$GIT_COMMON_DIR" ]] && [[ "$GIT_DIR_VAL" != "$GIT_COMMON_DIR" ]]; then
  debug_log "Hook-3: Already inside a worktree (git-dir=$GIT_DIR_VAL, common-dir=$GIT_COMMON_DIR)"
  echo "Already inside a worktree. Skipping session worktree creation."
  exit 0
fi

debug_log "Hook-3: Not inside a worktree, continuing"

# ══════════════════════════════════════════════════════════════════════════════
# Hook-4: Self-version check
# ══════════════════════════════════════════════════════════════════════════════
debug_log "Hook-4: Self-version check"

HOOK_VERSION=$(sed -n '2s/^# session-worktree v//p' "$0")
TEMPLATE_PATH="$HOME/.claude/plugins/marketplaces/compound-workflows-marketplace/plugins/compound-workflows/templates/session-worktree.sh"

if [[ -f "$TEMPLATE_PATH" ]]; then
  TEMPLATE_VERSION=$(sed -n '2s/^# session-worktree v//p' "$TEMPLATE_PATH")
  if [[ -n "$TEMPLATE_VERSION" && -n "$HOOK_VERSION" && "$HOOK_VERSION" != "$TEMPLATE_VERSION" ]]; then
    VERSION_WARNING="UPGRADE REQUIRED: Session hook v${HOOK_VERSION} is installed but v${TEMPLATE_VERSION} is available. Run /do:setup to upgrade.
"
    debug_log "Hook-4: Version mismatch (installed=$HOOK_VERSION, template=$TEMPLATE_VERSION)"
  else
    debug_log "Hook-4: Version OK ($HOOK_VERSION)"
  fi
else
  debug_log "Hook-4: Template not found at $TEMPLATE_PATH, skipping version check"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Hook-5: bd availability check
# ══════════════════════════════════════════════════════════════════════════════
debug_log "Hook-5: bd availability check"

if ! command -v bd >/dev/null 2>&1; then
  debug_log "Hook-5: bd not available, exiting"
  echo "${VERSION_WARNING}Session worktree isolation requires bd (beads). Install beads or set session_worktree: false to disable this warning."
  exit 0
fi

debug_log "Hook-5: bd available"

# ── Detect default branch ────────────────────────────────────────────────────
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
export DEFAULT_BRANCH

debug_log "Default branch: $DEFAULT_BRANCH"

# ── Resolve absolute repo root (for MANDATORY cd paths) ──────────────────────
REPO_ROOT=$(pwd -P)

# ══════════════════════════════════════════════════════════════════════════════
# Hook-6: Feature disabled path
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$VALUE" == "false" ]]; then
  debug_log "Hook-6: Feature disabled, running GC only"
  if [[ -d ".worktrees" ]] && [[ -n "$PLUGIN_SCRIPTS" ]] && [[ -f "$PLUGIN_SCRIPTS/session-gc.sh" ]]; then
    bash "$PLUGIN_SCRIPTS/session-gc.sh" --max 5 --caller-pid "$PPID" 2>/dev/null || true
  fi
  debug_log "Hook-6: GC complete, exiting"
  exit 0
fi

# Parsing contract: Only explicit "false" disables.
# Missing key handled above (exit 0). Empty value, "true", or any other value = enabled.
debug_log "Hook-6: Feature enabled, continuing"

# ══════════════════════════════════════════════════════════════════════════════
# Hook-7: Existing worktree scan
# ══════════════════════════════════════════════════════════════════════════════
debug_log "Hook-7: Scanning for existing worktrees"

EXISTING_LIST=$(ls -dt .worktrees/session-* 2>/dev/null || true)

if [[ -n "$EXISTING_LIST" ]]; then
  debug_log "Hook-7: Found existing worktrees, running GC first"

  # ════════════════════════════════════════════════════════════════════════════
  # Hook-8: GC merged worktrees (runs before evaluating existing-worktree path)
  # ════════════════════════════════════════════════════════════════════════════
  debug_log "Hook-8: Running GC"

  if [[ -n "$PLUGIN_SCRIPTS" ]] && [[ -f "$PLUGIN_SCRIPTS/session-gc.sh" ]]; then
    GC_RAW=$(bash "$PLUGIN_SCRIPTS/session-gc.sh" --max 5 --caller-pid "$PPID" 2>/dev/null || true)
    debug_log "Hook-8: GC output: $GC_RAW"

    # Parse GC output for issue detection
    while IFS= read -r gc_line; do
      [[ -n "$gc_line" ]] || continue
      case "$gc_line" in
        SKIPPED*uncommitted*|SKIPPED*unmerged*|SKIPPED*untracked*)
          GC_ISSUES_COUNT=$((GC_ISSUES_COUNT + 1))
          GC_OUTPUT="${GC_OUTPUT}${gc_line}
"
          ;;
        REMOVED*)
          debug_log "Hook-8: $gc_line"
          ;;
        SKIPPED*)
          debug_log "Hook-8: $gc_line"
          ;;
      esac
    done <<< "$GC_RAW"
  fi

  sweep_orphan_metadata

  debug_log "Hook-8: GC complete"

  # ── Re-scan after GC ─────────────────────────────────────────────────────
  EXISTING_LIST=$(ls -dt .worktrees/session-* 2>/dev/null || true)

  if [[ -n "$EXISTING_LIST" ]]; then
    debug_log "Hook-7: Post-GC survivors found, entering existing-worktree path (Hook-7a)"

    # ══════════════════════════════════════════════════════════════════════════
    # Hook-7a: Existing-worktree path
    # ══════════════════════════════════════════════════════════════════════════

    # Read stale threshold
    STALE_MINUTES=$(read_config_value "session_worktree_stale_minutes" "$CONFIG")
    if [[ -z "$STALE_MINUTES" ]] || ! [[ "$STALE_MINUTES" =~ ^[0-9]+$ ]]; then
      STALE_MINUTES=60
    fi
    debug_log "Hook-7a: Stale threshold: ${STALE_MINUTES}m"

    NOW=$(date +%s)
    WORKTREE_COUNT=0
    WORKTREE_STATS=""
    MOST_RECENT=""
    MOST_RECENT_NAME=""
    MAX_STATS=5

    while IFS= read -r wt_path; do
      [[ -n "$wt_path" ]] || continue
      WORKTREE_COUNT=$((WORKTREE_COUNT + 1))

      wt_name=$(basename "$wt_path")

      # Set most recent (first in mtime-sorted list)
      if [[ -z "$MOST_RECENT" ]]; then
        MOST_RECENT="$wt_path"
        MOST_RECENT_NAME="$wt_name"
      fi

      # Cap per-worktree stats gathering at MAX_STATS
      if [[ $WORKTREE_COUNT -le $MAX_STATS ]]; then
        # Mtime
        wt_mtime=$(get_mtime "$wt_path")
        age_label="unknown"
        is_stale="unknown"
        if [[ -n "$wt_mtime" ]]; then
          age_secs=$((NOW - wt_mtime))
          age_mins=$((age_secs / 60))
          if [[ $age_mins -lt 60 ]]; then
            age_label="${age_mins}m"
          elif [[ $age_mins -lt 1440 ]]; then
            age_label="$((age_mins / 60))h"
          else
            age_label="$((age_mins / 1440))d"
          fi
          if [[ $age_mins -ge $STALE_MINUTES ]]; then
            is_stale="stale"
          else
            is_stale="recent"
          fi
        fi

        # PID liveness — check both new and old format
        pid_status="no-pid"
        # New format: .worktrees/.metadata/<name>/pid.*
        if [[ -d ".worktrees/.metadata/$wt_name" ]]; then
          for pf in .worktrees/.metadata/"$wt_name"/pid.*; do
            [[ -f "$pf" ]] || continue
            pid_val=$(cat "$pf" 2>/dev/null || true)
            if [[ -n "$pid_val" ]] && kill -0 "$pid_val" 2>/dev/null; then
              pid_status="alive:$pid_val"
              break
            fi
          done
        fi
        # Old format backward compat: .worktrees/<name>/.session.pid
        if [[ "$pid_status" == "no-pid" ]] && [[ -f "$wt_path/.session.pid" ]]; then
          old_pid=$(cat "$wt_path/.session.pid" 2>/dev/null || true)
          if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
            pid_status="alive:$old_pid"
          fi
        fi

        # Uncommitted count
        uncommitted=$(git -C "$wt_path" status --porcelain --untracked-files=no 2>/dev/null | wc -l | tr -d '[:space:]')

        # Unmerged count
        wt_branch=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
        unmerged=0
        if [[ -n "$wt_branch" ]]; then
          unmerged=$(git log "${DEFAULT_BRANCH}..${wt_branch}" --oneline 2>/dev/null | wc -l | tr -d '[:space:]')
        fi

        WORKTREE_STATS="${WORKTREE_STATS}  - ${wt_name} (age: ${age_label}, ${is_stale}, PID: ${pid_status}, ${uncommitted} uncommitted, ${unmerged} unmerged)
"
      fi
    done <<< "$EXISTING_LIST"

    debug_log "Hook-7a: $WORKTREE_COUNT worktree(s) found"

    # Write PID to most recent worktree (safe-side — before user choice)
    if [[ -n "$MOST_RECENT_NAME" ]] && [[ -n "$PLUGIN_SCRIPTS" ]] && [[ -f "$PLUGIN_SCRIPTS/write-session-pid.sh" ]]; then
      bash "$PLUGIN_SCRIPTS/write-session-pid.sh" "$MOST_RECENT_NAME" "$PPID" 2>/dev/null || true
      debug_log "Hook-7a: Wrote PID $PPID to $MOST_RECENT_NAME"
    fi

    # Build output based on worktree count and staleness
    OUTPUT="${VERSION_WARNING}"

    if [[ $WORKTREE_COUNT -gt $MAX_STATS ]]; then
      WORKTREE_STATS="${WORKTREE_STATS}  ... and $((WORKTREE_COUNT - MAX_STATS)) more (name only, stats capped at $MAX_STATS)
"
    fi

    # Compose the MANDATORY directive
    if [[ $GC_ISSUES_COUNT -gt 0 ]]; then
      OUTPUT="${OUTPUT}MANDATORY: ${WORKTREE_COUNT} existing session worktree(s) found (${GC_ISSUES_COUNT} have unresolved issues from GC). Ask the user: resume ${MOST_RECENT_NAME}, or create a new one? After cd'ing into your worktree, run /do:start to resolve the worktrees with issues.
"
    else
      OUTPUT="${OUTPUT}MANDATORY: existing session worktree at ${REPO_ROOT}/${MOST_RECENT}. Ask the user: resume ${MOST_RECENT_NAME}, or create a new one?
"
    fi

    OUTPUT="${OUTPUT}
Worktree details:
${WORKTREE_STATS}
Run /do:start to manage session worktrees."

    debug_log "Hook-7a: Emitting existing-worktree output"
    printf '%s\n' "$OUTPUT"
    exit 0
  else
    debug_log "Hook-7: GC cleaned all worktrees, falling through to happy path"
    # Fall through to Hook-9 (happy path)
  fi
else
  debug_log "Hook-7: No existing worktrees"

  # ── Hook-8: Orphan metadata sweep (no worktrees case) ─────────────────────
  sweep_orphan_metadata

  # Fall through to Hook-9 (happy path)
fi

# ══════════════════════════════════════════════════════════════════════════════
# Hook-9: Happy path — create worktree
# ══════════════════════════════════════════════════════════════════════════════
debug_log "Hook-9: Creating new session worktree"

# Generate random 4-char hex ID
SESSION_ID=$(openssl rand -hex 2 2>/dev/null || printf '%04x' $RANDOM)
SESSION_NAME="session-${SESSION_ID}"
SESSION_PATH=".worktrees/${SESSION_NAME}"

debug_log "Hook-9: Attempting bd worktree create $SESSION_PATH"

# First attempt
CREATE_OK=false
if bd worktree create "$SESSION_PATH" 2>/dev/null; then
  CREATE_OK=true
  debug_log "Hook-9: Worktree created on first attempt"
fi

# Retry once with new ID if first attempt failed
if [[ "$CREATE_OK" != "true" ]]; then
  debug_log "Hook-9: First attempt failed, retrying with new ID"
  SESSION_ID=$(openssl rand -hex 2 2>/dev/null || printf '%04x' $RANDOM)
  SESSION_NAME="session-${SESSION_ID}"
  SESSION_PATH=".worktrees/${SESSION_NAME}"

  if bd worktree create "$SESSION_PATH" 2>/dev/null; then
    CREATE_OK=true
    debug_log "Hook-9: Worktree created on retry"
  fi
fi

# Both attempts failed
if [[ "$CREATE_OK" != "true" ]]; then
  debug_log "Hook-9: Both attempts failed, emitting diagnostic"
  OUTPUT="${VERSION_WARNING}Warning: Failed to create session worktree. bd worktree create failed twice.
Fallback: run manually:
  bd worktree create .worktrees/session-<name>
  cd .worktrees/session-<name>"
  printf '%s\n' "$OUTPUT"
  exit 0
fi

# Write PID file
debug_log "Hook-9: Writing PID file for $SESSION_NAME"
PID_WRITE_OK=false

if [[ -n "$PLUGIN_SCRIPTS" ]] && [[ -f "$PLUGIN_SCRIPTS/write-session-pid.sh" ]]; then
  if bash "$PLUGIN_SCRIPTS/write-session-pid.sh" "$SESSION_NAME" "$PPID"; then
    PID_WRITE_OK=true
    debug_log "Hook-9: PID file written"
  fi
fi

# If PID write failed, remove worktree for safety (fail-closed)
if [[ "$PID_WRITE_OK" != "true" ]]; then
  debug_log "Hook-9: PID write failed, removing worktree for safety"
  bd worktree remove "$SESSION_PATH" 2>/dev/null || git worktree remove "$SESSION_PATH" 2>/dev/null || true
  OUTPUT="${VERSION_WARNING}Warning: Worktree created but PID protection failed. Removed worktree for safety. Check .worktrees/.metadata/ permissions. Model should retry: bd worktree create .worktrees/session-<name>"
  printf '%s\n' "$OUTPUT"
  exit 0
fi

# Success — emit MANDATORY directive
debug_log "Hook-9: Success, emitting MANDATORY directive"

OUTPUT="${VERSION_WARNING}"
if [[ $GC_ISSUES_COUNT -gt 0 ]]; then
  OUTPUT="${OUTPUT}MANDATORY: session worktree created at ${SESSION_PATH}. Your FIRST action must be: cd ${REPO_ROOT}/${SESSION_PATH}. After cd'ing, run /do:start to resolve ${GC_ISSUES_COUNT} worktrees with unresolved issues."
else
  OUTPUT="${OUTPUT}MANDATORY: session worktree created at ${SESSION_PATH}. Your FIRST action must be: cd ${REPO_ROOT}/${SESSION_PATH}"
fi

printf '%s\n' "$OUTPUT"
exit 0
