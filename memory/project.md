# Project Context

## Overview
- Plugin: compound-workflows v1.6.0 (plugins/compound-workflows/)
- 22 agents, 15 skills, 9 commands under `/compound:*` namespace
- Forked from Every's compound-engineering (February 2026), fully self-contained
- GitHub repo: adamfeldman/compound-workflows (public)

## Architecture Decisions
- **Namespace `/compound:*`** not `/compound-workflows:*` — shorter to type
- **Config split into two files** — `compound-workflows.md` (committed, project: stack/agents/depth) + `compound-workflows.local.md` (gitignored, env: tracker/gh_cli). Separates shared project config from machine-specific env config. Red team prefs are runtime-detected, not stored (CLI availability is volatile).
- **Single work executor** — `/compound:work` IS the subagent architecture. No single-context executor exists. Main context runs out of context and never finishes; subagent overhead is minor.
- **`.workflows/` committed in user projects** (research traceability), gitignored in this plugin source repo

## Session Log Format
- Path: `~/.claude/projects/<path-with-dashes>/<session-id>.jsonl` (not hashed — path with `/` replaced by `-`)
- Entry types: progress, assistant, user, file-history-snapshot, queue-operation, system, custom-title, last-prompt
- System subtypes: turn_duration, compact_boundary, local_command
- compact_boundary entries have `compactMetadata: { trigger: "manual", preTokens: N }`
- Command detection: `isMeta: true` on user entries + `<command-name>` tags
