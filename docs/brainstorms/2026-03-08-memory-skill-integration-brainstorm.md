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
- Integrated memory management: compact-prep, recover, and setup aware of memory conventions
- Document knowledge hierarchy in README and setup tutorial
- Setup creates memory/ directory structure with templates
- CLAUDE.md repurposed as memory hot cache; AGENTS.md becomes the project conventions file

## Out of Scope

- Deep integration with brainstorm/plan/work (they already persist to docs/, not memory/)
- Auto-population of memory (stays curator-driven with user approval). Note: auto-promotion/demotion of hot cache items is *not* auto-population — it's housekeeping on existing memory entries. Memory aims to be reasonably automatic; automation handles lifecycle management, humans handle content creation.
- Beads integration with memory entries

# Why This Approach

## Integrated Memory Management (not standalone, not deep)

Memory only works if commands feed it. A standalone skill that nobody invokes is useless. But deep integration (every command writes to memory/) creates confusion about where knowledge goes — brainstorm decisions already go to docs/brainstorms/, plan steps to docs/plans/. The natural boundary:

- **Memory** = cross-cutting knowledge that persists across features (preferences, patterns, terms, people)
- **Docs/** = feature-specific knowledge scoped to one brainstorm/plan/solution

compact-prep and recover are the natural memory touchpoints because they deal with **session lifecycle**, not feature lifecycle. Rationale: user stated "memory captures cross-cutting knowledge, docs/ captures feature-specific knowledge."

## CLAUDE.md as Hot Cache, AGENTS.md as Conventions

The Anthropic skill uses CLAUDE.md as a "hot cache" for frequently-accessed terms. In compound-workflows projects, CLAUDE.md was previously used for project conventions. User decision: **CLAUDE.md contains `@AGENTS.md` pointer + Memory hot cache section.** AGENTS.md holds all project conventions/instructions (full replacement for CLAUDE.md's prior role). This mirrors the existing GEMINI.md pattern — a thin pointer file that delegates to AGENTS.md. Rationale: CLAUDE.md retains its auto-loaded status in Claude Code while keeping conventions in one place (AGENTS.md).

## Dual Framing: Workplace + Engineering

compound-workflows is for general workplace tooling AND engineering. The memory skill must include both workplace examples (people, acronyms, projects, meeting preferences) and engineering examples (architecture decisions, design patterns, codebase conventions, debugging insights). User rationale: "ensure the workplace examples persist, and ensure there are engineering examples as well. this will be used in engineering as well as general workplace use."

# Key Decisions

1. **Integrated memory management** — compact-prep, recover, setup. Not brainstorm/plan/work. Rationale: natural boundary between session-lifecycle (memory) and feature-lifecycle (docs/). "Integrated" because these touchpoints include tiered storage with promotion/demotion suggestions, not just simple writes.

2. **CLAUDE.md = `@AGENTS.md` pointer + memory hot cache** — CLAUDE.md contains an `@AGENTS.md` reference (so conventions are auto-loaded) plus a bounded memory hot cache section (~30 items). Same pattern as GEMINI.md. Rationale: keeps CLAUDE.md auto-loading, avoids two competing hot caches, AGENTS.md holds all conventions.

3. **Setup creates memory/ structure** — directory skeleton with empty templates (glossary.md, context/, etc.) created during `/compound:setup`. Rationale: users have the structure ready to populate organically.

4. **Knowledge hierarchy documented in README + setup tutorial** — brief overview in README, detailed walkthrough in setup. Rationale: both locations serve different audiences (new users vs. active setup).

5. **Fork attribution + licensing** — note in SKILL.md that it's forked from Anthropic's productivity plugin. Verify the Anthropic productivity plugin license permits forking and redistribution before publishing.

6. **Remove `/productivity:start` reference** — replace with compound-workflows equivalent or remove. Setup tutorial handles initialization.

7. **Active hot cache management** — CLAUDE.md memory section must be bounded to prevent unbounded growth. The "hot 30" rule from Anthropic's skill applies.

# Knowledge Hierarchy

```
CLAUDE.md (@AGENTS.md + hot cache) — Pointer to conventions + top ~30 people, terms, active projects. Bounded.
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

Note: this is a default ordering. Freshness matters — a stale memory entry may be less trustworthy than a recent plan. Context-researcher should weigh recency alongside source type.

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
- Added: data classification guidance — personal/sensitive data → `.claude/memory/` (gitignored), project facts → `memory/` (committed). User rationale: people profiles will exist in committed memory, so the skill must guide users on what's safe to commit.

## 2. `/compound:setup` Changes
- Create memory/ directory structure (glossary.md, context/, people/, projects/)
- Seed glossary.md with empty template
- Explain knowledge hierarchy in tutorial walkthrough
- Guide: "AGENTS.md for project conventions, CLAUDE.md for memory hot cache"

## 3. `/compound:compact-prep` Changes
- Step 1 references memory skill conventions for where to write
- **Promotion:** if a term/person/project from memory/ was used frequently this session, *suggest* promoting to CLAUDE.md hot cache (user approves)
- **Demotion:** if CLAUDE.md hot cache exceeds ~30 items, *suggest* demotions (user approves). No automated LRU tracking — simple count check.
- Follows tiered storage: new items go to memory/ by default, promoted to CLAUDE.md only if frequent

## 4. `/compound:recover` Changes
- Phase 5.5 writes extracted memory to memory/ following skill structure
- Uses same tiered format (hot cache vs deep storage)

## 5. README Changes
- Add "Knowledge Architecture" section explaining the hierarchy
- Brief overview, not the full skill reference

## 6. Versioning
- 15 skills (modifying existing memory-management skill, not adding a new one — the byte-for-byte copy already exists)
- v1.6.0 → v1.7.0 (MINOR bump — substantial new behavior even though skill file already exists)

## 7. AGENTS.md Migration
**AGENTS.md migration included** — the CLAUDE.md-as-hot-cache decision requires moving project conventions from CLAUDE.md to AGENTS.md. Include this migration in the same plan. User rationale: "The CLAUDE.md-as-hot-cache decision requires the AGENTS.md migration. Do both in one plan."

## 8. Memory Structure
**Keep Anthropic's memory/ structure** — glossary.md + people/ + projects/ + context/ (organizational backdrop). No renaming or simplification. User rationale: context/ is organizational backdrop, different from project conventions in AGENTS.md. `people/` tracks contributors, roles, domain ownership — relevant for both workplace and engineering use. Setup creates this template structure but users can add any top-level files alongside it (no rigid schema). Setup also suggests where existing organic files might map (e.g., `patterns.md` → `context/`). User rationale: "anything goes" + gentle migration guidance.

# Resolved Questions

1. **How much workplace framing to keep?** — Keep as-is. compound-workflows is general workplace tooling, not just engineering. User rationale: "these are general workplace tools."

2. **Integration depth?** — Integrated memory management (compact-prep, recover, setup). Boundary: memory = cross-cutting knowledge, docs/ = feature-specific knowledge. User rationale: agreed with the boundary. Relabeled from "light" to "integrated" because the compact-prep touchpoint includes tiered storage with promotion/demotion suggestions — more than trivially "light."

3. **Where to document knowledge hierarchy?** — Both README and setup tutorial. User rationale: different audiences.

4. **Setup creates structure or explains only?** — Creates structure with templates. User rationale: "users have the skeleton ready."

5. **CLAUDE.md hot cache conflict?** — CLAUDE.md keeps `@AGENTS.md` pointer + memory hot cache section. Same pattern as GEMINI.md — thin pointer file that delegates to AGENTS.md for conventions. User rationale: "keep CLAUDE.md in repo with the only content being '@AGENTS.md'. same thing is done for GEMINI.md."

6. **Hot cache growth management?** — Active management required. Memory aims to be reasonably automatic — auto-promotion/demotion is housekeeping, not content creation. User stated: "need to ensure hot cache is actively managed to prevent unbounded growth" and "auto-demotion is fine."

7. **Curator-driven vs automatic?** — Not contradictory. "Curator-driven" means humans decide what enters memory (content creation). Auto-promotion/demotion is lifecycle management of existing entries (housekeeping). User rationale: "auto-demotion is fine — it's housekeeping, not content creation. Memory aims to be reasonably automatic."

8. **Three-tier memory system?** — CLAUDE.md (`@AGENTS.md` + hot cache) serves as the auto-loaded tier. `memory/` is deep storage (committed, public). `.claude/memory/` is private preferences (gitignored). The auto-injected `~/.claude/projects/.../memory/MEMORY.md` is a Claude Code system feature — it's the *private* hot cache. CLAUDE.md's memory section is the *project* hot cache (committed, shared). No conflict — different scopes.

9. **Rollback path?** — The CLAUDE.md migration is reversible: move memory hot cache entries back to memory/, restore conventions from AGENTS.md to CLAUDE.md. No one-way door — both files are version-controlled.

10. **Mid-session memory writes?** — Acknowledged as a future enhancement. Currently memory is only written at session boundaries (compact-prep, recover). A mid-session `/compound:memorize <fact>` command could address the bottleneck but is out of scope for this iteration.
