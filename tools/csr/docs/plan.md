---
title: "feat: Claude Session Resume with tmux Integration"
type: feat
status: completed
date: 2026-02-23
note: "HISTORICAL — Pre-implementation spec. Post-implementation changes (transcript_path session name lookup, terminal title behavior discoveries) are documented in exploration-journal.md sections 9-10. The scripts in bin/ reflect the actual as-built state."
---

# Claude Session Resume with tmux Integration

## Context

Adam runs ~15 Claude CLI sessions across 4 Cursor terminal windows, often in the same directory (`~/Work/Strategy`, 283+ sessions). After reboot, restoring specific named sessions requires manually running `claude -r` and picking from a wall of UUIDs. No monitoring exists for sessions that need attention or hit errors.

**Built-in features we leverage (not rebuild):**
- `/rename <name>` assigns human-readable name to a session (stores `custom-title` record in JSONL)
- `claude --resume <name>` resumes by that name
- Session JSONL at `~/.claude/projects/<encoded-path>/<uuid>.jsonl`

**The gaps this fills:**
1. List named sessions from the shell without launching Claude interactively
2. Restore named sessions into tmux windows after reboot
3. macOS notifications when sessions need attention or hit errors

## What We're Building

### 1. `csr` CLI tool (`~/.local/bin/csr`)

Shell script. Two subcommands:

**`csr list [project_dir]`** -- List named sessions for a directory

```
$ csr list
  intellect          2h ago
  xiatech-strategy   1d ago
  cost-model         3d ago
```

- Encodes path (replace `/` with `-`, handle trailing slashes, resolve symlinks via `realpath`)
- Scans `~/.claude/projects/<encoded>/*.jsonl` (top-level only, never recurse into `subagents/`)
- Greps for `"custom-title"` lines (fast -- avoids full JSONL parse)
- Deduplicates by sessionId (take LAST `custom-title` per file -- sessions can be renamed/compacted multiple times)
- Shows: name, relative time since last modified (`stat` mtime)
- Sorted by last modified (most recent first)
- If no named sessions: print "No named sessions for <dir>" to stderr

**`csr restore <name>`** -- Restore a specific session into tmux

- Requires a name argument (no interactive mode)
- Creates tmux window, then sends resume command via `send-keys` (avoids shell injection)
- If not in tmux: print error and exit 1
- If session name not found: print error with `csr list` output as suggestion

**`csr version`** -- Print version string (e.g., `csr 0.1.0`)

**`csr help` / `csr --help` / `csr` with no args** -- Print usage

#### Review Findings

**Critical:**
- Rename `cs` to `csr` -- `cs` collides with claude-squad, an established tool that installs to the same path (`~/.local/bin/cs`). `csr` (claude session resume) is short, mnemonic, and unique. (architecture-strategist)
- Shell injection via `tmux new-window "claude --resume '<name>'"` -- the command string is executed by `/bin/sh -c`, so single quotes in session names break out of quoting. Use `tmux new-window` + `tmux send-keys` pattern instead. (security-sentinel, pattern-recognition)

**Recommendations:**
- Cut interactive `csr restore` (no-arg) mode -- adds ~25 LOC for a use case already covered by `csr list` + `csr restore <name>`. Diverges from non-interactive CLI pattern. (code-simplicity, pattern-recognition)
- Cut "start tmux if not in tmux" fallback -- just error and exit. You know you use tmux. (code-simplicity)
- Drop file size column from `csr list` -- JSONL file size tells you nothing useful. Show name + time only. (code-simplicity)
- Drop duplicate session name dedup logic for v1 -- with 7 named sessions, unlikely to collide. Let duplicates show in list. (code-simplicity)
- Add `csr version` subcommand for debugging parity with `bd`. (pattern-recognition)

**Implementation Details:**
- Use `tmux send-keys` pattern for safe session restoration:
  ```bash
  tmux new-window -t "$TMUX_SESSION" -n "$safe_name"
  tmux set-option -t "$TMUX_SESSION:$safe_name" -p remain-on-exit on
  tmux send-keys -t "$TMUX_SESSION:$safe_name" "claude --resume $(printf '%q' "$session_name")" C-m
  ```
  The `remain-on-exit` ensures the window stays open if `claude --resume` fails (e.g., session already running elsewhere), so the user sees the error.
- Add header comment block matching `bq_cost_measurement.sh` convention. (pattern-recognition)
- Add inline comment: `# If this script exceeds 200 lines, rewrite in Python.` (architecture-strategist)

### 2. Notification hook scripts (`~/.local/bin/`)

Separate script files (matches `statusline-command.sh` pattern). Two hooks:

**`~/.local/bin/notify-attention.sh`** -- Notification hook
- Matcher: `permission_prompt` (skip `auth_success` and `idle_prompt`)
- Reads JSON from stdin, extracts `cwd` basename and `message`
- Fires macOS notification with "Submarine" sound via environment variable passing (no string interpolation)
- Async with 5s timeout

**`~/.local/bin/notify-error.sh`** -- PostToolUseFailure hook
- Skip if `is_interrupt` is true (user cancelled, not a real error) -- use `jq -r '.is_interrupt // false'`
- Reads JSON from stdin, extracts `cwd` basename and `tool_name`
- Fires macOS notification with "Basso" sound via environment variable passing
- Async with 5s timeout

#### Review Findings

**Critical:**
- Shell injection via `osascript -e` string interpolation -- the `message` and `error` fields are interpolated directly into AppleScript. A crafted message with double quotes can escape and execute arbitrary AppleScript. Fix: use environment variable passing. (security-sentinel)
- Timeout unit error -- hooks documentation specifies timeout in **seconds**, not milliseconds. `5000` means 83 minutes. Correct value is `5`. (architecture-strategist, security-sentinel, research--hooks-docs)

**Recommendations:**
- Drop `idle_prompt` from Notification matcher for v1 -- with 15 concurrent sessions, idle notifications from every session will be noisy. Start with `permission_prompt` only. (architecture-strategist)
- Use lowercase variable names (`input`, `dir`, `msg`) to match `statusline-command.sh` convention. UPPERCASE is reserved for environment variables. (pattern-recognition)
- Remove `xargs basename` -- fragile with spaces, empty strings. Use direct `basename --` on variable instead. (security-sentinel, pattern-recognition)
- Add `"async": true` to both hook configs -- these are fire-and-forget side effects that should not block Claude. (architecture-strategist, pattern-recognition)

**Implementation Details:**
- Safe osascript pattern (no string interpolation of untrusted data):
  ```bash
  NOTIF_BODY="$dir: $msg" osascript -e 'display notification (system attribute "NOTIF_BODY") with title "Claude" sound name "Submarine"'
  ```
- Proper `is_interrupt` handling for optional field:
  ```bash
  is_interrupt=$(printf '%s' "$input" | jq -r '.is_interrupt // false')
  if [[ "$is_interrupt" == "true" ]]; then
    exit 0
  fi
  ```
- Two-step basename extraction:
  ```bash
  cwd=$(printf '%s' "$input" | jq -r '.cwd // "unknown"')
  dir=$(basename -- "$cwd")
  ```

### 3. Settings.json merge

Add hooks to existing `~/.claude/settings.json` alongside `SessionStart` and `PreCompact` (preserve those).

#### Review Findings

**Critical:**
- Timeout values must be `5` (seconds), not `5000` (which would be 83 minutes). (research--hooks-docs, architecture-strategist, security-sentinel)

**Recommendations:**
- Use absolute paths in hook commands to match existing `statusline-command.sh` pattern. Not tilde paths. (pattern-recognition)
- Add `"async": true` to both hook entries. (architecture-strategist, pattern-recognition)

## Files to Create/Modify

| File | Action | Lines |
|------|--------|-------|
| `~/.local/bin/csr` | Create | ~80 |
| `~/.local/bin/notify-attention.sh` | Create | ~15 |
| `~/.local/bin/notify-error.sh` | Create | ~15 |
| `~/.claude/settings.json` | Modify (add 2 hook entries) | ~10 added |

## Implementation Details

### Shell conventions (from repo patterns)

- `#!/bin/bash` with `set -uo pipefail` (no `-e` — intentional, matches `bq_cost_measurement.sh`; errors handled per-command)
- `jq` for JSON parsing (via PATH, not hardcoded — works on ARM and Intel Macs)
- `printf` over `echo`
- Named local variables in functions (lowercase)
- Clear error messages to stderr

#### Review Findings

**Recommendations:**
- Add `# If this script exceeds 200 lines, rewrite in Python.` comment at top. (architecture-strategist)
- Add header comment block with description and dependencies, matching `bq_cost_measurement.sh`. (pattern-recognition)
- Consider `CLAUDE_PROJECTS_DIR` env var override for projects directory. Low priority for personal tool. (pattern-recognition)

### Path encoding

```bash
# Claude Code encodes /Users/adamf/Work/Strategy as -Users-adamf-Work-Strategy
encode_path() {
  local dir="$1"
  dir="${dir/#\~/$HOME}"  # expand tilde when quoted (e.g., csr list "~/Work")
  local resolved
  resolved=$(realpath "$dir" 2>/dev/null || echo "$dir")
  resolved="${resolved%/}"  # strip trailing slash
  printf '%s' "$resolved" | tr '/' '-'
}

# macOS BSD stat for mtime (epoch seconds):
#   stat -f %m "$file"
# Relative time display: compare against $(date +%s)
```

#### Review Findings

**Recommendations:**
- Add directory existence check after encoding:
  ```bash
  projects_dir="$HOME/.claude/projects/$(encode_path "$dir")"
  if [[ ! -d "$projects_dir" ]]; then
    printf 'No sessions found for %s\n' "$dir" >&2
    exit 0
  fi
  ```
  (architecture-strategist, pattern-recognition, security-sentinel)
- Note: encoding is non-injective (`/a/b-c` and `/a/b/c` produce same output). Matches Claude Code behavior -- document the limitation, do not fix. (security-sentinel)
- Use `printf '%s'` instead of `echo` in the pipeline for consistency with stated conventions. (pattern-recognition)

### Session name sanitization for tmux

```bash
sanitize_tmux_name() {
  local name="$1"
  # Truncate to 30 chars, replace problematic chars
  printf '%s' "$name" | tr -c '[:alnum:] _-' '_' | cut -c1-30
}
```

#### Review Findings

**Recommendations:**
- code-simplicity says drop this function entirely -- your session names are things like "intellect" and "cost-model" that need no sanitization. Fix edge cases if they arise.
- If kept, note that this only sanitizes the tmux window name. The session name passed to `claude --resume` must be separately escaped with `printf '%q'`. (security-sentinel, pattern-recognition)

### Hook script pattern

```bash
#!/bin/bash
set -uo pipefail  # no -e: intentional, matches bq_cost_measurement.sh — handle errors per-command
input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // "unknown"')
dir=$(basename -- "$cwd")
msg=$(printf '%s' "$input" | jq -r '.message // "needs attention"')
NOTIF_BODY=$(printf '%s: %s' "$dir" "$msg" | tr -d '\000-\037') \
  osascript -e 'display notification (system attribute "NOTIF_BODY") with title "Claude" sound name "Submarine"' 2>/dev/null || true
```

#### Review Findings

**Critical:**
- Previous pattern used `osascript -e "display notification \"$DIR: $MSG\"..."` which allows AppleScript injection. The environment variable pattern above (from security-sentinel) eliminates injection by never putting untrusted data into AppleScript source code. (security-sentinel)
- Previous pattern used `xargs basename` which is fragile with spaces/empty strings. Two-step extraction above is safer. (security-sentinel, pattern-recognition)

**Recommendations:**
- Use lowercase variables (`input`, `dir`, `msg`) to match `statusline-command.sh`. (pattern-recognition)
- Add `2>/dev/null || true` after osascript for graceful failure when Terminal lacks notification permission. (research--best-practices)

### Settings.json additions (merged with existing)

```json
{
  "Notification": [{
    "matcher": "permission_prompt",
    "hooks": [{
      "type": "command",
      "command": "bash /Users/adamf/.claude/hooks/notify-attention.sh",
      "timeout": 5,
      "async": true
    }]
  }],
  "PostToolUseFailure": [{
    "matcher": "",
    "hooks": [{
      "type": "command",
      "command": "bash /Users/adamf/.claude/hooks/notify-error.sh",
      "timeout": 5,
      "async": true
    }]
  }]
}
```

#### Review Findings

**Critical:**
- Timeout changed from `5000` to `5` (seconds, not milliseconds). (research--hooks-docs, architecture-strategist, security-sentinel)

**Recommendations:**
- Absolute paths used instead of tilde paths to match existing `statusline-command.sh` convention. (pattern-recognition)
- `"async": true` added -- notification hooks are fire-and-forget, should not block Claude. (architecture-strategist, pattern-recognition)
- Matcher narrowed from `permission_prompt|idle_prompt` to `permission_prompt` only for v1. (architecture-strategist)

## Edge Cases Addressed

- **Session names with special chars:** `printf '%q'` escaping for `claude --resume`, sanitized for tmux window name
- **Large session dirs (108+ files):** Grep-based scan, no full JSONL parsing
- **No named sessions:** Clear message to stderr
- **Not in tmux:** Error and exit (not auto-start tmux)
- **Format changes:** Defensive checks -- if `~/.claude/projects/` missing or format unrecognized, clear error message
- **Subagent files:** Only top-level `*.jsonl` scanned, never recurse into `subagents/`

#### Review Findings

**Recommendations:**
- Dropped from original: duplicate session name handling, auto-start tmux session, interactive restore mode. All identified as YAGNI for v1. (code-simplicity)
- Explicit subagent exclusion added. The glob `*.jsonl` handles this, but it is now a documented decision. (architecture-strategist)

## Explicitly Cut from v1

- `--layout` save/restore window arrangement (track in beads for v2)
- `--json` output for scripting (first v2 feature -- enables composition with other tools)
- Stop/SessionEnd notifications (too noisy for interactive use)
- Cursor agent CLI support (only Claude Code for now)
- Interactive `cs restore` selection mode (use `csr list` + `csr restore <name>` instead)
- Auto-start tmux when not in tmux (error and exit instead)
- File size column in `csr list` (JSONL size is not meaningful)
- Duplicate session name dedup logic (unlikely with 7 named sessions)
- Notification rate-limiting / debounce (add if noisy in practice)
- `csr setup` subcommand for automated settings.json merge (v2 if distributing)

#### Review Findings

**Recommendations:**
- `--json` should be first v2 feature -- enables piping into claude-squad or other orchestrators. (architecture-strategist)
- Before building `--layout`, re-evaluate whether claude-squad or agent-deck already solve the layout problem. (architecture-strategist)
- Notification hooks are tool-agnostic (work regardless of session manager). Document as standalone components. (architecture-strategist)

## Verification

- [ ] Rename a session: In a Claude session, run `/rename test-session`, exit
- [x] List sessions: `csr list` -- verify "test-session" appears with mtime (verified: 7 named sessions listed)
- [ ] Restore single: `csr restore test-session` -- verify tmux window opens with resumed session
- [ ] Notification hook: Start a session, trigger a permission prompt, verify "Submarine" sound
- [ ] Error hook: Trigger a tool failure, verify "Basso" sound
- [x] Relative path: `csr list ../Strategy` -- verify same output as `csr list`
- [x] Tilde path: `csr list "~/Work/Strategy"` -- verify tilde expands correctly
- [x] No sessions: `csr list /tmp` -- verify "No named sessions" message
- [x] Bad name: `csr restore nonexistent` -- verify error with suggestion
- [x] Test hook manually: `echo '{"cwd":"/tmp","message":"test"}' | bash ~/.local/bin/notify-attention.sh`

#### Review Findings

**Recommendations:**
- Removed "Restore interactive" verification item (interactive mode cut). (code-simplicity)
- Added manual hook test command -- hooks are hard to trigger on demand. (code-simplicity)

## Dependencies

All pre-installed:
- `jq` (via PATH — verified at `/opt/homebrew/bin/jq` on this machine, but not hardcoded)
- `tmux` 3.6a
- `osascript` (macOS built-in)
- `realpath` (`/bin/realpath` on macOS 26.3 — verified; fallback to `readlink -f` if needed)
- `~/.local/bin/` on PATH

Script includes `check_deps()` function that verifies `jq` and `tmux` at startup via `command -v`.

#### Red Team Findings (gemini-3-pro-preview)

**Addressed:**
- Hardcoded `/opt/homebrew/bin/jq` removed — use `jq` via PATH (breaks on Intel Macs otherwise)
- `check_deps()` function added — verify required commands exist before running
- `realpath` verified on this macOS version; portable fallback noted
- `tmux set-option -p remain-on-exit on` added to `csr restore` — if `claude --resume` fails (e.g., session already running), the window stays open showing the error instead of vanishing
- Manual hook trigger added to verification plan for TCC permission check

**Not addressed (accepted risk for personal tool):**
- Session lock detection (checking if session is already running) — complex, low ROI with ~7 named sessions
- tmux window name truncation collision — unlikely with short, user-chosen names

## Ecosystem Context

This tool fills a genuine gap: none of the existing Claude session management tools solve "list my named sessions from the shell and restore them into tmux windows after a reboot." The existing ecosystem consists of session *orchestrators* that manage lifecycles; this is a session *browser* that reads existing state.

| Tool | Relationship |
|------|-------------|
| [claude-squad](https://github.com/smtg-ai/claude-squad) (`cs`) | Full TUI, creates/manages sessions with git worktrees. Different scope -- `csr` only lists/restores existing named sessions |
| [agent-deck](https://github.com/asheshgoplani/agent-deck) | Enterprise session management. `csr` is intentionally minimal |
| [claunch](https://github.com/0xkaz/claunch) | Closest in scope but creates sessions from project configs. `csr` works with existing `/rename`d sessions |
| `claude --resume` (built-in) | `csr` adds: non-interactive listing, tmux window creation, batch restore |

## Sources

- Research: `.workflows/plan-research/claude-session-resume/agents/`
- Deepen-plan run 1: `.workflows/deepen-plan/feat-claude-session-resume-tmux/agents/run-1/`
- Shell conventions: `scripts/bq_cost_measurement.sh`, `~/.claude/statusline-command.sh`
- Hook patterns: `~/.claude/settings.json` (existing `SessionStart`/`PreCompact`)
- Session format: `~/.claude/projects/-Users-adamf-Work-Strategy/*.jsonl`
- Official hooks docs: https://code.claude.com/docs/en/hooks
