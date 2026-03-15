---
title: "Safe macOS notifications from Claude Code hooks (no AppleScript injection)"
category: claude-code/hooks
validated: true
date: 2026-02-23
---

# Safe osascript from Shell Hooks

## Problem

Sending macOS notifications from Claude Code hooks requires passing untrusted data (session messages, tool names) to `osascript`. Naive string interpolation allows AppleScript injection:

```bash
# DANGEROUS — message content can escape quotes and execute arbitrary AppleScript
osascript -e "display notification \"$MSG\" with title \"Claude\""
```

## Solution

Pass untrusted data via environment variable. AppleScript reads it with `system attribute`, which returns a plain string — no parsing, no injection:

```bash
NOTIF_BODY=$(printf '%s: %s' "$session_name" "$msg" | tr -d '\000-\037') \
  osascript -e 'display notification (system attribute "NOTIF_BODY") with title "Claude" sound name "Submarine"' 2>/dev/null || true
```

Key details:
- **`tr -d '\000-\037'`** strips control characters from the notification body
- **`2>/dev/null || true`** handles TCC permission denial gracefully (Terminal may not have notification access)
- **Single quotes around the AppleScript** prevent shell interpolation entirely
- **Inline env var** (`VAR=val command`) scopes the variable to the osascript process only

## Available Sounds

macOS notification sounds (pass via `sound name`):
- `Submarine` — subtle, good for "needs attention"
- `Basso` — deeper, good for errors
- `Glass`, `Ping`, `Pop`, `Purr`, `Tink` — other options

## Full Hook Script Pattern

```bash
#!/bin/bash
set -uo pipefail
input=$(cat)
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
msg=$(printf '%s' "$input" | jq -r '.message // "needs attention"')

session_name=""
if [[ -n "$transcript" && -f "$transcript" ]]; then
  session_name=$(grep '"type":"custom-title"' "$transcript" 2>/dev/null | tail -1 | jq -r '.customTitle // empty' 2>/dev/null)
fi
if [[ -z "$session_name" ]]; then
  cwd=$(printf '%s' "$input" | jq -r '.cwd // "unknown"')
  session_name=$(basename -- "$cwd")
fi

NOTIF_BODY=$(printf '%s: %s' "$session_name" "$msg" | tr -d '\000-\037') \
  osascript -e 'display notification (system attribute "NOTIF_BODY") with title "Claude" sound name "Submarine"' 2>/dev/null || true
```
