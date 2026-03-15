# Synthesis Summary: Run 1

**Date:** 2026-02-23
**Run:** 1
**Agents:** 6 (2 research, 4 review)
**Plan:** `docs/plans/2026-02-23-feat-claude-session-resume-tmux-plan.md`

---

## Agent Roster

| Agent | Type | Key Contribution |
|-------|------|-----------------|
| research--best-practices | Research | Shell scripting patterns, macOS portability, tmux scripting, JSONL processing |
| research--hooks-docs | Research | Official hooks API documentation, JSON schemas, timeout units, event types |
| review--architecture-strategist | Review | Ecosystem analysis, naming collision, upgrade path, JSONL format risk |
| review--code-simplicity | Review | YAGNI analysis, LOC reduction recommendations, scope validation |
| review--pattern-recognition | Review | Convention consistency, settings.json compatibility, anti-pattern identification |
| review--security-sentinel | Review | Shell injection vectors, input validation, sanitization gaps |

---

## Top Findings by Severity

### Critical (Must Fix Before Implementation)

1. **Timeout unit error: `5000` should be `5`** -- Hooks documentation specifies timeout in seconds, not milliseconds. Current value means 83-minute timeout instead of 5-second. (architecture-strategist, security-sentinel, research--hooks-docs)

2. **Shell injection via `osascript -e` string interpolation** -- The `message` and `error` fields from hook JSON are interpolated directly into AppleScript strings. A crafted message containing double quotes can escape the string and execute arbitrary AppleScript including `do shell script`. Fix: use environment variable passing (`NOTIF_BODY="$msg" osascript -e 'display notification (system attribute "NOTIF_BODY")...'`). (security-sentinel, pattern-recognition)

3. **Shell injection via `tmux new-window` command string** -- The raw session name is embedded in single quotes in the `new-window` command, which is executed by `/bin/sh -c`. Names with single quotes break out of quoting. Fix: use `tmux new-window` + `tmux send-keys` pattern (separate window creation from command execution), or use `printf '%q'` escaping. (security-sentinel, pattern-recognition, architecture-strategist)

4. **Binary name `cs` collides with claude-squad** -- claude-squad is an established open-source tool that installs as `cs` to `~/.local/bin/`. Same name, same location. Rename to `csr` (claude session resume). (architecture-strategist)

### High (Should Fix Before Implementation)

5. **`xargs basename` is fragile** -- Paths with spaces, quotes, or empty jq output cause `xargs` to fail or behave unpredictably. Replace with direct `basename --` on a variable. (security-sentinel, pattern-recognition)

6. **Missing `is_interrupt` check in hook code** -- Plan text says "skip if is_interrupt is true" but the code sample does not implement it. Field is optional boolean -- must use `jq -r '.is_interrupt // false'`. (architecture-strategist, security-sentinel, pattern-recognition)

7. **Hook command paths use `~` instead of absolute paths** -- Existing `statusline-command.sh` uses absolute paths in settings.json. Plan uses tilde paths (`~/.claude/hooks/...`). Use absolute paths for consistency and robustness. (pattern-recognition)

8. **Add `"async": true` to notification hooks** -- These are fire-and-forget side effects. Without async, osascript blocks Claude's execution. (architecture-strategist, pattern-recognition)

### Medium (Fix During Implementation)

9. **Cut interactive `cs restore` (no-arg) mode** -- Adds ~25 LOC of complexity (select loop, input validation, `all` keyword, confirmation prompts) for a use case already covered by `cs list` + `cs restore <name>`. Diverges from non-interactive CLI pattern established by `bd`. (code-simplicity, pattern-recognition)

10. **Variable naming: use lowercase in hook scripts** -- Plan uses `INPUT`, `DIR`, `MSG` (uppercase). Existing `statusline-command.sh` uses lowercase (`input`, `cwd`, `model`). UPPERCASE is conventionally reserved for environment variables. (pattern-recognition)

11. **Add directory existence check before scanning** -- No guard for `~/.claude/projects/<encoded>/` existence. grep will error on nonexistent directory. (pattern-recognition, architecture-strategist)

12. **Only scan top-level JSONL files, not subagents/** -- The glob `*.jsonl` handles this, but it should be an explicit, documented decision. Subagent files also contain `custom-title` records but are not user-resumable. (architecture-strategist)

### Low (Nice to Have)

13. **Cut "start tmux if not in tmux" fallback** -- Just error and exit. Removes 5 LOC and a design decision. (code-simplicity)

14. **Drop file size column from `cs list`** -- File size of JSONL tells you nothing useful. Show name + time only. (code-simplicity)

15. **Add header comment block** -- Match `bq_cost_measurement.sh` convention. (pattern-recognition)

16. **Add `cs version` and `--help` flag** -- Trivial additions for debugging and UX parity with `bd`. (pattern-recognition)

17. **Evaluate `idle_prompt` in Notification matcher** -- With 15 concurrent sessions, idle notifications from every session may be noisy. Consider `permission_prompt` only for v1. (architecture-strategist)

18. **Sanitize osascript notification text** -- Even with env var approach, strip/escape control characters. (security-sentinel, pattern-recognition)

19. **Add comment: rewrite in Python if script exceeds 200 lines** -- Makes the architectural escape hatch explicit. (architecture-strategist)

---

## Sections With Most Feedback

| Plan Section | Finding Count | Key Issues |
|-------------|--------------|------------|
| Hook script pattern (lines 122-129) | 8 | osascript injection, xargs fragility, variable naming, is_interrupt, timeout |
| Settings.json additions (lines 133-151) | 5 | Timeout units, async flag, tilde paths, command path convention |
| `cs restore` (lines 47-55) | 5 | tmux injection, interactive mode, tmux fallback, sanitization scope |
| `cs list` output (lines 32-45) | 3 | File size column, relative time formatting, subagent exclusion |
| Path encoding (lines 100-107) | 2 | Non-injective encoding, directory existence check |

---

## Agents That Found Nothing Relevant

None. All six agents produced actionable findings.

---

## Contradictions Between Agents

### 1. Sanitization: Do It vs. YAGNI

- **security-sentinel** recommends a `validate_session_name()` function that rejects names with shell metacharacters, plus an `escape_applescript()` helper.
- **code-simplicity** says "You name your own sessions. You are not going to inject yourself" and recommends dropping `sanitize_tmux_name()` entirely.

**Resolution:** security-sentinel is right on the injection vectors (osascript and tmux command string) -- these are real even for a personal tool because the `error` and `message` fields in hook JSON come from Claude Code, not from the user directly. A compromised tool output or crafted file content could influence these fields. code-simplicity is right that the *tmux window name* sanitization is probably unnecessary. Split the difference: implement the env-var osascript pattern (eliminates injection with zero complexity) and use `printf '%q'` for the tmux resume command (one-liner), but skip the regex validation function and the tmux name sanitization.

### 2. Duplicate Name Handling: Build It vs. Ignore It

- **architecture-strategist** recommends handling duplicate names (restore most recent, print warning).
- **code-simplicity** says "Let duplicates show in the list. Don't write dedup logic until you have a collision."

**Resolution:** code-simplicity is right for v1. With 7 named sessions, duplicates are unlikely. Let them show in the list. `claude --resume` handles the ambiguity on its side.

### 3. Interactive Mode: Cut vs. Simplify

- **code-simplicity** says cut interactive mode entirely (require name argument).
- **pattern-recognition** says either require a name or make "restore all" the no-arg default.

**Resolution:** Both agree interactive selection is wrong. Cut it. Require a name argument. Add `cs restore --all` as a future flag if needed.
