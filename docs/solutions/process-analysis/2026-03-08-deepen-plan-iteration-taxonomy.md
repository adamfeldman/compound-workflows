---
title: "Deepen-Plan Iteration Taxonomy: Why 7-9 Rounds and What Drives Each"
date: 2026-03-08
type: process-analysis
status: validated
tags:
  - deepen-plan
  - iteration-dynamics
  - plan-quality
  - edit-induced-inconsistencies
  - process-optimization
  - empirical-analysis
evidence_base: "12 deepen-plan runs across 2 projects, ~112 agents"
origin_brainstorm: docs/brainstorms/2026-03-08-plan-readiness-agents-brainstorm.md
related:
  - docs/brainstorms/2026-03-08-plan-readiness-agents-brainstorm.md
  - .workflows/brainstorm-research/fix-verification-agent/session-log-analysis.md
---

# Deepen-Plan Iteration Taxonomy

## Core Finding

Rounds 1-3 of `/compound:deepen-plan` find genuine design and domain bugs. Rounds 4+ mostly find bugs **introduced by the fixing process itself**. Each edit creates ~0.5-1.0 new issues per fix, sustaining a Sisyphean cycle driven by the lack of a consolidation-and-rewrite step.

The plan becomes a palimpsest of layered corrections that contradict each other.

## Evidence Base

- **Retirement Monte Carlo Simulator:** 8 deepen-plan runs, ~80 agents total
- **Stock Strategy Dashboard:** 4 deepen-plan runs, ~32 agents total
- **Source:** WhatsNext project session logs (JSONL), plan files, and `.workflows/deepen-plan/` synthesis outputs

**Limitation:** Two projects in one domain (financial planning HTML apps). The five categories are likely general, but round boundaries may shift for other domains.

## The Five Categories

### Category 1: Genuine Domain Errors (Rounds 1-3)

Real factual mistakes in the plan's financial, technical, or legal claims. Highest-value findings. Dominated by research agents and red team models catching things the plan author missed.

**Examples:**
- Bond total returns double-counted dividends
- RMD age wrong (73 vs 75 per SECURE 2.0)
- SS actuarial adjustment formula wrong (uniform 6%/yr vs actual two-tier)
- allorigins.win `/raw` API contract wrong in plan

**By run 4, zero new domain errors appeared** — except when external information changed (IRS Notice 2025-67, OBBBA SALT cap).

### Category 2: Interaction/Integration Bugs (Rounds 2-5)

Cross-component interactions only visible once individual components stabilize. The hardest bugs to find because they require understanding how multiple subsystems interact.

**Examples:**
- FIRE sweep + slider change race condition
- Roth conversion tax funding formula uses wrong rate in denominator
- Hash schema cannot encode Level 3 unlock state

### Category 3: Edit-Induced Inconsistencies (Rounds 4-8) — THE DOMINANT DRIVER

**This is the single biggest cause of high iteration counts.** Every plan edit introduces new contradictions. Four specific sub-patterns:

1. **Stale values across locations.** The same number (sample paths, LTCG threshold, catch-up contribution) appears in 3-6 locations. Fixing one creates inconsistency with the others.

2. **Label/reference rot.** Cross-references like "(R12)", "(R26)" break when numbering changes. Batch find-replace introduces new errors (run 3: replacing "(R12)" with "(R26)" corrupted 9 of 11 citations).

3. **Audit trail bloat.** By run 7, the retirement plan was 1,501 lines but only ~700 were actual spec. 420 lines were "Run N Review Findings" annotations. Each round added ~100 lines without removing superseded text.

4. **Annotation errors.** RESOLVED notes that introduce new mistakes (e.g., `resetState` specification gained 12+ naming mismatches during the run-7 cleanup pass).

### Category 4: Underspecification / Missing Contracts (Rounds 4-6)

Once architecture stabilizes, review agents shift to "could a developer actually build this?" — exposing missing function signatures, undefined data shapes, unspecified interfaces.

**Examples:**
- `complete` message results shape undefined
- `proposedWithdrawals` and `costBasisUpdates` return shapes undefined
- No test infrastructure (0 of 11 steps have test definitions)

### Category 5: Code Simplicity / Scope Disputes (Persistent)

The same design tradeoffs re-flagged every single round, consuming review bandwidth without producing plan changes. Never resolved because no decision log prevents re-litigation.

**Examples — retirement simulator, all flagged across runs 2-8:**
- Preset count: 7 → 4 → 2-3 → 0 (never reconciled)
- Worker state machine vs callback chain
- Dual QDCG functions (hot-path vs detailed)
- Pre-allocated TypedArrays vs plain objects

## Quantified Issue Distribution

### Retirement Monte Carlo Simulator (8 runs)

| Category | Runs 1-2 | Run 3 | Runs 4-5 | Runs 6-8 |
|----------|----------|-------|----------|----------|
| Domain errors | 8 CRIT, 6 HIGH | 5 CRIT, 2 SER | 0 | 3 CRIT (new legislation) |
| Integration bugs | 3 CRIT, 4 HIGH | 3 SER | 4 CRIT, 8 SER | 2 SER |
| Edit-induced | 0 | 2 SER | 2 CRIT, 8 SER | 5+ CRIT, 10+ SER |
| Underspecification | 0 | 0 | 3 BLOCK, 8 SER | 6 SER |
| Scope disputes | 4 | 5 | 6 | 8+ |

### Stock Strategy Dashboard (4 runs)

| Category | Run 1 | Run 2 | Run 3 | Run 4 |
|----------|-------|-------|-------|-------|
| Domain errors | 2 CRIT | 2 CRIT | 0 | 1 CRIT |
| Integration bugs | 0 | 0 | 3 CRIT, 6 SER | 3 SER |
| Edit-induced | 0 | 0 | 2 SER | 5 SER |
| Underspecification | 1 SER | 3 SER | 8 SER | 1 SER |
| Scope disputes | 4 | 0 | 3 | 2 |

## Convergence Indicators

| Signal | Retirement Sim | Stock Dashboard |
|--------|---------------|-----------------|
| Zero new domain errors | Run 4 onward | Run 2 onward |
| Zero new architectural bugs | Run 5 onward | Run 3 onward |
| CRITICALs are edit-induced, not design flaws | Run 6 onward | Run 4 |
| performance-oracle finds nothing new | Run 7 onward | Run 4 |
| Findings are "transcription errors and config gaps" | Run 8 | Run 4 |

The stock dashboard converged in 4 runs vs 8 because: lower domain complexity, more linear architecture, and a dedicated run-2 "zero open items" sweep that prevented accretion.

## Root Causes

1. **Incremental editing, not rewriting.** Corrections appended as "Run N Review Findings" rather than replacing original text.
2. **No single-source-of-truth.** Same value in 3-6 locations. Fixing one creates inconsistency with others.
3. **Verification catches but doesn't prevent regressions.** Finding counts in runs 4-8 are roughly constant — cycling, not converging.
4. **Scope disputes never resolved.** No decision log prevents re-litigation.
5. **No consolidation pass.** The retirement simulator broke the cycle only after run 7 recommended "stop reviewing, start editing" with a 4-pass cleanup.

## When to Re-Read This

- **Designing any iterative refinement loop** — any edit-verify cycle will hit ~0.5-1.0 new issues per fix without consolidation
- **Evaluating whether to add another deepen-plan round** — if CRITICALs are edit-induced (not design flaws), consolidate, don't deepen
- **Building or modifying review agents** — late-round agents should focus on consistency checking, not architectural analysis
- **Debugging why deepen-plan "isn't converging"** — answer is almost always Category 3 or Category 5
- **Estimating round counts** — simple plans: 2-3 rounds. Complex plans: 4-5 + consolidation

## What Would Invalidate This

- If plans adopt constants-as-data pattern (single definition + references), Category 3 stale-values sub-pattern shrinks
- If synthesis agents rewrite sections cleanly instead of appending, edit-induced inconsistency rate drops
- If decision logs prevent dispute re-litigation, Category 5 bandwidth waste disappears
- If plan-readiness-agents work as designed, complex plans should converge in 4-5 rounds instead of 8

## Architectural Response

The plan-readiness-agents brainstorm (`docs/brainstorms/2026-03-08-plan-readiness-agents-brainstorm.md`) directly addresses these root causes:

| Root cause | Agent/mechanism |
|-----------|----------------|
| Stale values across locations | stale-values check (mechanical) + constants-as-data pattern |
| Label/reference rot | broken-references check (mechanical) |
| Audit trail bloat | audit-trail-bloat check (mechanical) + consolidator stripping |
| Unresolved disputes | unresolved-disputes check reads prior decision logs |
| No consolidation pass | plan-consolidator with section-by-section processing |
| Underspecification caught late | underspecification check runs at round 1 |

## Current Command Gap

**deepen-plan.md has no awareness of this problem.** Phase 4 Synthesis tells the agent to "Preserve all original content" and add "Review Findings" sections — the exact accretion pattern driving Category 3. No consolidation step, no round cap, no distinction between genuine new findings and edit-induced regressions.
