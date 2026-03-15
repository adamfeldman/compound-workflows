#!/bin/bash
# notify-attention.sh — macOS notification for Claude permission prompts
# Hook: Notification (matcher: permission_prompt)
set -uo pipefail

input=$(cat)
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
msg=$(printf '%s' "$input" | jq -r '.message // "needs attention"')

# Get session name from JSONL custom-title record, fall back to cwd basename
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
