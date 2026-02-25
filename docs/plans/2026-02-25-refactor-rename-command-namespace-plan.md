---
title: "Rename command namespace from compound-workflows to compound"
type: refactor
status: completed
date: 2026-02-25
---

# Rename Command Namespace: `compound-workflows:*` → `compound:*`

## Problem

The current command namespace `/compound-workflows:brainstorm` is verbose and annoying to type. Users want shorter slash commands. The prefix `compound:` is shorter and still descriptive.

## Scope

### What changes

1. **Directory rename**: `commands/compound-workflows/` → `commands/compound/`
2. **YAML `name:` fields**: All 7 commands updated (`compound-workflows:X` → `compound:X`)
3. **Text references**: All `/compound-workflows:X` → `/compound:X` across the plugin (~93 occurrences in 21 files)
4. **Directory path references**: `commands/compound-workflows/` → `commands/compound/` in docs

### What does NOT change

- Plugin name stays `compound-workflows` (in `plugin.json` and `marketplace.json`)
- Plugin directory stays `plugins/compound-workflows/`
- Config file stays `compound-workflows.local.md`
- Agent/skill content unchanged (only command references in their text)

## Implementation

### Phase 1: Directory rename and YAML updates

- [ ] `git mv commands/compound-workflows/ commands/compound/`
- [ ] Update YAML `name:` field in all 7 commands:
  - `brainstorm.md`: `compound-workflows:brainstorm` → `compound:brainstorm`
  - `plan.md`: `compound-workflows:plan` → `compound:plan`
  - `work.md`: `compound-workflows:work` → `compound:work`
  - `review.md`: `compound-workflows:review` → `compound:review`
  - `compound.md`: `compound-workflows:compound` → `compound:compound`
  - `deepen-plan.md`: `compound-workflows:deepen-plan` → `compound:deepen-plan`
  - `setup.md`: `compound-workflows:setup` → `compound:setup`

### Phase 2: Bulk text replacement across all files

Find-and-replace `/compound-workflows:` → `/compound:` across all 21 files that contain the pattern. Files affected:

**Commands (7 files):**
- `commands/compound/brainstorm.md` (5 refs)
- `commands/compound/plan.md` (5 refs)
- `commands/compound/work.md` (2 refs)
- `commands/compound/review.md` (1 ref)
- `commands/compound/compound.md` (3 refs)
- `commands/compound/deepen-plan.md` (3 refs)
- `commands/compound/setup.md` (7 refs)

**Skills (4 files):**
- `skills/setup/SKILL.md` (2 refs)
- `skills/document-review/SKILL.md` (1 ref)
- `skills/brainstorming/SKILL.md` (3 refs)
- `skills/file-todos/SKILL.md` (1 ref)

**Agents (3 files):**
- `agents/research/git-history-analyzer.md` (1 ref)
- `agents/research/learnings-researcher.md` (2 refs)
- `agents/review/code-simplicity-reviewer.md` (1 ref)

**Docs/config (5 files):**
- `CLAUDE.md` (4 refs + 1 directory path ref)
- `README.md` (15 refs)
- `CHANGELOG.md` (7 refs)
- `FORK-MANIFEST.yaml` (1 ref)
- `skills/orchestrating-swarms/SKILL.md` (19 refs — these are `compound-workflows:` namespace refs scattered throughout)

**Historical plans (2 files — update for consistency):**
- `docs/plans/2026-02-25-plugin-qa-and-publish-plan.md` (3 refs + 13 dir path refs)
- `docs/plans/2026-02-25-plugin-packaging-plan.md` (7 refs + 2 dir path refs)

### Phase 3: Directory path references

Update `commands/compound-workflows/` → `commands/compound/` in:
- `CLAUDE.md` (directory structure section)
- `docs/plans/2026-02-25-plugin-qa-and-publish-plan.md`
- `docs/plans/2026-02-25-plugin-packaging-plan.md`

### Phase 4: Documentation updates

- [ ] `CLAUDE.md`: Update directory structure, command references
- [ ] `README.md`: Update all command table and usage references
- [ ] `CHANGELOG.md`: Add entry for namespace rename
- [ ] Version bump in `plugin.json`: `1.1.0` → `1.2.0` (MINOR — no published users to break)
- [ ] Update `marketplace.json` description if it references commands

## Verification

- [ ] `grep -r "compound-workflows:" plugins/compound-workflows/` returns 0 results (excluding `compound-workflows.local.md` config references)
- [ ] All 7 commands have correct `name: compound:*` in YAML frontmatter
- [ ] Directory `commands/compound/` exists, `commands/compound-workflows/` does not
- [ ] `plugin.json` version is `1.2.0`

## Notes

- The `compound-workflows.local.md` config filename intentionally stays unchanged — it's the plugin config, not a command namespace
- `compound-workflows` as a plugin name/directory stays unchanged
- Grep for `compound-workflows:` should have zero results after this change (the string `compound-workflows.` will still exist for config file references — that's expected)
