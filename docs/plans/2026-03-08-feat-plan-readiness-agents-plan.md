---
title: "Plan Readiness Agents: plan-readiness-reviewer + plan-consolidator"
type: feat
status: completed
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
- [x] `plugins/compound-workflows/agents/workflow/plan-checks/stale-values.sh`
- [x] `plugins/compound-workflows/agents/workflow/plan-checks/broken-references.sh`
- [x] `plugins/compound-workflows/agents/workflow/plan-checks/audit-trail-bloat.sh`

**Each shell script follows this structure:**

```bash
#!/usr/bin/env bash
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
5. Shell safety: all variable expansions double-quoted (`"$var"`, not `$var`), `grep -F` for literal matching of values extracted from the plan, no `eval` or dynamic command construction from plan content, path validation for any file-existence checks (resolved path must stay within project directory). macOS portability: use `#!/usr/bin/env bash` shebang (not `#!/bin/bash`); for path resolution, use `cd "$(dirname "$target")" && pwd -P` instead of `realpath` (not available on stock macOS); avoid bash 4+ features (associative arrays, nameref) for macOS `/bin/bash` 3.2 compatibility; for md5 comparison, use: `md5 -q "$file" 2>/dev/null || md5sum "$file" | cut -d' ' -f1`

**Specific check instructions:**

**stale-values:** Detect the same value (numbers, constants, thresholds) appearing in multiple plan locations with different values. Two modes: (a) if plan has a `## Constants` section, verify all references match the defined values; (b) if no constants section, find identical labels (e.g., `budget_limit`, `max_retries`) that appear with different numeric values in different locations. Use grep/regex to find numeric patterns and cross-reference. Report each mismatch with both locations and both values. Uses conservative matching — only flags exact-match patterns (e.g., same label with different numbers), not heuristic "similar concept" matches.

**broken-references:** Detect cross-references like `(R12)`, `(S3)`, `Step 4.2` that point to wrong or non-existent targets. Parse all reference patterns, build a reference index, and check each target exists. Report broken references with the referencing location and the missing target. When checking file-existence for reference targets, validate that the resolved path stays within the project directory (`cd "$(dirname "$target")" && pwd -P` must start with the project root).

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

**Atomic output writes:** Each script writes output to `<output-path>.tmp` first, then `mv <output-path>.tmp <output-path>`. This ensures the reviewer never reads a partially-written file.

**Output size cap:** Each check script MUST cap its output at 150-200 lines. If findings exceed this, include the highest-severity findings and add a truncation notice: "Output truncated at 150 lines. N additional findings omitted — see full analysis for details." When truncating, preserve all CRITICAL and SERIOUS findings first. Only truncate MINOR findings. This prevents the reviewer's context from being exhausted during deduplication/aggregation.

**Read for patterns:** Read `plugins/compound-workflows/agents/workflow/spec-flow-analyzer.md` for workflow agent structure. Read `plugins/compound-workflows/agents/review/code-simplicity-reviewer.md` for review output format conventions.

### Run 2 Review Findings — Step 1

**Serious:**
- Shell scripts processing LLM-generated plan content are vulnerable to regex injection, path traversal, and unquoted variable expansion. Added shell safety requirements (item 5), `grep -F` for literal matching, path validation to broken-references, and atomic output writes. [security-sentinel F1]

**Minor:**
- Stale-values mode (b) description ("compare values that appear to represent the same concept") contradicted its own conservative-matching constraint. Reworded to "find identical labels with different numeric values." [code-simplicity-reviewer]
- `verify_only: true` in the script template is redundant with Decision #15's `type: mechanical` filter. All 3 scripts are `type: mechanical` AND `verify_only: true` — two paths to the same behavior. Kept both for clarity but noted the redundancy. [architecture-strategist M5]

---

### Step 2: Create semantic checks agent

Create a single semantic checks agent file that performs all 5 semantic analysis passes in one plan read. Bundling into 1 agent reduces dispatch count and avoids redundant plan reads.

**File to create:**
- [x] `plugins/compound-workflows/agents/workflow/plan-checks/semantic-checks.md`

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

Body contains: role description, instructions for all 5 analysis passes (performed sequentially within a single plan read), judgment criteria for each pass, output template (same finding-level format as mechanical checks, with pass-level breakdown in the summary; same 150-200 line output cap — when truncating, preserve all CRITICAL and SERIOUS findings first, only truncate MINOR findings). The agent reads the plan once and performs all 5 passes, writing a single combined output file.

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

### Run 2 Review Findings — Step 2

**Minor:**
- "Same format as mechanical checks" claim is inaccurate — templates differ in Summary section (pass-level breakdown vs. timing). Changed to "same finding-level format." [pattern-recognition-specialist]

---

### Step 3: Create plan-readiness-reviewer agent (aggregator)

**File to create:**
- [x] `plugins/compound-workflows/agents/workflow/plan-readiness-reviewer.md`

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

7. **Aggregation:** Write aggregated report to `.workflows/plan-research/<plan-stem>/readiness/report.md`. Include: plan file content hash (`md5 -q "$file" 2>/dev/null || md5sum "$file" | cut -d' ' -f1`, used by consolidator to detect if plan was modified between phases), overall severity summary, deduplicated findings in structured markdown (same output template as individual checks), completeness metadata (list of checks that ran, their status — success/timeout/error, `complete: true/false` flag — `complete: true` when all expected checks reported `status: success`; the consolidator proceeds on `complete: false` but includes a warning in its output). When dispatched from deepen-plan, use run-numbered path: `.workflows/plan-research/<plan-stem>/readiness/run-<N>/report.md`. Only read check outputs that contain findings — skip zero-finding outputs to reduce context load.

8. **Provenance log:** If external-verification pass reported verified YAML data in its findings, write that data to `.workflows/plan-research/<plan-stem>/provenance.md`. The reviewer is the single writer of provenance data — the semantic checks agent only reports verification results.

9. **Write authority:** ZERO plan-file write authority. Metadata writes only (report, provenance log).

10. **Return:** 2-3 sentence summary to parent with issue count and severity breakdown.

**Rate limit handling note:** If rate limits are hit during check dispatch, the command should retry with exponential backoff. The semantic checks agent gets a longer timeout (5-10 minutes instead of 3) due to WebSearch latency in the external-verification pass. Document this in the reviewer's instructions as context for timeout handling.

**Mode parameter:** The `mode` parameter (`full` or `verify-only`) is included in report metadata for traceability but does not change the reviewer's aggregation behavior. The command controls which checks run via dispatch decisions.

**Read for patterns:** `plugins/compound-workflows/commands/compound/deepen-plan.md` Phase 2c for agent discovery pattern. `plugins/compound-workflows/skills/disk-persist-agents/SKILL.md` for disk-write conventions. Existing workflow agents for file structure conventions.

**Examples section:** Include 2-3 examples showing: (a) plan with multiple issues found, (b) clean plan with 0 issues, (c) verify-only mode after consolidation.

### Run 2 Review Findings — Step 3

**Serious:**
- "Batch checks in groups of 4" was a vestige of the 8-check design — with exactly 4 dispatches, this instruction was a no-op. Replaced with "retry with exponential backoff." [architecture-strategist S3]

**Minor:**
- External-verification timeout was framed as pass-specific ("External-verification gets a longer timeout") but it applies to the entire semantic agent Task. Reworded to "The semantic checks agent gets a longer timeout." [architecture-strategist M2]
- Reviewer `mode` parameter had no behavioral effect but this was not documented. Added "Mode parameter" note clarifying it is metadata-only. [architecture-strategist M1]
- `complete: true/false` flag was undefined. Added inline definition: "complete: true when all expected checks reported status: success." [code-simplicity-reviewer]

---

### Step 4: Create plan-consolidator agent

**File to create:**
- [x] `plugins/compound-workflows/agents/workflow/plan-consolidator.md`

**Frontmatter:**

```yaml
---
name: plan-consolidator
description: "Fixes plan readiness issues with evidence-based auto-fixes and guardrailed user decisions"
model: inherit
---
```

**Implementation note:** The consolidator runs as a foreground Task agent. Foreground Task agents CAN use AskUserQuestion to interact with the user — this is the same mechanism used by deepen-plan's synthesis gate. The consolidator is the first workflow agent with interactive user communication. Fallback: If AskUserQuestion is not available from within a foreground Task agent, the consolidator should write all guardrailed findings to the consolidation report with status 'requires-user-decision' and return them to the parent command, which then handles user interaction directly using the same batch-decision format.

**Agent instructions must cover:**

1. **Input parameters** (passed via prompt): plan file path, reviewer report path (`.workflows/plan-research/<plan-stem>/readiness/report.md` or `.workflows/plan-research/<plan-stem>/readiness/run-<N>/report.md` when from deepen-plan), consolidation report output path.

2. **Plan integrity check:** Read the reviewer report's plan file content hash. Compute hash using `md5 -q "$file" 2>/dev/null || md5sum "$file" | cut -d' ' -f1` and compare. If mismatch: hard-stop and surface to user: "Plan modified since review. Rerun readiness check?" Never proceed with stale findings.

3. **Read full context:** Read the entire plan file and the full reviewer report. The consolidator operates on the full plan in a single pass — no section-by-section parsing or reassembly. This keeps the implementation simple while the pass-through and preservation rules (below) constrain what gets modified. For plans exceeding 500 lines, the consolidator should use offset/limit when reading and rely on the Edit tool's search/replace to apply targeted fixes without holding the full plan in working memory. The reviewer report identifies which sections need modification by heading text.

4. **Apply auto-fixes** (evidence-based, no user input):
   - Fix broken cross-references ONLY when the correct target is unambiguous (e.g., typo in reference pattern where intended target clearly exists). Missing targets with no obvious correct target route to user batch-decision.
   - Strip superseded "Run N" annotations that conflict with current spec text
   - Deduplicate stale values ONLY when explicit canonical source exists (constants section defines canonical value, or provenance log confirms value). Do NOT use "most-detailed specification" heuristic — all other value conflicts route to user.
   - Log each auto-fix to the consolidation report as it is applied (incremental writing protects against interruption)
   - **Plan size determines write strategy:** For plans >200 lines, use Edit tool (search/replace) instead of Write to minimize regression risk. For plans ≤200 lines, Write is acceptable. This is a dynamic choice based on plan size. If an Edit tool call fails (e.g., old_string not found due to whitespace mismatch), log the failure to the consolidation report and skip that finding. Do not attempt to rewrite the full file as a fallback — skip the individual fix and continue with remaining findings.
   - **File-path constraint:** The consolidator may ONLY write to two files: (1) the plan file (path received as input parameter) and (2) the consolidation report (path received as input parameter). Any Edit or Write call to a path not matching one of these two MUST be rejected. The consolidator does NOT modify source code, config files, or any file referenced within the plan.
   - **Write ordering:** For each finding: (1) log the decision/fix to the consolidation report, (2) then apply the edit to the plan file. This ensures user reasoning is captured even if the subsequent plan edit fails or the session is interrupted.
   - **Batch auto-fixes with related user decisions:** When auto-fixable and guardrailed findings reference the same plan section, present them together so the user sees the full picture before anything is applied. Do not apply auto-fixes independently of related user decisions. Pre-pass: group all findings by plan section. For each section, identify auto-fixable and guardrailed findings. If a section has only auto-fixable findings, apply immediately. If a section has any guardrailed findings, hold all findings for that section until user decisions are made.

5. **Pass-through rule:** Do NOT modify any content that has no associated findings from the reviewer. Write authority extends only to content with documented findings, and only to the specific issues described. Do not edit, reformat, or "improve" untouched content.

6. **Preservation rule:** NEVER strip text recording user decisions and reasoning. Patterns: "Rationale:", "Decision:", "Rejected because:", "User noted:", "Chose X over Y because". These are only reorganized (e.g., moved from an annotation block to the spec section), never deleted.

7. **Mechanical authority verification:** After writing the updated plan, run a verification pass:
   - Grep for all preservation-pattern lines in the original plan and verify every instance exists in the updated plan
   - Normalize both old and new content before comparing: strip leading/trailing whitespace, collapse internal whitespace, lowercase. This handles rewrapping and minor formatting changes that don't affect meaning.
   - If any preservation-pattern lines are missing after normalization, flag as a warning and restore them
   - Additionally, scan for sections where the same concept now has two descriptions (pre-fix text retained alongside post-fix text). Flag as warning if found — this catches accretion introduced by the consolidator itself.
   - **Size-change check:** Compare total line counts (original vs. updated). If the updated plan is more than 20% larger than the original, flag a warning: "Plan grew by N% during consolidation. Review added content." Exclude lines added to the Open Questions section from the size-change calculation, since deferred findings are expected to grow this section. This catches runaway additions without blocking legitimate fixes (e.g., creating an Open Questions section).
   The consolidator performs verification using Bash/Grep tool calls (e.g., `grep -F` for pattern matching), not pure LLM inference. This is tool-based deterministic verification.

8. **Batch user decisions:** Present all guardrailed items (ambiguous values, design disputes, spec gaps) as a batch via AskUserQuestion. Apply severity-based triage: CRITICAL individually, SERIOUS individually, MINOR as batch-accept option. When multiple findings target the same section, group them and present as a batch so the user sees the full picture for that section. Record user's reasoning for each decision.

9. **Deferred findings:** User-deferred findings are added to the plan's "Open Questions" section (create it if it doesn't exist, placed before Sources). This ensures `/compound:work` Phase 1.1 surfaces them.

10. **Output:** Write updated plan file. Write consolidation report to `.workflows/plan-research/<plan-stem>/readiness/consolidation-report.md` (or `.workflows/plan-research/<plan-stem>/readiness/run-<N>/consolidation-report.md` when from deepen-plan) with: auto-fixes applied (before/after), user decisions made, deferred items.

11. **Return:** Summary of auto-fixes applied, user decisions made, deferred items count.

**Read for patterns:** Same as Step 3. Also read the brainstorm's "Why Two Agents, Not One" section for the guardrail boundary rationale.

**Examples section:** Include 2-3 examples showing: (a) plan with auto-fixable issues only, (b) plan with guardrailed items requiring user decisions, (c) plan where consolidation introduces a new issue caught by re-verify.

### Run 2 Review Findings — Step 4

**Serious:**
- Consolidator input/output paths omitted run-numbered variant for deepen-plan. Added `run-<N>/` variants to both reviewer report input path (item 1) and consolidation report output path (item 10). [architecture-strategist S2]
- Consolidator Edit tool usage had no file-path constraint — could theoretically modify source files referenced in the plan. Added explicit two-file constraint (plan file + consolidation report only). [security-sentinel F2]

**Minor:**
- "Batch auto-fixes with related user decisions" lacked an algorithm. Added pre-pass grouping description. [code-simplicity-reviewer]
- No write-volume constraint existed. Added 20% size-change guardrail to mechanical authority verification (warning, not hard-stop). [security-sentinel F7]
- Write ordering (log decision before applying edit) was not specified. Added write-ordering requirement for interruption safety. [security-sentinel F6]

---

### Step 5: Integrate into plan.md

**File to modify:**
- [x] `plugins/compound-workflows/commands/compound/plan.md`

**Changes:**

Insert **Phase 6.7: Plan Readiness Check** between Phase 6.5 (Pre-Handoff Gates) and Phase 7 (Post-Generation Options).

**Phase 6.7 content:**

```markdown
### 6.7. Plan Readiness Check

Run plan readiness checks and aggregate findings to verify the plan is work-ready. The command dispatches all checks directly (flat dispatch — no nested agent dispatch).

**Dispatch:**

1. Read config from compound-workflows.md under the `## Plan Readiness` heading. Read flat keys (`plan_readiness_skip_checks`, `plan_readiness_provenance_expiry_days`, `plan_readiness_verification_source_policy`) and construct the parameter objects to pass to agents. Apply skip_checks filtering.
2. Create output directory: `mkdir -p .workflows/plan-research/<plan-stem>/readiness/checks/`
3. Run 3 mechanical check scripts in parallel (bash):
   - `agents/workflow/plan-checks/stale-values.sh <plan-path> <output-dir>/checks/stale-values.md`
   - `agents/workflow/plan-checks/broken-references.sh <plan-path> <output-dir>/checks/broken-references.md`
   - `agents/workflow/plan-checks/audit-trail-bloat.sh <plan-path> <output-dir>/checks/audit-trail-bloat.md`
4. If all 5 semantic passes are in skip_checks, skip the semantic agent dispatch entirely. Otherwise, dispatch 1 semantic checks agent (background Task):
   - Agent: `agents/workflow/plan-checks/semantic-checks.md`
   - Pass: plan file path, output path (`<output-dir>/checks/semantic-checks.md`), mode (`full`), skip_checks, provenance settings
5. Wait for all checks to complete (3-minute timeout for scripts, 5-10 minutes for semantic agent due to WebSearch latency). After timeout, remove any orphaned .tmp files: `rm -f <output-dir>/checks/*.tmp`. If rate limits are hit, retry with exponential backoff.
6. Dispatch plan-readiness-reviewer (foreground Task):
   - Pass: plan file path, plan stem, output directory, check output file paths, mode, config
7. Show the reviewer's summary to the user: "Plan readiness check: [summary]"

Keep Phase 6.7 focused on dispatch + response handling. The detailed analysis logic lives in the check scripts and agent files.

**If issues found:**

1. Dispatch plan-consolidator (foreground). Pass: plan file path, reviewer report path, consolidation report output path.
2. Consolidator applies auto-fixes, then presents guardrailed items to user.
3. After consolidation, re-run checks in `verify-only` mode: re-run all 3 mechanical scripts (type: mechanical), re-dispatch semantic agent with `mode: verify-only` (runs contradictions + underspecification only; skips unresolved-disputes, accretion, external-verification). Dispatch reviewer again.
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
- [x] `plugins/compound-workflows/commands/compound/deepen-plan.md`

**Changes:**

1. **Insert Phase 5.5: Plan Readiness Check** between Phase 5 (Recovery) and Phase 6 (Cleanup and Report). In the normal (non-recovery) flow, this runs after Phase 4.5 (Red Team Challenge).

**Phase 5.5 content:**

```markdown
## Phase 5.5: Plan Readiness Check

After all synthesis and red team edits are applied, verify the plan is work-ready. The command dispatches all checks directly (flat dispatch — same pattern as plan.md Phase 6.7).

**Dispatch:**

Set manifest status to `readiness_checking`.

1. Read config from compound-workflows.md under the `## Plan Readiness` heading. Read flat keys (`plan_readiness_skip_checks`, `plan_readiness_provenance_expiry_days`, `plan_readiness_verification_source_policy`) and construct the parameter objects to pass to agents. Apply skip_checks filtering.
2. Create output directory: `mkdir -p .workflows/plan-research/<plan-stem>/readiness/run-<N>/checks/`
3. Run 3 mechanical check scripts in parallel (bash):
   - `agents/workflow/plan-checks/stale-values.sh <plan-path> <output-dir>/checks/stale-values.md`
   - `agents/workflow/plan-checks/broken-references.sh <plan-path> <output-dir>/checks/broken-references.md`
   - `agents/workflow/plan-checks/audit-trail-bloat.sh <plan-path> <output-dir>/checks/audit-trail-bloat.md`
4. If all 5 semantic passes are in skip_checks, skip the semantic agent dispatch entirely. Otherwise, dispatch 1 semantic checks agent (background Task):
   - Agent: `agents/workflow/plan-checks/semantic-checks.md`
   - Pass: plan file path, output path (`<output-dir>/checks/semantic-checks.md`), mode (`full`), skip_checks, provenance settings
5. Wait for all checks to complete (3-minute timeout for scripts, 5-10 minutes for semantic agent). After timeout, remove any orphaned .tmp files: `rm -f <output-dir>/checks/*.tmp`. If rate limits are hit, retry with exponential backoff.
6. Dispatch plan-readiness-reviewer (foreground Task):
   - Pass: plan file path, plan stem, output directory (run-numbered), check output file paths, mode, config
7. Show the reviewer's summary to the user: "Plan readiness check: [summary]"

The readiness run number is the deepen-plan run number, not an independent counter. Pass the deepen-plan run number to the readiness dispatch.

Keep Phase 5.5 focused on dispatch + response handling. The detailed logic lives in the check scripts and agent files.

**If issues found:**

1. Dispatch plan-consolidator (foreground). Pass: plan file path, reviewer report path, consolidation report output path.
2. Consolidator applies auto-fixes, then presents guardrailed items to user.
3. After consolidation, re-run checks in `verify-only` mode: re-run all 3 mechanical scripts (type: mechanical), re-dispatch semantic agent with `mode: verify-only` (runs contradictions + underspecification only; skips unresolved-disputes, accretion, external-verification). Dispatch reviewer again.
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

### Run 2 Review Findings — Steps 5+6

**Serious:**
- Verify-only re-dispatch logic was underspecified — neither step described the dual mechanism (scripts filtered by type: mechanical, semantic agent filtered by mode: verify-only). Added explicit dispatch instructions to both steps. [architecture-strategist S4]
- "Batch checks in groups of 4" appeared in both steps — vestige of 8-check design. Replaced with "retry with exponential backoff." [architecture-strategist S3]

**Recommendations:**
- Add a single-line sync comment in each command file: `# Mirrors plan.md Phase 6.7 / deepen-plan.md Phase 5.5 — keep in sync.` [code-simplicity-reviewer]

---

### Step 7: Update setup.md

**File to modify:**
- [x] `plugins/compound-workflows/commands/compound/setup.md`

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
- [x] `plugins/compound-workflows/CLAUDE.md` — Update agent count (22 → 24), workflow agent count (3 → 5), add both agents to Agent Registry table, add `plan-checks/` to directory structure (note: 3 shell scripts + 1 semantic agent, not counted as standalone agents in registry), document plan_readiness config keys, update config reads for plan.md and deepen-plan.md
- [x] `plugins/compound-workflows/README.md` — Update component counts (22→24 agents in description and tables), add new agents to agent table
- [x] `plugins/compound-workflows/CHANGELOG.md` — Add v1.7.0 section with: "### Added" listing plan-readiness-reviewer, plan-consolidator, 3 mechanical check scripts, 1 semantic checks agent, plan_readiness config, Phase 6.7 in plan.md, Phase 5.5 in deepen-plan.md
- [x] `plugins/compound-workflows/.claude-plugin/plugin.json` — Bump version to 1.7.0 (MINOR: new agents). Update `description` field agent count (22→24)
- [x] `.claude-plugin/marketplace.json` — Bump version to 1.7.0, update `ref` field to `v1.7.0`
- [x] `plugins/compound-workflows/skills/disk-persist-agents/SKILL.md` — Add `readiness/` directory to the directory convention diagram with exact tree:
  ```
  plan-research/<plan-stem>/readiness/
  ├── checks/          # Individual check outputs
  ├── report.md        # Aggregated reviewer report
  └── consolidation-report.md
  ```
  And for deepen-plan: `readiness/run-<N>/` variant with the same structure.
- [x] `AGENTS.md` — Update agent count, add QA patterns for new files

**Agent Registry entries to add:**

| Agent | Category | Dispatched By | Model |
|-------|----------|---------------|-------|
| plan-readiness-reviewer | workflow | plan, deepen-plan | inherit |
| plan-consolidator | workflow | plan, deepen-plan | inherit |

Note: The 3 mechanical check scripts and 1 semantic checks agent are check modules in `plan-checks/`, not standalone agents in the registry. Rationale for excluding semantic-checks: it is a check module co-located with the scripts it complements, only dispatched as part of the readiness check pipeline, never independently. The CLAUDE.md directory structure should note that plan-checks/ contains 3 shell scripts and 1 agent-format .md file counted as a check module, not a standalone agent.

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

- [x] Pattern recognition specialist — verify new agents follow established conventions
- [x] Code simplicity reviewer — verify no over-engineering in check modules
- [x] Architecture strategist — verify integration doesn't break existing flows
- [x] Security sentinel — verify no plan-file corruption paths

Also manually verify:
- [x] Each mechanical check script has correct metadata comments (name, type, description, verify_only)
- [x] Semantic checks agent has correct frontmatter and all 5 analysis passes
- [x] Reviewer agent correctly handles input file paths (does not discover or dispatch)
- [x] Consolidator agent has preservation rule and pass-through rule
- [x] plan.md Phase 6.7 is correctly placed between 6.5 and 7
- [x] deepen-plan.md Phase 5.5 is correctly placed and manifest statuses added
- [x] setup.md writes plan_readiness config with correct defaults
- [x] All counts match across CLAUDE.md, README.md, AGENTS.md
- [x] Version is consistent across plugin.json and marketplace.json
- [x] Smoke test: run the full readiness check pipeline on a test plan and verify it produces a valid report (all check scripts execute, semantic agent completes, reviewer aggregates, output matches expected template)
- [x] Create test fixture plans (one with stale values, one with broken references, one with audit-trail bloat) and verify each script produces correct output on its fixture
- [x] Verify AskUserQuestion works from a foreground Task agent (the consolidator depends on this for user interaction)

## Key Design Decisions

All decisions trace to the brainstorm (see brainstorm: `docs/brainstorms/2026-03-08-plan-readiness-agents-brainstorm.md`):

1. **Two agents, not one** — guardrail boundary (reviewer: zero write authority; consolidator: constrained write authority) is the primary justification (brainstorm decision #1)
2. **Both in agents/workflow/** — prevents auto-discovery during deepen-plan Phase 2c (brainstorm decision #2)
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

14. **Single consolidator dispatch, internal finding iteration** — one agent reads the full plan, iterates through findings from the reviewer report, and processes each in context. Preserves cross-section awareness while keeping dispatch simple. Resolves specflow Q5.

15. **Verify-only mode** — run all 3 mechanical scripts (which always execute — they have no mode concept) + dispatch semantic agent in verify-only mode (runs only contradictions and underspecification passes). Unresolved-disputes, accretion, external-verification are excluded from verify-only. Resolves specflow Q6.

16. **Consolidator writes report incrementally** — after each finding is processed, the auto-fix log is appended to the consolidation report. The consolidator iterates through findings (from the reviewer report), not plan sections. Protects against interruption (specflow Gap 1).

17. **Pass-through rule for untouched sections** — sections with no findings pass through unchanged. Consolidator has no authority to "improve" sections without documented findings (specflow Gap 19).

18. **Reviewer shows summary to user before consolidation** — user sees "Plan readiness check found N SERIOUS, M MINOR issues. Running consolidation..." (specflow Q7).

19. **Batch user decisions use severity-based triage** — CRITICAL and SERIOUS individually, MINOR as batch-accept option. Same pattern as deepen-plan synthesis gate (specflow Gap 20).

20. **Minimum plan size check (20 substantive lines)** — plans under 20 lines skip all checks. Saves 4 check dispatches on trivially small plans (specflow Gap 6).

### Run 2 Review Findings — Design Decisions

**Serious:**
- Decision #14 said "internal section iteration" which contradicted Decisions #7, #16, and Step 4 item 3 (all say finding-based iteration, no section parsing). Stale from run-1 S2 edit. Fixed: reworded to "internal finding iteration." [architecture-strategist S1, code-simplicity-reviewer]
- Decision #2 referenced "deepen-plan Phase 3" but agent discovery happens in Phase 2c. Two other references in this plan correctly said "Phase 2c." Fixed. [pattern-recognition-specialist]

**Minor:**
- Decisions 5, 11, and 17 overlap — three numbered items describing two rules (pass-through, preservation). Not fixed: user explicitly chose to keep all 20 decisions. The overlap is noted but acceptable given the user's preference for explicit constraints. [code-simplicity-reviewer]
- Decision 12 is a natural consequence of Decision 7 (reading the full report gives cross-section context). Not fixed: same rationale as above. [code-simplicity-reviewer]
- Semantic-checks.md is a full .md agent dispatched as a Task but excluded from agent count. Added rationale note in Step 8: co-located check module, not standalone. [architecture-strategist M3]

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
- Steps 5+6 depend on Steps 1-4 (contain dispatch logic for all checks, reviewer, and consolidator)
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
