---
title: "feat: Add /compound:recover command for dead session recovery"
type: feat
status: active
date: 2026-03-07
origin: docs/brainstorms/2026-03-07-recover-command-brainstorm.md
---

# feat: Add /compound:recover command

Reactive counterpart to `/compound:compact-prep`. Recovers context from a dead or exhausted Claude Code session by reading the JSONL session log, cross-referencing external state, and producing a structured recovery manifest (see brainstorm: Key Decision #1 — dead sessions only, not post-compaction).

## Acceptance Criteria

- [ ] Command exists at `commands/compound/recover.md` as `/compound:recover`
- [ ] Accepts optional argument: session ID, or empty for picker
- [ ] Session picker shows last 10 sessions with activity summaries and exhaustion flags (AskUserQuestion to see more)
- [ ] Parses JSONL using head + tail strategy (first 3-5 user messages + tail from last `compact_boundary`)
- [ ] Cross-references external state: beads, git, `.workflows/` artifacts, plan files
- [ ] Writes recovery manifest to `.workflows/recover/<session-id>/` (summary.md, session-extract.md, state-snapshot.md)
- [ ] Presents human-readable summary to user
- [ ] Offers replay by outputting the exact command for the user to run (not programmatic invocation)
- [ ] Extracts memory-worthy content and offers to update memory files (fills compact-prep gap)
- [ ] Degrades gracefully when beads/session logs are unavailable
- [ ] CLAUDE.md updated with `/recover` reference

## Implementation Steps

### Step 1: Create the command file

Create `plugins/compound-workflows/commands/compound/recover.md` with:

- [x] YAML frontmatter: `name: compound:recover`, `description: Recover context from a dead or exhausted Claude Code session`, `argument-hint: "[session ID or empty for picker]"`
- [x] Argument handling: `<session_id> #$ARGUMENTS </session_id>` with empty fallback to picker
- [x] Phase structure (5 phases, detailed below)

### Step 2: Phase 0 — Environment Detection

- [x] Derive session log directory: `SESSION_DIR="$HOME/.claude/projects/$(echo "$(pwd)" | tr '/' '-')"`
- [x] Verify directory exists, error if not: "No session logs found for this project"
- [x] Count available `.jsonl` files
- [x] Detect beads availability: `which bd 2>/dev/null`
- [x] If session ID argument provided, skip to Phase 2

### Step 3: Phase 1 — Session Discovery (Picker)

Build the session picker. For each of the N most recent `.jsonl` files (default 10):

- [x] Extract metadata via targeted parsing (type/timestamp only scan):
  - Session slug (from any entry's `slug` field)
  - First user text message (original intent preview)
  - Last user text message (recent activity preview)
  - Timestamp range (first entry → last entry)
  - Compact boundary count and last `preTokens` value
  - Whether session ended mid-assistant-turn (exhaustion heuristic)
- [x] Format picker entries with exhaustion flags:
  ```
  1. [slug] — "first user message preview..." (2h ago, 3 compactions) ⚠ possible exhaustion
  2. [slug] — "first user message preview..." (5h ago, 1 compaction)
  ```
- [x] Present via AskUserQuestion: "Which session to recover?"
- [x] After presenting 10, offer "See more sessions?" via AskUserQuestion (options: 20, 50, or all)

**Parsing approach for picker:** Stream each JSONL file line by line. For each line, parse only the `type`, `timestamp`, `slug` fields. Collect the first `user` entry with text content (not tool_result) and the last `user` entry with text content. Count `compact_boundary` entries and note the last `preTokens`. Check if the final entry is an incomplete `assistant` turn. Do not load full message content — only extract previews (first 80 chars of text).

**No flag-style arguments.** Other compound commands don't use `--flags`. Use AskUserQuestion for "see more" instead. Consistent with plugin conventions.

### Step 4: Phase 2 — Parse & Extract Selected Session

Parse the selected session's JSONL using head + tail strategy (see brainstorm: Resolved Question #1):

- [x] **Head extraction** — first 5 intent-bearing `user` entries (where `isMeta` is false and content is a `text` block, not `tool_result`). These capture original intent. Truncate each entry to 2KB max.
- [x] **Tail extraction** — last 30 intent-bearing entries from the last `compact_boundary` forward. If no compact_boundary exists, take the last 30 filtered entries from end of file. Truncate each to 2KB. Total extraction budget: 50KB of raw JSONL content.
- [x] **Command detection** — scan for `user` entries with `isMeta: true` or content containing `<command-name>` tags. Extract the last invoked `/compound:*` command and infer its phase from subsequent activity.
- [x] **Decision extraction** — find AskUserQuestion tool_use calls in `assistant` entries and their corresponding `tool_result` responses in `user` entries. These are the user's decisions.
- [x] **File path extraction** — find `Read`, `Write`, `Edit` tool_use calls to identify which files were being worked on.
- [x] **Error extraction** — find `tool_result` entries with `is_error: true` to identify failures.
- [x] **Subagent detection** — find `Agent` tool_use calls to identify background work.

**Context safety:** Do not read the full content of large entries (tool_results with file contents, assistant entries with thinking blocks). Extract only the structured fields needed (tool name, file path, error flag, first 100 chars of text content).

### Step 5: Phase 3 — Cross-Reference External State

Check each recovery source (see brainstorm: Key Decision #5 — priority order):

- [x] **`.workflows/` artifacts:**
  ```bash
  ls -lt .workflows/brainstorm-research/ .workflows/plan-research/ .workflows/deepen-plan/ .workflows/compound-research/ .workflows/code-review/ .workflows/work-review/ 2>/dev/null
  ```
  For any directories modified within the session's time range, note the workflow type and stem.
  If a `manifest.json` exists in deepen-plan, read its `status` field.

- [x] **Beads state** (if available):
  ```bash
  bd list --status=in_progress 2>/dev/null
  bd list --status=open 2>/dev/null | head -5
  ```

- [x] **Git state:**
  ```bash
  git status --short
  git log --oneline -10
  git stash list
  ```

- [x] **Plan files:**
  ```bash
  ls -lt docs/plans/*.md 2>/dev/null | head -5
  ```
  For recent plans, check YAML frontmatter for `status: active` and count unchecked `- [x]` items.

- [x] **Compact-prep detection:** Check if a `compact_boundary` entry exists in the JSONL with activity before and after it. If compact-prep ran, note it — memory was likely updated, work likely committed.

### Step 6: Phase 4 — Write Recovery Manifest

Write three files to `.workflows/recover/<session-id>/` (overwrite if exists — see brainstorm: Resolved Question #5):

- [x] **`summary.md`** — Human-readable recovery summary:
  ```markdown
  # Recovery Summary: [session slug]

  **Session:** [session-id]
  **Time range:** [start] → [end]
  **Compactions:** [N] (last at [preTokens] tokens)
  **Status:** [⚠ possible exhaustion | normal end | compact-prep ran]

  ## What Was Happening
  [Synthesized from JSONL head + tail: original intent, last active task, command/phase if detected]

  ## Key Decisions Made
  [AskUserQuestion decisions extracted from JSONL]

  ## Files Being Worked On
  [File paths from Read/Write/Edit tool calls]

  ## External State
  - Beads: [N in_progress issues | not available]
  - Git: [uncommitted changes summary | clean]
  - .workflows/: [active artifacts found | none]
  - Plans: [active plans with unchecked items | none]

  ## Recommended Next Step
  [If compound command detected: "Resume /compound:[command] from Phase N"]
  [If interactive work: "Continue working on [topic]"]
  [If clean: "No interrupted work detected"]
  ```

- [x] **`session-extract.md`** — Structured extracts from JSONL:
  ```markdown
  # Session Extract: [session-id]

  ## Original Intent (Head)
  [First 3-5 user messages — the "why" of the session]

  ## Recent Context (Tail from last compaction)
  [Last ~10 user text messages, summarized]

  ## Active Command
  [Detected /compound:* command and inferred phase, or "interactive work"]

  ## Decisions
  [AskUserQuestion Q&A pairs]

  ## Errors
  [Tool errors encountered]

  ## Subagents
  [Agent dispatches and their status]
  ```

- [x] **`state-snapshot.md`** — External state at recovery time:
  ```markdown
  # State Snapshot: [timestamp]

  ## Beads
  [bd list output or "not available"]

  ## Git
  [git status + recent log]

  ## .workflows/ Artifacts
  [Recently modified directories and their contents]

  ## Active Plans
  [Plans with status: active and unchecked items]
  ```

### Step 7: Phase 5 — Present Summary & Offer Resume

- [x] Present the `summary.md` content directly to the user (don't just say "file written")
- [x] If a `/compound:*` command was detected, output the exact command to re-run:
  ```
  "The session was running /compound:deepen-plan docs/plans/my-plan.md in Phase 3 (red team).
  To resume, run: /compound:deepen-plan docs/plans/my-plan.md
  (deepen-plan will detect the interrupted manifest and resume automatically)."
  ```
  Then AskUserQuestion: "What would you like to do?"
  - Run the command above to resume
  - Continue manually (recovery context is loaded)
  - Done — just needed the summary
- [x] If interactive work (no command detected):
  ```
  "The session was working on [topic]. Recovery manifest written to .workflows/recover/<id>/."
  ```
  AskUserQuestion: "What would you like to do?"
  - Continue from here (recovery context is loaded)
  - Done — just needed the summary
- [x] **Note:** Commands cannot programmatically invoke other commands. The resume offer outputs the exact command string for the user to copy-paste. For commands with built-in recovery (deepen-plan), note that they'll auto-detect the interrupted state. For commands without (brainstorm, plan), the user starts fresh with the recovery context available on disk.

### Step 7.5: Memory Extraction (compact-prep gap)

When compact-prep doesn't run before a session dies, decisions and rationale are lost. This step fills that gap.

- [x] Scan the session extract for decision patterns: AskUserQuestion responses with rationale, explicit user preferences, corrections to prior assumptions
- [x] If memory-worthy content found, present via AskUserQuestion:
  ```
  "The dead session contained decisions/rationale that may be worth persisting to memory:
  - [Decision 1: brief summary]
  - [Decision 2: brief summary]
  Update memory files with these?"
  ```
  - Yes — update relevant memory files
  - Skip — don't update memory
- [x] If no memory-worthy content detected, skip silently

### Step 8: Update CLAUDE.md

- [ ] Add `/compound:recover` to the command list in `plugins/compound-workflows/CLAUDE.md`
- [ ] Brief description: "Recover context from a dead or exhausted session"
- [ ] Note the relationship with compact-prep

### Step 9: QA

- [ ] Run AGENTS.md QA checks (4 parallel agents)
- [ ] Verify command shows in slash command palette
- [ ] Test with a real session log (manual smoke test)

## Edge Cases

- **Empty session log:** Single-line JSONL (session started but no activity). Show in picker but note "no activity".
- **Very large session:** 24MB+ files. The head + tail strategy with 50KB budget and 2KB-per-entry truncation prevents context exhaustion.
- **No compact boundaries:** Parse last 30 filtered entries from end of file (same budget as tail strategy).
- **Current session selected:** Warn the user: "This appears to be the current session. Recovery is for dead sessions."
- **Session from different branch:** Note the `gitBranch` field in the summary — the user may have switched branches since.
- **Session from different working directory:** Note the `cwd` field if it differs from current `pwd` (may indicate worktree usage).
- **Beads unavailable:** Skip beads checks entirely. Don't error, just note "beads: not available" in state snapshot.
- **No `.workflows/` directory:** Skip artifact checks. Note "no .workflows/ directory found".
- **Malformed JSONL line:** Skip the line with a warning (session may have been mid-write during crash). Continue parsing.
- **Multiple commands in one session:** Detect the LAST active command (most relevant for recovery). Note prior commands as completed context.
- **Session still active in another terminal:** No detection mechanism. Known limitation — document it. The recovery manifest will be based on a partial, growing log.

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-03-07-recover-command-brainstorm.md` — Key decisions carried forward: dead sessions only (not post-compaction), plugin command, write manifest → present summary → offer replay, head + tail JSONL parsing, flag but don't filter exhaustion, configurable picker (default 10), idempotent overwrite.
- **Brainstorm research:** `.workflows/brainstorm-research/recover-command/` (repo-research.md, context-research.md, red-team--gemini.md)
- **Plan research:** `.workflows/plan-research/recover-command/agents/` (repo-research.md, learnings.md, specflow.md)
- **JSONL format:** Empirically discovered by inspecting `~/.claude/projects/-Users-adamf-Dev-compound-workflows-marketplace/*.jsonl`. Entry types: progress, assistant, user, file-history-snapshot, queue-operation, system, custom-title, last-prompt. System subtypes: turn_duration, compact_boundary, local_command.
