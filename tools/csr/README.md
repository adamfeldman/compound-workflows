# csr — Claude Session Resume

List and restore named Claude Code sessions into tmux windows. Includes macOS notification hooks for permission prompts and tool failures.

## What it does

- **`csr list [dir]`** — List `/rename`d Claude Code sessions for a directory, sorted by recency
- **`csr restore <name>`** — Open a tmux window and resume a named session
- **`notify-attention.sh`** — macOS notification (Submarine sound) when Claude needs permission
- **`notify-error.sh`** — macOS notification (Basso sound) when a tool fails

## Install

```bash
bash install.sh
```

This copies scripts to `~/.local/bin/`, makes them executable, and prints the settings.json snippet with your actual absolute paths. You still need to manually merge the hooks into `~/.claude/settings.json` (the install script prints exactly what to add).

**Manual install** (if you prefer):

```bash
cp bin/csr bin/notify-attention.sh bin/notify-error.sh ~/.local/bin/
chmod +x ~/.local/bin/csr ~/.local/bin/notify-attention.sh ~/.local/bin/notify-error.sh
```

Then add to the `"hooks"` object in `~/.claude/settings.json`:

```json
{
  "Notification": [{
    "matcher": "permission_prompt",
    "hooks": [{
      "type": "command",
      "command": "bash /Users/you/.local/bin/notify-attention.sh",
      "timeout": 5,
      "async": true
    }]
  }],
  "PostToolUseFailure": [{
    "matcher": "",
    "hooks": [{
      "type": "command",
      "command": "bash /Users/you/.local/bin/notify-error.sh",
      "timeout": 5,
      "async": true
    }]
  }]
}
```

**Important:** Hook paths must be absolute — tilde expansion doesn't work in settings.json. Replace `/Users/you` with your actual home directory, or use `install.sh` which handles this.

## Dependencies

All typically pre-installed on macOS:

- `jq` (via PATH)
- `tmux` (for `csr restore`)
- `osascript` (macOS built-in, for notifications)
- `realpath` (macOS 13+)
- `~/.local/bin/` on PATH

## How it works

### Session discovery

Claude Code stores sessions as JSONL files at `~/.claude/projects/<encoded-path>/<uuid>.jsonl`. When you `/rename` a session, Claude writes a `{"type":"custom-title","customTitle":"..."}` record to the JSONL. `csr list` greps for these records (fast, avoids full JSONL parsing) and displays the most recent title per file.

Path encoding: `/Users/adam/Work/Strategy` becomes `-Users-adam-Work-Strategy`.

### Session restore

`csr restore` creates a tmux window and sends `claude --resume <name>` via `tmux send-keys` (avoids shell injection from session names). `remain-on-exit` keeps the window open if resume fails.

### Notifications

Hook scripts receive JSON on stdin from Claude Code. Fields include `cwd`, `message`, `transcript_path`, `session_id`. The scripts grep the session JSONL (via `transcript_path`) for the `/rename` custom title to identify which session fired. Falls back to directory basename for unnamed sessions.

Security: notification body is passed to osascript via environment variable (not string interpolation) to prevent AppleScript injection.

## Limitations

- Only finds `/rename`d sessions. Auto-generated titles (shown in Claude Code UI and tmux tabs) are not stored in JSONL.
- `csr restore` requires tmux. No fallback for non-tmux environments.
- Notification identity depends on `/rename`. Unnamed sessions all show the directory basename (e.g., "Strategy").
- Path encoding is non-injective: `/a/b-c` and `/a/b/c` produce the same encoded path. Matches Claude Code behavior.
- macOS only (osascript notifications).

## Docs

- `docs/exploration-journal.md` — Full exploration narrative: how we got here, 30+ tools researched, decision points
- `docs/plan.md` — Implementation plan with review findings from 7 agents + Gemini red team
