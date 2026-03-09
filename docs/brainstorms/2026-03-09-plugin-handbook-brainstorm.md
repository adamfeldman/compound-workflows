---
title: Plugin Handbook — User-Facing Documentation
date: 2026-03-09
status: active
---

# Plugin Handbook — User-Facing Documentation

## What We're Building

A comprehensive user-facing handbook for the compound-workflows plugin, living at `handbook/` in the repo root. Markdown files readable on GitHub. Covers both audiences: people evaluating whether to install, and existing users who want to configure and get more out of it.

**Structure: Topic-based, flat directory** — one file per topic, no subdirectories. Simple to navigate on GitHub, easy to link to from README.

```
handbook/
├── README.md             # Table of contents + "Start here" orientation
├── getting-started.md    # Install, setup, first workflow walkthrough
├── core-workflow.md      # brainstorm → plan → work → compound cycle
├── commands.md           # All 8 commands with full usage, options, examples
├── skills.md             # All 19 skills with descriptions and when to use
├── agents.md             # All 25 agents — what they do, when they're dispatched
├── configuration.md      # compound-workflows.md settings, all knobs, defaults
├── plugin-qa.md          # plugin-changes-qa: Tier 1/Tier 2, hooks, bead cross-ref
├── architecture.md       # Context-lean, disk-persist, subagent dispatch, flat dispatch
└── troubleshooting.md    # Common issues, recovery, version checking, stale plugins
```

## Why This Approach

**Flat over nested** — the user preferred a simple structure over subdirectories (tutorials/concepts/reference split felt like too much nesting). Each file is self-contained and scannable.

**handbook/ not docs/** — `docs/` already contains development artifacts (plans, brainstorms, solutions). The handbook is user-facing content, separate concern. "Handbook" was preferred terminology over "guide" — conveys comprehensiveness.

**README stays as-is** — the plugin README.md keeps its current overview role. The handbook goes deeper on every topic. README can link to handbook sections but doesn't slim down.

**Comprehensive** — document everything: every command, every setting, every workflow. The plugin has significant surface area (8 commands, 19 skills, 25 agents, config system, QA pipeline, red team, plan readiness) and much of the knowledge is currently scattered across CLAUDE.md (developer-facing), memory files (session-specific), and skill files (inline in prompts). Users shouldn't need to read SKILL.md to understand what a feature does.

## Key Decisions

### Decision 1: Audience is both evaluators and existing users
Getting-started.md serves evaluators (what is this, why use it, install). Other files serve existing users (config, workflows, troubleshooting). Rationale: the repo is public and people will find it from different starting points.

### Decision 2: Consolidated reference files, not one-per-item
Commands.md covers all 8 commands in one file. Skills.md covers all 19 skills. Agents.md covers all 25 agents. Rationale: fewer files are easier to search within, and the total count per category is manageable (not 100+).

### Decision 3: Separate architecture.md from practical guides
Architecture concepts (context-lean, disk-persist, flat dispatch) get their own file rather than being woven into every topic. Rationale: users who want to understand WHY things work a certain way can go deep; users who just want to USE commands don't need to read architecture first.

### Decision 4: configuration.md is the settings reference
All knobs and their defaults documented in one place. Currently this info is split across: compound-workflows.md config format, setup.md (which creates the config), CLAUDE.md (which references config keys), and individual commands (which read specific keys). Rationale: user asked "what does provenance settings do?" — this info should be findable.

## Resolved Questions

### Q: How to handle cross-cutting concepts like "context-lean"?
**Answer:** architecture.md covers the concepts. Other files reference architecture.md via markdown links where relevant (e.g., commands.md can say "see [architecture](architecture.md#context-lean) for why agents return summaries instead of full output"). Some repetition is acceptable for readability — each file should be understandable on its own.

### Q: What about versioning the docs?
**Answer:** The handbook lives in the repo and versioned with git. No separate versioning scheme. The handbook content aligns to the current plugin version. CHANGELOG.md tracks feature changes; handbook updates happen alongside feature changes.

### Q: Should the handbook be auto-generated or hand-written?
**Answer:** Hand-written. Auto-generation was considered but dropped — the structured data (frontmatter, plugin.json) isn't consistent enough to extract from, and there's no enforcement mechanism (CI gate, pre-commit hook) to keep generated content in sync. Add QA checks later if drift becomes a problem. Rationale: simpler to start, and the current frontmatter schema would need standardization work before auto-extraction is viable.

### Q: Does the handbook warrant its own release version bump?
**Answer:** No. The handbook is outside `plugins/` directory. Only bump version when plugin code changes. Docs are updated alongside features in the same or semi-adjacent commits. Doc-only changes don't trigger releases on their own.

### Q: How should plan readiness settings be documented?
**Answer:** Split. `configuration.md` is the single reference for ALL config keys (including plan readiness keys like `provenance_expiry_days`) with brief descriptions and defaults. `core-workflow.md` covers when/why plan readiness runs and what each setting controls in context. `plugin-qa.md` covers only the plugin QA system (Tier 1/Tier 2 scripts, PostToolUse hook, bead cross-ref), not plan readiness. Rationale: plan readiness is part of the plan→work lifecycle, not the plugin QA pipeline.

### Decision 5: Document command autocomplete shortcuts
The handbook should tell users they can type short prefixes like `/prep` or `/work` and use autocomplete instead of typing full command names like `/compound:compact-prep`. This is a Claude Code feature (tab/autocomplete on `/` commands) but users won't discover it without being told. Rationale: the full command names are verbose — showing shortcuts reduces friction for daily use.

### Decision 6: Add /compound:help command
A `/compound:help` command that links to the handbook on GitHub, providing in-CLI discoverability. Also: post-setup hint in `/compound:setup` mentioning the handbook exists. Rationale: the handbook is static GitHub markdown — users need a way to discover it from within Claude Code.

### Decision 7: handbook/ stays at repo root despite not shipping with plugin
All 3 red team providers flagged that `handbook/` at repo root won't be included in marketplace installs. Rejected because: GitHub is the reading surface for docs, not the local filesystem. Nobody reads plugin docs from `~/.claude/plugins/`. The `/compound:help` command (Decision 6) bridges the discoverability gap.

### Decision 8: README keeps current content, accept overlap
README maintains its overview role (command tables, workflow cycle, architecture summary). Handbook goes deeper. Some duplication is accepted as the cost of two entry points. Rationale: the README serves people who land on the GitHub repo; the handbook serves people who want depth. Different contexts, overlapping content is OK.

### Decision 9: Docs serve the author too, not premature
Opus flagged "no demonstrated user need" for a single-user plugin. Rejected: the handbook consolidates scattered knowledge from CLAUDE.md, memory files, and SKILL.md into a findable reference. It serves the author after context compaction and prepares for future users. There is also 1 external user currently.

### Decision 10: Research agents disagreed on location — acknowledged
Research agents proposed three different locations: expand README (context-research), `plugins/.../docs/` (repo-research), and `handbook/` at repo root (brainstorm). The brainstorm chose repo root based on user preference during collaborative dialogue. Research informed the options but the user made the call.

## Red Team Resolution Summary

| # | Provider(s) | Severity | Finding | Resolution |
|---|-------------|----------|---------|------------|
| 1 | All 3 | CRITICAL | handbook/ at root won't ship with plugin | Rejected: GitHub is reading surface, /compound:help bridges gap |
| 2 | All 3 | SERIOUS | Auto-gen has no enforcement mechanism | Valid: dropped auto-gen, hand-write all |
| 3 | Gemini, OpenAI | SERIOUS | README overlap risks drift | Rejected: accept overlap, different contexts |
| 4 | Opus | SERIOUS | No demonstrated user need | Rejected: docs serve author too, 1 external user exists |
| 5 | OpenAI, Opus | SERIOUS | Two-audience design underspecified | Acknowledged: getting-started.md kept, goes deeper than README |
| 6 | Opus | MINOR | Flat structure may not scale | Acknowledged: 500 lines is manageable, split later if needed |
| 7 | Opus | MINOR | Versioning dodge = distribution problem | Addressed: /compound:help command bridges gap |
| 8 | Gemini, Opus | MINOR | No in-CLI discoverability | Addressed: /compound:help + post-setup hint |
| 9 | OpenAI | MINOR | Version alignment wording contradiction | Fixed: clarified "semi-adjacent commits, no standalone releases" |
| 10 | Opus | MINOR | Research disagreements not reconciled | Fixed: added Decision 10 acknowledging divergent proposals |

## Sources

- Context research: `.workflows/brainstorm-research/plugin-user-docs/context-research.md`
- Repo research: `.workflows/brainstorm-research/plugin-user-docs/repo-research.md`
- Red team (Gemini): `.workflows/brainstorm-research/plugin-user-docs/red-team--gemini.md`
- Red team (OpenAI): `.workflows/brainstorm-research/plugin-user-docs/red-team--openai.md`
- Red team (Opus): `.workflows/brainstorm-research/plugin-user-docs/red-team--opus.md`
- Existing README: `plugins/compound-workflows/README.md`
- Developer docs: `plugins/compound-workflows/CLAUDE.md`
- Config system: `plugins/compound-workflows/commands/compound/setup.md`
