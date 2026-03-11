#!/usr/bin/env bash
# name: context-lean-grep
# description: Detect context-lean violations in command files
#
# Checks:
#   1. Pattern B: "After receiving the response" + "write it to" (MCP transit)
#   2. TaskOutput calls (banned)
#   3. mcp__pal__clink / mcp__pal__chat calls (require manual verification)
#   4. Task dispatches missing OUTPUT INSTRUCTIONS or [disk-write within 50 lines
#   5. VAR=$() patterns that trigger mid-workflow permission prompts
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

# --- Check 4: Task/Agent dispatches missing OUTPUT INSTRUCTIONS or [disk-write ---
# For each Task or Agent dispatch line, check if OUTPUT INSTRUCTIONS or [disk-write or
# "Write your" or "Write to:" appears within the next 50 lines. If not, flag it.
#
# A "Task dispatch" is a line where Task is at the start (after optional whitespace),
# e.g., `Task general-purpose: "` or `Task subagent (run_in_background: true): "`.
# An "Agent dispatch" is a line where Agent( starts (after optional whitespace),
# e.g., `Agent(subagent_type: "compound-workflows:workflow:red-team-relay", ...)`.
# Lines where "Task" or "Agent" appear mid-sentence (prose descriptions) are skipped.
# Lines containing "context-lean-exempt" are skipped (legitimate exceptions).

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

  # Now scan for Task and Agent dispatches
  current_line=0
  while IFS= read -r line; do
    current_line=$((current_line + 1))

    # Detect dispatch type: Task or Agent
    dispatch_name=""
    if echo "$line" | grep -qE '^\s*Task [a-z][a-z0-9-]+' 2>/dev/null; then
      dispatch_name="$(echo "$line" | grep -oE 'Task [a-z][a-z0-9-]+' | head -1 || true)"
    elif echo "$line" | grep -qE '^\s*Agent\(subagent_type:' 2>/dev/null; then
      # Extract subagent_type value for display
      local_type="$(echo "$line" | grep -oE 'subagent_type: *"[^"]*"' | sed 's/subagent_type: *"//;s/"$//' | head -1 || true)"
      dispatch_name="Agent(${local_type:-unknown})"
    fi

    [[ -z "$dispatch_name" ]] && continue

    # Skip lines marked as legitimate exceptions
    if echo "$line" | grep -qF 'context-lean-exempt' 2>/dev/null; then
      continue
    fi

    # Look ahead 50 lines for OUTPUT INSTRUCTIONS, [disk-write, or Write your/to:
    # (MINOR triage Task blocks can be 40+ lines due to categorization instructions)
    found_output=false
    end_line=$((current_line + 50))
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
    if echo "$window" | grep -qE 'Write (your|to:)' 2>/dev/null; then
      found_output=true
    fi

    if [[ "$found_output" = false ]]; then
      add_finding "SERIOUS" "$f" "$current_line" "dispatch-missing-output-instructions" \
        "$dispatch_name dispatch has no OUTPUT INSTRUCTIONS or disk-write within 50 lines"
    fi
  done < "$lines_file"

  rm -f "$lines_file"
done

# --- Check 5: VAR=$() patterns that trigger mid-workflow permission prompts ---
# Variable assignments with $() command substitution always prompt (first token
# is a variable assignment, no static rule can match). Accepted patterns
# (init blocks, recovery) must be marked with # heuristic-exempt.
# Catches both $() command substitution and $(()) arithmetic expansion
# (both are empirically verified heuristic triggers).

for f in "$cmd_dir"/*.md; do
  [[ -f "$f" ]] || continue
  matches="$(grep -nE '^\s*[A-Z_]+=.*\$\(' "$f" || true)"
  if [[ -n "$matches" ]]; then
    while IFS= read -r match; do
      line_text="$(echo "$match" | cut -d: -f2-)"
      # Skip lines with heuristic-exempt marker
      if echo "$line_text" | grep -qF 'heuristic-exempt' 2>/dev/null; then
        continue
      fi
      line_num="$(echo "$match" | cut -d: -f1)"
      add_finding "SERIOUS" "$f" "$line_num" "var-dollar-paren-heuristic" \
        "VAR=\$() pattern triggers mid-workflow permission prompt — add # heuristic-exempt if intentional"
    done <<< "$matches"
  fi
done

# --- Output ---
emit_output "Context-Lean Grep Check"
exit 0
