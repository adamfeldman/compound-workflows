# compound-workflows

Fork of [Every's compound-engineering](https://github.com/EveryInc/compound-engineering-plugin) for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Longer sessions without context exhaustion, session recovery when things go wrong, task tracking that survives compaction, multi-model red team ([PAL](https://github.com/BeehiveInnovations/pal-mcp-server) + Claude), fewer plan iterations, and memory that persists across sessions.

<p align="center">
  <img src="assets/workflow-cycle.svg" alt="The compound workflow cycle: brainstorm → plan → work → review → compound" width="600">
</p>

- [What is Compound Engineering?](#what-is-compound-engineering)
- [Why Fork?](#why-fork)
- [What's Different](#whats-different)
- [Install](#install)
- [Update](#update)
- [Commands](#commands)
- [Dependencies](#dependencies)
- [Key Concept: Disk-Persisted Agents](#key-concept-disk-persisted-agents)
- [Roadmap](#roadmap)
- [Attribution](#attribution)

## What is Compound Engineering?

[Compound engineering](https://every.to/guides/compound-engineering) is a methodology where each unit of engineering work makes subsequent units easier. You document solutions, capture decisions with their rationale, and build institutional knowledge that compounds over time.

**Compound workflows** generalize this idea beyond software engineering to all knowledge work — an opinionated way to use Claude Code for research, planning, decision-making, and implementation. The cycle remains the same: brainstorm → plan → work → review → compound.

The plugin captures best-practice patterns and makes them shareable, while remaining configurable to individual user preferences.

## Why Fork?

Ambitious tasks in Claude Code hit walls:

- **Context exhaustion** — Agent outputs fill up context and trigger compaction.
  → Agents write to disk and return summaries, so sessions last longer.
- **State loss** — Work progress disappears on compaction.
  → `/compact-prep` and `/recover` handle planned and unplanned session boundaries; [beads](https://github.com/steveyegge/beads) tracking survives across compactions.
- **Plan iteration overhead** — Plans require many rounds to reach quality.
  → Readiness checks and consolidation catch issues earlier, preventing the fix-introduces-new-bug cycle.
- **Single-model blind spots** — One model can't catch its own assumptions.
  → Red team challenges from multiple providers (Gemini, OpenAI, Claude) surface what a single model misses.
- **Knowledge loss** — Context learned in one session is gone in the next.
  → Tiered memory management promotes frequently-used knowledge to where it's auto-loaded.

## What's Different

| | compound-engineering | compound-workflows |
|---|---|---|
| Agent outputs | In-context (fills up) | Sessions last longer — agents write to disk, not context |
| Plan quality | Unbounded iteration | Plans reach quality faster — readiness checks and auto-consolidation catch issues early |
| Red team | Single model | 3 models in parallel surface what a single model misses |
| Task tracking | TodoWrite only | Survives compaction — beads preferred, TodoWrite fallback |
| Session recovery | Manual | `/do:compact-prep` (proactive) + `/recover` (reactive) |
| Memory management | None | What you learn in one session carries to the next (in progress) |
| Process analysis | None | See where your time goes and which tasks take longer than expected |

## Install

```
/plugin marketplace add adamfeldman/compound-workflows
/plugin install compound-workflows
```

> **Warning:** Do not install alongside compound-engineering. This plugin bundles all agents and skills. Installing both will cause agent name conflicts. Run `/do:setup` to detect and resolve conflicts.

Then run setup to detect your environment:

```
/do:setup
```

## Update

From your terminal:

```
claude plugin update compound-workflows@compound-workflows-marketplace
```

Or use the interactive `/plugin` menu inside Claude Code.

## Commands

| Command | Purpose |
|---------|---------|
| `/do:setup` | Detect environment, configure directories, recommend enhancements |
| `/do:brainstorm` | Explore requirements through collaborative dialogue |
| `/do:plan` | Transform ideas into implementation plans with research agents |
| `/do:deepen-plan` | Enhance plans with parallel multi-model research + red-team challenges |
| `/do:work` | Execute plans autonomously with progress tracking |
| `/do:review` | Multi-agent code review from multiple perspectives |
| `/do:compound` | Document solved problems to build institutional knowledge |
| `/do:compact-prep` | Save your work before compaction — checklist for memory, commits, and resume |
| `/do:abandon` | Session-end capture without resumption |
| `/compound-workflows:recover` | Recover context from dead/exhausted sessions via JSONL log parsing |

> `/compound:*` aliases still work during the v3.0 transition period.

### Workflow Cycle

```
brainstorm -> plan -> [deepen-plan] -> work -> review -> compound
```

Each step produces documents that feed the next. Solutions feed future brainstorms.

### Session Recovery

Context exhaustion is inevitable in long sessions. Two paths:

- **Proactive:** `/do:compact-prep` before `/compact` — saves memory, checks for uncommitted work, queues a resume task. Say "resume" after compaction.
- **Ending a session:** `/do:abandon` — captures memory, compounds learnings, commits, and pushes without queuing a resume task.
- **Reactive:** `/compound-workflows:recover` when a session dies without compaction — parses the JSONL session log, cross-references git/beads/.workflows/plan state to reconstruct progress and extract what would otherwise be lost.

## Dependencies

| Tool | Required? | What it enables |
|------|-----------|-----------------|
| [beads](https://github.com/steveyegge/beads) (`bd`) | Recommended | Compaction-safe task tracking |
| [PAL MCP](https://github.com/BeehiveInnovations/pal-mcp-server) | Optional | Multi-model red team — dispatches to Gemini, OpenAI, and other providers. Also supports file-aware review via Gemini CLI and Codex CLI. |
| GitHub CLI (`gh`) | Optional | PR creation in work/review |

Without beads: TodoWrite fallback (loses state on compaction). Without PAL: Claude-only subagent fallback (single model).

## Key Concept: Disk-Persisted Agents

Instead of agents returning full results into conversation context (which fills up and compacts), every agent writes findings to `.workflows/` and returns only a 2-3 sentence summary.

- **Context stays lean** — run 15+ agents without exhaustion
- **Research survives** — files persist across sessions and compactions
- **Traceability** — see exactly what informed each decision
- **Recovery** — disk files + beads = full recovery after compaction

## Stats & Analysis

The plugin automatically collects per-dispatch timing and token data across all
workflows. All data stays local on your machine in `.workflows/stats/` — nothing
is sent externally. This enables:

- **Estimation calibration** — compare estimated vs actual time, segmented by type,
  priority, scope, and size. Discover which kinds of work consistently blow estimates
  and apply correction factors.
- **Workflow-level timing** — see how long each workflow step takes you, so you
  know where your time goes.
- **Model routing** — see which steps need the most capable model and which can
  run cheaper, so you spend quota where it matters.
- **Velocity tracking** — beads/hour trend over time, correlated with workflow maturity.
- **Outcome correlation** — because beads track tangible goals, time and token data
  connects back to actual deliverables, not just activity.
- **Deep insights** — mine Claude Code's session logs to understand compaction overhead,
  quota consumption patterns, and what's actually driving cost.

Run `/compound-workflows:classify-stats` to add complexity labels to collected data.
`/do:analyze-stats` (coming soon) will run the full analysis and present findings interactively.

## Roadmap

| Priority | Feature | Description | Done | Next | Target |
|----------|---------|-------------|------|------|--------|
| P1 | Quota optimization | Sonnet for research agents, relay wrappers | Released | — | v2.0 |
| P1 | Per-agent token tracking | Stats capture across all workflows | Released | — | v2.3 |
| P1 | Sonnet work subagents | Route mechanical work steps to Sonnet, save quota for judgment | Data collected | Brainstorm | — |
| P1 | Harden commands for Sonnet | Structural robustness so cheaper models follow instructions | — | Brainstorm | — |
| P2 | Workflow prompt optimization | Extend compact-prep's batch pattern to `/do:work` — where 43% of confirmation wait time concentrates | Phase 5 data | Brainstorm | — |
| P2 | Session analysis phase 6 | Hook audit, classification analysis, cache cost splits, effort dimension | Phase 5 done | Plan | — |
| P1 | Memory skill integration | Memory management with cleanup emphasis | Plan | Deepen | — |
| P2 | Plugin handbook | User-facing docs: getting-started, commands, config, architecture | Brainstorm | Plan | — |
| P2 | Correction-capture skill | Guide turning one-time corrections into durable rules | — | Brainstorm | — |
| P3 | Red team model selection | Configurable model routing for multi-provider challenges | Brainstorm | Plan | — |
| P3 | `/do:analyze-stats` | Run analysis on collected data and present findings interactively | Script built | Skill wrapper | — |
| P3 | macOS notifications | Native alerts for permission prompts and tool failures | Built | Plugin-ize | — |
| P3 | Live estimation | Workflows show estimated time remaining as they progress | Data collected | Brainstorm | — |
| — | `/do:abandon` | Session-end capture without resumption | Released | — | v3.1 |

## Attribution

Includes agents and skills forked from [Every's compound engineering plugin](https://github.com/EveryInc/compound-engineering-plugin) (MIT). The brainstorm-plan-work-review-compound cycle, agent-based review architecture, and knowledge compounding philosophy originate from that project. See [`NOTICE`](plugins/compound-workflows/NOTICE) and [`FORK-MANIFEST.yaml`](plugins/compound-workflows/FORK-MANIFEST.yaml) for provenance.

## License

[MIT](LICENSE)
