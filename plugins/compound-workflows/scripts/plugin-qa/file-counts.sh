#!/usr/bin/env bash
# name: file-counts
# description: Compare actual agent/skill/command counts against declared counts in docs
#
# Usage: ./file-counts.sh [plugin-root-path]

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/lib.sh"

resolve_plugin_root "${1:-}"
init_findings

# --- Count actual files ---

# Agents: .md files as direct children of category dirs only
actual_agents=0
for dir in "$PLUGIN_ROOT"/agents/research "$PLUGIN_ROOT"/agents/review "$PLUGIN_ROOT"/agents/workflow; do
  [[ -d "$dir" ]] || continue
  for f in "$dir"/*.md; do
    [[ -f "$f" ]] || continue
    actual_agents=$((actual_agents + 1))
  done
done

# Skills: directories in skills/ that contain SKILL.md
actual_skills=0
for dir in "$PLUGIN_ROOT"/skills/*/; do
  [[ -d "$dir" ]] || continue
  if [[ -f "$dir/SKILL.md" ]]; then
    actual_skills=$((actual_skills + 1))
  fi
done

# Commands: .md files in commands/compound/
actual_commands=0
for f in "$PLUGIN_ROOT"/commands/compound/*.md; do
  [[ -f "$f" ]] || continue
  actual_commands=$((actual_commands + 1))
done

# --- Extract declared counts ---
# Helper: extract first number matching a pattern from a file
# Usage: extract_count <file> <grep-pattern>
# Returns the first number found on the matching line, or "" if none
extract_count() {
  local file="$1"
  local pattern="$2"
  local line
  line="$(grep -E "$pattern" "$file" 2>/dev/null | head -1 || true)"
  if [[ -n "$line" ]]; then
    echo "$line" | grep -oE '[0-9]+' | head -1 || true
  fi
}

# CLAUDE.md
claude_md="$PLUGIN_ROOT/CLAUDE.md"
declared_agents_claude=""
declared_commands_claude=""
if [[ -f "$claude_md" ]]; then
  declared_agents_claude="$(extract_count "$claude_md" 'All [0-9]+ agents')"
  declared_commands_claude="$(extract_count "$claude_md" '[0-9]+ commands')"
fi

# plugin.json
plugin_json="$PLUGIN_ROOT/.claude-plugin/plugin.json"
declared_agents_plugin=""
declared_skills_plugin=""
declared_commands_plugin=""
if [[ -f "$plugin_json" ]]; then
  # Description line contains "N agents, N skills, and N commands"
  desc_line="$(grep -E '"description"' "$plugin_json" 2>/dev/null | head -1 || true)"
  if [[ -n "$desc_line" ]]; then
    declared_agents_plugin="$(echo "$desc_line" | grep -oE '[0-9]+ agents' | grep -oE '[0-9]+' || true)"
    declared_skills_plugin="$(echo "$desc_line" | grep -oE '[0-9]+ skills' | grep -oE '[0-9]+' || true)"
    declared_commands_plugin="$(echo "$desc_line" | grep -oE '[0-9]+ commands' | grep -oE '[0-9]+' || true)"
  fi
fi

# marketplace.json (at repo root, two levels up from plugin root)
marketplace_json="$PLUGIN_ROOT/../../.claude-plugin/marketplace.json"
declared_agents_marketplace=""
declared_skills_marketplace=""
declared_commands_marketplace=""
if [[ -f "$marketplace_json" ]]; then
  desc_line="$(grep -E '"description"' "$marketplace_json" 2>/dev/null | head -1 || true)"
  if [[ -n "$desc_line" ]]; then
    declared_agents_marketplace="$(echo "$desc_line" | grep -oE '[0-9]+ agents' | grep -oE '[0-9]+' || true)"
    declared_skills_marketplace="$(echo "$desc_line" | grep -oE '[0-9]+ skills' | grep -oE '[0-9]+' || true)"
    declared_commands_marketplace="$(echo "$desc_line" | grep -oE '[0-9]+ commands' | grep -oE '[0-9]+' || true)"
  fi
fi

# README.md
readme="$PLUGIN_ROOT/README.md"
declared_agents_readme=""
declared_skills_readme=""
declared_commands_readme=""
if [[ -f "$readme" ]]; then
  # First line with counts: "N agents, N skills, and N commands"
  count_line="$(grep -E '[0-9]+ agents.*[0-9]+ skills.*[0-9]+ commands' "$readme" 2>/dev/null | head -1 || true)"
  if [[ -n "$count_line" ]]; then
    declared_agents_readme="$(echo "$count_line" | grep -oE '[0-9]+ agents' | grep -oE '[0-9]+' || true)"
    declared_skills_readme="$(echo "$count_line" | grep -oE '[0-9]+ skills' | grep -oE '[0-9]+' || true)"
    declared_commands_readme="$(echo "$count_line" | grep -oE '[0-9]+ commands' | grep -oE '[0-9]+' || true)"
  fi
fi

# --- Compare actual vs declared ---

check_count() {
  local entity="$1"
  local actual="$2"
  local declared="$3"
  local source="$4"

  [[ -z "$declared" ]] && return 0
  if [[ "$actual" -ne "$declared" ]]; then
    add_finding "SERIOUS" "$source" "" "count-mismatch" \
      "$entity: actual=$actual, declared=$declared"
  fi
}

# Check agents
check_count "agents" "$actual_agents" "$declared_agents_claude" "CLAUDE.md"
check_count "agents" "$actual_agents" "$declared_agents_plugin" ".claude-plugin/plugin.json"
check_count "agents" "$actual_agents" "$declared_agents_marketplace" "../../.claude-plugin/marketplace.json"
check_count "agents" "$actual_agents" "$declared_agents_readme" "README.md"

# Check skills
check_count "skills" "$actual_skills" "$declared_skills_plugin" ".claude-plugin/plugin.json"
check_count "skills" "$actual_skills" "$declared_skills_marketplace" "../../.claude-plugin/marketplace.json"
check_count "skills" "$actual_skills" "$declared_skills_readme" "README.md"

# Check commands
check_count "commands" "$actual_commands" "$declared_commands_claude" "CLAUDE.md"
check_count "commands" "$actual_commands" "$declared_commands_plugin" ".claude-plugin/plugin.json"
check_count "commands" "$actual_commands" "$declared_commands_marketplace" "../../.claude-plugin/marketplace.json"
check_count "commands" "$actual_commands" "$declared_commands_readme" "README.md"

# --- Output ---
{
  emit_output "File Counts Check"
  echo ""
  echo "## Actual Counts"
  echo ""
  echo "- Agents: $actual_agents (direct children of agents/research/, agents/review/, agents/workflow/)"
  echo "- Skills: $actual_skills (directories in skills/ with SKILL.md)"
  echo "- Commands: $actual_commands (.md files in commands/compound/)"
}

exit 0
