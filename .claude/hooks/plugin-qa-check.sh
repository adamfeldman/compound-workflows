#!/usr/bin/env bash
# PostToolUse hook: runs Tier 1 QA scripts after git commits touching plugin files.
# Registered in .claude/settings.local.json (PostToolUse matcher: Bash).
#
# Exit codes:
#   0 = pass (no findings or not applicable)
#   2 = findings detected (surfaces feedback to Claude Code)
#
# SECURITY: tool_input.command is user-controlled (contains commit messages).
# NEVER use eval, backtick substitution, or unquoted expansion on this field.

set -euo pipefail

# --- Dependency check ---
command -v jq >/dev/null 2>&1 || {
  echo "plugin-qa-check: jq not installed, QA enforcement disabled" >&2
  exit 2
}

# --- Read PostToolUse event from stdin ---
input="$(cat)"

# --- Fast path: only act on git commit commands ---
# Use jq to safely test the command field against a regex
is_commit=$(echo "$input" | jq -r '
  (.tool_input.command // "") | test("\\bgit\\b.*\\bcommit\\b")
' 2>/dev/null || echo "false")

if [ "$is_commit" != "true" ]; then
  exit 0
fi

# --- Check sentinel file (suppress during /compound:work) ---
check_sentinel() {
  local sentinel="$1"
  if [ -f "$sentinel" ]; then
    local file_content
    file_content="$(cat "$sentinel" 2>/dev/null || echo "0")"
    # Validate numeric content
    if echo "$file_content" | grep -qE '^[0-9]+$' 2>/dev/null; then
      local sentinel_age=$(( $(date +%s) - file_content ))
      if [ "$sentinel_age" -lt 14400 ]; then
        exit 0  # Within 4 hours — suppressed
      fi
    fi
  fi
}

# Check both CWD and git root (worktree support)
check_sentinel ".workflows/.work-in-progress"
git_root="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
if [ -n "$git_root" ] && [ "$git_root" != "$(pwd)" ]; then
  check_sentinel "$git_root/.workflows/.work-in-progress"
fi

# --- Check if committed files include plugin dirs ---
if ! git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null | \
     grep -qE '^plugins/compound-workflows/(commands|agents|skills)/' 2>/dev/null; then
  exit 0  # No plugin files changed
fi

# --- Run Tier 1 scripts ---
script_dir="plugins/compound-workflows/scripts/plugin-qa"
plugin_root="plugins/compound-workflows"

# If we're not at repo root, try to find scripts relative to git root
if [ ! -d "$script_dir" ] && [ -n "$git_root" ]; then
  script_dir="$git_root/$script_dir"
  plugin_root="$git_root/$plugin_root"
fi

if [ ! -d "$script_dir" ]; then
  exit 0  # Scripts not found — nothing to check
fi

combined_output=""
has_findings=false

for script in "$script_dir"/*.sh; do
  [ -f "$script" ] || continue
  # Skip lib.sh (sourced, not executed)
  [ "$(basename "$script")" = "lib.sh" ] && continue

  script_output="$(bash "$script" "$plugin_root" 2>&1 || true)"
  combined_output="${combined_output}${script_output}"$'\n'

  # Check for non-empty ## Findings section
  if echo "$script_output" | grep -qE '^## Findings' 2>/dev/null; then
    # Check if findings section has content (not just "No findings.")
    if ! echo "$script_output" | grep -q 'No findings\.' 2>/dev/null; then
      has_findings=true
    fi
  fi
done

# --- Report findings ---
if [ "$has_findings" = true ]; then
  echo "Plugin QA findings detected after commit:" >&2
  echo "$combined_output" >&2
  echo "" >&2
  echo "Run \`/compound:plugin-changes-qa\` for full QA (includes semantic checks)" >&2
  exit 2
fi

exit 0
