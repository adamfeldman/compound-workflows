#!/usr/bin/env bash
# name: truncation-check
# description: Verify command and agent files have YAML frontmatter and are not truncated
#
# Usage: ./truncation-check.sh [plugin-root-path]

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/lib.sh"

resolve_plugin_root "${1:-}"
init_findings

# --- Helper: check a file for frontmatter and minimum length ---
# Usage: check_file <file> <min_lines> <file_type>
check_file() {
  local file="$1"
  local min_lines="$2"
  local file_type="$3"

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  # Check YAML frontmatter: first line must be exactly "---"
  local first_line
  first_line="$(head -1 "$file")"
  if [[ "$first_line" != "---" ]]; then
    add_finding "SERIOUS" "$file" "1" "missing-frontmatter" \
      "$file_type file missing YAML frontmatter (first line is not '---')"
  else
    # Check for closing frontmatter delimiter
    # Look for second "---" in first 20 lines (frontmatter should be short)
    local has_closing=false
    local line_num=0
    while IFS= read -r line; do
      line_num=$((line_num + 1))
      [[ "$line_num" -eq 1 ]] && continue  # skip opening ---
      if [[ "$line" = "---" ]]; then
        has_closing=true
        break
      fi
    done < <(head -20 "$file")
    if [[ "$has_closing" = false ]]; then
      add_finding "SERIOUS" "$file" "" "unclosed-frontmatter" \
        "$file_type file has opening '---' but no closing '---' in first 20 lines"
    fi
  fi

  # Check minimum line count
  local line_count
  line_count="$(wc -l < "$file" | tr -d ' ')"
  if [[ "$line_count" -lt "$min_lines" ]]; then
    add_finding "SERIOUS" "$file" "" "truncated-file" \
      "$file_type file appears truncated ($line_count lines, expected >$min_lines)"
  fi
}

# --- Check command files (thin aliases — lowered threshold) ---
for f in "$PLUGIN_ROOT"/commands/compound/*.md; do
  [[ -f "$f" ]] || continue
  check_file "$f" 3 "Command"
done

# --- Check do-* skill files (workflow skills migrated from commands) ---
for f in "$PLUGIN_ROOT"/skills/do-*/SKILL.md; do
  [[ -f "$f" ]] || continue
  check_file "$f" 20 "Skill"
done

# --- Check agent files (direct children of category dirs) ---
for dir in "$PLUGIN_ROOT"/agents/research "$PLUGIN_ROOT"/agents/review "$PLUGIN_ROOT"/agents/workflow; do
  [[ -d "$dir" ]] || continue
  for f in "$dir"/*.md; do
    [[ -f "$f" ]] || continue
    check_file "$f" 5 "Agent"
  done
done

# --- Output ---
emit_output "Truncation Check"
exit 0
