#!/usr/bin/env bash
# safe-commit.sh — Commit with an isolated temporary index to prevent staging cross-contamination
#
# Usage: bash safe-commit.sh [-m "message" | -F <file>] [file1 file2 ...]
#
# Creates a temporary GIT_INDEX_FILE initialized from HEAD (not the live .git/index),
# stages only the specified files, and commits. The real .git/index is never read or
# modified, preventing one session's staged files from leaking into another session's
# commit.
#
# Exit codes:
#   0 = commit succeeded
#   1 = error (no files specified, git failure, etc.)

set -euo pipefail

# ── Step 1: Create clean temp index from HEAD ────────────────────────────────
GIT_DIR=$(git rev-parse --git-dir)
TEMP_INDEX="$GIT_DIR/tmp-index-$$"
trap 'rm -f "$TEMP_INDEX" "$TEMP_INDEX.lock"' EXIT

GIT_INDEX_FILE="$TEMP_INDEX" git read-tree HEAD

# ── Step 2: Parse arguments ──────────────────────────────────────────────────
# Separate -m/-F commit args from file paths
COMMIT_ARGS=()
FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m)
      if [[ $# -lt 2 ]]; then
        echo "Error: -m requires a message argument" >&2
        exit 1
      fi
      COMMIT_ARGS+=("-m" "$2")
      shift 2
      ;;
    -F)
      if [[ $# -lt 2 ]]; then
        echo "Error: -F requires a file argument" >&2
        exit 1
      fi
      COMMIT_ARGS+=("-F" "$2")
      shift 2
      ;;
    *)
      FILES+=("$1")
      shift
      ;;
  esac
done

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "Error: no files specified to commit" >&2
  echo "Usage: bash safe-commit.sh [-m \"message\" | -F <file>] [file1 file2 ...]" >&2
  exit 1
fi

if [[ ${#COMMIT_ARGS[@]} -eq 0 ]]; then
  echo "Error: no commit message specified (-m or -F required)" >&2
  exit 1
fi

# ── Step 3: Stage files in temp index ────────────────────────────────────────
GIT_INDEX_FILE="$TEMP_INDEX" git add "${FILES[@]}"

# ── Step 4: Commit with temp index ───────────────────────────────────────────
# No copy-back — the real .git/index is NOT updated. This is intentional:
# copying back would overwrite another session's staged state.
GIT_INDEX_FILE="$TEMP_INDEX" git commit "${COMMIT_ARGS[@]}"
