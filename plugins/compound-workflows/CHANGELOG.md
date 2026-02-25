# Changelog

All notable changes to this project will be documented in this file.

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

- **NOTICE file** with full MIT license text and attribution to Kieran Klaassen (forked from v2.35.2)

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

- **Acknowledgment:** Built on workflow patterns from Kieran Klaassen's compound engineering plugin (MIT)
