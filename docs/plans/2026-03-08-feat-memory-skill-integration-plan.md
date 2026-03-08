---
title: "feat: Memory Skill Integration"
type: feat
status: active
date: 2026-03-08
origin: docs/brainstorms/2026-03-08-memory-skill-integration-brainstorm.md
---

# Memory Skill Integration

Fork Anthropic's memory-management skill into compound-workflows as a first-class skill. Integrate with compact-prep, recover, and setup. Migrate CLAUDE.md to `@AGENTS.md` pointer + memory hot cache. Dogfood the pattern in this repo.

## Background

The memory-management skill already exists as a byte-for-byte copy of Anthropic's productivity plugin (`plugins/compound-workflows/skills/memory-management/SKILL.md`). This plan adapts it for compound-workflows' knowledge hierarchy and integrates it with session-lifecycle commands.

Key architectural decisions (see brainstorm: `docs/brainstorms/2026-03-08-memory-skill-integration-brainstorm.md`):
- **Integrated memory management** — compact-prep, recover, setup. Not brainstorm/plan/work. Boundary: memory = cross-cutting knowledge, docs/ = feature-specific.
- **CLAUDE.md = `@AGENTS.md` + hot cache** — thin pointer file + bounded memory section (~30 items per category). `@AGENTS.md` auto-includes conventions.
- **Dual framing** — workplace AND engineering examples throughout.
- **Curator-driven content, automatic lifecycle** — humans decide what enters memory; automation handles promotion/demotion suggestions.
- **Data classification** — committed `memory/` for project facts, gitignored `.claude/memory/` for sensitive/personal data.

## Acceptance Criteria

- [ ] SKILL.md adapted with engineering examples, data classification, fork attribution, `@AGENTS.md` framing
- [ ] Setup creates `memory/` subdirectory structure with templates
- [ ] Setup creates CLAUDE.md (`@AGENTS.md` + empty hot cache) when none exists
- [ ] Setup offers to migrate existing CLAUDE.md conventions to AGENTS.md
- [ ] Compact-prep Step 1 suggests promotions/demotions (user approves)
- [ ] Recover Phase 5.5 writes to `memory/` following skill structure
- [ ] README has Knowledge Architecture section
- [ ] This repo has root CLAUDE.md with `@AGENTS.md` + hot cache (dogfood)
- [ ] Version bumped to 1.7.0 across all version files
- [ ] License verified for Anthropic productivity plugin fork

## Implementation Steps

### Step 1: Adapt SKILL.md
**Files:** `plugins/compound-workflows/skills/memory-management/SKILL.md`
**Depends on:** nothing (defines conventions all other steps reference)

This is the foundation — all subsequent steps reference the adapted skill's conventions.

- [ ] Add fork attribution header (forked from Anthropic's productivity plugin, note license)
- [ ] Replace `/productivity:start` reference (line 287) with: "Run `/compound:setup` to create the memory/ directory structure. Memory populates organically through work sessions, with `/compound:compact-prep` maintaining the hot cache at session boundaries."
- [ ] Adapt CLAUDE.md references to describe the `@AGENTS.md` pointer pattern: CLAUDE.md contains `@AGENTS.md` (auto-loads conventions) plus a memory hot cache section
- [ ] Add engineering examples alongside existing workplace examples:
  - People: "Alex Chen — backend lead, owns auth service" alongside "Todd Martinez — VP Sales"
  - Terms: "DDD — domain-driven design, used in services layer" alongside "PSR — pipeline status report"
  - Projects: "API v3 migration — breaking changes to REST endpoints" alongside "Phoenix — CRM migration"
- [ ] Add data classification section — new section "Committed vs. Private Memory":
  - Safe to commit (`memory/`): project codenames, team structure, acronyms, architectural decisions, tool conventions, people's names and roles
  - Keep private (`.claude/memory/`): salary data, performance reviews, personal contact info, medical information, credentials/tokens, personal preferences about individuals
- [ ] Add dual framing throughout — ensure skill description mentions both workplace and engineering use cases
- [ ] Keep unchanged: tiered lookup flow, table format, directory structure (glossary.md, people/, projects/, context/), hot 30 rule, file naming conventions
- [ ] No frontmatter flags added — Claude can auto-load the skill for passive convention learning

**Reference files to read:**
- Current SKILL.md: `plugins/compound-workflows/skills/memory-management/SKILL.md`
- Anthropic source (for comparison): `~/.claude/plugins/cache/knowledge-work-plugins/productivity/1.1.0/skills/memory-management/SKILL.md`
- Brainstorm: `docs/brainstorms/2026-03-08-memory-skill-integration-brainstorm.md`

**Commit:** `feat(memory): adapt memory-management skill for compound-workflows`

---

### Step 2: Update Setup Command
**Files:** `plugins/compound-workflows/commands/compound/setup.md`
**Depends on:** Step 1 (references skill conventions for structure and tutorial content)

Setup gains three new capabilities: create memory subdirectory structure, explain knowledge hierarchy, and handle CLAUDE.md/AGENTS.md creation/migration.

#### Step 2a: Memory directory structure (in Step 6 directory creation)
- [ ] Create `memory/glossary.md` with empty template: section headers (## Acronyms, ## Internal Terms, ## Project Codenames, ## Nicknames) with empty tables and one commented-out example row per table showing the format
- [ ] Create `memory/context/` directory (organizational backdrop — company, team, tools)
- [ ] Create `memory/people/` directory (individual profiles and roles)
- [ ] Create `memory/projects/` directory (project details and status)
- [ ] Handle existing organic files gracefully: if `memory/project.md` or `memory/patterns.md` exist, print migration suggestion (e.g., "Consider moving `patterns.md` to `context/patterns.md`") — do not auto-migrate, do not use AskUserQuestion (avoid friction)
- [ ] Skip creation for any directory/file that already exists (idempotent)

#### Step 2b: Knowledge hierarchy in tutorial walkthrough (in Step 6)
- [ ] Expand the `memory/` one-liner to explain the full knowledge hierarchy:
  ```
  CLAUDE.md        @AGENTS.md pointer + memory hot cache (~30 items, bounded)
  memory/          Deep storage for cross-cutting knowledge (people, terms, patterns)
    glossary.md    Full decoder ring — acronyms, terms, codenames
    context/       Organizational backdrop — company, team, tools
    people/        Individual profiles and roles
    projects/      Project details and status
  docs/            Feature-specific knowledge (brainstorms → plans → solutions)
  .workflows/      Research artifacts, ephemeral per workflow
  resources/       External reference material
  ```
- [ ] Add brief explanation: "Memory captures cross-cutting knowledge that persists across features. Feature-specific knowledge goes in docs/."

#### Step 2c: CLAUDE.md/AGENTS.md handling (new sub-step in Step 6, after directory creation)
- [ ] If no CLAUDE.md exists: create it with `@AGENTS.md` pointer + empty memory hot cache section:
  ```markdown
  @AGENTS.md

  # Memory

  <!-- Hot cache: ~30 items per category. Managed by /compound:compact-prep. -->
  <!-- See memory/ for deep storage. See memory-management skill for conventions. -->
  ```
- [ ] If CLAUDE.md exists: offer migration via AskUserQuestion: "Existing CLAUDE.md has project conventions. Move them to AGENTS.md and convert CLAUDE.md to memory hot cache?"
  - **Yes** — read CLAUDE.md content, write to AGENTS.md (append or create), replace CLAUDE.md with pointer + empty hot cache
  - **No** — leave as-is, print guidance: "When ready, move conventions to AGENTS.md and add `@AGENTS.md` to CLAUDE.md."
- [ ] If no AGENTS.md exists: create minimal AGENTS.md with project name header and placeholder for conventions
- [ ] If AGENTS.md exists: leave it alone

**Reference files to read:**
- Current setup.md: `plugins/compound-workflows/commands/compound/setup.md`
- Adapted SKILL.md (from Step 1)
- Brainstorm knowledge hierarchy section

**Commit:** `feat(setup): create memory structure, knowledge hierarchy tutorial, CLAUDE.md handling`

---

### Step 3: Update Compact-Prep Command
**Files:** `plugins/compound-workflows/commands/compound/compact-prep.md`
**Depends on:** Step 1 (references skill conventions for writes and format)

Compact-prep Step 1 gains promotion/demotion sub-steps. The existing "Update Memory" step already writes to `memory/` — this adds tiered storage awareness and hot cache lifecycle management.

- [ ] Update Step 1 preamble to reference memory skill conventions for file structure (glossary.md for terms, people/ for people, etc.)
- [ ] Add Step 1a — Promotion check (after memory writes):
  - Scan the session for terms/people/projects from `memory/` that were referenced 3+ times in user messages
  - If candidates found, present as batch AskUserQuestion: "These memory items were used frequently this session. Promote to CLAUDE.md hot cache?" with options: Approve all / Review individually / Skip
  - If CLAUDE.md doesn't exist, skip promotion silently (setup hasn't run yet)
  - Write promoted items to CLAUDE.md memory section following skill's table format
- [ ] Add Step 1b — Demotion check (after promotion):
  - Count items in CLAUDE.md memory section (all categories combined)
  - If total exceeds ~30 items, suggest demotions: "CLAUDE.md hot cache has N items (target: ~30). Suggest removing these items? [list items not referenced this session]"
  - Batch AskUserQuestion with same options as promotion
  - Demoted items remain in `memory/` (they're never deleted, just removed from hot cache)
  - If CLAUDE.md doesn't exist or has no memory section, skip silently
- [ ] Handle gracefully: no `memory/` directory (skip tiered writes, write to `memory/` root as before), no CLAUDE.md (skip promotion/demotion), empty hot cache (create table structure on first promotion)

**Reference files to read:**
- Current compact-prep.md: `plugins/compound-workflows/commands/compound/compact-prep.md`
- Adapted SKILL.md (from Step 1) — specifically the table format and tiered lookup sections

**Commit:** `feat(compact-prep): add memory promotion/demotion to Step 1`

---

### Step 4: Update Recover Command
**Files:** `plugins/compound-workflows/commands/compound/recover.md`
**Depends on:** Step 1 (references skill conventions for Phase 5.5 writes)

Minor update — recover Phase 5.5 already writes to `memory/`. Just needs explicit reference to skill structure.

- [ ] Update Phase 5.5 Step 5.5.2 to specify: write terms to `memory/glossary.md`, people to `memory/people/`, project info to `memory/projects/`, organizational context to `memory/context/`
- [ ] Add note: "If memory/ subdirectories don't exist (setup hasn't run), write to memory/ root following flat file format. Structure is preferred but not required."
- [ ] No promotion to CLAUDE.md hot cache — recover is emergency preservation, not optimization. Promotion happens at next compact-prep.

**Reference files to read:**
- Current recover.md: `plugins/compound-workflows/commands/compound/recover.md`
- Adapted SKILL.md (from Step 1)

**Commit:** `feat(recover): reference memory skill structure in Phase 5.5`

---

### Step 5: Update Command References
**Files:** `plugins/compound-workflows/commands/compound/setup.md` (line 307)
**Depends on:** Steps 1-4 (all command changes complete)

Post-migration cleanup of CLAUDE.md references in commands.

- [ ] Update `setup.md` line 307: change "General project instructions belong in CLAUDE.md or AGENTS.md" to "General project instructions belong in AGENTS.md" (CLAUDE.md is now memory hot cache, not conventions)
- [ ] Review `work.md` line 214: "Read CLAUDE.md and AGENTS.md for project conventions" — leave as-is (harmless, `@AGENTS.md` pointer makes CLAUDE.md effectively include AGENTS.md)
- [ ] Leave agent references unchanged (they work correctly with the `@AGENTS.md` pattern)

**Commit:** `chore: update CLAUDE.md references post-migration`

---

### Step 6: Add Knowledge Architecture to README
**Files:** `plugins/compound-workflows/README.md`
**Depends on:** Step 1 (references the hierarchy that the skill defines)
**Can parallel with:** Step 5

- [ ] Add "Knowledge Architecture" section after "Key Concept: Disk-Persisted Agents" and before "Attribution"
- [ ] Include the hierarchy diagram (CLAUDE.md → memory/ → docs/ → .workflows/ → resources/) with brief descriptions
- [ ] Include trust hierarchy one-liner: "Solutions (validated) > Memory (reference) > Plans (actionable) > Resources (reference) > Brainstorms (exploratory)"
- [ ] Add freshness caveat: "Recency matters — a stale memory entry may be less trustworthy than a recent plan."
- [ ] Keep it brief — 15-20 lines max. The skill and setup tutorial have the full details.

**Reference files to read:**
- Current README.md: `plugins/compound-workflows/README.md`
- Brainstorm knowledge hierarchy section

**Commit:** `docs(readme): add Knowledge Architecture section`

---

### Step 7: Dogfood in This Repo
**Files:** `CLAUDE.md` (new, at repo root)
**Depends on:** Steps 1-6 (pattern is finalized)

This plugin source repo creates a root CLAUDE.md following the pattern it teaches users.

- [ ] Create root `CLAUDE.md` with:
  ```markdown
  @AGENTS.md

  # Memory

  <!-- Hot cache: ~30 items per category. Managed by /compound:compact-prep. -->
  <!-- See memory/ for deep storage. See memory-management skill for conventions. -->
  ```
- [ ] Leave root `AGENTS.md` as-is (already serves as conventions file)
- [ ] Leave `plugins/compound-workflows/CLAUDE.md` as-is (plugin development instructions, separate concern)
- [ ] Leave existing `memory/project.md` and `memory/patterns.md` in place (organic files coexist with template structure)

**Commit:** `chore: dogfood CLAUDE.md @AGENTS.md + hot cache pattern`

---

### Step 8: Version Bump and Release
**Files:** `plugins/compound-workflows/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `plugins/compound-workflows/CHANGELOG.md`, `plugins/compound-workflows/README.md`, `plugins/compound-workflows/CLAUDE.md`, `AGENTS.md`, `memory/project.md`
**Depends on:** Steps 1-7 (all changes complete)

- [ ] Bump `plugin.json` version: 1.6.0 → 1.7.0
- [ ] Bump `marketplace.json` version: 1.6.0 → 1.7.0 (ref updated after tagging)
- [ ] Add `[1.7.0]` section to CHANGELOG.md documenting: memory skill adaptation, setup memory structure, compact-prep promotion/demotion, recover Phase 5.5 structure, README knowledge architecture, CLAUDE.md migration pattern
- [ ] Verify counts across all files: 22 agents, 15 skills, 9 commands (no count changes)
- [ ] Update `memory/project.md` version reference
- [ ] Verify Anthropic productivity plugin license permits forking — add license note to fork attribution in SKILL.md if required

**Commit:** `chore: bump to v1.7.0, update changelog`

## Open Questions

None — all questions resolved during brainstorm and planning research gates.

## Work-Readiness Notes

- **Step ordering:** Steps 1 must complete first (defines conventions). Steps 2-4 depend on Step 1 but are independent of each other. Steps 5+6 can parallel. Step 7 depends on 1-6. Step 8 is last.
- **Parallelization opportunities:** Steps 3+4 touch separate files (compact-prep.md vs recover.md) and can dispatch in parallel. Steps 5+6 can parallel (setup.md line update vs README section).
- **Step 2 is the largest** — setup.md changes span three sub-areas (directory structure, tutorial content, CLAUDE.md handling). Consider splitting into sub-issues during `/compound:work` setup.
- **Reference data:** Every step needs the adapted SKILL.md from Step 1. Subagents should read it from disk, not receive it inline.
- **Single-file constraint:** Steps 3 and 4 are single-file edits. Steps 1 and 2 are also single-file but larger.

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-03-08-memory-skill-integration-brainstorm.md` — integrated memory management, CLAUDE.md `@AGENTS.md` pattern, dual workplace+engineering framing, curator-driven content with automatic lifecycle, data classification
- **Repo research:** `.workflows/plan-research/memory-skill-integration/agents/repo-research.md`
- **Learnings:** `.workflows/plan-research/memory-skill-integration/agents/learnings.md`
- **Specflow analysis:** `.workflows/plan-research/memory-skill-integration/agents/specflow.md`
- **Red team outputs:** `.workflows/brainstorm-research/memory-skill-integration/red-team--{gemini,openai,opus}.md`
- **Anthropic source skill:** `~/.claude/plugins/cache/knowledge-work-plugins/productivity/1.1.0/skills/memory-management/SKILL.md`
