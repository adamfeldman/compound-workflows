---
title: Session Log Analysis Methodology
date: 2026-03-13
domain: data-analysis
status: methodology-established
origin_bead: 3zr
related:
  - .claude/memory/estimation-heuristics.md
  - .workflows/session-analysis/extract-timings.py
  - .workflows/session-analysis/summary.md
  - memory/cost-analysis.md
reuse_triggers:
  - Mining JSONL session logs for timing data
  - Recalibrating bead estimation heuristics
  - Evaluating bead management overhead
  - Adding new workflow phases needing benchmarks
  - Answering "how long have I spent on X"
---

# Session Log Analysis Methodology

## Question

How do you extract accurate timing, overhead, and cost metrics from Claude Code JSONL session logs when sessions overlap, phase boundaries bleed, and activities are interleaved?

## Key Findings

### 1. Phase Boundary Correction

**Problem:** Phase durations measured from Skill invocation to next Skill invocation. Compact-prep showed 12 min median (18.4 hrs total) — inflated because the real pattern is compact-prep → `/compact` → continue working on other tasks.

**Solution:** Use `isCompactSummary` JSONL entry as the true phase-end marker.

**Result:** Median drops to 5.5 min (from 12), total to 5.6 hrs (from 18.4). Distribution shows tight 3-10 min cluster with 2 outliers (nested compound runs). No natural break at 10 min — the prior "next Skill" boundary was cutting through continuous activity.

**Generalization:** Each phase type needs its own end marker. Compact-prep uses `isCompactSummary`. Other phases may use commit events, user messages, or next Skill — validate empirically before assuming "next Skill" is correct.

### 2. Proportional Tool-Call Time Allocation

**Problem:** Mixed-activity segments (coding + bead management + reading) classified as 100% one category. "Orchestration" counted as pure overhead, inflating overhead estimate to 73%.

**Solution:** For each segment, compute the fraction of tool calls in each category (bd commands, editing, reading, user dialogue, agents). Allocate the segment's active time proportionally.

**Result:**
- Orch-coding (24.5 hrs): 84% coding / 16% bd overhead
- Pure orchestration (11.5 hrs): 82% productive / 18% bd
- True bd overhead: ~13 hrs / 65.5 total = **20%** (not 73%)

**Limitation:** Assumes each tool call takes roughly equal time. In reality, Agent calls (minutes) ≠ Read calls (seconds). This systematically underweights Agent-heavy segments. Acceptable for overhead estimation where bd commands and Edit/Read calls dominate, but would need duration-weighting for accurate phase-level cost attribution.

### 3. Minute-Level Active Time Deduplication

**Problem:** Naive per-session active time sums to 87.3 hrs. With concurrent sessions (weighted avg 1.8, up to 6 concurrent), active minutes are double-counted.

**Solution:** Collect all active minutes across ALL sessions into a global set of `(year, month, day, hour, minute)` tuples. Active = consecutive entries with gaps < 5 min (threshold empirically determined: 99.6% of 56K inter-entry gaps fall below it). Set membership deduplicates automatically.

**Result:** 65.5 hrs deduplicated (25% reduction). Also: true wall-clock = 368.5 hrs (merged session intervals vs 647 hrs naive sum).

**Concurrency profile discovered:** 71% solo, 17% at 4 concurrent sessions, bimodal (rarely 2 — jumps from 1 to 3-4).

### 4. AskUserQuestion Categorization

10.4 hrs of AskUserQuestion time across all activity. Keyword-based classification:

| Category | Share | Hours | Reducible? |
|----------|-------|-------|------------|
| Triage (choosing between options) | 51% | 5.4 | No — high-value judgment |
| Confirmation (proceed/apply/commit) | 19% | 2.0 | Yes — auto-toggles |
| Design decisions | 16% | 1.7 | No — architecture thinking |
| Scope (include/exclude) | 11% | 1.1 | No — strategic decisions |
| Diagnosis | 2% | 0.3 | No — root cause analysis |

82% is high-value analysis, 18% is reducible mechanical confirmation. The 2.0 hrs of confirmation gates is the automation target.

## Evidence Chain

- **Data source:** 87 JSONL session logs (~199MB), Feb 25 - Mar 13, 2026
- **Script:** `.workflows/session-analysis/extract-timings.py` (2352 lines)
- **Raw output:** `.workflows/session-analysis/raw-observations.jsonl` (1321 records)
- **Idle threshold validation:** 56,405 inter-entry gaps analyzed, bimodal distribution with clear break at 5 min (99.6% below)
- **Phase boundary validation:** Full compact-prep distribution (48 values) shows continuous range, confirmed by user that post-compact work is the cause of inflation

## Invalidating Assumptions

| Assumption | What breaks it |
|------------|---------------|
| 5-min idle threshold | Different work patterns (long compilations, frequent pauses) could shift optimal threshold |
| Equal time per tool call | Agent calls take minutes vs Read/Bash seconds — biases proportional allocation |
| `isCompactSummary` as boundary | Only valid for compact-prep; other phases need own end markers |
| Stable JSONL format | Claude Code version changes could break parsers |
| Single-user data | All metrics from one user — generalization requires multi-user validation |

## Headline Metrics Produced

| Metric | Value |
|--------|-------|
| Deduplicated active time | 65.5 hrs |
| True wall-clock (merged) | 368.5 hrs |
| Active days | 9 |
| Avg per active day | 7.3 hrs |
| Estimation accuracy (median) | 1.09x |
| Overhead ratio | ~20% |
| Reducible overhead | ~2 hrs (confirmation gates) |

## Related Documents

- `.claude/memory/estimation-heuristics.md` — updated with all findings
- `memory/cost-analysis.md` — token economics and effective rates
- `.workflows/session-analysis/summary.md` — full statistical summary
- Bead 3zr — tracks all phases of this analysis work
