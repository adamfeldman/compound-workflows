#!/usr/bin/env bash
# name: unslugged-paths
# description: Detect .workflows/ write paths missing variable placeholders (static filenames overwrite on repeat runs)
#
# A "slugged" path contains at least one variable placeholder:
#   - Angle-bracket tokens: <stem>, <RUN_ID>, <DATE>, <plan-stem>, <topic-stem>, <PR_NUMBER>, <N>, <session-id>, etc.
#   - Shell variables: $UPPER_CASE or ${UPPER_CASE}
#   - Bare UPPER_CASE path segments: PR_NUMBER, RUN_ID (2+ uppercase letters)
#
# Exempt paths:
#   - .workflows/.work-in-progress.d/ (sentinel directory, per-session files intentionally overwrite)
#
# Usage: ./unslugged-paths.sh [plugin-root-path]

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/lib.sh"

resolve_plugin_root "${1:-}"
init_findings

# --- Collect scannable files ---
# All SKILL.md files + command .md files

scan_files=()

for f in "$PLUGIN_ROOT"/skills/*/SKILL.md; do
  [[ -f "$f" ]] || continue
  scan_files+=("$f")
done

for f in "$PLUGIN_ROOT"/skills/*/workflows/*.md; do
  [[ -f "$f" ]] || continue
  scan_files+=("$f")
done

cmd_dir="$PLUGIN_ROOT/commands/compound"
if [[ -d "$cmd_dir" ]]; then
  for f in "$cmd_dir"/*.md; do
    [[ -f "$f" ]] || continue
    scan_files+=("$f")
  done
fi

if [[ "${#scan_files[@]}" -eq 0 ]]; then
  echo "Warning: no skill or command files found" >&2
  emit_output "Unslugged Paths Check"
  exit 0
fi

# --- Check: write paths to .workflows/ must contain variable placeholders ---
# Use file-level grep to find candidate lines, then process only those.

for f in "${scan_files[@]}"; do
  # Find lines with Write.../.workflows/ (not Write(...) permission rules) or > .workflows/
  candidates="$(grep -nE '(Write[^(].*\.workflows/|> \.workflows/)' "$f" || true)"
  [[ -n "$candidates" ]] || continue

  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    line_num="${match%%:*}"
    line_text="${match#*:}"

    # Skip non-write operations: lines starting with mkdir, ls, Read, rm
    stripped="${line_text#"${line_text%%[![:space:]]*}"}"
    case "$stripped" in
      mkdir*|ls\ *|ls$'\t'*|Read*|rm\ *|rm$'\t'*) continue ;;
    esac
    # Bare cat without > (reading, not writing)
    case "$stripped" in
      cat\ *|cat$'\t'*)
        case "$stripped" in
          *">"*) ;; # cat with redirect — keep checking
          *) continue ;; # bare cat — skip
        esac
        ;;
    esac

    # Extract the .workflows/ path from the line
    workflows_path="$(echo "$line_text" | grep -oE '\.workflows/[^ "`'"'"')*]*' | head -1 || true)"
    [[ -n "$workflows_path" ]] || continue

    # Exempt: intentionally static scratch files (overwritten each call, not persisted artifacts)
    case "$workflows_path" in
      .workflows/.work-in-progress.d/*|.workflows/scratch/*) continue ;;
    esac

    # Check if path contains at least one slug token
    has_slug=false

    # Angle-bracket tokens: <anything>
    case "$workflows_path" in
      *"<"*">"*) has_slug=true ;;
    esac

    # Shell variables: $UPPER_CASE or ${UPPER_CASE}
    if [[ "$has_slug" = false ]]; then
      case "$workflows_path" in
        *'$'[A-Z]*) has_slug=true ;;
      esac
    fi

    # Bare UPPER_CASE path segments: e.g., PR_NUMBER, RUN_ID (2+ uppercase letters)
    # These are placeholder tokens used without $ or <> delimiters in some skills
    if [[ "$has_slug" = false ]]; then
      if echo "$workflows_path" | grep -qE '/[A-Z][A-Z_]+(/|$)'; then
        has_slug=true
      fi
    fi

    if [[ "$has_slug" = false ]]; then
      add_finding "SERIOUS" "$f" "$line_num" "unslugged-workflows-path" \
        "Static .workflows/ write path will overwrite on repeat runs: $workflows_path"
    fi
  done <<< "$candidates"
done

# --- Output ---
emit_output "Unslugged Paths Check"
exit 0
