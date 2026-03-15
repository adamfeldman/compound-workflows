# Repository Research: Claude Session Resume CLI Tool

## Search Context
- **Feature**: Lightweight CLI tool (`cs`) for managing and resuming named Claude Code sessions with tmux integration
- **Keywords**: session, tmux, CLI, hook, shell script, resume, settings.json, beads, tool pattern
- **Files Examined**: 40+ files across `.claude/`, `scripts/`, `docs/`, `.beads/`, `.workflows/`, plugin caches
- **Date**: 2026-02-23

---

## 1. Existing Plan Already Found

A detailed plan already exists at `/Users/adamf/.claude/plans/sprightly-weaving-pumpkin.md`. It specifies:

- Tool name: `cs` (claude sessions), installed to `~/.local/bin/`
- Three capabilities: `cs list`, `cs restore`, notification hooks
- Shell script (~80 lines)
- Dependencies: `jq` (1.8.1), `tmux` (3.6a), `osascript` (macOS built-in)
- Two files to create/modify: `~/.local/bin/cs` (new) and `~/.claude/settings.json` (modify)
- Verification plan with 5 test cases

This plan is the primary design document. The research below provides implementation context.

---

## 2. Existing Shell Scripts and Tools in the Repo

### `/Users/adamf/Work/Strategy/scripts/bq_cost_measurement.sh`
- **Only shell script in the repo.** 17.9KB, executable (`chmod +x`).
- **Conventions observed:**
  - Shebang: `#!/bin/bash`
  - `set -uo pipefail` (strict mode, minus `errexit` — intentional for error handling in functions)
  - Environment variable configuration with defaults: `PROJECT="${BQ_PROJECT:-}"`
  - Clear error messages with usage instructions on missing vars
  - Helper function pattern: `run_query()` with named parameters (`local name="$1"`)
  - TSV output format with header line
  - Timestamped run IDs: `RUN_ID="bqcost_$(date +%Y%m%d_%H%M%S)"`
  - Uses `python3` for date arithmetic (not pure bash)
  - Structured output with section headers: `echo "=== BQ Cost Measurement ==="`

### `/Users/adamf/.claude/statusline-command.sh`
- **1.9KB shell script for Claude Code status line.** Shows how to integrate with Claude's JSON stdin pattern.
- **Key pattern for hooks:**
  - Reads JSON from stdin: `input=$(cat)`
  - Parses with `jq`: `cwd=$(echo "$input" | jq -r '.workspace.current_dir')`
  - Uses `basename` for display-friendly paths
  - Conditional formatting with ANSI color codes
  - `printf` for formatted output (not `echo`)

### `/Users/adamf/Work/Strategy/scripts/toolbox`
- Binary (144MB). Google's MCP toolbox for BigQuery. Not a pattern reference.

### Python scripts in `/Users/adamf/Work/Strategy/scripts/`
- `build_v4.py`, `build_v5.py`, `build_v6_common.py`, `build_v6_spreadsheet.py`, `build_v6_tabs5_14.py`
- `generate_event_volume_xlsx.py`
- All use the `.venv` virtual environment per AGENTS.md conventions
- `requirements.txt` exists for dependency management

---

## 3. CLAUDE.md/AGENTS.md Conventions and Guidance

### File: `/Users/adamf/Work/Strategy/CLAUDE.md`
- Content: `@AGENTS.md` (just an import directive)

### File: `/Users/adamf/Work/Strategy/AGENTS.md` (27KB)
Key directives relevant to this tool:

1. **Communication style**: Direct, honest, no hedging. This applies to the tool's output format too.
2. **Python venv requirement**: "Always use a Python virtual environment for Python work." Not relevant if implementing in pure bash, but relevant if any Python is used.
3. **Shared docs must reference Cursor only**: Not relevant for a personal CLI tool.
4. **Landing the Plane protocol**: Mandatory push-to-remote workflow. Important context for how sessions end (and thus when notification hooks fire).
5. **Compound Knowledge Prompting**: The tool might be worth compounding after implementation.

### File: `/Users/adamf/Work/Strategy/.gitignore`
- Ignores `.DS_Store`, lock files, `*.tmp`, `.venv/`, `__pycache__/`
- The `cs` script lives outside this repo (`~/.local/bin/`), so gitignore is not directly relevant.

---

## 4. Beads (`bd`) CLI Tool Structure — Pattern Reference

Beads is the closest pattern reference for a lightweight CLI tool in this ecosystem.

### Installation and Distribution
- Installed as a Go binary. Discovered via Claude Code plugin system.
- Plugin manifest at `/Users/adamf/.claude/plugins/cache/beads-marketplace/beads/0.49.4/.claude-plugin/plugin.json`
- The binary itself is not in the Strategy repo — it's globally installed.

### CLI Command Pattern
- Subcommand-based: `bd list`, `bd create`, `bd show`, `bd update`, `bd close`, `bd sync`, `bd ready`, `bd prime`, `bd worktree create/info/remove`, `bd dep add`, `bd config get/set`
- Short verb-first commands with positional args and flags
- JSON output mode available (`--json`)
- Actor/audit trail support (`--actor`)

### State Storage
- Primary: `.beads/issues.jsonl` (JSONL format, git-tracked)
- Ephemeral: `.beads/ephemeral.sqlite3` (SQLite, git-ignored)
- Config: `.beads/config.yaml`
- Metadata: `.beads/metadata.json`
- Custom git merge driver: `.gitattributes` registers `merge=beads` for JSONL files

### Hook Integration
- Plugin hooks: `SessionStart` runs `bd prime`, `PreCompact` runs `bd prime`
- Both global (`~/.claude/settings.json`) and plugin-level hooks exist
- Hook pattern: `{ "matcher": "", "hooks": [{ "type": "command", "command": "bd prime" }] }`

### Key Insight for `cs`
The `bd` tool shows that a globally-installed CLI with project-local state (`.beads/` directory) and Claude Code hook integration is a proven, well-established pattern in this ecosystem. The `cs` tool follows the same architecture but with user-global state (`~/.claude/projects/`) rather than project-local state.

---

## 5. Claude Code Hooks Configuration

### Global settings: `/Users/adamf/.claude/settings.json`
Current hooks:
```json
{
  "hooks": {
    "PreCompact": [{ "matcher": "", "hooks": [{ "type": "command", "command": "bd prime" }] }],
    "SessionStart": [{ "matcher": "", "hooks": [{ "type": "command", "command": "bd prime" }] }]
  },
  "statusLine": {
    "type": "command",
    "command": "bash /Users/adamf/.claude/statusline-command.sh"
  },
  "env": {
    "MCP_TIMEOUT": "300000",
    "MCP_TOOL_TIMEOUT": "300000",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "60",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "64000"
  }
}
```

**Critical implementation detail:** The plan specifies adding `Stop`, `Notification`, and `PostToolUseFailure` hooks. These must be **merged** with the existing `SessionStart` and `PreCompact` hooks, not overwrite them.

### Project-level settings: `/Users/adamf/Work/Strategy/.claude/settings.local.json`
- Contains permission allowlists for Bash commands (notably `"Bash(tmux:*)"` is already permitted)
- Contains MCP server enablement
- This is per-project. The `cs` tool's hooks go in the global `settings.json`.

### Hook Input Pattern (from statusline-command.sh and plan)
- Hooks receive JSON on stdin
- Pattern: `INPUT=$(cat); DIR=$(echo "$INPUT" | jq -r '.cwd // "unknown"' | xargs basename)`
- The `Stop` hook in the plan uses this pattern for macOS notifications via `osascript`

### Available Hook Types
From the compound-engineering plugin and existing config:
- `SessionStart` — fires when a session begins
- `PreCompact` — fires before context compaction
- `Stop` — fires when a session ends (planned for notification)
- `Notification` — fires when Claude needs user attention (planned)
- `PostToolUseFailure` — fires after a tool call fails (planned)

---

## 6. tmux Integration Patterns

### Existing tmux Usage
- tmux 3.6a is installed (confirmed in plan)
- `"Bash(tmux:*)"` is in the project's permission allowlist — Claude Code sessions can run tmux commands
- No `.tmux.conf` was found in the repo (searched but timed out on home dir glob)

### Compound-Engineering Plugin tmux Patterns
The `orchestrating-swarms` skill at `/Users/adamf/.claude/plugins/cache/every-marketplace/compound-engineering/2.35.2/skills/orchestrating-swarms/SKILL.md` contains extensive tmux integration documentation:

- **Auto-detection logic**: Checks `$TMUX` env var, then `$TERM_PROGRAM`, then `which tmux`
- **Backend types**: `in-process` (default when not in tmux), `tmux` (visible panes), `iterm2` (macOS-specific)
- **Swarm session naming**: Creates `claude-swarm` tmux session for external use
- **Pane management**: `tmux new-window`, `tmux list-panes`, `tmux select-pane`, `tmux kill-pane`
- **Layout**: `tmux select-layout tiled` for auto-arrangement

**Key patterns for `cs restore`:**
```bash
# Create named window in tmux
tmux new-window -n "<name>" "claude --resume '<name>'"

# Check if inside tmux
if [ -n "$TMUX" ]; then ...

# Create new tmux session if not in one
tmux new-session -s claude
```

### Claude Code Bridge Reference
From `/Users/adamf/Work/Strategy/Resources/ai-dev-toolchain-context.md`:
- Claude Code Bridge (225 stars): "persistent terminal sessions in tmux/WezTerm instead of MCP protocol. Each AI maintains independent context in split panes."
- Shows the concept of tmux-managed AI sessions is an established pattern in the ecosystem.

---

## 7. Session Data Structure

### Session Storage Location
- Sessions stored at `~/.claude/projects/<encoded-path>/<uuid>.jsonl`
- Path encoding: slashes replaced with hyphens, e.g., `-Users-adamf-Work-Strategy`
- The Strategy project has 90+ session files

### JSONL Session Records
Named sessions have `custom-title` records:
```json
{"type":"custom-title","customTitle":"Claude Code vs. Cursor Agents","sessionId":"1d131e22-72f1-4422-af97-c2164827edca"}
```

**Observed named sessions in this project:**
- "Claude Code vs. Cursor Agents"
- "Xiatech strategy"
- "Cube hosting"
- "giant context with cost model work"

**Implementation note:** The `custom-title` type appears multiple times per session (once per rename or compaction). The `cs list` command should deduplicate by sessionId and take the most recent title.

### Path Encoding
The plan says "encode the project path (replace `/` with `-`)". Verified: `/Users/adamf/Work/Strategy` becomes `-Users-adamf-Work-Strategy`. The leading hyphen is significant.

---

## 8. `~/.local/bin/` Directory Status

Current contents:
- `claude` symlink -> `/Users/adamf/.local/share/claude/versions/2.1.50`
- `reddit-user-to-sqlite` (pipx-installed tool)

The `cs` script will be the third item. The directory exists and is presumably on `$PATH` (since `claude` works from it).

---

## 9. Relevant Institutional Knowledge (from docs/solutions/)

### Origin Traceability Pattern
**File:** `/Users/adamf/Work/Strategy/docs/solutions/workflow-design/origin-traceability-and-phase-boundary-gates.md`
- **Relevance:** Session resume is fundamentally a phase-boundary crossing (suspended -> resumed). The gate principle suggests explicitly surfacing deferred items at resume time.
- **Application to `cs`:** When `cs restore` opens a session, Claude Code's `--resume` handles the context. But the beads `bd ready` command (which runs via SessionStart hook) already surfaces pending work. The existing hook architecture handles this.

### Adapting Code Tools for Analytical Work
**File:** `/Users/adamf/Work/Strategy/docs/solutions/workflow-design/adapting-code-tools-for-analytical-work.md`
- **Relevance:** The `cs` tool serves both code sessions (RAD prototype work) and analytical sessions (strategy, cost modeling). The tool doesn't need mode detection since it's session management, not session content.

### Upstream Fork Management
**File:** `/Users/adamf/Work/Strategy/docs/solutions/workflow-design/upstream-fork-management-pattern.md`
- **Relevance:** If `cs` evolves, the "discuss each delta" pattern applies to incorporating community improvements.

---

## 10. Related Brainstorm: Dual-Tool Workflow

**File:** `/Users/adamf/Work/Strategy/docs/brainstorms/2026-02-23-claude-code-cursor-dual-tool-brainstorm.md`

This brainstorm documents the CLI parity between Claude Code and Cursor:

| Operation | Claude Code | Cursor |
|-----------|-------------|--------|
| Resume session | `claude --resume <id>` | `agent --resume <id>` |
| Non-interactive | `claude -p "prompt"` | `agent -p "prompt"` |

**Implication:** The `cs` tool is currently Claude Code-specific. If it ever needs to support Cursor sessions too, the `claude --resume` calls would need to be configurable (e.g., `CS_AGENT_CMD=claude` vs `CS_AGENT_CMD=agent`). Not needed now, but worth noting for future extensibility.

The brainstorm also documents hooks translation:
- Claude Code's `SessionStart` -> Cursor's initial rule loading
- Claude Code's `Stop` -> Cursor's `stop` hook in `.cursor/hooks.json`
- Hooks format is different but functionally equivalent

---

## 11. Implementation Constraints and Conventions Summary

### Shell Script Conventions (from existing scripts)
1. Use `#!/bin/bash` (not `#!/bin/zsh` — scripts should be portable)
2. Use `set -uo pipefail` for strict mode
3. Environment variable defaults: `VAR="${ENV_VAR:-default}"`
4. Clear error messages with usage examples
5. `jq` for JSON parsing (already a dependency)
6. `printf` over `echo` for formatted output
7. Helper functions with named local variables

### Hooks Conventions (from existing config)
1. Hooks are defined in `~/.claude/settings.json` under the `hooks` key
2. Each hook type maps to an array of matchers, each with a `hooks` array
3. Hook commands receive JSON on stdin
4. Parse stdin once: `INPUT=$(cat)`, then extract fields with `jq`
5. Existing hooks (`SessionStart`, `PreCompact`) must be preserved when adding new ones

### File Locations
- CLI tool: `~/.local/bin/cs` (executable)
- Hook config: `~/.claude/settings.json` (modify existing)
- Session data: `~/.claude/projects/<encoded-path>/<uuid>.jsonl` (read-only)

### Dependencies (all pre-installed)
- `jq` 1.8.1 at `/opt/homebrew/bin/jq`
- `tmux` 3.6a
- `osascript` (macOS built-in)
- `basename`, `date`, `grep` (standard unix tools)

---

## 12. Gaps and Risks

### Not Found in Repo
1. **No `.tmux.conf`** — No existing tmux configuration to conflict with or build on. The `cs` tool starts from scratch for tmux layout management.
2. **No existing session management scripts** — This is genuinely new functionality. No prior art in the repo.
3. **No tests for shell scripts** — The `bq_cost_measurement.sh` has no test suite. The `cs` tool's verification plan (in the existing plan doc) is manual.

### Potential Issues
1. **JSONL parsing performance**: With 90+ session files (some very large — the "giant context" session has 6700+ lines), grepping through all of them could be slow. The plan's approach of grepping for `"type":"custom-title"` is correct — it avoids full JSON parsing.
2. **Session data format stability**: The JSONL format is internal to Claude Code and could change between versions. The `custom-title` record type and `customTitle` field name are undocumented.
3. **Hook stdin format**: The exact JSON structure of `Stop`, `Notification`, and `PostToolUseFailure` hook inputs is not documented in the repo. The plan's use of `.cwd` and `.message` fields is assumed from the `statusline-command.sh` pattern but needs verification.
4. **tmux session naming conflicts**: If the user has existing tmux sessions, `cs restore` could conflict. The plan doesn't specify a tmux session prefix/namespace.

---

## 13. Files Referenced in This Research

| File | Relevance |
|------|-----------|
| `/Users/adamf/.claude/plans/sprightly-weaving-pumpkin.md` | The existing plan for this feature |
| `/Users/adamf/.claude/settings.json` | Global hooks config to be modified |
| `/Users/adamf/.claude/statusline-command.sh` | Shell script pattern for JSON stdin parsing |
| `/Users/adamf/Work/Strategy/scripts/bq_cost_measurement.sh` | Shell script conventions |
| `/Users/adamf/Work/Strategy/.claude/settings.local.json` | Project-level permissions (tmux allowed) |
| `/Users/adamf/Work/Strategy/.beads/config.yaml` | Beads CLI config pattern |
| `/Users/adamf/Work/Strategy/.beads/README.md` | Beads CLI documentation pattern |
| `/Users/adamf/Work/Strategy/AGENTS.md` | Project conventions and memory |
| `/Users/adamf/Work/Strategy/docs/solutions/workflow-design/origin-traceability-and-phase-boundary-gates.md` | Phase-boundary gate pattern |
| `/Users/adamf/Work/Strategy/docs/solutions/workflow-design/adapting-code-tools-for-analytical-work.md` | Dual-mode tool pattern |
| `/Users/adamf/Work/Strategy/docs/solutions/workflow-design/upstream-fork-management-pattern.md` | Fork management pattern |
| `/Users/adamf/Work/Strategy/docs/brainstorms/2026-02-23-claude-code-cursor-dual-tool-brainstorm.md` | CLI parity and hooks translation |
| `/Users/adamf/.claude/plugins/cache/beads-marketplace/beads/0.49.4/.claude-plugin/plugin.json` | Plugin hook pattern |
| `/Users/adamf/.claude/plugins/cache/every-marketplace/compound-engineering/2.35.2/skills/orchestrating-swarms/SKILL.md` | tmux backend patterns |
| `/Users/adamf/.claude/agents/context-researcher.md` | Agent definition pattern |
| `/Users/adamf/.claude/commands/aworkflows/plan.md` | Workflow skill that spawned this research |
| `/Users/adamf/.claude/commands/aworkflows/work.md` | Work execution pattern with beads tracking |
| `/Users/adamf/.claude/commands/aworkflows/brainstorm.md` | Brainstorm workflow pattern |
| `/Users/adamf/Work/Strategy/.beads/.gitignore` | State file management pattern |
