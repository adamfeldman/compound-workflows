# Brainstorm: Harden Review Pipeline Against Inherited-Assumption Blind Spots

**Date:** 2026-03-14
**Bead:** #ytlk
**Origin:** `docs/solutions/process-analysis/2026-03-14-inherited-assumption-blind-spots.md`

## What We're Building

Five changes to the review pipeline that surface and validate inherited assumptions — implicit premises carried forward from prior work that currently propagate undetected through brainstorm, plan, deepen-plan, and red team phases.

The solution doc identified this through a specific analytics incident (mixed bead populations), but the brainstorm generalizes the problem: **any implicit assumption inherited from prior work can propagate undetected.** Population homogeneity is one category among several: temporal validity, scope, definitional drift, completeness, and environmental assumptions.

### The Five Changes

1. **Brainstorm Assumptions section** — always-present section in brainstorm output documents with evidence of categories checked
2. **Plan Inherited Assumptions section** — always-present section with two subsections: "Carried Forward" (from brainstorm) and "Newly Identified" (plan-specific)
3. **Plan-readiness Pass 6** — new `inherited-assumptions` semantic check verifying the plan has an Inherited Assumptions section
4. **Assumption-validator agent** — new deepen-plan review agent purpose-built for cross-cutting assumption analysis (replaces the solution doc's "modify existing agents" approach)
5. **Red team dimension** — generalized "inherited assumption validation" dimension on plan and deepen-plan red teams (not brainstorm), with population homogeneity as one named example
6. **Bead origin metadata** — explicit origin metadata on `/do:work` bead creation (already implemented — commit 80ea033)

### Design Philosophy

**Primary defense (changes 1-3):** Surface assumptions proactively during brainstorm and plan creation. Make the implicit explicit before it enters the pipeline.

**Safety net (changes 4-5):** Validate inherited assumptions during deepen-plan and red team. Catches what the primary defense missed.

**Layered defense:** Adaptive dialogue (best effort) → structured output section (forcing function) → readiness check (structural verification) → new agent + red team (challenge). Each layer catches what the previous one missed. Note: layers 1, 2, and 4 share the same model family and may share failure modes. Layer 3 (structural check) and layer 5 (multi-provider red team) provide genuine independence. CoT requirements and deterministic elements reduce shared failure mode risk.

**Considered alternative: reframe existing layers instead of adding new ones.** Reframing the existing "Unexamined assumptions" red team dimension with concrete examples and population-analysis instructions could achieve partial coverage. Rejected because: (a) the existing dimension already failed even with its current framing — the issue was assumptions being invisible, not poorly framed, and (b) assumption *surfacing* (proactive, changes 1-3) is a structurally different mechanism from assumption *challenging* (reactive, existing red team). Simplifying to "better prompts on existing dimensions" omits the proactive surfacing layer entirely.

## Why This Approach

The solution doc's post-mortem found that every existing review layer is reactive — examining stated claims and checking internal consistency. None question premises inherited from prior work. A bead population assumption survived 8+ research agents, a 3-provider red team, and multiple readiness checks because none asked "are these items actually comparable?"

The root cause isn't missing coverage — it's a missing *class* of analysis. The pipeline checks what you said, not what you took for granted.

### Generalization Over Specificity

The solution doc framed Change 5 as "population homogeneity" — the specific failure. This brainstorm generalizes to all inherited assumption types because:
- Population homogeneity was the instance that exposed the gap, not the only possible gap
- Other assumption types (temporal, scope, definitional, completeness, environmental) are equally invisible to current review
- A generalized dimension catches the entire class, not just the observed species
- The brainstorm red team already has "Unexamined assumptions" (dimension 1) — the problem wasn't the absence of that dimension but that assumptions were too implicit to surface. The new Assumptions section fixes this by making them explicit *before* the red team runs

## Key Decisions

### 1. Always-present sections with evidence of categories checked
**Decision:** Both brainstorm and plan get always-present Assumptions/Inherited Assumptions sections, even when empty. Empty sections must name the categories the model checked (e.g., "No data model, analytical unit, or population assumptions identified in this design").
**Why:** Prevents silent skipping. The forcing function isn't "section exists" but "model must demonstrate it looked at specific categories." An omitted section is invisible — an explicit "nothing found after checking X, Y, Z" is auditable.

### 2. Adaptive multi-stage dialogue for assumption surfacing
**Decision:** During brainstorm Phase 1.2, ask about assumptions using a multi-stage adaptive approach: start with a general question, then adaptively follow up based on what surfaces. Category list (population, temporal, scope, definitional, environmental) is available as reference but model adapts probes to the brainstorm topic.
**Why:** Prescriptive questions risk feeling forced on brainstorms without data model concerns. Too-open questions risk shallow probing. Multi-stage adaptive balances coverage with relevance. Safe because the always-present section with evidence serves as the backstop even if dialogue doesn't surface everything.

### 3. New agent instead of modifying existing agents
**Decision:** Create a dedicated assumption-validator agent for deepen-plan rather than bolting inherited-assumption instructions onto architecture-strategist and code-simplicity-reviewer.
**Why:** Over-extending existing agents risks diluting their core analysis. Assumption validation is fundamentally cross-cutting — it spans architecture, data models, scope, temporal validity. No single existing agent has that breadth. A dedicated agent can be purpose-built, independently tested, and tuned without affecting other agents' quality. The user expressed concern about "breaking" or over-extending existing agents.
**Note:** This diverges from the solution doc (`docs/solutions/process-analysis/2026-03-14-inherited-assumption-blind-spots.md`), which recommended modifying existing agents ("not a new agent... existing agents just need the mandate"). The user chose a new agent during brainstorm dialogue because assumption validation is a cross-cutting concern that doesn't fit any single existing agent's domain. This brainstorm supersedes the solution doc's recommendation on this point.
**Cost tradeoff:** One additional agent adds ~1 file, ~1 registry entry, ~5-15k tokens per deepen run. The alternative (modifying existing agents) would add ~1 paragraph each to 2 agent prompts, no new files. The new-agent approach has higher concrete costs but avoids speculative dilution risk to existing agents' analysis quality.

### 4. Assumption-validator runs in review batch with blocking capability
**Decision:** The new agent runs in the deepen-plan review batch (later), parallel with other review agents. If it flags CRITICAL assumption invalidations, this should feed into the readiness gate or trigger a revision loop — not just passively report to the user.
**Why:** Benefits from research batch findings — if a framework-docs-researcher discovered a dependency changed versions, the assumption-validator can catch "this plan assumes the API works the same way." Runs parallel with other review agents so marginal latency impact. A passive-only validator is a warning system that can be overlooked; wiring to a readiness gate makes it a genuine safety net. (Red team challenge: Gemini flagged that passive validation without blocking is "a safety net without teeth.")

### 5. Generalized red team dimension with explicit challenge instruction
**Decision:** The red team dimension is "inherited assumption validation" (general), not "population homogeneity" (specific). Population homogeneity is a named example within the broader dimension. Added to plan and deepen-plan red teams only — not brainstorm. Red team prompts must explicitly instruct: "Aggressively challenge and attempt to invalidate all items listed in the Assumptions and Inherited Assumptions sections."
**Why:** The brainstorm red team already has "Unexamined assumptions" — the new Assumptions section feeds that existing dimension with explicit content. Adding a redundant dimension to brainstorm red team adds noise. Plan and deepen-plan are where inherited assumptions become dangerous (the plan acts on them). The explicit challenge instruction prevents a risk flagged by Gemini: documented assumptions might be treated as "authorized facts" rather than targets for challenge.

### 6. New readiness Pass 6
**Decision:** Add `inherited-assumptions` as Pass 6 in semantic-checks.md (new pass), not extend Pass 3 (underspecification).
**Why:** Clean separation of concerns. "Steps too vague" (underspecification) and "assumptions not enumerated" (inherited-assumptions) are different failure modes. A distinct pass auto-inherits the skip_checks infrastructure. verify_only: false since it's not a recheck-eligible pass.

### 7. Plan Inherited Assumptions has two subsections
**Decision:** "Carried Forward" (from brainstorm, with validation status per assumption) and "Newly Identified" (assumptions the plan introduces about existing systems).
**Why:** Preserves provenance. Users can see which assumptions came from the brainstorm and whether they were validated or just carried blindly. The plan's Phase 0 "Extract and carry forward" mechanism already exists — assumptions are added to that carry-forward list.

### 8. One plan, all 5 changes
**Decision:** Implement all changes in a single plan rather than phased rollout.
**Why:** Changes are moderate in scope (prompt modifications across 4 skill files + 1 new agent file) but tightly coupled — the dependency chain (brainstorm section feeds plan section feeds readiness check feeds agent + red team) means the full system needs to exist to test meaningfully.

### 9. Validation strategy
**Decision:** Test with the known failure case first, then test against a different historical case, audit 3-5 recent brainstorms for base rate, and ship and observe on new work.
**Why:** The known case (analytics brainstorm that missed mixed bead populations) is necessary but not sufficient — the system was designed specifically for it, so passing is confirmation-biased (OpenAI + Opus flagged this). Testing against a different case validates generalizability. Auditing prior brainstorms estimates the base rate of assumption-related gaps, addressing the N=1 generalization concern (Opus flagged). The evidence base for this being a systemic problem is currently one incident; the audit either confirms systemic value or scopes the changes appropriately.

### 10. Per-change instrumentation
**Decision:** Keep one plan for all changes, but add per-change instrumentation so each layer's output is independently observable.
**Why:** If quality regresses after shipping, we need to attribute it to a specific change. The dependency chain means phased rollout breaks testability, but instrumentation preserves attribution without breaking the chain. (Red team challenge: OpenAI flagged that coupled rollout makes regression attribution impossible.)

## Assumptions

- **Prompt changes are sufficient for reliable assumption surfacing.** The always-present section with evidence of categories checked forces the model to demonstrate analysis, but a model could still cargo-cult the section. Mitigations: (a) require Chain-of-Thought reasoning before the final assumption output — the model must write a brief scratchpad analysis of *why* it believes there are no assumptions for each category, and (b) add deterministic detection elements (scripts scanning for prior-phase references, structural template validation) alongside prompt changes. (Red team challenge: Opus and Gemini flagged that 4 of 5 defense layers depend on prompt compliance, which is the failure mode this work addresses.)
- **A single new agent can effectively cover cross-cutting assumption validation.** The assumption-validator spans multiple domains (architecture, data, temporal, scope). If the analysis is too shallow across all domains, the agent may need to be split or specialized.
- **The brainstorm red team's existing "Unexamined assumptions" dimension becomes effective once fed explicit content.** The theory is that the dimension failed because assumptions were too implicit to challenge. If the Assumptions section makes them explicit, the dimension should catch problems. This is testable against the known failure case.
- **Adding Pass 6 to plan-readiness does not significantly increase readiness check time.** Currently 5 passes; adding a 6th is marginal. But if each pass is a separate model call, the cost adds up.
- **The assumption category list (population, temporal, scope, definitional, environmental) is reasonably complete.** Missing categories would leave blind spots. The adaptive dialogue approach partially mitigates this — the model can discover novel categories — but the evidence-of-categories-checked format relies on the list being sufficient.
- **The pipeline has capacity for additional mechanisms without diminishing returns.** This brainstorm adds to every stage of an already multi-layered pipeline. If future incidents reveal that added layers are not catching new failure classes, the pipeline's complexity budget should be reassessed. The justification for these additions is that they represent a new *class* of analysis (assumption validation), not more of the same class (consistency checking).
- **The brainstorm Assumptions section and plan Inherited Assumptions section are template-coupled.** Changes to either section's format require synchronized updates to both. The carry-forward mechanism depends on the plan skill knowing how to read and extract from the brainstorm's Assumptions section.

## Open Questions

*(All questions resolved during brainstorm dialogue. Remaining uncertainties — cargo-cult risk, category completeness, single-agent breadth — are tracked as assumptions above.)*

## Resolved Questions

1. **Format of Assumptions section** — Always present with evidence of categories checked. Multi-stage adaptive dialogue during Phase 1.2.
2. **Conditional vs always-present plan section** — Always present, two subsections. Every plan inherits something.
3. **Pass 6 vs extend Pass 3** — New Pass 6, clean separation.
4. **Modify existing agents vs new agent** — New assumption-validator agent, avoids over-extending existing agents.
5. **Brainstorm red team needs new dimension?** — No. The Assumptions section feeds the existing "Unexamined assumptions" dimension.
6. **Specific vs general red team dimension** — General "inherited assumption validation" with population homogeneity as named example.
7. **Agent batch placement** — Review batch (later). Benefits from research context, no latency cost.
8. **One plan vs phased rollout** — One plan, all changes. Moderate scope but tightly coupled, system needs full chain to test.
9. **Validation approach** — Test known failure case, test different case, audit prior brainstorms, then ship and observe.
10. **Per-change instrumentation** — Each layer independently observable for regression attribution.

## Red Team Resolution Summary

**Providers:** Gemini, OpenAI, Claude Opus (3-provider parallel review)

| # | Finding | Severity | Resolution |
|---|---------|----------|------------|
| 1 | Passive validator can't block pipeline | CRITICAL | **Fixed:** Decision 4 updated — assumption-validator wires to readiness gate |
| 2 | Prompt compliance paradox (4/5 layers share failure mode) | SERIOUS | **Fixed:** Assumption 1 updated — CoT reasoning + deterministic detection elements added |
| 3 | Validation is confirmation-biased (known case is tautological) | SERIOUS | **Fixed:** Decision 9 updated — add different historical case + audit prior brainstorms |
| 4 | Explicit assumptions may bypass red team as "authorized facts" | SERIOUS | **Fixed:** Decision 5 updated — explicit challenge instruction added to red team prompts |
| 5 | Contradicts solution doc on Change 4 without acknowledgment | SERIOUS | **Fixed:** Decision 3 updated — explicit divergence note added |
| 6 | N=1 generalization without base rate evidence | SERIOUS | **Fixed:** Decision 9 updated — audit 3-5 prior brainstorms for base rate |
| 7 | Coupled rollout removes attribution/rollback clarity | SERIOUS | **Fixed:** Decision 10 added — per-change instrumentation |
| 8 | No consideration of simplifying instead of adding layers | MINOR | **Fixed:** Design Philosophy updated — considered alternative documented |
| 9 | New-agent vs modify-existing tradeoff not quantified | MINOR | **Fixed:** Decision 3 updated — concrete cost comparison added |
| 10 | Defense layers not independent (same LLM failure mode) | MINOR | **Fixed:** Design Philosophy updated — independence caveat added |
| 11 | Pipeline bloat and diminishing returns | MINOR | **Fixed:** New assumption added — complexity budget acknowledgment |
| 12 | Cross-skill template drift | MINOR | **Fixed:** New assumption added — template coupling tracked |
| 13 | Change 6 listed as pending but already implemented | MINOR | **Fixed (batch):** Notation added to Changes list |
| 14 | "Open Questions: None" conflicts with remaining uncertainties | MINOR | **Fixed (batch):** Cross-reference to assumptions added |
| 15 | "Changes are small enough" understates scope | MINOR | **Fixed (batch):** Recharacterized as "moderate in scope" |
| 16 | Over-reliance on LLM dialogue | MINOR | **No action:** Dialogue is interactive by design; user reviews assumptions |
| 17 | Scope messaging contradiction | MINOR | **No action:** Complementary statements, not contradictory |
| 18 | Category completeness concern | MINOR | **No action:** Already tracked as Assumption 5 |
