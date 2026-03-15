# CSR Exploration Journal

**Session ID:** `39d5a373-bf6d-4f8d-8385-67c2a9e7551d`
**Date:** 2026-02-23 (based on plan date)
**Transcript:** 1,975 lines JSONL
**Session title:** "csr" (renamed by Adam near end)

---

## 1. The Exploration Arc

### Phase 1: "Tips for tmux + Claude" (Lines 2-20)

Adam opened with a general question: **"tips/plugins for using claude with tmux"**. The assistant provided generic advice (escape-time, color support, keybindings), then confidently hallucinated a `--name` flag for Claude Code. Adam tried to use it, it didn't work, and the assistant had to correct itself:

> "No `--name` flag. I made that up -- sorry. Claude Code doesn't set the terminal title at all."

This correction established a pattern for the session: claims about Claude Code features were unreliable and needed verification.

Adam then asked about `-c` (continue flag) and the distinction between tmux sessions and Claude named sessions. The assistant clarified these are "completely different things" -- tmux pane titles are cosmetic, Claude's `-c`/`--resume` are conversation state.

### Phase 2: Ecosystem Research (Lines 22-222)

Adam asked: **"do research on how other people use tmux and claude code together. in particular, integrating the sessions up"**

This launched a massive research phase covering 30+ tools. The research went through several rounds:

1. **First pass** (Line 22) -- Found the core ecosystem: Matsuyama's popup pattern, Zaadi's auto-resume hook, official agent teams, claude-squad, NTM, Claudeman, claude-tmux, Quemy's notification system.

2. **"research more tools like tier 2, and better compare them for me"** (Line 103) -- Deeper comparison of 7 tmux-based session managers with feature matrices and star counts.

3. **"what about gas town and such?"** (Line 206) -- Researched Gastown (Steve Yegge's multi-agent orchestrator, 10.1k stars). Conclusion: "overkill" for Adam's needs.

4. **"what if I'm not tied to tmux, what else can i use?"** (Line 222) -- Expanded to non-tmux tools: desktop apps, web UIs, CLI orchestrators, cloud solutions.

### Phase 3: The Needs Discovery Moment (Lines 383-394)

The real pivot came when Adam revealed his actual workflow:

> **"i have 4 cursor windows, each with 2-6 claude sessions"** (Line 383)

The assistant immediately recognized this changed the picture: "You're not looking for a tmux session manager -- you're already running 8-24 Claude sessions through Cursor." None of the researched tools were designed for Cursor's embedded sessions.

Adam clarified: **"they are not all running at once -- i keep context around"** (Line 388). He was using Cursor windows as persistent workspaces, not parallel execution.

Then the actual pain point crystallized:

> **"i need to monitor long-running operations better"** (Line 391)

And the critical detail: **"specifically i have cursor in terminal tabs"** (Line 394). These were CLI processes running in Cursor's integrated terminal, not Cursor's embedded agent sessions. This meant Claude Code hooks would work.

### Phase 4: Hooks Discovery and Scoping (Lines 395-442)

Adam asked **"which hooks?"** and the assistant mapped all 17 Claude Code hook events, narrowing to the 4 relevant ones: Stop, Notification, PostToolUseFailure, SessionEnd.

Adam caught the assistant dropping context: **"what happened to including the working directory in the notification? what about the claude session name?"** (Line 422). The assistant corrected course, incorporating `cwd` from hook JSON stdin.

Key discovery: Claude Code doesn't have named sessions -- only UUIDs. The directory basename was the best identifier available natively.

After a brief revisit of tmux integration options and agent-deck comparison, Adam asked: **"can any tool help me resume particular claude sessions after reboot?"** (Line 432). The answer was no -- and the assistant identified the gap nobody had filled: a tool that maps human-readable names to session IDs, persists the mapping, and restores tmux panes with `claude --resume <id>`.

### Phase 5: Planning (Lines 444-986)

Adam triggered `/aworkflows:plan` with **"make a plan to build it"**. Key discoveries during research:

- **Claude Code already has `/rename` and `--resume <name>`** -- the naming layer was built-in. This narrowed the scope from "build session naming" to "build a browser and restore tool."
- **283 sessions** in Adam's Strategy project alone, stored as JSONL at `~/.claude/projects/<url-encoded-path>/<uuid>.jsonl`
- **Existing hooks** (`SessionStart` and `PreCompact` running `bd prime`) gave a pattern to follow

### Phase 6: Deepen-Plan (Lines 1004-1458)

Adam ran `/aworkflows:deepen-plan` which launched 7 review agents (2 research, 4 review, 1 synthesis) plus a Gemini 3 red team. Key findings that changed the plan:

- Timeout units wrong (5000 ms vs 5 seconds)
- 3 shell injection vectors found and fixed
- `cs` name collision with claude-squad -- renamed to `csr`
- `realpath` portability concern (resolved: exists on this macOS)

### Phase 7: Implementation and Iteration (Lines 1475-end)

Implementation was attempted via `/compound-engineering:workflows:work` but context ran out. After compaction and session continuation, the tool was built. Post-implementation, Adam flagged: **"the notify-attention one is already annoying, since i can't identify which of my 20 terminal windows produced it"** (Line 1685).

This led to discovering that the hook JSON includes `transcript_path`, which points to the session JSONL file. The hooks were updated to grep the JSONL for the `custom-title` record (set by `/rename`) and include the session name in notifications.

Further discoveries during iteration:
- Auto-generated titles (from Claude Code's internal logic) are NOT stored in JSONL -- only `/rename` custom titles are
- Claude Code emits auto-generated titles as terminal escape sequences (visible in tmux tabs via oh-my-zsh's auto-title feature), but `/rename` custom titles are NOT emitted this way
- The terminal title chain: oh-my-zsh auto-title enabled (`DISABLE_AUTO_TITLE` commented out in `.zshrc`) + tmux `set-titles on` + `set-titles-string "#T"` = Claude's escape sequences show in tmux tabs

---

## 2. Tools and Projects Researched

### Tmux-Based Session Managers

| Tool | Stars | Language | Status | Why Considered | Verdict |
|------|------:|----------|--------|---------------|---------|
| **claude-squad** | 6,111 | Go | Stale (Dec 2025) | Most popular, Homebrew install, git worktrees | HN users called UX "clunky." AGPL license. Development stalled. Would be safest bet if maintenance resumes |
| **agent-deck** | 1,019 | Go | Very active | Prefixed tmux sessions (`agentdeck_*`), session forking, MCP management, tmux status bar notifications | "Strongest fit" for tmux users. Only 3 months old, no HN discussion. Stability issue reported (#4) |
| **Agent of Empires (AoE)** | 870 | Rust | Very active | Docker sandboxing (unique), 57 releases in 6 weeks | Runner-up. Even younger than agent-deck, 22 open issues |
| **NTM** | 152 | Go | Active (solo dev) | Named panes, broadcast to all agents, dashboard with token velocity | 2,250 commits from 1 person = red flag. Over-scoped |
| **Claudeman** | 106 | TypeScript | Active (solo dev) | Auto-compacts at 110k tokens, auto-clears at 140k, auto-respawns idle agents. 1,435 tests | Web-first (replaces tmux rather than integrating). Claude-only |
| **claude-tmux** | 27 | Rust | Dead (Jan 2026) | Detects Claude panes, shows working/idle/waiting status, fuzzy filtering | Dead project |
| **claunch** | 40 | Shell | Dead (Jun 2025) | Lightweight launcher | Dead project |

### Non-Tmux Orchestrators

| Tool | Stars | Language | What | Notes |
|------|------:|----------|------|-------|
| **ccmanager** | 881 | TypeScript | Supports 8 AI CLIs, copies session data to worktrees, devcontainer support | "Most practical" of CLI orchestrators. Best fit if staying in Cursor tabs |
| **claude-octopus** | 794 | Shell | Routes across Claude/Codex/Gemini, 75% consensus quality gate | Adversarial review mode interesting |
| **parallel-code** | 216 | TypeScript | Claude+Codex+Gemini side by side, QR code phone monitoring | By Super Productivity creator |
| **ccswarm** | 111 | Rust | Native PTY sessions, specialized agent pool (Frontend/Backend/DevOps/QA) | No tmux dependency |
| **herdctl** | 12 | TypeScript | "Kubernetes for Claude Code." YAML-defined fleets, scheduled agents, Discord integration | Ambitious but tiny adoption |

### Desktop Apps

| Tool | Stars | What | Notes |
|------|------:|------|-------|
| **Opcode** | 20,652 | Tauri desktop app, session timeline with checkpoints, branching, time-travel | Star count looks inflated relative to activity (last commit Oct 2025) |
| **CodePilot** | 2,128 | Electron + Next.js, uses Claude Agent SDK directly, SQLite persistence | Simpler and more honest about what it is |

### Web UIs / Monitoring

| Tool | Stars | What | Notes |
|------|------:|------|-------|
| **CloudCLI** | 6,529 | Session discovery, grouping, real-time streaming, mobile access | Standout for mobile monitoring |
| **KyleAMathews/claude-code-ui** | 363 | Kanban board monitoring, TODO/WIP/DONE columns | Watches session logs |
| **claude-code-monitor** | 188 | macOS-only, QR code for phone monitoring, AppleScript terminal control | Purpose-built for monitoring |

### Multi-Agent Orchestration (Different Category)

| Tool | Stars | What | Notes |
|------|------:|------|-------|
| **Gastown** (Steve Yegge) | 10,100 | Mayor/Rigs/Polecats hierarchy, 20-30 agents, git-backed state via beads | "$100/hour token burn rate at peak." Overkill. Uses same beads (`bd`) system Adam already runs. HN reception polarized |

### Notable Patterns (Not Full Tools)

| Pattern | Author | What |
|---------|--------|------|
| **Popup pattern** | Matsuyama | `tmux display-popup` with MD5-hashed directory as session name. Closing popup detaches, doesn't kill |
| **Auto-resume hook** | Erik Zaadi | `SessionEnd` hook saves session ID to `.claude_session` per directory. Shell wrapper auto-passes `--resume`. One session per directory only |
| **Notification system** | Quemy | Hooks `Stop` and `Notification`, enriches with tmux pane coordinates, routes through n8n to Gotify. Click notification jumps to right pane |

### Cloud / Zero-Setup

| Tool | What | Notes |
|------|------|-------|
| **Claude Code Web** (official) | Prefix `&` for parallel sessions, async -- close browser, come back later | Pro/Max plan required |
| **Ona** (formerly Gitpod) | Each agent gets own cloud container with full isolation | $20/mo |
| **Docker Sandboxes** | microVMs for running Claude unsupervised | Free (Docker Desktop) |

### The Gap None Filled

None of the 30+ tools solved the specific problem: resuming multiple named Claude sessions into tmux panes after reboot, with a human-readable interface for browsing sessions. The session managers create tmux sessions that resurrect can capture, but Claude Code conversation state is not auto-restorable by any tool.

---

## 3. Key Discoveries

### Claude Code Built-In Features (Not Widely Known)

1. **`/rename` command** exists inside Claude Code sessions. Sets a `custom-title` record in the session JSONL.
2. **`claude --resume <name>`** finds sessions by custom title, not just UUID. This was not obvious from `claude --help`.
3. **Sessions are JSONL files** at `~/.claude/projects/<url-encoded-path>/<uuid>.jsonl`. The path is URL-encoded (e.g., `-Users-adamf-Work-Strategy`).
4. **283 sessions** in Adam's Strategy project alone. Some files 6,700+ lines.
5. **`custom-title` appears multiple times per session** (on rename/compaction). Must deduplicate by sessionId, take most recent.

### Hook System Details

6. **Hook input comes via JSON on stdin**, not environment variables. Environment variables are documented but buggy (GitHub issue #9567).
7. **Timeout is in seconds, not milliseconds.** `"timeout": 5000` would be ~83 minutes. The plan originally had this wrong; every review agent caught it.
8. **Hook JSON includes `transcript_path`** -- discovered post-implementation when Adam complained about notification identity. Points to the session JSONL file, enabling session name lookup.
9. **Auto-generated titles are NOT stored in JSONL.** They live in Claude Code's internal state only. Only `/rename` custom titles are persisted to the JSONL.
10. **Claude Code emits auto-generated titles as terminal escape sequences** (captured by oh-my-zsh auto-title + tmux `set-titles`), but `/rename` custom titles are NOT emitted this way. Contradicts the earlier incorrect claim that Claude Code "doesn't emit title escape sequences."
11. **Hooks snapshot at session startup.** Edits mid-session require `/hooks` menu review.
12. **Matchers support pipe `|` as regex OR** since the matcher field is a full regex pattern.
13. **`Stop` hook fires every response turn**, not just on long autonomous completions. Cannot distinguish "finished 10-minute task" from "answered quick question." Too noisy for notifications.

### Shell/System Details

14. **macOS 26.3 has `/bin/realpath`** -- the Gemini red team flagged this as missing from stock macOS, but it exists on this machine.
15. **BSD `stat` syntax**: `stat -f %m` for epoch mtime (not GNU `stat -c %Y`).
16. **`cs` binary name collides with claude-squad** (which installs as `cs` to `~/.local/bin/`). Renamed to `csr`.

### Security Findings (3 Injection Vectors)

17. **osascript string interpolation** -- Untrusted JSON fields interpolated into AppleScript strings allow arbitrary command execution via `do shell script`. Fixed with environment variable passing: `NOTIF_BODY="$msg" osascript -e 'display notification (system attribute "NOTIF_BODY")...'`
18. **tmux `new-window` command string** -- Session names with single quotes break out of quoting in `/bin/sh -c`. Fixed with two-step pattern: `tmux new-window` (create) then `tmux send-keys` with `printf '%q'` escaping.
19. **`xargs basename` without `--`** -- Mishandles paths with special characters. Fixed with explicit delimiter handling.

---

## 4. Decision Points

### "Named session resume, lightweight" (Line 452)

The assistant presented two options: "Named session resume" (lightweight shell script) vs "Full session manager" (closer to agent-deck). Adam chose:

> **"Named session resume"** -- Map human-readable names to Claude session IDs. After reboot, restore named tmux panes with claude --resume. Hook-based, lightweight shell script.

### "combo of 1 and 3" for restore UX (Line 963)

When asked how `cs restore` should behave with 7+ sessions and no argument, Adam chose:

> **"combo of 1 and 3 -- show the list, with an option for all too"**

This was later cut during the deepen-plan phase. Two review agents flagged the interactive picker as disproportionate complexity for a personal tool. The simplicity reviewer noted: "requiring a name argument and using `cs list` to find it is simpler and sufficient." The non-interactive pattern matched the established `bd` CLI convention.

### "Separate scripts (Recommended)" for hook style (Line 963)

Asked whether hooks should be extracted into separate script files (like existing `statusline-command.sh`) or kept as inline JSON one-liners:

> **"Separate scripts (Recommended)"**

### "Notification + Failure only" for hook events (Line 966)

After the assistant explained that `Stop` fires every response turn (too noisy) and `Notification` fires on permission prompts (useful signal), Adam chose:

> **"Notification + Failure only"** -- Cleanest signal-to-noise ratio.

### "include it" for sanitize_tmux_name (Line 1427)

The assistant asked whether to keep or drop `sanitize_tmux_name()`. Options: "Drop it" (YAGNI) or "Keep it simple" (truncate to 30 chars). Adam chose neither option explicitly:

> **"include it"**

The function was kept in the implementation.

### Renaming from `cs` to `csr` (Line ~1389)

The architecture review agent discovered `cs` collides with claude-squad (established open-source tool installing to same path). The assistant renamed throughout the plan:

> Changed to `csr` (Claude Session Resume). No user pushback needed -- this was accepted as obvious.

### "use gemini 3" for red team (Line 1347)

The assistant initially tried to use PAL for the red team, but Adam stopped it and directed:

> **"use gemini 3"**

The Gemini 3 Pro red team caught the `realpath` portability issue and the hardcoded `/opt/homebrew/bin/jq` path.

### "just commit" for transfer strategy (Line 1464)

Asked whether to commit and push, Adam said: **"just commit"** -- local only, no push. The plan was self-contained and transferable to another machine.

---

## 5. Adam's Actual Workflow (Revealed Incrementally)

The session gradually revealed how Adam actually works:

1. **4 Cursor windows** -- each representing a project/context area
2. **2-6 Claude sessions per window** -- running in Cursor's integrated terminal tabs (CLI processes, not Cursor's embedded agent)
3. **~15 concurrent sessions total** -- not all active simultaneously, many holding context
4. **Same directory for many sessions** -- `~/Work/Strategy` has 283+ sessions, making `-c` (resume most recent) useless for specific sessions
5. **Long-running operations** -- kicks off a task in one tab, switches to another window, has no way to know when it's done or stuck
6. **Named sessions via `/rename`** -- uses names like "intellect," "cost-model," "Xiatech strategy"
7. **tmux-resurrect + tmux-continuum** set up but newly installed -- unclear how much value they add
8. **oh-my-zsh with auto-title enabled** -- `DISABLE_AUTO_TITLE` is commented out, so oh-my-zsh sets terminal titles to the running command. Combined with tmux `set-titles on`, this is how Claude's auto-generated session titles show in tmux tabs
9. **`~/.local/bin/` on PATH** -- standard location for personal scripts
10. **`jq` 1.8.1, tmux 3.6a** available -- no dependency concerns

### The Monitoring Pain Point

The core frustration: with 20 terminal tabs across 4 windows, a macOS notification saying "Strategy: Permission needed for Bash" gives no indication of *which* tab needs attention. After implementing the notification hooks, Adam immediately flagged this: **"the notify-attention one is already annoying, since i can't identify which of my 20 terminal windows produced it"** (Line 1685).

This led to the post-implementation improvement of grepping the session JSONL for the `/rename` custom title and including it in the notification body.

---

## 6. The "Needs Discovery" Moment

The session evolved through three false starts before reaching the real problem:

### False Start 1: "Tips for tmux + Claude" (Line 2)
The opening question implied a configuration/plugin problem. The assistant provided generic tmux advice. This was exploratory, not need-driven.

### False Start 2: "How do other people use tmux and Claude Code together?" (Line 22)
This triggered a massive ecosystem research phase (30+ tools). The implicit assumption was that the solution existed and just needed finding. It didn't.

### False Start 3: "Can agent-deck help?" (Lines 199-432)
Deep-diving specific tools, comparing features, checking HN reception. Still searching for an existing solution to a problem that hadn't been articulated.

### The Pivot: "i have 4 cursor windows, each with 2-6 claude sessions" (Line 383)

This was the first time Adam described his actual workflow. The assistant immediately recognized: "You're not looking for a tmux session manager." But the real need was still buried.

### The Crystallization: "i need to monitor long-running operations better" (Line 391)

One sentence. After 390 lines of research, the actual pain point was finally stated. The assistant connected it immediately: "You kick off a long task in one of your ~15 Cursor Claude sessions, switch to another window to keep working, and have no way to know when it's done or stuck waiting for input."

### The Final Clarification: "specifically i have cursor in terminal tabs" (Line 394)

This unlocked the solution. CLI processes in Cursor's terminal tabs are real PTY processes -- hooks work on them, monitoring tools can see them. The path from here to building `csr` + notification hooks was direct.

### Pattern

The session demonstrates a common need-discovery pattern: the user's opening question ("tips for tmux + Claude") was several abstraction layers above the actual pain point ("I can't tell which of my 20 terminal tabs needs attention"). It took ~40 minutes of research and exploration before the real problem surfaced through incremental self-disclosure:

1. General question (tips) --> abstract problem space
2. Research request (what exists?) --> assumes solution exists
3. Workflow reveal (4 Cursor windows, 15 sessions) --> context
4. Pain point (monitor long-running ops) --> actual need
5. Technical detail (cursor terminal tabs) --> actionable constraint

---

## 7. Session Flow Summary

| Phase | Lines | Duration Est. | What Happened |
|-------|-------|---------------|---------------|
| Tmux tips + hallucinated --name | 2-20 | ~5 min | Generic advice, corrected hallucination |
| Ecosystem research (3 rounds) | 22-222 | ~30 min | 30+ tools cataloged |
| "Not tied to tmux" expansion | 222-382 | ~15 min | Desktop apps, web UIs, orchestrators |
| **Needs discovery pivot** | 383-394 | ~2 min | Workflow revealed, pain point crystallized |
| Hooks exploration | 395-443 | ~10 min | 17 hook events mapped, notification design |
| Planning (/aworkflows:plan) | 444-998 | ~30 min | Research agents, specflow, plan written |
| Deepen-plan (7 agents + red team) | 1004-1458 | ~45 min | Security fixes, naming collision, timeout fix |
| Open items resolution | 1416-1464 | ~10 min | 10 items resolved, committed |
| Implementation (/aworkflows:work) | 1475-1487 | ~5 min | Context exhaustion, compaction |
| Post-compaction implementation | 1487-1680 | ~20 min | `csr` + hooks built and committed |
| Post-implementation iteration | 1680-1870 | ~20 min | Hook identity fix, auto-title discovery, v2 epic |
| Session close + handoff | 1870-1975 | ~10 min | Beads issues created, documentation request |

**Total estimated session time:** ~3.5 hours

---

## 8. What Was Built

### Files Created

1. **`~/.local/bin/csr`** (185 lines) -- List and restore named Claude sessions into tmux windows
   - `csr list [dir]` -- Scans JSONL files for `/rename`d sessions
   - `csr restore <name>` -- Opens tmux window and runs `claude --resume <name>`
   - `csr version` / `csr help`

2. **`~/.local/bin/notify-attention.sh`** (22 lines) -- macOS notification on Notification events (matcher: `permission_prompt`). Submarine sound. Includes session name via JSONL grep.

3. **`~/.local/bin/notify-error.sh`** (28 lines) -- macOS notification on PostToolUseFailure events. Basso sound. Skips `is_interrupt`. Includes session name.

4. **`~/.claude/settings.json`** -- Two hook entries added (preserving existing `SessionStart`/`PreCompact` hooks)

### Artifacts

- **Plan:** `docs/plans/2026-02-23-feat-claude-session-resume-tmux-plan.md` (status: completed)
- **Research:** `.workflows/plan-research/claude-session-resume/agents/` (3 files)
- **Reviews:** `.workflows/deepen-plan/feat-claude-session-resume-tmux/` (7 review files + 2 synthesis + 2 manifests)
- **Beads epic:** `Strategy-256` (csr v2 enhancements) with 5 children:
  - `Strategy-256.2` (P2) -- Notification improvements brainstorm
  - `Strategy-2l7` (P3) -- Tab-completion
  - `Strategy-k7n` (P3) -- fzf integration
  - `Strategy-256.1` (P4) -- `--json` output
  - `Strategy-cxx` (P4) -- Layout save/restore

### Commits

- `cd1c206` -- Plan + all research/review artifacts (Strategy repo)
- `55bb79f` -- Implementation (csr tool + notification hooks) (Strategy repo)

---

## 9. Post-Implementation Findings

These discoveries came from real usage after the tool was deployed, during the same session and a follow-up session on 2026-03-15.

### Notification Identity Problem

Within minutes of the hooks going live, Adam flagged: **"the notify-attention one is already annoying, since i can't identify which of my 20 terminal windows produced it."**

The original hooks showed `<directory>: <message>` (e.g., "Strategy: Permission needed for Bash"). With ~15 sessions in the same directory, this was useless.

**Fix:** We discovered the hook JSON includes `transcript_path` — the full path to the session's JSONL file. The hooks were updated to grep the JSONL for the `/rename` custom title and show it in the notification body. Unnamed sessions fall back to directory basename.

**Hook JSON fields available** (captured via debug dump):
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

### Terminal Title Behavior (Not What We Thought)

Early in the session, the assistant claimed Claude Code doesn't emit terminal title escape sequences. This was wrong. Claude Code DOES emit them — but the behavior differs between auto-generated and `/rename` titles:

| Title Type | Stored in JSONL | Emitted as terminal escape sequence | Shows in tmux tab |
|------------|:-:|:-:|:-:|
| Auto-generated (e.g., "terminal notification issues") | No | Yes | Yes |
| `/rename` custom title (e.g., "setup") | Yes (`custom-title` record) | No | No |

**Proof:** Adam `/rename`d a session to "setup" — the tmux tab continued showing "2.1.76" (the Claude Code version, which is the default terminal title). The auto-generated title for THIS session ("csr and claude notifications") DID show in the tab.

**The terminal title chain:**
1. Claude Code emits `\033]2;<title>\033\\` escape sequence with the auto-generated title
2. oh-my-zsh's auto-title is enabled (`DISABLE_AUTO_TITLE` is commented out in Adam's `.zshrc`)
3. tmux captures this as the pane title
4. `set-titles-string "#T"` displays it as the window/tab title
5. `pane-border-format "#{pane_title}"` shows it in pane borders

**Implication for notifications:** The hooks can only identify sessions that were `/rename`d (because that's what's in JSONL). The tmux tabs show auto-generated titles (because that's what's emitted as escape sequences). These are two different naming systems that don't talk to each other.

### Notifications: Functional but Unsatisfying

Adam's verdict after initial use: notifications work, but aren't good enough. Core issues:
1. **Identity problem** — even with `/rename` lookup, most sessions aren't renamed
2. **No click-to-focus** — macOS notification doesn't take you to the right terminal tab
3. **Sound fatigue** — Submarine/Basso on every permission prompt across 15+ sessions
4. **No grouping** — multiple sessions needing attention = multiple separate notifications

These are tracked in beads issue `Strategy-256.2` (P2, "Brainstorm: notification hook improvements") with a trigger: Adam's feedback after first real usage day.

### What JSONL Records Exist

Session JSONL files contain these record types (discovered by scanning with `jq`):
- `assistant` — Claude's responses
- `user` — User messages
- `system` — System prompts
- `progress` — Progress updates
- `file-history-snapshot` — File state captures
- `queue-operation` — Queue management
- `custom-title` — Set by `/rename` only

Notably absent: no record type for auto-generated titles. They exist only in Claude Code's runtime state.

---

## 10. Research Artifacts Index

All research artifacts are preserved in `docs/research/`:

### Plan Research (`docs/research/plan-research/`)
- `repo-research.md` — Shell conventions from existing scripts, beads CLI patterns
- `learnings.md` — Past solutions search (no prior art found)
- `specflow.md` — 25 gaps identified in initial plan (shell injection, timeout units, path edge cases)

### Deepen-Plan Run 1 (`docs/research/deepen-plan-run-1/`)
- `research--best-practices.md` — External best practices for shell tools and osascript
- `research--hooks-docs.md` — Claude Code hooks documentation analysis
- `review--architecture-strategist.md` — Architecture review (naming collision, async hooks, v2 roadmap)
- `review--code-simplicity.md` — Simplicity review (cut interactive mode, drop file size column)
- `review--pattern-recognition.md` — Pattern compliance (header blocks, variable naming, existing conventions)
- `review--security-sentinel.md` — Security review (3 injection vectors found and fixed)
- `red-team--critique.md` — Gemini 3 Pro red team (realpath portability, hardcoded jq path, TCC permissions)
- `run-1-synthesis.md` — Cross-agent synthesis with priority-ranked findings

### Synthesis (`docs/research/`)
- `synthesis.md` — Top-level synthesis document
