---
title: "/compound:recover — Dead Session Recovery Command"
date: 2026-03-07
origin: /Users/adamf/Documents/Projects/WhatsNext/docs/solutions/meta-tooling/session-log-mining-full-analysis.md
tags:
  - recover
  - session-recovery
  - context-exhaustion
  - automation
status: draft
---

# /compound:recover — Dead Session Recovery Command

## What We're Building

A command that recovers context from a dead or exhausted Claude Code session. It reads the JSONL session log, cross-references external state (beads, git, `.workflows/` artifacts), writes a structured recovery manifest to disk, presents a summary, and optionally offers to re-invoke the interrupted command.

This is the **reactive** counterpart to `/compound:compact-prep` (proactive). Compact-prep preserves context before compaction; recover reconstructs it after an unplanned session death.

## Why This Approach

From session-log-mining analysis: ~4% of sessions need explicit recovery. The current approach is fully manual — paste a session UUID, describe the interruption point, say "resume." This is error-prone and loses nuance.

The JSONL session logs already exist at `~/.claude/projects/<project-hash>/<session-id>.jsonl` — they're written by Claude Code automatically. No new logging infrastructure needed. The command just reads what's already there.

## Key Decisions

### 1. Scope: Dead sessions only, not post-compaction
**Decision:** `/recover` handles sessions that died or exhausted context unexpectedly. Post-compaction recovery is handled by `/compact-prep`'s post-compaction task queue.
**Rationale:** User explicitly separated these concerns. Compact-prep is proactive (you planned for it); recover is reactive (it broke unexpectedly).

### 2. Plugin command, not personal command
**Decision:** Lives at `commands/compound/recover.md` as `/compound:recover`.
**Rationale:** Leverages `.workflows/` conventions and can do richer recovery when a compound command was running (manifest detection, agent output discovery). Still useful for non-compound sessions — just produces a simpler summary.

### 3. Output: Write to disk, present summary, offer replay
**Decision:** Three-step output:
- **C** — Write structured recovery manifest to `.workflows/recover/<session-id>/`
- **A** — Present a human-readable summary of what was happening
- **B** — Offer to re-invoke the interrupted command (user option, not automatic)
**Rationale:** Disk-first follows the plugin's persistence philosophy. Presenting the summary gives the user agency. Replay is opt-in because the user may want to change approach.

### 4. Session discovery: Auto-list recent sessions with summaries
**Decision:** When invoked without arguments, show recent sessions for the current project with:
- Activity summary (what was being worked on, not just first message)
- Whether context was exhausted
- Last modified timestamp
- Session ID for selection
**Rationale:** Users shouldn't have to hunt for UUIDs in the filesystem. A picker with activity summaries is more useful than first-message previews (which could be "resume" and tell you nothing).

### 5. Recovery sources (priority order)
1. **JSONL session log** — primary source of intent, decisions, conversation flow
2. **`.workflows/` artifacts** — incomplete research, manifests, partial agent outputs
3. **Beads state** — `bd list --status=in_progress` for active work items
4. **Git state** — uncommitted changes, recent commits
5. **Plan files** — `docs/plans/*.md` with unchecked items
6. **Memory files** — stable project context

### 6. Recovery manifest structure
```
.workflows/recover/<session-id>/
  summary.md          # Human-readable: what was happening, where it stopped, what's recoverable
  session-extract.md  # Key exchanges from JSONL: last user messages, decisions made, files referenced
  state-snapshot.md   # External state: beads issues, git status, .workflows/ artifacts found
```

## Approach

### Phase 1: Session Discovery
- Locate project's session log directory (`~/.claude/projects/<project-hash>/`)
- List JSONL files, sorted by last modified
- For each recent session: parse tail of JSONL to extract activity summary + detect exhaustion
- Present picker via AskUserQuestion (or accept session ID as argument)

### Phase 2: Parse & Extract
- Read selected session's JSONL
- Extract: last ~20 user messages, active command/phase, AskUserQuestion decisions, file paths referenced, error messages, subagent dispatches
- Detect which `/compound:*` command was running (if any) and what phase it was in

### Phase 3: Cross-Reference External State
- Check `.workflows/` for artifacts from the session (brainstorm research, plan research, manifests, agent outputs)
- Check beads for in_progress issues
- Check git for uncommitted changes and recent commits
- Check plan files for active plans with unchecked items

### Phase 4: Write Recovery Manifest
- Write structured files to `.workflows/recover/<session-id>/`
- Present summary to user

### Phase 5: Offer Resume
- If a compound command was detected: "The session was running `/compound:deepen-plan` in Phase 3 (red team). Resume from there?"
- If interactive work: "The session was working on [topic]. Here's the context — continue from here?"
- User chooses to resume the command, continue manually, or do nothing

## JSONL Session Log Format

Discovered by inspecting actual session logs. Entry types (from a 4849-line / 24MB session):

| Type | Count | Description |
|------|-------|-------------|
| `progress` | 1571 | Streaming progress updates |
| `assistant` | 1482 | Assistant responses (heavy — contains full content) |
| `user` | 1166 | User messages and tool results |
| `file-history-snapshot` | 450 | File state snapshots |
| `queue-operation` | 94 | Task queue operations |
| `system` | 79 | System events (subtypes below) |
| `custom-title` | 8 | Session title updates |
| `last-prompt` | 6 | Last prompt markers |

**System subtypes:** `turn_duration` (65), `compact_boundary` (7), `local_command` (7)

**Key structure per entry:** `type`, `sessionId`, `uuid`, `parentUuid`, `timestamp`, `cwd`, `version`, `gitBranch`, `slug`, `message` (for user/assistant types)

**Compact boundary entry:** Has `compactMetadata: { trigger: "manual", preTokens: N }` — indicates when compaction occurred and how full the context was.

**No explicit exhaustion signal.** There is no `context_exhaustion` entry type. Exhaustion must be inferred heuristically.

### Project directory derivation
The session log directory uses the project's absolute path with `/` replaced by `-`:
`~/.claude/projects/-Users-adamf-Dev-compound-workflows-marketplace/<session-id>.jsonl`

## Resolved Questions

### 1. JSONL parsing depth
**Decision:** Two-tier approach — metadata scan for the picker, head + tail for full recovery. Parse the first 3-5 user messages (original intent/task description) plus everything from the last `compact_boundary` forward (recent context).
**Rationale:** Metadata scan (type/timestamp only) is fast even for large files and gives enough for activity summaries. For recovery, the head captures the original intent that may not exist in external artifacts (especially for interactive sessions), and the tail captures recent context. Red team (Gemini) correctly identified that tail-only would miss foundational intent.

### 2. Project directory derivation
**Decision:** Path with `/` replaced by `-` (e.g., `-Users-adamf-Dev-compound-workflows-marketplace`).
**Rationale:** Verified by inspecting `~/.claude/projects/` — no hashing, just path transformation.

### 3. Exhaustion detection
**Decision:** Flag but don't filter. Show all recent sessions in the picker with activity summaries, but add a visual indicator (e.g., "⚠ possible exhaustion") based on heuristics.
**Rationale:** No explicit exhaustion entry exists in the JSONL. Heuristic-only detection risks false positives. Showing everything with flags gives the user full visibility while still surfacing likely problem sessions. Heuristics to flag: session ends mid-assistant-turn, last `compact_boundary` has high `preTokens` with no subsequent meaningful user messages.

### 4. Session age cutoff
**Decision:** Configurable with a default of 10 sessions. Accept an optional argument to override (e.g., `--limit 20` or `--since 48h`).
**Rationale:** 10 sessions covers most recovery scenarios without overwhelming the picker. Configurability handles edge cases (busy day with many short sessions, or recovering from a session days ago).

### 5. Multiple recovery attempts
**Decision:** Overwrite the prior manifest. Recovery is idempotent.
**Rationale:** External state (git, beads, .workflows/) may have changed since the last recovery attempt, so a fresh snapshot is more accurate than a stale one. No value in keeping recovery history — the session log itself is the immutable record.

## Red Team Review (Gemini)

### Resolved

1. **CRITICAL — Cross-platform path resolution.** Rejected: Claude Code plugins are macOS/Linux only. Windows support is not a current concern. The path mangling convention (`/` → `-`) is sufficient for the target platforms.

2. **SERIOUS — Data leak risk (session extracts in .workflows/).** Rejected: Session extracts are structured summaries, not raw dumps. `.workflows/` is already offered for `.gitignore` by the setup command. Risk is overstated.

3. **SERIOUS — Contradiction: tail-only misses original intent.** Accepted: Updated JSONL parsing to use head + tail strategy. Parse first 3-5 user messages for original intent plus tail from last `compact_boundary` for recent context.

4. **SERIOUS — No official Claude Code export API.** Rejected: The JSONL files are the de facto interface. Claude Code is open-source; the format is discoverable and the risk of breakage is acceptable for an internal tool.

5. **MINOR — Exhaustion heuristics false positives.** Acknowledged: Since heuristics only flag (don't filter), false positives from Ctrl+C or terminal close are tolerable.

## Open Questions

None — all questions resolved.
