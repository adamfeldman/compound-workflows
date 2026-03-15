# Claude Code Hooks Documentation Research

**Source:** https://code.claude.com/docs/en/hooks (official reference) and https://code.claude.com/docs/en/hooks-guide (guide)
**Date:** 2026-02-23

---

## 1. Notification Hook

### JSON stdin fields

All common fields plus notification-specific fields:

```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../00893aaf.jsonl",
  "cwd": "/Users/...",
  "permission_mode": "default",
  "hook_event_name": "Notification",
  "message": "Claude needs your permission to use Bash",
  "title": "Permission needed",
  "notification_type": "permission_prompt"
}
```

| Field               | Description                                    |
|---------------------|------------------------------------------------|
| `message`           | The notification text                          |
| `title`             | Optional title for the notification            |
| `notification_type` | Which notification type fired (matcher target) |

### Matcher field

Yes, `notification_type` is the correct matcher field. The matcher is a regex matched against `notification_type`.

### Valid notification_type values

| Value                 | When it fires                              |
|-----------------------|--------------------------------------------|
| `permission_prompt`   | Claude needs permission approval           |
| `idle_prompt`         | Claude has been idle / waiting for input   |
| `auth_success`        | Authentication succeeded                   |
| `elicitation_dialog`  | An elicitation dialog is shown             |

### Decision control

Notification hooks **cannot block or modify notifications**. They are fire-and-forget, used for side effects (logging, desktop notifications, etc.). Exit code 2 shows stderr to user only. You can return `additionalContext` to add context to the conversation.

### Configuration example

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/permission-alert.sh"
          }
        ]
      },
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/idle-notification.sh"
          }
        ]
      }
    ]
  }
}
```

**Notification only supports `type: "command"` hooks** (not prompt or agent).

---

## 2. PostToolUseFailure Hook

### JSON stdin fields

All common fields plus failure-specific fields:

```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../00893aaf.jsonl",
  "cwd": "/Users/...",
  "permission_mode": "default",
  "hook_event_name": "PostToolUseFailure",
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm test",
    "description": "Run test suite"
  },
  "tool_use_id": "toolu_01ABC123...",
  "error": "Command exited with non-zero status code 1",
  "is_interrupt": false
}
```

| Field          | Type             | Description                                                     |
|----------------|------------------|-----------------------------------------------------------------|
| `tool_name`    | string           | Name of the tool that failed (matcher target)                   |
| `tool_input`   | object           | The arguments that were sent to the tool                        |
| `tool_use_id`  | string           | Unique identifier for this tool use                             |
| `error`        | string           | String describing what went wrong                               |
| `is_interrupt` | optional boolean | Whether the failure was caused by user interruption             |

### Key answers

- **`is_interrupt`** is an **optional boolean**. It may not always be present in the JSON.
- The tool name field is **`tool_name`** (same as PreToolUse/PostToolUse).
- Matcher matches on `tool_name`.

### Decision control

PostToolUseFailure **cannot block** (the tool already failed). Exit code 2 shows stderr to Claude. You can return:

| Field               | Description                                                   |
|---------------------|---------------------------------------------------------------|
| `decision`          | `"block"` prompts Claude with the `reason`                    |
| `reason`            | Explanation shown to Claude                                   |
| `additionalContext` | Additional context for Claude alongside the error             |

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUseFailure",
    "additionalContext": "Additional information about the failure for Claude"
  }
}
```

---

## 3. Stop Hook

### JSON stdin fields

All common fields plus stop-specific fields:

```json
{
  "session_id": "abc123",
  "transcript_path": "~/.claude/projects/.../00893aaf.jsonl",
  "cwd": "/Users/...",
  "permission_mode": "default",
  "hook_event_name": "Stop",
  "stop_hook_active": true,
  "last_assistant_message": "I've completed the refactoring. Here's a summary..."
}
```

| Field                    | Type    | Description                                                          |
|--------------------------|---------|----------------------------------------------------------------------|
| `stop_hook_active`       | boolean | `true` when Claude is already continuing as a result of a stop hook  |
| `last_assistant_message` | string  | Text content of Claude's final response                              |

### What is `stop_hook_active`?

`stop_hook_active` is `true` when Claude Code is **already continuing as a result of a prior Stop hook invocation**. This is the critical field for **preventing infinite loops**. If your Stop hook blocked Claude from stopping (via `decision: "block"`), Claude will continue working and eventually try to stop again. When it does, `stop_hook_active` will be `true`. Your hook script MUST check this value and exit 0 (allow stop) to avoid an infinite loop.

```bash
#!/bin/bash
INPUT=$(cat)
if [ "$(echo "$INPUT" | jq -r '.stop_hook_active')" = "true" ]; then
  exit 0  # Allow Claude to stop -- prevent infinite loop
fi
# ... rest of your hook logic
```

### Decision control

Stop hooks **can block** Claude from stopping:

```json
{
  "decision": "block",
  "reason": "Must be provided when Claude is blocked from stopping"
}
```

- `decision: "block"` prevents Claude from stopping and continues the conversation
- `reason` is **required** when decision is `"block"` -- tells Claude why it should continue
- Omit `decision` or exit 0 with no JSON to allow Claude to stop
- Exit code 2 also prevents Claude from stopping (stderr fed back to Claude)

### Important notes

- Stop hooks **do not support matchers** -- they fire on every occurrence
- Stop hooks **do not fire on user interrupts**
- Stop hooks fire whenever Claude finishes responding, not only at task completion

---

## 4. General Hook Configuration Format

### Settings.json structure

```json
{
  "hooks": {
    "<EventName>": [
      {
        "matcher": "<regex_pattern>",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/script.sh",
            "timeout": 30,
            "async": true,
            "statusMessage": "Running checks..."
          }
        ]
      }
    ]
  }
}
```

### Three levels of nesting

1. **Hook event** -- lifecycle point (e.g., `PreToolUse`, `Stop`, `Notification`)
2. **Matcher group** -- regex filter for when it fires
3. **Hook handler(s)** -- the command/prompt/agent that runs

### Hook handler types

| Type      | Key fields              | Default timeout |
|-----------|-------------------------|-----------------|
| `command` | `command`, `async`      | 600 seconds     |
| `prompt`  | `prompt`, `model`       | 30 seconds      |
| `agent`   | `prompt`, `model`       | 60 seconds      |

### Common handler fields

| Field           | Required | Description                                                  |
|-----------------|----------|--------------------------------------------------------------|
| `type`          | yes      | `"command"`, `"prompt"`, or `"agent"`                        |
| `timeout`       | no       | **Seconds** (NOT milliseconds) before canceling              |
| `statusMessage` | no       | Custom spinner message while hook runs                       |
| `once`          | no       | If `true`, runs only once per session (skills only)          |

### Command-specific fields

| Field     | Required | Description                                      |
|-----------|----------|--------------------------------------------------|
| `command` | yes      | Shell command to execute                         |
| `async`   | no       | If `true`, runs in background without blocking   |

### Async option

- `"async": true` runs the hook in the background -- Claude continues immediately
- **Only available on `type: "command"` hooks** (not prompt or agent)
- Async hooks **cannot block or return decisions** (action already proceeded)
- Output delivered on next conversation turn via `systemMessage` or `additionalContext`

---

## 5. Specific Questions Answered

### Can matchers use pipe (`|`) for OR matching?

**Yes.** The matcher is a **regex** pattern. The pipe `|` is the regex OR operator. Examples from official docs:

- `"matcher": "Edit|Write"` -- matches either Edit or Write tool
- `"matcher": "mcp__.*"` -- matches any MCP tool
- `"matcher": "Notebook.*"` -- matches any tool starting with Notebook

For Notification hooks specifically, you could use:
- `"matcher": "permission_prompt|idle_prompt"` -- matches either notification type

This is explicitly documented: "The matcher is a regex, so `Edit|Write` matches either tool."

### Is `"timeout": 5000` the correct format (milliseconds)?

**No. Timeout is in SECONDS, not milliseconds.**

- `"timeout": 30` means 30 seconds
- `"timeout": 600` means 600 seconds (10 minutes, the default for command hooks)
- `"timeout": 120` means 2 minutes

Default timeouts by hook type:
| Type    | Default timeout |
|---------|----------------|
| command | 600 seconds    |
| prompt  | 30 seconds     |
| agent   | 60 seconds     |

If you want 5 seconds, use `"timeout": 5`, not `"timeout": 5000`.

### What happens when a hook command fails (non-zero exit)?

Three exit code behaviors:

| Exit code | Behavior                                                                                     |
|-----------|----------------------------------------------------------------------------------------------|
| **0**     | Success. Claude Code parses stdout for JSON output. Action proceeds.                         |
| **2**     | **Blocking error.** Stdout/JSON ignored. Stderr fed back to Claude as error. Effect depends on event (see table below). |
| **Other** | **Non-blocking error.** Stderr shown in verbose mode only. Execution continues normally.     |

**Exit code 2 behavior varies by event:**

| Hook event           | Can block? | What happens on exit 2                                            |
|----------------------|------------|-------------------------------------------------------------------|
| `PreToolUse`         | Yes        | Blocks the tool call                                              |
| `Stop`               | Yes        | Prevents Claude from stopping, continues conversation             |
| `UserPromptSubmit`   | Yes        | Blocks prompt processing and erases the prompt                    |
| `PermissionRequest`  | Yes        | Denies the permission                                             |
| `PostToolUse`        | No         | Shows stderr to Claude (tool already ran)                         |
| `PostToolUseFailure` | No         | Shows stderr to Claude (tool already failed)                      |
| `Notification`       | No         | Shows stderr to user only                                         |
| `SessionStart`       | No         | Shows stderr to user only                                         |
| `SessionEnd`         | No         | Shows stderr to user only                                         |

**Key rule:** JSON output is ONLY processed on exit 0. If you exit 2, any JSON on stdout is ignored -- only stderr matters.

---

## 6. Common Input Fields (All Events)

Every hook event receives these fields via stdin JSON:

| Field             | Description                                              |
|-------------------|----------------------------------------------------------|
| `session_id`      | Current session identifier                               |
| `transcript_path` | Path to conversation JSON (.jsonl file)                  |
| `cwd`             | Current working directory when the hook was invoked      |
| `permission_mode` | Current permission mode                                  |
| `hook_event_name` | Name of the event that fired                             |

---

## 7. All Hook Events (Complete List)

| Event                | When it fires                                    | Matcher target       | Can block? |
|----------------------|--------------------------------------------------|----------------------|------------|
| `SessionStart`       | Session begins or resumes                        | source (startup/resume/clear/compact) | No |
| `UserPromptSubmit`   | User submits a prompt                            | No matcher support   | Yes        |
| `PreToolUse`         | Before a tool call executes                      | tool_name            | Yes        |
| `PermissionRequest`  | Permission dialog appears                        | tool_name            | Yes        |
| `PostToolUse`        | After a tool call succeeds                       | tool_name            | No         |
| `PostToolUseFailure` | After a tool call fails                          | tool_name            | No         |
| `Notification`       | Notification sent                                | notification_type    | No         |
| `SubagentStart`      | Subagent spawned                                 | agent_type           | No         |
| `SubagentStop`       | Subagent finishes                                | agent_type           | Yes        |
| `Stop`               | Claude finishes responding                       | No matcher support   | Yes        |
| `TeammateIdle`       | Teammate about to go idle                        | No matcher support   | Yes        |
| `TaskCompleted`      | Task marked as completed                         | No matcher support   | Yes        |
| `ConfigChange`       | Config file changes during session               | config source        | Yes        |
| `WorktreeCreate`     | Worktree being created                           | No matcher support   | Yes        |
| `WorktreeRemove`     | Worktree being removed                           | No matcher support   | No         |
| `PreCompact`         | Before context compaction                        | trigger (manual/auto)| No         |
| `SessionEnd`         | Session terminates                               | reason               | No         |

---

## 8. Environment Variables Available in Hooks

| Variable              | Description                                              |
|-----------------------|----------------------------------------------------------|
| `$CLAUDE_PROJECT_DIR` | Project root directory. Use for referencing scripts.     |
| `${CLAUDE_PLUGIN_ROOT}` | Plugin root directory (for plugin hooks)              |
| `$CLAUDE_ENV_FILE`    | File path for persisting env vars (SessionStart only)    |
| `$CLAUDE_CODE_REMOTE` | Set to `"true"` in remote web environments               |

---

## 9. Hook Locations (Where to Configure)

| Location                            | Scope              | Shareable                         |
|-------------------------------------|--------------------|------------------------------------|
| `~/.claude/settings.json`           | All projects       | No, local to machine               |
| `.claude/settings.json`             | Single project     | Yes, can commit to repo            |
| `.claude/settings.local.json`       | Single project     | No, gitignored                     |
| Managed policy settings             | Organization-wide  | Yes, admin-controlled              |
| Plugin `hooks/hooks.json`           | When plugin active | Yes, bundled with plugin           |
| Skill/agent frontmatter             | While active       | Yes, defined in component file     |

---

## 10. Important Edge Cases and Gotchas

1. **Hooks snapshot at startup.** Direct edits to settings files don't take effect mid-session. Claude Code warns you and requires review in `/hooks` menu.

2. **Shell profile interference.** If `~/.zshrc` or `~/.bashrc` has unconditional `echo` statements, they prepend to hook stdout and break JSON parsing. Wrap in `if [[ $- == *i* ]]; then ... fi`.

3. **Stop hook infinite loops.** Always check `stop_hook_active` to prevent infinite continuation loops.

4. **PermissionRequest hooks don't fire in headless mode** (`-p`). Use `PreToolUse` hooks instead for automated permission decisions.

5. **Matchers are case-sensitive.** `"bash"` will NOT match `"Bash"`.

6. **All matching hooks run in parallel.** Identical handlers are deduplicated automatically.

7. **Only `type: "command"` hooks support `async`.** Prompt and agent hooks cannot run asynchronously.

8. **Notification, SessionStart, SessionEnd, SubagentStart, TeammateIdle, PreCompact, WorktreeCreate, WorktreeRemove, ConfigChange** only support `type: "command"` hooks (not prompt or agent).
