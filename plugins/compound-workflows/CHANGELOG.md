# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2026-02-25

### Added

- **8 commands:**
  - `/compound-workflows:setup` — Environment detection, enhancement recommendations, directory setup
  - `/compound-workflows:brainstorm` — Collaborative dialogue with PAL/Claude red-team challenge
  - `/compound-workflows:plan` — Disk-persisted research agents with brainstorm cross-check
  - `/compound-workflows:deepen-plan` — Multi-run plan enhancement with red-team + consensus
  - `/compound-workflows:work` — Plan execution with beads/TodoWrite task tracking
  - `/compound-workflows:work-agents` — Subagent dispatch architecture for large plans
  - `/compound-workflows:review` — Multi-agent code review with disk-persisted outputs
  - `/compound-workflows:compound` — Solution documentation with analytical/strategic mode

- **1 agent:**
  - `context-researcher` — Broad knowledge base search across 5 directories, tagged by source type

- **1 skill:**
  - `disk-persist-agents` — Reusable pattern for agents that write to disk instead of context

- **Graceful degradation:** All commands work without beads (TodoWrite fallback), PAL (Claude subagent fallback), or compound-engineering (general-purpose agent fallback)

- **Acknowledgment:** Built on workflow patterns from compound-engineering by Kieran Klaassen / Every (MIT)
