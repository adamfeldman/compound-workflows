# Bead Estimation Heuristics

When creating beads, estimate total remaining workflow time in minutes using `--estimate N`.

## Per-Phase Timings (empirical, 2026-03-14)

Mined from 99 personal session JSONL logs (~240MB). Active time = wall-clock minus idle gaps >= 5 min (threshold empirically determined: 99.6% of inter-entry gaps are under 5 min). N = number of observed phase invocations.

| Phase | N | Active Median | Active Mean | Active P90 | Wall-clock Med |
|-------|---|--------------|-------------|------------|---------------|
| Brainstorm | 17 | 43 min | 59 min | 138 min | 89 min |
| Plan | 23 | 23 min | 26 min | 46 min | 31 min |
| Deepen-plan | 7 | 49 min | 47 min | — | 49 min |
| Work | 23 | 54 min | 59 min | 91 min | 103 min |
| Compact-prep | 66 | 4.9 min | 9.3 min | 15.3 min | 5.1 min |
| Compound | 11 | 9 min | 15 min | 48 min | 14 min |
| QA | 2 | 13 min | 13 min | — | 20 min |
| Review | — | ~15-20 min | — | — | — |

Review has no JSONL data yet (not invoked via Skill in measured sessions). Estimate retained from prior observation.

**Compact-prep timing notes:** Phase 6 expanded from 57 to 66 observations (using next-skill-invocation boundaries). Median stable at 4.9 min active. P90 is 15.3 min. Compact-prep is 96% active (almost no idle time).

**Active ratio insight:** Brainstorm and work phases are ~48-53% active — roughly equal time spent on model work vs reviewing output and making decisions. Plan and deepen-plan are ~75-99% active — more continuous model-driven work with less review pausing.

### Per-Step (Subagent Dispatch) Timings from Stats YAML

These measure individual subagent dispatches within workflows — complementary to the per-phase timings above which measure the full orchestrated workflow including user interaction. N=228 dispatches across 4 workflow types.

**By workflow command (dispatch duration in minutes):**

| Command | N | Median | Mean | P90 | Min | Max |
|---------|---|--------|------|-----|-----|-----|
| Work | 59 | 3.65 | 4.49 | 9.87 | 0.68 | 18.46 |
| Plan | 61 | 2.38 | 2.51 | 4.01 | 0.86 | 5.62 |
| Brainstorm | 45 | 1.85 | 1.99 | 2.82 | 0.61 | 5.69 |
| Deepen-plan | 13 | 2.81 | 3.32 | 5.75 | 1.74 | 6.06 |

**By agent type (dispatch duration in minutes):**

| Agent | N | Median | Mean | P90 |
|-------|---|--------|------|-----|
| general-purpose | 85 | 2.44 | 3.81 | 7.20 |
| red-team-relay | 24 | 2.02 | 2.20 | 3.80 |
| semantic-checks | 16 | 2.38 | 2.41 | 3.15 |
| repo-research-analyst | 15 | 3.24 | 3.23 | 4.93 |
| learnings-researcher | 9 | 1.79 | 1.83 | — |
| plan-readiness-reviewer | 8 | 1.07 | 1.17 | — |
| context-researcher | 7 | 2.47 | 2.55 | — |
| spec-flow-analyzer | 7 | 4.01 | 3.99 | — |
| plan-consolidator | 4 | 1.90 | 1.79 | — |

**Dispatch-to-estimate ratio:** median 0.15x, mean 0.26x (N=32). Dispatch time is agent wall-clock only — it excludes orchestrator time, user wait, and inter-step gaps. A 15-min estimate typically uses ~2.3 min of subagent compute (the rest is orchestration overhead and user interaction).

### Notable agent durations (usage-reported)

| Agent | N | Median | P90 |
|-------|---|--------|-----|
| plan-consolidator | 10 | 126s | 1523s |
| spec-flow-analyzer | 2 | 312s | — |
| plan-readiness-reviewer | 19 | 67s | 474s |
| semantic-checks | 3 | 319s | — |
| Explore | 20 | 57s | 145s |
| general-purpose | 46 | 103s | 404s |

### Token cost per phase (subagent tokens only)

Orchestrator context (main conversation cache reads) is not captured in `<usage>` blocks — only subagent tokens are available. These numbers undercount total phase cost but are useful for relative comparison.

| Phase | Agents | Total Tokens | Tokens/Agent |
|-------|--------|-------------|-------------|
| Work | 79 | 3,476,639 | 44,008 |
| Non-workflow | 48 | 2,305,412 | 48,029 |
| Brainstorm | 21 | 809,466 | 38,546 |
| Compact-prep | 23 | 853,302 | 37,100 |
| Plan | 18 | 630,761 | 35,042 |
| Deepen-plan | 8 | 588,545 | 73,568 |

Deepen-plan has the highest per-agent token usage (73,568) — consistent with deep-research nature. Total observed: 8.87M subagent tokens.

## Estimation Formula

Sum remaining phases using **median** for the base estimate:

- **Next: Brainstorm** → brainstorm + plan + work = ~120 min
- **Next: Plan** → plan + work = ~77 min
- **Next: Deepen-plan** → deepen + work = ~103 min
- **Next: Work** → work only = ~54 min
- **Next: Research/audit** → ~30-60 min (no build phase, not yet measured)
- **Bug fix** → ~30-60 min (usually straight to work, not yet measured)

These are active-time estimates. Wall-clock will be higher due to review/decision time. Multiply by ~1.5-2x for wall-clock expectation on brainstorm and work phases; ~1.3x for plan and deepen-plan.

## Estimation Accuracy (Segmented)

Phase 6 analysis: 100 beads with both estimates and actuals (windowed attribution). Overall median ratio: **0.56x** (estimates tend to be generous — actual work completes in ~56% of estimated time). 30 under-estimated (ratio > 1), 70 over-estimated (ratio < 1).

### By issue type

| Type | N | Median | Mean | Under-est | Over-est |
|------|---|--------|------|-----------|----------|
| Bug | 19 | 2.36x | 3.24x | 12 | 7 |
| Feature | 5 | 0.95x | 2.29x | 2 | 3 |
| Task | 76 | 0.51x | 1.19x | 16 | 60 |

**Key finding:** Bug estimates are systematically under-estimated (median 2.36x) — bugs take more than double the estimated time. Tasks are systematically over-estimated (median 0.55x). Features are roughly accurate at the median.

### By priority

| Priority | N | Median | Under-est | Over-est |
|----------|---|--------|-----------|----------|
| P0 | 1 | 0.70x | 0 | 1 |
| P1 | 44 | 0.56x | 10 | 34 |
| P2 | 28 | 1.46x | 17 | 11 |
| P3 | 13 | 0.62x | 3 | 10 |
| P4 | 3 | 0.55x | 0 | 3 |

**Key finding:** P2 beads are under-estimated (median 1.46x) — mid-priority items tend to have hidden complexity. P1 beads are over-estimated (0.56x) — these get detailed plans and execute faster than expected.

### By session count (single vs multi-session)

| Sessions | N | Median | Under-est | Over-est |
|----------|---|--------|-----------|----------|
| Multi-session | 21 | 4.27x | 20 | 1 |
| Single-session | 79 | 0.48x | 10 | 69 |

**Key finding:** Multi-session beads almost always blow estimates (95% under-estimated, median 4.27x). Single-session beads almost always beat estimates (87% over-estimated, median 0.48x). This is the strongest predictor of estimation accuracy.

### By estimate size bucket

| Bucket | N | Median | Under-est | Over-est |
|--------|---|--------|-----------|----------|
| <15 min | 19 | 0.91x | 7 | 12 |
| 15-60 min | 64 | 0.51x | 17 | 47 |
| 60-120 min | 4 | 4.45x | 4 | 0 |
| >120 min | 2 | 4.66x | 2 | 0 |

**Key finding:** Small estimates (<15 min) are the most accurate (median 0.91x). The 15-60 min bucket is over-estimated (0.51x). Large estimates (60+ min) are always under-estimated — they indicate scope that should be split.

### By effort tier (DID NOT VALIDATE — phase 6)

Effort tiers (routine/involved/exploratory/pioneering) were tested as a composite predictor using session count + estimate size. Result: effort tiers reduce MAE by only -2.8% vs session-count segmentation alone (threshold was 25% improvement). Session count alone is a better predictor. Effort tiers are NOT recommended for bead metadata.

| Effort Tier | N | Median | Mean | Under-est | Over-est |
|-------------|---|--------|------|-----------|----------|
| routine (1 session, <15 min est) | 17 | 0.88x | 0.90x | 5 | 12 |
| involved (1 session, 15-60 min est) | 62 | 0.33x | 0.52x | 5 | 57 |
| exploratory (2-3 sessions or >60 min est) | 16 | 4.16x | 5.58x | 15 | 1 |
| pioneering (4+ sessions and >120 min actual) | 5 | 4.30x | 5.40x | 5 | 0 |

### Correction Factor Recommendations

Apply these multipliers to raw estimates for better accuracy:

| Situation | Correction | Rationale |
|-----------|------------|-----------|
| **Bug fix** | 2.0x | Bugs take 2.36x median — debugging is unpredictable |
| **Task (well-scoped single-session)** | 0.6x | Tasks consistently over-estimated, median 0.55x |
| **Feature** | 1.0x | Features are roughly accurate at median |
| **Multi-session scope** | 3.0x | 95% under-estimated, median 4.27x |
| **Large estimate (>60 min)** | 3.0x | Always under-estimated — consider splitting |
| **P2 priority** | 1.5x | Hidden complexity pattern, median 1.46x |
| **Subagent-only step** (from /do:work plan) | 0.15x of total estimate | Dispatch time is 15% of estimate (median) |

**Practical rule:** If an estimate exceeds 60 minutes and the bead hasn't been split into sub-steps, the estimate is almost certainly wrong. Split first, then sum sub-step estimates.

## Adjustment Factors

- **Multi-command scope** (touches brainstorm + plan + deepen-plan): +50%
- **Well-scoped, single-file change**: use lower bound. Work (jak data): 8 dispatches completed in ~10 min active with exact old/new text in plan.
- **Needs deepen-plan?** Add ~49 min active (median). Skip if: brainstorm was thorough, plan is simple, red team in plan covers validation needs.
- **Has dependencies**: estimate only this bead's work, not the dependency chain

## Compaction Overhead

From 97 compaction events across 13 sessions:

| Metric | Value |
|--------|-------|
| Compaction events | 97 |
| Sessions with compaction | 13 of 99 (13%) |
| Total compaction token cost | $8.26 |
| Per-compaction cost (median) | $0.09 |
| Per-compaction cost (mean) | $0.09 |
| Reorientation time (median) | 5.72 min |
| Reorientation time (mean) | 24.58 min |
| Total reorientation time | 2384 min (39.7 hrs) |

**Impact on estimates:** Each compaction adds ~6 min of reorientation overhead (median). For sessions likely to compact (long work phases, multi-step plans), add 6 min per expected compaction. The mean (25 min) is skewed by long idle gaps where the session was abandoned overnight after compaction.

**Compaction rate:** 13% of sessions compact. Long sessions (>2 hrs active) are much more likely to compact. For beads estimated at >90 min active, budget 1-2 compaction cycles (12-18 min overhead).

## Velocity Trend

Daily velocity across 9 active dates, 226 beads closed, 104.6 active hours.

| Metric | Value |
|--------|-------|
| Overall beads/hour | 2.16 |
| Median beads/day | 20 |
| Mean beads/day | 25.1 |
| Median active hours/day | 11.66 |
| Mean active hours/day | 15.65 |

### Daily Trend

| Date | Beads Closed | Active Hours | Beads/Hour |
|------|-------------|-------------|------------|
| 2026-02-25 | 10 | 17.37 | 0.58 |
| 2026-03-08 | 13 | 45.40 | 0.29 |
| 2026-03-09 | 67 | 0.06 | — |
| 2026-03-10 | 29 | 0.00 | — |
| 2026-03-11 | 19 | 8.47 | 2.24 |
| 2026-03-12 | 56 | 14.94 | 3.75 |
| 2026-03-13 | 22 | 17.76 | 1.24 |
| 2026-03-14 | 10 | 0.60 | 16.67 |

**Velocity pattern:** Beads/hour improved from 0.3-0.6 early on (learning curve, infrastructure setup) to 2.2-3.8 in the mature period (Mar 11-13). The 2.16 overall figure is dragged down by early dates. Steady-state velocity is ~2.5-3.0 beads/active-hour.

**Active minutes per bead:** 19.9 min (4497 dedup min / 226 beads). At steady-state velocity, closer to ~15-20 min per bead.

## Cost-Productivity Trend (phase 6)

Daily cost efficiency, excluding dates with <1.0 active hours. Shows cost per bead trending down 76% — improving efficiency as the project matured.

| Date | Cost | Beads Closed | Cost/Bead | Active Hours |
|------|------|--------------|-----------|--------------|
| 2026-02-25 | $272.35 | 10 | $27.23 | 17.4 |
| 2026-03-08 | $804.57 | 13 | $61.89 | 45.4 |
| 2026-03-11 | $185.63 | 19 | $9.77 | 8.5 |
| 2026-03-12 | $307.43 | 56 | $5.49 | 14.9 |
| 2026-03-13 | $383.86 | 22 | $17.45 | 17.8 |
| **Overall** | **$1,954** | **120** | **$16.28** | **103.9** |

Pearson r = -0.25 (N=5) — too few data points for statistical significance. The trend direction is clear from the table: early sessions cost $27-62/bead, mature sessions cost $5-17/bead. Efficiency improved as workflow patterns stabilized and beads became better-scoped.

## Sonnet Subagent Savings Analysis (phase 6)

Estimated savings from routing mechanical/analytical subagent dispatches to Sonnet instead of Opus.

| Metric | Value |
|--------|-------|
| Theoretical upper bound (all Opus at Sonnet rates) | $787 savings (40.0% of total) |
| **Achievable via subagent routing** | **$1.08 savings (0.05% of total)** |
| Opus-to-Sonnet cache_read ratio (Opus 4.6) | 1.67x ($0.50 vs $0.30) |
| Orchestrator share of total cost | 86.2% (untouchable with subagent routing) |

**Key insight:** The prior rough estimate (10-15% savings) was based on incorrect Opus 4 pricing with a 7.4x cache_read ratio. With Opus 4.6 dominant (1.67x ratio), per-token savings are much smaller. More importantly, dispatched subagents consume only a tiny fraction of total tokens — the orchestrator session dominates cost and cannot be moved to Sonnet. Achievable savings are negligible ($1.08).

**Implication for routing decisions:** Sonnet subagent routing should be motivated by throughput/quota management (freeing Opus capacity for judgment work), not by dollar savings.

## Non-Workflow Activity Timings (empirical, 2026-03-14)

For beads that don't follow the formal workflow pipeline. Classified by dominant tool-call pattern across 192 session segments.

| Category | N | Active Median | Active Mean | Active P90 | Wall-clock Median |
|----------|---|--------------|-------------|------------|-------------------|
| Coding | 18 | 39 min | 55 min | 77 min | 49 min |
| Light-coding | 50 | 35 min | 49 min | 136 min | 48 min |
| Mixed | 62 | 11 min | 24 min | 65 min | 14 min |
| Bead management | 15 | 22 min | 28 min | 80 min | 180 min |
| Exploration | 16 | 14 min | 16 min | 36 min | 23 min |
| Discussion | 7 | 1 min | 1 min | — | 1 min |
| Configuration | 3 | 9 min | 22 min | — | 9 min |

### Subcategory breakdown (light-coding and mixed)

| Subcategory | N | Active Median | Active P90 | Total Active Min |
|-------------|---|--------------|------------|------------------|
| light-coding:orch-coding | 46 | 37 min | 136 min | 2318 min |
| mixed:still-mixed | 43 | 28 min | 69 min | 1339 min |
| mixed:interactive | 7 | 11 min | — | 132 min |
| light-coding:iterating | 1 | 74 min | — | 74 min |
| light-coding:plain | 1 | 31 min | — | 31 min |
| light-coding:interactive-dev | 2 | 7 min | — | 13 min |
| mixed:transition | 12 | 0.2 min | 1 min | 6 min |

The dominant subcategory is `orch-coding` (46 of 50 light-coding segments) — orchestration-heavy editing where `bd` commands mix with edits. `mixed:transition` segments are brief connective tissue between phases.

**Bead management breakdown** (7.1 hrs total active, 7.5% of all time):
- Triage (show/list/search/ready): 189 min
- Updating (update/close/label): 155 min
- Creation: 52 min
- Other: 28 min

### Non-workflow estimation guidance

- **Ad-hoc coding** (bug fix, small feature, config change): ~39 min active, ~49 min wall-clock
- **Light-coding / orchestration**: ~35 min active, ~48 min wall-clock (most common non-workflow activity)
- **Exploration/investigation**: ~14 min active (longer investigations likely use workflow phases)
- **Housekeeping** (bead management, memory cleanup, AGENTS.md updates): ~22 min active, but wall-clock inflates heavily due to interleaving with other work

## Time Allocation Overview

Total across 99 sessions: **104.6 hrs active** (dedup: 74.95 hrs), 406.3 hrs true wall-clock.

### By purpose (from segment analysis)

| Purpose | Hrs | Share |
|---------|-----|-------|
| Workflow phases (brainstorm+plan+deepen+work+compact-prep+compound+qa) | ~85 hrs | ~81% |
| Non-workflow (ad-hoc coding, bead mgmt, etc.) | ~20 hrs | ~19% |

### By simplified category rollup (active time)

| Category | Active Hrs | % of Total |
|----------|-----------|------------|
| Light-coding | 40.6 | 43.2% |
| Mixed | 24.6 | 26.2% |
| Coding | 16.0 | 17.0% |
| Bead management | 7.1 | 7.5% |
| Exploration | 4.4 | 4.7% |
| Configuration | 1.1 | 1.2% |
| Discussion | 0.2 | 0.2% |

## Dispatch Classification Profile (phase 6)

Stats YAML dispatches classified by complexity and output type (N=178 classified entries).

| Complexity | N | % | Median Duration | Median Tokens |
|------------|---|---|----------------|---------------|
| Analytical | 95 | 53.4% | 2.17 min | 48,396 |
| Mechanical | 36 | 20.2% | 2.02 min | 20,630 |
| Judgment | 14 | 7.9% | 2.32 min | 38,701 |
| Unclassified | 33 | 18.5% | 3.65 min | 61,865 |

Analytical dispatches dominate (53%), consistent with the project's analysis-heavy workflow. Mechanical dispatches are fastest (2.02 min median) and cheapest in tokens (20,630 median).

## Concurrency Profile

Across 40 sessions with timestamps (Feb 25 -- Mar 14, 2026):

| Concurrency | Time | Share |
|-------------|------|-------|
| 1 (solo) | 262 hrs | 71% |
| 2 | 3 hrs | 1% |
| 3 | 38 hrs | 10% |
| 4 | 63 hrs | 17% |
| 5-6 | 3 hrs | 1% |

Weighted average: 1.8 sessions. Peak: 6 concurrent. Pattern is bimodal -- either solo or 3-4 sessions. Rarely just 2. When concurrent, wall-clock totals double-count (each session's wall-clock is independent). True wall-clock: 406.3 hrs (merged intervals). Active/wall ratio: 18.5% (74.95 dedup active hrs / 406.3 wall hrs).

## Deduplicated Active Time

Because sessions frequently overlap (112 overlapping pairs across 40 sessions), naive summation of per-session active time double-counts concurrent work. Deduplication merges all active-minute intervals across sessions, counting each calendar minute at most once.

| Metric | Value |
|--------|-------|
| Naive session-sum active time | 104.6 hrs |
| Deduplicated active time | 74.95 hrs (4497 min) |
| True wall-clock (merged intervals) | 406.3 hrs (24,376 min) |
| Dedup active / wall-clock ratio | 18.5% |

The 29.7 hr gap between naive and deduplicated active time represents concurrent session overlap -- time when 2+ sessions were both active simultaneously. The 18.5% active ratio means ~81% of wall-clock time is idle (waiting for user, between sessions, overnight).

## Overhead Analysis

Overhead is measured via proportional allocation of bead-management (`bd`) tool calls within each activity segment. Each segment's active time is split proportionally across tool-call types. BD commands appear in nearly every segment type (not just bead-management segments), so the proportional approach captures overhead that segment-level classification misses.

| Metric | Value |
|--------|-------|
| Segments classified as bead-management | 15 (425 min active, 7.1 hrs) |
| Proportionally-allocated bd time (all segments) | ~749 min (12.5 hrs) |
| Overall overhead ratio (bd allocated / dedup active) | 16.7% |
| Orchestration segments analyzed | 50 |
| BD commands in orchestration | 698 (12.8% of orchestration tool calls) |
| BD allocated time in orchestration | 327 min |
| Productive tool calls in orchestration | 4775 (87.2%) |

The 16.7% overhead ratio reflects bd tool calls proportionally allocated across ALL segment types (work, plan, brainstorm, etc.), not just segments classified as "bead-management." This is more accurate than prior estimates that attributed entire bead-management segments as overhead.

### Proportional time allocation by activity bucket

| Activity Bucket | Segments | Active Min | bd % | editing % | reading % | agent % | other % | user-dialogue % |
|-----------------|----------|------------|------|-----------|-----------|---------|---------|-----------------|
| orchestration | 50 | 2560 | 11.4% | 19.8% | 20.1% | 5.8% | 35.8% | 7.0% |
| work | 23 | 1363 | 19.2% | 15.4% | 16.0% | 6.6% | 39.4% | 3.4% |
| coding | 18 | 988 | 4.1% | 32.9% | 25.0% | 6.5% | 28.5% | 3.0% |
| brainstorm | 17 | 1004 | 13.0% | 18.2% | 19.1% | 6.9% | 29.1% | 13.6% |
| plan | 30 | 914 | 2.5% | 18.8% | 19.2% | 8.2% | 44.5% | 6.9% |

Work phases have the highest bd overhead (19.2%) -- frequent bead updates during implementation. Plan phases have the lowest (2.5%) -- focused on content, minimal bead interaction.

## AskUserQuestion Breakdown

898 AskUserQuestion events categorized by question content. Wait time = gap from question to next assistant message.

| Category | Count | % of Total | Avg Wait (min) | Total Wait (min) |
|----------|-------|------------|----------------|------------------|
| confirmation | 280 | 31.2% | 4.71 | 1318 |
| triage | 210 | 23.4% | 6.59 | 1383 |
| scope | 185 | 20.6% | 0.94 | 174 |
| design-decision | 106 | 11.8% | 1.19 | 126 |
| other | 105 | 11.7% | 0.84 | 88 |
| diagnosis | 12 | 1.3% | 1.15 | 14 |

### AskUserQuestion by Workflow Phase

| Workflow | All Events | Confirmations | Avg Confirm Wait |
|----------|-----------|--------------|-----------------|
| non-workflow | 263 (29.3%) | 76 (27.1%) | 7.40 min |
| brainstorm | 259 (28.8%) | 71 (25.4%) | 1.10 min |
| work | 116 (12.9%) | 46 (16.4%) | 12.22 min |
| plan | 89 (9.9%) | 36 (12.9%) | 1.48 min |
| deepen-plan | 76 (8.5%) | 11 (3.9%) | 1.56 min |
| compact-prep | 51 (5.7%) | 23 (8.2%) | 0.70 min |
| compound | 5 (0.6%) | 2 (0.7%) | 2.42 min |

**Key insight:** Work phase confirmations have the longest wait (12.22 min avg) -- likely because users step away during long work executions. Brainstorm confirmations resolve fastest (1.10 min) -- interactive, user is engaged. Non-workflow confirmations are also slow (7.40 min), reflecting context-switching overhead.

**Reducible confirmation (31%):** The 280 confirmation prompts (avg 4.71 min wait) are the largest single category. Total confirmation wait: 1318 min (22.0 hrs).

## Permission Prompt Analysis (phase 6 — actual data)

### Proxy Estimate (section 25, retained for comparison)

122 Bash commands across 21 sessions matched heuristic-triggering patterns (`$()`, `<<`, `{"`). Upper-bound time cost: 78 min (1.3 hours). Likely range: 23-39 min (0.39-0.65 hours).

### Actual Hook Audit Data (section 27)

Cross-references hook audit log with JSONL session data. Coverage starts 2026-03-10 (hook installation date). All current entries are legacy 3-field format (no tool_use_id), so the user-prompted count is an upper bound — many were likely auto-approved but cannot be matched.

| Category | Count | % of Total |
|----------|-------|------------|
| auto-approved | 0 | 0.0% |
| hook-suppressed | 1,947 | 28.6% |
| ambiguous | 741 | 10.9% |
| user-prompted (upper bound) | 4,113 | 60.5% |
| **Total Bash calls** | **6,801** | **100%** |

**Interpretation:** The proxy estimate (122 triggering commands) dramatically undercounted — it only matched specific patterns. The hook audit shows 4,113 Bash calls not accounted for by auto-approve or work-phase suppression. However, this is an upper bound because legacy log entries lack tool_use_id for matching. The true user-prompted count will become measurable once 5-field entries accumulate.

**Hook suppression impact:** 1,947 Bash calls (28.6%) were suppressed during work phases via the `.work-in-progress` sentinel file. This is the validated savings from the hook system.

## Project Cost Summary (phase 6 — corrected pricing)

Total project cost corrected with accurate per-model-generation pricing (Opus 4.6 at $5/$6.25/$0.50/$25 per MTok, not Opus 4 at $15/$18.75/$1.50/$75).

| Metric | Phase 5 (wrong pricing) | Phase 6 (corrected) | Change |
|--------|------------------------|---------------------|--------|
| Total cost | $4,945 | $1,966 | -60% |
| Cost per active hour | $72.38 | $26.24 | -64% |
| Cost per bead (overall) | $23.11 | $16.28 | -30% |
| Per-session median | $51.63 | $11.50 | -78% |
| Cache-inclusive effective rate | $1.74/M tokens | $0.69/M tokens | -60% |

### Cost by Token Type

| Token Type | Cost | % of Total |
|-----------|------|-----------|
| Cache read | $1,382 | 70.3% |
| Cache creation | $465 | 23.6% |
| Output | $119 | 6.0% |
| Input | $0.58 | 0.0% |

**Cache dominance:** 93.9% of total cost is cache (creation + read). Non-cache (input + output) is only 6.1%.

### Cost by Phase (with cache split)

| Phase | Total | Cache | Non-Cache | Cache % |
|-------|-------|-------|-----------|---------|
| compact-prep | $598 | $567 | $31 | 94.9% |
| work | $408 | $383 | $26 | 93.7% |
| non-workflow | $270 | $253 | $17 | 93.7% |
| brainstorm | $258 | $239 | $18 | 92.8% |
| plan | $227 | $211 | $16 | 92.9% |
| deepen-plan | $104 | $98 | $6 | 94.2% |
| compound | $70 | $67 | $3 | 95.2% |
| qa | $10 | $10 | $0.44 | 95.6% |

### Cost by Model

| Model | Cost | % of Total |
|-------|------|-----------|
| claude-opus-4-6 | $1,962 | 99.8% |
| claude-sonnet-4-6 | $4.75 | 0.2% |

## Headline Metrics

Key aggregate metrics computed with minute-level deduplication across concurrent sessions.

| Metric | Value | Notes |
|--------|-------|-------|
| Sessions analyzed | 99 | Personal JSONL logs |
| Deduplicated active hours | 74.95 | After merging overlapping session intervals |
| True wall-clock hours | 406.3 | Merged concurrent session intervals |
| Total cost (JSONL-computed) | $1,966 | From per-request `message.usage` fields (corrected pricing) |
| Total cost (ccusage, for comparison) | $310.46 | From ccusage CLI (subagent tokens only) |
| Cost per active hour | $26.24 | $1,966 / 74.95 hrs |
| Cost per bead | $16.28 | Overall average across qualifying dates |
| Overhead ratio (bd / active) | 16.7% | Proportional allocation of bd tool calls |
| Automation ratio (Agent+Task / tools) | 6.09% | (738 + 31) / 13087 total tool calls |
| Closed beads | 226 | From beads database |
| Active days | 8 | Calendar days with session activity |
| Beads per day | 28.2 | 226 / 8 |
| Active minutes per bead | 19.9 | 4497 dedup min / 226 beads |
| Estimation accuracy (median) | 0.56x | Actual / estimated -- estimates are generous |
| Phase skip rate | 73.8% | 155 of 210 work phases without brainstorm/deepen |

**Cost context:** The $1,966 JSONL-computed figure captures all tokens including orchestrator cache reads (2.77B cache_read tokens). The $310.46 ccusage figure only captured subagent tokens visible in `<usage>` blocks. The JSONL figure is the true project cost. At $26.24/active-hour, 99.8% is Claude Opus 4.6 cost. Per-session median: $11.50.

**Phase skip rate:** 73.8% of work executions happen without a preceding brainstorm or deepen-plan. This reflects the project's heavy use of well-scoped beads (bug fixes, config changes, step-by-step plan execution) that go straight to work.

## QA Retry Cost

No QA retry sequences detected in measured sessions. 2 sessions had QA skill invocations but none contained qa-fix-qa retry chains -- QA passed on first attempt or fixes were done outside the skill-tracked workflow. QA retry cost is currently unmeasured.

## Coverage Gaps

1. **Review phase**: Still no JSONL data (not invoked via Skill in measured sessions). Estimate is based on prior observation only.
2. **Small-N phases**: QA (N=2), compound (N=11), deepen-plan (N=7) have limited data for P90 or outlier analysis. Will improve as usage accumulates.
3. **QA retry cost**: No retry sequences observed -- need more QA data to quantify retry overhead.
4. **Permission prompt cost (partially resolved)**: Hook audit provides classification counts but legacy log format prevents auto-approved matching. True cost will become measurable once 5-field entries accumulate.
5. **Phase boundary detection**: Phase boundaries use next-skill-invocation, which may capture inter-phase idle time. Tighter markers would improve precision.
6. **Sonnet quality validation**: Subagent routing savings analysis shows negligible dollar impact, but quality equivalence for mechanical/analytical dispatches on Sonnet is unvalidated.

## Cost Data

See `memory/cost-analysis.md` for detailed token economics, effective rates, per-agent cost estimates, and classification results.

## Data Source

Raw data: `.workflows/session-analysis/raw-observations.jsonl`. Analysis script: `.workflows/session-analysis/extract-timings.py`. Summary: `.workflows/session-analysis/summary.md` (31 sections). All personal data from a single user's 99 sessions.
