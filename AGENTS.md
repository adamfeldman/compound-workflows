# Agent Instructions — compound-workflows-marketplace

This repo contains the **compound-workflows** Claude Code plugin. Workflow skills use the `/do:*` namespace (shorthand) or `/compound-workflows:do:*` (full). Legacy `/compound:*` aliases redirect to `/do:*` during the v3.0.0 transition period.

## Project Structure

```
plugins/compound-workflows/
├── .claude-plugin/plugin.json    # Plugin manifest (version here)
├── agents/{research,review,workflow}/  # 26 agent YAML files
├── skills/                       # Skill directories (SKILL.md each)
├── commands/compound/            # Thin aliases redirecting to /do:* skills
├── scripts/plugin-qa/           # Tier 1 QA scripts (8 scripts + lib.sh)
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

Eight bash scripts in `plugins/compound-workflows/scripts/plugin-qa/`:

| Script | What it checks |
|--------|----------------|
| `stale-references.sh` | Old namespace references (`aworkflows:`), references to non-existent commands/agents, stale Task dispatches |
| `file-counts.sh` | Agent, skill, and command counts match declarations in CLAUDE.md, plugin.json, marketplace.json, README.md |
| `truncation-check.sh` | YAML frontmatter present and closed, minimum line count thresholds (catches truncated files) |
| `context-lean-grep.sh` | MCP response transit patterns, banned TaskOutput calls, MCP calls needing Task-wrapping verification, Task dispatches missing OUTPUT INSTRUCTIONS |
| `version-sync.sh` | Validates version consistency across plugin.json, marketplace.json, and CHANGELOG.md |
| `capture-stats-format.sh` | Tests capture-stats.sh with both Agent and Task `<usage>` formats, empty usage, and timeout variant |
| `unslugged-paths.sh` | Checks .workflows/ write paths have variable placeholders (catches static filenames that would overwrite on repeat runs) |
| `no-shell-atomicity.sh` | Detect .tmp atomic write instructions in LLM-interpreted files |

### Tier 2: Semantic Agents (LLM)

Three `Task general-purpose` agents with disk-persisted output:

| Agent | What it checks |
|-------|----------------|
| Context-lean reviewer | No large agent returns in orchestrator, MCP calls wrapped in subagents, OUTPUT INSTRUCTIONS on all Task dispatches, disk-persist pattern used |
| Role description reviewer | Task dispatch agent names exist, inline role descriptions match agent definitions, allowed-tools and model specs consistent |
| Command completeness reviewer | AskUserQuestion usage, phase/step numbering, YAML frontmatter, required sections, namespace conventions, argument handling |

### Hook-Based Enforcement

The PostToolUse hook in `.claude/settings.json` auto-triggers Tier 1 scripts after git commits touching plugin files. The hook is suppressed during `/do:work` via the `.workflows/.work-in-progress` sentinel file.

### Expected Result

All checks should return zero findings. Any finding must be fixed before committing.

**Both tiers are mandatory.** Do not skip Tier 2 semantic agents — they catch issues that Tier 1 scripts cannot. Run `/compound-workflows:plugin-changes-qa` which executes both tiers, rather than running Tier 1 scripts directly.

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

Do not use plan mode, ad-hoc research agents, or inline answers for tasks that have a workflow skill. Route through skills instead:

- **Exploring an idea** ("should we...", "what if...", "is there an opportunity to..."): `/do:brainstorm` — do not answer exploratory questions directly
- **Building a known feature or task**: `/do:plan` to design, then `/do:work` to execute — do not implement without a plan
- **Plan needs deeper research**: `/do:deepen-plan` before executing
- **Reviewing code changes**: `/do:review` — do not review inline
- **Solved a non-obvious problem**: `/do:compound` to capture institutional knowledge
- **Before `/compact`**: `/do:compact-prep` to preserve session context
- **Recovering a dead/exhausted session**: `/compound-workflows:recover`

> **v3.0.0 transition:** During the transition period, `/compound:*` aliases redirect to `/do:*`. Aliases will be removed in a future version. Update muscle memory, docs, and memory files to use `/do:*`.

## Sequential Feature Execution

Run plan→deepen→work for one feature at a time. Do not run parallel feature tracks that touch plugin files.

Plugin files (commands, agents, skills) are prose, not code — git cannot meaningfully merge conflicts in 400-line prompt files. Two branches both modifying `work.md` or `plan.md` means manual rewrite, not a resolvable merge. Plan and deepen-plan immediately before work so the repo doesn't drift between planning and execution.

## Knowledge Precedence

When sources conflict, prefer higher-tier documents. Higher tiers have more review, refinement, and user validation.

| Tier | Source | Why |
|------|--------|-----|
| 1 (highest) | **Live code** — scripts, commands, skills, configs | Ground truth. What actually runs. |
| 2 | **Solutions** — `docs/solutions/` | Post-hoc validated. Documents what worked and why. |
| 3 | **Plans** — `docs/plans/` | Reviewed, deepened, and approved before execution. |
| 4 | **Brainstorms** — `docs/brainstorms/` | Red-teamed and user-decided, but pre-implementation. |
| 5 | **Memory** — `memory/`, `.claude/memory/` | Living notes. May lag behind code or decisions. |
| 6 (lowest) | **Research artifacts** — `.workflows/brainstorm-research/`, `.workflows/plan-research/` | Working artifacts produced by subagents during brainstorm/plan phases. May contain errors, stale claims, or findings that were later overruled by user decisions in the brainstorm or plan they fed into. |

**When to apply:** Before trusting a claim from a lower-tier source, check whether a higher-tier source addresses the same topic. If a research artifact contradicts a brainstorm, trust the brainstorm — the brainstorm incorporated the research and may have deliberately overruled it.

**Research artifacts are not garbage** — they contain valuable detail, citations, and cross-references that higher-tier docs often summarize away. Read them for depth. Just don't let them override reviewed decisions.

## Key Conventions

- Workflow skills use `do:` namespace prefix; `compound:` aliases redirect for backwards compat
- All Task dispatches include inline role descriptions for graceful fallback
- Red team uses 3 independent providers in parallel (Gemini, OpenAI, Claude Opus)
- Red team provider method (clink vs pal chat) is runtime-detected, not stored in config
- Config is split: `compound-workflows.md` (committed) + `compound-workflows.local.md` (gitignored)
- No git remote configured; local-only development
- Only commit files you changed in the current session. If untracked or modified files from prior sessions are present, offer to commit them separately (they may have been left behind) — the goal is a clean working tree at session end
- **Suggest squash before push** — when multiple commits on the same topic accumulate during a session, suggest squashing to the user before pushing. Never auto-squash. Wait for the user to say the change is done before committing — don't commit mid-iteration while still refining.
- Do not use auto memory (`~/.claude/projects/.../memory/`) — use repo-level memory instead: `memory/` (committed, project knowledge) + `.claude/memory/` (gitignored, private preferences)
- **Always add `--estimate` when creating beads** — estimate total remaining workflow time in minutes (not just the next step). See `memory/estimation-heuristics.md` for per-phase timing data.
- **Show estimates when listing beads** — when the user asks to see open beads, include the estimate alongside each bead for context (e.g., `nn3 P1 90m — Evaluate red team step in plan`).
- **Tag beads with impact via `--metadata`** — score impact on three dimensions and store a precomputed score for sorting. Each dimension uses: `none` (0), `minor` (1), `major` (3). Dimensions: cost = token/quota savings, quality = output quality lift, friction = manual work eliminated. Sum → `impact_score` (0–9). Priority captures urgency; impact captures value when shipped. Sort by priority first, impact_score as tiebreaker. Example: `bd update <id> --metadata '{"impact": {"cost": "major", "quality": "none", "friction": "minor"}, "impact_score": 4}'`. Update impact_score whenever a dimension changes.
- **Impact efficiency = impact_score / (estimate_hours)** — when deciding what to work on next, compute impact per hour invested. High-score low-effort beads are the best bang for buck. Use this to break ties within the same priority tier.
- **Two bead table formats:**
  - **Full table** (`show me the full table`) — all open beads sorted by priority then impact score. Columns: Pri, Score, Est, Eff, Title, Cost, Quality, Friction. Mark blocked beads with ⊘.
  - **What's next table** (`what's next`) — actionable beads only (not blocked, not P4), sorted by efficiency descending. Columns: Rank, Title, Est, Score, Eff.

## Bash Generation Rules

> Injected by `/do:setup` — teaches the model to generate bash that avoids Claude Code's permission prompt heuristics.

These rules apply to the command string submitted to the Bash tool — what Claude Code's heuristic inspector evaluates. They do NOT apply to script files written via the Write tool (heuristics don't inspect file content).

**Principle:** You SHOULD avoid patterns that trigger Claude Code's permission prompt heuristics in Bash tool commands. Default to split-call or temp-script alternatives. Use `$()` only when: (a) the value would change between separate Bash calls (atomic operation), or (b) split-calls have caused problems in the current conversation. Verbosity is not a justification — more Bash calls is fine; wrong results isn't.

**Do NOT append `2>/dev/null` reflexively.** It enables heuristic triggers when combined with globs (`ls *.md 2>/dev/null`) or quoted-dash strings in compounds (`cmd 2>/dev/null; echo "---"`). Let stderr show — it's almost never harmful in conversation.

### Avoidance Patterns

| # | Instead of | Use |
|---|-----------|-----|
| 1 | `VAR=$(cmd)` | Run `cmd` alone, read output, use value in next Bash call |
| 2 | `for ...; do val=$(cmd); done` | Run each command separately, synthesize results |
| 3 | `echo "$(date)"` | Run `date` alone, incorporate output in next call |
| 4 | `$(( x + y ))` | `python3 -c "print(x + y)"` or `echo "x + y" \| bc` |
| 5 | `git commit -m "$(cat <<'EOF'...)"` | Write tool creates file, then `git commit -F file` |
| 6 | Complex loops/pipelines with `$()` | Write tool creates .sh script, then `bash script.sh` |
| 7 | `ls *.md 2>/dev/null` | `ls *.md` (let stderr show) |
| 8 | `TS="$(date)" && cat >> f` | Get timestamp first, then Write tool appends |

### When $() Is Acceptable

- **Atomic operations** — the value would change between separate Bash tool calls
- **Practical escape valve** — split-calls have caused problems in the current conversation

### Notes

- Variables do NOT persist across Bash tool calls (each is a fresh shell). CWD does persist.
- Commands covered by `Bash(X:*)` static rules (git, for, python3, bd, cat) can use any pattern — static rules suppress heuristics entirely.
- These rules apply to in-conversation bash only. Script files (.sh) use normal shell idioms.
