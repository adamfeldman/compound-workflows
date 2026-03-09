# Agent Instructions — compound-workflows-marketplace

This repo contains the **compound-workflows** Claude Code plugin. Commands use the `/compound:*` namespace; skills use `/compound-workflows:*`.

## Project Structure

```
plugins/compound-workflows/
├── .claude-plugin/plugin.json    # Plugin manifest (version here)
├── agents/{research,review,workflow}/  # 26 agent YAML files
├── skills/                       # Skill directories (SKILL.md each)
├── commands/compound/            # Slash commands (max 8 per dir)
├── scripts/plugin-qa/           # Tier 1 QA scripts (5 scripts + lib.sh)
├── CLAUDE.md                     # Plugin dev instructions
├── CHANGELOG.md                  # Version history
└── README.md                     # User-facing docs

.claude-plugin/marketplace.json   # Marketplace wrapper (version here too)
docs/plans/                       # Planning documents
```

## Development Workflow

1. Make changes to commands, agents, or skills
2. Run QA (see below)
3. Fix any issues found
4. Update CHANGELOG.md
5. Bump version in plugin.json + marketplace.json
6. Commit

## QA Process

Run `/compound-workflows:plugin-changes-qa` after ANY change to commands, agents, or skills. The command runs two tiers of checks:

### Tier 1: Structural Scripts (Deterministic)

Five bash scripts in `plugins/compound-workflows/scripts/plugin-qa/`:

| Script | What it checks |
|--------|----------------|
| `stale-references.sh` | Old namespace references (`aworkflows:`), references to non-existent commands/agents, stale Task dispatches |
| `file-counts.sh` | Agent, skill, and command counts match declarations in CLAUDE.md, plugin.json, marketplace.json, README.md |
| `truncation-check.sh` | YAML frontmatter present and closed, minimum line count thresholds (catches truncated files) |
| `context-lean-grep.sh` | MCP response transit patterns, banned TaskOutput calls, MCP calls needing Task-wrapping verification, Task dispatches missing OUTPUT INSTRUCTIONS |
| `version-sync.sh` | Validates version consistency across plugin.json, marketplace.json, and CHANGELOG.md |

### Tier 2: Semantic Agents (LLM)

Three `Task general-purpose` agents with disk-persisted output:

| Agent | What it checks |
|-------|----------------|
| Context-lean reviewer | No large agent returns in orchestrator, MCP calls wrapped in subagents, OUTPUT INSTRUCTIONS on all Task dispatches, disk-persist pattern used |
| Role description reviewer | Task dispatch agent names exist, inline role descriptions match agent definitions, allowed-tools and model specs consistent |
| Command completeness reviewer | AskUserQuestion usage, phase/step numbering, YAML frontmatter, required sections, namespace conventions, argument handling |

### Hook-Based Enforcement

The PostToolUse hook in `.claude/settings.local.json` auto-triggers Tier 1 scripts after git commits touching plugin files. The hook is suppressed during `/compound:work` via the `.workflows/.work-in-progress` sentinel file.

### Expected Result

All checks should return zero findings. Any finding must be fixed before committing.

## Versioning

Every change MUST update:
1. `plugins/compound-workflows/.claude-plugin/plugin.json` — bump version
2. `.claude-plugin/marketplace.json` — bump version
3. `plugins/compound-workflows/CHANGELOG.md` — document changes
4. `plugins/compound-workflows/README.md` — verify component counts

- **MAJOR**: Breaking changes to command interfaces or config schema
- **MINOR**: New commands, agents, skills, or significant enhancements
- **PATCH**: Bug fixes, doc updates, prompt improvements

## Release Process

Only release when files inside `plugins/compound-workflows/` change. Changes to the repo root (README, AGENTS.md, docs/, assets/) do NOT warrant a release.

**Do not tag or release until the user explicitly says to release.** Version bumps and CHANGELOG updates are fine during development, but tagging, pushing tags, and `gh release create` require user confirmation. Do not bundle release into a commit flow automatically.

1. Run QA (see above), fix any issues
2. Update `plugins/compound-workflows/CHANGELOG.md`
3. Bump version in `plugins/compound-workflows/.claude-plugin/plugin.json`
4. Bump version in `.claude-plugin/marketplace.json`
5. Commit
6. **Ask the user if they want to release now or defer.** Do not assume either way.
7. If user confirms, tag: `git tag v<version>`
8. Push: `git push origin main --tags`
9. Release: `gh release create v<version> --title "v<version>" --notes "<changelog entry>"`

After release, update locally via CLI (`claude plugin update compound-workflows@compound-workflows-marketplace`) or the interactive `/plugin` menu inside Claude Code.

## Routing

Do not use plan mode, ad-hoc research agents, or inline answers for tasks that have a compound command. Route through compound commands instead:

- **Exploring an idea** ("should we...", "what if...", "is there an opportunity to..."): `/compound:brainstorm` — do not answer exploratory questions directly
- **Building a known feature or task**: `/compound:plan` to design, then `/compound:work` to execute — do not implement without a plan
- **Plan needs deeper research**: `/compound:deepen-plan` before executing
- **Reviewing code changes**: `/compound:review` — do not review inline
- **Solved a non-obvious problem**: `/compound:compound` to capture institutional knowledge
- **Before `/compact`**: `/compound:compact-prep` to preserve session context
- **Recovering a dead/exhausted session**: `/compound-workflows:recover`

## Sequential Feature Execution

Run plan→deepen→work for one feature at a time. Do not run parallel feature tracks that touch plugin files.

Plugin files (commands, agents, skills) are prose, not code — git cannot meaningfully merge conflicts in 400-line prompt files. Two branches both modifying `work.md` or `plan.md` means manual rewrite, not a resolvable merge. Plan and deepen-plan immediately before work so the repo doesn't drift between planning and execution.

## Key Conventions

- Commands use `compound:` namespace prefix
- All Task dispatches include inline role descriptions for graceful fallback
- Red team uses 3 independent providers in parallel (Gemini, OpenAI, Claude Opus)
- Red team provider method (clink vs pal chat) is runtime-detected, not stored in config
- Config is split: `compound-workflows.md` (committed) + `compound-workflows.local.md` (gitignored)
- No git remote configured; local-only development
- Only commit files you changed in the current session. If untracked or modified files from prior sessions are present, offer to commit them separately (they may have been left behind) — the goal is a clean working tree at session end
- Do not use auto memory (`~/.claude/projects/.../memory/`) — use repo-level memory instead: `memory/` (committed, project knowledge) + `.claude/memory/` (gitignored, private preferences)
