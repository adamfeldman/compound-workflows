#!/usr/bin/env bash
# write-session-pid.sh v0.1.0 — Write a per-claimant PID file for session worktree tracking
#
# Usage: write-session-pid.sh <worktree-name> <pid>
#
# Creates .worktrees/.metadata/<worktree-name>/pid.<pid> with the PID as content.
# Multiple sessions can claim the same worktree — each gets its own pid file.
# Session-gc.sh uses these files to determine which worktrees have live sessions.
#
# Exit codes:
#   0 = PID file written successfully
#   1 = error (invalid args, permission denied, etc.)

set -euo pipefail

# ── Validate arguments ────────────────────────────────────────────────────────
if [[ $# -ne 2 ]]; then
  echo "Error: exactly 2 arguments required" >&2
  echo "Usage: write-session-pid.sh <worktree-name> <pid>" >&2
  exit 1
fi

WORKTREE_NAME="$1"
PID_VAL="$2"

# Worktree name must not contain path separators (prevent directory traversal)
if [[ "$WORKTREE_NAME" == */* ]]; then
  echo "Error: worktree name must not contain path separators: '$WORKTREE_NAME'" >&2
  exit 1
fi

# PID must be a positive integer
if [[ ! "$PID_VAL" =~ ^[0-9]+$ ]]; then
  echo "Error: PID must be a positive integer, got: '$PID_VAL'" >&2
  exit 1
fi

if [[ "$PID_VAL" -eq 0 ]]; then
  echo "Error: PID must be a positive integer, got: '$PID_VAL'" >&2
  exit 1
fi

# ── Create metadata directory ─────────────────────────────────────────────────
META_DIR=".worktrees/.metadata/$WORKTREE_NAME"

if ! mkdir -p "$META_DIR" 2>/dev/null; then
  # Retry once after attempting to fix permissions
  chmod 755 .worktrees/.metadata 2>/dev/null || true
  if ! mkdir -p "$META_DIR"; then
    echo "Error: failed to create metadata directory: $META_DIR" >&2
    echo "  Check ownership and permissions of .worktrees/.metadata/" >&2
    exit 1
  fi
fi

# ── Write PID file ────────────────────────────────────────────────────────────
PID_FILE="$META_DIR/pid.$PID_VAL"

if ! echo "$PID_VAL" > "$PID_FILE"; then
  echo "Error: failed to write PID file: $PID_FILE" >&2
  exit 1
fi

exit 0
