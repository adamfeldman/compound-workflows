# Changelog

All notable changes to this project will be documented in this file.

## [1.4.3] - 2026-03-07

### Added

- **Setup tutorial walkthrough** — Step 6 now explains the full project structure (docs/, resources/, memory/, .workflows/), the workflow cycle (brainstorm → plan → work → review → compound), and the `/compound:` command shorthand via AskUserQuestion
- **`resources/` directory** created by `/compound:setup` — for external reference material (API docs, specs, research papers). Searched recursively by context-researcher.

### Changed

- **`Resources/` → `resources/`** — lowercase, consistent with other directories. Updated in context-researcher, brainstorm, and plugin README.
- **context-researcher genericized** — removed project-specific descriptions and examples leaked from fork source

## [1.4.2] - 2026-03-07

### Changed

- **7 reference-only skills hidden from command palette** — added `user-invocable: false` to compound-docs, setup, brainstorming, disk-persist-agents, document-review, orchestrating-swarms, and agent-native-architecture. These are reference materials loaded by commands, not standalone workflows.

## [1.4.1] - 2026-03-07

### Added

- **Git repo prerequisite check** in `/compound:setup` — fails fast if not in a git repo (worktrees, diffs, commits depend on it)
- **Beads initialization offer** in `/compound:setup` — if `bd` is installed but not initialized in the project, offers to run `bd init`

### Fixed

- **Attribution** — copyright holder corrected to Every (matches upstream LICENSE), upstream URL fixed to EveryInc/compound-engineering-plugin
- **Hallucinated fork version** `v2.35.2` removed — no such upstream release exists
- **PAL MCP link** corrected to BeehiveInnovations/pal-mcp-server
- **Beads link** corrected to steveyegge/beads

## [1.4.0] - 2026-03-07

### Added

- **`clink` support for red team reviews** — Gemini CLI and Codex CLI can now be used as red team providers via PAL `clink`, giving models direct file access in the repo for richer analysis. Falls back to `pal chat` or Claude-only if CLIs aren't available.
- **Gemini CLI and Codex CLI detection** in `/compound:setup` — detects installed CLIs, guides users through one-time per-repo file access permission grant
- **Full TodoWrite fallback in `/compound:work`** — TodoWrite mode blocks at all divergence points: worktree setup, issue creation, dispatch loop, result handling, recovery, quality check, and worktree cleanup. Previously only detection at the top with a "mentally replace" instruction.
- **Full Task dispatch syntax in `/compound:compound`** — all 8 agent dispatches (5 Phase 1 + 3 Phase 3) now have complete `Task` blocks with inline role descriptions. Previously agents 2-5 were shorthand references.
- **AGENTS.md** — project-specific agent instructions with reusable QA process (4 parallel checks covering all 8 commands, stale references, and CLAUDE.md consistency)

### Changed

- **Config split into two files** — `compound-workflows.md` (committed, shared project config: stack, agents, depth) and `compound-workflows.local.md` (gitignored, per-machine: tracker, gh_cli). Previously a single `compound-workflows.local.md` held everything.
- **Red team providers run independently in parallel** — all three providers (Gemini, OpenAI, Claude Opus) now review independently with no provider reading another's critique. Previously sequential (Gemini first, then OpenAI/Opus reading prior critiques). Rationale: reading prior critiques anchors models and reduces independent insight; deduplication happens at triage.
- **Red team provider preference is runtime-detected** — CLI and PAL availability checked each session, user asked to choose if multiple options exist. Previously stored in config (went stale across machines).
- **PAL write-to-disk made explicit** — PAL `chat` and `clink` responses now have explicit "After receiving the response, write it to: [path]" instructions. PAL returns strings, doesn't write files.
- **AskUserQuestion consistency** across all 8 commands — every user decision point now explicitly specifies AskUserQuestion. Fixed ~12 instances of "ask the user" or "suggest" without the tool name.
- **Conditional review agents** in `/compound:review` now have explicit `(run_in_background: true)` and `[disk-write for:]` instructions, matching the standard agent format
- **Batch-accept paths** in `/compound:deepen-plan` now prompt for user reasoning, consistent with "record the why" principle

### Fixed

- **`bd sync --flush-only` removed from `/compound:work`** — nonexistent command (same fix previously applied to compact-prep)
- **Phase 4 step numbering** in `/compound:work` — was 1,2,3,5,6,7; now sequential 1-6
- **`/resolve_todo_parallel`** reference removed from `/compound:review` — command doesn't exist in plugin
- **`/test-browser` and `/xcode-test`** references removed from `/compound:review` — replaced with generic test guidance
- **`/resolve_todo_parallel`** reference removed from `skills/file-todos/SKILL.md`
- **Hardcoded date** `2026-02-23` removed from `/compound:review` example
- **"work skill"** → "`/compound:work` command" in `/compound:deepen-plan`

## [1.3.0] - 2026-03-07

### Added

- **`/compound:compact-prep` command** — Pre-compaction checklist that preserves session context: memory update, beads sync, compound check (before compaction), dual commit checks, and post-compaction task queuing
- **Rationale-capture instructions** in brainstorm, plan, and deepen-plan — commands now record *why* the user made decisions, not just what they decided. User reasoning evaporates with conversation context; documents are the only durable record.
- **Work-readiness guidance** in plan and deepen-plan handoffs — assess step sizing for subagent dispatch, flag oversized steps, identify parallelism opportunities
- **Zero untriaged items principle** across brainstorm, plan, and deepen-plan — every finding, question, or concern must be explicitly resolved, deferred by the user, or removed before handoff. Nothing silently applied, nothing accidentally skipped.
- **Red team model examples** — specific model recommendations: Gemini 3.1 Pro Preview, GPT 5.4 Pro, Claude Opus via Task subagent

### Changed

- **Consolidated triage in deepen-plan** — synthesis findings AND red team findings now go through the same triage flow. Previously synthesis findings were silently written into the plan without user review.
- **AskUserQuestion in compact-prep** — compound check now uses structured options instead of waiting for free text
- **Setup creates `.workflows/` directory** and warns if it's gitignored — recommends committing for research traceability
- **README `.workflows/` guidance** — changed from "gitignore this" to "recommend committing for traceability"
- **Smoke test plan** — updated to 13 tests covering all 8 commands, fixed duplicate test numbering

## [1.2.0] - 2026-02-25

### Changed

- **Command namespace shortened** from verbose prefix to `compound:*` across all 7 commands
  - `/compound:brainstorm`, `/compound:plan`, `/compound:work`, `/compound:review`, `/compound:compound`, `/compound:deepen-plan`, `/compound:setup`
  - Shorter prefix improves UX -- easier to type and remember
  - Plugin name (`compound-workflows`) and config file (`compound-workflows.local.md`) unchanged
- **Commands directory renamed:** `commands/compound-workflows/` to `commands/compound/`

## [1.1.0] - 2026-02-25

### Added

- **21 new agents** (6 research, 13 review, 3 workflow) -- 22 total with existing context-researcher
  - Research (5 new): best-practices-researcher, framework-docs-researcher, git-history-analyzer, learnings-researcher, repo-research-analyst
  - Review (13 new): agent-native-reviewer, architecture-strategist, code-simplicity-reviewer, data-integrity-guardian, data-migration-expert, deployment-verification-agent, frontend-races-reviewer, pattern-recognition-specialist, performance-oracle, python-reviewer, schema-drift-detector, security-sentinel, typescript-reviewer
  - Workflow (3 new): bug-reproduction-validator, pr-comment-resolver, spec-flow-analyzer

- **14 new skills** (5 command-referenced + 9 utility) -- 15 total with existing disk-persist-agents
  - Command-referenced: brainstorming, compound-docs, orchestrating-swarms, resolve-pr-parallel, setup
  - Utility: agent-browser, agent-native-architecture, create-agent-skills, document-review, file-todos, frontend-design, gemini-imagegen, git-worktree, skill-creator

- **NOTICE file** with full MIT license text and attribution to Every

- **FORK-MANIFEST.yaml** tracking per-file provenance from the upstream source plugin

### Changed

- **3 agents renamed/depersonalized:** kieran-typescript-reviewer -> typescript-reviewer, kieran-python-reviewer -> python-reviewer, julik-frontend-races-reviewer -> frontend-races-reviewer

- **7 commands updated** for self-contained plugin:
  - work-agents.md merged into work.md (subagent dispatch is now the default mode)
  - setup.md fully rewritten -- detects bundled agents, warns on upstream plugin conflict
  - deepen-plan.md discovery logic rewritten for generic plugin agent discovery
  - brainstorm.md and deepen-plan.md red team methodology upgraded to 3-provider parallel (Gemini + OpenAI + Claude Opus)
  - brainstorm.md and deepen-plan.md MINOR severity surfacing added
  - plan.md, compound.md, review.md genericized (examples updated, agent names updated)

- **Plugin is now fully self-contained** -- upstream source plugin no longer needed as a dependency

### Removed

- Upstream source plugin listed as "Recommended" dependency (superseded by bundled agents)

## [1.0.0] - 2026-02-25

### Added

- **7 commands:**
  - `/compound:setup` -- Environment detection, enhancement recommendations, directory setup
  - `/compound:brainstorm` -- Collaborative dialogue with PAL/Claude red-team challenge
  - `/compound:plan` -- Disk-persisted research agents with brainstorm cross-check
  - `/compound:deepen-plan` -- Multi-run plan enhancement with red-team + consensus
  - `/compound:work` -- Subagent dispatch plan execution with beads/TodoWrite task tracking
  - `/compound:review` -- Multi-agent code review with disk-persisted outputs
  - `/compound:compound` -- Solution documentation with analytical/strategic mode

- **1 agent:**
  - `context-researcher` -- Broad knowledge base search across 5 directories, tagged by source type

- **1 skill:**
  - `disk-persist-agents` -- Reusable pattern for agents that write to disk instead of context

- **Graceful degradation:** All commands work without beads (TodoWrite fallback), PAL (Claude subagent fallback), or bundled agents (general-purpose agent fallback)

- **Acknowledgment:** Built on workflow patterns from Every's compound engineering plugin (MIT)
