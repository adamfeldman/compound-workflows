#!/usr/bin/env bash
# init-values.sh — Shared init-value emitter for compound-workflows commands
#
# Usage: bash init-values.sh <command-name> [<stem>]
#
# Emits KEY=VALUE pairs to stdout. One pair per line. Keys uppercase, no quoting.
# Model parses by matching line prefix (e.g., "the line starting with PLUGIN_ROOT=").
#
# Supported commands:
#   brainstorm, plan, deepen-plan, review  -> PLUGIN_ROOT, MAIN_ROOT, WORKFLOWS_ROOT, RUN_ID, DATE, STATS_FILE, CACHED_MODEL[, NOTE]
#   work                                   -> PLUGIN_ROOT, MAIN_ROOT, WORKFLOWS_ROOT, RUN_ID, DATE, STEM, STATS_FILE, WORKTREE_MGR, CACHED_MODEL[, NOTE]
#   compact-prep                           -> PLUGIN_ROOT, MAIN_ROOT, WORKFLOWS_ROOT, VERSION_CHECK, DATE, DATE_COMPACT, TIMESTAMP, SNAPSHOT_FILE
#   setup                                  -> PLUGIN_ROOT, VERSION_CHECK
#   plugin-changes-qa, classify-stats      -> REPO_ROOT, PLUGIN_ROOT, MAIN_ROOT, WORKFLOWS_ROOT, DATE, RUN_ID
#   version                                -> VERSION_CHECK
#
# Exit codes:
#   0 = success, valid KEY=VALUE output on stdout
#   1 = invalid arguments, missing paths, or validation failure (errors on stderr)

set -euo pipefail

# ── Resolve PLUGIN_ROOT ──────────────────────────────────────────────────────
# scripts/ is one level below plugin root
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)" || PLUGIN_ROOT=""

# Fallback: find from home directory
if [[ -z "$PLUGIN_ROOT" ]] || [[ ! -d "$PLUGIN_ROOT" ]]; then
  found="$(find ~/.claude/plugins -name "plugin.json" -path "*/compound-workflows/.claude-plugin/*" -exec dirname {} \; 2>/dev/null | head -1)"
  if [[ -n "$found" ]]; then
    PLUGIN_ROOT="$(cd "$found/.." && pwd -P)"
  fi
fi

if [[ -z "$PLUGIN_ROOT" ]] || [[ ! -d "$PLUGIN_ROOT" ]]; then
  echo "Error: PLUGIN_ROOT could not be resolved or does not exist" >&2
  exit 1
fi

if [[ ! -f "$PLUGIN_ROOT/.claude-plugin/plugin.json" ]]; then
  echo "Error: PLUGIN_ROOT validation failed — .claude-plugin/plugin.json not found at $PLUGIN_ROOT" >&2
  echo "  Resolved PLUGIN_ROOT: $PLUGIN_ROOT" >&2
  exit 1
fi

# ── Parse arguments ──────────────────────────────────────────────────────────
CMD="${1:-}"
STEM_ARG="${2:-}"

if [[ -z "$CMD" ]]; then
  echo "Error: command name required as first argument" >&2
  echo "Usage: bash init-values.sh <command-name> [<stem>]" >&2
  exit 1
fi

# ── Sanitize stem ────────────────────────────────────────────────────────────
sanitize_stem() {
  local raw="$1"
  echo "$raw" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9-' '-' | sed 's/^-//;s/-$//'
}

# ── Derive common values ─────────────────────────────────────────────────────
compute_date() {
  date +%Y-%m-%d
}

compute_date_compact() {
  date +%Y%m%d
}

compute_timestamp() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

compute_run_id() {
  uuidgen | cut -c1-8
}

compute_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

compute_main_root() {
  # Returns the main worktree root (the primary checkout), even when running
  # inside a linked worktree. Used for .workflows/ and .claude/memory/ paths
  # that must be shared across all worktrees.
  # Fallback to compute_repo_root if git worktree list fails (prevents /.workflows catastrophe).
  local result
  result=$(git worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //')
  if [[ -n "$result" ]]; then
    echo "$result"
  else
    compute_repo_root
  fi
}


resolve_version_check() {
  local vc="$PLUGIN_ROOT/scripts/version-check.sh"
  if [[ -f "$vc" ]]; then
    echo "$vc"
  else
    find ~/.claude/plugins -name "version-check.sh" -path "*/compound-workflows/*" 2>/dev/null | head -1
  fi
}

resolve_worktree_mgr() {
  local wm="$PLUGIN_ROOT/skills/git-worktree/scripts/worktree-manager.sh"
  if [[ -f "$wm" ]]; then
    echo "$wm"
  else
    find ~/.claude/plugins -name "worktree-manager.sh" -path "*/compound-workflows/*" 2>/dev/null | head -1
  fi
}

# ── Auto-detect branch for work command ───────────────────────────────────────
detect_branch_stem() {
  local branch=""
  branch="$(git branch --show-current 2>/dev/null)" || true
  if [[ -z "$branch" ]]; then
    branch="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')" || true
  fi
  if [[ -z "$branch" ]]; then
    if git rev-parse --verify origin/main >/dev/null 2>&1; then
      branch="main"
    else
      branch="master"
    fi
  fi
  sanitize_stem "$branch"
}

# ── Validation helpers ────────────────────────────────────────────────────────
validate_date() {
  local val="$1"
  if ! echo "$val" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    echo "Error: DATE validation failed: '$val' does not match YYYY-MM-DD" >&2
    exit 1
  fi
}

validate_run_id() {
  local val="$1"
  if ! echo "$val" | grep -qiE '^[0-9A-F]{8}$'; then
    echo "Error: RUN_ID validation failed: '$val' is not 8 hex chars" >&2
    exit 1
  fi
}

validate_plugin_root() {
  if [[ -z "$PLUGIN_ROOT" ]] || [[ ! -d "$PLUGIN_ROOT" ]]; then
    echo "Error: PLUGIN_ROOT validation failed: '$PLUGIN_ROOT' is empty or not a directory" >&2
    exit 1
  fi
}

validate_stats_file() {
  local val="$1"
  if [[ "$val" != *.yaml ]]; then
    echo "Error: STATS_FILE validation failed: '$val' does not end in .yaml" >&2
    exit 1
  fi
}

# ── Per-command output ────────────────────────────────────────────────────────
case "$CMD" in
  brainstorm|plan|deepen-plan|review)
    if [[ -z "$STEM_ARG" ]]; then
      echo "Error: stem argument required for $CMD" >&2
      exit 1
    fi
    STEM="$(sanitize_stem "$STEM_ARG")"
    DATE_VAL="$(compute_date)"
    RUN_ID_VAL="$(compute_run_id)"
    MAIN_ROOT_VAL="$(compute_main_root)"
    WORKFLOWS_ROOT_VAL="${MAIN_ROOT_VAL}/.workflows"
    STATS_FILE_VAL="${WORKFLOWS_ROOT_VAL}/stats/${DATE_VAL}-${CMD}-${STEM}-${RUN_ID_VAL}.yaml"
    mkdir -p "$(dirname "$STATS_FILE_VAL")"

    validate_plugin_root
    validate_date "$DATE_VAL"
    validate_run_id "$RUN_ID_VAL"
    validate_stats_file "$STATS_FILE_VAL"

    echo "PLUGIN_ROOT=$PLUGIN_ROOT"
    echo "MAIN_ROOT=$MAIN_ROOT_VAL"
    echo "WORKFLOWS_ROOT=$WORKFLOWS_ROOT_VAL"
    echo "RUN_ID=$RUN_ID_VAL"
    echo "DATE=$DATE_VAL"
    echo "STATS_FILE=$STATS_FILE_VAL"

    # Subagent model for inherit-model agents
    _csm="${CLAUDE_CODE_SUBAGENT_MODEL:-}"
    echo "CACHED_MODEL=${_csm:-opus}"
    if [[ -n "$_csm" ]]; then
      echo "NOTE=CLAUDE_CODE_SUBAGENT_MODEL is set — agents with model: inherit will use the override. Agents with explicit model: sonnet are unaffected."
    fi
    ;;

  work)
    if [[ -n "$STEM_ARG" ]]; then
      STEM="$(sanitize_stem "$STEM_ARG")"
    else
      STEM="$(detect_branch_stem)"
    fi
    DATE_VAL="$(compute_date)"
    RUN_ID_VAL="$(compute_run_id)"
    MAIN_ROOT_VAL="$(compute_main_root)"
    WORKFLOWS_ROOT_VAL="${MAIN_ROOT_VAL}/.workflows"
    STATS_FILE_VAL="${WORKFLOWS_ROOT_VAL}/stats/${DATE_VAL}-work-${STEM}-${RUN_ID_VAL}.yaml"
    mkdir -p "$(dirname "$STATS_FILE_VAL")"
    WORKTREE_MGR_VAL="$(resolve_worktree_mgr)"

    validate_plugin_root
    validate_date "$DATE_VAL"
    validate_run_id "$RUN_ID_VAL"
    validate_stats_file "$STATS_FILE_VAL"

    echo "PLUGIN_ROOT=$PLUGIN_ROOT"
    echo "MAIN_ROOT=$MAIN_ROOT_VAL"
    echo "WORKFLOWS_ROOT=$WORKFLOWS_ROOT_VAL"
    echo "RUN_ID=$RUN_ID_VAL"
    echo "DATE=$DATE_VAL"
    echo "STEM=$STEM"
    echo "STATS_FILE=$STATS_FILE_VAL"
    echo "WORKTREE_MGR=$WORKTREE_MGR_VAL"

    # Subagent model for inherit-model agents
    _csm="${CLAUDE_CODE_SUBAGENT_MODEL:-}"
    echo "CACHED_MODEL=${_csm:-opus}"
    if [[ -n "$_csm" ]]; then
      echo "NOTE=CLAUDE_CODE_SUBAGENT_MODEL is set — agents with model: inherit will use the override. Agents with explicit model: sonnet are unaffected."
    fi
    ;;

  compact-prep)
    DATE_VAL="$(compute_date)"
    DATE_COMPACT_VAL="$(compute_date_compact)"
    TIMESTAMP_VAL="$(compute_timestamp)"
    VERSION_CHECK_VAL="$(resolve_version_check)"
    MAIN_ROOT_VAL="$(compute_main_root)"
    WORKFLOWS_ROOT_VAL="${MAIN_ROOT_VAL}/.workflows"
    SNAPSHOT_FILE_VAL="${WORKFLOWS_ROOT_VAL}/stats/${DATE_VAL}-ccusage-snapshot.yaml"
    mkdir -p "$(dirname "$SNAPSHOT_FILE_VAL")"

    validate_plugin_root
    validate_date "$DATE_VAL"

    echo "PLUGIN_ROOT=$PLUGIN_ROOT"
    echo "MAIN_ROOT=$MAIN_ROOT_VAL"
    echo "WORKFLOWS_ROOT=$WORKFLOWS_ROOT_VAL"
    echo "VERSION_CHECK=$VERSION_CHECK_VAL"
    echo "DATE=$DATE_VAL"
    echo "DATE_COMPACT=$DATE_COMPACT_VAL"
    echo "TIMESTAMP=$TIMESTAMP_VAL"
    echo "SNAPSHOT_FILE=$SNAPSHOT_FILE_VAL"
    ;;

  setup)
    VERSION_CHECK_VAL="$(resolve_version_check)"

    validate_plugin_root

    echo "PLUGIN_ROOT=$PLUGIN_ROOT"
    echo "VERSION_CHECK=$VERSION_CHECK_VAL"
    ;;

  plugin-changes-qa|classify-stats)
    REPO_ROOT_VAL="$(compute_repo_root)"
    MAIN_ROOT_VAL="$(compute_main_root)"
    WORKFLOWS_ROOT_VAL="${MAIN_ROOT_VAL}/.workflows"
    DATE_VAL="$(compute_date)"
    RUN_ID_VAL="$(compute_run_id)"

    validate_plugin_root
    validate_date "$DATE_VAL"
    validate_run_id "$RUN_ID_VAL"

    echo "REPO_ROOT=$REPO_ROOT_VAL"
    echo "PLUGIN_ROOT=$PLUGIN_ROOT"
    echo "MAIN_ROOT=$MAIN_ROOT_VAL"
    echo "WORKFLOWS_ROOT=$WORKFLOWS_ROOT_VAL"
    echo "DATE=$DATE_VAL"
    echo "RUN_ID=$RUN_ID_VAL"
    ;;

  version)
    VERSION_CHECK_VAL="$(resolve_version_check)"

    echo "VERSION_CHECK=$VERSION_CHECK_VAL"
    ;;

  *)
    echo "Error: unknown command '$CMD'" >&2
    echo "Valid commands: brainstorm, plan, deepen-plan, review, work, compact-prep, setup, plugin-changes-qa, classify-stats, version" >&2
    exit 1
    ;;
esac

exit 0
