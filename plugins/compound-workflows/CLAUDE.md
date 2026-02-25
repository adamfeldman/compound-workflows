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
└── workflow/     # Workflow utility agents (3)

commands/
└── compound/ # All slash commands (namespaced, 7 commands)

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
├── orchestrating-swarms/    # Multi-agent orchestration patterns
├── resolve-pr-parallel/     # Parallel PR comment resolution
├── setup/                   # Setup configuration reference (disable-model-invocation)
└── skill-creator/           # Skill packaging scripts
```

## Agent Registry

All 22 agents with their categories, command references, and model configuration.

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
| spec-flow-analyzer | workflow | plan | inherit |

**Model column key:** `haiku` = cost-optimized for well-scoped tasks (Haiku model). `inherit` = uses the default model from the calling context. Override in agent YAML frontmatter if needed.

**Standalone agents** are not dispatched by any command directly but are available for manual Task dispatch or dynamic discovery by deepen-plan.

## Setup Command/Skill Split

The setup command and setup skill coexist with distinct roles:

- **Command** (`commands/compound/setup.md`): The interactive entry point invoked via `/compound:setup`. Handles the UX flow (AskUserQuestion), environment detection, and config writing.
- **Skill** (`skills/setup/SKILL.md`): Reference material with `disable-model-invocation: true`. Provides the "what to configure" knowledge -- stack detection logic, agent lists, depth options.

The setup command handles the interactive UX flow. The setup skill (with disable-model-invocation: true) provides reference knowledge. The command was written by reading the skill at fork time -- it does not load the skill at runtime. If the skill is updated, the command must be manually synced.

## Config Schema (compound-workflows.local.md)

Written by `/compound:setup`. Consumers:
- `review.md` reads: review_agents, red_team, gh_cli
- `plan.md` reads: plan_review_agents, depth
- `deepen-plan.md` reads: red_team
- `work.md` reads: tracker
- `setup.md` writes all keys

## Command Conventions

- All commands use `compound:` prefix in YAML `name:` field
- Commands reference agents by name with inline role descriptions for graceful fallback
- Commands detect beads/PAL at runtime and adapt behavior
- Phase gates enforce resolution of open questions before proceeding
- Research outputs persist to `.workflows/` directories

## Testing Changes

1. Install the plugin in a test project
2. Run `/compound:setup` to verify detection
3. Test each modified command end-to-end
4. Verify graceful degradation without beads/PAL
