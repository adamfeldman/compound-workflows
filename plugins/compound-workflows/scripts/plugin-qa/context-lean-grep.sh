#!/usr/bin/env bash
# name: context-lean-grep
# description: Detect context-lean violations in command files
#
# Checks:
#   1. Pattern B: "After receiving the response" + "write it to" (MCP transit)
#   2. TaskOutput calls (banned)
#   3. mcp__pal__clink / mcp__pal__chat calls (require manual verification)
#   4. Task dispatches missing OUTPUT INSTRUCTIONS or [disk-write within 30 lines
#
# NOTE: This script does NOT skip code blocks. Command files use code blocks
# for actual Task dispatch syntax that Claude Code executes -- these are
# functional content, not documentation examples.
#
# Usage: ./context-lean-grep.sh [plugin-root-path]

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/lib.sh"

resolve_plugin_root "${1:-}"
init_findings

# --- Collect command files ---
cmd_dir="$PLUGIN_ROOT/commands/compound"
if [[ ! -d "$cmd_dir" ]]; then
  echo "Warning: commands/compound/ directory not found" >&2
  emit_output "Context-Lean Grep Check"
  exit 0
fi

# --- Check 1: Pattern B -- "After receiving the response" + "write it to" ---
# These two phrases on the same line or nearby indicate MCP response transiting orchestrator

for f in "$cmd_dir"/*.md; do
  [[ -f "$f" ]] || continue
  line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    # Check for the combined pattern on a single line
    if echo "$line" | grep -qiE 'After receiving the response' 2>/dev/null; then
      if echo "$line" | grep -qiE 'write it to' 2>/dev/null; then
        add_finding "SERIOUS" "$f" "$line_num" "pattern-b-violation" \
          "MCP response transiting orchestrator: 'After receiving the response...write it to'"
      fi
    fi
  done < "$f"
done

# --- Check 2: TaskOutput calls (banned) ---
# Skip ban instruction lines (e.g., "DO NOT call TaskOutput") — only flag actual usage

for f in "$cmd_dir"/*.md; do
  [[ -f "$f" ]] || continue
  matches="$(grep -nE 'TaskOutput' "$f" || true)"
  if [[ -n "$matches" ]]; then
    while IFS= read -r match; do
      line_text="$(echo "$match" | cut -d: -f2-)"
      # Skip lines that are ban instructions (contain "DO NOT" or "NEVER" before TaskOutput)
      if echo "$line_text" | grep -qE '(DO NOT|NEVER|do not|never|banned|ban).*TaskOutput' 2>/dev/null; then
        continue
      fi
      # Skip lines where TaskOutput appears in a negative context
      if echo "$line_text" | grep -qE 'TaskOutput.*(banned|prohibited|forbidden)' 2>/dev/null; then
        continue
      fi
      line_num="$(echo "$match" | cut -d: -f1)"
      add_finding "SERIOUS" "$f" "$line_num" "taskoutput-banned" \
        "TaskOutput is banned -- use file-existence polling instead"
    done <<< "$matches"
  fi
done

# --- Check 3: MCP pal calls -- flag for manual verification ---

for f in "$cmd_dir"/*.md; do
  [[ -f "$f" ]] || continue
  matches="$(grep -nE 'mcp__pal__(clink|chat)' "$f" || true)"
  if [[ -n "$matches" ]]; then
    while IFS= read -r match; do
      line_num="$(echo "$match" | cut -d: -f1)"
      matched_text="$(echo "$match" | cut -d: -f2-)"
      # Extract which tool
      tool="$(echo "$matched_text" | grep -oE 'mcp__pal__(clink|chat)' | head -1 || true)"
      add_finding "INFO" "$f" "$line_num" "mcp-call-needs-verification" \
        "$tool call found -- requires manual verification that it is wrapped in a Task subagent"
    done <<< "$matches"
  fi
done

# --- Check 4: Task dispatches missing OUTPUT INSTRUCTIONS or [disk-write ---
# For each Task dispatch line, check if OUTPUT INSTRUCTIONS or [disk-write appears
# within the next 20 lines. If not, flag it.
#
# A "Task dispatch" is a line matching: ^Task <name> or containing "Task <name>"
# at the start of a markdown instruction (possibly inside a code block).

for f in "$cmd_dir"/*.md; do
  [[ -f "$f" ]] || continue

  # Read entire file into an array (Bash 3.2 compatible -- use while loop)
  line_count=0
  # Use a temp file to hold lines since Bash 3.2 lacks mapfile
  lines_file="$(mktemp)"

  while IFS= read -r line; do
    line_count=$((line_count + 1))
    echo "$line" >> "$lines_file"
  done < "$f"

  # Now scan for Task dispatches
  current_line=0
  while IFS= read -r line; do
    current_line=$((current_line + 1))

    # Match Task dispatches: "Task <agent-name>" with optional modifiers
    if echo "$line" | grep -qE 'Task [a-z][a-z0-9-]+' 2>/dev/null; then
      # Skip lines that are just discussing Task concept (e.g., "each Task")
      # We want actual dispatch lines
      task_name="$(echo "$line" | grep -oE 'Task [a-z][a-z0-9-]+' | head -1 || true)"
      [[ -z "$task_name" ]] && continue

      # Look ahead 30 lines for OUTPUT INSTRUCTIONS or [disk-write
      # (MCP relay Task blocks can be 25+ lines due to embedded prompts)
      found_output=false
      end_line=$((current_line + 30))
      if [[ "$end_line" -gt "$line_count" ]]; then
        end_line="$line_count"
      fi

      # Read the relevant window from the lines file
      window="$(sed -n "${current_line},${end_line}p" "$lines_file" || true)"
      if echo "$window" | grep -qE 'OUTPUT INSTRUCTIONS' 2>/dev/null; then
        found_output=true
      fi
      if echo "$window" | grep -qE '\[disk-write' 2>/dev/null; then
        found_output=true
      fi

      if [[ "$found_output" = false ]]; then
        add_finding "SERIOUS" "$f" "$current_line" "task-missing-output-instructions" \
          "$task_name dispatch has no OUTPUT INSTRUCTIONS or [disk-write within 20 lines"
      fi
    fi
  done < "$lines_file"

  rm -f "$lines_file"
done

# --- Output ---
emit_output "Context-Lean Grep Check"
exit 0
