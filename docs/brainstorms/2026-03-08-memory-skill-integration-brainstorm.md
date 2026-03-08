---
title: "Memory Skill Integration into compound-workflows"
date: 2026-03-08
type: feature
status: active
tags: [memory, skill, knowledge-hierarchy, CLAUDE.md, AGENTS.md]
---

# What We're Building

Fork Anthropic's memory-management skill (from the productivity plugin) into compound-workflows as a first-class skill. Integrate it with existing commands (compact-prep, recover, setup) and document the knowledge hierarchy that explains how memory relates to brainstorms, plans, solutions, and research artifacts.

## Scope

- Fork and adapt the memory-management SKILL.md
- Light integration: compact-prep, recover, and setup aware of memory conventions
- Document knowledge hierarchy in README and setup tutorial
- Setup creates memory/ directory structure with templates
- CLAUDE.md repurposed as memory hot cache; AGENTS.md becomes the project conventions file

## Out of Scope

- Deep integration with brainstorm/plan/work (they already persist to docs/, not memory/)
- Auto-population of memory (stays curator-driven with user approval)
- Beads integration with memory entries

# Why This Approach

## Light Integration (not standalone, not deep)

Memory only works if commands feed it. A standalone skill that nobody invokes is useless. But deep integration (every command writes to memory/) creates confusion about where knowledge goes — brainstorm decisions already go to docs/brainstorms/, plan steps to docs/plans/. The natural boundary:

- **Memory** = cross-cutting knowledge that persists across features (preferences, patterns, terms, people)
- **Docs/** = feature-specific knowledge scoped to one brainstorm/plan/solution

compact-prep and recover are the natural memory touchpoints because they deal with **session lifecycle**, not feature lifecycle. Rationale: user stated "memory captures cross-cutting knowledge, docs/ captures feature-specific knowledge."

## CLAUDE.md as Hot Cache, AGENTS.md as Conventions

The Anthropic skill uses CLAUDE.md as a "hot cache" for frequently-accessed terms. In compound-workflows projects, CLAUDE.md was previously used for project conventions. User decision: **AGENTS.md is a full replacement for CLAUDE.md** for project conventions/instructions. CLAUDE.md becomes purely a memory hot cache (~30 people/terms/projects, bounded). Rationale: clean separation of concerns, AGENTS.md is already read by Claude Code for project guidance.

## Keep Workplace Framing

compound-workflows is for general workplace tooling, not just engineering. The memory skill's workplace examples (people, acronyms, projects) fit naturally. User confirmed: "these are general workplace tools."

# Key Decisions

1. **Light integration scope** — compact-prep, recover, setup. Not brainstorm/plan/work. Rationale: natural boundary between session-lifecycle (memory) and feature-lifecycle (docs/).

2. **CLAUDE.md = memory hot cache** — repurpose CLAUDE.md as bounded hot cache (~30 items). AGENTS.md takes over as the project conventions file. Rationale: user stated "AGENTS.md is a full replacement for CLAUDE.md."

3. **Setup creates memory/ structure** — directory skeleton with empty templates (glossary.md, context/, etc.) created during `/compound:setup`. Rationale: users have the structure ready to populate organically.

4. **Knowledge hierarchy documented in README + setup tutorial** — brief overview in README, detailed walkthrough in setup. Rationale: both locations serve different audiences (new users vs. active setup).

5. **Fork attribution** — note in SKILL.md that it's forked from Anthropic's productivity plugin.

6. **Remove `/productivity:start` reference** — replace with compound-workflows equivalent or remove. Setup tutorial handles initialization.

7. **Active hot cache management** — CLAUDE.md memory section must be bounded to prevent unbounded growth. The "hot 30" rule from Anthropic's skill applies.

# Knowledge Hierarchy

```
CLAUDE.md (hot cache)     — Top ~30 people, terms, active projects. Bounded.
memory/                   — Deep storage. Grows indefinitely.
  glossary.md             — Full decoder ring (terms, acronyms, people, codenames)
  context/                — Company/team/tools context
  people/                 — Individual profiles
  projects/               — Project details
docs/brainstorms/         — Feature explorations (point-in-time decisions)
docs/plans/               — Implementation roadmaps (derived from brainstorms)
docs/solutions/           — Post-implementation learnings (compound output)
docs/decisions/           — Deliberate choice records between alternatives
.workflows/               — Research artifacts, agent outputs (ephemeral per workflow)
resources/                — External reference material
```

**Trust hierarchy** (used by context-researcher):
Solutions (validated) > Memory (reference) > Plans (actionable) > Resources (reference) > Brainstorms (exploratory)

**Memory flow:**
- compact-prep (Step 1) — planned save before compaction, writes to memory/ following skill conventions
- recover (Phase 5.5) — emergency save for dead sessions, writes to memory/ following skill conventions
- setup — creates memory/ directory structure with templates
- context-researcher — reads memory/ alongside other knowledge sources

# Integration Changes

## 1. New Skill: `skills/memory-management/SKILL.md`
- Forked from Anthropic's productivity plugin
- Adapted: CLAUDE.md hot cache section describes the compound-workflows model
- Adapted: remove `/productivity:start` reference
- Adapted: add fork attribution
- Adapted: reference AGENTS.md as conventions file, CLAUDE.md as memory only
- Keep: workplace examples, tiered lookup, glossary format, people/projects structure

## 2. `/compound:setup` Changes
- Create memory/ directory structure (glossary.md, context/, people/, projects/)
- Seed glossary.md with empty template
- Explain knowledge hierarchy in tutorial walkthrough
- Guide: "AGENTS.md for project conventions, CLAUDE.md for memory hot cache"

## 3. `/compound:compact-prep` Changes
- Step 1 references memory skill conventions for where to write
- **Promotion:** if a term/person/project from memory/ was used frequently this session, promote to CLAUDE.md hot cache
- **Demotion:** if a CLAUDE.md hot cache item hasn't been referenced in recent sessions, demote to memory/ only
- **Growth check:** after updates, verify CLAUDE.md memory section stays within bounds (~30 items per category). If over, demote least-recently-used items automatically.
- Follows tiered storage: new items go to memory/ by default, promoted to CLAUDE.md only if frequent

## 4. `/compound:recover` Changes
- Phase 5.5 writes extracted memory to memory/ following skill structure
- Uses same tiered format (hot cache vs deep storage)

## 5. README Changes
- Add "Knowledge Architecture" section explaining the hierarchy
- Brief overview, not the full skill reference

## 6. Versioning
- 15 → 16 skills
- v1.6.0 → v1.7.0 (new skill = MINOR bump)

7. **AGENTS.md migration included** — the CLAUDE.md-as-hot-cache decision requires moving project conventions from CLAUDE.md to AGENTS.md. Include this migration in the same plan. User rationale: "The CLAUDE.md-as-hot-cache decision requires the AGENTS.md migration. Do both in one plan."

8. **Keep Anthropic's memory/ structure** — glossary.md + people/ + projects/ + context/ (organizational backdrop). No renaming or simplification. User rationale: context/ is organizational backdrop, different from project conventions in AGENTS.md.

# Resolved Questions

1. **How much workplace framing to keep?** — Keep as-is. compound-workflows is general workplace tooling, not just engineering. User rationale: "these are general workplace tools."

2. **Integration depth?** — Light integration (compact-prep, recover, setup). Boundary: memory = cross-cutting knowledge, docs/ = feature-specific knowledge. User rationale: agreed with the boundary and chose light integration.

3. **Where to document knowledge hierarchy?** — Both README and setup tutorial. User rationale: different audiences.

4. **Setup creates structure or explains only?** — Creates structure with templates. User rationale: "users have the skeleton ready."

5. **CLAUDE.md hot cache conflict?** — CLAUDE.md becomes memory-only. AGENTS.md replaces CLAUDE.md for project conventions. User rationale: "AGENTS.md is a full replacement for CLAUDE.md."

6. **Hot cache growth management?** — Active management required. User stated: "need to ensure hot cache is actively managed to prevent unbounded growth."
