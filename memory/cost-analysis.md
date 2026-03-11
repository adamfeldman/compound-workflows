# Cost Analysis & Token Economics

## Daily Usage Profile (2026-03-11)

From ccusage data across multiple sessions:

| Model | Cost | Input | Output | Cache Creation | Cache Read |
|-------|------|-------|--------|----------------|------------|
| Opus 4.6 | $98.59 | 17,558 | 182,357 | 4,000,647 | 137,883,963 |
| Sonnet 4.6 | $2.01 | 9,341 | 20,524 | 277,419 | 2,115,757 |
| Haiku 4.5 | $0.12 | 25 | 3,536 | 65,926 | 190,367 |
| **Total** | **$100.72** | **26,924** | **206,417** | **4,343,992** | **140,190,087** |

### Historical Daily Totals

| Date | Total Cost | Opus | Sonnet | Haiku |
|------|-----------|------|--------|-------|
| 2026-03-10 | $209.74 | $195.86 | $13.73 | $0.15 |
| 2026-03-11 | $100.72 | $98.59 | $2.01 | $0.12 |

## Effective Rate Analysis

### Why cache tokens dominate

Claude Code sends the full conversation context with every API call. Each tool call, response, and file read accumulates in the conversation. Each new API request re-sends the entire history — with prompt caching, repeated prefixes are read from cache ($1.875/M) instead of reprocessed as fresh input ($15/M).

A session with 200 tool calls sending a 500k context each = 100M cache read tokens. Long sessions + frequent tool use + compaction cycles = massive cache read volumes.

### Three effective rates (Opus)

1. **Per total token (naive):** $98.59 / 142M = **$0.69/M** — misleading because it blends cheap cache reads with expensive output
2. **Per I/O token (cache-inclusive):** $98.59 / 200k = **$493/M** — attributes all cache cost to the I/O tokens that generated it
3. **Cache:I/O ratio:** 141.9M cache / 200k I/O = **~710x** — every I/O token carries ~710 cache tokens of overhead

Rate #2 ($493/M) is the most useful for estimating per-dispatch cost from the `tokens` field in stats YAML (which captures only I/O tokens).

### Caveat: orchestrator vs subagent cache ratios

The 710x ratio is a daily aggregate dominated by the orchestrator context, which re-sends a growing conversation with every interaction. Subagents start fresh with smaller contexts — their cache:I/O ratio is likely much lower (estimated 50-100x). Per-agent cost estimates using the aggregate ratio will overstate subagent cost and understate orchestrator cost.

## Per-Agent Cost Estimates (Opus, using $493/M cache-inclusive rate)

These are Opus agents that are candidates for cheaper-model dispatch. All relay agents are already on Sonnet (v2.0.0).

| Agent | Role | Complexity | Tokens (I/O) | Est. Cost |
|-------|------|-----------|-------------|-----------|
| general-purpose (red-team-opus) | Direct adversarial review | judgment | 21-56k | $10-28 |
| general-purpose (minor-triage) | Dedup + categorize MINORs | analytical | 24-37k | $12-18 |
| spec-flow-analyzer | Flow completeness | analytical | 53k | $26 |
| semantic-checks | Contradiction/underspec | analytical | 29-54k | $14-27 |
| plan-readiness-reviewer | Readiness assessment | analytical | 32-33k | $16 |
| general-purpose (work steps) | Code edits | analytical/mechanical | 22-57k | $11-28 |

### Per brainstorm+plan run cost (Opus agents only)

Rough estimate: $50-100 per full brainstorm→plan cycle for the Opus analytical/judgment agents listed above. On Sonnet (~$6/M vs $493/M effective... but Sonnet has its own cache profile), savings would be significant IF quality holds.

## Stats Schema Gap

The `tokens` field in stats YAML captures `total_tokens` (input+output only). It does NOT include `cache_read_tokens` or `cache_creation_tokens`. ccusage only reports daily aggregates, not per-dispatch breakdowns.

Accurate per-agent cost analysis requires either:
- Enhanced stats capture with cache fields from the `<usage>` block
- Session JSONL mining for per-request billing data (bead 3zr)
- Per-dispatch ccusage (not currently supported)

## Classification Results (2026-03-11)

First full classify-stats run on 44 entries across 7 files, 3 workflow runs.

### Complexity Distribution
| Tier | Count | % |
|------|-------|---|
| rote | 0 | 0% |
| mechanical | 12 | 27% |
| analytical | 27 | 61% |
| judgment | 5 | 11% |

### Output Type Distribution
| Type | Count | % |
|------|-------|---|
| code-edit | 14 | 32% |
| research | 8 | 18% |
| review | 11 | 25% |
| relay | 8 | 18% |
| synthesis | 3 | 7% |

### Key Finding: No new Sonnet opportunities from classification alone

All 8 relay dispatches are already on Sonnet (v2.0.0). The remaining Opus agents are analytical (27) or judgment (5). Whether analytical agents can safely run on Sonnet is a quality question, not a cost question — needs empirical testing (bead xu2 for work steps, bead 5b6 for broader audit).

## Sonnet Downgrade Opportunities

### Effective Rates (cache-inclusive, from 2026-03-11 ccusage)

| Model | Daily Cost | I/O Tokens | Cache-Inclusive Rate |
|-------|-----------|------------|---------------------|
| Opus | $98.59 | 200k | $493/M I/O |
| Sonnet | $2.01 | 30k | $67/M I/O |
| **Ratio** | | | **7.4x cheaper on Sonnet** |

### Tier 1: High confidence (mechanical tasks)

| Agent | Tokens | Opus Cost | Sonnet Cost | Savings | Quality Risk |
|-------|--------|-----------|-------------|---------|-------------|
| Work steps (mechanical) | 22-40k | $11-20 | $1.5-2.7 | $9-17/step | Low — follows explicit plan specs, find-and-replace |
| minor-triage | 24-37k | $12-18 | $1.6-2.5 | $10-16/run | Low — structured categorization with explicit criteria |

Work steps are the biggest prize: a 10-step `/compound:work` run could save **$90-170** if all mechanical steps use Sonnet. This is bead xu2.

### Tier 2: Medium confidence (structured analytical)

| Agent | Tokens | Opus Cost | Sonnet Cost | Savings | Quality Risk |
|-------|--------|-----------|-------------|---------|-------------|
| plan-readiness-reviewer | 32-33k | $16 | $2.2 | ~$14/run | Medium — aggregates findings into template, but must catch subtle readiness gaps |
| semantic-checks | 29-54k | $14-27 | $2-3.6 | $12-23/run | Medium — structured 5-pass analysis, but contradiction detection needs reasoning |
| spec-flow-analyzer | 53k | $26 | $3.6 | ~$22/run | Medium-High — flow mapping requires domain understanding |

Per plan run (2-3 semantic-checks + 1 readiness + 1 specflow): save **$50-80** if all hold quality.

### Tier 3: Keep on Opus

| Agent | Tokens | Cost | Why |
|-------|--------|------|-----|
| red-team-opus | 21-56k | $10-28 | Adversarial reasoning is exactly where model quality matters most |
| analytical work steps | 40-57k | $20-28 | Steps requiring judgment (sentinel redesign, multi-file coordination) |

### Total potential savings per full brainstorm→plan→work cycle

| Tier | Per-cycle savings | Confidence |
|------|------------------|------------|
| Tier 1 only (mechanical work + triage) | $100-200 | High |
| Tier 1 + Tier 2 (add readiness/semantic/specflow) | $150-280 | Medium |
| All possible | $200-350 | Needs empirical validation |

At 1-2 cycles/day: **$200-700/day** or **$6,000-21,000/month**.

### Recommended next steps

1. **xu2 first** (work steps) — biggest volume, lowest risk, most data available
2. **minor-triage** — add `model: sonnet` to dispatch, easy to A/B test
3. **Tier 2 agents need empirical testing** — run a plan with Sonnet semantic-checks and compare quality against Opus baseline

### Deep Dive: Work Step Feasibility for Sonnet

Most work steps from classified data were **analytical**, not mechanical:

| Step | Tokens | Tools | Classification | What it did |
|------|--------|-------|---------------|-------------|
| 8zy | 57k | 36 | analytical | Created validate-stats.sh + replaced patterns across files |
| qnu | 54k | 18 | analytical | Sentinel redesign + heuristic-exempt markers |
| igp | 40k | 16 | analytical | Version bumps + CHANGELOG |
| step-7 | 46k | 60 | analytical | Bulk multi-file edits with discovery |
| step-8 | 22k | 7 | mechanical | QA check addition |

Only step-8 was truly mechanical. The rest required understanding context, making choices about edit structure, and coordinating across files. Sonnet is known to skip steps and conflate scope (Robustness Principles #1-5 exist because of this). Blanket Sonnet for all work steps would likely regress quality.

**Dynamic model routing per step is the right approach.** The Opus orchestrator already reads the plan and decomposes into steps. It could classify each step before dispatch:

- Plan step has explicit `old_string`→`new_string` → **Sonnet** (mechanical find-and-replace)
- Plan step says "create file with this exact content" → **Sonnet**
- Plan step says "redesign", "refactor", "coordinate across files" → **Opus**
- Plan step touches >3 files → **Opus** (coordination complexity)

The classification is a simple heuristic in the work command — no separate agent needed. The Opus orchestrator is already paying the context cost; adding a one-line model decision per step is nearly free.

This reframes the Tier 1 work step savings: not $90-170 per 10-step run, but more like $30-50 (only the 2-3 genuinely mechanical steps per run). The remaining analytical steps stay on Opus.

### Deep Dive: Minor-Triage Model Split

Considered splitting minor-triage into Sonnet (categorize) + Opus (propose edits). Not recommended:
- Two dispatches instead of one — each carries cache overhead that may eat savings
- Second agent needs to re-read context or depend on first agent's output
- Edit proposals are a small fraction of total triage work (most tokens go to reading/deduplicating)
- User-gate (AskUserQuestion confirmation) already catches bad edit proposals

Simpler approach: run whole triage on Sonnet, let the confirmation step be the quality check. Split only if Sonnet edit quality proves poor in practice.

**Better approach: dynamic model routing for triage.** The orchestrator already has the red team files read — it knows the MINOR count and complexity before dispatching. One dispatch, dynamic model:

- **Few MINORs (1-3)**, all clearly categorizable → **Sonnet** — small scope, explicit criteria, low risk
- **Many MINORs (5+)**, cross-provider deduplication needed → **Opus** — more synthesis, more room for missed duplicates
- **MINORs touching areas with prior context** (references to earlier decisions, architectural patterns) → **Opus** — needs domain reasoning for edit proposals

The model decision costs nothing — the Opus orchestrator is already paying context. This is cleaner than the two-agent split: one dispatch, dynamic model selection based on input complexity.

### Decision: Dynamic Model Routing Is the Way Forward

**Date:** 2026-03-11
**Status:** Decided

Rather than blanket Sonnet downgrades or static model assignments per agent, the plugin should use **dynamic model routing** — the Opus orchestrator evaluates each dispatch's input and selects Opus or Sonnet based on complexity heuristics.

**Rationale:**
- Blanket Sonnet fails on analytical steps (skip steps, conflate scope — Robustness Principles #1-5)
- Static assignment misses the variance within the same agent type (minor-triage with 2 items vs 8, work step doing find-and-replace vs redesign)
- The Opus orchestrator is already paying context cost — adding a model decision per dispatch is nearly free
- User-gated steps (minor-triage, work step review) provide a safety net for Sonnet quality regressions

**Applies to:**
- Work steps (xu2): classify by plan step specificity and file count
- Minor-triage: classify by MINOR count and complexity
- Potentially Tier 2 agents (semantic-checks, spec-flow-analyzer, plan-readiness-reviewer) — pending empirical testing

**Does NOT apply to:**
- Red-team-opus: adversarial reasoning must stay on Opus
- Research agents: already on Sonnet (v2.0.0)
- Relay agents: already on Sonnet (v2.0.0)

**Revisit trigger:** If Claude Max quota model changes (e.g., Sonnet doesn't count against quota, or separate quotas per model), the calculus shifts — blanket Sonnet might become preferable over dynamic routing complexity.

### Full Agent Model Inventory

**Dynamic routing candidates (sometimes Sonnet, sometimes Opus based on input complexity):**

Tier 1 (high confidence):
- `general-purpose` work subagents — mechanical steps only (xu2)
- `general-purpose` minor-triage — when few MINORs

Tier 2 (needs empirical testing):
- `semantic-checks` — 5-pass structured analysis
- `spec-flow-analyzer` — flow mapping
- `plan-readiness-reviewer` — readiness aggregation

**Already static Sonnet (v2.0.0):**
- `repo-research-analyst`, `context-researcher`, `learnings-researcher`, `best-practices-researcher`, `framework-docs-researcher`, `red-team-relay`

**Stay on Opus:**
- `general-purpose` as red-team-opus — adversarial reasoning
- `general-purpose` analytical work steps — complex edits
- `convergence-advisor`

**Not yet evaluated:**
- All 13 review agents (review.md)

### Likely Implementation Plan (pending brainstorm/plan)

Tier 1 dynamic routing — two dispatch patterns, both `general-purpose`, Opus orchestrator decides model per dispatch:

| Agent | Dispatched By | Role | When Sonnet | When Opus |
|-------|-------------|------|-------------|-----------|
| general-purpose (work step) | work.md | Execute plan steps | Explicit old→new text, single file, "create file with content" | Multi-file coordination, redesign, refactor |
| general-purpose (minor-triage) | brainstorm.md, plan.md | Categorize + propose edits for MINORs | 1-3 MINORs, clearly categorizable | 5+ MINORs, cross-provider dedup needed, domain-heavy edits |

Tier 2 agents (semantic-checks, spec-flow-analyzer, plan-readiness-reviewer) deferred until Tier 1 is validated empirically. Still needs full brainstorm→plan→work cycle before implementation.

### wtn Hardening Scope

wtn (harden commands for cheaper-model robustness) is a prerequisite for dynamic routing. Scope depends on which commands dispatch Sonnet-candidate agents:

| Command | Sonnet candidates dispatched | Needs hardening? |
|---------|------------------------------|-----------------|
| work.md | Mechanical work steps | Yes — biggest savings |
| plan.md | minor-triage, semantic-checks, spec-flow, readiness | Yes |
| deepen-plan.md | Same plan-phase agents | Yes |
| brainstorm.md | minor-triage | Yes, but simpler scope |
| review.md | All review agents stay Opus? | Probably not |
| compact-prep.md | No subagent dispatches | No |
| setup.md | One-time, not quota-sensitive | No |
| compound.md | Infrequent | No |

Practical wtn scope: **work + plan + deepen-plan + brainstorm** — the high-frequency commands where Sonnet subagents would actually be dispatched. Not "all commands."

## Projected Quota Impact

### Tier 1 per-cycle token volume

| Dispatch | Count per cycle | I/O tokens each | Total I/O |
|----------|----------------|-----------------|-----------|
| Mechanical work steps | 2-3 | 22-40k | 60-100k |
| Minor-triage | 1-2 | 24-37k | 25-75k |
| **Tier 1 total** | | | **85-175k** |

### Percentage reduction estimate

From classified data, Tier 1 agents represent ~25% of all Opus subagent I/O tokens. But the orchestrator context (re-sends growing conversation hundreds of times) is the dominant cost component — estimated 50-70% of total Opus spend. Subagents are one-shot dispatches.

| Orchestrator share of Opus cost | Tier 1 savings | Total Opus reduction |
|--------------------------------|---------------|---------------------|
| 50% | 25% of 50% × 86% | ~11% |
| 60% | 25% of 40% × 86% | ~9% |
| 70% | 25% of 30% × 86% | ~6% |

(86% = Sonnet discount: 1 - 1/7.4)

**Honest range: 5-15% quota reduction from Tier 1 alone.**

### Why Tier 1 alone isn't transformative

The orchestrator is the elephant in the room — it's untouchable with subagent model routing. The real quota wins would come from:

1. **Shorter sessions** — less context accumulation → less cache per request
2. **More aggressive compaction** — resets cache growth curve
3. **Tier 2 agents on Sonnet** — adds another ~15-25% of subagent cost savings
4. **Running the orchestrator on Sonnet** — biggest possible win, highest quality risk

### Implication for prioritization

Tier 1 dynamic routing is still worth doing (5-15% reduction could be the difference at quota margin), but it won't solve weekly quota exhaustion on its own. The brainstorm should explore orchestrator-level optimizations alongside subagent routing.

### Note on estimates

These use the cache-inclusive effective rate ($493/M Opus, $67/M Sonnet) which overstates subagent cost (subagents have lower cache:I/O ratios than the orchestrator-dominated daily aggregate). Actual savings will be lower but directionally correct. The 7.4x Opus:Sonnet ratio should hold regardless of absolute cost, since both models face similar cache dynamics.

## Quota Context: Claude Max 20x

**User is on Max 20x ($200/month).** Token costs shown throughout this report are NOT actual charges — they are a **proxy for quota consumption**. The goal is to reduce quota burn to avoid hitting the weekly limit, not to save money directly.

ccusage reports "cost" using standard API rates, which serves as a proportional measure of how much quota each operation consumes. Switching agents from Opus to Sonnet reduces quota burn by ~7.4x per I/O token (same ratio as the API price difference).

### Weekly quota pressure

User regularly exhausts weekly Max 20x quota. Daily usage of $100-210 in API-equivalent cost means ~$700-1,470/week in quota burn. Sonnet downgrades in Tier 1 alone ($100-200/cycle, 1-2 cycles/day) could reduce weekly quota burn by 15-30%, potentially keeping usage within limits.

### Implication for 5b6

The cheaper-model audit isn't about saving dollars — it's about **staying within quota**. This elevates the priority: hitting the quota wall stops all work, making Sonnet downgrades a throughput issue, not just a cost optimization.
