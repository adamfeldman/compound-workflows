---
title: "feat: Deepen-Plan Convergence Guidance"
type: feat
status: active
date: 2026-03-08
origin: docs/brainstorms/2026-03-08-deepen-plan-convergence-brainstorm.md
---

# Deepen-Plan Convergence Guidance

## Problem

After deepen-plan completes, the user has no data-driven guidance on whether to run another round. Phase 6 offers "Deepen further" as a flat option with no convergence analysis. Users must decide blindly — leading to either premature stops (missing genuine issues) or unnecessary rounds (chasing edit-induced inconsistencies).

Empirical data from 12 deepen-plan runs across 2 projects shows a "Sisyphean cycle": rounds 1-3 find genuine design bugs, rounds 4+ mostly find bugs introduced by the fixing process itself. Each edit creates ~0.5-1.0 new issues per fix. The decision of when to stop is the single most impactful gap in the deepen-plan workflow (see brainstorm: `docs/brainstorms/2026-03-08-deepen-plan-convergence-brainstorm.md`).

## Scope

2 new files, 1 modified file, plugin metadata update.

| File | Change |
|------|--------|
| `agents/workflow/plan-checks/convergence-signals.sh` | **New** — bash script computing 5 structured metrics |
| `agents/workflow/convergence-advisor.md` | **New** — agent classifying findings as genuine vs edit-induced |
| `commands/compound/deepen-plan.md` | Add Phase 5.75 (convergence dispatch), update Phase 6 (present convergence), update Phase 1 (read prior signals) |
| `plugin.json` | Version bump, agent count update |

## Architecture

**Hybrid: deterministic script + LLM agent** (see brainstorm: Decision 1).

1. **Script** (`convergence-signals.sh`) computes 5 structured metrics from readiness reports and manifests — deterministic, fast, no LLM needed
2. **Agent** (`convergence-advisor`) classifies synthesis/red team findings as genuine vs edit-induced (6th signal: category mix) — requires semantic judgment
3. **Orchestrator** runs script first, passes output to agent as input. Agent writes the complete convergence file (`run-<N>-convergence.md`) incorporating both script metrics and its own classification (see brainstorm: specflow Q1 resolution — option D)
4. **Phase 6** reads the Recommendation and Signals sections of the convergence file (not the full analysis) for context-lean presentation
5. **Next run's Phase 1** reads prior convergence signals (not recommendation) to prevent anchoring (see brainstorm: Decision 4)

### Convergence File Format

Written to `.workflows/deepen-plan/<stem>/run-<N>-convergence.md`:

```markdown
## Recommendation

[One of four states — see Decision Logic below]

Recommended next step: [Start /compound:work | Deepen further | Consolidate first]

## Signals

- **Run:** N
- **Complete:** true|false (false = agent portion did not complete)
- **Issue count trend:** Run N-1: X → Run N: Y (decreasing|stable|increasing|first-run)
- **Severity distribution:** N CRITICAL, N SERIOUS, N MINOR
- **Change magnitude:** N sections with findings this run
- **Deferred items:** N (trend: increasing|stable|decreasing|first-run)
- **Readiness result:** passed|issues-found|failed
- **Category mix:** N% genuine, N% edit-induced (proxy: readiness check types + agent classification)

## Analysis

[Detailed reasoning, category classifications, signal conflicts noted]
```

Phase 6 reads only `## Recommendation` and `## Signals`.

### Decision Logic

Four recommendation states with explicit rules (see brainstorm: Decision 3):

| Recommendation | Criteria |
|---|---|
| **"Plan appears converged, ready for work"** | Zero CRITICAL/SERIOUS genuine findings this run, issue count trending down or flat, readiness passed clean |
| **"Consolidate, then evaluate"** | Findings exist but predominantly edit-induced (category mix > 50% edit-induced), or readiness required consolidator fixes |
| **"Recommend another run"** | Genuine CRITICAL/SERIOUS findings remain, or new design/architectural issues surfaced this run |
| **"Recommend another run after consolidation"** | Both genuine issues and significant edit-induced churn exist |

**Conflict resolution:** When signals conflict, genuine CRITICALs override trend signals. When classification confidence is low, default to "genuine" (avoids premature convergence).

**First-run special case:** Trend signals are unavailable on run 1. If run 1 has zero CRITICAL/SERIOUS genuine findings and clean readiness, recommend "Plan appears converged" with note "first run — no trend data available." Otherwise recommend based on available signals.

**Soft round-count guardrails:** If run count exceeds 5 and signals haven't triggered convergence, flag: "Run count exceeds typical convergence range — consider whether remaining findings are genuine or systemic." Advisory only, not blocking (see brainstorm: "Signal-based with soft round-count guardrails").

## Implementation

### Phase 1: Create convergence-signals.sh

**File:** `plugins/compound-workflows/agents/workflow/plan-checks/convergence-signals.sh`

- [ ] Create script following plan-checks pattern (shebang, YAML header, `set -euo pipefail`)
- [ ] **Custom interface** — NOT using lib.sh's `validate_inputs` (incompatible interface). Takes: `<stem-dir> <readiness-dir> <output-file>`. The stem directory (`.workflows/deepen-plan/<stem>/`) contains manifests and synthesis summaries. The readiness directory (`.workflows/plan-research/<stem>/readiness/`) contains readiness reports. The output file receives a copy of stdout for debugging.
- [ ] Parse current manifest (`manifest.json`) for run number via `jq`
- [ ] Parse current readiness report summary for severity counts (`grep` for `By severity:` line)
- [ ] Parse prior readiness report (from `run-<N-1>-manifest.json` path convention) for issue count trend. Handle missing prior data gracefully (first run).
- [ ] Compute change magnitude: count distinct `Location:` values from current readiness report findings. Note: this measures sections flagged by readiness checks, not sections modified by synthesis. This is a proxy for edit churn, not a direct measurement of change scope.
- [ ] Count deferred items from current synthesis summary (grep for `Deferred` disposition)
- [ ] Extract readiness result: `passed` (zero findings + complete), `issues-found` (findings exist), `failed` (check failures)
- [ ] Detect stale prior data: compare plan file hash (md5) against hash in prior readiness report's `Plan hash:` field. If mismatch, flag prior signals as stale.
- [ ] **Defensive parsing:** If the readiness report is missing or does not contain expected fields (`By severity:`, `Plan hash:`), report the affected signal as "unavailable" rather than failing the script.
- [ ] Output structured signal values to stdout (the orchestrator captures this for the agent prompt)
- [ ] Write script output to `<output-file>` as well (debug artifact only — the orchestrator uses stdout, not the file, when constructing the agent dispatch prompt)
- [ ] **Signal mapping:** The 5 structured metrics are: (1) issue count trend, (2) severity distribution, (3) change magnitude, (4) deferred items, (5) readiness result. Run number and stale data detection are supporting computations used by the script but are not standalone signals.

### Phase 2: Create convergence-advisor.md

**File:** `plugins/compound-workflows/agents/workflow/convergence-advisor.md`

- [ ] Create agent file with YAML frontmatter (name, description, type: workflow)
- [ ] Agent receives: script-computed metrics (5 signals) via prompt, paths to current synthesis summary and prior convergence file
- [ ] Agent reads current run's synthesis summary (bounded — one file only)
- [ ] Agent reads prior run's convergence signals section only (not recommendation — anti-anchoring per Decision 4)
- [ ] Agent classifies synthesis/red team findings as genuine vs edit-induced using:
  - Readiness check types as proxy: stale-values/broken-references = edit-induced; contradictions/underspecification = genuine
  - For synthesis/red team findings without a readiness check type: classify using the brainstorm criteria ("edit-induced if it flags a value/reference/label that was correct in a prior run and broke due to a plan edit; genuine if it identifies a design flaw independent of prior edits"). When confidence is low, default to "genuine."
- [ ] Agent applies decision logic to produce one of 4 recommendations
- [ ] Agent writes complete convergence file (`run-<N>-convergence.md`) with Recommendation, Signals, and Analysis sections
- [ ] OUTPUT INSTRUCTIONS: write to the specified output path, return only a 2-3 sentence summary
- [ ] 3-minute timeout
- [ ] **Dispatch prompt skeleton** — The orchestrator invokes the agent with this structure:
  ```
  Convergence signals (from convergence-signals.sh):
  <raw script stdout pasted here>

  Files to read:
  - Current synthesis summary: <path>
  - Prior convergence file: <path> (or "none" if first run)

  Output path: <path>/run-<N>-convergence.md
  ```
  Signals are passed as the raw structured text from script stdout. File paths are explicit in the prompt (no discovery needed by the agent).

### Phase 3: Update deepen-plan.md — Add Phase 5.75

**File:** `plugins/compound-workflows/commands/compound/deepen-plan.md`

- [ ] Insert new Phase 5.75 between Phase 5.5 (readiness) and Phase 6 (report)
- [ ] Phase 5.75 "Convergence Analysis":
  1. Run `convergence-signals.sh <stem-dir> <readiness-dir> <signals-output-path>` and capture stdout
  2. Dispatch convergence-advisor agent (background Task) with:
     - Script-computed metrics from stdout
     - Path to current synthesis summary
     - Path to prior convergence file (if exists)
     - Output path: `.workflows/deepen-plan/<stem>/run-<N>-convergence.md`
  3. Poll for convergence file existence (3-minute timeout)
  4. If agent fails/times out: write script-only convergence file with `complete: false` and available metrics
- [ ] No new manifest status — convergence is treated as part of the Phase 5.5→6 flow. If interrupted, Phase 6 checks for convergence file existence and re-runs if missing. No Phase 5 (Recovery) changes are needed — Phase 6's re-run-if-missing is the intended recovery mechanism for convergence-phase interruption.

### Phase 4: Update deepen-plan.md — Update Phase 6

**File:** `plugins/compound-workflows/commands/compound/deepen-plan.md`

- [ ] Add step 5 (after deferred items, before work readiness check): "**Convergence summary:** Read the `## Recommendation` and `## Signals` sections from `run-<N>-convergence.md`. Present the recommendation and key signals to the user."
- [ ] Add "Recommended next step:" annotation to the options list based on convergence recommendation:
  - If "converged": annotate "Start `/compound:work`" as recommended
  - If "run again": annotate "Deepen further" as recommended
  - If "consolidate": suggest running consolidator before another round
- [ ] Handle missing convergence file: "Convergence analysis was not completed. Consider running `/compound:deepen-plan` again for convergence guidance."
- [ ] **Precedence rule:** Convergence recommendation takes precedence for "next step" guidance since it already incorporates readiness as an input signal. If readiness passes clean but convergence recommends another run, the convergence recommendation governs.

### Phase 5: Update deepen-plan.md — Update Phase 1

**File:** `plugins/compound-workflows/commands/compound/deepen-plan.md`

- [ ] In Phase 1 (where prior run data is read), add: read prior convergence file's `## Signals` section (NOT the `## Recommendation` section — anti-anchoring)
- [ ] Surface prior signals as context: "Prior run (run N-1) signals: [issue count, severity, category mix]"
- [ ] Handle missing prior convergence file: "No prior convergence data available."
- [ ] Handle stale prior data (hash mismatch): "Prior convergence signals are stale — plan was modified since last run."

### Phase 6: Plugin Metadata

- [ ] Bump version in `plugin.json` (minor version increment)
- [ ] Update agent count (add convergence-advisor)
- [ ] Update CHANGELOG.md
- [ ] Update AGENTS.md with new agent and script descriptions

## Acceptance Criteria

- [ ] `convergence-signals.sh` parses readiness reports and manifests to produce 5 structured metrics
- [ ] `convergence-advisor` classifies findings and produces one of 4 recommendations
- [ ] Phase 5.75 dispatches script then agent, writes `run-<N>-convergence.md`
- [ ] Phase 6 presents convergence recommendation and signals before options
- [ ] Phase 1 reads prior convergence signals (not recommendation) for anti-anchoring
- [ ] First-run produces meaningful guidance (partial signals, special-case recommendation)
- [ ] Agent failure degrades gracefully (script metrics still presented, `complete: false`)
- [ ] Stale prior data detected via plan hash comparison
- [ ] Soft round-count guardrail flags runs > 5
- [ ] Context-lean: Phase 6 reads only Recommendation + Signals sections

## Out of Scope

- **Anchoring elimination** — anti-anchoring mechanism (omitting prior recommendation) reduces but does not eliminate anchoring from signal values. This is an acceptable trade-off.
- **Nested convergence history** — only current + prior run are read. Full history analysis would require unbounded reads.
- **Concurrent deepen-plan runs** — not a real scenario; run numbering is sequential in the manifest.
- **Constants-as-data refactoring** — would reduce edit-induced findings at the source, but is a separate improvement.

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-03-08-deepen-plan-convergence-brainstorm.md` — key decisions: hybrid script+agent, six signals, four recommendation states, anti-anchoring, bounded reads, failure modes
- **Repo research:** `.workflows/plan-research/deepen-plan-convergence/agents/repo-research.md`
- **Learnings:** `.workflows/plan-research/deepen-plan-convergence/agents/learnings.md`
- **SpecFlow analysis:** `.workflows/plan-research/deepen-plan-convergence/agents/specflow.md`
- **Iteration taxonomy:** `docs/solutions/process-analysis/2026-03-08-deepen-plan-iteration-taxonomy.md` (empirical data from 12 runs across 2 projects)
