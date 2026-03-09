#!/usr/bin/env bash
# name: stale-references
# description: Detect old namespace references and references to non-existent commands/skills/agents
#
# Usage: ./stale-references.sh [plugin-root-path]

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/lib.sh"

resolve_plugin_root "${1:-}"
init_findings

# --- Build index of existing commands, agents, skills ---

commands_list=""
for f in "$PLUGIN_ROOT"/commands/compound/*.md; do
  [[ -f "$f" ]] || continue
  commands_list="${commands_list}$(basename "$f" .md)"$'\n'
done

agents_list=""
for dir in "$PLUGIN_ROOT"/agents/research "$PLUGIN_ROOT"/agents/review "$PLUGIN_ROOT"/agents/workflow; do
  [[ -d "$dir" ]] || continue
  for f in "$dir"/*.md; do
    [[ -f "$f" ]] || continue
    agents_list="${agents_list}$(basename "$f" .md)"$'\n'
  done
done

# --- Helper: check if line is inside a fenced code block ---
# Count ``` lines above the given line number. Odd count = inside code block.
is_in_code_block() {
  local file="$1"
  local line_num="$2"
  local fence_count
  fence_count=$(head -n "$line_num" "$file" | grep -c '^```' || true)
  (( fence_count % 2 == 1 ))
}

# --- Check 1: Old namespace references (aworkflows: or aworkflows/) ---

while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  rest="${match#*:}"
  line_num="${rest%%:*}"
  line_text="${rest#*:}"

  # Skip CHANGELOG.md
  case "$file" in */CHANGELOG.md) continue ;; esac

  # Skip code blocks
  is_in_code_block "$file" "$line_num" && continue

  matched="$(echo "$line_text" | grep -oE 'aworkflows[:/][^ ]*' || true)"
  add_finding "SERIOUS" "$file" "$line_num" "old-namespace" "Old namespace reference: $matched"
done < <(grep -rnE 'aworkflows[:/]' \
  "$PLUGIN_ROOT/commands" "$PLUGIN_ROOT/agents" "$PLUGIN_ROOT/skills" \
  --include="*.md" 2>/dev/null || true)

# --- Check 2: References to non-existent commands ---

while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  rest="${match#*:}"
  line_num="${rest%%:*}"
  line_text="${rest#*:}"

  # Skip code blocks
  is_in_code_block "$file" "$line_num" && continue

  # Extract command names from this line
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    cmd_name="${ref#compound:}"
    [[ -z "$cmd_name" ]] && continue
    if ! echo "$commands_list" | grep -qxF "$cmd_name" 2>/dev/null; then
      add_finding "SERIOUS" "$file" "$line_num" "missing-command" "Reference to non-existent command: /$ref"
    fi
  done < <(echo "$line_text" | grep -oE 'compound:[a-z][a-z0-9-]*' || true)
done < <(grep -rnE 'compound:[a-z][a-z0-9-]*' \
  "$PLUGIN_ROOT/commands" "$PLUGIN_ROOT/agents" "$PLUGIN_ROOT/skills" \
  --include="*.md" 2>/dev/null || true)

# --- Check 3: Task dispatches to non-existent agents ---
# All real agent names contain hyphens (e.g., pr-comment-resolver, code-simplicity-reviewer).
# Require at least one hyphen to avoid matching English phrases like "Task system".

while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  rest="${match#*:}"
  line_num="${rest%%:*}"
  line_text="${rest#*:}"

  # Skip code blocks
  is_in_code_block "$file" "$line_num" && continue

  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    agent_name="${ref#Task }"
    [[ -z "$agent_name" ]] && continue
    # Skip built-in/generic agent types
    case "$agent_name" in
      general-purpose) continue ;;
    esac
    if ! echo "$agents_list" | grep -qxF "$agent_name" 2>/dev/null; then
      add_finding "SERIOUS" "$file" "$line_num" "missing-agent" "Task dispatch to non-existent agent: $agent_name"
    fi
  done < <(echo "$line_text" | grep -oE 'Task [a-z][a-z0-9]*-[a-z][a-z0-9-]*' || true)
done < <(grep -rnE 'Task [a-z][a-z0-9]*-[a-z][a-z0-9-]+' \
  "$PLUGIN_ROOT/commands" "$PLUGIN_ROOT/agents" "$PLUGIN_ROOT/skills" \
  --include="*.md" 2>/dev/null || true)

# --- Output ---
emit_output "Stale References Check"
exit 0
