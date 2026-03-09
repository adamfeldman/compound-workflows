# Compound Workflows Plugin Development

## Versioning

Every change MUST update all three files:

1. **`.claude-plugin/plugin.json`** -- Bump version (semver)
2. **`CHANGELOG.md`** -- Document changes
3. **`README.md`** -- Verify component counts and tables

### Version Rules

- **MAJOR** (2.0.0): Breaking changes to command interfaces or directory conventions
- **MINOR** (1.1.0): New commands, agents, or skills
- **PATCH** (1.0.1): Bug fixes, doc updates, prompt improvements

Also update the marketplace.json version at the repo root.

## Directory Structure

```
agents/
├── research/     # Research and knowledge agents (6)
├── review/       # Code review agents (13)
└── workflow/     # Workflow utility agents (5)
    └── plan-checks/  # 3 shell scripts + 1 agent-format .md file (check modules, not standalone agents)

commands/
└── compound/ # All slash commands (namespaced, 10 commands)

scripts/
└── plugin-qa/               # 4 bash scripts + lib.sh — serves both the QA command and the PostToolUse hook

skills/
├── agent-browser/           # Browser automation for agents
├── agent-native-architecture/ # Architecture patterns reference (15 files)
├── brainstorming/           # Brainstorm methodology reference
├── compound-docs/           # Solution documentation schema and templates
├── create-agent-skills/     # Agent and skill creation workflows
├── disk-persist-agents/     # Reusable disk-persistence pattern
├── document-review/         # Document review methodology
├── file-todos/              # TODO tracking patterns
├── frontend-design/         # Frontend design patterns
├── gemini-imagegen/         # Gemini image generation scripts
├── git-worktree/            # Git worktree management scripts
├── memory-management/       # Auto-memory file management
├── orchestrating-swarms/    # Multi-agent orchestration patterns
├── resolve-pr-parallel/     # Parallel PR comment resolution
├── setup/                   # Setup configuration reference (disable-model-invocation)
└── skill-creator/           # Skill packaging scripts
```

## Agent Registry

All 24 agents with their categories, command references, and model configuration.

| Agent | Category | Dispatched By | Model |
|-------|----------|---------------|-------|
| best-practices-researcher | research | plan, setup | inherit |
| context-researcher | research | brainstorm | haiku |
| framework-docs-researcher | research | plan, setup | inherit |
| git-history-analyzer | research | (standalone) | inherit |
| learnings-researcher | research | plan | haiku |
| repo-research-analyst | research | brainstorm, plan, setup | inherit |
| agent-native-reviewer | review | review | inherit |
| architecture-strategist | review | review, setup | inherit |
| code-simplicity-reviewer | review | review, setup, work | inherit |
| data-integrity-guardian | review | compound | inherit |
| data-migration-expert | review | review | inherit |
| deployment-verification-agent | review | review | inherit |
| frontend-races-reviewer | review | review | inherit |
| pattern-recognition-specialist | review | review | inherit |
| performance-oracle | review | compound, review, setup | inherit |
| python-reviewer | review | setup | inherit |
| schema-drift-detector | review | (standalone) | inherit |
| security-sentinel | review | compound, deepen-plan, review, setup | inherit |
| typescript-reviewer | review | review, setup | inherit |
| bug-reproduction-validator | workflow | (standalone) | inherit |
| pr-comment-resolver | workflow | (standalone) | inherit |
| plan-consolidator | workflow | plan, deepen-plan | inherit |
| plan-readiness-reviewer | workflow | plan, deepen-plan | inherit |
| spec-flow-analyzer | workflow | plan | inherit |

**Model column key:** `haiku` = cost-optimized for well-scoped tasks (Haiku model). `inherit` = uses the default model from the calling context. Override in agent YAML frontmatter if needed.

**Standalone agents** are not dispatched by any command directly but are available for manual Task dispatch or dynamic discovery by deepen-plan.

All agents expect callers to include OUTPUT INSTRUCTIONS per the `disk-persist-agents` skill. See Context-Lean Convention below.

## Setup Command/Skill Split

The setup command and setup skill coexist with distinct roles:

- **Command** (`commands/compound/setup.md`): The interactive entry point invoked via `/compound:setup`. Handles the UX flow (AskUserQuestion), environment detection, and config writing.
- **Skill** (`skills/setup/SKILL.md`): Reference material with `disable-model-invocation: true`. Provides the "what to configure" knowledge -- stack detection logic, agent lists, depth options.

The setup command handles the interactive UX flow. The setup skill (with disable-model-invocation: true) provides reference knowledge. The command was written by reading the skill at fork time -- it does not load the skill at runtime. If the skill is updated, the command must be manually synced.

## Config Files

Written by `/compound:setup`. Two files:

### `compound-workflows.md` (committed, shared)

Project-level settings shared across team members.
- `review.md` reads: review_agents
- `plan.md` reads: plan_review_agents, depth, plan_readiness_* (under `## Plan Readiness` heading)
- `deepen-plan.md` reads: plan_readiness_* (under `## Plan Readiness` heading)
- `review.md` reads: depth

Keys: stack, review_agents, plan_review_agents, depth, plan_readiness_skip_checks, plan_readiness_provenance_expiry_days, plan_readiness_verification_source_policy, Workflow Instructions section (plugin-specific overrides like red team focus areas, domain constraints, review emphasis).

### `compound-workflows.local.md` (gitignored, per-machine)

Machine-specific environment detection.
- `work.md` reads: tracker
- `review.md` reads: gh_cli

Keys: tracker, gh_cli.

### Red team dispatch (runtime, not stored)

Red team provider preferences are detected each session, not stored in config. CLI availability varies by machine and may change. Detection order:
1. Check `which gemini` / `which codex` for CLI availability
2. Check if PAL MCP tools are available
3. If multiple options exist for a provider, ask user once per session
4. Fallback: Claude-only Task subagent

## Command Conventions

- All commands use `compound:` prefix in YAML `name:` field
- Commands reference agents by name with inline role descriptions for graceful fallback
- Commands detect beads/PAL/CLI availability at runtime and adapt behavior
- Phase gates enforce resolution of open questions before proceeding
- Research outputs persist to `.workflows/` directories
- `/compound:recover` is the reactive counterpart to `/compound:compact-prep` — it recovers context from dead/exhausted sessions by parsing JSONL logs and cross-referencing external state. It does not dispatch any agents from the agent registry.

## Context-Lean Convention

**"Context-lean"** is the canonical design principle for this plugin: orchestrator commands dispatch agents that write complete outputs to disk and return only brief summaries, keeping the parent context small enough to avoid compaction.

> Some command file subtitles use "context-safe" — this is the same principle, renamed for clarity.

### Rules

1. **All commands dispatching agents MUST include OUTPUT INSTRUCTIONS blocks.** Two variants exist:
   - **Relay variant** (MCP dispatch agents): "Write the response faithfully" wording — the agent relays an external tool's output to disk without interpreting it.
   - **Analysis variant** (research/review agents): "Write your COMPLETE findings" wording — the agent performs analysis and writes its own conclusions.

2. **TaskOutput is banned.** Never use TaskOutput to retrieve full agent results into the orchestrator context. Instead, poll for file existence (`ls .workflows/...`) to detect completion.

3. **MCP tool responses must be wrapped in Task subagents.** Any MCP tool that returns large content (context7 docs, web fetches, etc.) must be called from within a Task subagent that writes the response to disk. The orchestrator never receives the raw MCP response.

4. **Zero exceptions policy.** If a future command legitimately needs MCP responses in orchestrator context for routing/triage decisions, add a documented exception at that time with rationale. Currently: zero exceptions.

See `skills/disk-persist-agents/SKILL.md` for the canonical pattern and output instruction templates.

## Testing Changes

1. Install the plugin in a test project
2. Run `/compound:setup` to verify detection
3. Test each modified command end-to-end
4. Verify graceful degradation without beads/PAL
