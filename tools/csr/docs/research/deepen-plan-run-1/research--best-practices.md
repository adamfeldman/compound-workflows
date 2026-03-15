# Best Practices: Lightweight Bash CLI for Claude Session Resume

Research date: 2026-02-23
Context: Building a ~100-line bash script that lists Claude Code sessions from JSONL files and restores them into tmux windows.

---

## 1. Bash CLI Argument Parsing Patterns

### Recommended Pattern: case + shift (No External Dependencies)

For a lightweight ~100-line tool, skip `getopts` (no long options) and skip external libraries. Use the manual `case`/`shift` pattern directly:

```bash
usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  list              List recent Claude sessions
  restore <id>      Restore session into tmux window

Options:
  -n, --limit NUM   Max sessions to show (default: 10)
  -h, --help        Show this help
EOF
}

# Parse subcommand
cmd="${1:-}"
shift 2>/dev/null || true

case "$cmd" in
  list)
    # parse list-specific flags
    limit=10
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -n|--limit) limit="$2"; shift 2 ;;
        -h|--help)  usage; exit 0 ;;
        *)          echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
      esac
    done
    do_list "$limit"
    ;;
  restore)
    session_id="${1:-}"
    [[ -z "$session_id" ]] && { echo "Error: session id required" >&2; exit 1; }
    do_restore "$session_id"
    ;;
  -h|--help|"")
    usage; exit 0
    ;;
  *)
    echo "Unknown command: $cmd" >&2; usage >&2; exit 1
    ;;
esac
```

### Key Rules

- **Always provide `--help`** and show it on empty input. A CLI without help is hostile.
- **Exit non-zero on errors** and send error messages to stderr (`>&2`).
- **Initialize defaults before parsing.** Don't rely on unset variables.
- **Use `shift 2` for flags with values** (`--limit 10`), `shift` alone for booleans.
- **Catch the wildcard `*)`** to reject unknown flags explicitly rather than silently ignoring them.
- **If the script grows past ~150 lines of logic, switch to Python.** Bash argument parsing becomes a maintenance liability at scale.

Sources:
- [Robustly parsing flags in Bash scripts (2025)](https://iafisher.com/blog/2025/08/robustly-parsing-flags-in-bash-scripts)
- [Parse Command Line Arguments in Bash - Baeldung](https://www.baeldung.com/linux/bash-parse-command-line-arguments)
- [Bash Argument Parsing - Medium](https://medium.com/@Drew_Stokes/bash-argument-parsing-54f3b81a6a8f)

---

## 2. Safe Shell Scripting for Untrusted Input

### Strict Mode Header

Every bash script should start with this:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

| Flag | Effect |
|------|--------|
| `-e` | Exit immediately on non-zero exit status |
| `-u` | Treat unset variables as errors |
| `-o pipefail` | Pipeline fails if ANY command in the pipe fails, not just the last |

**Caveats with `set -e`:**
- Commands in `if` conditions, `||`, and `&&` chains are exempt. `if ! command; then` does NOT trigger `-e`.
- Subshells inherit `-e` but functions called without `||` or `if` propagate it.
- To allow a specific command to fail: `command_that_may_fail || true`

### Quoting: The Single Most Important Rule

**Always double-quote variable expansions.** No exceptions for "I know it won't have spaces."

```bash
# WRONG - word-splitting and glob expansion
rm $file
ls $dir

# RIGHT
rm "$file"
ls "$dir"

# Passing all arguments to another command
wrapped_command "$@"    # preserves argument boundaries
# NOT $@ or $*
```

### Sanitizing Session Names (Special Characters)

Claude Code session names may contain spaces, quotes, or other special characters. Strategies:

```bash
# 1. Validate with a regex - reject anything unexpected
if [[ ! "$session_name" =~ ^[a-zA-Z0-9_.\ -]+$ ]]; then
  echo "Error: session name contains invalid characters" >&2
  exit 1
fi

# 2. Sanitize for use as tmux window name (replace unsafe chars)
safe_name="${session_name//[^a-zA-Z0-9_.-]/_}"

# 3. Use printf %q to get a shell-safe quoted version
printf '%q\n' "$session_name"

# 4. Bash 4.4+ parameter transformation
echo "${session_name@Q}"
```

### Trap for Cleanup

```bash
cleanup() {
  # Remove temp files, restore state
  [[ -f "$tmpfile" ]] && rm -f "$tmpfile"
}
trap cleanup EXIT        # Always runs on exit
trap cleanup ERR         # Runs on error (with set -e)
trap 'exit 130' INT      # Ctrl+C: exit with standard code
trap 'exit 143' TERM     # kill: exit with standard code
```

### Critical Safety Practices

- **Use `--` to end option parsing** before passing variables as arguments: `grep -- "$pattern" "$file"`
- **Never use `eval` with user input.** Period.
- **Use `[[ ]]` instead of `[ ]`** -- double brackets don't do word splitting or pathname expansion.
- **Run ShellCheck** on every script: `shellcheck script.sh` catches quoting bugs, uninitialized variables, and portability issues automatically.
- **`IFS` management:** The default IFS (`space tab newline`) is fine for most scripts. Only change it if you're doing field splitting on specific delimiters, and restore it afterward.

Sources:
- [Writing Safe Shell Scripts - MIT SIPB](https://sipb.mit.edu/doc/safe-shell/)
- [Safer Bash Scripts with set -euxo pipefail](https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/)
- [Bash Traps: Exit, Error, Sigint](https://brandonrozek.com/blog/bash-traps-exit-error-sigint/)
- [Securing Your Bash Scripts](https://www.fosslinux.com/101589/bash-security-tips-securing-your-scripts-and-preventing-vulnerabilities.htm)
- [Apple Shell Script Security](https://developer.apple.com/library/archive/documentation/OpenSource/Conceptual/ShellScripting/ShellScriptSecurity/ShellScriptSecurity.html)

---

## 3. macOS osascript Notification Best Practices

### Basic Command

```bash
osascript -e 'display notification "Session restored" with title "Claude Sessions" sound name "Pop"'
```

Parameters:
- **body text** (first string): notification body
- **with title**: bold title
- **subtitle**: smaller text below title
- **sound name**: any file from `/System/Library/Sounds/` (e.g., "Pop", "Ping", "Glass", "Basso")

### The Sequoia/Sonoma Pitfall (Critical)

**`display notification` may silently fail when called from Terminal via osascript.** This is the #1 gotcha.

**Root cause:** macOS notification permissions are per-application. Terminal.app (or whatever terminal emulator you use) must have notification permission granted in System Settings > Notifications. The osascript command runs in the context of the calling application.

**Workarounds:**

1. **Grant Terminal notification permission:** Run `display notification` once from Script Editor to trigger the system permission prompt. This sometimes bootstraps Terminal's permission too.

2. **Check notification settings:** System Settings > Notifications > Terminal (or your terminal app). Ensure notifications are allowed.

3. **Use heredoc syntax** instead of `-e` (reportedly more reliable in some cases):
   ```bash
   osascript <<'EOF'
   display notification "Session restored" with title "Claude Sessions"
   EOF
   ```

4. **Focus Mode interference:** If Focus is on, notifications are suppressed regardless of app permissions.

5. **Fallback gracefully:** Always treat notifications as optional. Don't let notification failure break the script:
   ```bash
   notify() {
     osascript -e "display notification \"$1\" with title \"$2\"" 2>/dev/null || true
   }
   ```

### Design Recommendations

- **Notifications are fire-and-forget.** Never depend on them for user-critical information. Always print to stdout as well.
- **Keep notifications brief.** They truncate after ~2 lines of body text.
- **Don't spam.** One notification per user action, not one per file processed.
- **Sound names must match exactly** or macOS plays the default alert sound. Use `ls /System/Library/Sounds/` to see available options.

Sources:
- [Apple: Displaying Notifications](https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/DisplayNotifications.html)
- [Trigger Notifications from macOS Terminal](https://swissmacuser.ch/native-macos-notifications-from-terminal-scripts/)
- [Display Notification Issues - Late Night Software Forum](https://forum.latenightsw.com/t/trying-to-use-terminal-for-display-notification/5068)

---

## 4. tmux Scripting Best Practices

### Detecting tmux State

```bash
# Check if currently inside a tmux session
if [[ -n "${TMUX:-}" ]]; then
  echo "Inside tmux"
else
  echo "Outside tmux"
fi

# Check if tmux server is running at all
if tmux list-sessions &>/dev/null; then
  echo "tmux server is running"
fi
```

The `$TMUX` environment variable is set inside tmux sessions. Always use `${TMUX:-}` with `set -u` to avoid unbound variable errors.

### Checking if a Session Exists

```bash
# Preferred: has-session (purpose-built, returns exit code)
if tmux has-session -t "my-session" 2>/dev/null; then
  echo "Session exists"
fi

# Alternative: grep list-sessions (less precise, matches substrings)
# AVOID this - "work" would match "work" and "workspace"
tmux list-sessions | grep "work"
```

**Always use `has-session`** over grep-based approaches. It's exact-match and purpose-built.

### Creating Sessions and Windows

```bash
SESSION="claude-sessions"

# Create session detached (essential for scripting)
tmux new-session -d -s "$SESSION" -n "main"

# Create additional windows
tmux new-window -t "$SESSION" -n "session-1"

# Rename the first window (window 0 is auto-created with the session)
tmux rename-window -t "$SESSION:0" "main"

# Send a command to a specific window
tmux send-keys -t "$SESSION:session-1" "claude --resume abc123" C-m
```

**Key flags:**
- `-d`: Detached. Essential for non-interactive scripting. Without it, tmux tries to attach immediately.
- `-s`: Session name.
- `-n`: Window name.
- `-t`: Target (session, window, or pane).

### The Idiomatic Create-or-Attach Pattern

```bash
SESSION="claude-sessions"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  # Session doesn't exist - create it
  tmux new-session -d -s "$SESSION" -n "main"
  # ... set up windows ...
fi

# Attach or switch depending on context
if [[ -n "${TMUX:-}" ]]; then
  # Already inside tmux - switch to the session
  tmux switch-client -t "$SESSION"
else
  # Outside tmux - attach to the session
  tmux attach-session -t "$SESSION"
fi
```

### Naming Conventions

- **Session names:** Lowercase, hyphens for separators (`claude-sessions`, not `Claude Sessions`).
- **Window names:** Descriptive but short. Use the session/project name as context.
- **Avoid special characters** in session/window names. Tmux allows them but they complicate targeting (`-t`).
- Sanitize user-provided names before passing to tmux:
  ```bash
  # Replace non-alphanumeric chars (except hyphen/underscore) with hyphens
  tmux_safe_name="${raw_name//[^a-zA-Z0-9_-]/-}"
  ```

### Machine-Parseable Output

```bash
# Use -F for format strings instead of parsing default output
tmux list-sessions -F "#{session_name}|#{session_windows}|#{session_created}"
tmux list-windows -t "$SESSION" -F "#{window_index}|#{window_name}|#{pane_current_command}"
```

Format strings are stable across tmux versions and don't break when display formatting changes.

Sources:
- [Tao of tmux: Scripting](https://tao-of-tmux.readthedocs.io/en/latest/manuscript/10-scripting.html)
- [Scripting Tmux Workspaces](https://ryan.himmelwright.net/post/scripting-tmux-workspaces/)
- [tmux Scripting - Peter Debelak](https://www.peterdebelak.com/blog/tmux-scripting/)
- [Check tmux Session Exists in Script](https://davidltran.com/blog/check-tmux-session-exists-script/)
- [tmux Getting Started Wiki](https://github.com/tmux/tmux/wiki/Getting-Started)

---

## 5. JSONL File Processing with grep + jq

### Architecture: grep for Pre-filtering, jq for Parsing

The optimal pattern for scanning many JSONL files is a two-stage pipeline:

1. **Stage 1 (grep):** Fast text-pattern matching to eliminate files/lines that can't possibly match.
2. **Stage 2 (jq):** Structured JSON parsing on the reduced dataset.

```bash
# Find JSONL files containing a session type, then parse with jq
grep -l '"type":"human"' "$sessions_dir"/*.jsonl | while read -r file; do
  jq -r 'select(.type == "human") | .message' "$file"
done

# Or inline: grep pre-filters lines, jq parses matches
grep '"session_id"' "$file" | jq -r '.session_id'
```

**Why this matters:** grep is 10-100x faster than jq for raw text scanning. On hundreds of JSONL files, grep eliminates non-matching files before jq even starts, dramatically reducing total parse time.

### jq Performance Patterns

```bash
# Line-by-line (default for JSONL) - memory efficient, preferred
jq -r '.field' file.jsonl

# Compact output (-c) - reduces I/O when piping between tools
jq -c 'select(.type == "human")' file.jsonl

# Slurp (-s) - loads ALL lines into array. Use only for small files or aggregation
jq -s 'sort_by(.timestamp) | last' file.jsonl

# Raw output (-r) - strips quotes from string output
jq -r '.session_name' file.jsonl

# Handle malformed lines gracefully
jq -r 'try .field catch empty' file.jsonl

# Or pre-filter with grep to skip non-JSON lines
grep '^{' file.jsonl | jq -r '.field'
```

### Processing Multiple Files Efficiently

```bash
# GOOD: Find files first, then process
# grep -l is fast - it stops reading each file at first match
matching_files=$(grep -rl '"session"' "$dir"/*.jsonl 2>/dev/null)
for file in $matching_files; do
  jq -r '.session // empty' "$file"
done

# GOOD: Process all files in one jq invocation (if all files are small)
jq -r '.session // empty' "$dir"/*.jsonl

# BAD: Spawning jq per-line (process overhead dominates)
while read -r line; do
  echo "$line" | jq '.field'  # DON'T do this
done < file.jsonl

# BETTER: Let jq handle the iteration natively
jq -r '.field' file.jsonl
```

### Extracting Session Metadata (Specific Pattern)

For Claude Code JSONL sessions, a likely pattern:

```bash
# Get the first human message as a session summary
get_session_summary() {
  local file="$1"
  # grep pre-filters to lines containing "human", then jq parses
  grep '"human"' "$file" | head -1 | jq -r '.message // "No message"' 2>/dev/null
}

# Get last modified time (using stat, see Section 6 for portability)
get_session_time() {
  local file="$1"
  stat -f %m "$file"  # macOS
}
```

### The 120-Character Rule

When your jq expression exceeds ~120 characters between single quotes, it's time to either:
1. Extract the jq filter into a file: `jq -f filter.jq file.jsonl`
2. Switch to Python with the `json` module

Sources:
- [JSON, JSONlines, and jq as a better grep](https://zxvf.org/post/jq-as-grep/)
- [How to Transform JSON Data with jq - DigitalOcean](https://www.digitalocean.com/community/tutorials/how-to-transform-json-data-with-jq)
- [Process Large JSON Streams with jq in 2026](https://copyprogramming.com/howto/process-large-json-stream-with-jq)
- [jq 1.8 Manual](https://jqlang.org/manual/)

---

## 6. Portable Bash Patterns for macOS

### realpath / readlink

| Tool | Linux | macOS (pre-Ventura) | macOS (Ventura+) |
|------|-------|---------------------|------------------|
| `realpath` | Available | NOT available | Available |
| `readlink -f` | Works | NOT supported (BSD readlink) | NOT supported |
| `readlink` (no flags) | Works | Works (one symlink level) | Works |

**Recommended portable pattern:**

```bash
# Get the directory of the currently running script (handles symlinks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)"

# If you need realpath and can assume macOS Ventura+ (13+) or Homebrew:
resolve_path() {
  if command -v realpath &>/dev/null; then
    realpath "$1"
  elif command -v greadlink &>/dev/null; then
    greadlink -f "$1"
  else
    # Fallback: cd + pwd -P (works everywhere but doesn't handle non-existent paths)
    (cd "$(dirname "$1")" &>/dev/null && echo "$(pwd -P)/$(basename "$1")")
  fi
}
```

**For this specific tool (macOS-targeted, 2026):** `realpath` is available on all current macOS versions. You can use it directly if you document a minimum macOS version of Ventura (13.0). If you want to support older macOS, use the `SCRIPT_DIR` pattern above.

### stat Syntax

| Purpose | GNU/Linux | macOS (BSD) |
|---------|-----------|-------------|
| File size | `stat -c %s file` | `stat -f %z file` |
| Modification time (epoch) | `stat -c %Y file` | `stat -f %m file` |
| Permissions (octal) | `stat -c %a file` | `stat -f %Lp file` |

**Portable wrapper:**

```bash
# Get modification time as epoch seconds
file_mtime() {
  if stat -c %Y "$1" &>/dev/null 2>&1; then
    stat -c %Y "$1"    # GNU
  else
    stat -f %m "$1"    # BSD/macOS
  fi
}
```

**For macOS-only tools:** Just use the BSD syntax directly. Don't add GNU detection overhead if your target is exclusively macOS.

### sed -i (In-Place Editing)

```bash
# GNU: sed -i 's/old/new/' file
# macOS BSD: sed -i '' 's/old/new/' file (requires empty string for backup extension)

# Portable:
if [[ "$(uname)" == "Darwin" ]]; then
  sed -i '' 's/old/new/' file
else
  sed -i 's/old/new/' file
fi
```

Not likely needed for this tool, but worth knowing.

### date Command

```bash
# Convert epoch to human-readable
# GNU: date -d @1708700000 "+%Y-%m-%d %H:%M"
# macOS: date -r 1708700000 "+%Y-%m-%d %H:%M"

format_epoch() {
  local epoch="$1"
  if date -d @0 &>/dev/null 2>&1; then
    date -d "@$epoch" "+%Y-%m-%d %H:%M"   # GNU
  else
    date -r "$epoch" "+%Y-%m-%d %H:%M"    # macOS/BSD
  fi
}
```

### Other macOS Gotchas

- **Bash version:** macOS ships bash 3.2 (2007!) due to GPL v3 licensing. Associative arrays (`declare -A`) require bash 4+. Either use `#!/usr/bin/env bash` and document the requirement, or stick to indexed arrays and avoid bash 4+ features.
- **`#!/usr/bin/env bash`** is more portable than `#!/bin/bash` (Homebrew bash may be at `/opt/homebrew/bin/bash` on Apple Silicon).
- **`mktemp` works the same** on both platforms for creating temporary files.
- **`grep -P` (Perl regex) is NOT available** on macOS. Use `grep -E` (extended regex) instead.
- **`sort -V` (version sort) is NOT available** on macOS BSD sort. Use Homebrew `gsort` or avoid it.

Sources:
- [Write Cross-Platform Shell: Linux vs macOS Differences](https://tech-champion.com/programming/write-cross-platform-shell-linux-vs-macos-differences-that-break-production/)
- [How to Write Portable Shell Scripts (2026)](https://oneuptime.com/blog/post/2026-01-24-portable-shell-scripts/view)
- [Using GNU command line tools in macOS](https://gist.github.com/skyzyx/3438280b18e4f7c490db8a2a2ca0b9da)
- [Portable realpath implementations on GitHub](https://github.com/mkropat/sh-realpath)

---

## Recommended Script Skeleton

Combining all the above into a starting template:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)"
readonly SESSIONS_DIR="${HOME}/.claude/sessions"  # adjust as needed
readonly TMUX_SESSION="claude"

# --- Helpers ---

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  list              List recent Claude sessions
  restore <id>      Restore session into tmux window

Options:
  -n, --limit NUM   Max sessions to show (default: 10)
  -h, --help        Show this help
EOF
}

die() { echo "Error: $*" >&2; exit 1; }

notify() {
  osascript -e "display notification \"$1\" with title \"Claude Sessions\"" 2>/dev/null || true
}

# Sanitize for tmux window name
tmux_safe_name() {
  local name="$1"
  echo "${name//[^a-zA-Z0-9_.-]/-}"
}

# macOS-compatible epoch to date
format_time() {
  date -r "$1" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown"
}

# --- Commands ---

cmd_list() {
  local limit="${1:-10}"
  # Pre-filter with grep, parse with jq, sort by time
  # Implementation here...
}

cmd_restore() {
  local session_id="$1"
  local safe_name
  safe_name="$(tmux_safe_name "$session_id")"

  # Create or reuse tmux session
  if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    tmux new-session -d -s "$TMUX_SESSION" -n "$safe_name"
  else
    tmux new-window -t "$TMUX_SESSION" -n "$safe_name"
  fi

  tmux send-keys -t "$TMUX_SESSION:$safe_name" "claude --resume $session_id" C-m

  # Attach or switch
  if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "$TMUX_SESSION:$safe_name"
  else
    tmux attach-session -t "$TMUX_SESSION:$safe_name"
  fi

  notify "Session $session_id restored"
}

# --- Main ---

cmd="${1:-}"
shift 2>/dev/null || true

case "$cmd" in
  list)
    limit=10
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -n|--limit) limit="$2"; shift 2 ;;
        -h|--help)  usage; exit 0 ;;
        *)          die "Unknown option: $1" ;;
      esac
    done
    cmd_list "$limit"
    ;;
  restore)
    [[ $# -eq 0 ]] && die "Session ID required"
    cmd_restore "$1"
    ;;
  -h|--help|"")
    usage
    ;;
  *)
    die "Unknown command: $cmd"
    ;;
esac
```

---

## Key Tradeoffs and Decisions

| Decision | Recommendation | Rationale |
|----------|---------------|-----------|
| Argument parser | Manual case/shift | No dependencies, sufficient for 2-3 subcommands |
| Strict mode | `set -euo pipefail` | Non-negotiable for any bash tool |
| macOS portability | Target macOS only (BSD stat, realpath) | No need for GNU compat if this is a personal/team tool |
| Bash version | Stick to bash 3.2 features OR require bash 5+ via Homebrew | Associative arrays need 4+; decide upfront |
| JSONL parsing | grep pre-filter + jq | grep -l finds relevant files fast, jq parses structure |
| tmux detection | `$TMUX` variable + `has-session` | Standard, reliable, no parsing hacks |
| Notifications | osascript with silent fallback | May not work without Terminal notification permission |
| Session name safety | Regex sanitize to `[a-zA-Z0-9_.-]` | tmux targets break with special chars |
