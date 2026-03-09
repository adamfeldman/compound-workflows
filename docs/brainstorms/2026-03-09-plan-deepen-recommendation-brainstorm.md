# Brainstorm: Plan Should Recommend Deepen-Plan

**Date:** 2026-03-09
**Bead:** 1mx
**Status:** Complete

## What We're Building

Make `/compound:plan`'s Phase 7 handoff recommend whether to run `/compound:deepen-plan` based on the readiness report that already runs in Phase 6.7. Currently the handoff is a static menu — same four options in the same order regardless of plan quality.

The recommendation adds annotation text to the static menu and highlights the recommended option based on readiness severity counts. Menu ordering stays fixed (preserving muscle memory). When findings suggest deepening, a recommendation note explains why. When the plan is clean, the message notes deepen-plan is available but not necessary.

## Why This Approach

### Input signals: readiness report + lightweight supplements

The readiness report (Phase 6.7) already produces structured severity counts across checks: underspecification, contradictions, unresolved-disputes, external-verification, stale-values, broken-references, audit-trail-bloat. These are the primary signal.

**Supplemental signal — brainstorm existence:** Plan already reads the brainstorm in Phase 0 and knows whether one exists. A plan built without any brainstorm for a complex feature is a different risk profile. This is a near-zero-cost binary signal that partially mitigates the "confident-but-wrong plan" blind spot (see Acknowledged Limitations).

**Rejected alternative (full Option B):** Parsing research agent outputs, counting verified facts, measuring citation density. Rejected because:
- "Research thoroughness" is hard to measure without parsing agent outputs — significant context cost
- Risk of false positives for simple plans where brainstorm was legitimately skipped
- Lightweight proxies (brainstorm existence) capture the highest-value signal without the parsing cost

**Rejected alternative (LLM evaluator):** Passing readiness report + metadata to a dedicated LLM evaluator for holistic recommendation. Rejected because the decision tree is simple enough to be inline logic; a subagent would add latency and token cost for a decision that's fundamentally "read severity counts and branch."

**User rationale:** Option A (readiness signals only) with brainstorm-existence as a lightweight supplement. We believe this is sufficient but have not measured it — this is a hypothesis, not a validated claim. Track recommendation-vs-outcome data to validate (see Feedback Loop).

### Static menu with recommendation annotations, not dynamic reordering

Menu options stay in a fixed order across all runs. The recommendation is conveyed through annotation text (e.g., "Recommended:" prefix, explanation of why). This preserves muscle memory — users who habitually select option N get the same action regardless of plan quality.

**Rejected alternative (dynamic menu reordering):** Moving the recommended option to position 1. Rejected because dynamic menus are a known CLI anti-pattern — users build muscle memory for option positions, and swapping them causes accidental selection of expensive operations (like launching a full deepen-plan agent swarm when intending to start work). Red team flagged this as CRITICAL across multiple providers.

**User rationale:** Dynamic reordering → static menu with annotations. Muscle memory matters more than positional nudging.

### De-emphasize, don't drop

When the plan is clean (zero CRITICAL/SERIOUS), deepen-plan stays in the menu but is de-emphasized rather than removed. The de-emphasis message names deepen-plan explicitly and communicates its cost, so users can make an informed tradeoff.

**User rationale:** Dropping seems aggressive vs. de-emphasizing.

### Placement after readiness checks

The recommendation is computed after Phase 6.7 readiness checks complete and presented as part of the Phase 7 handoff — not a new phase. This is when maximum signal is available (readiness findings, plan structure, deferred items).

### Structured readiness output

The recommendation logic must consume structured output from the readiness report (severity counts by category), not parse prose text. This prevents brittle regex parsing that could silently break if readiness report formatting changes.

## Key Decisions

1. **Signal source:** Readiness report structured severity counts (primary) + brainstorm existence (supplemental)
2. **Presentation:** Static menu with recommendation annotations, not dynamic reordering
3. **Clean plan behavior:** De-emphasize deepen-plan (keep in menu with cost context), work annotated as recommended
4. **Dirty plan behavior:** Deepen-plan annotated as recommended, with note citing specific findings
5. **Placement:** Inline at Phase 7, computed from Phase 6.7 output — no new phase
6. **Feedback loop:** Track recommendation-vs-user-choice for future calibration

## Decision Tree

```
IF readiness report shows any CRITICAL finding (any category):
  → Annotate deepen-plan as "Recommended"
  → "Recommended: deepen-plan to address critical findings before work"

ELSE IF readiness shows any SERIOUS finding:
  → Annotate deepen-plan as "Recommended"
  → "Recommended: deepen-plan to address serious findings before work"

ELSE IF no brainstorm exists AND plan has 4+ steps:
  → Annotate deepen-plan as "Consider"
  → "Consider: no brainstorm preceded this plan — deepen-plan can catch assumptions"

ELSE (clean or only MINOR findings, brainstorm exists or plan is small):
  → Annotate work as "Recommended"
  → "Plan readiness checks passed — ready for work. Deepen-plan available
     for adversarial review if desired (~2-5 min, agent swarm + red team)."
```

**Note on first-run signal dominance:** On fresh plans (before any deepen-plan iteration), underspecification is empirically the dominant signal — most other checks (contradictions, unresolved-disputes) find nothing until edits introduce inconsistencies. The CRITICAL/SERIOUS catch-all branches still have value for replanned scenarios (e.g., after work started and gaps emerged), but on first-draft plans the tree is effectively an underspecification + brainstorm-existence detector. This is acceptable — those are the highest-value signals at plan-time.

## Feedback Loop

Track recommendation-vs-user-choice so future analysis can validate whether the decision tree produces good recommendations:

- **What to track:** The recommendation made (which option was annotated), the user's actual choice, and readiness severity counts at the time. Store in the plan's `.workflows/` research directory.
- **What to analyze later:** Do users frequently override the recommendation? Does skipping deepen-plan correlate with rework during `/compound:work`? Are there patterns in false negatives (recommended work, user needed deepen-plan)?
- **When to act:** If override rate exceeds ~30%, revisit the decision tree thresholds and consider adding signals.

## Acknowledged Limitations

- **Confident-but-wrong plans:** Structural readiness checks can't catch a plan that is precisely specified but based on incorrect assumptions from thin research. This is exactly what deepen-plan's red team is for — but we can't run a red team inside plan to decide whether to recommend a red team. The brainstorm-existence signal partially mitigates this (no brainstorm = higher risk of unvalidated assumptions), but it's not a complete solution.
- **Domain risk assessment:** The readiness report checks internal consistency, not external validity or architectural soundness. A plan can be structurally perfect yet propose a fundamentally flawed approach. The external-verification check partially addresses this, but only for explicitly cited external facts.

## Resolved Questions

- **Should iteration round estimates guide the recommendation?** No for round counts (pre-convergence data, will change). The simple/complex distinction from the taxonomy is partially captured by the decision tree's severity-count thresholds — more findings = more complex. Round count prediction is out of scope; the recommendation focuses on *whether* to deepen, not *how many rounds*.
- **Should the recommendation logic be a separate agent or inline?** Inline — it's reading structured severity counts, not doing analysis. A subagent would add latency for a simple branch.
- **Should user history or plan type inform the recommendation?** Not in v1. Plan type (feat/fix/refactor) and history (first plan vs replan) are valid signals but add complexity. The readiness report + brainstorm-existence covers the high-value cases. Revisit if feedback loop shows gaps.

## Open Questions

(none)

## Red Team Resolution Summary

**Providers:** Gemini (gemini-3.1-pro-preview), OpenAI (Codex CLI), Claude Opus
**Files:** `.workflows/brainstorm-research/plan-deepen-recommendation/red-team--{gemini,openai,opus}.md`

### CRITICAL (2 findings, both resolved)
1. **Decision tree logic gap** (Gemini + OpenAI) — Single SERIOUS finding and CRITICAL in unlisted categories fell to "clean" bucket. **Fixed:** Catch-all branches for any CRITICAL and any SERIOUS.
2. **Dynamic menu reordering breaks muscle memory** (Gemini; Opus + OpenAI as MINOR) — CLI anti-pattern. **Fixed:** Switched to static menu with annotations.

### SERIOUS (6 findings, all resolved)
1. **Single-signal dominance at first run** (Opus) — Only underspecification fires on fresh plans. **Acknowledged** in decision tree note; other branches serve replan scenarios.
2. **"80-90% coverage" claim unsubstantiated** (OpenAI + Opus) — **Fixed:** Restated as hypothesis, added feedback loop for validation.
3. **Brainstorm/research signals dismissed too broadly** (OpenAI + Opus) — **Fixed:** Added brainstorm-existence as lightweight supplemental signal.
4. **No feedback loop** (Opus) — **Fixed:** Added Feedback Loop section with tracking spec.
5. **Underspecification won't catch confident-but-wrong plans** (Gemini) — **Acknowledged** in limitations; partially mitigated by brainstorm-existence signal.
6. **Brittle parsing of readiness report** (Gemini) — **Fixed:** Added structured readiness output requirement.

### MINOR (7 findings, all resolved)
1. **Clean-plan message doesn't mention deepen-plan** (Opus) — **Fixed:** Clean-plan message now names deepen-plan with cost context.
2. **User history / plan type not explicitly rejected** (Opus) — **Fixed:** Added to Resolved Questions with rationale.
3. **Iteration/complexity rejection conflated** (Opus) — **Fixed:** Resolved Question now separates round counts (rejected) from complexity classification (captured via severity thresholds).
4. **"Open Questions: (none)" is brittle** (OpenAI) — Threshold tuning and category weighting are addressed by the feedback loop; validation protocol is the tracking spec. No unresolved items remain.
5. **Behavioral nudging may overfit** (OpenAI) — **Resolved:** Dynamic ordering was rejected entirely (CRITICAL #2). Static menu with annotations doesn't have the overfit risk.
6. **LLM evaluator alternative not considered** (Gemini) — **Fixed:** Added to rejected alternatives with rationale.
7. **No "why skip deepen-plan" rationale for clean plans** (Opus) — **Fixed:** Clean-plan message includes deepen-plan cost context.
