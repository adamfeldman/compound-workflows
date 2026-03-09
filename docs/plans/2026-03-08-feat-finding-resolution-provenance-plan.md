---
title: "feat: Finding Resolution Provenance"
type: feat
status: completed
date: 2026-03-08
origin: docs/brainstorms/2026-03-08-finding-resolution-provenance-brainstorm.md
---

# Finding Resolution Provenance

## Problem

When deepen-plan resolves a finding (synthesis or red team triage), the resolution line replaces the original finding text in the plan. The original text disappears — only the decision survives. This is correct (keeping both causes annotation bloat, empirically validated as a Category 3 convergence blocker: 420 lines of accumulated findings in the retirement simulator plan). But the resolution line should include a provenance pointer back to where the original finding lives in `.workflows/`.

The gap isn't rationale loss — the Preservation Rule already protects decision reasoning. The gap is that you can't trace a resolution back to what triggered it (see brainstorm: `docs/brainstorms/2026-03-08-finding-resolution-provenance-brainstorm.md`).

## Scope

Three files, ~5 edit locations. No new files, no new commands, no architectural changes.

| File | What changes |
|------|-------------|
| `deepen-plan.md` | Phase 4 Step 5 (synthesis apply), Phase 4.5 Steps 2-3 (red team apply) |
| `plan-consolidator.md` | Section 9 (Preservation Rule patterns), Section 10a (grep regex) |

## Resolution Line Format

One canonical format for all verdict types. Extends existing bracket notation (`[agent-name]`) with a `see` clause:

```
- **Accepted:** [finding summary]. [agent-name, see .workflows/deepen-plan/<stem>/run-<N>-synthesis.md]
- **Modified:** [modified finding]. User: [reasoning]. [agent-name, see .workflows/deepen-plan/<stem>/run-<N>-synthesis.md]
- **Rejected:** [finding summary]. User: [reasoning]. [agent-name, see .workflows/deepen-plan/<stem>/run-<N>-synthesis.md]
- **Deferred:** [finding summary]. User: [reasoning]. [agent-name, see .workflows/deepen-plan/<stem>/run-<N>-synthesis.md]
```

**Red team triage** uses the specific provider file:
```
- **Resolved (valid):** [finding summary]. [action taken]. [red-team--<provider>, see .workflows/deepen-plan/<stem>/agents/run-<N>/red-team--<provider>.md]
```

**Batch-accept** uses a single annotation pointing to the summary:
```
- **Acknowledged (batch):** N MINOR findings accepted. [see .workflows/deepen-plan/<stem>/run-<N>-synthesis.md]
```

**Multi-provider red team** lists all provider names, one path:
```
[red-team--gemini, red-team--openai, see .workflows/deepen-plan/<stem>/agents/run-<N>/red-team--gemini.md]
```

**Best-effort fallback** (no file path available): omit the `see` clause, keep agent name only:
```
[deepen-plan triage]
```

### Design Decisions

- **Pointer targets synthesis summary for synthesis findings** — the synthesis file aggregates and attributes by agent name, so the orchestrator doesn't need to reconstruct individual agent file paths from names. For red team findings, point to the specific provider file (paths are predictable: `red-team--<provider>.md`).
- **Deferred items also get provenance pointers** — they move to Open Questions, where the `/compound:work` implementer encounters them with no other context about origin.
- **Run-2 supersession is natural replacement** — when a new run's resolution replaces a prior run's resolution, the new line includes its own provenance pointer. The Preservation Rule protects `[see .workflows/` from deletion, not from replacement by another line containing the same pattern.

## Implementation

### Phase 1: Synthesis Triage Provenance

**File:** `plugins/compound-workflows/commands/compound/deepen-plan.md`

- [x] **Phase 4, Step 5 (~line 329):** Replace current text:
  ```
  **Step 5: Apply.** Update the plan with all accepted/modified findings. Remove any rejected findings. Record the user's reasoning for all non-trivial decisions.
  ```
  With updated text that:
  - Replaces "Remove any rejected findings" with "Replace resolved findings with a resolution line"
  - Specifies the provenance pointer format for each verdict type (Accept, Modify, Reject, Defer)
  - Adds concrete format examples
  - Notes best-effort fallback when path is unavailable
  - Specifies that batch-accept uses a single annotation pointing to the synthesis summary

### Phase 2: Red Team Triage Provenance

**File:** `plugins/compound-workflows/commands/compound/deepen-plan.md`

- [x] **Phase 4.5, Step 2 (~lines 559-567):** Update the "Apply the user's decision" instruction to include provenance pointer format. Resolution lines should reference the specific red team file: `[red-team--<provider>, see .workflows/deepen-plan/<stem>/agents/run-<N>/red-team--<provider>.md]`

- [x] **Phase 4.5, Step 3 (~lines 574-579):** Update batch-accept to include provenance pointer. Format: `**Acknowledged (batch):** N MINOR findings accepted. [see .workflows/deepen-plan/<stem>/agents/run-<N>/red-team--<provider>.md]`. For multi-provider findings, list all provider names.

### Phase 3: Consolidator Preservation

**File:** `plugins/compound-workflows/agents/workflow/plan-consolidator.md`

- [x] **Section 9 (~lines 169-179):** Add `"[see .workflows/"` as a sixth protected pattern in the Preservation Rule bullet list.

- [x] **Section 10a (~lines 186-193):** Add `\[see \.workflows/` to the grep regex alternation so mechanical verification checks for provenance pointer preservation.

### Phase 4: Verification

- [ ] ~~Run a deepen-plan cycle on an existing plan and verify:~~ (deferred — verify organically on next deepen-plan run)
  - Resolution lines include provenance pointers
  - Batch-accept generates a single annotation with pointer
  - Consolidator preserves all `[see .workflows/` references
  - Pointers resolve to real files in `.workflows/`

## Acceptance Criteria

- [ ] Synthesis triage resolution lines include `[agent-name, see <path>]` pointing to the synthesis summary
- [ ] Red team triage resolution lines include `[red-team--<provider>, see <path>]` pointing to the provider's file
- [ ] Batch-accept produces a single annotation with provenance pointer
- [ ] Deferred findings in Open Questions include provenance pointers
- [ ] Consolidator Preservation Rule protects `[see .workflows/` from deletion
- [ ] Section 10a grep regex verifies provenance pointer preservation
- [ ] Best-effort fallback works: agent name only when path unavailable

## Out of Scope

- **Brainstorm red team findings** — already keep original text inline (written once, not iterated)
- **Plan readiness consolidator** — already has its own audit trail
- **Review findings** — go to `todos/`, separate tracking
- **Synthesis agent prompt changes** — orchestrator reconstructs paths, no need to change the synthesis prompt
- **Recovery detection heuristic** — provenance pointers naturally help recovery (grep for `[see .workflows/` to find triaged findings), but documenting this as a recovery feature is deferred

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-03-08-finding-resolution-provenance-brainstorm.md` — key decisions: pointer-not-inline (annotation bloat prevention), best-effort (no pointer > wrong pointer), deepen-plan only (scope boundary), consolidator preservation
- **Repo research:** `.workflows/plan-research/finding-resolution-provenance/agents/repo-research.md`
- **Learnings:** `.workflows/plan-research/finding-resolution-provenance/agents/learnings.md`
- **SpecFlow analysis:** `.workflows/plan-research/finding-resolution-provenance/agents/specflow.md`
- **Iteration taxonomy:** `docs/solutions/process-analysis/2026-03-08-deepen-plan-iteration-taxonomy.md` (Category 3 annotation bloat evidence)
