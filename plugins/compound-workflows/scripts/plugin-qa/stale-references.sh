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
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  agents_list="${agents_list}$(basename "$f" .md)"$'\n'
done < <(find "$PLUGIN_ROOT"/agents -name '*.md' -type f 2>/dev/null || true)

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

  # Extract command names from this line (both compound: and do: namespaces)
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    cmd_name="${ref#compound:}"
    [[ -z "$cmd_name" ]] && continue
    if ! echo "$commands_list" | grep -qxF "$cmd_name" 2>/dev/null; then
      add_finding "SERIOUS" "$file" "$line_num" "missing-command" "Reference to non-existent command: /$ref"
    fi
  done < <(echo "$line_text" | grep -oE 'compound:[a-z][a-z0-9-]*' || true)

  # Also check do: namespace references against command list (do:X maps to command X)
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    cmd_name="${ref#do:}"
    [[ -z "$cmd_name" ]] && continue
    if ! echo "$commands_list" | grep -qxF "$cmd_name" 2>/dev/null; then
      # Not a command — will be checked by Check 2b against skills
      :
    fi
  done < <(echo "$line_text" | grep -oE 'do:[a-z][a-z0-9-]*' || true)
done < <(grep -rnE '(compound|do):[a-z][a-z0-9-]*' \
  "$PLUGIN_ROOT/commands" "$PLUGIN_ROOT/agents" "$PLUGIN_ROOT/skills" \
  --include="*.md" 2>/dev/null || true)

# --- Check 2b: References to non-existent do: skills ---
# Build skill name index from do-* directory names

do_skills_list=""
for dir in "$PLUGIN_ROOT"/skills/do-*/; do
  [[ -d "$dir" ]] || continue
  # Extract directory name, convert do-X to X (the part after "do:")
  dir_name="$(basename "$dir")"
  skill_name="${dir_name#do-}"
  do_skills_list="${do_skills_list}${skill_name}"$'\n'
done

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

  # Extract do: skill references from this line
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    skill_name="${ref#do:}"
    [[ -z "$skill_name" ]] && continue
    if ! echo "$do_skills_list" | grep -qxF "$skill_name" 2>/dev/null; then
      add_finding "SERIOUS" "$file" "$line_num" "missing-do-skill" "Reference to non-existent skill: /$ref"
    fi
  done < <(echo "$line_text" | grep -oE 'do:[a-z][a-z0-9-]*' || true)
done < <(grep -rnE 'do:[a-z][a-z0-9-]*' \
  "$PLUGIN_ROOT/commands" "$PLUGIN_ROOT/agents" "$PLUGIN_ROOT/skills" \
  --include="*.md" 2>/dev/null || true)

# --- Check 3: Task/Agent dispatches to non-existent agents ---
# All real agent names contain hyphens (e.g., pr-comment-resolver, code-simplicity-reviewer).
# Require at least one hyphen to avoid matching English phrases like "Task system".
#
# Matches two dispatch syntaxes:
#   Task [agent-name]                                  -- legacy Task dispatch
#   Agent(subagent_type: "namespace:category:name")    -- native Agent dispatch

# Check 3a: Task dispatches (legacy)
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

# Check 3b: Agent dispatches (native)
# Extract subagent_type value, then take the last colon-delimited segment as agent name.
# e.g., "compound-workflows:workflow:red-team-relay" → "red-team-relay"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  rest="${match#*:}"
  line_num="${rest%%:*}"
  line_text="${rest#*:}"

  # Skip code blocks
  is_in_code_block "$file" "$line_num" && continue

  while IFS= read -r subagent_type; do
    [[ -z "$subagent_type" ]] && continue
    # Extract the last colon-delimited segment as the agent name
    agent_name="${subagent_type##*:}"
    [[ -z "$agent_name" ]] && continue
    # Skip built-in/generic agent types
    case "$agent_name" in
      general-purpose) continue ;;
    esac
    # Skip template placeholders (e.g., "<subagent_type from manifest>", "...")
    case "$subagent_type" in
      *"<"*) continue ;;
      "..."|*"...") continue ;;
    esac
    if ! echo "$agents_list" | grep -qxF "$agent_name" 2>/dev/null; then
      add_finding "SERIOUS" "$file" "$line_num" "missing-agent" "Agent dispatch to non-existent agent: $subagent_type (resolved name: $agent_name)"
    fi
  done < <(echo "$line_text" | grep -oE 'Agent\(subagent_type: *"[^"]*"' | sed 's/Agent(subagent_type: *"//;s/"$//' || true)
done < <(grep -rnE 'Agent\(subagent_type: *"[^"]+"' \
  "$PLUGIN_ROOT/commands" "$PLUGIN_ROOT/agents" "$PLUGIN_ROOT/skills" \
  --include="*.md" 2>/dev/null || true)

# --- Output ---
emit_output "Stale References Check"
exit 0
