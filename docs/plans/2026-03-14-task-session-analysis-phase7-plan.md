---
title: "Session Analysis Phase 7: Bead Origin Segmentation"
type: task
status: active
date: 2026-03-14
bead: rm84
---

# Session Analysis Phase 7: Bead Origin Segmentation

## Goal

Add bead origin classification to extract-timings.py and re-segment all bead-dependent analytics by origin (work-created vs manual). Re-present phase 6 findings with corrected population splits. Update estimation-heuristics.md with per-population correction factors.

## Why

Phase 6 analytics treat all beads as a single population. Two fundamentally different populations exist: work-created beads (~73% of closed, auto-decomposed by `/do:work`, granular 15-60 min scope) and manual beads (~27%, human-created, varied scope). Mixing them corrupts estimation accuracy, cost-per-bead, velocity, and effort dimension signals. See `docs/solutions/process-analysis/2026-03-14-inherited-assumption-blind-spots.md`.

## Data Reality

- ~230 closed beads total (live database, count varies). ~170 have `description LIKE 'Plan:%'` (work-created). ~60 do not (manual). Exact counts computed at runtime, not hardcoded.
- Only 3 closed beads have `origin` metadata (shipped in v3.1.8, commit ac9237f). Zero of these 3 have `estimated_minutes`.
- Estimation accuracy segmentation is 100% heuristic-based (`Plan:` prefix) for the foreseeable future. The metadata origin layer will match zero beads in `load_closed_bead_estimates()` until post-v3.1.8 work beads accumulate AND close with estimates. The plan should be explicit about this — the two-layer classifier is architecturally correct but practically heuristic-only right now.

### Prerequisite: One-time database migration (Step 0)

Rather than embedding the `Plan:` heuristic permanently in the analytics script, run a one-time `bd sql UPDATE` to set `origin` metadata on all historical beads. This cleans the source data permanently and lets the script use a single code path (`metadata.origin`). [red-team--gemini, red-team--opus]

## Inherited Assumptions

- 5-minute idle threshold for active time: still valid (unchanged from phase 4).
- Phase boundaries via next-skill-invocation: still valid.
- Bead attribution windows (60-second padding): still valid.
- Cache-inclusive effective rate from corrected MODEL_PRICING: still valid (phase 6 P0a).

## Implementation

All steps modify `.workflows/session-analysis/extract-timings.py` unless noted. Steps are sequential (single file). Each step's commit serves as a rollback point (`git revert`), and the script must remain runnable after each individual step. [red-team--opus finding 10]

### Step 0: One-time database migration — set origin on historical beads

- [x] Run a one-time `bd sql` UPDATE to set `origin` metadata on all historical beads where `description LIKE 'Plan:%'` and origin is not already set. This permanently fixes the source data so the analytics script needs only one code path (metadata.origin).
  - Validate first: `bd sql "SELECT COUNT(*) FROM issues WHERE description LIKE 'Plan:%' AND (JSON_EXTRACT(metadata, '$.origin') IS NULL OR JSON_EXTRACT(metadata, '$.origin') = 'null')"` — confirm the count is reasonable (~170)
  - Cross-check: for the 3 beads that already have `origin` metadata, verify the `Plan:` heuristic agrees: `bd sql "SELECT SUBSTR(id, -4), description LIKE 'Plan:%' AS has_prefix, JSON_EXTRACT(metadata, '$.origin') AS origin FROM issues WHERE JSON_EXTRACT(metadata, '$.origin') IS NOT NULL"` [red-team--opus finding 2, finding 7 — validates heuristic against ground truth]
  - Spot-check: sample 5-10 beads classified as "manual" (no `Plan:` prefix) and verify they are genuinely manual-created [red-team--openai finding 1]
  - If validation passes, run the migration. If it fails, investigate before proceeding.
  - Note: this step is outside extract-timings.py — it's a database operation

Test: `bd sql "SELECT JSON_EXTRACT(metadata, '$.origin') AS origin, COUNT(*) FROM issues WHERE status='closed' GROUP BY origin"` shows two groups (work ~170, NULL ~60).

Commit: `fix(beads): retroactively set origin metadata on historical work-created beads (rm84-S0)`

### Step 1: Switch bd sql parsing to JSON format and add origin to loaders

- [x] In ALL `bd sql` subprocess calls that parse structured output (`load_closed_bead_estimates`, `load_bead_closures_by_date`, `count_closed_beads`, `load_known_bead_ids`), switch from pipe-delimited tabular parsing (`split("|")`) to JSON format:
  - Add `--result-format json` flag to `bd sql` calls
  - Replace `split("|")` positional parsing with `json.loads()` and key-based access
  - This eliminates: pipe characters in `description` breaking the parser [red-team--gemini CRITICAL], fragile positional index arithmetic [red-team--openai SERIOUS, red-team--opus finding 3], `bd sql` text truncation in tabular mode [red-team--gemini CRITICAL], and manual quote-stripping from JSON values [red-team--gemini MINOR]

- [x] Update `load_closed_bead_estimates()` to include `origin`:
  - Add `JSON_EXTRACT(metadata, '$.origin') AS origin` to SQL query
  - With JSON parsing, access `row["origin"]` directly — no index arithmetic needed
  - After Step 0 migration, metadata origin covers historical beads. For any remaining unset beads, fall back to `description LIKE 'Plan:%'` as a safety net.
  - Store `"origin"` in the returned dict

- [x] Add companion function `load_bead_closures_by_date_and_origin()`:
  - SQL: `SELECT DATE(closed_at) AS date, JSON_EXTRACT(metadata, '$.origin') AS origin, COUNT(*) AS count FROM issues WHERE status='closed' AND closed_at IS NOT NULL GROUP BY DATE(closed_at), JSON_EXTRACT(metadata, '$.origin') ORDER BY date` — uses SQL aggregation (origin is now in metadata after Step 0, no need for Python-side classification) [red-team--gemini MINOR]
  - Return: `dict[date_str -> dict[origin_str -> count]]`
  - Keep existing `load_bead_closures_by_date()` unchanged (other consumers use it)

- [x] Handle `bd sql --result-format json` edge cases:
  - Verify the flag exists: test with a simple query first. If unavailable, fall back to `--result-format csv` with `csv.reader()`.
  - NULL/nil handling: JSON format returns `null` for SQL NULLs — simpler than `<nil>` sentinel [red-team--openai SERIOUS]

Test: Run script, verify it parses all bd sql output correctly with JSON format. Verify origin counts match Step 0 migration results.

Commit: `refactor(session-analysis): switch bd sql parsing to JSON format + add origin (rm84-S1)`

### Step 2: Re-segment estimation accuracy by origin

- [x] In `compute_estimation_segments()`, add `"origin"` to per-bead records: `"origin": est_data.get("origin") or "manual"`
- [x] Add `by_origin` segment dimension (same pattern as `by_type`, `by_priority`, etc.)
- [x] In `generate_summary()` section 22, render `by_origin` segment table via `render_segment_table("By Origin", segs.get("by_origin", {}), "Origin")`
- [x] Add `Origin` column to per-bead detail table in section 22

Test: Script runs clean, section 22 shows "By Origin" table with work/manual rows. Work-created beads should show tighter estimation accuracy than manual beads.

Commit: `feat(session-analysis): segment estimation accuracy by bead origin (rm84-S2)`

### Step 3: Re-segment velocity and cost-productivity by origin

- [x] In `main()` velocity computation (line ~4927), use `load_bead_closures_by_date_and_origin()` alongside existing `load_bead_closures_by_date()`
- [x] Add `work_beads_closed` and `manual_beads_closed` to each velocity trend record
- [x] Add `total_work_beads_closed` and `total_manual_beads_closed` to velocity summary dict
- [x] In `generate_summary()` section 24, add `Work` and `Manual` columns to daily velocity table
- [x] In `compute_cost_productivity_correlation()`, accept origin-split closures and add `work_beads_closed`/`manual_beads_closed` to each daily record
- [x] In `generate_summary()` section 29, add `Work` and `Manual` columns to cost-productivity table
- [x] Keep aggregate `beads_closed` and `cost_per_bead` columns unchanged — the split columns are additive

Test: Script runs clean, sections 24 and 29 show work/manual columns. Days with high total closures should show most from work-created beads.

Commit: `feat(session-analysis): segment velocity and cost-productivity by bead origin (rm84-S3)`

### Step 4: Re-run effort validation per population and add origin to section 31

- [x] Add `origin` field to per-bead records in `compute_effort_validation()`
- [x] After full-population validation, run validation separately on each origin population (filter `closed_bead_estimates` to origin="work" or origin="manual" before calling)
- [x] N<20 guard: compute N AFTER all filters used by `compute_effort_validation()` — this is beads with estimates AND attribution data, not total closed beads. The work population may have fewer beads with estimates than total work beads. Gate subsection rendering on the actual filtered N. [red-team--opus finding 4, red-team--openai finding 3, red-team--gemini finding 1]
- [x] In `generate_summary()` section 31, add origin column to per-bead detail table
- [x] Add subsection: "Effort Validation — Manual Beads Only" showing whether effort tiers validate when work-created beads are excluded
- [x] If manual-only `improvement_vs_session` >= 0.25 (same metric as full-population validation): note that effort tiers may have been masked by population mixing

Test: Script runs clean, section 31 shows per-population validation result. Manual-only MAE comparison may differ from full-population result.

Commit: `feat(session-analysis): per-population effort validation (rm84-S4)`

### Step 5: Update estimation-heuristics.md and present findings

- [ ] Re-run the full script: `python3 .workflows/session-analysis/extract-timings.py`
- [ ] Read `.workflows/session-analysis/summary.md` for updated sections 22, 24, 29, 31
- [ ] Update `.claude/memory/estimation-heuristics.md`:
  - Add "By origin" segmentation table to Estimation Accuracy section
  - Split correction factors by origin where they differ significantly
  - Add origin-split velocity figures
  - Note whether effort dimension rehabilitates on manual-only population
  - Update cost-per-bead with origin split
- [ ] Present all findings to user — this is the deferred phase 6 findings presentation (y53x notes) plus phase 7 new data:
  - Origin-segmented estimation accuracy: do the two populations show opposite biases?
  - Correction factors: which ones change per population?
  - Velocity: how much is inflated by work-created beads?
  - Cost-per-bead: does the "76% efficiency improvement" hold within each population or is it a mix effect?
  - Effort dimension: does it validate on manual beads alone?
  - Decision: should effort tiers be rolled out for manual beads specifically?
  - **Novel/curious findings**: anything surprising, unexpected, or interesting in the data — not just from the origin split but from any section of the analysis. Patterns worth investigating, outliers worth explaining, numbers that don't match intuition. The analysis has 31 sections across 99 sessions; surface anything worth a second look.

Test: estimation-heuristics.md updated with per-origin data. Findings presented.

Commit: `docs: update estimation heuristics with phase 7 origin segmentation (rm84-S5)`

## Constraints

- Single file (extract-timings.py) for script changes. Step 0 is a database operation (outside the script).
- Python stdlib only (no scipy/numpy)
- estimation-heuristics.md for doc updates
- Sequential execution (each step builds on prior). Each commit is a rollback point.
- After Step 0 migration, metadata origin is the primary signal for ALL beads (historical and new). The `Plan:` prefix heuristic remains as a safety-net fallback in the Python classifier, not the primary path.
- Do not split effort validation if filtered N < 20 per population — document as insufficient data instead
- `bd sql --result-format json` for all structured queries — eliminates pipe-delimiter, truncation, and positional-index fragility

## Red Team Review Findings

2 CRITICAL, 4 SERIOUS findings resolved. Key changes from red team:
- **C1+S2: JSON parsing** — switched all `bd sql` parsing from `split("|")` to `--result-format json`. Eliminates pipe-in-description breakage and positional index fragility. [red-team--gemini, red-team--openai, red-team--opus]
- **S3: DB migration** — one-time `bd sql UPDATE` sets origin on historical beads. Cleans source data permanently, simplifies script to single metadata code path. [red-team--gemini]
- **C2: Classifier validation** — Step 0 includes cross-check of heuristic against metadata ground truth + spot-check sample. [red-team--openai, red-team--opus]
- **S1: Effort N<20 fix** — N computed after all filters (estimates + attribution), not total closed beads. [all 3 providers]
- **S4: Estimation is heuristic-only** — documented explicitly in Data Reality. [red-team--opus]
- **MINOR findings acknowledged:** SQL-to-Python aggregation change noted (finding 6), heuristic-metadata agreement validated in Step 0 (finding 7), stale counts replaced with runtime baselines (finding from OpenAI), rollback strategy documented. [red-team--opus findings 5-10, red-team--openai findings 6-7]

## Acceptance Criteria

- Script runs clean across all sessions with 0 parse errors
- Section 22 shows "By Origin" segment table
- Sections 24 and 29 show work/manual split columns
- Section 31 shows per-population effort validation result
- estimation-heuristics.md updated with origin-specific correction factors
- Findings presented to user with decision matrix for effort dimension rollout

## Sources

- Solution doc: `docs/solutions/process-analysis/2026-03-14-inherited-assumption-blind-spots.md`
- Phase 6 plan: `docs/plans/2026-03-14-task-session-analysis-phase6-plan.md` (completed)
- Phase 5 plan: `docs/plans/2026-03-13-task-session-analysis-phase5-plan.md` (completed)
- Methodology: `docs/solutions/process-analysis/2026-03-13-session-log-analysis-methodology.md`
- Research: `.workflows/plan-research/task-session-analysis-phase7/agents/`
- Bead: rm84
