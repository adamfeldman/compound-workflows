---
title: "QA, Fix, and Publish compound-workflows Plugin"
type: feat
status: active
date: 2026-02-25
origin: docs/plans/2026-02-25-plugin-packaging-plan.md
---

# Plan: QA, Fix, and Publish compound-workflows Plugin

## Context

The compound-workflows plugin was scaffolded and all files were ported in a prior session. The plugin is locally committed at `~/Dev/compound-workflows-marketplace/` with 16 files across 2 commits. It has NOT been published to GitHub or tested via `claude /install`.

This plan covers the remaining work: quality review of ported commands, fixes for any issues found, GitHub publication, and installation testing.

## What Was Already Done (Prior Session)

### Phase 0: Scaffold — COMPLETE
- Created full directory tree at `~/Dev/compound-workflows-marketplace/`
- Wrote `.claude-plugin/marketplace.json` (marketplace wrapper)
- Wrote `plugins/compound-workflows/.claude-plugin/plugin.json` (plugin manifest v1.0.0)
- Wrote `LICENSE` (MIT)
- `git init` with 2 commits on `main`

### Phase 0.5: Setup Command — COMPLETE
- Created `/compound:setup` command at `commands/compound/setup.md`
- Detects beads, PAL MCP, compound-engineering, GitHub CLI
- Presents status table, shows install instructions for missing tools
- Offers to create missing `docs/` directories
- Writes `compound-workflows.local.md` config file

### Phase 1: Port 7 Commands — COMPLETE (needs QA)

All 7 commands ported from `~/.claude/commands/aworkflows/` to `commands/compound/`:

| Command | Namespace | Year refs | Cross-refs | Role descriptions | PAL fallback | Beads/TodoWrite |
|---------|:---------:|:---------:|:----------:|:-----------------:|:------------:|:---------------:|
| brainstorm.md | done | done | done | done | done | n/a |
| plan.md | done | done | done | done | n/a | n/a |
| work.md | done | n/a | done | done | n/a | done |
| work-agents.md | done | n/a | done | done | n/a | done |
| review.md | done | n/a | done | done | n/a | n/a |
| compound.md | done | n/a | done | done | n/a | n/a |
| deepen-plan.md | done | done | done | done | done | n/a |

**Verified:** Zero `aworkflows` references remain (grep confirmed). All YAML `name:` fields correct. Beads/TodoWrite detection in work + work-agents. PAL fallback in brainstorm + deepen-plan.

### Phase 2: Port context-researcher Agent — COMPLETE
- Copied to `agents/research/context-researcher.md`
- Generalized examples (removed Flooid-specific references like Intellect, Eric, StarRocks)
- Added directory existence checks
- Kept `model: haiku`

### Phase 3: disk-persist-agents Skill — COMPLETE
- Created at `skills/disk-persist-agents/SKILL.md`
- Documents: output instruction block template, `.workflows/` directory convention, file monitoring, retention policy, batch dispatch, anti-patterns

### Phase 4: Documentation — COMPLETE
- `README.md` — Installation, feature comparison table, dependency table, directory conventions, acknowledgments
- `CLAUDE.md` — Plugin dev instructions (versioning, directory structure, testing)
- `CHANGELOG.md` — v1.0.0 entry with full feature list

### Phase 5: Git — PARTIAL
- 2 commits on `main`:
  - `8f3e737` — `feat: initial release of compound-workflows plugin v1.0.0` (16 files, 2682 lines)
  - `4a6f66b` — `docs: add plugin packaging plan for posterity`
- **NOT done:** GitHub repo creation, push, install testing

## Remaining Work

### Step 1: QA Review of Ported Commands

Read each ported command file end-to-end and compare against the source in `~/.claude/commands/aworkflows/`. Check for:

- [ ] **Truncation** — Did the subagent that ported the files write complete content? (Commands are 150-400 lines each; verify nothing was cut off)
- [ ] **Role descriptions on ALL agent dispatches** — Some agents may have been missed. Grep for `Task ` patterns without "You are a" following
- [ ] **TodoWrite fallback completeness** — The detection block was added, but does the rest of `work.md` and `work-agents.md` still reference `bd` commands without TodoWrite equivalents in the body? The detection block says "mentally replace" but for clean execution the commands should include conditional guidance throughout, not just at the top
- [ ] **Example dates** — `2026-02-10`, `2026-02-20` appear in examples in work.md and work-agents.md. These are fine (they're illustrative), but verify they don't say "the current year is 2026"
- [ ] **Cross-references to skills** — brainstorm.md references `brainstorming` skill and `document-review` skill; review.md references `file-todos` skill and `git-worktree` skill. These are compound-engineering skills. Verify they're referenced by name (so they work if compound-engineering is installed) but the commands don't break if those skills are absent

### Step 2: Fix Issues Found in QA

Apply fixes. Commit.

### Step 3: Create GitHub Repo and Push

```bash
cd ~/Dev/compound-workflows-marketplace
gh repo create compound-workflows-marketplace --public --source=. --push
```

Or if Adam prefers a different GitHub org/name, adjust accordingly.

### Step 4: Test Installation

Test from a clean project (NOT the Strategy repo):

```bash
mkdir -p /tmp/test-plugin-install && cd /tmp/test-plugin-install
git init

# Install the marketplace
claude  # start a session
# Then: /install compound-workflows-marketplace from <github-url>
```

Verify:
- [ ] All 8 commands appear in `/` slash command autocomplete
- [ ] `/compound:setup` runs and detects environment correctly
- [ ] `/compound:brainstorm test idea` starts the dialogue flow
- [ ] Agent names resolve (if compound-engineering installed) or fall back gracefully

### Step 5: Update Plans

- [ ] Mark `2026-02-25-plugin-packaging-plan.md` as fully completed
- [ ] Mark this plan as completed
- [ ] Commit final state

## Critical Files

| File | Path | What to check |
|------|------|---------------|
| brainstorm.md | `plugins/compound-workflows/commands/compound/brainstorm.md` | Most complex — PAL fallback, context-researcher ref, skill refs |
| work.md | `plugins/compound-workflows/commands/compound/work.md` | Beads/TodoWrite dual-path completeness |
| work-agents.md | `plugins/compound-workflows/commands/compound/work-agents.md` | Beads/TodoWrite dual-path, subagent prompt template |
| deepen-plan.md | `plugins/compound-workflows/commands/compound/deepen-plan.md` | PAL fallback, consensus fallback, multi-run manifest |
| context-researcher.md | `plugins/compound-workflows/agents/research/context-researcher.md` | Generalization completeness |

## Source Files for Comparison

| Original | Plugin copy |
|----------|------------|
| `~/.claude/commands/aworkflows/brainstorm.md` | `plugins/.../commands/compound/brainstorm.md` |
| `~/.claude/commands/aworkflows/plan.md` | `plugins/.../commands/compound/plan.md` |
| `~/.claude/commands/aworkflows/work.md` | `plugins/.../commands/compound/work.md` |
| `~/.claude/commands/aworkflows/work-agents.md` | `plugins/.../commands/compound/work-agents.md` |
| `~/.claude/commands/aworkflows/review.md` | `plugins/.../commands/compound/review.md` |
| `~/.claude/commands/aworkflows/compound.md` | `plugins/.../commands/compound/compound.md` |
| `~/.claude/commands/aworkflows/deepen-plan.md` | `plugins/.../commands/compound/deepen-plan.md` |
| `~/.claude/agents/context-researcher.md` | `plugins/.../agents/research/context-researcher.md` |
