# Architecture Review: Claude Session Resume CLI Tool

**Reviewer:** architecture-strategist agent
**Date:** 2026-02-23
**Plan reviewed:** `/Users/adamf/Work/Strategy/docs/plans/2026-02-23-feat-claude-session-resume-tmux-plan.md`
**Research inputs:** `research--best-practices.md`, `research--hooks-docs.md`

---

## 1. Architecture Overview

The tool has two distinct components with different architectural profiles:

- **`cs` CLI** (`~/.local/bin/cs`): A bash script that reads Claude Code's internal JSONL session files to list named sessions and orchestrates tmux to restore them.
- **Notification hooks** (`~/.claude/hooks/*.sh`): Three fire-and-forget shell scripts invoked by Claude Code's hook system to trigger macOS desktop notifications.

These share no state, no runtime coupling, and no code. They are correctly designed as independent components that happen to ship together.

---

## 2. Evaluation: Bash vs. Python/Go/Rust

**Verdict: Bash is the right choice for v1. The plan gets this right.**

Reasons it works:

- The tool is glue code. It calls `grep`, `jq`, `stat`, `tmux`, and `osascript`. Bash is the native language for orchestrating CLI tools. Python would add subprocess overhead and a venv dependency. Go/Rust would add a build step for no benefit.
- The plan correctly estimates ~100 lines. At that size, bash is readable and maintainable.
- All dependencies (`jq`, `tmux`, `osascript`, `realpath`) are already installed. Zero setup.
- The hooks are 10-15 lines each. Any other language would be over-engineering.

Reasons to switch later (and the trigger for switching):

- **If `cs` grows past ~200 lines of logic**, the lack of structured error handling, named data types, and testability in bash becomes a liability. The specflow analysis already identified 25 gaps that would each add 5-15 lines of defensive code. Addressing even half of them pushes toward 200+ lines.
- **If session data parsing becomes complex** (e.g., needing to correlate subagent files with parent sessions, or parse timestamps from within JSONL records), `jq` pipelines become unreadable. Python's `json` module is strictly better for multi-field extraction and aggregation.
- **If the tool needs to support multiple projects simultaneously** (e.g., `cs list --all`), the path encoding + directory scanning + deduplication logic becomes a three-dimensional problem that bash handles poorly.

**Concrete recommendation:** Implement v1 in bash. Add a comment at the top: `# If this script exceeds 200 lines, rewrite in Python.` This makes the architectural decision and its escape hatch explicit.

---

## 3. Evaluation: JSONL grep vs. Index/Cache

**Verdict: grep is sufficient for current scale. The plan gets this right, but the robustness boundary is closer than it appears.**

### Current scale analysis

- 108 session files in the Strategy project directory (confirmed from glob results)
- Only 7 of those contain `custom-title` records (confirmed from grep)
- `grep -l "custom-title"` across 108 files completes in milliseconds (grep stops reading each file at first match with `-l`)
- Subsequent `jq` parsing runs on only 7 files
- Total wall time: under 100ms on warm filesystem cache, under 500ms on cold

### Where it breaks

- **Subagent files:** The directory contains deep `subagents/` subdirectories. The glob returned files like `39d5a373.../subagents/agent-abb97ae.jsonl` that *also* contain `custom-title` records. The plan's glob pattern `~/.claude/projects/<encoded>/*.jsonl` only matches top-level files, which is correct for session listing (subagents are not user-resumable sessions). But this is an implicit assumption that should be explicit in the implementation: only scan `*.jsonl` in the top-level directory, never recurse into `subagents/`.

- **Multi-project scanning:** If the user wants `cs list --all` (not in v1, but an obvious v2 feature), the tool would need to scan every project directory. With 20+ encoded paths and 100+ files each, the linear scan becomes noticeable (1-3 seconds). At that point, a simple cache file (`~/.claude/cs-index.json`) updated on `SessionStart` hook would be the right move.

- **Format breakage:** This is the real risk, not performance. The JSONL format is an undocumented internal API. The `custom-title` type, the `customTitle` field name, and the path encoding scheme could all change in any Claude Code update. The plan mentions "defensive checks" but does not specify what they look like.

**Concrete recommendation:** Add a version-detection guard at the top of `cs list`:

```bash
# Verify session directory structure exists
SESSIONS_DIR="$HOME/.claude/projects"
if [[ ! -d "$SESSIONS_DIR" ]]; then
  printf 'Error: %s not found. Is Claude Code installed?\n' "$SESSIONS_DIR" >&2
  exit 1
fi

# Verify at least one encoded-path directory contains JSONL files
if ! ls "$ENCODED_DIR"/*.jsonl &>/dev/null; then
  printf 'No sessions found for %s\n' "$PROJECT_DIR" >&2
  exit 0
fi
```

Skip the index/cache for v1. The grep approach handles the current scale with margin to spare. If v2 needs multi-project scanning, add a SessionStart hook that appends to a lightweight index file.

---

## 4. Evaluation: Separate Hook Script Files

**Verdict: Correct decision. The plan already adopted this pattern, which is good.**

The plan specifies three separate files in `~/.claude/hooks/`:
- `notify-attention.sh` (Notification hook)
- `notify-error.sh` (PostToolUseFailure hook)

This matches the existing pattern of `~/.claude/statusline-command.sh` and avoids the JSON-escaping nightmare of inline shell commands. The specflow analysis identified this issue in the earlier plan draft and the current plan correctly addresses it.

**One structural concern:** The plan puts the hook scripts in `~/.claude/hooks/` but the `cs` CLI in `~/.local/bin/cs`. These are logically part of the same tool but live in different directories with no cross-reference. If someone deletes or moves `~/.claude/hooks/notify-attention.sh`, there is no error visible to the user -- the hook silently fails (non-zero exit codes on hooks are swallowed in verbose mode only).

**Recommendation:** This is acceptable for a personal tool. Do not try to add health-check logic or cross-referencing. If you later package this for distribution, consolidate everything under one directory with a setup script that creates symlinks.

---

## 5. Evaluation: Own State vs. Reading Claude's Files Directly

**Verdict: Reading Claude's files directly is correct for v1. Do not maintain separate state.**

The arguments against maintaining separate state:

- **Single source of truth.** The session JSONL files are the authoritative record of which sessions exist and what they are named. Any separate state would be a cache that can go stale.
- **No write operations.** `cs` only reads session data. It never modifies sessions, creates them, or deletes them. There is nothing to track that Claude's files do not already contain.
- **No synchronization problem.** If `cs` maintained a separate index, it would need to handle: sessions created outside `cs`, sessions renamed after indexing, sessions deleted by Claude Code compaction, sessions that appear in new project directories. All of these "just work" when reading the source files directly.
- **Simplicity.** Zero state means zero corruption risk, zero migration path, zero cleanup.

The one scenario where separate state becomes necessary:

- **Cross-session metadata.** If v2 needs features like "tag sessions," "mark sessions as archived," "group sessions into layouts," or "track which sessions were last restored together," Claude's JSONL files cannot store that. At that point, a `~/.claude/cs-state.json` or SQLite file becomes justified. But not before.

**Concrete recommendation:** Read Claude's files directly. Do not create `~/.claude/cs-state.json` or any other state file. If v2 needs custom metadata, use a single JSON file (not JSONL, not SQLite -- the data is small and read-heavy).

---

## 6. Evaluation: Ecosystem Composition

**This is where the plan has a significant blind spot.**

### The `cs` binary name collides with claude-squad

[Claude Squad](https://github.com/smtg-ai/claude-squad) is an established open-source tool (Go, actively maintained) that installs as `cs` to `~/.local/bin/`. It manages multiple Claude Code sessions in tmux with git worktree isolation, auto-accept mode, diff previews, and branch management.

The plan proposes installing a bash script named `cs` to `~/.local/bin/`. If claude-squad is ever installed (even for evaluation), one overwrites the other. This is not a theoretical risk -- claude-squad is one of the most-discussed Claude Code session management tools in the ecosystem.

**This naming collision must be resolved before implementation.** Options:

1. **Rename to `csr`** (claude session resume) -- short, distinct, no known collisions.
2. **Rename to `csm`** (claude session manager) -- also clear, but closer to ccmanager's territory.
3. **Rename to `claude-sessions`** -- unambiguous but verbose for frequent use.
4. **Keep `cs` and accept the collision** -- defensible only if you are certain you will never evaluate claude-squad.

I recommend `csr`. It is three characters (fast to type), mnemonic, and unique in the ecosystem.

### How this tool relates to the existing ecosystem

| Tool | What It Does | How `cs`/`csr` Differs |
|------|-------------|----------------------|
| [claude-squad](https://github.com/smtg-ai/claude-squad) (`cs`) | Full TUI for managing multiple AI agent sessions with tmux + git worktrees. Go binary. | Much heavier. Creates new sessions, manages branches, handles diffs. `csr` only lists and restores *existing named sessions*. Different scope entirely. |
| [agent-deck](https://github.com/asheshgoplani/agent-deck) | TUI dashboard for AI coding agents. Session forking, MCP management, conductor agents. Go binary. | Enterprise-grade session management. `csr` is intentionally minimal -- it does not monitor, fork, or orchestrate. |
| [ccmanager](https://github.com/kbwo/ccmanager) | Multi-agent session manager (Claude, Gemini, Codex, etc.). Go binary. | Agent-agnostic. `csr` is Claude-Code-specific by design. |
| [claunch](https://github.com/0xkaz/claunch) | Project-based Claude CLI session manager with tmux. | Closest competitor in scope. Creates sessions from project configs. `csr` works with existing named sessions, no project config needed. |
| [claude-tmux](https://github.com/nielsgroen/claude-tmux) | tmux popup with session management and git worktree support. | tmux-native integration (popup, not TUI). Different UX model. |
| `claude --resume` (built-in) | Resume a session by name or UUID interactively. | `csr` adds: non-interactive listing, tmux window creation, batch restore. These are the actual gaps in the built-in tool. |

**The plan's value proposition is real:** none of these tools solve the specific problem of "list my named sessions from the shell and restore them into tmux windows after a reboot." claude-squad and agent-deck create and manage their *own* sessions. `csr` works with sessions created during normal Claude Code usage via `/rename`. That is a genuinely different approach.

**But the plan should explicitly acknowledge this ecosystem** and explain why a new tool is justified rather than adopting or wrapping an existing one. The answer is: the existing tools are session *orchestrators* that manage the lifecycle. This tool is a session *browser* that reads existing state. Different architectural role.

### Composition opportunities

- **`csr list --json`** (cut from v1 but noted for v2) would enable piping into other tools: `csr list --json | jq '.[] | .name'` could feed into claude-squad or any other orchestrator.
- **The notification hooks are tool-agnostic.** They work regardless of whether sessions are managed by `csr`, claude-squad, or raw `claude` CLI. They should be documented as standalone components that can be adopted independently.

---

## 7. Evaluation: Upgrade Path

### From personal tool to shared tool

The plan is correctly scoped as a personal tool with hardcoded macOS assumptions (`osascript`, BSD `stat`, Homebrew `jq` path). If this needs to be shared:

**Step 1 (minimal):** Move the `osascript` calls behind a `notify()` function. Add a Linux branch that uses `notify-send`. This is a 10-line change.

**Step 2 (portable):** Replace BSD `stat -f %m` with the portable wrapper from the best-practices research. Replace `/opt/homebrew/bin/jq` with `command -v jq` lookup. These are already documented in the research.

**Step 3 (distributable):** Create a `Makefile` or install script. Package the `cs`/`csr` binary and hook scripts together. Add `cs setup` to configure `settings.json` hooks automatically (currently a manual merge).

**Step 4 (rewrite trigger):** If the tool needs config files, persistent state, or multi-platform CI, rewrite in Python or Go. Bash does not scale to that complexity.

### From session browser to session manager

The plan explicitly cuts `--layout` (save/restore window arrangement) and `--json` output from v1. These are the two features that would move `csr` from "browser" to "manager" territory:

- `--layout` implies state (saved arrangements) and conflicts with claude-squad's raison d'etre.
- `--json` is purely additive and should be the first v2 feature. It enables composition without expanding scope.

**Recommendation:** Add `--json` in v2. Track `--layout` as a separate evaluation -- before building it, re-evaluate whether claude-squad or agent-deck already solve the layout problem.

---

## 8. Specific Architectural Issues in the Plan

### Issue 1: Timeout unit error (CRITICAL)

The plan specifies `"timeout": 5000` in the hook configuration. Per the official hooks documentation (confirmed in `research--hooks-docs.md`), **timeout is in seconds, not milliseconds.** A value of 5000 means 5000 seconds (83 minutes), not 5 seconds. The correct value for a 5-second timeout is `"timeout": 5`.

**File:** `/Users/adamf/Work/Strategy/docs/plans/2026-02-23-feat-claude-session-resume-tmux-plan.md`, lines 138 and 148.

### Issue 2: PostToolUseFailure matcher should filter `is_interrupt`

The plan's PostToolUseFailure hook has `"matcher": ""` (matches all tool failures). The plan mentions "Skip if `is_interrupt` is true" in the description but the matcher cannot express this -- it matches on `tool_name`, not on `is_interrupt`. The filtering must happen in the script itself:

```bash
IS_INTERRUPT=$(printf '%s' "$INPUT" | jq -r '.is_interrupt // false')
if [[ "$IS_INTERRUPT" == "true" ]]; then
  exit 0
fi
```

The plan's hook script description says to do this, so this is not a gap in intent -- but the implementation detail matters because `is_interrupt` is documented as an **optional boolean**. It may not be present in the JSON at all. The `jq` expression must use `// false` to handle the missing-field case.

### Issue 3: `cs restore` uses `tmux new-window` with command argument

The plan specifies:
```bash
tmux new-window -n "<sanitized-name>" "claude --resume '<name>'"
```

This creates a tmux window that runs `claude --resume` as its *initial command*. When that command exits (user quits the Claude session), the tmux window closes automatically. This is correct behavior for session restoration -- but the user should know that closing the Claude session closes the tmux window. No plan change needed, but this should be noted in the `cs help` output.

### Issue 4: Plan removes the Stop hook but the specflow still references it

The current plan (the version I reviewed at `/Users/adamf/Work/Strategy/docs/plans/2026-02-23-feat-claude-session-resume-tmux-plan.md`) does NOT include a Stop hook -- it only has Notification and PostToolUseFailure hooks. The specflow analysis (`specflow.md`) extensively discusses the Stop hook, its `stop_hook_active` loop risk, and the "Glass" sound. This mismatch suggests the Stop hook was correctly cut during plan refinement. If so, the specflow's warnings about Stop hooks are moot for v1. Good decision -- Stop fires on every response turn and would be extremely noisy.

### Issue 5: Notification hook matcher includes `idle_prompt`

The plan's Notification hook uses `"matcher": "permission_prompt|idle_prompt"`. The `idle_prompt` notification type fires when "Claude has been idle / waiting for input." For a tool that manages 15+ concurrent sessions, idle notifications from every session would be noisy. Consider whether `idle_prompt` is genuinely useful or if `permission_prompt` alone is sufficient for v1.

---

## 9. Risk Analysis

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Claude Code changes JSONL format | Medium (internal API, no stability guarantee) | `cs list` breaks silently | Defensive checks + clear error messages when format is unrecognized |
| Binary name collision with claude-squad | High (same name, same install location) | One tool overwrites the other | Rename to `csr` before implementation |
| Timeout unit error (5000 seconds) | Certain (documented as seconds, plan says 5000) | Hooks block for 83 minutes on failure | Change to `5` |
| Notification fatigue from PostToolUseFailure | Medium (retry loops produce many failures) | User ignores all notifications | Add rate-limiting or debounce in the hook script |
| Shell injection via session names | Low (names are user-controlled via `/rename`) | Arbitrary command execution | Sanitize names before passing to `tmux` and `osascript` |
| macOS notification permissions not granted | Medium (Sequoia requires explicit permission) | Notifications silently fail | Document setup step, add `|| true` fallback |

---

## 10. Recommendations Summary

**Must fix before implementation:**

1. **Rename `cs` to `csr`** (or another name that does not collide with claude-squad).
2. **Fix timeout values** from `5000` to `5` in the hook configuration.
3. **Add `is_interrupt` filtering** in the PostToolUseFailure hook script with `// false` default for the optional field.

**Should fix before implementation:**

4. **Explicitly document that only top-level JSONL files are scanned** (not `subagents/` directories). The glob `*.jsonl` handles this, but it should be a conscious choice, not an accident.
5. **Evaluate whether `idle_prompt` is worth including** in the Notification matcher for v1. With 15 concurrent sessions, idle notifications may be noisy.
6. **Add the `async: true` flag** to both hook configurations. These are fire-and-forget side effects that should not block Claude's execution.

**Should fix in v2:**

7. Add `--json` output to `cs list`.
8. Add rate-limiting / debounce to notification hooks (e.g., no more than one notification per 10 seconds per session).
9. Add `cs setup` subcommand to automate the `settings.json` merge.

---

## 11. Verdict

The plan is architecturally sound for its stated scope. The decision to use bash, read Claude's files directly, and use separate hook scripts are all correct. The tool fills a genuine gap that existing ecosystem tools (claude-squad, agent-deck) do not address -- they are session orchestrators, while this is a session browser.

The critical issues are: the naming collision with claude-squad (rename to `csr`), the timeout unit error (change `5000` to `5`), and the need for defensive handling of the undocumented JSONL format. None of these require architectural changes -- they are implementation fixes that preserve the current design.

The upgrade path is clear: bash is appropriate up to ~200 lines. Beyond that, rewrite in Python. Beyond needing persistent state or multi-platform distribution, rewrite in Go. The plan correctly cuts scope to stay within bash's sweet spot.
