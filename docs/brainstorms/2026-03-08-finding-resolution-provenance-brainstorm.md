# Finding Resolution Provenance

**Date:** 2026-03-08
**Status:** Draft
**Scope:** How resolved findings in plan files should reference their original source

## What We're Building

When deepen-plan resolves a finding (synthesis triage or red team triage), the resolution line replaces the original finding text in the plan. The original finding text disappears from the plan — only the decision survives. This is correct (keeping both causes annotation bloat, empirically validated as Category 3 convergence blocker), but the resolution line should include a provenance pointer back to where the original finding lives in `.workflows/`.

## Why This Approach

- **Annotation bloat is real.** The retirement simulator plan grew to 1,501 lines with 420 lines of accumulated findings (see `docs/solutions/process-analysis/2026-03-08-deepen-plan-iteration-taxonomy.md`). Keeping original finding text alongside resolutions doubles the annotation footprint. Option B (pointer, not inline) is the right tradeoff.
- **`.workflows/` already retains everything.** Raw agent outputs, red team critiques, synthesis files — all have "never delete" rules (8 explicit rules across 6 commands). The original finding text is there. We just need to point at it.
- **The consolidator's Preservation Rule already protects rationale.** Text matching "Rationale:", "Decision:", "Rejected because:", "User noted:", "Chose X over Y because" is never deleted. The gap isn't rationale loss — it's that you can't trace a resolution back to what triggered it.

## Key Decisions

1. **Resolution lines get a provenance pointer.** Format: `[source-agent, see <relative-path>]` appended to the resolution line. The path points to the `.workflows/` file containing the original finding.

2. **Pointer is best-effort, not mandatory.** If the source file path isn't available (e.g., findings surfaced in conversation rather than from a disk-persisted agent), the resolution records the source agent name only. No pointer is better than a wrong pointer.

3. **This applies to deepen-plan triage only.** Brainstorm red team findings go into the brainstorm doc as "Considered and Rejected" notes — those already keep the original text inline (brainstorm docs don't have the bloat problem because they're written once, not iterated). Plan readiness consolidator already logs to a consolidation report. Review findings go to `todos/`. No other command has this gap.

4. **The consolidator should not strip provenance pointers.** When the consolidator strips superseded annotations, it should preserve `[see .workflows/...]` references in resolution lines. These are part of the decision record, not annotation bloat.

## Where to Change

- **`deepen-plan.md` Phase 4 synthesis triage (Step 5, line 329):** Update "Remove any rejected findings" to "Replace rejected findings with a resolution line including provenance pointer." Update the apply instruction for accepted/modified findings similarly.
- **`deepen-plan.md` Phase 4.5 red team triage:** Same pattern — resolution lines should include `[red-team--<provider>.md]` pointer.
- **`plan-consolidator.md`:** Add `[see .workflows/...]` to the Preservation Rule patterns so provenance pointers survive annotation stripping.

## Open Questions

None — scope is narrow and approach is clear.

## Research

- Repo research: `.workflows/brainstorm-research/finding-traceability/repo-research.md`
- Context research: `.workflows/brainstorm-research/finding-traceability/context-research.md`
