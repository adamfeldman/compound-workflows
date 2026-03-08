---
title: "Plan Readiness Agents: plan-readiness-reviewer + plan-consolidator"
type: feat
status: active
date: 2026-03-08
origin: docs/brainstorms/2026-03-08-plan-readiness-agents-brainstorm.md
---

# Plan Readiness Agents

## Problem

Deepen-plan rounds 4+ are dominated by edit-induced inconsistencies (~0.5-1.0 new issues per fix), not new design bugs. Plans become palimpsests of layered corrections. The system has no post-gate verification and no consolidation step (see brainstorm: origin document for empirical evidence from 12 deepen-plan runs across 2 projects).

## Solution

Two new agents and supporting check modules that run at the end of every `/compound:plan` and `/compound:deepen-plan`:

1. **3 mechanical check shell scripts** — Deterministic bash scripts for stale-values, broken-references, and audit-trail-bloat. Run directly by the command, not as LLM agents.
2. **1 semantic checks agent** — Single LLM agent that performs all 5 semantic analysis passes (contradictions, unresolved-disputes, underspecification, accretion, external-verification) in one plan read.
3. **plan-readiness-reviewer** — Foreground aggregator agent that reads check outputs from disk, deduplicates overlapping findings, and writes an aggregated report. Zero plan-file write authority. Does NOT dispatch checks — the command does.
4. **plan-consolidator** — Fixes issues from the reviewer. Evidence-based auto-fixes for mechanical issues; routes judgment calls to user. Constrained write authority with preservation rules.

**Dispatch architecture:** Flat dispatch from the command (not nested). The command dispatches all checks directly (3 mechanical scripts in parallel + 1 semantic agent as background Task), then dispatches the reviewer-aggregator as a foreground Task to read outputs and produce the report. Nested Task dispatch (subagents spawning further subagents) was tested and does not work.

Re-verification loop capped at 1 cycle (reviewer → consolidator → verify-only → present remaining to user). No second consolidation.

## Implementation Steps

### Step 1: Create mechanical check shell scripts

Create `plugins/compound-workflows/agents/workflow/plan-checks/` directory and 3 mechanical check shell scripts. These are actual bash scripts, not LLM agent .md files — mechanical checks are truly deterministic and do not require LLM reasoning.

**Files to create:**
- [ ] `plugins/compound-workflows/agents/workflow/plan-checks/stale-values.sh`
- [ ] `plugins/compound-workflows/agents/workflow/plan-checks/broken-references.sh`
- [ ] `plugins/compound-workflows/agents/workflow/plan-checks/audit-trail-bloat.sh`

**Each shell script follows this structure:**

```bash
#!/bin/bash
# name: <check-name>
# description: "<one-line description>"
# type: mechanical
# verify_only: true
#
# Usage: ./<check-name>.sh <plan-file-path> <output-file-path>
```

**Note:** Shell script metadata is in comments at the top of the file, following the same fields as agent frontmatter (`name`, `description`, `type`, `verify_only`) for consistency. The command reads these comments for discovery and filtering. Deepen-plan Phase 2c discovers `.md` files only — these `.sh` scripts are NOT discovered as review agents.

Each script contains:
1. Input validation (plan file exists, output directory exists)
2. Detection logic (grep, awk, regex patterns, line counting)
3. Output generation in the standard findings template
4. Exit code: 0 = ran successfully (even if findings found), 1 = script error

**Specific check instructions:**

**stale-values:** Detect the same value (numbers, constants, thresholds) appearing in multiple plan locations with different values. Two modes: (a) if plan has a `## Constants` section, verify all references match the defined values; (b) if no constants section, compare values that appear to represent the same concept across locations. Use grep/regex to find numeric patterns and cross-reference. Report each mismatch with both locations and both values. Uses conservative matching — only flags exact-match patterns (e.g., same label with different numbers), not heuristic "similar concept" matches.

**broken-references:** Detect cross-references like `(R12)`, `(S3)`, `Step 4.2` that point to wrong or non-existent targets. Parse all reference patterns, build a reference index, and check each target exists. Report broken references with the referencing location and the missing target.

**audit-trail-bloat:** Detect "Run N Review Findings" or similar annotation sections. Calculate ratio of spec text to annotation text. Flag when annotations exceed 30% of total plan content, or when annotations contradict current spec text. Report total lines, spec lines, annotation lines, and specific contradictory annotations.

**Output template for all mechanical checks:**

```markdown
status: success

## Findings

### [SEVERITY] <finding-title>
- **Check:** <check-name>
- **Location:** <section heading text>
- **Description:** <what was detected>
- **Values:** <specific values, if applicable>
- **Suggested fix:** <what should change>

## Summary
- Total findings: N
- By severity: N CRITICAL, N SERIOUS, N MINOR
- Check completed in: N seconds
```

The first line of output MUST be `status: success` or `status: error` (if the script encountered an error during execution). Location MUST use the section heading text (e.g., "### Step 3: Create plan-readiness-reviewer agent"), never line numbers or line ranges — line numbers shift as the plan is edited.

**Graceful handling of fresh plans:** Checks must handle plans that have no Run N annotations, no Constants section, and no (R12)-style references. If the patterns a check looks for are not present, report "No applicable patterns found." with zero findings — do not error.

**Output size cap:** Each check script MUST cap its output at 150-200 lines. If findings exceed this, include the highest-severity findings and add a truncation notice: "Output truncated at 150 lines. N additional findings omitted — see full analysis for details." This prevents the reviewer's context from being exhausted during deduplication/aggregation.

**Read for patterns:** Read `plugins/compound-workflows/agents/workflow/spec-flow-analyzer.md` for workflow agent structure. Read `plugins/compound-workflows/agents/review/code-simplicity-reviewer.md` for review output format conventions.

---

### Step 2: Create semantic checks agent

Create a single semantic checks agent file that performs all 5 semantic analysis passes in one plan read. Bundling into 1 agent reduces dispatch count and avoids redundant plan reads.

**File to create:**
- [ ] `plugins/compound-workflows/agents/workflow/plan-checks/semantic-checks.md`

**Frontmatter:**

```yaml
---
name: semantic-checks
description: "Performs 5 semantic analysis passes on a plan: contradictions, unresolved-disputes, underspecification, accretion, external-verification"
model: inherit
type: semantic
verify_only: false
---
```

Body contains: role description, instructions for all 5 analysis passes (performed sequentially within a single plan read), judgment criteria for each pass, output template (same format as mechanical checks, same 150-200 line output cap). The agent reads the plan once and performs all 5 passes, writing a single combined output file.

**Analysis passes (performed in order):**

**Pass 1 — contradictions** (`verify_only: true`): Find sections that disagree with each other — different values for the same concept, conflicting instructions, mutually exclusive requirements. Read the full plan and cross-reference claims section by section. Be specific about which sections contradict and what each says.

**Pass 2 — unresolved-disputes** (`verify_only: false`): Find design tradeoffs flagged by reviewers that were never explicitly decided. Read prior gate decisions from `.workflows/deepen-plan/<plan-stem>/` and `.workflows/plan-research/<plan-stem>/` to distinguish settled decisions from ongoing disagreements. Do NOT re-flag disputes the user already resolved — check the gate logs first. If no gate logs exist (plan not created by /compound:plan), skip this pass and report "No prior gate decisions found — skipping."

**Pass 3 — underspecification** (`verify_only: true`): Find steps too vague for a subagent to execute independently. Check for: missing function signatures, undefined data shapes, unspecified interfaces, steps that require judgment calls without guidance, steps that reference external resources without URLs or file paths. This pass has highest value at round 1. Rate severity: CRITICAL = subagent cannot proceed; SERIOUS = subagent must guess; MINOR = subagent can infer from context.

**Pass 4 — accretion** (`verify_only: false`): Find features with 3+ descriptions at different points in their evolution — the original spec, a "Run N" correction, a later override, etc. The subagent wouldn't know which version to implement. Flag when the same feature/concept has multiple contradictory descriptions in different sections or annotations.

**Pass 5 — external-verification** (`verify_only: false`): Verify externally-sourced facts (IRS limits, API behavior, legal thresholds, library versions) against current reality via WebSearch. Read provenance log from `.workflows/plan-research/<plan-stem>/provenance.md` first — skip recently-verified values (within expiry window). Report verified results as YAML data in the findings section (value, source_url, verified_date, plan_locations, expiry_date). The reviewer-aggregator writes provenance.md from this data — the semantic checks agent does NOT write to provenance.md directly. Use conservative source policy by default (only .gov, official API docs, primary sources). If WebSearch is unavailable, report all unverified values as "unverified (WebSearch unavailable)" — never mark unverified values as "verified."

**Output template:**

```markdown
status: success

## Findings

### [SEVERITY] <finding-title>
- **Check:** <pass-name> (e.g., contradictions, underspecification)
- **Location:** <section heading text>
- **Description:** <what was detected>
- **Values:** <specific values, if applicable>
- **Suggested fix:** <what should change>

## Summary
- Total findings: N
- By severity: N CRITICAL, N SERIOUS, N MINOR
- By pass: contradictions (N), unresolved-disputes (N), underspecification (N), accretion (N), external-verification (N)
```

The first line of output MUST be `status: success` or `status: error`. Location MUST use the section heading text, never line numbers or line ranges.

**Graceful handling of fresh plans:** Each pass must handle plans that have no Run N annotations, no Constants section, and no (R12)-style references. If the patterns a pass looks for are not present, report "No applicable patterns found." for that pass — do not error.

**Verify-only mode:** When the agent receives `mode: verify-only`, only execute passes marked `verify_only: true` (contradictions and underspecification). Skip all other passes. The command passes the mode via the prompt.

**skip_checks configuration:** The command passes a `skip_checks` list. If any pass names appear in this list, skip those passes.

**Read for patterns:** Same as Step 1.

---

### Step 3: Create plan-readiness-reviewer agent (aggregator)

**File to create:**
- [ ] `plugins/compound-workflows/agents/workflow/plan-readiness-reviewer.md`

**Frontmatter:**

```yaml
---
name: plan-readiness-reviewer
description: "Aggregates and deduplicates plan readiness check outputs into a work-readiness report"
model: inherit
---
```

**Architecture:** This agent is an aggregator/deduplicator, NOT an orchestrator. It does NOT dispatch checks — the command does that. The reviewer receives paths to check output files, reads them from disk, deduplicates overlapping findings, and writes an aggregated report. It is dispatched as a foreground Task by the command after all checks have completed.

**Agent instructions must cover:**

1. **Input parameters** (passed via prompt): plan file path, plan stem, output directory path, check output file paths (list of paths to individual check output files), mode (`full` or `verify-only`), configuration (skip_checks list, provenance settings — passed through from the command, not read from config by the reviewer).

2. **Pre-flight check:** Read the plan. Count substantive lines (non-frontmatter, non-blank). If fewer than 20 substantive lines, skip aggregation and report: "Plan too short for readiness analysis (N lines)."

3. **Config handling:** The COMMAND reads config from `./compound-workflows.md`; the reviewer receives config as input parameters. The reviewer does not read config files directly.

4. **Fault-tolerant parsing:** For each check output file path received, read the file. Extract findings between `## Findings` and `## Summary` headers — ignore any preambles or postambles outside these markers. If a file doesn't exist or is empty, record that check as "incomplete (no output)." Check for the `status:` header on line 1 — record `status: success`, `status: error`, or missing status.

5. **Truncation detection:** Check each output for truncation notices (e.g., "Output truncated at N lines. N additional findings omitted"). If found, include in the report summary: "N additional findings truncated from [check-name]."

6. **Deduplication:** After collecting all check outputs, deduplicate findings: (a) group by plan location (section heading text), (b) when multiple findings reference the same location and same values, merge into one finding with the highest severity and note which checks/passes flagged it, (c) when findings reference the same location but different aspects, keep separate.

7. **Aggregation:** Write aggregated report to `.workflows/plan-research/<plan-stem>/readiness/report.md`. Include: plan file content hash (`md5 -q` on macOS / `md5sum` on Linux, used by consolidator to detect if plan was modified between phases), overall severity summary, deduplicated findings in structured markdown (same output template as individual checks), completeness metadata (list of checks that ran, their status — success/timeout/error, `complete: true/false` flag). When dispatched from deepen-plan, use run-numbered path: `.workflows/plan-research/<plan-stem>/readiness/run-<N>/report.md`. Only read check outputs that contain findings — skip zero-finding outputs to reduce context load.

8. **Provenance log:** If external-verification pass reported verified YAML data in its findings, write that data to `.workflows/plan-research/<plan-stem>/provenance.md`. The reviewer is the single writer of provenance data — the semantic checks agent only reports verification results.

9. **Write authority:** ZERO plan-file write authority. Metadata writes only (report, provenance log).

10. **Return:** 2-3 sentence summary to parent with issue count and severity breakdown.

**Rate limit handling note:** If rate limits are hit during check dispatch, the command should batch checks in groups of 4. External-verification gets a longer timeout (5-10 minutes instead of 3) due to WebSearch latency. Document this in the reviewer's instructions as context for timeout handling.

**Read for patterns:** `plugins/compound-workflows/commands/compound/deepen-plan.md` Phase 2c for agent discovery pattern. `plugins/compound-workflows/skills/disk-persist-agents/SKILL.md` for disk-write conventions. Existing workflow agents for file structure conventions.

**Examples section:** Include 2-3 examples showing: (a) plan with multiple issues found, (b) clean plan with 0 issues, (c) verify-only mode after consolidation.

---

### Step 4: Create plan-consolidator agent

**File to create:**
- [ ] `plugins/compound-workflows/agents/workflow/plan-consolidator.md`

**Frontmatter:**

```yaml
---
name: plan-consolidator
description: "Fixes plan readiness issues with evidence-based auto-fixes and guardrailed user decisions"
model: inherit
---
```

**Implementation note:** The consolidator runs as a foreground Task agent. Foreground Task agents CAN use AskUserQuestion to interact with the user — this is the same mechanism used by deepen-plan's synthesis gate. The consolidator is the first workflow agent with interactive user communication.

**Agent instructions must cover:**

1. **Input parameters** (passed via prompt): plan file path, reviewer report path (`.workflows/plan-research/<plan-stem>/readiness/report.md`), consolidation report output path.

2. **Plan integrity check:** Read the reviewer report's plan file content hash. Compute `md5 -q` (macOS) or `md5sum` (Linux) on the plan file and compare. If mismatch: hard-stop and surface to user: "Plan modified since review. Rerun readiness check?" Never proceed with stale findings.

3. **Read full context:** Read the entire plan file and the full reviewer report. The consolidator operates on the full plan in a single pass — no section-by-section parsing or reassembly. This keeps the implementation simple while the pass-through and preservation rules (below) constrain what gets modified.

4. **Apply auto-fixes** (evidence-based, no user input):
   - Fix broken cross-references ONLY when the correct target is unambiguous (e.g., typo in reference pattern where intended target clearly exists). Missing targets with no obvious correct target route to user batch-decision.
   - Strip superseded "Run N" annotations that conflict with current spec text
   - Deduplicate stale values ONLY when explicit canonical source exists (constants section defines canonical value, or provenance log confirms value). Do NOT use "most-detailed specification" heuristic — all other value conflicts route to user.
   - Log each auto-fix to the consolidation report as it is applied (incremental writing protects against interruption)
   - **Plan size determines write strategy:** For plans >200 lines, use Edit tool (search/replace) instead of Write to minimize regression risk. For plans ≤200 lines, Write is acceptable. This is a dynamic choice based on plan size.
   - **Batch auto-fixes with related user decisions:** When auto-fixable and guardrailed findings reference the same plan section, present them together so the user sees the full picture before anything is applied. Do not apply auto-fixes independently of related user decisions.

5. **Pass-through rule:** Do NOT modify any content that has no associated findings from the reviewer. Write authority extends only to content with documented findings, and only to the specific issues described. Do not edit, reformat, or "improve" untouched content.

6. **Preservation rule:** NEVER strip text recording user decisions and reasoning. Patterns: "Rationale:", "Decision:", "Rejected because:", "User noted:", "Chose X over Y because". These are only reorganized (e.g., moved from an annotation block to the spec section), never deleted.

7. **Mechanical authority verification:** After writing the updated plan, run a verification pass:
   - Grep for all preservation-pattern lines in the original plan and verify every instance exists in the updated plan
   - Normalize both old and new content before comparing: strip leading/trailing whitespace, collapse internal whitespace, lowercase. This handles rewrapping and minor formatting changes that don't affect meaning.
   - If any preservation-pattern lines are missing after normalization, flag as a warning and restore them
   This is a deterministic check the consolidator runs on its own output.

8. **Batch user decisions:** Present all guardrailed items (ambiguous values, design disputes, spec gaps) as a batch via AskUserQuestion. Apply severity-based triage: CRITICAL individually, SERIOUS individually, MINOR as batch-accept option. When multiple findings target the same section, group them and present as a batch so the user sees the full picture for that section. Record user's reasoning for each decision.

9. **Deferred findings:** User-deferred findings are added to the plan's "Open Questions" section (create it if it doesn't exist, placed before Sources). This ensures `/compound:work` Phase 1.1 surfaces them.

10. **Output:** Write updated plan file. Write consolidation report to `.workflows/plan-research/<plan-stem>/readiness/consolidation-report.md` with: auto-fixes applied (before/after), user decisions made, deferred items.

11. **Return:** Summary of auto-fixes applied, user decisions made, deferred items count.

**Read for patterns:** Same as Step 3. Also read the brainstorm's "Why Two Agents, Not One" section for the guardrail boundary rationale.

**Examples section:** Include 2-3 examples showing: (a) plan with auto-fixable issues only, (b) plan with guardrailed items requiring user decisions, (c) plan where consolidation introduces a new issue caught by re-verify.

---

### Step 5: Integrate into plan.md

**File to modify:**
- [ ] `plugins/compound-workflows/commands/compound/plan.md`

**Changes:**

Insert **Phase 6.7: Plan Readiness Check** between Phase 6.5 (Pre-Handoff Gates) and Phase 7 (Post-Generation Options).

**Phase 6.7 content:**

```markdown
### 6.7. Plan Readiness Check

Run plan readiness checks and aggregate findings to verify the plan is work-ready. The command dispatches all checks directly (flat dispatch — no nested agent dispatch).

**Dispatch:**

1. Read config from compound-workflows.md `plan_readiness` section. Apply skip_checks filtering.
2. Create output directory: `mkdir -p .workflows/plan-research/<plan-stem>/readiness/checks/`
3. Run 3 mechanical check scripts in parallel (bash):
   - `agents/workflow/plan-checks/stale-values.sh <plan-path> <output-dir>/checks/stale-values.md`
   - `agents/workflow/plan-checks/broken-references.sh <plan-path> <output-dir>/checks/broken-references.md`
   - `agents/workflow/plan-checks/audit-trail-bloat.sh <plan-path> <output-dir>/checks/audit-trail-bloat.md`
4. Dispatch 1 semantic checks agent (background Task):
   - Agent: `agents/workflow/plan-checks/semantic-checks.md`
   - Pass: plan file path, output path (`<output-dir>/checks/semantic-checks.md`), mode (`full`), skip_checks, provenance settings
5. Wait for all checks to complete (3-minute timeout for scripts, 5-10 minutes for semantic agent due to WebSearch latency). If rate limits are hit, batch checks in groups of 4.
6. Dispatch plan-readiness-reviewer (foreground Task):
   - Pass: plan file path, plan stem, output directory, check output file paths, mode, config
7. Show the reviewer's summary to the user: "Plan readiness check: [summary]"

Keep Phase 6.7 focused on dispatch + response handling. The detailed analysis logic lives in the check scripts and agent files.

**If issues found:**

1. Dispatch plan-consolidator (foreground). Pass: plan file path, reviewer report path.
2. Consolidator applies auto-fixes, then presents guardrailed items to user.
3. After consolidation, re-run checks in `verify-only` mode and dispatch reviewer again.
4. If verify finds new issues: present remaining findings to user directly.
   User options: resolve now, defer to Open Questions, or dismiss.
5. Show user: "Readiness check complete. N auto-fixes applied, M items resolved, K deferred."

**If zero issues found:**

Skip consolidator and re-verify. Show: "Plan readiness check: no issues found."

**If reviewer fails:**

Warn: "Readiness check failed — consider running /compound:deepen-plan before starting work."
Proceed to Phase 7.
```

**Update Phase 7 handoff message** to include readiness status:
- If readiness passed: include in handoff message
- If CRITICAL findings were deferred: add warning to "Start /compound:work" option
- If readiness check was skipped/failed: note it

**Read for context:** The full plan.md file to understand the Phase 6.5 → Phase 7 transition.

---

### Step 6: Integrate into deepen-plan.md

**File to modify:**
- [ ] `plugins/compound-workflows/commands/compound/deepen-plan.md`

**Changes:**

1. **Insert Phase 5.5: Plan Readiness Check** between Phase 5 (Recovery) and Phase 6 (Cleanup and Report). In the normal (non-recovery) flow, this runs after Phase 4.5 (Red Team Challenge).

**Phase 5.5 content:**

```markdown
## Phase 5.5: Plan Readiness Check

After all synthesis and red team edits are applied, verify the plan is work-ready. The command dispatches all checks directly (flat dispatch — same pattern as plan.md Phase 6.7).

**Dispatch:**

Set manifest status to `readiness_checking`.

1. Read config from compound-workflows.md `plan_readiness` section. Apply skip_checks filtering.
2. Create output directory: `mkdir -p .workflows/plan-research/<plan-stem>/readiness/run-<N>/checks/`
3. Run 3 mechanical check scripts in parallel (bash):
   - `agents/workflow/plan-checks/stale-values.sh <plan-path> <output-dir>/checks/stale-values.md`
   - `agents/workflow/plan-checks/broken-references.sh <plan-path> <output-dir>/checks/broken-references.md`
   - `agents/workflow/plan-checks/audit-trail-bloat.sh <plan-path> <output-dir>/checks/audit-trail-bloat.md`
4. Dispatch 1 semantic checks agent (background Task):
   - Agent: `agents/workflow/plan-checks/semantic-checks.md`
   - Pass: plan file path, output path (`<output-dir>/checks/semantic-checks.md`), mode (`full`), skip_checks, provenance settings
5. Wait for all checks to complete (3-minute timeout for scripts, 5-10 minutes for semantic agent). If rate limits are hit, batch checks in groups of 4.
6. Dispatch plan-readiness-reviewer (foreground Task):
   - Pass: plan file path, plan stem, output directory (run-numbered), check output file paths, mode, config
7. Show the reviewer's summary to the user: "Plan readiness check: [summary]"

Keep Phase 5.5 focused on dispatch + response handling. The detailed logic lives in the check scripts and agent files.

**If issues found:**

1. Dispatch plan-consolidator (foreground). Pass: plan file path, reviewer report path.
2. Consolidator applies auto-fixes, then presents guardrailed items to user.
3. After consolidation, re-run checks in `verify-only` mode and dispatch reviewer again.
4. If verify finds new issues: present remaining findings to user directly.
   User options: resolve now, defer to Open Questions, or dismiss.
5. Show user: "Readiness check complete. N auto-fixes applied, M items resolved, K deferred."

**If zero issues found:**

Skip consolidator and re-verify. Show: "Plan readiness check: no issues found."

**If reviewer fails:**

Warn: "Readiness check failed — consider running again before starting work."

Set manifest status to `readiness_complete`.
```

2. **Update manifest status values.** Add two new status values to the manifest lifecycle:
   - `readiness_checking` — set when Phase 5.5 starts
   - `readiness_complete` — set when readiness check finishes (whether issues were found or not)

3. **Update Phase 5 Recovery** to handle readiness-phase interruptions:
   - If manifest status is `readiness_checking`: check if readiness output files exist; if report.md exists, skip to consolidator dispatch; otherwise re-run checks and reviewer
   - If manifest status is `readiness_complete`: skip to Phase 6

4. **Update Phase 6 report** to include a "Plan Readiness" summary section: issues found, auto-fixes applied, user decisions, deferred items.

**Read for context:** The full deepen-plan.md file, especially Phases 4.5, 5, and 6.

---

### Step 7: Update setup.md

**File to modify:**
- [ ] `plugins/compound-workflows/commands/compound/setup.md`

**Changes:**

Add a `## Plan Readiness` section to the compound-workflows.md output using flat key-value format (consistent with existing `## Stack & Agents` section). Written during setup with sensible defaults:

```markdown
## Plan Readiness

plan_readiness_skip_checks: (none)
plan_readiness_provenance_expiry_days: 30
plan_readiness_verification_source_policy: conservative
```

The setup command should explain each option briefly when writing the config. The flat key-value format matches the existing config convention — no nested YAML.

**Read for context:** The full setup.md file to understand where config sections are written.

---

### Step 8: Update registry and metadata

**Files to modify:**
- [ ] `plugins/compound-workflows/CLAUDE.md` — Update agent count (22 → 24), workflow agent count (3 → 5), add both agents to Agent Registry table, add `plan-checks/` to directory structure (note: 3 shell scripts + 1 semantic agent, not counted as standalone agents in registry), document plan_readiness config keys, update config reads for plan.md and deepen-plan.md
- [ ] `plugins/compound-workflows/README.md` — Update component counts (22→24 agents in description and tables), add new agents to agent table
- [ ] `plugins/compound-workflows/CHANGELOG.md` — Add v1.7.0 section with: "### Added" listing plan-readiness-reviewer, plan-consolidator, 3 mechanical check scripts, 1 semantic checks agent, plan_readiness config, Phase 6.7 in plan.md, Phase 5.5 in deepen-plan.md
- [ ] `plugins/compound-workflows/.claude-plugin/plugin.json` — Bump version to 1.7.0 (MINOR: new agents). Update `description` field agent count (22→24)
- [ ] `.claude-plugin/marketplace.json` — Bump version to 1.7.0, update `ref` field to `v1.7.0`
- [ ] `plugins/compound-workflows/skills/disk-persist-agents/SKILL.md` — Add `readiness/` directory to the directory convention diagram with exact tree:
  ```
  plan-research/<plan-stem>/readiness/
  ├── checks/          # Individual check outputs
  ├── report.md        # Aggregated reviewer report
  └── consolidation-report.md
  ```
  And for deepen-plan: `readiness/run-<N>/` variant with the same structure.
- [ ] `AGENTS.md` — Update agent count, add QA patterns for new files

**Agent Registry entries to add:**

| Agent | Category | Dispatched By | Model |
|-------|----------|---------------|-------|
| plan-readiness-reviewer | workflow | plan, deepen-plan | inherit |
| plan-consolidator | workflow | plan, deepen-plan | inherit |

Note: The 3 mechanical check scripts and 1 semantic checks agent are check modules in `plan-checks/`, not standalone agents in the registry.

**Directory structure update for CLAUDE.md:**

```
agents/
├── research/     # Research and knowledge agents (6)
├── review/       # Code review agents (13)
└── workflow/     # Workflow utility agents (5)
    └── plan-checks/  # 3 mechanical .sh scripts + 1 semantic .md agent
```

**Config documentation for CLAUDE.md:**

Add to Config Files section:
- `plan.md` reads: plan_review_agents, depth, **plan_readiness**
- `deepen-plan.md` reads: (add) **plan_readiness**

**Read for context:** Current CLAUDE.md, README.md, CHANGELOG.md, plugin.json, marketplace.json, AGENTS.md.

---

### Step 9: QA

Run the AGENTS.md QA process (4 parallel agent checks):

- [ ] Pattern recognition specialist — verify new agents follow established conventions
- [ ] Code simplicity reviewer — verify no over-engineering in check modules
- [ ] Architecture strategist — verify integration doesn't break existing flows
- [ ] Security sentinel — verify no plan-file corruption paths

Also manually verify:
- [ ] Each mechanical check script has correct metadata comments (name, type, description, verify_only)
- [ ] Semantic checks agent has correct frontmatter and all 5 analysis passes
- [ ] Reviewer agent correctly handles input file paths (does not discover or dispatch)
- [ ] Consolidator agent has preservation rule and pass-through rule
- [ ] plan.md Phase 6.7 is correctly placed between 6.5 and 7
- [ ] deepen-plan.md Phase 5.5 is correctly placed and manifest statuses added
- [ ] setup.md writes plan_readiness config with correct defaults
- [ ] All counts match across CLAUDE.md, README.md, AGENTS.md
- [ ] Version is consistent across plugin.json and marketplace.json
- [ ] Smoke test: run the full readiness check pipeline on a test plan and verify it produces a valid report (all check scripts execute, semantic agent completes, reviewer aggregates, output matches expected template)
- [ ] Verify AskUserQuestion works from a foreground Task agent (the consolidator depends on this for user interaction)

## Key Design Decisions

All decisions trace to the brainstorm (see brainstorm: `docs/brainstorms/2026-03-08-plan-readiness-agents-brainstorm.md`):

1. **Two agents, not one** — guardrail boundary (reviewer: zero write authority; consolidator: constrained write authority) is the primary justification (brainstorm decision #1)
2. **Both in agents/workflow/** — prevents auto-discovery during deepen-plan Phase 3 (brainstorm decision #2)
3. **Mechanical vs semantic checks** — mechanical checks are actual shell scripts (not LLM agents), making the distinction genuinely meaningful: deterministic bash for pattern-matching, LLMs for judgment (brainstorm decision #9)
4. **Evidence-based auto-fix only** — auto-fix only when provenance makes correct value unambiguous; ambiguous cases route to user (brainstorm decision #4, red team C1)
5. **Preservation rule** — user decision rationale is never stripped, only reorganized (brainstorm decision #11, red team C2)
6. **Capped re-verification (max 1 cycle)** — reviewer → consolidator → verify-only → present remaining to user. No second consolidation. Simplified from brainstorm's 2-cycle cap based on deepen-plan review: 1 cycle captures 90% of value at lower integration complexity (brainstorm decision #10, deepen-plan run 1 S3)
7. **Consolidator reads full plan, no section parsing** — the consolidator reads the full plan + report in a single pass, applies fixes, and writes the result. Pass-through and preservation rules constrain what gets modified. Section-by-section parsing/reassembly was dropped because it doesn't actually reduce context within a single agent invocation (deepen-plan run 1 S2). The pass-through and preservation rules (from brainstorm decision #14) are retained as the essential guardrails.
8. **Flat dispatch with 4 check dispatches** (3 scripts + 1 semantic agent) — reduces main context usage, immediately configurable and extensible. The configurability is maintained: skip_checks applies to the semantic agent's internal pass list, and individual scripts can be skipped. Flat dispatch replaces nested dispatch-within-dispatch which was tested and proven non-functional (brainstorm decision #7)
9. **Constants-as-data pattern** — prevents stale-value proliferation at the source (brainstorm decision #12)
10. **Structured markdown output with machine-parseable format** — designed for programmatic aggregation by the reviewer. This is a new output format distinct from the free-form output used by existing review agents. No YAML/JSON for agent communication (brainstorm decision #6, reworded per deepen-plan run 1 S10)

## Design Decisions Made During Planning

These decisions resolve specflow questions that the brainstorm left open:

11. **Pass-through and preservation rules are the authority constraints** — no section parsing/reassembly, but the pass-through rule (don't modify content without findings) and preservation rule (never strip rationale text) are mechanically verified by the consolidator after writing. Resolves specflow Q1 differently: instead of parsing sections, the consolidator reads/writes the full plan with constrained authority.

12. **Cross-section dependencies handled via full report context** — the consolidator receives the full reviewer report when processing each finding, so it knows about cross-section issues. Auto-fix ONLY when explicit canonical source exists (constants section or provenance log). All other value conflicts route to user. Resolves specflow Q2.

13. **Deferred readiness findings go to plan's Open Questions** — ensures `/compound:work` Phase 1.1 surfaces them. Only on-disk storage would mean work.md needs a new step. Resolves specflow Q4.

14. **Single consolidator dispatch, internal section iteration** — one agent reads the full plan, processes sections sequentially within its context. Preserves cross-section awareness while keeping dispatch simple. Resolves specflow Q5.

15. **Verify-only mode = checks with `verify_only: true` OR `type: mechanical`** — all 3 mechanical checks + contradictions + underspecification. Unresolved-disputes, accretion, external-verification are excluded from verify-only. Resolves specflow Q6.

16. **Consolidator writes report incrementally** — after each finding is processed, the auto-fix log is appended to the consolidation report. The consolidator iterates through findings (from the reviewer report), not plan sections. Protects against interruption (specflow Gap 1).

17. **Pass-through rule for untouched sections** — sections with no findings pass through unchanged. Consolidator has no authority to "improve" sections without documented findings (specflow Gap 19).

18. **Reviewer shows summary to user before consolidation** — user sees "Plan readiness check found N SERIOUS, M MINOR issues. Running consolidation..." (specflow Q7).

19. **Batch user decisions use severity-based triage** — CRITICAL and SERIOUS individually, MINOR as batch-accept option. Same pattern as deepen-plan synthesis gate (specflow Gap 20).

20. **Minimum plan size check (20 substantive lines)** — plans under 20 lines skip all checks. Saves 4 check dispatches on trivially small plans (specflow Gap 6).

## Dependency Graph

```
Step 1 (mechanical scripts) ──┐
                               ├── Step 3 (reviewer-aggregator) ── Step 4 (consolidator) ──┬── Step 5 (plan.md) ── Step 6 (deepen-plan.md)
Step 2 (semantic agent) ──────┘                                                             │
                                                                                            │
Step 7 (setup.md) ── independent ──────────────────────────────────────────────────────────┘

All above ──► Step 8 (registry) ──► Step 9 (QA)
```

**Sequential dependencies:**
- Step 3 depends on Steps 1+2 (references check module output paths and format)
- Step 4 depends on Step 3 (reads reviewer output format to know what it receives)
- Steps 5+6 depend on Steps 1+2 (contain dispatch logic for the check scripts/agent)
- Step 6 depends on Step 5 (Phase 5.5 adapts Phase 6.7's content)

**Parallel opportunities:**
- Steps 1 + 2 are independent (different files, same directory)
- Step 7 is independent of Steps 3-6

**Work-readiness notes:**
- Step 1 creates 3 shell scripts following the same template — a subagent can create all in one step
- Step 2 creates 1 semantic checks agent file with 5 analysis passes
- Step 3 (reviewer-aggregator) is simpler than originally scoped — no dispatch logic, just parsing/deduplication/aggregation
- Step 4 (consolidator) is complex — full-plan processing with pass-through/preservation rules and mechanical verification
- Steps 5+6 now contain dispatch logic (moved from reviewer) — the commands orchestrate directly
- Step 8 is a sweep across 7 files but each change is small (counts, table rows, version numbers)

## Open Questions

(None — all specflow questions resolved in "Design Decisions Made During Planning" above.)

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-03-08-plan-readiness-agents-brainstorm.md` — 14 key decisions, 7 resolved questions, red-teamed by 3 providers. All design decisions trace back here.
- **Session log analysis:** `.workflows/brainstorm-research/fix-verification-agent/session-log-analysis.md` — empirical evidence for the five-category taxonomy
- **Iteration taxonomy:** `docs/solutions/process-analysis/2026-03-08-deepen-plan-iteration-taxonomy.md` — compound solution documenting the finding
- **Repo research:** `.workflows/plan-research/plan-readiness-agents/agents/repo-research.md` — agent structure patterns, command integration points, file conventions
- **Institutional learnings:** `.workflows/plan-research/plan-readiness-agents/agents/learnings.md` — 10 critical learnings informing the design
- **Specflow analysis:** `.workflows/plan-research/plan-readiness-agents/agents/specflow.md` — 26 gaps and 9 questions, all resolved
- **Deepen-plan run 1:** `.workflows/deepen-plan/feat-plan-readiness-agents/run-1-synthesis.md` — 4 agents (architecture, simplicity, patterns, work-readiness), 12 SERIOUS findings triaged, scope/consolidator/re-verify simplified
- **Deepen-plan run 1 red team:** `.workflows/deepen-plan/feat-plan-readiness-agents/agents/run-1/red-team--*.md` — 3 providers (Gemini, OpenAI, Opus), 6 CRITICAL + 16 SERIOUS + 10 MINOR deduplicated findings
