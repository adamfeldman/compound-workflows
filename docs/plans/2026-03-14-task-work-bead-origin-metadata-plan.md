---
title: "Add origin metadata to /do:work bead creation"
type: task
status: completed
date: 2026-03-14
bead: smy2
---

# Add origin metadata to /do:work bead creation

## Goal

Add `--metadata '{"origin": "work", "plan": "<plan-file>"}'` to `/do:work` Phase 1 `bd create` calls so auto-created beads are structurally distinguishable from manually-created beads.

## Why

Bead-dependent analytics (estimation accuracy, cost-per-bead, velocity, effort dimension) mix two fundamentally different populations without distinguishing them. Work-created beads are granular plan decompositions; manual beads are varied-scope feature/bug tracking. The `Plan:` description prefix is ~95% accurate for retroactive classification but is a convention, not a contract. Explicit metadata makes the signal structural.

See: `docs/solutions/process-analysis/2026-03-14-inherited-assumption-blind-spots.md`

## Implementation

### Step 1: Update SKILL.md bead creation template

File: `plugins/compound-workflows/skills/do-work/SKILL.md`

- [x] Add `--metadata '{"origin": "work", "plan": "<plan-file>"}'` to both `bd create` example calls in Phase 1.3
- [x] Add prose instruction above the examples: "Every `bd create` call MUST include `--metadata '{"origin": "work", "plan": "<plan-file>"}'` where `<plan-file>` is the plan path from the skill arguments."
- [x] Keep the existing `Plan:` description prefix — it serves human readability. The metadata serves machine queryability. Both coexist.

The plan file path is available from `$ARGUMENTS` (the skill input) and from Phase 1.1.1 STEM derivation. Use the full path (e.g., `docs/plans/2026-03-14-my-plan.md`), not the stem.

### Step 2: Update AGENTS.md bead creation examples

File: `AGENTS.md`

- [x] In the bead creation guidance section, add `origin` to the `--metadata` example alongside `impact` and `impact_score`
- [x] Note that `origin` is auto-added by `/do:work` — users creating beads manually do not need to add it (absence = manual origin)

### Step 3: Version bump + QA

- [x] Bump version in `plugins/compound-workflows/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`
- [x] Update `plugins/compound-workflows/CHANGELOG.md`
- [x] Run `/compound-workflows:plugin-changes-qa`

## Constraints

- `Bash(bd:*)` static rule suppresses the `{"` heuristic — no permission prompt risk (empirically verified)
- Do not add origin metadata to `plugin-changes-qa` `bd create` calls — different concern, different origin type
- Do not change the `Plan:` description body prefix — keep both signals
- Absence of `origin` in metadata = manually-created bead — no need to tag manual beads

## Acceptance Criteria

- Both `bd create` examples in SKILL.md include `--metadata` with `origin` and `plan` fields
- Prose instruction mandates the metadata for all `/do:work` bead creation
- AGENTS.md documents the convention
- QA passes clean

## Sources

- Solution doc: `docs/solutions/process-analysis/2026-03-14-inherited-assumption-blind-spots.md` (change #6)
- Research: `.workflows/plan-research/work-bead-origin-metadata/agents/`
