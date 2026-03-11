---
title: "Dynamic Model Routing for Quota Reduction"
date: 2026-03-11
type: analytical-finding
category: cost-modeling
domain: dynamic model routing / quota optimization
trigger: classify-stats run on 44 entries plus ccusage analysis to determine Sonnet downgrade feasibility
decision: dynamic model routing — Opus orchestrator selects Opus or Sonnet per dispatch based on input complexity
decision_date: 2026-03-11
status: decided
related_beads: [xu2, 5b6, wtn, 8sd, 2kj, 7k6]
upstream_docs:
  - memory/cost-analysis.md
---

# Dynamic Model Routing for Quota Reduction

## Question

Where could we use Sonnet instead of Opus in compound-workflows dispatches, and what would the quota impact be?

**Why it matters:** User is on Max 20x ($200/month). Daily Opus consumption of $98-210 (API-equivalent) regularly exhausts the weekly quota. Hitting the quota wall stops all work — this is a throughput problem, not a cost optimization.

## Evidence Chain

### Token Economics (2026-03-11 ccusage)

| Metric | Value |
|--------|-------|
| Daily Opus cost (API-equivalent) | $98.59 |
| Total tokens (Opus) | 142M |
| I/O tokens (Opus) | 200k |
| Cache:I/O ratio | ~710x |
| Effective rate per I/O token (Opus, cache-inclusive) | $493/M |
| Effective rate per I/O token (Sonnet, cache-inclusive) | $67/M |
| Opus:Sonnet cost ratio | 7.4x |

Cache tokens dominate: 138M cache reads vs 200k I/O. Claude Code re-sends growing conversation context with every API call. Long sessions + frequent tool use = massive cache volumes.

### Classification of 44 Agent Dispatches

First full classify-stats run across 7 stats files, 3 workflow sessions.

| Complexity | Count | % |
|-----------|-------|---|
| Mechanical | 12 | 27% |
| Analytical | 27 | 61% |
| Judgment | 5 | 11% |

| Output Type | Count | % |
|------------|-------|---|
| code-edit | 14 | 32% |
| research | 8 | 18% |
| review | 11 | 25% |
| relay | 8 | 18% |
| synthesis | 3 | 7% |

**Key finding:** All 8 relay agents already on Sonnet (v2.0.0). No new low-hanging fruit from classification alone. Remaining Opus agents are analytical (27) or judgment (5).

## Decision: Dynamic Model Routing

Rather than blanket Sonnet downgrades or static model assignments per agent, the plugin should use **dynamic model routing** — the Opus orchestrator evaluates each dispatch's input and selects Opus or Sonnet based on complexity heuristics.

### Alternatives Rejected

1. **Blanket Sonnet for all work steps** — Most work steps are analytical, not mechanical. Sonnet skips steps and conflates scope (Robustness Principles #1-5). Would cause quality regression.

2. **Static model assignment per agent** — Misses variance within the same agent type. Minor-triage with 2 items is trivial (Sonnet-safe); minor-triage with 8 cross-provider items needs Opus. Static can't capture this.

3. **Split minor-triage into Sonnet categorize + Opus edit** — Two dispatches eat savings via cache overhead. Second agent must re-read context. Complexity outweighs benefit.

### Why Dynamic Routing Wins

- The Opus orchestrator already reads plan steps and red team findings — it has the information to classify complexity
- Adding a model decision per dispatch costs essentially nothing (orchestrator already paying context)
- User-gated steps (minor-triage confirmation, work step review) provide a safety net for Sonnet quality regressions
- Captures the best of both: Sonnet for simple dispatches, Opus for complex ones

## Implementation Tiers

### Tier 1: High Confidence (implement first)

| Agent | Dispatched By | When Sonnet | When Opus |
|-------|-------------|-------------|-----------|
| general-purpose (work step) | work.md | Explicit old→new text, single file, "create file with content" | Multi-file coordination, redesign, refactor, >3 files |
| general-purpose (minor-triage) | brainstorm.md, plan.md | 1-3 MINORs, clearly categorizable | 5+ MINORs, cross-provider dedup, domain-heavy edits |

### Tier 2: Needs Empirical Testing (defer)

- `semantic-checks` — 5-pass structured analysis
- `spec-flow-analyzer` — flow mapping
- `plan-readiness-reviewer` — readiness aggregation

### Stay on Opus

- `general-purpose` as red-team-opus — adversarial reasoning
- `general-purpose` analytical work steps — complex edits
- `convergence-advisor`

### Already on Sonnet (v2.0.0)

- `repo-research-analyst`, `context-researcher`, `learnings-researcher`, `best-practices-researcher`, `framework-docs-researcher`, `red-team-relay`

### Not Yet Evaluated

- All 13 review agents (review.md)

## Projected Quota Impact

### Tier 1: 5-15% total Opus quota reduction

The orchestrator is 50-70% of total Opus cost and untouchable with subagent routing. Tier 1 agents represent ~25% of subagent I/O tokens.

| Orchestrator cost share | Tier 1 reduction |
|------------------------|-----------------|
| 50% | ~11% |
| 60% | ~9% |
| 70% | ~6% |

### Per-cycle savings

| Tier | Per-cycle savings | Confidence |
|------|------------------|------------|
| Tier 1 only (mechanical work + triage) | $100-200 | High |
| Tier 1 + Tier 2 | $150-280 | Medium |

At 1-2 cycles/day: $200-700/day, or 15-30% weekly quota reduction.

### Why Tier 1 Alone Isn't Transformative

The orchestrator is the elephant in the room. Real quota wins require:
1. Shorter sessions (less context accumulation)
2. More aggressive compaction (reset cache growth curve)
3. Tier 2 agents on Sonnet (adds ~15-25% of subagent savings)
4. Running the orchestrator on Sonnet (biggest win, highest risk)

## Prerequisites

1. **wtn** — Harden commands for cheaper-model robustness. Scope: work + plan + deepen-plan + brainstorm.
2. **xu2** — Work step dynamic routing. Biggest volume, lowest risk, implement first.
3. Empirical A/B testing for Tier 2 before committing.

## Stats Schema Gap

The `tokens` field in stats YAML captures only I/O tokens, not cache. Per-agent cost estimation requires the $493/M cache-inclusive effective rate (which overstates subagent cost since subagents have lower cache:I/O ratios than the orchestrator-dominated aggregate). Accurate per-agent cost needs either:
- Enhanced stats capture with cache fields from `<usage>` block
- Session JSONL mining (bead 3zr)
- Per-dispatch ccusage (not currently supported)

## Related Work

### Dependency Chain

```
22l (v2.0.0, done) — established Sonnet tier for 6 agents
    |
    v
voo (v2.3.0, done) — built stats capture infrastructure
    |
    v
8sd (done) — validated classify-stats on 44 entries
    |
    v
5b6 (in-progress) — cheaper-model audit using classified data
    |         |
    v         v
xu2 (next)   wtn (prerequisite)
    |              |
    v              v
Dynamic model routing implementation
```

### Key Documents

- **memory/cost-analysis.md** — Full detailed report with all data tables and analysis
- **docs/brainstorms/2026-03-09-workflow-quota-optimization-brainstorm.md** — Original Sonnet tier decisions (v2.0.0)
- **docs/solutions/plugin-infrastructure/2026-03-09-task-completion-usage-persistence.md** — Discovery that `<usage>` tags provide per-dispatch data; seeded voo
- **plugins/compound-workflows/CLAUDE.md** — Robustness Principles #1-5 (Sonnet failure modes)

### Related Beads

- **xu2** — Work-step-executor: Sonnet for mechanical work subagents (Tier 1 implementation)
- **5b6** — Audit plugin for cheaper-model dispatch opportunities (in progress)
- **wtn** — Harden plugin commands for cheaper-model robustness (prerequisite)
- **8sd** — Classify-stats validation (completed this session, unblocked xu2/5b6)
- **2kj** — Task→Agent dispatch migration (related cleanup)
- **3zr** — Session JSONL mining (could provide per-agent cache data)

## Reuse Triggers

Re-read this analysis when:
- Implementing xu2 or 5b6
- Weekly Max 20x quota is exhausted
- Before any brainstorm/plan on model selection
- Anthropic changes Max plan pricing or quota structure
- New Claude models change the Opus/Sonnet cost ratio
- Adding new agent dispatches to any command

## Assumptions That Could Invalidate

- Cache:I/O ratio of 710x is a daily aggregate; actual per-dispatch ratios unknown. If subagent cache:I/O is much lower (e.g., 50x), Sonnet savings per dispatch are *larger* than projected — this assumption cuts in favor of routing
- $493/M and $67/M effective rates assume today's usage pattern
- 50-70% orchestrator cost share is estimated, not measured
- Sonnet quality assessment based on known failures, not empirical A/B testing
- Max 20x quota structure may change (separate model quotas)
- The 7.4x ratio assumes standard API pricing maps to Max quota proportionally

**If Max 20x gets separate Sonnet quota → blanket Sonnet becomes viable and dynamic routing complexity is unnecessary.**
