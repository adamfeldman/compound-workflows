---
title: "Session Analysis Phase 6: Hook Audit, Classification Analysis, Cost Optimization"
type: task
status: active
date: 2026-03-14
bead: y53x
---

# Session Analysis Phase 6: Hook Audit, Classification Analysis, Cost Optimization

## Goal

Extend extract-timings.py with 12 analysis items plus 1 prerequisite infrastructure fix. Produce per-phase cache vs non-cache cost splits, actual permission prompt counts from hook audit log, classification-enriched timing data, effort dimension validation, and updated Sonnet savings estimates. Present all findings to user at end.

## Prerequisites

### P0a: Fix MODEL_PRICING in extract-timings.py

The script's `MODEL_PRICING` dict has incorrect rates. Multiple model generations exist with different pricing. The script must match model names to the correct rates.

Current (wrong):
```python
"claude-opus-4": (15, 3.75, 1.875, 75)  # wrong cache_read ($1.875 should be $1.50), and doesn't distinguish Opus 4.6
```

Correct rates from Anthropic pricing page (verified 2026-03-14):

| Model | Input | Cache Write (5min) | Cache Read | Output |
|-------|-------|--------------------|------------|--------|
| Claude Opus 4.6 | $5 | $6.25 | $0.50 | $25 |
| Claude Opus 4.5 | $5 | $6.25 | $0.50 | $25 |
| Claude Opus 4.1 | $15 | $18.75 | $1.50 | $75 |
| Claude Opus 4 | $15 | $18.75 | $1.50 | $75 |
| Claude Sonnet 4.6 | $3 | $3.75 | $0.30 | $15 |
| Claude Sonnet 4.5 | $3 | $3.75 | $0.30 | $15 |
| Claude Sonnet 4 | $3 | $3.75 | $0.30 | $15 |
| Claude Haiku 4.5 | $1 | $1.25 | $0.10 | $5 |
| Claude Haiku 3 | $0.25 | $0.30 | $0.03 | $1.25 |

Tasks:
- [ ] Update `MODEL_PRICING` dict to use prefix matching that distinguishes model generations (e.g., `"claude-opus-4-6"` matches before `"claude-opus-4"`)
- [ ] Add entries for all model versions in the table above
- [ ] Fix `get_model_pricing()` to match longest prefix first (so `claude-opus-4-6` doesn't match `claude-opus-4`)
- [ ] Re-run script — all cost numbers will change
- [ ] Update section 15 headline metrics, section 19 project cost, and all downstream cost references
- [ ] Note: the Opus-to-Sonnet cache read ratio is now $0.50/$0.30 = 1.67x for Opus 4.6 (was assumed 6x). This dramatically reduces the projected Sonnet savings.

Impact: the $4,980 total cost figure from phase 5 is wrong. The corrected figure will be significantly different depending on the model mix (Opus 4 vs 4.6 sessions).

Commit: `fix(session-analysis): correct MODEL_PRICING for all Claude model generations (3zr-P6-P0a)`

### P0b: Add tool_use_id and session_id to hook audit log (bead 5wsw)

One-line change in `auto-approve.sh` `log_approval()`:

```python
# Current:
printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$tool_name" "$detail"
# New:
tool_use_id="$(echo "$input" | jq -r '.tool_use_id // empty' 2>/dev/null)"
session_id="$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)"
printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$tool_name" "${tool_use_id:-none}" "${session_id:-none}" "$detail"
```

New log format: `TIMESTAMP\tTOOL_NAME\tTOOL_USE_ID\tSESSION_ID\tDETAIL`

Historical entries (pre-change) have 3 fields. The parser must handle both 3-field (legacy) and 5-field (new) formats.

Test: run a few commands after the change, verify new fields appear in `.workflows/.hook-audit.log`.

Commit: `fix(hooks): add tool_use_id and session_id to hook audit log (5wsw)`

## Data Sources

| Source | What it has | Phase 6 use |
|--------|------------|-------------|
| JSONL sessions (93+ files) | Per-request billing (4 token types), model, tool calls, timestamps | Cache splits, hook cross-ref, cost correlation |
| Stats YAML (34+ files, 176 entries) | Per-dispatch tokens, duration_ms, model, complexity, output_type | Classification analysis, model selection data |
| Hook audit log (6485+ lines) | Auto-approved tool calls with timestamps, tool_use_id (after P0), session_id (after P0) | Permission prompt counts |
| Beads database | Priority, type, estimated_minutes, metadata, labels, closed_at | Effort validation, productivity correlation |
| `.work-in-progress.d/` sentinel files | Per-session timestamps of work-phase execution | Identify hook-suppressed windows |

## Implementation Steps

All steps modify `.workflows/session-analysis/extract-timings.py` unless noted. Steps are sequential (single file).

### Design Decision: generate_summary() parameter grouping

Group all phase 6 data into a single `phase6_data` dict parameter passed to `generate_summary()`, rather than adding 6-8 individual parameters to the already-22-parameter signature. The dict keys correspond to analysis function return values.

### Step 1: Compaction reorientation fix (Item 5)

- [ ] In `extract_compaction_costs()`, apply active/idle gap detection to the reorientation window instead of reporting raw gap time
- [ ] Use the same `IDLE_THRESHOLD_SECONDS` (300s) logic from `compute_active_idle()`: scan JSONL entries between compaction timestamp and first productive tool call, subtract idle gaps (>5 min between entries)
- [ ] This preserves legitimate 10-30 min reorientation while filtering overnight gaps (829 min outlier)
- [ ] Update section 23 (Compaction Cost) to show capped values alongside raw values
- [ ] Emit updated `compaction_cost` records with both `reorientation_minutes_raw` and `reorientation_minutes_active`

Test: script runs clean, section 23 shows both raw and active reorientation, median should be similar (~5.67 min), mean should drop significantly from 25.36 min.

Commit: `fix(session-analysis): use active time for compaction reorientation (3zr-P6-S1)`

### Step 2: Hook audit log cross-reference (Item 1, bead 5wsw prerequisite)

- [ ] Add `parse_hook_audit_log()` function:
  - Read `.workflows/.hook-audit.log` from repo root (handle worktree by checking main worktree path)
  - Parse tab-delimited lines, handling both 3-field (legacy) and 5-field (new) formats
  - Handle multi-line commands: lines not starting with ISO 8601 timestamp pattern are continuation of previous entry
  - Return list of dicts: `{timestamp, tool_name, tool_use_id, session_id, detail}`
  - Graceful fallback: if file doesn't exist or is empty, return empty list with stderr warning

- [ ] Add `cross_reference_hook_audit()` function:
  - For new-format entries (5-field): match by `tool_use_id` against JSONL tool call entries (exact key join on content block id field: in assistant messages, content blocks with `type="tool_use"` have an `"id"` field containing the tool_use_id)
  - For legacy entries (3-field): match by timestamp proximity (5-second window) + exact command string match against `bash_commands_with_ts`
  - Detect work-phase windows: sentinel files are created at work-start and deleted at work-end, so only currently-active sentinels have timestamps. For historical sessions, infer work-phase windows from JSONL session data: a work-phase window is the span from the first to last tool call in any session that has an associated stats YAML entry with `command=work` (i.e., was dispatched by `/do:work`). If no stats YAML entries exist for a session, it is not a work-phase session.
  - Classify each JSONL Bash tool call into three categories:
    - **auto-approved**: matched in hook audit log
    - **hook-suppressed**: falls within a work-phase window (hook was disabled)
    - **user-prompted**: not in audit log AND not in a suppressed window
  - Return per-session and aggregate counts for each category

- [ ] Add section 27 "Permission Prompt Analysis (Hook Audit)" to summary.md:
  - Total Bash tool calls by category (auto-approved / hook-suppressed / user-prompted)
  - Breakdown by session
  - Comparison with section 25 proxy estimate
  - Note: work-phase data is hook-suppressed, not permission-prompted

- [ ] Emit `hook_audit_analysis` records to raw-observations.jsonl

Test: script runs clean, section 27 shows three-category breakdown, user-prompted count should be lower than section 25's proxy estimate.

Commit: `feat(session-analysis): actual permission prompt counts from hook audit log (3zr-P6-S2)`

### Step 3: Cache vs non-cache cost split (Items 7 + 8 combined)

- [ ] Add `compute_phase_cost_by_token_type()` function:
  - Iterate `request_costs` per session within phase time windows (same loop as existing `phase_cost` accumulation)
  - For each request, compute four cost components: `input_cost`, `cache_creation_cost`, `cache_read_cost`, `output_cost` using `get_model_pricing()`
  - Accumulate per-phase: `{phase: {input_cost, cache_creation_cost, cache_read_cost, output_cost, total_cost}}`
  - Also accumulate globally and per-model

- [ ] Modify section 19 (Project Cost) tables:
  - "Cost by Phase" table: add columns for Cache (cache_read + cache_creation), Non-cache (input + output), Cache %
  - "Cost by Model" table: add Cache/Non-cache/Cache% columns
  - "Per-Session Cost Distribution" table: add Cache/Non-cache split

- [ ] Apply cache split to section 23 (Compaction Cost): add token cost breakdown (cache vs non-cache) per compaction event. The compaction cost window is the single reorientation window: from the compaction request timestamp to the first productive tool call timestamp (same window already used for reorientation measurement in Step 1).

- [ ] Apply cache split to any new cost tables added in subsequent steps (cross-cutting principle)

Test: script runs clean, section 19 tables show cache/non-cache columns, cache% should be ~89% overall as validated in conversation.

Commit: `feat(session-analysis): cache vs non-cache cost split across all cost tables (3zr-P6-S3)`

### Step 4: Classification-enriched analysis (Item 2)

- [ ] Extend `compute_stats_step_timing()` to add grouping by `complexity` and `output_type`:
  - `by_complexity`: group entries by complexity tier, compute duration stats (median, P90, mean, total)
  - `by_output_type`: group entries by output type, compute same stats
  - Also compute token stats per group (median, mean tokens)

- [ ] Add section 28 "Dispatch Analysis by Classification" to summary.md:
  - Duration by complexity tier table
  - Duration by output type table
  - Token usage by complexity tier
  - Cross-tabulation: complexity × output_type (count matrix)

- [ ] Emit `classification_analysis` records

Test: script runs clean, section 28 shows all groupings, analytical should dominate (~69% of entries).

Commit: `feat(session-analysis): classification-enriched dispatch analysis (3zr-P6-S4)`

### Step 5: Cost per workflow step (Item 3)

- [ ] Add `compute_step_cost()` helper:
  - Map abbreviated model names to full model prefixes using the script's `get_model_pricing()` (after P0a, this handles all 9 model variants). The abbreviated→full mapping must distinguish generations: stats YAML `model` field may say "opus" without specifying 4 vs 4.6 — default to the model generation active during that stats entry's timestamp, or use the most common generation if ambiguous.
  - Unknown model names: skip cost computation for that entry and emit a stderr warning
  - Use stats YAML `tokens` field with the script's corrected effective rate (after P0a). The $493/M cache-inclusive rate from prior analysis is stale — compute a fresh effective rate from the corrected `MODEL_PRICING` and observed cache:I/O ratios from Step 3 data.
  - Label all per-step costs as approximate in summary output

- [ ] Extend section 20 (Step Timing from Stats YAML) with per-step cost column:
  - "Duration by Command" table: add Approx Cost column
  - "Duration by Agent" table: add Approx Cost column
  - Add note: "Cost is approximate — stats YAML captures total I/O tokens only, not cache. Uses $493/M cache-inclusive effective rate."

- [ ] Apply cache split principle (Item 8): per-step cost shows total only (no cache split available from stats YAML — note the limitation)

Test: script runs clean, section 20 has cost columns, work dispatches should show higher cost than brainstorm/plan dispatches.

Commit: `feat(session-analysis): approximate per-step cost from stats YAML (3zr-P6-S5)`

### Step 6: Session cost vs productivity correlation (Item 4)

- [ ] Add `compute_cost_productivity_correlation()` function:
  - Bucket `session_total_cost` by session start date (same pattern as `active_minutes_by_date`)
  - Join with bead closures by date (reuse `load_bead_closures_by_date()` which queries `SELECT DATE(closed_at) as date, COUNT(*) as count FROM issues WHERE status='closed' AND closed_at IS NOT NULL GROUP BY DATE(closed_at) ORDER BY date`)
  - Exclude dates with active_hours < 1.0 (filters batch-closure dates like Mar 9/10 — document exclusion)
  - Compute manual Pearson correlation using `statistics.stdev` (no scipy)
  - Compute cost-per-bead-closed trend: daily_cost / daily_closures
  - Compute beads-per-dollar trend: daily_closures / daily_cost

- [ ] Add section 29 "Cost vs Productivity" to summary.md:
  - Daily table: Date, Cost, Beads Closed, Cost/Bead, Active Hours, Beads/Dollar
  - Pearson correlation coefficient (with N and caveat about small sample)
  - Trend direction: is cost/bead increasing (diminishing returns) or stable?

- [ ] Apply cache split principle: daily cost shows cache/non-cache breakdown

- [ ] Emit `cost_productivity` records

Test: script runs clean, section 29 shows correlation table, excluded dates noted.

Commit: `feat(session-analysis): session cost vs productivity correlation (3zr-P6-S6)`

### Step 7: Model selection optimization data (Item 6)

- [ ] Add `compute_model_selection_data()` function:
  - Group stats YAML entries by complexity tier AND by output_type
  - For each group: count of Opus vs Sonnet dispatches, total tokens, total duration, approx cost
  - Compute hypothetical savings: "if all Opus dispatches in this group used Sonnet, cost would be X" using the cache read rate difference (ratio depends on model generation — 1.67x for Opus 4.6, 5x for Opus 4)
  - Note: most/all dispatches are Opus — this is a projection, not an empirical comparison

- [ ] Add section 30 "Model Selection Analysis" to summary.md:
  - By complexity: table showing dispatches, tokens, cost, projected Sonnet cost, savings
  - By output_type: same table structure
  - Highlight: which complexity tiers and output types have the highest savings potential

Test: script runs clean, section 30 shows savings projections per tier.

Commit: `feat(session-analysis): model selection optimization by classification (3zr-P6-S7)`

### Step 8: Effort dimension validation (Item 9)

- [ ] Define effort classification criteria (retroactive, computed from observed patterns):
  - **routine**: single-session, <15 min estimate, <3 unique tool types used, no Agent dispatches
  - **involved**: single-session, 15-60 min estimate OR 3+ tool types, may have Agent dispatches
  - **exploratory**: multi-session (2-3 sessions) OR >60 min estimate OR >50% read/grep tool calls (investigation-heavy)
  - **pioneering**: multi-session (4+ sessions) AND >120 min actual time (both thresholds required)

- [ ] Add `classify_bead_effort()` function:
  - Input: bead ID, windowed attribution data (sessions, actual_minutes, tool-call breakdown from proportional allocation), estimate data (estimated_minutes, type, priority)
  - Session count from `bead_attribution_windowed[bead_id]["sessions"]`
  - Tool diversity from session data (count unique tool types across ALL sessions where bead was active — coarser whole-session granularity, not per-window; uses existing `bead_attribution_windowed` session list)
  - Output: effort tier string

- [ ] Apply to all closed beads with windowed attribution data
- [ ] Correlate effort tier with estimation accuracy (actual/estimated ratio) — same segmentation pattern as section 22
- [ ] Compare predictive power: does effort tier predict blowups better than type alone? Better than session count?

- [ ] Add section 31 "Estimation Accuracy by Effort" to summary.md:
  - Effort tier distribution table
  - Accuracy by effort tier (median, mean, N, under/over count)
  - Comparison with type-based and session-count-based segmentation

- [ ] Store effort classification in metadata: `bd update <id> --metadata '{"effort": "<tier>"}'` for closed beads where effort was computed (script prints bd update commands to stdout, one per line; orchestrator captures and runs them)

- [ ] Emit `effort_validation` records

Test: script runs clean, section 31 shows effort tiers with accuracy correlation.

Commit: `feat(session-analysis): effort dimension validation on closed beads (3zr-P6-S8)`

### Step 9: Re-estimate Sonnet savings (Item 11)

- [ ] Using per-phase cache split data from Step 3, compute:
  - For each phase: what would cache_read cost be at Sonnet rates vs current Opus rates? Use the script's corrected `get_model_pricing()` (after P0a) — do NOT hardcode rates
  - For each complexity tier from Step 4: same projection
  - Total projected savings = sum of (opus_cache_read_cost - sonnet_cache_read_cost) for movable dispatches
  - "Movable dispatches" = mechanical + analytical complexity tiers (not judgment)
  - Note: the Opus-to-Sonnet cache ratio varies by model generation (1.67x for Opus 4.6, 5x for Opus 4). Savings projections must account for the actual model used per dispatch.

- [ ] Baseline: rough 10-15% estimate from xu2/sze8 bead notes (computed with wrong pricing — will be recalculated after P0a)

- [ ] Add section 32 "Sonnet Migration Savings Estimate" to summary.md:
  - Per-phase: current cost, projected Sonnet cost, savings, savings %
  - Per-complexity: same structure
  - Total savings vs baseline estimate
  - Note: projection assumes Sonnet produces equivalent quality for mechanical/analytical work

- [ ] Emit `sonnet_savings_estimate` records

Test: script runs clean, section 32 shows before/after comparison with baseline.

Commit: `feat(session-analysis): re-estimate Sonnet savings with actual cache data (3zr-P6-S9)`

### Step 10: Update estimation heuristics (Item 12 partial)

- [ ] Re-run the full script to generate fresh outputs: `python3 .workflows/session-analysis/extract-timings.py`
- [ ] Read `.workflows/session-analysis/summary.md` for new sections 27-32
- [ ] Update `.claude/memory/estimation-heuristics.md` with:
  - Actual permission prompt count (replacing proxy estimate)
  - Per-phase cache vs non-cache cost
  - Effort dimension findings (if predictive)
  - Updated Sonnet savings estimate (replacing rough 10-15%)
  - Cost-productivity trend
  - Any new coverage gaps
- [ ] Write before/after report: which numbers changed, by how much, why

Test: estimation-heuristics.md has all new sections.

Commit: `docs: update estimation heuristics with phase 6 findings (3zr-P6-S10)`

### Step 11: Effort instruction rollout (Item 10)

- [ ] Only if Step 8 validates that effort tiers are predictive (better than type alone):
  - Update AGENTS.md bead creation instructions to include `--metadata '{"effort": "<tier>"}'`
  - Add to bd create examples alongside `--estimate` and `--metadata` impact
  - Add to Memory Hot Cache section
- [ ] If effort is NOT predictive: note the finding, skip the rollout, update y53x bead with "effort dimension did not validate — do not roll out"

Test: AGENTS.md has effort tag in bead creation examples (or documented reason for skipping).

Commit: `docs: add effort dimension to bead creation instructions (3zr-P6-S11)` (or `docs: effort dimension did not validate — skip rollout`)

### Step 12: Present findings to user (Item 12)

- [ ] This is not a script step — it's the orchestrator presenting results after all steps complete
- [ ] Walk through all new/changed numbers from sections 27-32
- [ ] Compare with phase 5 values — what changed, what's new
- [ ] Highlight actionable findings (Sonnet savings, effort predictiveness, actual permission prompt count)

## Acceptance Criteria

- Script runs clean across all 93+ sessions with 0 parse errors
- 6 new summary sections (27-32) added
- All cost tables show cache vs non-cache split
- Hook audit produces actual permission prompt counts (three categories)
- Effort dimension validated or explicitly rejected
- Sonnet savings re-estimated with actual cache ratios
- estimation-heuristics.md updated
- Before/after report presented to user

## Constraints

- Single file (extract-timings.py) for all script changes
- Python stdlib only (no scipy/numpy)
- estimation-heuristics.md and AGENTS.md for doc updates
- Sequential execution (single file)
- P0 prerequisite (hook audit log change) is in auto-approve.sh, not extract-timings.py

## Related Beads (stats collection improvements)

These beads were created during phase 6 planning for future improvements. They are NOT prerequisites for phase 6 execution — phase 6 works with current data. They improve data quality for future analysis.

- **5wsw** (P2) — Add tool_use_id + session_id to hook audit log (folded into P0 above)
- **1cep** (P3) — Auto-classify stats entries at capture time
- **gl69** (P3) — Add session_id to stats YAML entries
- **3vte** (P3) — Log hook fall-through for complete permission prompt coverage
- **ncjb** (P3) — Add dispatch parent tracking to stats YAML

## Sources

- Phase 5 plan: `docs/plans/2026-03-13-task-session-analysis-phase5-plan.md` (completed)
- Phase 4 methodology: `docs/solutions/process-analysis/2026-03-13-session-log-analysis-methodology.md`
- Cost modeling: `docs/solutions/cost-modeling/2026-03-11-dynamic-model-routing-cost-analysis.md`
- Research: `.workflows/plan-research/task-session-analysis-phase6/agents/`
- Bead: y53x (12 items in notes)
- Related beads: xu2 (Sonnet work subagents), sze8 (downgrade analytical agents), 1hu4 (reduce confirmations), tz4b (velocity ramp)
