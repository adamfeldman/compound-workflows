# compound-workflows

Self-contained compound engineering workflows for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Fork of [Every's compound-engineering](https://github.com/EveryInc/compound-engineering-plugin) (February 2026) with 22 bundled agents, multi-model red team via [PAL](https://github.com/BeehiveInnovations/pal-mcp-server), and disk-persisted outputs.

## What's Different

| | compound-engineering | compound-workflows |
|---|---|---|
| Agents | Separate plugin dependency | 22 bundled (self-contained) |
| Red team | Single model | 3 providers in parallel via PAL (Gemini + OpenAI + Claude Opus) |
| Agent outputs | In-context (fills up) | Disk-persisted to `.workflows/` |
| Task tracking | TodoWrite only | Beads preferred, TodoWrite fallback |
| Config | Single file | Split: committed project + gitignored machine-specific |

## Install

```
/install adamfeldman/compound-workflows
```

Then run setup to detect your environment:

```
/compound:setup
```

> **Warning:** Do not install alongside compound-engineering. This plugin bundles all agents and skills. Installing both will cause agent name conflicts. Run `/compound:setup` to detect and resolve conflicts.

## Commands

| Command | Purpose |
|---------|---------|
| `/compound:setup` | Detect environment, configure directories, recommend enhancements |
| `/compound:brainstorm` | Explore requirements through collaborative dialogue |
| `/compound:plan` | Transform ideas into implementation plans with research agents |
| `/compound:deepen-plan` | Enhance plans with parallel research + red-team challenges |
| `/compound:work` | Execute plans via subagent dispatch with task tracking |
| `/compound:review` | Multi-agent code review with disk-persisted findings |
| `/compound:compound` | Document solved problems to build institutional knowledge |
| `/compound:compact-prep` | Pre-compaction checklist — save context before `/compact` |

### Workflow Cycle

```
brainstorm -> plan -> [deepen-plan] -> work -> review -> compound
```

Each step produces documents that feed the next. Solutions feed future brainstorms.

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

## Attribution

Includes agents and skills forked from [Every's compound engineering plugin](https://github.com/EveryInc/compound-engineering-plugin) (MIT). The brainstorm-plan-work-review-compound cycle, agent-based review architecture, and knowledge compounding philosophy originate from that project. See `NOTICE` and `FORK-MANIFEST.yaml` for provenance.

## License

[MIT](LICENSE)
