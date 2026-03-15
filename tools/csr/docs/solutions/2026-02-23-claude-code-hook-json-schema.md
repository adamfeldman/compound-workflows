---
title: "Claude Code hook JSON schema (stdin fields)"
category: claude-code/hooks
validated: true
date: 2026-02-23
---

# Claude Code Hook JSON Schema

## Problem

Claude Code hooks receive JSON on stdin, but the available fields aren't fully documented. Building useful hooks requires knowing what data is available.

## Discovery

Hook input comes via stdin as JSON (not environment variables — env vars are documented but buggy per GitHub issue #9567). We captured the full payload by adding a debug dump:

```bash
input=$(cat)
printf '%s' "$input" | jq . > /tmp/claude-hook-debug.json
```

## Notification Hook Fields

```json
{
  "session_id": "39d5a373-bf6d-4f8d-8385-67c2a9e7551d",
  "transcript_path": "/Users/adamf/.claude/projects/-Users-adamf-Work-Strategy/39d5a373-bf6d-4f8d-8385-67c2a9e7551d.jsonl",
  "cwd": "/Users/adamf/Work/Strategy",
  "hook_event_name": "Notification",
  "message": "Claude needs your permission to use Bash",
  "notification_type": "permission_prompt"
}
```

Key fields:
- **`transcript_path`** — Full path to the session JSONL file. Enables session name lookup by grepping for `custom-title` records. This is the most useful field for session identification.
- **`session_id`** — UUID matching the JSONL filename.
- **`cwd`** — Working directory of the Claude session.
- **`notification_type`** — `permission_prompt`, `auth_success`, or `idle_prompt`. Use in matcher to filter.

## PostToolUseFailure Fields

Not fully captured, but includes at minimum:
- `cwd`, `session_id`, `transcript_path` (same as above)
- `tool_name` — Name of the tool that failed
- `is_interrupt` — Boolean. True when user cancelled, not a real error. Check this to avoid false notifications.

## Session Name Lookup Pattern

```bash
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
session_name=""
if [[ -n "$transcript" && -f "$transcript" ]]; then
  session_name=$(grep '"type":"custom-title"' "$transcript" 2>/dev/null | tail -1 | jq -r '.customTitle // empty' 2>/dev/null)
fi
if [[ -z "$session_name" ]]; then
  cwd=$(printf '%s' "$input" | jq -r '.cwd // "unknown"')
  session_name=$(basename -- "$cwd")
fi
```

## Other Hook Notes

- **Timeout is in seconds**, not milliseconds. `"timeout": 5` = 5 seconds. `"timeout": 5000` = 83 minutes.
- **`"async": true`** makes hooks fire-and-forget — they don't block Claude.
- **Hooks snapshot at session startup.** Edits to settings.json mid-session require reviewing hooks via `/hooks`.
- **Matchers are regex.** `"matcher": "permission_prompt"` works. `"matcher": "permission_prompt|idle_prompt"` also works.
