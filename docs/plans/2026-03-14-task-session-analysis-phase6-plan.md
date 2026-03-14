---
title: "Session Analysis Phase 6: Hook Audit, Classification Analysis, Cost Optimization"
type: task
status: completed
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
- [x] Update `MODEL_PRICING` dict to use prefix matching that distinguishes model generations (e.g., `"claude-opus-4-6"` matches before `"claude-opus-4"`)
- [x] Add entries for all model versions in the table above
- [x] Fix `get_model_pricing()` to match longest prefix first (so `claude-opus-4-6` doesn't match `claude-opus-4`)
- [x] Re-run script — all cost numbers will change
- [x] Update section 15 headline metrics, section 19 project cost, and all downstream cost references
- [x] Note: the Opus-to-Sonnet cache read ratio is now $0.50/$0.30 = 1.67x for Opus 4.6 (was assumed 6x). This dramatically reduces the projected Sonnet savings.

Impact: the $4,980 total cost figure from phase 5 is wrong. The corrected figure will be significantly different depending on the model mix (Opus 4 vs 4.6 sessions).

After running, manually verify: pick one session with known model (Opus 4.6), compute expected cost from JSONL token counts × corrected rates, verify script output matches. Document the session ID and expected values in the commit message.

Commit: `fix(session-analysis): correct MODEL_PRICING for all Claude model generations (3zr-P6-P0a)`

#### Review Findings

**Critical:**
- Opus 4.6 cache_read is overcharged 3.75x ($1.875 vs correct $0.50) — this is the dominant model in session logs, so total project cost will drop substantially after correction. [repo-research-analyst, context-researcher, learnings-researcher]
- `get_model_pricing()` loop must sort by key length descending, not rely on dict insertion order — insertion-order matching is fragile if future entries are added in any order. Use `sorted(MODEL_PRICING.items(), key=lambda x: -len(x[0]))`. [repo-research-analyst, architecture-strategist]
- `claude-opus-4-5` appears in 2 session files but has no MODEL_PRICING entry — currently falls through to (0,0,0,0) default. P0a must add this entry. [repo-research-analyst]

**Recommendations:**
- Add an inline assertion or stderr print after P0a that `get_model_pricing("claude-opus-4-6-20260101")` returns Opus 4.6 rates and `get_model_pricing("claude-opus-4-20250101")` returns Opus 4 rates — one-line safeguard against the highest-impact bug class. [architecture-strategist]
- The $493/M cache-inclusive effective rate, the 7.4x Opus:Sonnet ratio, and the $4,945 total cost are all stale post-P0a. Every downstream step must use corrected values. [learnings-researcher, context-researcher]

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

#### Review Findings

**Recommendations:**
- The hook audit log also contains non-Bash approvals (Write, Edit tools). The parser must handle all tool types, not just Bash. [repo-research-analyst]
- Multi-line commands confirmed in the log (e.g., large echo commands). The plan's parser design (lines not starting with ISO 8601 timestamp are continuations) is correct. [repo-research-analyst]

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

#### Review Findings

**Recommendations:**
- The actual parameter count is 23 (14 positional + 9 keyword), not 22 as stated. Not blocking, but the plan text is off by one. [repo-research-analyst]
- Document the `phase6_data` dict's expected keys and their types in a docstring or comment block at both the production site (in `main()`) and consumption site (in `generate_summary()`). String-keyed dicts without documentation create discovery problems. [architecture-strategist]
- The dict approach is a pragmatic bandage for phase 6. Post-phase-6, consider a dataclass (stdlib `dataclasses`) for the analysis results container. [architecture-strategist]

### Step 1: Compaction reorientation fix (Item 5)

- [x] In `extract_compaction_costs()`, apply active/idle gap detection to the reorientation window instead of reporting raw gap time
- [x] Use the same `IDLE_THRESHOLD_SECONDS` (300s) logic from `compute_active_idle()`: scan JSONL entries between compaction timestamp and first productive tool call, subtract idle gaps (>5 min between entries)
- [x] This preserves legitimate 10-30 min reorientation while filtering overnight gaps (829 min outlier)
- [x] Update section 23 (Compaction Cost) to show capped values alongside raw values
- [x] Emit updated `compaction_cost` records with both `reorientation_minutes_raw` and `reorientation_minutes_active`

Test: script runs clean, section 23 shows both raw and active reorientation, median should be similar (~5.67 min), mean should drop significantly from 25.36 min.

Commit: `fix(session-analysis): use active time for compaction reorientation (3zr-P6-S1)`

#### Review Findings

**Recommendations:**
- `compute_active_idle()` can be called directly within `extract_compaction_costs()` — the function takes `sorted_timestamps, start_ts, end_ts` and returns `active_minutes, idle_minutes, idle_gap_count, entry_count`. The reuse is confirmed feasible. [repo-research-analyst]
- Performance is negligible: ~30 compaction events * ~50 timestamps each = ~1,500 comparisons. [performance-oracle]

### Step 2: Hook audit log cross-reference (Item 1)

Note: P0b adds tool_use_id to the hook log, but all ~6,700 existing entries are legacy (3-field) format. For Phase 6, implement only the legacy matching path. The tool_use_id matching path is infrastructure for future phases — build it when enough new-format data exists (~5-10 sessions after P0b lands).

- [x] Add `parse_hook_audit_log()` function:
  - Read `.workflows/.hook-audit.log` from repo root (handle worktree by checking main worktree path)
  - Parse tab-delimited lines, handling both 3-field (legacy) and 5-field (new) formats
  - Handle multi-line commands: lines not starting with ISO 8601 timestamp pattern are continuation of previous entry
  - Return list of dicts: `{timestamp, tool_name, tool_use_id, session_id, detail}`
  - Graceful fallback: if file doesn't exist or is empty, return empty list with stderr warning

- [x] Add `cross_reference_hook_audit()` function:
  - For new-format entries (5-field): match by `tool_use_id` against JSONL tool call entries (exact key join on content block id field: in assistant messages, content blocks with `type="tool_use"` have an `"id"` field containing the tool_use_id)
  - For legacy entries (3-field): match by timestamp proximity (5-second window) + exact command string match against `bash_commands_with_ts`
  - Detect work-phase windows: sentinel files are created at work-start and deleted at work-end, so only currently-active sentinels have timestamps. For historical sessions, infer work-phase windows from JSONL session data: a work-phase window is the span from the first to last tool call in any session that has an associated stats YAML entry with `command=work` (i.e., was dispatched by `/do:work`). If no stats YAML entries exist for a session, it is not a work-phase session.
  - Classify each JSONL Bash tool call into four categories:
    - **auto-approved**: matched in hook audit log (exact tool_use_id for new-format, timestamp+command for legacy)
    - **hook-suppressed**: falls within a work-phase window (hook was disabled)
    - **ambiguous**: session contained work dispatch but window boundaries uncertain (e.g., mixed work+non-work session where suppression scope is unclear)
    - **user-prompted**: not in audit log AND not in a suppressed/ambiguous window
  - Return per-session and aggregate counts for each category
  - Note: work-phase window inference from stats YAML is approximate — it tags entire work sessions, not just the dispatch window within a session. The "ambiguous" category captures this uncertainty rather than presenting false precision.
  - Stats YAML to JSONL session join: match by timestamp overlap — each stats entry has a `timestamp` field. Find the JSONL session whose time range (first_ts to last_ts) contains the stats entry's timestamp. If no session matches, skip that stats entry.

- [x] Add section 27 "Permission Prompt Analysis (Hook Audit)" to summary.md:
  - Total Bash tool calls by category (auto-approved / hook-suppressed / user-prompted)
  - Breakdown by session
  - Comparison with section 25 proxy estimate
  - Note: work-phase data is hook-suppressed, not permission-prompted

- [x] Emit `hook_audit_analysis` records to raw-observations.jsonl

Test: script runs clean, section 27 shows three-category breakdown, user-prompted count should be lower than section 25's proxy estimate.

Commit: `feat(session-analysis): actual permission prompt counts from hook audit log (3zr-P6-S2)`

#### Review Findings

**Critical:**
- Legacy 3-field timestamp-proximity matching is fragile and covers only diminishing historical data. Consider classifying legacy entries as a separate "legacy (pre-instrumentation)" category instead of attempting fuzzy matching. This removes one of two matching codepaths and eliminates concurrent-session false-match risk. [code-simplicity-reviewer]

**Recommendations:**
- Use bisect-based matching for legacy timestamp cross-reference: sort `bash_commands_with_ts` by timestamp, use `bisect.bisect_left`/`bisect_right` to narrow the 5-second window to ~2-3 candidates per entry instead of scanning all ~5,000 commands. Reduces worst case from ~32M to ~20K comparisons. Costs 5-10 extra lines. [performance-oracle]
- Pre-index `tool_use_id` values during the main `process_session()` loop into a `{tool_use_id: (session_id, timestamp, command)}` dict. The ids are already extracted at line 1512 (`tool_id = block.get("id", "")`) but stored in `agent_dispatches` and `skill_invocations`, not a unified lookup. This avoids any need for a 6th file re-read. [performance-oracle]
- Three-category classification (auto-approved / hook-suppressed / user-prompted) is essential from day one. Do not implement a two-category version that conflates hook-suppressed with user-prompted. [learnings-researcher]
- The hook audit log has non-Bash entries (Write, Edit). Parser must handle all tool types. [repo-research-analyst]

### Step 3: Cache vs non-cache cost split (Items 7 + 8 combined)

- [x] Add `compute_phase_cost_by_token_type()` function:
  - Iterate `request_costs` per session within phase time windows (same loop as existing `phase_cost` accumulation)
  - For each request, compute four cost components: `input_cost`, `cache_creation_cost`, `cache_read_cost`, `output_cost` using `get_model_pricing()`
  - Accumulate per-phase: `{phase: {input_cost, cache_creation_cost, cache_read_cost, output_cost, total_cost}}`
  - Also accumulate globally and per-model

- [x] Modify section 19 (Project Cost) tables:
  - "Cost by Phase" table: add columns for Cache (cache_read + cache_creation), Non-cache (input + output), Cache %
  - "Cost by Model" table: add Cache/Non-cache/Cache% columns
  - "Per-Session Cost Distribution" table: add Cache/Non-cache split

- [x] Apply cache split to section 23 (Compaction Cost): add token cost breakdown (cache vs non-cache) per compaction event. The compaction cost window is the single reorientation window: from the compaction request timestamp to the first productive tool call timestamp (same window already used for reorientation measurement in Step 1).

- [x] Apply cache split to any new cost tables added in subsequent steps (cross-cutting principle)

Test: script runs clean, section 19 tables show cache/non-cache columns with populated values for all phases. Do not assert specific percentages — P0a changes all cost figures.

Commit: `feat(session-analysis): cache vs non-cache cost split across all cost tables (3zr-P6-S3)`

#### Review Findings

**Recommendations:**
- Implementation is lower-lift than it looks: the raw data already exists in `request_costs` list entries (four token counts per request). New code extends the existing phase cost loop to also accumulate per-token-type costs. No new JSONL parsing needed. [learnings-researcher]
- `compute_request_cost()` (line 399) collapses four token costs into one scalar float. The new function should call `get_model_pricing()` directly rather than trying to decompose the scalar. [learnings-researcher, repo-research-analyst]
- After Step 3, dump section 19 cost totals to stderr as a snapshot validation checkpoint. After Step 9, compare against these values to verify only Sonnet projections changed, not base costs. [architecture-strategist]
- Performance: pure arithmetic on in-memory data. ~200K trivial operations across 96 sessions. Negligible impact. [performance-oracle]

### Step 4: Classification-enriched analysis (Item 2)

- [x] Extend `compute_stats_step_timing()` to add grouping by `complexity` and `output_type`:
  - `by_complexity`: group entries by complexity tier, compute duration stats (median, P90, mean, total)
  - `by_output_type`: group entries by output type, compute same stats
  - Also compute token stats per group (median, mean tokens)

- [x] Add section 28 "Dispatch Analysis by Classification" to summary.md:
  - Duration by complexity tier table
  - Duration by output type table
  - Token usage by complexity tier
  - Cross-tabulation: complexity x output_type (count matrix)

- [x] Emit `classification_analysis` records

Test: script runs clean, section 28 shows all groupings with populated tables. Verify analytical entries are the largest group (exact % may shift with new data).

Commit: `feat(session-analysis): classification-enriched dispatch analysis (3zr-P6-S4)`

#### Review Findings

**Recommendations:**
- Stats YAML grouping on 176 entries is microsecond-level work. No performance concern. [performance-oracle]
- The first 44 entries from Phase 5 showed: mechanical 27%, analytical 61%, judgment 11%. Phase 6 extends to 176 entries. [context-researcher]

### Step 5: Cost per workflow step (Item 3)

- [x] Add `compute_step_cost()` helper:
  - Map abbreviated model names to full model prefixes using the script's `get_model_pricing()` (after P0a, this handles all 9 model variants). The abbreviated->full mapping must distinguish generations: stats YAML `model` field may say "opus" without specifying 4 vs 4.6 -- default to the model generation active during that stats entry's timestamp, or use the most common generation if ambiguous.
  - Unknown model names: skip cost computation for that entry and emit a stderr warning
  - Use stats YAML `tokens` field with the script's corrected effective rate (after P0a). The $493/M cache-inclusive rate from prior analysis is stale -- compute a fresh effective rate from the corrected `MODEL_PRICING` and observed cache:I/O ratios from Step 3 data.
  - Label all per-step costs as approximate in summary output

- [x] Extend section 20 (Step Timing from Stats YAML) with per-step cost column:
  - "Duration by Command" table: add Approx Cost column
  - "Duration by Agent" table: add Approx Cost column
  - Add note: "Cost is approximate — stats YAML captures total I/O tokens only, not cache. Uses computed cache-inclusive effective rate from corrected MODEL_PRICING."

- [x] Apply cache split principle (Item 8): per-step cost shows total only (no cache split available from stats YAML -- note the limitation)

Test: script runs clean, section 20 has cost columns, work dispatches should show higher cost than brainstorm/plan dispatches.

Commit: `feat(session-analysis): approximate per-step cost from stats YAML (3zr-P6-S5)`

#### Review Findings

**High:**
- The plan body says to compute a fresh effective rate from Step 3 data, but the output annotation note still hardcodes "$493/M." This is an internal contradiction -- the implementation should use the freshly computed rate in the annotation text, not the stale value. [repo-research-analyst]
- Step 5 has a sequential dependency on Step 3: the fresh effective rate requires Step 3's cache:I/O ratios. The plan's step ordering already handles this correctly. [learnings-researcher]

**Recommendations:**
- Consider cutting Step 5 entirely. Per-step cost from stats YAML is fundamentally approximate (no cache granularity), the plan contradicts itself on the rate to use, and existing duration data in section 20 already communicates relative sizing. If per-step cost is needed later, derive it from Step 3's per-phase JSONL data. [code-simplicity-reviewer]
- If Step 5 is kept, the `tokens` field in stats YAML is I/O-only (confirmed: comes from `<usage>` block which lacks cache fields). Using a naive per-token rate produces ~700x cost errors unless the cache-inclusive effective rate is used with explicit approximation labels. [learnings-researcher]

### Step 6: Session cost vs productivity correlation (Item 4)

- [x] Add `compute_cost_productivity_correlation()` function:
  - Bucket `session_total_cost` by session start date (same pattern as `active_minutes_by_date`)
  - Join with bead closures by date (reuse `load_bead_closures_by_date()` which queries `SELECT DATE(closed_at) as date, COUNT(*) as count FROM issues WHERE status='closed' AND closed_at IS NOT NULL GROUP BY DATE(closed_at) ORDER BY date`)
  - Exclude dates with active_hours < 1.0 (filters batch-closure dates like Mar 9/10 -- document exclusion)
  - Compute cost-per-bead-closed: daily_cost / daily_closures for each qualifying date, plus overall average
  - Compute beads-per-dollar: daily_closures / daily_cost
  - Compute manual Pearson correlation using `statistics.stdev` (no scipy) — include but note "N=5, will become meaningful as more data accumulates"

- [x] Add section 29 "Cost vs Productivity" to summary.md:
  - Daily table: Date, Cost, Beads Closed, Cost/Bead, Active Hours, Beads/Dollar
  - Pearson correlation coefficient (with N and caveat about small sample)
  - Trend direction: is cost/bead increasing (diminishing returns) or stable?

- [x] Apply cache split principle: daily cost shows cache/non-cache breakdown

- [x] Emit `cost_productivity` records

Test: script runs clean, section 29 shows correlation table, excluded dates noted.

Commit: `feat(session-analysis): session cost vs productivity correlation (3zr-P6-S6)`

#### Review Findings

**High:**
- Pearson correlation with N~5 is statistical theater. After exclusions (active_hours < 1.0, zero-bead days, the Mar 8 outlier with 45.4 active hours), usable data points drop to approximately 5 dates. The t-test has 3 degrees of freedom -- almost anything fails to reject the null. A single outlier dominates the regression. [code-simplicity-reviewer]

**Recommendations:**
- Replace Step 6 with a simple "Cost per Bead Closed" summary table: daily_cost / daily_closures for each qualifying date, plus an overall average. No Pearson, no correlation coefficient, no trend analysis. This answers the actual question ("is cost/bead stable?") without pretending to do statistics. Estimated reduction: ~60% of Step 6 implementation effort. [code-simplicity-reviewer]
- If Pearson is kept, the caveat must be prominent (not a footnote). N=5 Pearson is not actionable. [code-simplicity-reviewer]
- Performance is trivial regardless of approach: ~10-15 data points, microsecond computation. [performance-oracle]

### Step 7: **MERGED INTO STEP 9** — see Step 9 (Sonnet migration analysis) which combines model selection data and savings estimation into one step with per-phase and per-tier sub-functions.

### Step 8: Effort dimension validation (Item 9)

- [x] Define effort classification criteria (retroactive, session_count + estimate_size only — tool diversity dropped as too coarse at whole-session granularity):
  - **routine**: single-session AND <15 min estimate
  - **involved**: single-session AND 15-60 min estimate
  - **exploratory**: multi-session (2-3 sessions) OR >60 min estimate
  - **pioneering**: multi-session (4+ sessions) AND >120 min actual time (both thresholds required)

- [x] Add `classify_bead_effort()` function:
  - Input: bead ID, windowed attribution data (sessions, actual_minutes), estimate data (estimated_minutes)
  - Session count from `bead_attribution_windowed[bead_id]["sessions"]`
  - Output: effort tier string

- [x] Apply to all closed beads with windowed attribution data
- [x] Correlate effort tier with estimation accuracy (actual/estimated ratio) -- same segmentation pattern as section 22
- [x] Compare predictive power: does effort tier predict blowups better than type alone? Better than session count? Validation threshold: effort tiers must reduce mean estimation error by at least 25% vs session-count alone. If they do not, skip rollout (Step 11) without further deliberation.

- [x] Add section 31 "Estimation Accuracy by Effort" to summary.md:
  - Effort tier distribution table
  - Accuracy by effort tier (median, mean, N, under/over count)
  - Comparison with type-based and session-count-based segmentation

- [x] If effort validates: print recommended `bd update` commands to stderr for manual execution (analysis script should not mutate the database)

- [x] Emit `effort_validation` records

Test: script runs clean, section 31 shows effort tiers with accuracy correlation.

Commit: `feat(session-analysis): effort dimension validation on closed beads (3zr-P6-S8)`

#### Review Findings

**High:**
- The effort dimension has no prior documentation anywhere in the knowledge base. This is entirely new in Phase 6 -- the classification criteria are first-time definitions with no baseline to validate against. The conditional rollout gate (Step 11) is appropriate. [context-researcher]
- Tool diversity criterion is a proxy of a proxy: whole-session tool counting for per-bead windows means a bead active during 20% of a session gets credited with all tool types from the entire session. This is noise, not signal. [code-simplicity-reviewer]
- N will be small per tier. ~90 beads split across 4 tiers will have some tiers with N < 10. The "pioneering" tier (4+ sessions AND >120 min) will likely have only 2-5 beads. [code-simplicity-reviewer]
- Section 22 already shows multi-session beads have 4.27x median accuracy ratio vs single-session at 0.51x -- a loud, clean signal from a single binary variable. The effort dimension is trying to add nuance to an already-clear split. [code-simplicity-reviewer]

**Recommendations:**
- Simplify effort criteria: drop tool diversity (too coarse at whole-session granularity). Use only session_count + estimate_size as tier criteria -- these are already available without new computation. [code-simplicity-reviewer]
- Remove `bd update` side-effect from the analysis script. An analysis script should not mutate the database. If tiers validate, do bd updates as a manual post-analysis step. [code-simplicity-reviewer]
- Define a specific validation threshold before implementation: effort tiers must reduce mean estimation error by at least 25% vs session-count alone. If they do not, skip rollout without further deliberation. [code-simplicity-reviewer]
- Performance is fine: ~50 closed beads, pure in-memory classification. Negligible. [performance-oracle]

### Step 9: Sonnet migration analysis (Items 6 + 11 merged)

Merge model selection data (former Step 7) and Sonnet savings re-estimation into one step with two internal functions. Frame as **quota/throughput freed**, not dollar savings — user is on Max 20x plan.

- [x] Add `compute_sonnet_migration_analysis()` with two sub-functions:
  - `_per_phase_projections()`: for each phase, compute what cache_read cost would be at Sonnet rates vs Opus rates. Use corrected `get_model_pricing()` — do NOT hardcode rates. Ratio depends on model generation (1.67x for Opus 4.6, 5x for Opus 4).
  - `_per_tier_projections()`: group stats YAML entries by complexity tier AND output_type. For each group: Opus vs Sonnet dispatch counts, tokens, duration, projected Sonnet cost. Note: nearly all dispatches are Opus — this is a projection.
  - "Movable dispatches" = mechanical + analytical complexity tiers (not judgment)
  - Exclude research agents already on Sonnet (5 agents + relay) from savings opportunities

- [x] Baseline: rough 10-15% estimate from xu2/sze8 bead notes (computed with wrong pricing — will be recalculated after P0a)

- [x] Add section 30 "Sonnet Migration Analysis" to summary.md (replaces former sections 30+32):
  - Lead with quota impact ("moving mechanical dispatches to Sonnet frees X% of Opus quota for judgment work"), include dollar amounts alongside for completeness
  - Per-phase: current cost, projected Sonnet cost, quota freed %, dollar savings
  - Per-complexity tier: same structure, highlighting which tiers have highest savings potential
  - Total quota impact vs baseline estimate
  - Note: projection assumes Sonnet produces equivalent quality for mechanical/analytical work — quality validation is a separate concern (xu2/sze8 scope)
  - Note: orchestrator is 50-70% of total Opus cost and untouchable with subagent routing

- [x] Emit `sonnet_savings_estimate` records

Test: script runs clean, section 32 shows before/after comparison with baseline.

Commit: `feat(session-analysis): re-estimate Sonnet savings with actual cache data (3zr-P6-S9)`

#### Review Findings

**Critical:**
- The 10-15% Sonnet savings baseline is almost certainly wrong. It was computed using a 7.4x Opus:Sonnet effective rate ratio based on Opus 4 pricing. With Opus 4.6 dominant and cache_read at $0.50 vs Sonnet $0.30, the ratio is only 1.67x. Expect dramatically lower savings for recent sessions. This is expected and correct, not a script bug -- document the before/after explicitly. [context-researcher, learnings-researcher]
- User is on Max 20x plan: Sonnet downgrades are a throughput/quota issue, not a dollar savings issue. Frame section 32 output accordingly. [context-researcher]

**Recommendations:**
- If Step 7 is kept as a separate step, Step 9 should absorb Step 7's per-tier projections to avoid two overlapping Sonnet savings sections. [code-simplicity-reviewer]
- Research agents already on Sonnet (5 agents + relay) should be excluded from "savings opportunities" -- they are already optimized. [context-researcher]
- Orchestrator is 50-70% of total Opus cost and untouchable with subagent routing. Section 32 must note this constraint. [context-researcher]

### Step 10: Update estimation heuristics (Item 12 partial)

- [x] Re-run the full script to generate fresh outputs: `python3 .workflows/session-analysis/extract-timings.py`
- [x] Read `.workflows/session-analysis/summary.md` for new sections 27-31
- [x] Update `.claude/memory/estimation-heuristics.md` with:
  - Actual permission prompt count (replacing proxy estimate)
  - Per-phase cache vs non-cache cost
  - Effort dimension findings (if predictive)
  - Updated Sonnet savings estimate (replacing rough 10-15%)
  - Cost-productivity trend
  - Any new coverage gaps
- [x] Write before/after report: which numbers changed, by how much, why

Test: estimation-heuristics.md has all new sections.

Commit: `docs: update estimation heuristics with phase 6 findings (3zr-P6-S10)`

#### Review Findings

**Recommendations:**
- Preserve all validated correction factors from estimation-heuristics.md: bug 2.0x, task 0.6x, multi-session 3.0x, >60min estimate 3.0x, P2 1.5x, subagent-only step 0.15x. If phase 6's new sessions shift these values, document before/after with N counts. Do not silently overwrite. [learnings-researcher]
- Consider reordering: present findings (current Step 12) before committing to doc changes (Step 10). This lets the user course-correct before docs are updated. [code-simplicity-reviewer]

### Step 11: Effort instruction rollout (Item 10)

- [x] Only if Step 8 validates that effort tiers are predictive (better than type alone):
  - Update AGENTS.md bead creation instructions to include `--metadata '{"effort": "<tier>"}'`
  - Add to bd create examples alongside `--estimate` and `--metadata` impact
  - Add to Memory Hot Cache section
- [x] If effort is NOT predictive: note the finding, skip the rollout, update y53x bead with "effort dimension did not validate -- do not roll out"

Test: AGENTS.md has effort tag in bead creation examples (or documented reason for skipping).

Commit: `docs: add effort dimension to bead creation instructions (3zr-P6-S11)` (or `docs: effort dimension did not validate -- skip rollout`)

#### Review Findings

**Recommendations:**
- Editing AGENTS.md (high-traffic file affecting all sessions) for a dimension derived from ~90 beads is premature. Even if effort tiers validate on the current dataset, consider deferring AGENTS.md changes until a second cycle confirms the findings. [code-simplicity-reviewer]
- The validation criteria "better than type alone" is not quantified. Define a specific threshold: effort tiers must reduce mean estimation error by at least 25% vs session-count alone. [code-simplicity-reviewer]

### Step 12: Present findings to user (Item 12)

- [x] This is not a script step -- it's the orchestrator presenting results after all steps complete
- [ ] Walk through all new/changed numbers from new sections
- [ ] Compare with phase 5 values -- what changed, what's new
- [ ] Present decision matrix for each analysis area:
  - **Sonnet migration**: if quota freed > 10% for mechanical/analytical tiers → recommend proceeding with xu2/sze8. If < 5% → savings too small to justify risk.
  - **Effort dimension**: if tiers reduce mean estimation error by >= 25% vs session-count → roll out (Step 11). If not → document finding and skip rollout.
  - **Cost-productivity**: present cost/bead trend. If stable → current process is efficient. If increasing → investigate why.
  - **Permission prompts**: present actual count vs proxy. If actual < proxy → proxy was conservative, no action. If actual > proxy → investigate missed patterns.

## Acceptance Criteria

- Script runs clean across all 93+ sessions with 0 parse errors
- 5 new summary sections (27-31) added (Steps 7+9 merged into one section)
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

## Architectural Observations

These findings from the architecture review are not blockers for phase 6 but should inform execution and post-phase-6 planning.

#### Review Findings

**High:**
- The script at 5,352 lines is already beyond comfortable single-file size. Phase 6 adds ~1,150 lines (22% growth) to ~6,500 lines. Accept the growth for phase 6 but create a bead for post-phase-6 restructuring. [architecture-strategist]
- `main()` at 766 lines performs 5 distinct responsibilities. Phase 6 pushes it past 960 lines. Variable scope pollution risk increases with 30+ local dicts. [architecture-strategist]
- `generate_summary()` at 1,814 lines will grow to ~2,200 lines. Each of its 26 (soon 32) section blocks is 30-100 lines consuming different parameter subsets. [architecture-strategist]

**Recommendations:**
- Extract the "derived analysis" block (L3100-L3425 plus new phase 6 code) from `main()` into `compute_derived_analyses(session_data, raw_out) -> dict`. This is a mechanical extraction with low risk that reduces `main()` by ~500 lines and naturally produces the `phase6_data` dict. Can be done as Step 0 before Step 1. [architecture-strategist]
- Post-phase-6: extract each summary section into its own renderer function (e.g., `render_section_19_project_cost(lines, data)`). This is the single highest-leverage structural improvement -- reduces `generate_summary()` to ~200 lines of ordering logic. [architecture-strategist]
- Post-phase-6: consider whether future analysis should consume `raw-observations.jsonl` via new scripts rather than extending extract-timings.py further. The JSONL output was designed as a stable intermediate format. [architecture-strategist]
- Natural module split points exist: parsers.py, analysis.py, rendering.py, extract_timings.py (thin orchestrator). Each ~1,200-1,800 lines. Defer to post-phase-6. [architecture-strategist]

## Related Beads (stats collection improvements)

These beads were created during phase 6 planning for future improvements. They are NOT prerequisites for phase 6 execution -- phase 6 works with current data. They improve data quality for future analysis.

- **5wsw** (P2) -- Add tool_use_id + session_id to hook audit log (folded into P0 above)
- **1cep** (P3) -- Auto-classify stats entries at capture time
- **gl69** (P3) -- Add session_id to stats YAML entries
- **3vte** (P3) -- Log hook fall-through for complete permission prompt coverage
- **ncjb** (P3) -- Add dispatch parent tracking to stats YAML

## Sources

- Phase 5 plan: `docs/plans/2026-03-13-task-session-analysis-phase5-plan.md` (completed)
- Phase 4 methodology: `docs/solutions/process-analysis/2026-03-13-session-log-analysis-methodology.md`
- Cost modeling: `docs/solutions/cost-modeling/2026-03-11-dynamic-model-routing-cost-analysis.md`
- Research: `.workflows/plan-research/task-session-analysis-phase6/agents/`
- Deepen research: `.workflows/deepen-plan/task-session-analysis-phase6/agents/run-1/`
- Bead: y53x (12 items in notes)
- Related beads: xu2 (Sonnet work subagents), sze8 (downgrade analytical agents), 1hu4 (reduce confirmations), tz4b (velocity ramp)
