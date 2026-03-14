---
title: "Inherited Assumption Blind Spots in Incremental Analysis"
category: process-analysis
date: 2026-03-14
confidence: high
problem_type: methodology-gap
domain: analytical-process
severity: medium
tags:
  - data-model-assumptions
  - population-homogeneity
  - incremental-analysis
  - review-blind-spots
  - inherited-assumptions
  - multi-phase-work
origin_brainstorm: null
origin_plan: docs/plans/2026-03-14-task-session-analysis-phase6-plan.md
reuse_triggers:
  - Performing multi-phase analytical work where later phases build on earlier findings
  - Reviewing analysis that mixes data from heterogeneous sources or populations
  - Designing review agents or checklists for analytical deliverables
  - Encountering metrics that seem valid but produce confusing or contradictory results
  - Adding new data categories to an existing analytical framework
---

# Inherited Assumption Blind Spots in Incremental Analysis

## Problem

Across 6 incremental phases of session analysis (~7 days), every analytical layer treated "beads" as a homogeneous population. Two fundamentally different populations exist:

1. **Work-created beads** (~73% of closed, ~164 beads): Auto-created by `/do:work` from plan step decomposition. Granular scope (15-60 min), descriptions start with "Plan:", estimates derived mechanically from plan steps, single-session execution is the norm.
2. **Manual beads** (~27% of closed, ~60 beads): Created by the plugin author for feature/bug/task tracking. Varied scope, created before plans exist, estimates are human judgment calls, multi-session execution common.

Mixing these populations corrupted every bead-dependent metric: estimation accuracy ratios, cost-per-bead, velocity trends, effort dimension validation, and Sonnet migration projections. The issue was never caught despite:
- 8+ research/review agents in deepen-plan
- 3-provider red team (Gemini, OpenAI, Claude Opus)
- code-simplicity-reviewer, architecture-strategist, performance-oracle reviews

The user noticed it in conversation.

## Root Cause

This is a **latent assumption propagation** problem. Phase 3 introduced bead attribution by joining session activity windows to bead IDs. The join treated all beads identically. The implicit assumption "a bead is a bead" was never stated, so it was never available for challenge. Every subsequent phase inherited the data model unchanged and added new segmentation dimensions on top — but every new dimension segmented within the same undifferentiated population.

### Phase-by-phase propagation chain

| Phase | What it added | How it inherited the assumption |
|-------|--------------|-------------------------------|
| Phase 3 | Bead attribution (linking sessions to beads) | Defined the join — all beads joined identically |
| Phase 5, Step 4 | Estimation accuracy segmentation | Segmented by type, priority, session count, estimate size — but not by origin |
| Phase 5, Step 6 | Velocity trend (beads/day) | Counted all closures equally |
| Phase 6, Step 6 | Cost per bead closed | Averaged cost across both populations |
| Phase 6, Step 8 | Effort dimension validation | Classified effort tiers using session count + estimate size, confounded by population membership |

### Why existing segmentation didn't catch it

Phase 5 segmented by issue type (task/bug/feature). This partially correlates with origin — most work-created beads are type "task" — but the correlation is imperfect. Manual beads can also be type "task." The type dimension captures a label, not the structural origin that determines scoping and estimation behavior.

Similarly, single-vs-multi-session segmentation partially captures the distinction, but conflates cause and effect. Work-created beads are single-session *because* they're pre-scoped. Manual beads become multi-session *because* their scope wasn't pre-constrained.

## Why the Review Pipeline Missed It

All review layers are **reactive** — they examine claims, check consistency, challenge architecture. None perform **proactive population analysis**.

| Review layer | What it checks | Why it missed this |
|-------------|----------------|-------------------|
| Research agents (4-8 per plan) | Problem domain, methodology | Scoped to "what data is available?" not "is the population coherent?" |
| Readiness checks | Internal consistency, stale values | Checks plan coherence, not whether the plan's premise is sound |
| Red team (3 providers) | Assumptions, architecture, missing steps | Focused on the plan's claims, not on what the plan doesn't claim. The assumption was implicit. |
| Code-simplicity reviewer | Over-engineering, YAGNI | Flagged N=5 Pearson as statistical theater — but not population validity |
| Architecture-strategist | Code structure, parameter counts | Checked function signatures, not input population structure |

The closest any agent came: code-simplicity-reviewer noted "Section 22 already shows multi-session beads have 4.27x vs single-session 0.51x — a loud, clean signal from a single binary variable." This correctly identified that one dimension dominates, but framed it as "effort dimension adds no nuance" rather than "the population might be heterogeneous."

## The Pattern (Generalizable)

**Incremental analytics built on unexamined assumptions accumulate precision without accuracy.**

Each phase added new metrics, tables, and segmentation dimensions. The analysis became more detailed and more wrong simultaneously — more detailed because new dimensions were added, more wrong because every new dimension operated within a flawed population boundary.

This is a textbook **Simpson's Paradox**: the overall estimation accuracy median (0.64x) blends work-created beads' systematic overestimation (~0.51x) with manual beads' systematic underestimation (~4.27x for multi-session). The aggregate hides two opposite signals.

### Analogous patterns

- **Ecological fallacy**: "beads take 19.2 min on average" — applying group-level statistics to individual beads from different populations
- **Survivorship bias in velocity**: high "beads/day" may reflect `/do:work` decomposing one plan into 8 granular steps, not 8 independent accomplishments
- **Base rate neglect**: adding segmentation dimensions creates the appearance of analytical depth while leaving the most important dimension (population membership) unexamined

## Solution

### Retroactive classification (immediate)

Use `description LIKE 'Plan:%'` to classify existing beads — ~95% accurate based on `/do:work`'s consistent description prefix convention. Re-segment all bead-dependent analytics by origin in phase 7 (bead rm84).

### Prospective metadata (structural fix)

`/do:work` Phase 1 `bd create` calls should add explicit metadata: `--metadata '{"origin": "work", "plan": "<plan-file>"}'`. This makes the signal structural rather than heuristic.

### Process fix (preventing the pattern class)

**Phase-0 assumption audit for analytical extensions:**

Before building new analysis on prior-phase outputs, enumerate inherited data model assumptions and ask for each analytical unit: "Is this population homogeneous for the question I'm asking?"

```markdown
## Inherited Assumptions (from prior phases)
- Beads are treated as a single population (no segmentation by creation source)
- Active time uses 5-minute idle threshold
- Phase boundaries use next-skill-invocation

### Validity check for this phase:
- [x] Idle threshold: still valid
- [ ] Bead population: NOT checked — this phase adds per-bead metrics
```

This is a plan template addition — zero implementation cost, directly targets the failure mode.

## Connection to Existing Knowledge

### Methodology finding #2 (closest analog)

`docs/solutions/process-analysis/2026-03-13-session-log-analysis-methodology.md` already documented and fixed an identical population-mixing problem for activity segments — mixed-activity segments inflated overhead from 73% to a corrected 20%. The fix (disaggregate by purpose, then measure) is the same pattern. But it was never generalized to beads.

Development Principle #1 ("comprehensive fixes, not targeted") should have triggered applying the disaggregation pattern to all heterogeneous populations once it was validated for segments. The principle is framed as a code-audit directive and was not extended to analytical methodology.

### Plan vs deepen role separation

`docs/solutions/process-analysis/2026-03-14-plan-vs-deepen-role-separation.md` identifies the same structural blind spot: generative analysis ("what metrics should we compute?") and structural analysis ("are we computing metrics over the right population?") are orthogonal concerns. No amount of iteration on the former compensates for skipping the latter.

### Deepen-plan iteration taxonomy

`docs/solutions/process-analysis/2026-03-08-deepen-plan-iteration-taxonomy.md` shows how incremental refinement creates assumption inheritance chains. Each phase's outputs become the next phase's inputs. By phase 6, the mixed-population assumption was 3 layers deep — too embedded for surface-level review to question.

## Impact

### Metrics affected

| Metric | Impact |
|--------|--------|
| Estimation accuracy (0.64x median) | Blends two populations with opposite biases |
| Correction factors (bug 2.0x, task 0.6x) | May not apply correctly to either population |
| Velocity (2.28 beads/hour) | Inflated by granular work-decomposition beads |
| Cost per bead ($23.11) | Averages across incomparable scope levels |
| Active minutes per bead (19.2) | Same issue |
| Effort dimension tiers | Confounded by population membership |

### Metrics NOT affected

Phase-level timings (brainstorm 43 min, plan 23 min, etc.), concurrency profile, AskUserQuestion breakdown, overhead ratio, cost by phase — these measure at workflow/session level, not bead level.

## Plugin-Level Prevention

The process fix above (Phase-0 assumption audit) is scoped to the analytics pipeline. The blind spot class — inherited assumptions surviving incremental review — affects any multi-phase project using the plugin's workflow pipeline. Six plugin-level changes would prevent this class for all users.

**Design philosophy:** Plan should become more robust over time, reducing the need for deepen-plan. Front-load assumption surfacing into brainstorm and plan (changes 1-2) as the primary defense. Deepen-plan and red team dimensions (changes 3-4) are the safety net, not the main line. Each time deepen-plan catches a class of issue, the fix should flow back into plan so it doesn't recur.

### Primary defense: assumption surfacing in brainstorm and plan

#### 1. Brainstorm: capture assumptions alongside decisions

When brainstorm design decisions establish data models or define analytical units, the brainstorm doc should capture an "Assumptions" section alongside "Decisions" and "Open Questions." This makes implicit assumptions explicit before they enter the plan.

**Change:** Add an Assumptions section to the brainstorm output template. When a decision implicitly relies on an assumption (e.g., "analyze beads" assumes beads are comparable), the brainstorm should surface it.

#### 2. Plan: "Inherited Assumptions" section for plans building on prior work

Plans that define data pipelines or build on prior-phase outputs should include an "Inherited Assumptions" section listing what the plan takes as given from prior phases, brainstorms, or existing infrastructure.

**Change:** Add to the plan skill's output template. When a plan references prior-phase data, models, or outputs, it should enumerate what it inherits and whether each assumption holds for the new work.

#### 3. Plan-readiness: flag missing assumptions inventory

The plan-readiness-reviewer already checks for underspecifications, contradictions, and stale references. A new check: when a plan references prior-phase data pipelines, models, or outputs (detectable via references to prior plan files, existing scripts, or "from phase N" language), flag if no "Inherited Assumptions" section exists.

**Change:** Add a readiness check module (or extend an existing semantic check) that detects prior-phase references and verifies an assumptions inventory is present. This is a structural check — it doesn't evaluate the assumptions, just ensures they're enumerated. Verifies that change #2 was done.

### Safety net: review-time validation

#### 4. Deepen-plan: "Inherited Assumptions" review dimension

Deepen-plan dispatches research and review agents against a plan. Currently, agents review the plan's internal quality — architecture, simplicity, performance, security. None are tasked with questioning assumptions inherited from prior work.

**Change:** Add an inherited-assumptions dimension to the review agent prompts dispatched by `/do:deepen-plan`. When a plan references prior-phase outputs, data models, or existing infrastructure, the reviewer should ask: "What assumptions does the prior work make? Are those assumptions valid for this plan's purposes? Are the entities being processed/analyzed actually comparable?"

This is a prompt change to the deepen-plan skill, not a new agent. The existing review agents (architecture-strategist, code-simplicity-reviewer) are well-positioned — they just need the mandate.

#### 5. Red team: "Population homogeneity" challenge dimension

The red team currently challenges assumptions, architecture, missing steps, and dependencies. "Are the entities being analyzed/processed actually comparable?" is a distinct dimension that none of the 3 providers caught in the phase 6 review.

**Change:** Add to the red team prompt a specific challenge: "Does this plan treat a collection of entities as uniform when they may contain structurally different sub-populations? If the plan computes metrics, segments data, or processes items in bulk, verify that the items are comparable."

This targets Simpson's Paradox and ecological fallacy — the two most common failure modes when heterogeneous populations are treated as one.

### Structural fix

#### 6. `/do:work` bead origin metadata

Currently `/do:work` creates beads via `bd create` with no origin marker. The description convention (`Plan:` prefix) is reliable but implicit.

**Change:** `/do:work` Phase 1 should add `--metadata '{"origin": "work", "plan": "<plan-file>"}'` to every `bd create` call. This benefits any user's project — it enables filtering, reporting, and understanding where work items came from. Any future analytics (not just this project's session analysis) can segment by origin without heuristics.

### Implementation notes

- Changes 1-3 (primary defense) are the highest priority — they prevent assumptions from entering the pipeline unexamined
- Changes 4-5 (safety net) catch what slips through — important but secondary
- Change 6 is a one-line addition to the `/do:work` SKILL.md bead creation template
- All six changes are independently valuable — they can be implemented and released separately
- Related beads: rm84 (phase 7 analytics), ytlk (plugin hardening)

## Reuse Triggers

Re-read this document when:
- Adding a new analysis dimension to an existing analytical pipeline
- A review agent reviews incremental changes to analytics code
- Creating estimation heuristics from mixed data sources
- Segmenting data and finding bimodal distributions or counterintuitive trends
- Encountering metrics that seem valid but produce confusing results
- Designing review agents or checklists for analytical deliverables
- Modifying deepen-plan, red team, or plan-readiness review prompts
- Adding new bead creation pathways (CI-triggered, imported, template-generated)

## Research Artifacts

`.workflows/compound-research/inherited-assumption-blind-spots/agents/` — 5 agent outputs from the compound research phase.
