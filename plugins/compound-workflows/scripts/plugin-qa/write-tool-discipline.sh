#!/usr/bin/env bash
# name: write-tool-discipline
# description: Detect heredocs, echo redirects, and git commit -m in LLM-interpreted files
#
# These patterns should use the Write tool or git commit -F instead:
#   - Heredocs (<< EOF): Write tool creates file content directly
#   - Echo redirects (echo >> file): Write tool appends atomically
#   - git commit -m "...": Write tool creates message file, then git commit -F
#
# NOTE: This script contains detection regex strings that would match themselves.
# This is safe because scripts/plugin-qa/ is not in the scan scope.
#
# LIMITATION: The git commit -m regex catches explicit -m flags but NOT
# underspecified prose like "commit your changes" that an LLM might interpret
# as git commit -m. That class of violation requires Tier 2 semantic review.
#
# Usage: ./write-tool-discipline.sh [plugin-root-path]

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/lib.sh"

resolve_plugin_root "${1:-}"
init_findings

# --- Collect scannable files ---
# commands/compound/*.md, skills/*/SKILL.md, skills/*/workflows/*.md,
# agents/**/*.md (excluding references/)

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

for f in "$PLUGIN_ROOT"/skills/*/workflows/*.md; do
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
  emit_output "Write Tool Discipline Check"
  exit 0
fi

# --- Pattern 1: Heredoc ---
# Matches: << 'EOF', << YAML_EOF, <<EOF, <<-EOF, << eof (case-insensitive)
HEREDOC_RE='<<-?\s*['"'"'"]?[A-Za-z_]+['"'"'"]?'

for f in "${scan_files[@]}"; do
  matches="$(grep -niE "$HEREDOC_RE" "$f" || true)"
  [[ -n "$matches" ]] || continue

  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    line_num="$(echo "$match" | cut -d: -f1)"
    line_text="$(echo "$match" | cut -d: -f2-)"

    # Exempt: lines with write-tool-exempt or heuristic-exempt marker
    case "$line_text" in
      *"write-tool-exempt"*|*"heuristic-exempt"*) continue ;;
    esac

    add_finding "SERIOUS" "$f" "$line_num" "heredoc-in-prompt" \
      "Heredoc pattern in LLM-interpreted file — use Write tool to create file content"
  done <<< "$matches"
done

# --- Pattern 2: Echo redirect ---
# Matches: echo '...' >> file, echo "..." >> file
ECHO_REDIRECT_RE='echo\s+.*>>'

for f in "${scan_files[@]}"; do
  matches="$(grep -nE "$ECHO_REDIRECT_RE" "$f" || true)"
  [[ -n "$matches" ]] || continue

  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    line_num="$(echo "$match" | cut -d: -f1)"
    line_text="$(echo "$match" | cut -d: -f2-)"

    # Exempt: lines with write-tool-exempt or heuristic-exempt marker
    case "$line_text" in
      *"write-tool-exempt"*|*"heuristic-exempt"*) continue ;;
    esac

    add_finding "SERIOUS" "$f" "$line_num" "echo-redirect-in-prompt" \
      "Echo redirect pattern in LLM-interpreted file — use Write tool to append content"
  done <<< "$matches"
done

# --- Pattern 3: git commit -m ---
# Matches: git commit -m "...", git commit --amend -m, etc.
GIT_COMMIT_M_RE='git commit\s+.*-m\s'

for f in "${scan_files[@]}"; do
  matches="$(grep -nE "$GIT_COMMIT_M_RE" "$f" || true)"
  [[ -n "$matches" ]] || continue

  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    line_num="$(echo "$match" | cut -d: -f1)"
    line_text="$(echo "$match" | cut -d: -f2-)"

    # Exempt: lines with write-tool-exempt or heuristic-exempt marker
    case "$line_text" in
      *"write-tool-exempt"*|*"heuristic-exempt"*) continue ;;
    esac

    add_finding "SERIOUS" "$f" "$line_num" "git-commit-m-in-prompt" \
      "git commit -m pattern in LLM-interpreted file — use Write tool + git commit -F instead"
  done <<< "$matches"
done

emit_output "Write Tool Discipline Check"
exit 0
