#!/bin/bash
# notify-error.sh — macOS notification for Claude tool failures
# Hook: PostToolUseFailure
set -uo pipefail

input=$(cat)

is_interrupt=$(printf '%s' "$input" | jq -r '.is_interrupt // false')
if [[ "$is_interrupt" == "true" ]]; then
  exit 0
fi

transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // "unknown tool"')

# Get session name from JSONL custom-title record, fall back to cwd basename
session_name=""
if [[ -n "$transcript" && -f "$transcript" ]]; then
  session_name=$(grep '"type":"custom-title"' "$transcript" 2>/dev/null | tail -1 | jq -r '.customTitle // empty' 2>/dev/null)
fi
if [[ -z "$session_name" ]]; then
  cwd=$(printf '%s' "$input" | jq -r '.cwd // "unknown"')
  session_name=$(basename -- "$cwd")
fi

NOTIF_BODY=$(printf '%s: %s failed' "$session_name" "$tool_name" | tr -d '\000-\037') \
  osascript -e 'display notification (system attribute "NOTIF_BODY") with title "Claude Error" sound name "Basso"' 2>/dev/null || true
