# compound-workflows

Context-safe compound engineering workflows for Claude Code. Enhanced versions of compound-engineering's workflow commands with disk-persisted agent outputs, beads/TodoWrite task tracking, multi-model red-team challenges, and a subagent dispatch architecture.

## What This Adds

| Feature | compound-engineering | compound-workflows |
|---------|---------------------|-------------------|
| Agent outputs | In context (fills up) | Disk-persisted (`.workflows/`) |
| Task tracking | TodoWrite (in-memory) | Beads preferred, TodoWrite fallback |
| Red-team challenges | None | PAL MCP (multi-model) or Claude subagent |
| Large plan execution | Single context | Subagent dispatch (`/compound-workflows:work-agents`) |
| Research traceability | Ephemeral | Retained across sessions |
| Phase gates | Informal | Enforced (open questions must be resolved/deferred) |
| Plan deepening | Single run | Multi-run with numbered directories |
| Knowledge search | `docs/solutions/` only | 5 directories, tagged by source type |

## Installation

```bash
# Add the marketplace
claude /install compound-workflows-marketplace

# Enable for your project
claude /plugin enable compound-workflows
```

Then run setup to detect your environment:

```
/compound-workflows:setup
```

## Commands

| Command | Description |
|---------|-------------|
| `/compound-workflows:setup` | Detect environment, recommend enhancements, configure directories |
| `/compound-workflows:brainstorm` | Explore requirements through collaborative dialogue |
| `/compound-workflows:plan` | Transform ideas into implementation plans with research agents |
| `/compound-workflows:deepen-plan` | Enhance plans with parallel research + red-team challenges |
| `/compound-workflows:work` | Execute plans with beads/TodoWrite tracking |
| `/compound-workflows:work-agents` | Execute large plans via subagent dispatch |
| `/compound-workflows:review` | Multi-agent code review with disk-persisted findings |
| `/compound-workflows:compound` | Document solved problems to build institutional knowledge |

## Workflow Cycle

```
brainstorm → plan → [deepen-plan] → work / work-agents → review → compound
    ↑                                                                  |
    └──────────────────────────────────────────────────────────────────┘
```

Each step produces documents that feed the next. Solutions feed future brainstorms.

## Dependencies

| Tool | Required? | What it enables |
|------|-----------|-----------------|
| **beads** (`bd`) | Recommended | Compaction-safe task tracking. Without it: TodoWrite fallback (loses state on compaction) |
| **PAL MCP** | Optional | Multi-model red-team challenges. Without it: Claude subagent fallback (single-model) |
| **compound-engineering** | Recommended | Specialized review/research agents. Without it: general-purpose fallback |
| **GitHub CLI** (`gh`) | Optional | PR creation in work/review commands |

Run `/compound-workflows:setup` to see what's installed and get instructions for anything missing.

## Directory Conventions

This plugin expects the following project structure:

```
your-project/
├── docs/
│   ├── brainstorms/     # Output from /compound-workflows:brainstorm
│   ├── plans/           # Output from /compound-workflows:plan
│   ├── solutions/       # Output from /compound-workflows:compound
│   └── decisions/       # Decision records (optional)
├── memory/              # Project memory files (optional)
├── Resources/           # Reference documents (optional)
└── .workflows/          # Working state for disk-persisted agents (gitignore this)
```

Run `/compound-workflows:setup` to create missing directories.

## Key Concept: Disk-Persisted Agents

The core innovation. Instead of agents returning full results into the conversation context (which fills up and compacts), every agent writes its complete findings to a file under `.workflows/` and returns only a 2-3 sentence summary. This means:

- **Context stays lean** — you can run 15+ agents without exhaustion
- **Research survives** — files persist across sessions and compactions
- **Traceability** — see exactly what informed each decision
- **Recovery** — if context compacts, `bd ready` + disk files = full recovery

See `skills/disk-persist-agents/SKILL.md` for the full pattern.

## Acknowledgments

This plugin builds on the workflow patterns established by [compound-engineering](https://github.com/EveryInc/compound-engineering-plugin) by Kieran Klaassen / Every. The brainstorm → plan → work → review → compound cycle, agent-based review architecture, and knowledge compounding philosophy originate from that project (MIT licensed).

compound-workflows extends this foundation with disk persistence, multi-model red-teaming, beads integration, and subagent dispatch — addressing context exhaustion and session continuity in long-running workflows.

## License

MIT
