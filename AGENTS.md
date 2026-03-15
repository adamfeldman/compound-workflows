# Agent Instructions — compound-workflows-marketplace

This repo contains the **compound-workflows** Claude Code plugin. Workflow skills use the `/do:*` namespace (shorthand) or `/compound-workflows:do:*` (full). Legacy `/compound:*` aliases redirect to `/do:*` during the v3.0.0 transition period.

The plugin's purpose is to capture best-practice patterns and make them shareable, while remaining configurable to individual user preferences.

## Interaction Rules

**Present proposals and STOP. Do not execute until the user explicitly says to proceed.**

Asking "Want me to apply?" or "Ready to dispatch?" is NOT receiving confirmation. Only explicit user responses like "yes", "do it", "go", "apply it" count as permission. Instructions about *how* to do something ("keep the bead updated", "don't close the bead") are not permission to *start* — they are constraints for when work begins. When in doubt, wait.

## Routing

Do not use plan mode, ad-hoc research agents, or inline answers for tasks that have a workflow skill. Route through skills instead:

- **Exploring an idea** ("should we...", "what if...", "is there an opportunity to..."): `/do:brainstorm` — do not answer exploratory questions directly
- **Building a known feature or task**: `/do:plan` to design, then `/do:work` to execute — do not implement without a plan
- **Plan needs deeper research**: `/do:deepen-plan` before executing
- **Reviewing code changes**: `/do:review` — do not review inline
- **Solved a non-obvious problem**: `/do:compound` to capture institutional knowledge
- **Before `/compact`**: `/do:compact-prep` to preserve session context
- **Abandoning a session** ("done for today", "wrapping up for the day", "closing out", "ending the session"): `/do:abandon` — do not just close the terminal
- **Recovering a dead/exhausted session**: `/compound-workflows:recover`

> **v3.0.0 transition:** During the transition period, `/compound:*` aliases redirect to `/do:*`. Aliases will be removed in a future version. Update muscle memory, docs, and memory files to use `/do:*`.

### Session-End Detection

When you detect session-end language ("done for today", "wrapping up for the day", "closing out",
"ending the session", "abandoning"), add an inline text suggestion:

> Tip: run `/do:abandon` to capture session knowledge before closing.

**This is a suggestion, not a gate.** Do not ask, do not block, do not repeat if the user continues working.

**Suppression rules:**
- Suppress after the user dismisses it or ignores it twice in the same session (track in conversation context)
- Ambiguous phrases ("I'm done", "that's all") excluded from triggers — they fire on task completion, creating cry-wolf pattern
- If the user says "stop suggesting /abandon", stop immediately for the remainder of the session

## Project Structure

```
plugins/compound-workflows/
├── .claude-plugin/plugin.json    # Plugin manifest (version here)
├── agents/{research,review,workflow}/  # Agent definitions (.md)
├── skills/                       # Skill directories (SKILL.md each)
├── commands/compound/            # Thin aliases redirecting to /do:* skills
├── scripts/plugin-qa/           # Tier 1 QA scripts + lib.sh
├── CLAUDE.md                     # Plugin dev instructions (authoritative inventory counts)
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

Nine bash scripts in `plugins/compound-workflows/scripts/plugin-qa/`:

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
| `write-tool-discipline.sh` | Heredoc, echo redirect, and inline commit-flag patterns in LLM-interpreted files |

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
3. `plugins/compound-workflows/CHANGELOG.md` — document changes (lead with user benefit, not implementation details)
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

After release, update the local install. `claude plugin update` is slow to recognize new releases, so pull the marketplace clone manually first as a workaround:

1. `git -C ~/.claude/plugins/marketplaces/compound-workflows-marketplace pull origin main`
2. `claude plugin update compound-workflows@compound-workflows-marketplace`
3. Restart the session (loaded skills are cached at session start)

Do NOT skip step 1. Do NOT use `claude plugin remove` + `claude plugin install` as a workaround.

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
- Git remote: `origin` at `github.com/adamfeldman/compound-workflows.git`
- Only commit files you changed in the current session. If untracked or modified files from prior sessions are present, offer to commit them separately (they may have been left behind) — the goal is a clean working tree at session end
- **Group commits by logical change, not by file or session** — changes that share a single "why" belong together. Different motivations get separate commits, even if they touch the same file. When in doubt, split. Don't split mechanically — two changes that only make sense together should stay in one commit.
- **Suggest squash before push** — when multiple commits on the same topic accumulate during a session, suggest squashing to the user before pushing. Never auto-squash. Wait for the user to say the change is done before committing — don't commit mid-iteration while still refining.
- Do not use auto memory (`~/.claude/projects/.../memory/`) — use repo-level memory instead: `memory/` (committed, project knowledge) + `.claude/memory/` (gitignored, private preferences)
- **Always add `--estimate` when creating beads** — estimate in minutes. See `.claude/memory/estimation-heuristics.md` for per-phase timing data, origin-specific correction factors, and calibration guidance.
- **Show estimates when listing beads** — when the user asks to see open beads, include the estimate alongside each bead for context (e.g., `nn3 P1 90m — Evaluate red team step in plan`).
- **Tag beads with impact via `--metadata`** — score impact on three dimensions and store a precomputed score for sorting. Each dimension uses: `none` (0), `minor` (1), `major` (3). Dimensions: cost = token/quota savings, quality = output quality lift, friction = manual work eliminated. Sum → `impact_score` (0–9). Priority captures urgency; impact captures value when shipped. Sort by priority first, impact_score as tiebreaker. Example: `bd update <id> --metadata '{"impact": {"cost": "major", "quality": "none", "friction": "minor"}, "impact_score": 4}'`. Update impact_score whenever a dimension changes.
- **Bead origin metadata** — `/do:work` automatically adds `"origin": "work"` and `"plan": "<plan-file>"` to `--metadata` when creating work steps, making them structurally distinguishable from beads. Beads created outside `/do:work` do not need `origin` — its absence signals a regular bead. This enables analytics (estimation accuracy, velocity, cost-per-bead) to separate the two populations without relying on description-prefix conventions.
- **`bd show` does not display `estimated_minutes`** — the field exists in the database but `bd show` omits it from output. To retrieve estimates, use `bd sql "SELECT SUBSTR(id, -4) AS short, priority, estimated_minutes, JSON_EXTRACT(metadata, '$.impact_score') AS score, title FROM issues WHERE status = 'open' ORDER BY priority"`.
- **Impact efficiency = impact_score / (estimate_hours)** — when deciding what to work on next, compute impact per hour invested. High-score low-effort beads are the best bang for buck. Use this to break ties within the same priority tier.
- **Two bead table formats:**
  - **Full table** (`show me the full table`) — all open beads sorted by priority then impact score. Columns: Pri, Score, Est, Eff, Title, Cost, Quality, Friction. Mark blocked beads with ⊘.
  - **What's next table** (`what's next`) — actionable beads only (not blocked, not P4), sorted by efficiency descending. Columns: Rank, Title, Est, Score, Eff.

## Session Worktree Isolation

**At session start, before doing anything else, create a session worktree.**
Run `bd worktree create .worktrees/session-<name>` and `cd` into it.
Do not read files, run commands, or respond to the user first.

- Name the worktree after the task if known: `session-s7qj` or `session-fix-typo`
- User can say "stay on main" / "skip worktree" to opt out
- If you're already in a worktree (post-compact resume), skip — you're already isolated
- If `bd worktree create` fails, warn the user and proceed on main
- If the hook warns that bd is unavailable, skip worktree creation
- At session end, `/do:compact-prep` merges back to the default branch
- Any git operations before creating the worktree happen on the default branch
- Before committing, if session_worktree is enabled and you're NOT in a worktree,
  warn the user: "You're committing to main without worktree isolation. Continue?"

**Beads database (.beads/) is shared across all sessions.** Worktree isolation covers git state only. Bead operations are concurrency-safe at the SQL level (Dolt) but not coordination-safe at the business logic level.

## Bash Generation Rules

> Injected by `/do:setup` — teaches the model to generate bash that avoids Claude Code's permission prompt heuristics.

These rules apply to the command string submitted to the Bash tool — what Claude Code's heuristic inspector evaluates. They do NOT apply to script files written via the Write tool (heuristics don't inspect file content).

**Principle:** You SHOULD avoid patterns that trigger Claude Code's permission prompt heuristics in Bash tool commands. Default to split-call or temp-script alternatives. Use `$()` only when: (a) the value would change between separate Bash calls (atomic operation), or (b) split-calls have caused problems in the current conversation. Verbosity is not a justification — more Bash calls is fine; wrong results isn't. Every violation causes an interactive permission prompt that blocks the user mid-workflow. These are not style suggestions — they directly affect usability.

**Do NOT append `2>/dev/null` reflexively.** It enables heuristic triggers when combined with globs (`ls *.md 2>/dev/null`) or quoted-dash strings in compounds (`cmd 2>/dev/null; echo "---"`). Let stderr show — it's almost never harmful in conversation.

### Avoidance Patterns

| # | Instead of | Use |
|---|-----------|-----|
| 1 | `VAR=$(cmd)` | Run `cmd` alone, read output, use value in next Bash call |
| 2 | `for ...; do val=$(cmd); done` | Run each command separately, synthesize results |
| 3 | `echo "$(date)"` | Run `date` alone, incorporate output in next call |
| 4 | `$(( x + y ))` | `python3 -c "print(x + y)"` or `echo "x + y" \| bc` |
| 5 | `git commit -m "$(cat <<'EOF'...)"` | `git commit -F /dev/stdin << 'EOF'` |
| 6 | Complex loops/pipelines with `$()` | Write tool creates .sh script, then `bash script.sh` |
| 7 | `ls *.md 2>/dev/null` | `ls *.md` (let stderr show) |
| 8 | `TS="$(date)" && cat >> f` | Get timestamp first, then Write tool appends |
| 9 | `ls dir 2>/dev/null; echo "---"; date` | Separate Bash calls: `ls dir`, then `date`. No separators, no stderr suppression. |

### Polling Agent Output

When checking whether subagent output files exist, use **separate Bash calls** — one per command. Do not combine `ls`, `echo`, or `date` into compound chains.

**Good:**
```
Bash call 1: ls -la .workflows/plan-research/agents/
Bash call 2: date
```

**Bad — triggers permission prompt:**
```
ls -la .workflows/plan-research/agents/ 2>/dev/null; echo "---"; date
```

Each semicolon-joined segment adds heuristic surface area. Quoted separators (`"---"`) and `2>/dev/null` are especially problematic. Separate calls cost nothing — use them.

### When $() Is Acceptable

- **Atomic operations** — the value would change between separate Bash tool calls
- **Practical escape valve** — split-calls have caused problems in the current conversation

### Notes

- Variables do NOT persist across Bash tool calls (each is a fresh shell). CWD does persist.
- Commands covered by `Bash(X:*)` static rules (git, for, python3, bd, cat) can use any pattern — static rules suppress heuristics entirely.
- These rules apply to in-conversation bash only. Script files (.sh) use normal shell idioms.

## Memory Hot Cache

Critical preferences that must survive compaction. Source of truth: `.claude/memory/MEMORY.md` + `memory/`.

### Interaction

- **Wait for confirmation** — see Interaction Rules at top of file. "Want me to apply?" is not receiving permission.
- **Don't jump to fixing** — when discussing a bead, update the bead with findings but don't edit code until asked.

### Workflow

- **Plans must be fully specified** — no underspecifications that force decisions during /do:work.
- **Automate, don't ask** — minimize user prompts in workflows and permission prompts.
- **Reduce main context** — heavy analysis always in subagents.
- **Cost-conscious** — evaluate workflow cost vs value before running commands.
- **Always run Tier 2 QA** — never skip semantic agents before merging plugin changes.

### Engineering

- **Deterministic over probabilistic** — prefer bash scripts and hooks over LLM inline instructions for mechanical tasks.
- **Warn over silent skip** — when something breaks, warn so user can file a bug. Don't silently degrade.
- **Empirical over speculative** — test before claiming root cause on undocumented Claude Code behavior.
- **Name the specific config file** — never shorthand like "settings." Specify settings.json vs settings.local.json vs compound-workflows.md vs compound-workflows.local.md.
- **Changelog entries lead with user benefit** — not implementation details.
- **Purpose-specific directories over scratch, never `/tmp`** — use `.workflows/<command>/<run-id>/` for artifacts, `.workflows/scratch/` as fallback. Never `/tmp`.
