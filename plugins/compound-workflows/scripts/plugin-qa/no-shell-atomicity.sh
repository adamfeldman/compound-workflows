#!/usr/bin/env bash
# name: no-shell-atomicity
# description: Detect .tmp atomic write instructions in LLM-interpreted files
#
# Shell atomicity patterns (.tmp→mv) are legitimate in .sh scripts but
# unnecessary in agent/skill .md files where the Write tool is atomic.
#
# Usage: ./no-shell-atomicity.sh [plugin-root-path]

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/lib.sh"

resolve_plugin_root "${1:-}"
init_findings

# --- Collect scannable files ---
# commands/compound/*.md, skills/*/SKILL.md, agents/**/*.md (excluding references/)

scan_files=()

cmd_dir="$PLUGIN_ROOT/commands/compound"
if [[ -d "$cmd_dir" ]]; then
  for f in "$cmd_dir"/*.md; do
    [[ -f "$f" ]] || continue
    scan_files+=("$f")
  done
fi

for f in "$PLUGIN_ROOT"/skills/*/SKILL.md; do
  [[ -f "$f" ]] || continue
  scan_files+=("$f")
done

while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  case "$f" in */references/*) continue ;; esac
  scan_files+=("$f")
done < <(find "$PLUGIN_ROOT/agents" -name "*.md" 2>/dev/null)

if [[ "${#scan_files[@]}" -eq 0 ]]; then
  echo "Warning: no scannable files found" >&2
  emit_output "Shell Atomicity in Prompts Check"
  exit 0
fi

# --- Grep for .tmp and filter exemptions ---

for f in "${scan_files[@]}"; do
  matches="$(grep -nE '\.tmp' "$f" || true)"
  [[ -n "$matches" ]] || continue

  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    line_num="$(echo "$match" | cut -d: -f1)"
    line_text="$(echo "$match" | cut -d: -f2-)"

    # Exempt: rm -f cleanup lines (orchestrator cleanup)
    case "$line_text" in
      *"rm -f"*|*"rm "*) continue ;;
    esac

    # Exempt: lines with shell-atomicity-exempt marker
    case "$line_text" in
      *"shell-atomicity-exempt"*) continue ;;
    esac

    add_finding "SERIOUS" "$f" "$line_num" "shell-atomicity-in-prompt" \
      ".tmp atomic write pattern in LLM-interpreted file — use Write tool (already atomic)"
  done <<< "$matches"
done

emit_output "Shell Atomicity in Prompts Check"
exit 0
