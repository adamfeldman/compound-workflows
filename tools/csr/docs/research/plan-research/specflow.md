# Spec Flow Analysis: `cs` — Claude Session Resume CLI Tool

**Date:** 2026-02-23
**Spec source:** `/Users/adamf/.claude/plans/sprightly-weaving-pumpkin.md`
**Research inputs:** `repo-research.md`, `learnings.md`, Claude Code hooks reference documentation

---

## User Flow Overview

### Flow 1: List named sessions for current directory

1. User runs `cs list` from a project directory (e.g., `~/Work/Strategy`)
2. Tool encodes the absolute path of `$PWD` (replace `/` with `-`)
3. Tool scans `~/.claude/projects/<encoded>/` for `.jsonl` files
4. For each file, grep for `"type":"custom-title"` lines
5. Extract `customTitle` via `jq`, deduplicate by sessionId (take last occurrence)
6. Get last line timestamp for "last activity"
7. Get line count for "message count"
8. Output formatted table sorted by last activity (most recent first)

### Flow 2: List named sessions for a specified directory

1. User runs `cs list ~/Work/Dev/RAD`
2. Tool resolves the argument to an absolute path (handles `~`, relative paths, symlinks)
3. Same as Flow 1 from step 2 onward, using the specified path instead of `$PWD`

### Flow 3: Restore a single named session

1. User runs `cs restore intellect`
2. Tool runs `cs list` internally to find matching session
3. Tool checks if currently inside tmux (`$TMUX` env var)
4. If in tmux: creates a new tmux window named after the session, runs `claude --resume '<name>'` in it
5. If not in tmux: starts a new tmux session, then creates the window

### Flow 4: Restore all named sessions

1. User runs `cs restore` (no argument)
2. Tool runs `cs list` to enumerate all named sessions
3. For each named session, creates a tmux window and runs `claude --resume '<name>'`

### Flow 5: Notification on session finish (Stop hook)

1. Any Claude Code session finishes responding
2. Stop hook fires, receives JSON on stdin with `cwd`, `session_id`, `last_assistant_message`
3. Hook extracts directory basename via `jq`
4. `osascript` fires macOS notification with "Glass" sound

### Flow 6: Notification on attention needed (Notification hook)

1. Claude Code needs user attention (permission prompt, idle prompt, etc.)
2. Notification hook fires, receives JSON with `message`, `title`, `notification_type`, `cwd`
3. Hook extracts directory basename and message via `jq`
4. `osascript` fires macOS notification with "Submarine" sound

### Flow 7: Notification on tool failure (PostToolUseFailure hook)

1. A tool call fails inside any Claude Code session
2. PostToolUseFailure hook fires, receives JSON with `tool_name`, `error`, `cwd`
3. Hook extracts directory basename and tool name via `jq`
4. `osascript` fires macOS notification with "Basso" sound

---

## Flow Permutations Matrix

### `cs list` Permutations

| Dimension | Variation | Spec Coverage | Notes |
|-----------|-----------|---------------|-------|
| Named sessions | 0 named sessions | NOT SPECIFIED | What does the tool output? Empty table? Message? |
| Named sessions | 1-10 named sessions | Covered | Happy path |
| Named sessions | Session renamed multiple times | NOT SPECIFIED | If user renames session A to B, does B appear or both? |
| Project dir | Current directory | Covered | Default behavior |
| Project dir | Explicit path argument | Covered | `cs list ~/Work/Dev/RAD` |
| Project dir | Nonexistent directory | NOT SPECIFIED | What error message? |
| Project dir | Directory with no sessions | NOT SPECIFIED | `~/.claude/projects/<encoded>/` does not exist |
| Project dir | Path with spaces | NOT SPECIFIED | E.g., `~/Work/My Project` -- encoding and quoting |
| Project dir | Symlinked path | NOT SPECIFIED | `~/Work/Strategy` might be a symlink; resolved path may differ from encoded path |
| Project dir | Relative path argument | NOT SPECIFIED | `cs list ../Dev/RAD` -- needs resolution to absolute |
| Session files | Large JSONL (6700+ lines) | PARTIALLY | Plan uses grep (fast), but line count for "message count" requires `wc -l` on every file |
| Session files | Corrupted/truncated JSONL | NOT SPECIFIED | What if `jq` parsing fails? |
| Session files | Permission denied on file | NOT SPECIFIED | Files are mode `600` (`-rw-------`), should be fine for the user, but robustness |
| Session files | Sessions with identical names | NOT SPECIFIED | Two different sessions both named "debug" -- both shown? Which restores? |
| Deduplication | Same title repeated in one JSONL | PARTIALLY | Plan mentions grep, but does not specify dedup logic. Real data shows "Xiatech strategy" appears 12 times in one file |

### `cs restore` Permutations

| Dimension | Variation | Spec Coverage | Notes |
|-----------|-----------|---------------|-------|
| tmux context | Inside tmux session | Covered | `tmux new-window` |
| tmux context | Outside tmux, tmux installed | Covered | Start new tmux session |
| tmux context | Outside tmux, tmux NOT installed | NOT SPECIFIED | Error message? |
| tmux context | Inside nested tmux | NOT SPECIFIED | `$TMUX` is set but user may want a new session |
| Session name | Exact match | Covered | Happy path |
| Session name | No match found | NOT SPECIFIED | What happens when `cs restore nonexistent`? |
| Session name | Partial match | NOT SPECIFIED | `cs restore intel` when "intellect" exists -- should it fuzzy match? |
| Session name | Multiple matches | NOT SPECIFIED | Two sessions named "debug" -- restore both? Error? |
| Session name | Name with spaces | NOT SPECIFIED | `cs restore "giant context with cost model work"` -- shell quoting |
| Session name | Name with special chars | NOT SPECIFIED | Apostrophes, quotes, ampersands in session names break shell commands |
| Restore all | 0 named sessions | NOT SPECIFIED | `cs restore` with nothing to restore |
| Restore all | 20+ named sessions | NOT SPECIFIED | Opening 20 tmux windows -- resource concern? Confirmation prompt? |
| Restore all | Session already running | NOT SPECIFIED | `claude --resume` on an already-active session -- what happens? |
| tmux window | Window name conflicts | NOT SPECIFIED | tmux window named "Xiatech strategy" already exists |
| tmux window | Window name with special chars | NOT SPECIFIED | tmux window names have character restrictions |
| Existing sessions | Session was compacted | NOT SPECIFIED | Does `claude --resume` handle compacted sessions? (Likely yes, but untested in spec) |

### Notification Hook Permutations

| Dimension | Variation | Spec Coverage | Notes |
|-----------|-----------|---------------|-------|
| Stop hook | Normal completion | Covered | "Glass" sound |
| Stop hook | User interrupt | NOT APPLICABLE | Stop hook does not fire on user interrupt per docs |
| Stop hook | `stop_hook_active` is true | NOT SPECIFIED | Hook fires repeatedly if a Stop hook causes continuation -- infinite notification loop |
| Stop hook | Multiple sessions finish simultaneously | NOT SPECIFIED | Notification flood -- all fire "Glass" at once |
| Notification hook | Permission prompt | Covered | "Submarine" sound |
| Notification hook | Idle prompt | Covered (implicitly) | Same handler, same sound |
| Notification hook | Auth success | NOT SPECIFIED | Should auth_success also play "Submarine"? It is not "needs attention" |
| PostToolUseFailure | Tool failure | Covered | "Basso" sound |
| PostToolUseFailure | Frequent failures | NOT SPECIFIED | Rapid-fire tool failures produce a stream of notifications |
| PostToolUseFailure | User interrupt failure | NOT SPECIFIED | `is_interrupt: true` -- should this still notify? |
| All hooks | macOS Do Not Disturb active | NOT SPECIFIED | Notifications suppressed by OS -- no fallback |
| All hooks | `jq` not found | NOT SPECIFIED | Hook silently fails or errors? |
| All hooks | JSON parsing failure | NOT SPECIFIED | Malformed stdin -- `jq` returns empty/error |

---

## Missing Elements and Gaps

### Category: Input Validation and Error Handling

**Gap 1: No error handling in `cs list` for missing directories**
The spec does not define behavior when `~/.claude/projects/<encoded>/` does not exist. This happens when the user runs `cs list` in a directory where no Claude sessions have ever been created.
**Impact:** Script crashes with a grep/find error on a nonexistent directory.
**Current ambiguity:** Is this an error, a warning, or silent empty output?

**Gap 2: No handling for `cs restore` when session name is not found**
The spec says "If `name` specified: create one tmux window" but does not cover the case where the name does not match any session.
**Impact:** User runs `cs restore my-session`, gets no feedback, no window created, unclear what happened.

**Gap 3: No input validation on session names with special characters**
Real session names in the data include spaces ("giant context with cost model work", "Claude Code vs. Cursor Agents"). These names need careful quoting in:
- Shell arguments to `cs restore`
- tmux window names passed to `tmux new-window -n`
- The `claude --resume '<name>'` command
**Impact:** Shell injection risk. A session named `test'; rm -rf ~; echo '` would execute arbitrary commands in the current `tmux new-window ... "claude --resume '...' "` construction.

**Gap 4: No handling for duplicate session names**
The spec does not address what happens when two different sessions have the same name. `claude --resume <name>` presumably picks one (most recent?), but `cs list` should indicate the ambiguity and `cs restore` should have a defined behavior.
**Impact:** User may resume the wrong session.

### Category: Path Resolution

**Gap 5: Relative path and `~` expansion for `cs list` argument**
The spec shows `cs list ~/Work/Dev/RAD` as an example, but `~` expansion in a shell argument depends on quoting. If the user quotes it (`cs list "~/Work/Dev/RAD"`), `~` is not expanded by the shell.
**Impact:** Path encoding produces `~-Work-Dev-RAD` instead of `-Users-adamf-Work-Dev-RAD`.

**Gap 6: Symlink resolution**
If `$PWD` returns a symlinked path but Claude Code encoded the resolved real path when creating sessions, the encoded path will not match.
**Impact:** `cs list` returns empty results despite sessions existing.

**Gap 7: Path encoding edge case -- trailing slashes**
`/Users/adamf/Work/Strategy/` vs `/Users/adamf/Work/Strategy` -- does the encoding handle trailing slashes consistently?
**Impact:** Encoded path mismatch, empty results.

### Category: JSONL Parsing and Performance

**Gap 8: Session title deduplication logic not specified**
The plan says "For each file, grep for `"type":"custom-title"` lines" and "Extract `customTitle` and `timestamp` via `jq`" but does not specify how to deduplicate. Real data shows a single session ("Xiatech strategy") has 12 duplicate `custom-title` records. The spec needs to say: take the LAST `custom-title` record per file.
**Impact:** Without dedup, `cs list` shows "Xiatech strategy" 12 times.

**Gap 9: "Message count" metric is ambiguous**
The spec says output includes "message count" but does not define what counts as a message. Options:
- Total lines in the JSONL (includes all record types)
- Lines with `type: "human"` or `type: "assistant"` only
- Some other metric
Running `wc -l` on every file in a directory with 108 files (some 2.5MB+) is O(total bytes), which may be slow.
**Impact:** Unclear metric, potentially slow.

**Gap 10: Performance with large session directories**
The Strategy project has 108 session files. Grepping all of them for `custom-title`, then running `jq` on matches, then counting lines in each -- this is 3 passes over the directory. With sessions up to 2.5MB, total I/O could be 50-100MB per `cs list` invocation.
**Impact:** Sluggish response on first run (before filesystem cache).

**Gap 11: Timestamp extraction for "last activity"**
The spec says "Get last line timestamp for last activity" but does not specify which JSON field. The `custom-title` records have no explicit timestamp field in the observed data. The plan would need to use file modification time (`stat`) or parse the last record in the JSONL file for a timestamp field.
**Impact:** Implementation ambiguity. `stat` mtime is the simplest approach but may not match the actual last interaction time.

### Category: tmux Integration

**Gap 12: tmux session naming and conflicts**
The spec does not define what tmux session name to use when starting a new tmux session outside of tmux. Should it be `claude`, `cs`, or derived from the project name?
**Impact:** May conflict with existing tmux sessions.

**Gap 13: tmux window name sanitization**
tmux window names have limitations. Session names like "Claude Code vs. Cursor Agents" contain spaces and periods which are valid but create visual noise. Names with certain special characters may break tmux commands.
**Impact:** `tmux new-window -n "giant context with cost model work"` -- the space-heavy name is unwieldy in tmux status bar.

**Gap 14: Restoring a session that is already running**
If `cs restore intellect` is run but that session is already resumed in another tmux window, `claude --resume` may either fail, create a duplicate, or take over the existing session. The spec does not address this.
**Impact:** User accidentally corrupts session state or gets confused by duplicates.

**Gap 15: `cs restore` with no arguments and many sessions -- confirmation**
With 7+ named sessions in one project, `cs restore` would open 7 tmux windows simultaneously. No confirmation prompt is specified.
**Impact:** User accidentally floods their tmux with windows.

### Category: Notification Hooks

**Gap 16: Hook JSON field name mismatch -- `tool_name` not `.tool_name`**
The plan's PostToolUseFailure hook uses `.tool_name` in the `jq` expression, which is correct per the official docs. But the Stop hook uses `.cwd`, and the Notification hook uses `.message` -- these are confirmed correct by the official schema. This is NOT a gap, just noting that verification was done.

**Gap 17: Stop hook `stop_hook_active` not checked**
The official docs explicitly warn: "Check `stop_hook_active` value or process the transcript to prevent Claude Code from running indefinitely." The spec's Stop hook does not check this field. If any OTHER Stop hook causes Claude to continue (e.g., a prompt-based Stop hook), the notification hook would fire repeatedly every time Claude stops and is forced to continue.
**Impact:** Notification spam -- "Glass" sound fires over and over.

**Gap 18: Notification hook fires for `auth_success` -- wrong sound**
The Notification hook matcher is empty (matches all notification types). This means `auth_success` notifications also play the "Submarine" sound intended for "needs attention." An auth success is the opposite of needing attention.
**Impact:** Misleading notification -- user hears "needs attention" sound for a successful auth.

**Gap 19: PostToolUseFailure notification volume**
A single Claude session can fail dozens of tool calls during a retry loop (e.g., repeated permission denials, network timeouts). Each failure fires a notification with "Basso" sound.
**Impact:** Notification fatigue. User learns to ignore notifications.

**Gap 20: Hook timeout not specified**
The spec does not set `timeout` on any hook. Default is 600 seconds (10 minutes) for command hooks. These notification hooks should execute in under 1 second. While the default is fine (it will not block), explicitly setting a short timeout (e.g., 5 seconds) documents the intent and prevents a hung `osascript` from blocking Claude for 10 minutes.
**Impact:** A hung `osascript` process would block Claude for up to 10 minutes.

**Gap 21: Hooks should probably be async**
Notification hooks are side effects -- they should not block Claude. The spec defines them as synchronous (no `"async": true`). Per the docs, async hooks cannot return decisions, which is fine since Notification and PostToolUseFailure have no decision control anyway, and the Stop hook's notification use case does not need to block/continue Claude.
**Impact:** Synchronous notification hooks add latency to every stop, notification, and failure event.

### Category: Settings.json Merge Safety

**Gap 22: Merge strategy for settings.json not defined**
The spec says "Merge with existing hooks (don't overwrite `SessionStart` and `PreCompact`)." But the actual merge operation is not specified. Is it:
- Manual JSON editing?
- `jq` merge command?
- In-place edit with a specific tool?
If done wrong, existing hooks (`bd prime` on SessionStart and PreCompact) are destroyed.
**Impact:** Breaking beads integration by overwriting existing hooks.

### Category: Session Data Format Stability

**Gap 23: Undocumented JSONL format dependency**
The `custom-title` record type, the `customTitle` field name, and the session path encoding are all internal to Claude Code and undocumented. Any Claude Code update could change:
- The JSONL record schema
- The path encoding scheme
- The session storage location
**Impact:** `cs` breaks silently on Claude Code upgrade with no error message.

### Category: Missing Subcommands

**Gap 24: No `cs help` or `cs --help`**
The spec defines `cs list` and `cs restore` but no help output.
**Impact:** User runs `cs` with no args and gets an error instead of usage.

**Gap 25: No `cs version`**
No way to check which version is installed. Minor for a personal tool, but useful when debugging.

---

## Critical Questions Requiring Clarification

### Critical (blocks implementation or creates data/security risks)

**Q1: How should session names with special characters be handled in shell commands?**
Real session names contain spaces ("giant context with cost model work"), which will break `tmux new-window -n <name> "claude --resume '<name>'"` without proper quoting. Names could theoretically contain single quotes, double quotes, or shell metacharacters.
*Why it matters:* Shell injection risk. A malicious or accidental session name could execute arbitrary commands.
*Default assumption if unanswered:* Sanitize names by replacing non-alphanumeric characters (except spaces and hyphens) with underscores for tmux window names. Use `--` argument terminator and proper quoting for `claude --resume`.

**Q2: What should `cs restore` do when two sessions have the same name?**
`claude --resume <name>` presumably picks the most recent, but the user may want the other one.
*Why it matters:* User resumes the wrong session, losing context on the one they intended.
*Default assumption if unanswered:* Show a disambiguation prompt listing both with their last-activity timestamps. Or, if keeping the tool non-interactive, restore the most recent and print a warning.

**Q3: Should the Stop hook check `stop_hook_active` to prevent notification loops?**
The official docs explicitly warn about this. If any other hook causes Claude to continue after a Stop event, the notification fires again on the next stop.
*Why it matters:* Infinite notification loop producing "Glass" sound repeatedly.
*Default assumption if unanswered:* Yes, add `stop_hook_active` check: only notify when `stop_hook_active` is false.

### Important (significantly affects UX or maintainability)

**Q4: Should notification hooks be async?**
Synchronous hooks block Claude until `osascript` completes. This is typically fast (<100ms) but `osascript` can hang if the notification system is unresponsive.
*Why it matters:* A hung notification blocks Claude for up to 10 minutes (default timeout).
*Default assumption if unanswered:* Make them async with a 5-second timeout.

**Q5: Should `cs restore` with no arguments require confirmation before opening N windows?**
With 7+ named sessions, blindly opening all of them floods tmux.
*Why it matters:* User muscle-memory types `cs restore` and gets 7 windows they did not want.
*Default assumption if unanswered:* If more than 5 sessions, print the list and ask for confirmation. Or, since this is a personal tool for a power user, just print a count and proceed.

**Q6: What should `cs list` output when there are no named sessions?**
*Why it matters:* Difference between "no output" (confusing) and "No named sessions found in /path" (clear).
*Default assumption if unanswered:* Print "No named sessions found for <dir>" to stderr.

**Q7: How should "last activity" be determined?**
The JSONL `custom-title` records do not contain explicit timestamps. Options: file mtime, last JSONL record timestamp, or some other approach.
*Why it matters:* File mtime changes on any access. JSONL parsing is expensive for large files (2.5MB+).
*Default assumption if unanswered:* Use file mtime via `stat`. Fast and accurate enough for this use case.

**Q8: Should the Notification hook differentiate notification types?**
Currently all notification types (`permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog`) play the same "Submarine" sound. But `auth_success` does not represent "needs attention."
*Why it matters:* Misleading sound cue. User runs to check their terminal when nothing is needed.
*Default assumption if unanswered:* Add matchers: `permission_prompt` and `idle_prompt` get "Submarine," ignore `auth_success`, ignore `elicitation_dialog` or give it a distinct treatment.

**Q9: What is the "message count" metric?**
Total JSONL lines? Conversation turns? Some filtered count?
*Why it matters:* Determines implementation complexity and output usefulness. The "giant context" session has 6700+ lines, most of which are not human messages.
*Default assumption if unanswered:* Use total JSONL line count as a rough size proxy. Label the column "lines" or "size" instead of "messages" to avoid implying it is a message count.

### Nice-to-Have (improves clarity but has reasonable defaults)

**Q10: Should `cs list` support `--json` output for scripting?**
*Why it matters:* Composability with other tools. `cs list --json | jq '.[] | select(.name | contains("strategy"))'`
*Default assumption if unanswered:* Skip for v1. Add later if needed.

**Q11: Should `cs` handle the case where Claude Code is not installed?**
*Why it matters:* Useful error message vs. cryptic failure.
*Default assumption if unanswered:* Check for `~/.claude/projects/` existence on startup. Print clear error if missing.

**Q12: Should the `--layout` feature (save/restore window arrangement) be scoped or cut?**
The plan marks it as "optional, if time permits."
*Why it matters:* Unscoped optional features create implementation ambiguity. Either define it or explicitly cut it from v1.
*Default assumption if unanswered:* Cut from v1. Track in a beads issue for v2.

---

## Architecture Observations

### The plan's hook commands have a correctness issue

The plan's hook JSON uses inline shell one-liners embedded in JSON strings with extensive escaping:

```json
"command": "INPUT=$(cat); DIR=$(echo \"$INPUT\" | jq -r '.cwd // \"unknown\"' | xargs basename); osascript -e \"display notification \\\"Done in $DIR\\\" with title \\\"Claude Finished\\\" sound name \\\"Glass\\\"\""
```

This is fragile. The escaping required for JSON-embedded shell commands with nested `osascript -e` strings containing their own escaped quotes is error-prone and unreadable. A single misplaced backslash breaks everything.

**Recommendation:** Extract each hook into a standalone script file (e.g., `~/.claude/hooks/notify-stop.sh`, `~/.claude/hooks/notify-attention.sh`, `~/.claude/hooks/notify-error.sh`). The settings.json then becomes:

```json
"command": "bash ~/.claude/hooks/notify-stop.sh"
```

This is the pattern used by the existing `statusline-command.sh` and recommended by the official docs. It is testable, readable, and maintainable.

### Session data format is an undocumented internal API

The entire `cs list` implementation depends on:
1. Session files living at `~/.claude/projects/<encoded-path>/<uuid>.jsonl`
2. Path encoding being `/` replaced by `-`
3. The `custom-title` record type existing with a `customTitle` field

None of this is documented. This is a calculated risk for a personal tool, but it means `cs` should be written defensively: check for the directory structure, handle missing fields gracefully, and fail with clear error messages when the format changes.

### The spec is missing the `SessionEnd` hook

The plan uses `Stop` for "session finished" notifications, but `Stop` fires when Claude finishes responding -- not when the session ends. A session can have many Stop events (one per turn). The user probably wants notification when the entire interactive session ends (the user exits Claude Code), which is the `SessionEnd` hook.

Alternatively, if the intent is "Claude is done thinking and I should go look at what it produced," then `Stop` is correct -- but the notification text "Claude Finished" is misleading because Claude has not "finished" in the session sense. It finished one response.

This is a design question, not a bug, but it should be explicit.

---

## Recommended Next Steps

1. **Resolve Critical Questions Q1-Q3** before implementation. Shell quoting and the `stop_hook_active` check are correctness issues, not style preferences.

2. **Extract hooks into script files** instead of inline JSON one-liners. Create `~/.claude/hooks/` directory with `notify-stop.sh`, `notify-attention.sh`, `notify-error.sh`. This matches existing patterns (`statusline-command.sh`).

3. **Add matchers to the Notification hook** to separate `permission_prompt`/`idle_prompt` (needs attention) from `auth_success` (does not need attention).

4. **Define error messages** for: no sessions found, session name not found, not in tmux and tmux not installed, directory does not exist.

5. **Add `stop_hook_active` check** to the Stop hook to prevent notification loops.

6. **Consider making hooks async** with short timeouts, since they are fire-and-forget notifications.

7. **Clarify the Stop vs. SessionEnd distinction** -- does the user want "Claude finished one response" or "Claude session ended"?

8. **Add a `cs help` subcommand** and handle `cs` with no arguments gracefully.

9. **Track `--layout` feature as a beads issue** rather than leaving it as an ambiguous "if time permits" in the plan.

10. **Add defensive checks for the JSONL format** -- if the format changes, `cs list` should print a clear error ("Session data format may have changed") instead of silently producing empty output.

---

## Files Referenced

| File | Purpose |
|------|---------|
| `/Users/adamf/.claude/plans/sprightly-weaving-pumpkin.md` | The feature plan being analyzed |
| `/Users/adamf/.claude/settings.json` | Global hooks config to be modified |
| `/Users/adamf/.claude/statusline-command.sh` | Existing hook script pattern |
| `/Users/adamf/Work/Strategy/.workflows/plan-research/claude-session-resume/agents/repo-research.md` | Repository research findings |
| `/Users/adamf/Work/Strategy/.workflows/plan-research/claude-session-resume/agents/learnings.md` | Institutional learnings |
| `/Users/adamf/.claude/projects/-Users-adamf-Work-Strategy/` | Session data directory (108 files, 7 with custom titles) |
| [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) | Official hook documentation with full JSON schemas |
