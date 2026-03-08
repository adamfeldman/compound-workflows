---
title: "Context-Lean Audit: Compound Workflows Plugin"
type: fix
status: active
date: 2026-03-08
---

# Context-Lean Audit: Compound Workflows Plugin

All compound skills and commands should minimize main context usage by dispatching work to subagents that persist outputs to disk. This audit reviews every command and skill for compliance.

## Audit Methodology

Every SKILL.md and command .md file was read in full. Each was evaluated on:

1. **Does it dispatch work to subagents?** (Agent/Task tool with `run_in_background`)
2. **Do agents write outputs to disk?** (OUTPUT INSTRUCTIONS block, `.workflows/` directories)
3. **Does the orchestrator avoid pulling full results into its own context?** (No TaskOutput calls, reads disk files only when synthesis is needed)
4. **Are MCP tool responses handled context-safely?** (Wrapped in subagents, not called directly from orchestrator)

---

## Commands (commands/compound/)

### compound:work — EXCELLENT

The gold standard for context-lean orchestration. The orchestrator *never* reads source files or writes code. Every implementation step is dispatched to an independent subagent. Recovery works via persistent state (beads/git/plan file checkboxes).

Key patterns:
- "Orchestrator never codes" rule (line 404)
- Each subagent gets a self-contained prompt with file paths to read (not inline content)
- Foreground dispatch by default (sequential safety), parallel only when files are disjoint
- Recovery after compaction via `bd ready` + `git log` + plan file — zero in-memory state dependency

**No changes needed.**

### compound:review — EXCELLENT

All 7+ review agents dispatched in parallel with disk-persist. Explicit rules: "Every agent writes to disk, returns only a summary" (line 38). Polls via `ls` for file existence, never calls TaskOutput. Synthesis reads from disk.

Key patterns:
- Standard OUTPUT INSTRUCTIONS block appended to every agent prompt
- Conditional agents (data-migration, frontend-races) only launched when PR matches criteria
- 3-minute timeout for stragglers — doesn't let one slow agent block everything

**No changes needed.**

### compound:deepen-plan — EXCELLENT (with one fix needed)

The most sophisticated disk-persist implementation. Batched agent dispatch (10-15 at a time), JSON manifest for tracking, numbered run directories for traceability, recovery protocol for interrupted runs.

Explicit rules:
- "NEVER call TaskOutput to retrieve full agent results" (line 528)
- "NEVER paste full plan content into your own context if you can give agents the file path" (line 529)
- Synthesis delegated to a dedicated subagent that reads all files from disk

**Fix needed: Red team MCP calls** (see Issue #1 below).

### compound:plan — GOOD

Research agents (repo-research-analyst, learnings-researcher, best-practices-researcher, framework-docs-researcher, spec-flow-analyzer) all properly dispatched with disk-persist pattern. Explicit: "DO NOT call TaskOutput to retrieve full results" (line 98).

Step 1.6 "Consolidate Research" reads research files from disk into the orchestrator's context. This is *necessary* — the orchestrator needs the research to write the plan. This is acceptable context usage: the orchestrator is consuming research to produce a deliverable, not passively holding agent transcripts.

**No changes needed.**

### compound:compound — GOOD

Phase 1 dispatches 5 research agents in parallel, all with OUTPUT INSTRUCTIONS blocks. Phase 3 dispatches up to 3 review agents. All disk-persisted. Monitors via file existence, not TaskOutput.

Phase 2 reads all agent output files to assemble the solution document — necessary for the deliverable.

**No changes needed.**

### compound:brainstorm — GOOD (with one fix needed)

Research phase properly dispatches repo-research-analyst and context-researcher with disk-persist. The Claude opus red team subagent correctly uses disk-persist.

**Fix needed: Red team MCP calls** (see Issue #1 below).

### compound:compact-prep — GOOD

Lightweight interactive checklist. No heavy research, no large data processing. Mostly AskUserQuestion calls and git/beads status checks. Subagent dispatch would add overhead without benefit here.

**No changes needed.**

---

## Skills (skills/)

### disk-persist-agents — EXCELLENT

The canonical pattern document. All other skills and commands reference this pattern. Clearly documents:
- The OUTPUT INSTRUCTIONS block template
- Batch dispatch strategy
- File existence monitoring (not TaskOutput)
- Retention policy

**No changes needed. This is the reference standard.**

### resolve-pr-parallel — BAD (fix needed)

Dispatches `pr-comment-resolver` agents in parallel (one per unresolved PR thread) but has **zero disk-persist discipline**. All agent results return directly to the orchestrator's main context. For a PR with 10+ comment threads, this means 10 full agent transcripts in the orchestrator's context window.

**Fix needed:** See Issue #2 below.

### orchestrating-swarms — NEEDS WORK (fix needed)

Comprehensive documentation of TeammateTool, Task system, backends, and orchestration patterns. However, all example patterns show teammates sending findings directly to the leader's inbox as full text. None of the patterns demonstrate the disk-persist approach for managing output volume.

This is problematic for the swarm patterns specifically — Pattern 3 (Self-Organizing Swarm) can have many workers all sending findings to the leader, filling the leader's context.

The skill already uses `disable-model-invocation: true` and `user-invocable: false` (it's reference material, not an executable command), so the impact is indirect — it influences how developers write swarm orchestration code.

**Fix needed:** See Issue #3 below.

### All other skills (13) — GOOD

These are either:
- **Reference/educational** (agent-native-architecture, create-agent-skills, brainstorming, compound-docs, frontend-design, agent-browser): Provide knowledge, not heavy processing
- **File-output focused** (file-todos, memory-management, setup): Outputs are files by nature
- **Interactive/lightweight** (document-review, git-worktree, gemini-imagegen, skill-creator): No multi-agent dispatch needed

**No changes needed for any of these.**

---

## Issues to Fix

### Issue #1: Red Team MCP Calls Leak Into Main Context

**Affects:** `compound:brainstorm` (Phase 3.5), `compound:deepen-plan` (Phase 4.5)

**Problem:** Both commands dispatch red team challenges via three providers: Gemini, OpenAI, and Claude. The Claude subagent correctly uses disk-persist (Task with OUTPUT INSTRUCTIONS). But the Gemini and OpenAI calls use `mcp__pal__clink` or `mcp__pal__chat` directly from the orchestrator, which means the full red team critique returns into the orchestrator's main context before being written to disk.

Current flow:
```
mcp__pal__clink: gemini ...  → FULL response in main context → write to disk (too late, context already consumed)
mcp__pal__clink: codex ...   → FULL response in main context → write to disk (too late)
Task (bg): opus ...          → writes to disk → 2-3 sentence summary only ✓
```

A red team critique can be 1,000-3,000 tokens. Two of them adds 2,000-6,000 tokens of transient content to the orchestrator's context for no reason — the orchestrator only needs the summary to triage findings.

**Fix:** Wrap all three red team providers in subagents. The subagent makes the MCP call, writes the response to disk, and returns only a summary. Subagents have `Tools: *` so they can call MCP tools.

Target flow:
```
Task (bg): "Call mcp__pal__clink gemini ... Write response to disk. Return summary." ✓
Task (bg): "Call mcp__pal__clink codex ...  Write response to disk. Return summary." ✓
Task (bg): "Read file, analyze. Write to disk. Return summary."                      ✓
```

**Files to modify:**
- [ ] `commands/compound/brainstorm.md` — Phase 3.5, Step 1 (all three providers)
- [ ] `commands/compound/deepen-plan.md` — Phase 4.5, Step 1 (all three providers)

**Implementation notes:**
- Each provider becomes a `Task general-purpose (run_in_background: true)` that:
  1. Detects CLI availability (same `which gemini`/`which codex` checks)
  2. Calls the appropriate MCP tool (`mcp__pal__clink` or `mcp__pal__chat`)
  3. Writes the response to the correct `.workflows/` path
  4. Returns a 2-3 sentence summary
- The runtime detection logic (`which gemini`, `which codex`, PAL availability) moves inside the subagent prompt since the subagent needs to make the decision
- The fallback logic (if PAL unavailable, run only Claude) stays in the orchestrator since it determines whether to launch the Gemini/OpenAI subagents at all
- All three can still launch in parallel from a single message

### Issue #2: resolve-pr-parallel Has No Disk-Persist Pattern

**Affects:** `skills/resolve-pr-parallel/SKILL.md`

**Problem:** The skill dispatches one `pr-comment-resolver` agent per unresolved PR thread, all in parallel. None of them write outputs to disk. All results return to the orchestrator's main context. For PRs with many comment threads (10+), this risks context exhaustion.

**Fix:** Add a disk-persist working directory and OUTPUT INSTRUCTIONS to each agent's prompt.

**Implementation:**
- [ ] Add working directory setup: `mkdir -p .workflows/resolve-pr/<pr-number>/agents/`
- [ ] Each `pr-comment-resolver` agent prompt gets the OUTPUT INSTRUCTIONS block:
  - Write findings/changes to `.workflows/resolve-pr/<pr-number>/agents/thread-<N>.md`
  - Return only: what was changed, which files, commit hash (2-3 sentences)
- [ ] Orchestrator reads output files from disk for the commit/resolve phase
- [ ] Add retention note (don't delete `.workflows/resolve-pr/` outputs)

**File to modify:**
- [ ] `skills/resolve-pr-parallel/SKILL.md`

### Issue #3: orchestrating-swarms Missing Disk-Persist Guidance

**Affects:** `skills/orchestrating-swarms/SKILL.md`

**Problem:** The skill documents 6 orchestration patterns. In all patterns, teammates send full findings to the leader's inbox as plain text messages. None demonstrate the disk-persist pattern for managing output volume when scaling to many agents.

This is especially relevant for:
- **Pattern 1 (Parallel Specialists):** 3 reviewers send full findings via inbox → leader reads all inline
- **Pattern 3 (Swarm):** N workers all send findings to team-lead → scales poorly
- **Workflow 1 (Full Code Review):** Multiple reviewers, all inbox-based

The inbox mechanism is fine for coordination messages (status, task claims, shutdown requests) but not for heavy analytical output.

**Fix:** Add a "Scaling Output: Disk-Persist Pattern" section that shows how to combine the TeammateTool inbox (for coordination) with disk persistence (for findings).

**Implementation:**
- [ ] Add new section after "Orchestration Patterns" (or as a subsection within it)
- [ ] Show the pattern: teammates write full findings to `.workflows/<team-name>/agents/<teammate-name>.md`, send only a summary via inbox message
- [ ] Provide a concrete example adapting Pattern 1 (Parallel Specialists) with disk-persist
- [ ] Reference the `disk-persist-agents` skill as the canonical pattern
- [ ] Note the threshold: disk-persist is recommended when teammates produce analytical output (findings, reviews, research) vs. just coordination messages

**File to modify:**
- [ ] `skills/orchestrating-swarms/SKILL.md`

---

## Summary

| Component | Rating | Fix? |
|-----------|--------|------|
| compound:work | EXCELLENT | No |
| compound:review | EXCELLENT | No |
| compound:deepen-plan | EXCELLENT* | Yes — Issue #1 (red team MCP) |
| compound:plan | GOOD | No |
| compound:compound | GOOD | No |
| compound:brainstorm | GOOD* | Yes — Issue #1 (red team MCP) |
| compound:compact-prep | GOOD | No |
| disk-persist-agents (skill) | EXCELLENT | No |
| resolve-pr-parallel (skill) | BAD | Yes — Issue #2 |
| orchestrating-swarms (skill) | NEEDS WORK | Yes — Issue #3 |
| 13 other skills | GOOD | No |

**Total files to modify: 4** (brainstorm.md, deepen-plan.md, resolve-pr-parallel/SKILL.md, orchestrating-swarms/SKILL.md)
