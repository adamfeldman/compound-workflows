---
title: "Session Analysis Phase 5: Stats Mining & Heuristic Tightening"
type: task
status: completed
date: 2026-03-13
bead: 3zr
---

# Session Analysis Phase 5: Stats Mining & Heuristic Tightening

## Goal

Mine existing data sources (stats YAML files, JSONL session logs) to produce 9 new analysis outputs, then tighten estimation heuristics based on findings. All changes go into `extract-timings.py` and `estimation-heuristics.md` — no plugin skill files touched.

## Data Sources

| Source | What it has | Gap |
|--------|------------|-----|
| JSONL sessions (89 files, ~200MB) | Per-request billing (input, cache_creation, cache_read, output tokens), model field, AskUserQuestion events, Skill invocations, isCompactSummary | Script ignores `message.usage` and `message.model` fields |
| Stats YAML (31 files) | Per-dispatch tokens (I/O only), duration_ms, model, step, run_id, command, bead | Not parsed by extract-timings.py at all |
| Beads database | Priority, type, estimated_minutes, metadata (impact), labels | Need `bd sql` to join with timing data |

## Implementation Steps

All steps modify `.workflows/session-analysis/extract-timings.py` unless noted.

### Step 1: Per-request cost from JSONL

- [x] Extract `message.usage` fields from every `type=assistant` JSONL entry: `input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`
- [x] Extract `message.model` to apply model-specific rates (Opus: $15/$3.75/$1.875/$15 per M for input/cache_create/cache_read/output; Sonnet: $3/$3.75/$0.30/$15; Haiku: $0.25/$0.30/$0.03/$1.25)
- [x] Sum per-session and per-phase costs
- [x] Emit `project_cost` record with total, per-phase breakdown, per-model breakdown
- [x] Add "Project Cost" section to summary.md with comparison to ccusage total

### Step 2: Stats YAML mining

- [x] Add YAML parsing to extract-timings.py — read all `.workflows/stats/*.yaml` files
- [x] Parse agent dispatch entries: command, step, model, tokens, duration_ms, run_id, bead
- [x] Skip ccusage-snapshot documents (different schema)
- [x] Group by command (workflow type) and compute per-step duration statistics (median, P90, mean)
- [x] Compute estimate vs actual for this phase 4 run: match stats entries with bead estimates from `bd sql`
- [x] Emit `stats_step_timing` records and add "Step Timing from Stats" section to summary.md

### Step 3: Per-workflow confirmation prompt breakdown

- [x] For each AskUserQuestion event already extracted, determine which workflow phase it falls within (match event timestamp against phase windows)
- [x] For events outside any phase window, classify as "non-workflow"
- [x] Break down the 238 confirmation prompts by workflow: how many from plan, brainstorm, work, compact-prep, etc.
- [x] Also break down all 802 AskUserQuestion events by workflow (not just confirmation)
- [x] Emit `askuser_per_workflow` records and add table to summary.md

### Step 4: Estimation accuracy segmentation

- [x] Use `bd sql` to get closed beads with: id, type, priority, estimated_minutes, metadata (impact_score), labels, title
- [x] Join with windowed attribution data (already computed) to get actual minutes per bead
- [x] Segment accuracy ratio by: type (task/bug/feature), priority (P0-P4), single-session vs multi-session, estimate size buckets (<15min, 15-60min, 60-120min, >120min)
- [x] Emit `estimation_segments` records and add segmented accuracy table to summary.md

### Step 5: Compaction cost

- [x] For each `isCompactSummary` timestamp (already tracked), find the assistant entry immediately preceding it
- [x] Read that entry's `message.usage` to get the compaction request's token cost
- [x] Measure re-orientation time: gap from `isCompactSummary` to first productive tool call (Edit/Write/Agent, not Read/Grep which are orientation)
- [x] Emit `compaction_cost` records with: session, timestamp, token_cost, reorientation_minutes
- [x] Add "Compaction Cost" section to summary.md with median/mean/total

### Step 6: Velocity trend

- [x] Bucket bead closures by date (from beads database via `bd sql`)
- [x] Bucket active time by date (from session timestamps already extracted)
- [x] Compute beads/day trend and active-hours/day trend
- [x] Emit `velocity_trend` records and add trend table to summary.md

### Step 7: Permission prompt cost estimation

- [x] No JSONL signal for OS-level permission prompts (confirmed by research)
- [x] Proxy: count Bash tool calls in `permissionMode="default"` sessions that match known heuristic-triggering patterns (`$()`, `<<`, `{"`)
- [x] Estimate: count × median user response time for confirmation AskUserQuestion (5.24 min) as upper bound
- [x] Add "Permission Prompt Estimate" note to summary.md with methodology caveat

### Step 8: QA retry cost

- [x] Detect qa→work→qa sequences within sessions: Skill("qa") followed by non-qa phases, then another Skill("qa")
- [x] Measure active time per QA invocation and count retries per sequence
- [x] Emit `qa_retry` records with: session, retry_count, total_active_minutes, phases_between
- [x] Add "QA Retry Cost" section to summary.md

### Step 9: Tighten estimation heuristics

- [x] Re-run the full script to generate fresh outputs with steps 1-8
- [x] Update `.claude/memory/estimation-heuristics.md` with:
  - Project-specific cost replacing the cross-repo ccusage figure ($4.69/hr → corrected)
  - Per-step timing data from stats YAML (separate from per-phase timing)
  - Segmented estimation accuracy (where estimates are reliable vs need correction)
  - Correction factor recommendations (e.g., 0.6x for well-scoped subagent steps)
  - Compaction overhead quantified
  - Velocity trend
  - Any new coverage gaps discovered
- [x] Report before/after changes to user: which numbers changed, by how much, why

## Acceptance Criteria

- Script runs clean across all 89+ sessions with 0 parse errors
- Per-project cost computed from JSONL (not ccusage) replaces the cross-repo figure
- Estimation accuracy segmented by at least 3 dimensions
- All 9 sections added to summary.md
- estimation-heuristics.md updated with corrected figures
- Before/after report presented to user

## Constraints

- No plugin skill file changes — pure analysis
- Single file (extract-timings.py) for all script changes
- estimation-heuristics.md for heuristic updates
- Sequential execution required (single file)

## Sources

- Research: `.workflows/plan-research/session-analysis-phase5/agents/`
- Phase 4 methodology: `docs/solutions/process-analysis/2026-03-13-session-log-analysis-methodology.md`
- Bead: 3zr (phase 5 scope in notes)
- Related beads: t7sd (live estimation, deferred), 1hu4 (reduce confirmation prompts), 42s (user input gates)
