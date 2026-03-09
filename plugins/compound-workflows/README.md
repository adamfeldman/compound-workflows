# compound-workflows

Self-contained compound engineering workflows for Claude Code. 25 agents, 19 skills, and 8 commands with disk-persisted agent outputs, beads/TodoWrite task tracking, multi-model red-team challenges, and a subagent dispatch architecture.

- [What This Adds](#what-this-adds)
- [Installation](#installation)
- [Commands](#commands)
- [Workflow Cycle](#workflow-cycle)
- [Dependencies](#dependencies)
- [Directory Conventions](#directory-conventions)
- [Key Concept: Disk-Persisted Agents](#key-concept-disk-persisted-agents)
- [Session Recovery](#session-recovery)
- [Attribution](#attribution)

> **Warning:** Do not install alongside Every's compound engineering plugin. This plugin bundles all agents and skills and is fully self-contained. Installing both will cause agent name conflicts and unpredictable dispatch behavior. Run `/compound:setup` to detect and resolve conflicts.

## What This Adds

| Feature | Description |
|---------|-------------|
| Agent outputs | Disk-persisted to `.workflows/` (context stays lean) |
| Task tracking | Beads preferred, TodoWrite fallback |
| Red-team challenges | 3-provider parallel (Gemini + OpenAI + Claude Opus) |
| Large plan execution | Subagent dispatch (`/compound:work`) |
| Research traceability | Retained across sessions |
| Phase gates | Enforced (open questions must be resolved/deferred) |
| Plan deepening | Multi-run with numbered directories |
| Knowledge search | 5 directories, tagged by source type |
| Bundled agents | 25 specialized agents (research, review, workflow) |
| Bundled skills | 19 reusable patterns and reference materials |

## Installation

```
/plugin marketplace add adamfeldman/compound-workflows
/plugin install compound-workflows
```

Then run setup to detect your environment:

```
/compound:setup
```

## Commands

| Command | Description |
|---------|-------------|
| `/compound:setup` | Detect environment, recommend enhancements, configure directories |
| `/compound:brainstorm` | Explore requirements through collaborative dialogue |
| `/compound:plan` | Transform ideas into implementation plans with research agents |
| `/compound:deepen-plan` | Enhance plans with parallel research + red-team challenges |
| `/compound:work` | Execute plans via subagent dispatch with beads/TodoWrite tracking |
| `/compound:review` | Multi-agent code review with disk-persisted findings |
| `/compound:compound` | Document solved problems to build institutional knowledge |
| `/compound:compact-prep` | Pre-compaction checklist — save memory, compound, commit, queue resume task |
| `/compound-workflows:recover` | Recover context from dead/exhausted sessions — parse JSONL logs, cross-reference state |

## Workflow Cycle

```
brainstorm -> plan -> [deepen-plan] -> work -> review -> compound
    |                                                          |
    +----------------------------------------------------------+
```

Each step produces documents that feed the next. Solutions feed future brainstorms.

## Dependencies

| Tool | Required? | What it enables |
|------|-----------|-----------------|
| **beads** (`bd`) | Recommended | Compaction-safe task tracking. Without it: TodoWrite fallback (loses state on compaction) |
| **PAL MCP** | Optional | Multi-model red-team challenges. Without it: Claude subagent fallback (single-model) |
| **GitHub CLI** (`gh`) | Optional | PR creation in work/review commands |

Run `/compound:setup` to see what's installed and get instructions for anything missing.

## Directory Conventions

This plugin expects the following project structure:

```
your-project/
+-- docs/
|   +-- brainstorms/     # Output from /compound:brainstorm
|   +-- plans/           # Output from /compound:plan
|   +-- solutions/       # Output from /compound:compound
|   +-- decisions/       # Decision records (optional)
+-- memory/              # Project memory files (optional)
+-- resources/           # External reference material (optional)
+-- .workflows/          # Disk-persisted agent outputs (recommend committing for traceability)
```

Run `/compound:setup` to create missing directories.

## Key Concept: Disk-Persisted Agents

The core innovation. This plugin follows the **context-lean** principle: instead of agents returning full results into the conversation context (which fills up and compacts), every agent writes its complete findings to a file under `.workflows/` and returns only a 2-3 sentence summary. This means:

- **Context stays lean** -- you can run 15+ agents without exhaustion
- **Research survives** -- files persist across sessions and compactions
- **Traceability** -- see exactly what informed each decision
- **Recovery** -- if context compacts, `bd ready` + disk files = full recovery

See `skills/disk-persist-agents/SKILL.md` for the full pattern.

## Session Recovery

Context exhaustion is inevitable in long sessions. compound-workflows handles this two ways:

**Proactive: `/compound:compact-prep`** — Run before `/compact` to save session state. Updates memory files, checks for uncommitted work, offers to compound learnings, and queues a resume task. After compaction, say "resume" to pick up where you left off.

**Reactive: `/compound-workflows:recover`** — When a session dies without compaction (context exhaustion, crash, forgot to compact). Parses the JSONL session log, cross-references git history, beads state, `.workflows/` artifacts, and plan files to reconstruct what happened and what's left to do. Extracts memory-worthy content that would otherwise be lost.

**Why recovery works:** Disk-persisted agent outputs survive in `.workflows/`. Beads issues survive in `.beads/`. Plan checkboxes track progress in `docs/plans/`. Git commits are durable. The only thing lost on context exhaustion is conversation history — and `/compound-workflows:recover` reconstructs that from the JSONL log.

## Attribution

This plugin includes agents and skills forked from Every's compound engineering plugin (MIT licensed). The brainstorm, plan, work, review, and compound cycle, agent-based review architecture, and knowledge compounding philosophy originate from that project.

compound-workflows extends this foundation with disk persistence, multi-model red-teaming, beads integration, subagent dispatch, and self-contained bundling of all agents and skills. See `NOTICE` for full license text and `FORK-MANIFEST.yaml` for per-file provenance.

## License

MIT
