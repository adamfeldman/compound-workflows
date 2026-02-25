---
title: "Port Gaps: Forking Agents & Skills from compound-engineering"
type: brainstorm
status: complete
date: 2026-02-25
---

# What We're Building

A complete fork of compound-engineering's agents and skills into the compound-workflows plugin, making it fully self-contained. Users install ONE plugin and get everything — no naming collisions with compound-engineering's overlapping commands.

## Scope

### Agents: 21 new (22 total with existing context-researcher)

**Research (6 total):**
1. `context-researcher` — already ported
2. `repo-research-analyst` — used by brainstorm, plan
3. `learnings-researcher` — used by plan
4. `best-practices-researcher` — used by plan
5. `framework-docs-researcher` — used by plan
6. `git-history-analyzer` — not referenced, useful for deepen-plan discovery

**Review (13 total):**
7. `code-simplicity-reviewer` — used by work, work-agents, review
8. `typescript-reviewer` — renamed from kieran-typescript-reviewer
9. `python-reviewer` — renamed from kieran-python-reviewer
10. `pattern-recognition-specialist` — used by review
11. `architecture-strategist` — used by review
12. `security-sentinel` — used by review, compound
13. `performance-oracle` — used by review, compound
14. `agent-native-reviewer` — used by review
15. `data-migration-expert` — review conditional
16. `deployment-verification-agent` — review conditional
17. `frontend-races-reviewer` — renamed from julik-frontend-races-reviewer
18. `data-integrity-guardian` — compound conditional
19. `schema-drift-detector` — not referenced, useful for review expansion

**Workflow (3 total):**
20. `spec-flow-analyzer` — used by plan (4-phase completeness/edge case analysis)
21. `bug-reproduction-validator` — not referenced, standalone utility
22. `pr-comment-resolver` — not referenced, standalone utility

### Skills: 14 new (15 total with existing disk-persist-agents)

**Referenced by commands (5):**
1. `brainstorming` — brainstorm.md
2. `document-review` — brainstorm.md
3. `file-todos` — review.md
4. `git-worktree` — review.md
5. `compound-docs` — compound.md (templates + YAML schema)

**Utility (9):**
6. `setup` — replaces existing setup command; adds stack detection + agent config
7. `gemini-imagegen` — Gemini API image generation
8. `agent-browser` — browser automation
9. `orchestrating-swarms` — multi-agent coordination patterns
10. `create-agent-skills` — guide for creating new agents/skills
11. `agent-native-architecture` — architecture patterns (12 reference docs)
12. `resolve-pr-parallel` — parallel PR comment resolution
13. `skill-creator` — skill creation and iteration
14. `frontend-design` — distinctive frontend interfaces, anti-AI-slop guide

**Already exists:**
15. `disk-persist-agents` — output persistence patterns

### Commands: 7 existing, need updates

Changes needed:
- **review.md**: Remove Rails reviewer references (dhh-rails-reviewer, kieran-rails-reviewer). Update 3 renamed agent refs (typescript-reviewer, python-reviewer, frontend-races-reviewer).
- **setup.md**: Replace content with setup skill approach (stack detection + agent config + beads/PAL detection). Add conflict detection: warn if compound-engineering is also installed.
- **deepen-plan.md**: Update dynamic agent discovery logic (Phase 2c) to search compound-workflows' own `agents/` directory instead of (or in addition to) compound-engineering's cache path.
- **All commands**: Remove compound-engineering as optional dependency — plugin is now self-contained. Genericize any company-specific examples encountered during updates.
- **README.md, CLAUDE.md**: Update dependency table, component counts. Add upstream sync note and attribution.

### Dropped (not porting)

**Agents:**
- dhh-rails-reviewer (Rails-specific)
- kieran-rails-reviewer (Rails-specific)
- every-style-editor (Every brand-specific)
- lint (Ruby/ERB-specific)
- ankane-readme-writer (Ruby gem-specific)
- 3 design/Figma agents (require Figma MCP — the real blocker; agent-browser is being ported separately)

**Skills:**
- dhh-rails-style (Rails)
- every-style-editor (Every brand)
- andrew-kane-gem-writer (Ruby gem)
- dspy-ruby (Ruby)
- rclone (not workflow-related)

## Why This Approach

**Fork over dependency** — compound-engineering ships overlapping commands (`/workflows:brainstorm`, `/workflows:review`, `/workflows:compound`, `/deepen-plan`). Requiring it means users see both sets in the slash command picker with no clear way to distinguish. Forking the agents and skills eliminates this confusion for users who only install compound-workflows. Users who install both will see a conflict warning from `/compound-workflows:setup`.

**One plugin, full power** — The current inline role descriptions (1-sentence fallbacks) lose all the structured methodology, output templates, and quality standards that full agent definitions provide. For the 5 research agents alone, that's the difference between a 1-sentence "You are a research analyst" and a multi-page structured methodology with search strategies and quality assurance. Note: some skills (gemini-imagegen, agent-browser) require external setup (API keys, browser tools) — "full power" means all prompts are present, not all external deps are pre-configured.

**Depersonalized names** — Three agents carried contributor names (kieran-*, julik-*) that don't serve the marketplace audience. Renamed to descriptive names.

**Genericized examples** — Company-specific examples in agent prompts (e.g., "BriefSystem", "EmailProcessing") will be replaced with generic domain examples (e.g., "AuthService", "PaymentProcessor") during the port. This prevents few-shot anchoring bias toward specific company patterns.

**Upstream sync** — This is a fork, not a permanent divergence. Will regularly use LLMs to diff and merge improvements from upstream compound-engineering, and will consider contributing changes back.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Relationship to compound-engineering | Fork agents/skills, no dependency | Avoids command naming collision |
| Coexistence | Document "don't install both" | Duplicate agents would be unpredictable |
| Agent names | Depersonalize 3 (kieran-*, julik-*) | Generic names for marketplace |
| Examples | Genericize during port | Prevents few-shot anchoring bias (red team finding) |
| Model fields | Keep haiku/inherit as-is | Preserves cost optimization |
| Agent organization | Mirror compound-engineering structure (research/, review/, workflow/) | Familiar layout |
| Dropped agents | Rails, Every, Figma, Ruby-specific | Not relevant to general audience |
| Skills scope | All non-company-specific | Broad utility |
| Setup overlap | Replace command with skill approach | Skill is more comprehensive; add beads/PAL detection |
| Command cleanup | Remove all dropped agent refs | Ship clean, no dead references |
| Version | 1.1.0 (MINOR — adding agents/skills) | Plugin never published; no users to break |
| Attribution | NOTICE file + README credit | MIT license requires copyright notice for forks |
| Upstream sync | LLM-assisted periodic merge | Fork, not permanent divergence; will contribute back |
| Conflict detection | Setup warns if compound-engineering installed | Technical enforcement, not just documentation |

## Resolved Questions

**Q: What about users who want both plugins?**
A: Document that compound-workflows supersedes compound-engineering. Install one or the other. Agent resolution with duplicates would be unpredictable.

**Q: Should we generalize company-specific examples in agents?**
A: Yes — genericize during the port. Three independent red team models (Gemini, GPT-5.2, Opus) all flagged that company-specific examples cause few-shot anchoring bias in LLM outputs. Replace "BriefSystem" etc. with generic domain examples.

**Q: How do renamed agents affect existing commands?**
A: Commands must be updated to reference new names (typescript-reviewer, python-reviewer, frontend-races-reviewer). Also remove references to dropped agents (Rails reviewers).

**Q: Should the setup command or setup skill win?**
A: The setup skill replaces the setup command's content. It has a more comprehensive interactive wizard (stack detection, agent configuration, depth selection). Beads/PAL/directory detection gets added to it.

## Red Team Challenge — Resolved

Three models reviewed this brainstorm (Gemini 3 Pro, GPT-5.2, Claude Opus 4.6). Full critiques at `.workflows/brainstorm-research/port-gaps-compound-engineering/red-team-*.md`.

### Addressed (updated brainstorm)

| Finding | Severity | Resolution |
|---------|----------|------------|
| Fork drift / no sync strategy | CRITICAL (all 3) | Added upstream sync decision: LLM-assisted periodic merge, will contribute back |
| Licensing/attribution | CRITICAL (GPT-5.2) | Added NOTICE file + README credit for MIT (c) Kieran Klaassen |
| spec-flow-analyzer missing from scope | SERIOUS (Opus) | Added to Workflow agents list (now 23 total) |
| Examples bias LLM outputs | SERIOUS (all 3) | Changed decision: genericize examples during port |
| "Don't install both" unenforceable | SERIOUS (all 3) | Setup command will detect compound-engineering and warn (technical enforcement) |
| deepen-plan discovery searches wrong paths | SERIOUS (Opus) | Added to command update scope |
| Figma drop rationale inconsistent | SERIOUS (GPT-5.2) | Corrected: real blocker is Figma MCP, not agent-browser |
| "One plugin, full power" overstates | SERIOUS (GPT-5.2) | Clarified: all prompts present, external deps need separate setup |

### Considered and Rejected

| Finding | Severity | Why rejected |
|---------|----------|-------------|
| Should be 2.0.0 not 1.1.0 | CRITICAL (GPT-5.2) | Plugin was never published. No users, no scripts, no references to break. |
| Namespace aliasing instead of fork | SERIOUS (Gemini, GPT-5.2) | Claude Code plugins don't support command aliasing or renaming upstream commands. Fork is the only mechanism available. |
| Thin wrapper / proxy agents | SERIOUS (Opus) | Adds complexity without reducing maintenance — still need to maintain wrapper logic AND track upstream changes. Full fork is simpler. |
| Selective fork (Tier 1 only) | MINOR (Opus) | User explicitly chose all 21 agents. Partial fork would leave /review degraded. |
| Generic names may collide more easily | MINOR (Opus) | Acceptable risk. "typescript-reviewer" is descriptive. Collision with another plugin's same-named agent is an edge case. |
| Model field "haiku" may not resolve for all providers | SERIOUS (Gemini) | Claude Code's model field is Claude-ecosystem specific. "haiku" resolves to Claude Haiku. Not a provider-agnostic system. |
| No testing strategy | SERIOUS (Opus) | Valid but out of scope for brainstorm. Testing plan will be part of `/aworkflows:plan`. |

## Directory Structure After Port

```
plugins/compound-workflows/
├── agents/
│   ├── research/
│   │   ├── context-researcher.md        (existing)
│   │   ├── repo-research-analyst.md
│   │   ├── learnings-researcher.md
│   │   ├── best-practices-researcher.md
│   │   ├── framework-docs-researcher.md
│   │   └── git-history-analyzer.md
│   ├── review/
│   │   ├── code-simplicity-reviewer.md
│   │   ├── typescript-reviewer.md        (renamed)
│   │   ├── python-reviewer.md            (renamed)
│   │   ├── pattern-recognition-specialist.md
│   │   ├── architecture-strategist.md
│   │   ├── security-sentinel.md
│   │   ├── performance-oracle.md
│   │   ├── agent-native-reviewer.md
│   │   ├── data-migration-expert.md
│   │   ├── deployment-verification-agent.md
│   │   ├── frontend-races-reviewer.md    (renamed)
│   │   ├── data-integrity-guardian.md
│   │   └── schema-drift-detector.md
│   └── workflow/
│       ├── spec-flow-analyzer.md
│       ├── bug-reproduction-validator.md
│       └── pr-comment-resolver.md
├── commands/
│   └── compound-workflows/
│       ├── brainstorm.md                 (update refs)
│       ├── plan.md                       (update refs)
│       ├── work.md                       (update refs)
│       ├── work-agents.md                (update refs)
│       ├── review.md                     (remove Rails, update renames)
│       ├── compound.md                   (update refs)
│       ├── deepen-plan.md                (update refs)
│       └── setup.md                      (replace with skill approach)
├── skills/
│   ├── disk-persist-agents/SKILL.md      (existing)
│   ├── brainstorming/SKILL.md
│   ├── document-review/SKILL.md
│   ├── file-todos/SKILL.md
│   ├── git-worktree/SKILL.md
│   ├── compound-docs/                    (SKILL.md + assets/ + schema.yaml)
│   ├── setup/SKILL.md                    (replaces command approach)
│   ├── gemini-imagegen/SKILL.md
│   ├── agent-browser/SKILL.md
│   ├── orchestrating-swarms/SKILL.md
│   ├── create-agent-skills/              (SKILL.md + references/ + templates/ + workflows/)
│   ├── agent-native-architecture/        (SKILL.md + 12 reference docs)
│   ├── resolve-pr-parallel/SKILL.md
│   ├── skill-creator/SKILL.md
│   └── frontend-design/SKILL.md
├── CLAUDE.md                             (update counts)
├── README.md                             (update dependency table + attribution)
├── NOTICE                                (compound-engineering MIT attribution)
└── CHANGELOG.md                          (add v1.1.0)
```
