#!/usr/bin/env bash
# auto-approve v2.4.0
# PreToolUse hook: auto-approves known-safe tool calls, falls through for everything else.
# Registered in .claude/settings.json (PreToolUse matcher: "").
#
# Exit behavior:
#   stdout JSON + exit 0 = auto-approve (allow)
#   no stdout + exit 0   = fall through (normal prompting)
#
# SECURITY: tool_input is user-controlled (contains arbitrary commands/paths).
# NEVER use eval, backtick substitution, or unquoted expansion on input fields.
# stdout MUST contain ONLY the JSON decision or nothing — no debug output.

set -euo pipefail

# --- Dependency check ---
# If jq is missing, fall through silently (no auto-approve, no crash)
command -v jq >/dev/null 2>&1 || exit 0

# --- Read PreToolUse event from stdin ---
input="$(cat)"

# --- Extract tool_name and tool_input ---
tool_name="$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
[ -n "$tool_name" ] || exit 0

# --- Project root detection ---
# Prefer cwd from hook input; validate by checking for .claude/ directory
cwd="$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)" || true
project_root=""
if [ -n "$cwd" ] && [ -d "$cwd/.claude" ]; then
  project_root="$cwd"
fi
# Fallback to git root
if [ -z "$project_root" ]; then
  project_root="$(git rev-parse --show-toplevel 2>/dev/null)" || true
fi

# --- Audit log helper ---
log_approval() {
  local detail="$1"
  # Only log if we have a project root with .workflows/
  if [ -n "$project_root" ] && [ -d "$project_root/.workflows" ]; then
    printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$tool_name" "$detail" \
      >> "$project_root/.workflows/.hook-audit.log" 2>/dev/null || true
  fi
}

# --- Approve helper ---
approve() {
  local detail="$1"
  log_approval "$detail"
  echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}'
  exit 0
}

# =============================================================================
# Write / Edit tools — .workflows scoping
# =============================================================================
if [ "$tool_name" = "Write" ] || [ "$tool_name" = "Edit" ]; then
  file_path="$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)" || exit 0
  [ -n "$file_path" ] || exit 0

  # Match relative .workflows/** or absolute */.workflows/**
  case "$file_path" in
    .workflows/*) approve "$file_path" ;;
    */.workflows/*) approve "$file_path" ;;
  esac

  # Not a .workflows path — fall through
  exit 0
fi

# =============================================================================
# Bash tool — full pipeline
# =============================================================================
if [ "$tool_name" = "Bash" ]; then
  command_str="$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
  [ -n "$command_str" ] || exit 0

  # --- Full-command pre-checks (before splitting) ---
  # Command substitution and backticks can appear anywhere, even inside quotes
  # that the splitter might not catch. Check the full command first.
  case "$command_str" in
    *'$('*) exit 0 ;;  # command substitution
  esac
  # Backtick check — use grep to avoid quoting issues in case statements
  if printf '%s' "$command_str" | grep -qF '`'; then
    exit 0
  fi

  # --- Quote-aware compound command splitting ---
  # Split on &&, ||, ;, | that appear outside single/double quotes.
  # Returns segments separated by newlines.
  split_compound() {
    local cmd="$1"
    local len=${#cmd}
    local i=0
    local in_single=false
    local in_double=false
    local segment=""
    local ch prev_ch next_ch

    while [ "$i" -lt "$len" ]; do
      ch="${cmd:$i:1}"
      prev_ch=""
      next_ch=""
      [ "$i" -gt 0 ] && prev_ch="${cmd:$((i-1)):1}"
      [ "$((i+1))" -lt "$len" ] && next_ch="${cmd:$((i+1)):1}"

      # Toggle quote state
      if [ "$ch" = "'" ] && [ "$in_double" = false ]; then
        if [ "$in_single" = true ]; then
          in_single=false
        else
          in_single=true
        fi
        segment="${segment}${ch}"
        i=$((i + 1))
        continue
      fi

      if [ "$ch" = '"' ] && [ "$in_single" = false ]; then
        if [ "$in_double" = true ]; then
          in_double=false
        else
          in_double=true
        fi
        segment="${segment}${ch}"
        i=$((i + 1))
        continue
      fi

      # Only split outside quotes
      if [ "$in_single" = false ] && [ "$in_double" = false ]; then
        # Check for && or ||
        if { [ "$ch" = "&" ] && [ "$next_ch" = "&" ]; } || \
           { [ "$ch" = "|" ] && [ "$next_ch" = "|" ]; }; then
          printf '%s\0' "$segment"
          segment=""
          i=$((i + 2))
          continue
        fi
        # Check for ; or single |
        if [ "$ch" = ";" ]; then
          printf '%s\0' "$segment"
          segment=""
          i=$((i + 1))
          continue
        fi
        if [ "$ch" = "|" ] && [ "$next_ch" != "|" ]; then
          printf '%s\0' "$segment"
          segment=""
          i=$((i + 1))
          continue
        fi
      fi

      segment="${segment}${ch}"
      i=$((i + 1))
    done

    # Emit last segment (null-delimited — safe for multi-line commands)
    [ -n "$segment" ] && printf '%s\0' "$segment"
  }

  # --- Per-segment redirect/heredoc check ---
  # Returns 0 if segment contains redirects or heredocs, 1 if clean
  has_redirects() {
    local seg="$1"
    local len=${#seg}
    local i=0
    local in_single=false
    local in_double=false
    local ch next_ch

    while [ "$i" -lt "$len" ]; do
      ch="${seg:$i:1}"
      next_ch=""
      [ "$((i+1))" -lt "$len" ] && next_ch="${seg:$((i+1)):1}"

      # Toggle quote state
      if [ "$ch" = "'" ] && [ "$in_double" = false ]; then
        in_single=$([ "$in_single" = true ] && echo false || echo true)
        i=$((i + 1))
        continue
      fi
      if [ "$ch" = '"' ] && [ "$in_single" = false ]; then
        in_double=$([ "$in_double" = true ] && echo false || echo true)
        i=$((i + 1))
        continue
      fi

      if [ "$in_single" = false ] && [ "$in_double" = false ]; then
        # Check for << (heredoc)
        if [ "$ch" = "<" ] && [ "$next_ch" = "<" ]; then
          return 0
        fi
        # Check for >> or > (redirect) or 2>
        if [ "$ch" = ">" ]; then
          return 0
        fi
        # Check for 2> (digit before >)
        if [ "$ch" = "2" ] && [ "$next_ch" = ">" ]; then
          return 0
        fi
      fi

      i=$((i + 1))
    done
    return 1
  }

  # --- Extract first token (command name) from a segment ---
  first_token() {
    local seg="$1"
    # Strip leading whitespace
    seg="${seg#"${seg%%[![:space:]]*}"}"
    # Extract first whitespace-delimited token (first line only — multi-line safe)
    printf '%s' "$seg" | awk 'NR==1{print $1; exit}'
  }

  # --- Path validation helper ---
  # Returns 0 if all paths resolve within project_root, 1 otherwise
  validate_paths_in_project() {
    [ -n "$project_root" ] || return 1

    local path
    for path in "$@"; do
      [ -n "$path" ] || continue
      # Resolve path (works even if path doesn't exist yet)
      # Try GNU realpath -m (Linux), grealpath -m (macOS+homebrew), python3 fallback
      local resolved
      resolved="$(realpath -m "$path" 2>/dev/null)" || \
        resolved="$(grealpath -m "$path" 2>/dev/null)" || \
        resolved="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$path" 2>/dev/null)" || \
        return 1
      # Must start with project_root/ (trailing slash prevents prefix collision)
      case "$resolved" in
        "$project_root"/*) ;; # OK
        "$project_root") ;; # Exact match (the root itself)
        *) return 1 ;;
      esac
    done
    return 0
  }

  # --- Safe prefix list ---
  is_safe_prefix() {
    local token="$1"
    case "$token" in
      ls|find|cat|head|tail|wc|grep|sort|uniq|cut|tr) return 0 ;;
      which|sleep|echo|printf|date|uuidgen) return 0 ;;
      cd|touch|realpath|dirname|basename) return 0 ;;
      diff|md5|shasum|read) return 0 ;;
      bd|ccusage|claude) return 0 ;;
      *) return 1 ;;
    esac
  }

  # --- Dangerous git patterns ---
  is_dangerous_git() {
    local seg="$1"
    case "$seg" in
      *"push --force"*|*"push -f"*) return 0 ;;
      *"reset --hard"*) return 0 ;;
      *"clean -f"*|*"clean -fd"*) return 0 ;;
      *"checkout -- ."*) return 0 ;;
      *"restore ."*|*"restore --staged ."*) return 0 ;;
      *"stash drop"*) return 0 ;;
      *"branch -D"*) return 0 ;;
    esac
    return 1
  }

  # --- Validate a single segment ---
  # Returns 0 if segment is safe, 1 if not
  validate_segment() {
    local seg="$1"

    # Per-segment redirect/heredoc check
    if has_redirects "$seg"; then
      return 1
    fi

    local token
    token="$(first_token "$seg")"
    [ -n "$token" ] || return 1

    # Check for variable assignment: VAR=value
    # (command substitution already checked on full command)
    if printf '%s' "$token" | grep -qE '^[A-Za-z_][A-Za-z_0-9]*='; then
      return 0
    fi

    # Safe prefix list
    if is_safe_prefix "$token"; then
      return 0
    fi

    # Git with guardrails
    if [ "$token" = "git" ]; then
      if is_dangerous_git "$seg"; then
        return 1
      fi
      return 0
    fi

    # rm — path-scoped
    if [ "$token" = "rm" ]; then
      # Special deny patterns
      case "$seg" in
        *"rm -rf /"*|*"rm -rf ~"*|*'rm -rf $HOME'*) return 1 ;;
      esac

      # Parse arguments: strip the "rm" command itself, then strip flags
      local args_str
      args_str="$(printf '%s' "$seg" | sed 's/^[[:space:]]*rm[[:space:]]*//')"

      # Check for glob characters in any path argument
      if printf '%s' "$args_str" | grep -qE '[*?[{]'; then
        return 1
      fi

      # Extract path arguments (non-flag tokens) via simple whitespace split
      # SECURITY: Do NOT use eval here — args_str is user-controlled
      local path_args=()
      local word
      for word in $args_str; do
        case "$word" in
          -*) ;; # skip flags
          *) path_args+=("$word") ;;
        esac
      done

      # Must have at least one path
      [ "${#path_args[@]}" -gt 0 ] || return 1

      # Validate all paths within project
      validate_paths_in_project "${path_args[@]}" || return 1
      return 0
    fi

    # mkdir — path-scoped
    if [ "$token" = "mkdir" ]; then
      local args_str
      args_str="$(printf '%s' "$seg" | sed 's/^[[:space:]]*mkdir[[:space:]]*//')"

      # SECURITY: Do NOT use eval here — args_str is user-controlled
      local path_args=()
      local word
      for word in $args_str; do
        case "$word" in
          -*) ;; # skip flags (-p, -v, -m, etc.)
          *) path_args+=("$word") ;;
        esac
      done

      [ "${#path_args[@]}" -gt 0 ] || return 1
      validate_paths_in_project "${path_args[@]}" || return 1
      return 0
    fi

    # bash/python3 — path-scoped
    if [ "$token" = "bash" ] || [ "$token" = "python3" ]; then
      # Extract the script path (first non-flag argument after the command)
      local args_str
      args_str="$(printf '%s' "$seg" | sed "s/^[[:space:]]*${token}[[:space:]]*//")"

      # SECURITY: Do NOT use eval here — args_str is user-controlled
      local script_path=""
      local word
      for word in $args_str; do
        [ -n "$word" ] || continue
        case "$word" in
          -*) ;; # skip flags
          *)
            script_path="$word"
            break
            ;;
        esac
      done

      # Must have a script path
      [ -n "$script_path" ] || return 1
      validate_paths_in_project "$script_path" || return 1
      return 0
    fi

    # Unknown command — not safe
    return 1
  }

  # --- Main Bash validation ---
  # Split into segments and validate each one
  all_safe=true
  detail_for_log="$command_str"

  while IFS= read -r -d '' segment; do
    # Skip empty segments
    trimmed="${segment#"${segment%%[![:space:]]*}"}"
    [ -n "$trimmed" ] || continue

    if ! validate_segment "$segment"; then
      all_safe=false
      break
    fi
  done < <(split_compound "$command_str")

  if [ "$all_safe" = true ]; then
    approve "$detail_for_log"
  fi

  # Fall through — not all segments safe
  exit 0
fi

# =============================================================================
# Everything else — fall through
# =============================================================================
exit 0
