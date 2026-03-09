# Agent Instructions — compound-workflows-marketplace

This repo contains the **compound-workflows** Claude Code plugin. 24 agents, 15 skills, 9 commands under the `/compound:*` namespace.

## Project Structure

```
plugins/compound-workflows/
├── .claude-plugin/plugin.json    # Plugin manifest (version here)
├── agents/{research,review,workflow}/  # 24 agent YAML files
├── skills/                       # 15 skill directories
├── commands/compound/            # 9 slash commands
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

Run after ANY change to commands, agents, or skills. Launch all 4 checks in parallel using background agents.

### Check 1: Commands QA (brainstorm + plan)

```
Agent: "QA review brainstorm.md and plan.md. Read each file and check:
1. Truncation — complete file?
2. Role descriptions on ALL Task dispatches — inline role present?
3. Stale references — any compound-workflows:, aworkflows:, bd sync, /resolve_todo_parallel, /test-browser, /xcode-test?
4. AskUserQuestion — all user decision points explicit?
5. Year references — any hardcoded dates?
6. Red team — providers independent (no reading each other)? Both clink and pal chat paths? Runtime detection?
7. PAL write-to-disk — explicit instruction to write PAL response to file?
Report: ISSUE or OK per check per file."
```

### Check 2: Commands QA (deepen-plan + work)

```
Agent: "QA review deepen-plan.md and work.md. Read each file and check:
1. Truncation — complete file?
2. Role descriptions on ALL Task dispatches — inline role present?
3. Stale references — any compound-workflows:, aworkflows:, bd sync?
4. AskUserQuestion — all user decision points explicit?
5. Year references — any hardcoded dates?
6. Red team (deepen-plan) — providers independent? Both clink and pal chat? Runtime detection?
7. TodoWrite fallback (work) — TodoWrite mode blocks at all divergence points? Step numbering sequential?
8. Plan readiness (plan + deepen-plan) — readiness phase present? Dispatches plan-readiness-reviewer with role description? Config gate (plan_readiness)? Output paths match SKILL.md convention?
Report: ISSUE or OK per check per file."
```

### Check 3: Commands QA (setup + review + compound + compact-prep)

```
Agent: "QA review setup.md, review.md, compound.md, compact-prep.md. Check:
1. Truncation — complete?
2. Role descriptions on ALL Task dispatches — inline role?
3. Stale references — compound-workflows:, aworkflows:, bd sync? (compound-engineering in setup is intentional)
4. AskUserQuestion — all decision points explicit?
5. Year references — hardcoded dates?
6. Setup: detects gemini+codex CLI? Writes TWO config files? No red team in stored config?
7. Review: conditional agents have run_in_background + disk-write?
8. Compound: all 8 dispatches (5 Phase 1 + 3 Phase 3) have full Task syntax + role?
9. Compact-prep: both commit checks use AskUserQuestion?
Report: ISSUE or OK per check per file."
```

### Check 4: Stale References + CLAUDE.md

```
Agent: "Scan plugins/compound-workflows/ commands/, agents/, skills/ for:
1. compound-workflows: (old namespace, exclude compound-workflows.local and compound-workflows.md)
2. aworkflows
3. bd sync
4. /resolve_todo_parallel, /test-browser, /xcode-test
5. kieran or julik (case insensitive) in agents/
6. BriefSystem, EmailProcessing, Xiatech, EveryInc, Every Reader in agents/ and skills/

Then read CLAUDE.md and verify:
- Config section documents TWO files (committed + gitignored)
- Red team dispatch is runtime detection, not stored config
- Agent count is 24 (22 original + plan-readiness-reviewer + plan-consolidator)
- Workflow agent count is 5 (3 original + 2 new)
- plan-checks/ noted as check modules, not standalone agents

Then verify plan-checks/ integrity:
- 3 shell scripts are executable and have #!/usr/bin/env bash
- semantic-checks.md has agent YAML frontmatter
- No shell scripts reference absolute paths or non-portable commands
Report all results."
```

### Expected Result

All checks should return OK. Any ISSUE must be fixed before committing.

## Versioning

Every change MUST update:
1. `plugins/compound-workflows/.claude-plugin/plugin.json` — bump version
2. `.claude-plugin/marketplace.json` — bump version
3. `plugins/compound-workflows/CHANGELOG.md` — document changes

- **MAJOR**: Breaking changes to command interfaces or config schema
- **MINOR**: New commands, agents, skills, or significant enhancements
- **PATCH**: Bug fixes, doc updates, prompt improvements

## Release Process

Only release when files inside `plugins/compound-workflows/` change. Changes to the repo root (README, AGENTS.md, docs/, assets/) do NOT warrant a release.

1. Run QA (see above), fix any issues
2. Update `plugins/compound-workflows/CHANGELOG.md`
3. Bump version in `plugins/compound-workflows/.claude-plugin/plugin.json`
4. Bump version + ref in `.claude-plugin/marketplace.json`
5. Commit
6. Push: `git push origin main`
7. Release: `gh release create v<version> --title "v<version>" --notes "<changelog entry>"` (creates tag automatically)

After release, update locally via CLI (`claude plugin update compound-workflows@compound-workflows-marketplace`) or the interactive `/plugin` menu inside Claude Code.

## Key Conventions

- Commands use `compound:` namespace prefix
- All Task dispatches include inline role descriptions for graceful fallback
- Red team uses 3 independent providers in parallel (Gemini, OpenAI, Claude Opus)
- Red team provider method (clink vs pal chat) is runtime-detected, not stored in config
- Config is split: `compound-workflows.md` (committed) + `compound-workflows.local.md` (gitignored)
- No git remote configured; local-only development
- Only commit files you changed in the current session — do not stage unrelated modified files
