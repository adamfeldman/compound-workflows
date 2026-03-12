# Compound Workflows Plugin Development

## Versioning

Every change MUST update all four files:

1. **`.claude-plugin/plugin.json`** -- Bump version (semver)
2. **`CHANGELOG.md`** -- Document changes
3. **`README.md`** -- Verify component counts and tables
4. **`.claude-plugin/marketplace.json`** (repo root) -- Bump version

### Version Rules

- **MAJOR** (2.0.0): Breaking changes to command interfaces or directory conventions
- **MINOR** (1.1.0): New commands, agents, or skills
- **PATCH** (1.0.1): Bug fixes, doc updates, prompt improvements

## Directory Structure

```
agents/
├── research/     # Research and knowledge agents (6)
├── review/       # Code review agents (13)
└── workflow/     # Workflow utility agents (7)
    └── plan-checks/  # 4 shell scripts + 1 agent-format .md file (check modules, not standalone agents)

commands/
└── compound/ # Thin aliases redirecting to /do:* skills (8 commands, backwards compat)

scripts/
├── append-snapshot.sh       # Atomic append of ccusage snapshot YAML documents — hides heredoc from heuristic inspector
├── capture-stats.sh         # Deterministic atomic append for per-dispatch YAML stats capture
├── check-sentinel.sh        # Sentinel staleness detection — replaces inline 3-pattern block in work.md
├── init-values.sh           # Shared init-value computation — PLUGIN_ROOT, RUN_ID, DATE, STATS_FILE (auto-approved)
├── validate-stats.sh        # Diagnostic stats entry count validation — replaces inline ENTRY_COUNT=$(grep -c ...) blocks
├── plugin-qa/               # 8 bash scripts + lib.sh — serves both the QA command and the PostToolUse hook
└── version-check.sh         # 3-way version comparison (source vs installed vs release) — NOT in plugin-qa/ (makes network calls)

resources/
├── bash-generation-rules.md  # Template for Bash Generation Rules — injected into project CLAUDE.md by setup Step 8e
└── stats-capture-schema.md   # YAML schema, field derivation rules, and capture-stats.sh usage reference

templates/
└── auto-approve.sh          # PreToolUse hook template — installed to .claude/hooks/ by /do:setup

skills/
├── do-brainstorm/           # Workflow: explore requirements through collaborative dialogue
├── do-compact-prep/         # Workflow: pre-compaction checklist — save memory, compound, commit
├── do-compound/             # Workflow: document solved problems for institutional knowledge
├── do-deepen-plan/          # Workflow: enhance plans with parallel research + red-team challenges
├── do-plan/                 # Workflow: transform ideas into implementation plans
├── do-review/               # Workflow: multi-agent code review with disk-persisted findings
├── do-setup/                # Workflow: detect environment, configure directories (disable-model-invocation)
├── do-work/                 # Workflow: execute plans via subagent dispatch with tracking
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
├── plugin-changes-qa/       # Plugin QA automation (Tier 1-3 checks)
├── recover/                 # Context recovery from dead/exhausted sessions
├── resolve-pr-parallel/     # Parallel PR comment resolution
├── setup/                   # Setup configuration reference (disable-model-invocation)
├── classify-stats/          # Post-hoc complexity and output_type classification
├── skill-creator/           # Skill packaging scripts
└── version/                 # Plugin version status check (source vs installed vs release)
```

## Agent Registry

All 26 agents with their categories, skill references, and model configuration.

| Agent | Category | Dispatched By | Model |
|-------|----------|---------------|-------|
| best-practices-researcher | research | do:plan, do:setup | sonnet |
| context-researcher | research | do:brainstorm | sonnet |
| framework-docs-researcher | research | do:plan, do:setup | sonnet |
| git-history-analyzer | research | (standalone) | inherit |
| learnings-researcher | research | do:plan | sonnet |
| repo-research-analyst | research | do:brainstorm, do:plan, do:setup | sonnet |
| agent-native-reviewer | review | do:review | inherit |
| architecture-strategist | review | do:review, do:setup | inherit |
| code-simplicity-reviewer | review | do:review, do:setup, do:work | inherit |
| data-integrity-guardian | review | do:compound | inherit |
| data-migration-expert | review | do:review | inherit |
| deployment-verification-agent | review | do:review | inherit |
| frontend-races-reviewer | review | do:review | inherit |
| pattern-recognition-specialist | review | do:review | inherit |
| performance-oracle | review | do:compound, do:review, do:setup | inherit |
| python-reviewer | review | do:setup | inherit |
| schema-drift-detector | review | (standalone) | inherit |
| security-sentinel | review | do:compound, do:deepen-plan, do:review, do:setup | inherit |
| typescript-reviewer | review | do:review, do:setup | inherit |
| bug-reproduction-validator | workflow | (standalone) | inherit |
| convergence-advisor | workflow | do:deepen-plan | inherit |
| pr-comment-resolver | workflow | (standalone) | inherit |
| red-team-relay | workflow | do:brainstorm, do:deepen-plan, do:plan | sonnet |
| plan-consolidator | workflow | do:plan, do:deepen-plan | inherit |
| plan-readiness-reviewer | workflow | do:plan, do:deepen-plan | inherit |
| spec-flow-analyzer | workflow | do:plan | inherit |

**Model column key:** `haiku` = cost-optimized for well-scoped tasks (Haiku model). `sonnet` = balanced cost/quality for research and relay tasks (Sonnet model). `inherit` = uses the default model from the calling context. Override in agent YAML frontmatter if needed.

**Standalone agents** are not dispatched by any command directly but are available for manual dispatch or dynamic discovery by deepen-plan.

All agents expect callers to include OUTPUT INSTRUCTIONS per the `disk-persist-agents` skill. See Context-Lean Convention below.

## Setup: Three-Way Relationship

Setup has three layers, each with a distinct role:

- **Thin alias** (`commands/compound/setup.md`): Redirects `/compound:setup` to `/do:setup` for backwards compatibility. Will be removed in a future version.
- **Workflow skill** (`skills/do-setup/SKILL.md`): The interactive entry point invoked via `/do:setup`. Handles the UX flow (AskUserQuestion), environment detection, and config writing. Has `disable-model-invocation: true` so it loads as reference context rather than auto-executing.
- **Reference skill** (`skills/setup/SKILL.md`): Reference material with `disable-model-invocation: true`. Provides the "what to configure" knowledge -- stack detection logic, agent lists, depth options.

The workflow skill was written by reading the reference skill at fork time -- it does not load the reference skill at runtime. If the reference skill is updated, the workflow skill must be manually synced.

## Config Files

Written by `/do:setup`. Two files:

### `compound-workflows.md` (committed, shared)

Project-level settings shared across team members.
- `do-review` reads: review_agents
- `do-plan` reads: plan_review_agents, depth, plan_readiness_* (under `## Plan Readiness` heading)
- `do-deepen-plan` reads: plan_readiness_* (under `## Plan Readiness` heading)
- `do-review` reads: depth

Keys: stack, review_agents, plan_review_agents, depth, plan_readiness_skip_checks, plan_readiness_provenance_expiry_days, plan_readiness_verification_source_policy, Workflow Instructions section (plugin-specific overrides like red team focus areas, domain constraints, review emphasis).

### `compound-workflows.local.md` (gitignored, per-machine)

Machine-specific environment detection.
- `do-work` reads: tracker
- `do-review` reads: gh_cli

Keys: tracker, gh_cli.

### Red team dispatch (runtime, not stored)

Red team provider preferences are detected each session, not stored in config. CLI availability varies by machine and may change. Detection order:
1. Check `which gemini` / `which codex` for CLI availability
2. Check if PAL MCP tools are available
3. If multiple options exist for a provider, ask user once per session
4. Fallback: Claude-only Task subagent

## Skill/Command Conventions

- **Workflow skills** use `do:` prefix in YAML `name:` field (e.g., `do:brainstorm`, `do:plan`). These are the primary entry points, invoked as `/do:brainstorm` or `/compound-workflows:do:brainstorm`.
- **Thin alias commands** in `commands/compound/` use `compound:` prefix for backwards compatibility. Each alias redirects to the corresponding `/do:*` skill. Aliases will be removed in a future version.
- Workflow skills reference agents by name with inline role descriptions for graceful fallback
- Workflow skills detect beads/PAL/CLI availability at runtime and adapt behavior
- Phase gates enforce resolution of open questions before proceeding
- Research outputs persist to `.workflows/` directories
- **Setup is idempotent** — `/do:setup` must be safe to re-run at any time. New runs merge rules and config, never clobber user-added values. Report what changed.
- `/compound-workflows:recover` is the reactive counterpart to `/do:compact-prep` — it recovers context from dead/exhausted sessions by parsing JSONL logs and cross-referencing external state. It does not dispatch any agents from the agent registry.

## Context-Lean Convention

**"Context-lean"** is the canonical design principle for this plugin: orchestrator workflow skills dispatch agents that write complete outputs to disk and return only brief summaries, keeping the parent context small enough to avoid compaction.

> Some command file subtitles use "context-safe" — this is the same principle, renamed for clarity.

### Rules

1. **All workflow skills dispatching agents MUST include OUTPUT INSTRUCTIONS blocks.** Two variants exist:
   - **Relay variant** (MCP dispatch agents): "Write the response faithfully" wording — the agent relays an external tool's output to disk without interpreting it.
   - **Analysis variant** (research/review agents): "Write your COMPLETE findings" wording — the agent performs analysis and writes its own conclusions.

2. **TaskOutput is banned.** Never use TaskOutput to retrieve full agent results into the orchestrator context. Instead, poll for file existence (`ls .workflows/...`) to detect completion.

3. **MCP tool responses must be wrapped in Task subagents.** Any MCP tool that returns large content (context7 docs, web fetches, etc.) must be called from within a Task subagent that writes the response to disk. The orchestrator never receives the raw MCP response.

4. **Zero exceptions policy.** If a future command legitimately needs MCP responses in orchestrator context for routing/triage decisions, add a documented exception at that time with rationale. Currently: zero exceptions.

See `skills/disk-persist-agents/SKILL.md` for the canonical pattern and output instruction templates.

## `${CLAUDE_SKILL_DIR}` Path Resolution

All workflow skills and script-referencing skills use `${CLAUDE_SKILL_DIR}` (Claude Code v2.1.69+) for path resolution. This variable is substituted at skill load time with the absolute path to the skill's directory.

### Depth Assumption

Skills reference plugin scripts via `${CLAUDE_SKILL_DIR}/../../scripts/<script>`. The `../../` assumes skills are exactly 2 levels below the plugin root:

```
plugins/compound-workflows/          # PLUGIN_ROOT
├── skills/
│   └── do-brainstorm/               # ${CLAUDE_SKILL_DIR} = .../skills/do-brainstorm
│       └── SKILL.md                 # ../../ = PLUGIN_ROOT
```

This 2-level depth is mandated by the Agent Skills spec (skills live in `skills/<name>/SKILL.md`). All plugins follow this convention.

### Validation

`init-values.sh` validates the resolved PLUGIN_ROOT by checking for `.claude-plugin/plugin.json`:

```bash
if [[ ! -f "$PLUGIN_ROOT/.claude-plugin/plugin.json" ]]; then
  echo "Error: PLUGIN_ROOT validation failed" >&2
  exit 1
fi
```

If the depth assumption ever breaks (e.g., nested skill directories), the validation fails loudly. The existing `find` fallback in skill files that don't use init-values.sh handles discovery as a backup.

### When to Use

- **Workflow skills (`do-*`):** `bash ${CLAUDE_SKILL_DIR}/../../scripts/init-values.sh <cmd>` for init-values.sh
- **Utility skills with scripts:** `${CLAUDE_SKILL_DIR}/scripts/<script>` for co-located scripts (e.g., git-worktree, resolve-pr-parallel)
- **Commands:** Commands do NOT get `${CLAUDE_SKILL_DIR}`. The 8 commands in `commands/compound/` are thin aliases only.

## Command Robustness Principles

Commands are prose instructions interpreted by LLMs. Cheaper models (Sonnet) and even Opus can fail to follow instructions faithfully — skipping steps, conflating scope, ignoring gates. All commands must be structurally robust, not just well-written prose.

1. **Completion gates over implicit expectations** — before any post-phase work, include an explicit checklist of what must be resolved. Don't assume prior steps ran correctly.
2. **Unambiguous step scope** — every step and choice must state what it covers and what it doesn't. Batch choices should clarify what comes next. LLMs conflate partial actions with full completion.
3. **Deterministic verification over LLM judgment** — use bash scripts, file existence checks, hooks, or hash comparisons to verify state. Don't rely on the LLM's sense of "done," "enough time," or "already handled."
4. **Defensive redundancy** — repeat critical constraints at decision points and phase transitions, not just in headers. LLMs lose track over long contexts.
5. **Fail loud, not silent** — when steps are skipped or incomplete, the command must surface it. Silent omission (icn) is worse than a wrong-order execution because no one knows something was missed.
6. **Instrument to iterate** — build robustness now (failures are happening), but instrument step-level timing so future improvements are data-driven. Guardrails that prove too costly can be tuned; those proving insufficient can be tightened.
7. **Fix underspecifications proactively** — when readiness checks or specflow analysis find an underspecification, fix it if the answer is unambiguous and follows from existing decisions. Only ask the user when there's a genuine design choice with tradeoffs. Presenting "fix / accept / defer" for a trivially-derivable answer wastes user attention and violates "plans must be fully specified." (See bead 4v2)
8. **Audit entire plugin scope, not just commands** — commands, skills, agents, and any `.md` file containing model-interpreted bash instructions are subject to the same heuristics. QA checks must match audit scope. A "plugin audit" means the whole `plugins/compound-workflows/` tree, not `commands/compound/` alone. (See bead jak v2.4.1: skills missed from heuristic audit.)
9. **Don't accept limitations without feasibility assessment** — when a brainstorm or plan declares something "accepted" or "unavoidable" (e.g., "accept init-block prompts"), verify the assumption by checking whether the pattern is actually eliminable. Most $() init patterns can be rewritten as standalone commands, glob loops, or model-side tracking. Accepting a limitation without exploring alternatives leads to unnecessary technical debt. (See bead jak: Decision 1 accepted fixable init prompts.)

## Development Principles

General principles for plugin development workflow and decision-making.

1. **Comprehensive fixes, not targeted** — when an audit or review identifies a class of issues, fix the entire class across the full scope. Don't cherry-pick high-frequency instances or defer low-frequency ones to follow-up beads. If the fix technique is validated, apply it everywhere. Targeted fixes leave debt that accumulates. (See bead 3l7: jak v2.4.1 fixed commands but skipped skills — the residual became a separate bead.)

## Permission Architecture

The plugin ships a PreToolUse auto-approve hook (`templates/auto-approve.sh`) and a minimal committed baseline in `.claude/settings.json`. Users may also add static `Bash(X:*)` rules in `.claude/settings.local.json`.

**Key principle: static rules serve all LLM-generated bash, not just plugin commands.** When analyzing which static rules to keep or remove, consider ad-hoc commands the LLM generates for debugging, data analysis, and iteration (e.g., `for id in $(bd search ...); do ...`). The hook audit log is blind to `$()`-containing commands that static rules handle — static rules fire before heuristics, so the hook never sees them. Use session JSONL logs as the true source for `$()` frequency analysis.

**Evaluation order:** static rules → heuristics → hook → interactive prompt. Static rules suppress **most** heuristics (`$()`, `{"`). However, `<<` (heredoc) is a "hard" heuristic that fires even with a matching static rule — heredocs must be hidden inside script files. If a heuristic fires, the hook cannot override it — only static rules (for soft heuristics) or script encapsulation (for hard heuristics) can.

### Bash Generation Rules (opt-in via setup)

`/do:setup` offers to inject bash generation rules into the project's CLAUDE.md. These rules teach the model to avoid `$()`, `2>/dev/null` + glob, and other patterns that trigger permission prompt heuristics during ad-hoc conversation bash. The rules are advisory ("SHOULD avoid") with escape valves for atomic operations and practical necessity.

The rules are injected into the project's CLAUDE.md (not the plugin's) so that "not loaded = not active" — projects that don't opt in are unaffected. See `docs/brainstorms/2026-03-11-permissionless-bash-generation-brainstorm.md` for the full empirical analysis.

## Testing Changes

1. Install the plugin in a test project
2. Run `/do:setup` to verify detection
3. Test each modified command end-to-end
4. Verify graceful degradation without beads/PAL
