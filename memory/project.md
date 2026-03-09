# Project Context

## Overview
- Plugin: compound-workflows v1.7.0 (plugins/compound-workflows/)
- Commands under `/compound:*`, skills under `/compound-workflows:*`
- Forked from Every's compound-engineering (February 2026), fully self-contained
- GitHub repo: adamfeldman/compound-workflows (public)
- Old personal commands archived to .archive/ (aworkflows/, compact-prep.md removed from ~/.claude/commands/)

## Architecture Decisions
- **Namespace `/compound:*`** not `/compound-workflows:*` — shorter to type, user found long prefix annoying. `/compound:compound` accepted despite redundancy.
- **Single work executor** — `/compound:work` IS the subagent architecture. No single-context executor exists. Main context runs out of context and never finishes; subagent overhead is minor.
- **`.workflows/` committed in user projects** (research traceability), gitignored in this plugin source repo
- **Deferring is OK** when user explicitly chooses it — the principle is "zero untriaged items" not "zero deferred items"

## Session Log Format
- Path: `~/.claude/projects/<path-with-dashes>/<session-id>.jsonl` (not hashed — path with `/` replaced by `-`)
- Entry types: progress, assistant, user, file-history-snapshot, queue-operation, system, custom-title, last-prompt
- System subtypes: turn_duration, compact_boundary, local_command
- compact_boundary entries have `compactMetadata: { trigger: "manual", preTokens: N }`
- Command detection: `isMeta: true` on user entries + `<command-name>` tags

## Critical Discoveries
- **Nested Task dispatch does NOT work** — subagents launched via Agent tool cannot themselves spawn further subagents (tested empirically). Any architecture assuming nested dispatch must use flat dispatch instead (command dispatches all, then dispatches aggregator).
- **Claude Code hooks cannot trigger slash commands** — hooks run bash commands, HTTP calls, or prompt/agent evaluations only. For QA enforcement, use PostToolUse on Bash: hook script checks if committed files include plugin dirs, runs Tier 1 bash scripts, surfaces findings via exit 2 stderr. Sentinel file `.workflows/.work-in-progress` suppresses during `/compound:work`.

## Completed Work
- **Plan readiness agents (v1.7.0)** — PR #1 merged (squash), v1.7.0 tagged + GitHub release created
  - 12 commits, 17 files, +1,674 lines
  - 7 new files: 3 shell scripts + lib.sh, semantic-checks.md, reviewer.md, consolidator.md
  - Plan: `docs/plans/2026-03-08-feat-plan-readiness-agents-plan.md` (completed)

## Completed Work (continued)
- **Context-lean enforcement + QA enhancement (v1.8.0)** — bead `bdr` closed. 12 commits, 17+ files. MCP wrapping, disk-persist, QA command, hook, sentinel, docs, rename, version bump.

## In-Progress Work
- **Finding resolution provenance** — brainstorm written, ready for `/compound:plan`
  - Brainstorm: `docs/brainstorms/2026-03-08-finding-resolution-provenance-brainstorm.md`
  - Bead: `compound-workflows-marketplace-emx` (P1, open)
- **Deepen-plan convergence guidance** — help user evaluate if another run is advisable
  - Brainstorm: `docs/brainstorms/2026-03-08-deepen-plan-convergence-brainstorm.md` (red team complete)
  - Bead: `compound-workflows-marketplace-ruh` (P1, open, blocked on bdr)
  - Key decisions: hybrid script+agent, bounded reads (current+prior run only), 4 recommendation states, soft round-count guardrails, anti-anchoring (read prior signals not prior recommendation)
- **Dependency chain (all unblocked):** emx → ruh → aig → h0g
