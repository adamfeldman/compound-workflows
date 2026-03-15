# Red Team Critique — Gemini 3 Pro Preview

**Date:** 2026-02-23
**Model:** gemini-3-pro-preview
**Run:** 1

## Findings

### CRITICAL

**1. `realpath` not available on stock macOS**
- Location: Dependencies, Path encoding
- macOS does not ship `realpath` by default (BSD `readlink` only). `realpath` comes from GNU coreutils via Homebrew.
- Risk: `encode_path()` fails entirely on a fresh macOS install without Homebrew coreutils.
- Fix: Use portable function or `readlink -f` fallback, or `pwd -P`.

### SERIOUS

**2. Hardcoded `/opt/homebrew/bin/jq` path**
- Location: Dependencies, Shell conventions
- Breaks on Intel Macs (`/usr/local/bin`), MacPorts installs, or direct binary installs.
- Fix: Use `jq` via `$PATH`. Verify with `command -v jq`.

**3. Session lock state not checked**
- Location: `csr restore`
- No check if session is currently running elsewhere. `claude --resume` on an active session will fail. The tmux window opens then immediately closes (or sits dead).
- Fix: Use `tmux set-option -p remain-on-exit on` so the user sees why it failed, or check for running claude processes with the same session ID.

**4. Missing `check_deps` function**
- Location: Implementation Details
- Script relies on `jq`, `tmux`, and `realpath` but has no dependency verification.
- Fix: Add startup check for required commands.

### MINOR

**5. TCC/Permissions for osascript**
- Location: Hook scripts
- macOS TCC may silently block `osascript` notifications from background processes unless the parent terminal has notification permissions.
- Fix: Add manual trigger instruction to verification plan.

**6. Tmux window name truncation collision**
- Location: `sanitize_tmux_name()`
- Truncating to 30 chars could make two different session names identical. tmux doesn't allow duplicate window names.
- Fix: Append short hash if truncation occurs, or skip sanitization entirely (per code-simplicity recommendation).
