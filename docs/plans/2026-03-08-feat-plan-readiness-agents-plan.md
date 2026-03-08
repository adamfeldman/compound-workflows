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

Two new agents that run at the end of every `/compound:plan` and `/compound:deepen-plan`:

1. **plan-readiness-reviewer** — Dispatches 8 check modules in parallel, aggregates findings into a structured report. Zero plan-file write authority.
2. **plan-consolidator** — Fixes issues from the reviewer. Evidence-based auto-fixes for mechanical issues; routes judgment calls to user. Constrained write authority with preservation rules.

Re-verification loop capped at 1 cycle (reviewer → consolidator → verify-only → present remaining to user). No second consolidation.

## Implementation Steps

### Step 1: Create mechanical check modules

Create `plugins/compound-workflows/agents/workflow/plan-checks/` directory and 3 mechanical check module files.

**Files to create:**
- [ ] `plugins/compound-workflows/agents/workflow/plan-checks/stale-values.md`
- [ ] `plugins/compound-workflows/agents/workflow/plan-checks/broken-references.md`
- [ ] `plugins/compound-workflows/agents/workflow/plan-checks/audit-trail-bloat.md`

**Each check module file follows this structure:**

```yaml
---
name: <check-name>
description: "<one-line description>"
model: inherit
type: mechanical
verify_only: true   # mechanical checks always run in verify-only mode
---
```

**Note:** Check modules extend the standard agent frontmatter (`name`, `description`, `model`) with `type` and `verify_only` fields. The `model` field is included for consistency even though mechanical checks use scripts. Deepen-plan Phase 2c discovers these files but the `workflow/` skip rule filters them out — they are NOT general-purpose review agents.

Body contains:
1. Role description ("You are a plan readiness check that...")
2. What to detect (specific patterns, with examples)
3. How to detect it (bash commands, regex patterns, line counting)
4. Output template with required sections: Findings (severity-tagged), Summary

**Specific check instructions:**

**stale-values:** Detect the same value (numbers, constants, thresholds) appearing in multiple plan locations with different values. Two modes: (a) if plan has a `## Constants` section, verify all references match the defined values; (b) if no constants section, compare values that appear to represent the same concept across locations. Use grep/regex to find numeric patterns and cross-reference. Report each mismatch with both locations and both values.

**broken-references:** Detect cross-references like `(R12)`, `(S3)`, `Step 4.2` that point to wrong or non-existent targets. Parse all reference patterns, build a reference index, and check each target exists. Report broken references with the referencing location and the missing target.

**audit-trail-bloat:** Detect "Run N Review Findings" or similar annotation sections. Calculate ratio of spec text to annotation text. Flag when annotations exceed 30% of total plan content, or when annotations contradict current spec text. Report total lines, spec lines, annotation lines, and specific contradictory annotations.

**Output template for all mechanical checks:**

```markdown
## Findings

### [SEVERITY] <finding-title>
- **Check:** <check-name>
- **Location:** <section name or line range>
- **Description:** <what was detected>
- **Values:** <specific values, if applicable>
- **Suggested fix:** <what should change>

## Summary
- Total findings: N
- By severity: N CRITICAL, N SERIOUS, N MINOR
- Check completed in: N seconds
```

**Output size cap:** Each check module MUST cap its output at 150-200 lines. If findings exceed this, include the highest-severity findings and add a truncation notice: "Output truncated at 150 lines. N additional findings omitted — see full analysis for details." This prevents the reviewer's context from being exhausted during deduplication/aggregation.

**Read for patterns:** Read `plugins/compound-workflows/agents/workflow/spec-flow-analyzer.md` for workflow agent structure. Read `plugins/compound-workflows/agents/review/code-simplicity-reviewer.md` for review output format conventions.

---

### Step 2: Create semantic check modules

Create 5 semantic (LLM-based) check module files in the same `plan-checks/` directory.

**Files to create:**
- [ ] `plugins/compound-workflows/agents/workflow/plan-checks/contradictions.md`
- [ ] `plugins/compound-workflows/agents/workflow/plan-checks/unresolved-disputes.md`
- [ ] `plugins/compound-workflows/agents/workflow/plan-checks/underspecification.md`
- [ ] `plugins/compound-workflows/agents/workflow/plan-checks/accretion.md`
- [ ] `plugins/compound-workflows/agents/workflow/plan-checks/external-verification.md`

**Each file follows this structure:**

```yaml
---
name: <check-name>
description: "<one-line description>"
model: inherit
type: semantic
verify_only: false   # unless this check should run in verify-only mode
---
```

Body contains: role description, what to analyze, judgment criteria, output template (same format as mechanical checks, same 150-200 line output cap).

**Specific check instructions:**

**contradictions** (`verify_only: true`): Find sections that disagree with each other — different values for the same concept, conflicting instructions, mutually exclusive requirements. Read the full plan and cross-reference claims section by section. Be specific about which sections contradict and what each says.

**unresolved-disputes** (`verify_only: false`): Find design tradeoffs flagged by reviewers that were never explicitly decided. Read prior gate decisions from `.workflows/deepen-plan/<plan-stem>/` and `.workflows/plan-research/<plan-stem>/` to distinguish settled decisions from ongoing disagreements. Do NOT re-flag disputes the user already resolved — check the gate logs first. If no gate logs exist (plan not created by /compound:plan), skip this check and report "No prior gate decisions found — skipping."

**underspecification** (`verify_only: false`): Find steps too vague for a subagent to execute independently. Check for: missing function signatures, undefined data shapes, unspecified interfaces, steps that require judgment calls without guidance, steps that reference external resources without URLs or file paths. This check has highest value at round 1. Rate severity: CRITICAL = subagent cannot proceed; SERIOUS = subagent must guess; MINOR = subagent can infer from context.

**accretion** (`verify_only: false`): Find features with 3+ descriptions at different points in their evolution — the original spec, a "Run N" correction, a later override, etc. The subagent wouldn't know which version to implement. Flag when the same feature/concept has multiple contradictory descriptions in different sections or annotations.

**external-verification** (`verify_only: false`): Verify externally-sourced facts (IRS limits, API behavior, legal thresholds, library versions) against current reality via WebSearch. Read provenance log from `.workflows/plan-research/<plan-stem>/provenance.md` first — skip recently-verified values (within expiry window). Write verified results back to provenance log with YAML format: value, label, source URL, source_type (primary/secondary), verified_date, confidence (high/medium/low), plan_locations, expiry_date. Use conservative source policy by default (only .gov, official API docs, primary sources). If WebSearch is unavailable, report all unverified values as "unverified (WebSearch unavailable)" — never mark unverified values as "verified." Add `format_version: 1` to provenance log.

**Note on external-verification dual-write:** The external-verification check writes to TWO files: (1) its findings report (standard output path) and (2) the provenance log (`.workflows/plan-research/<plan-stem>/provenance.md`). This is a special case — all other checks write to a single output file. Document this dual-write pattern in the check module's instructions.

**Read for patterns:** Same as Step 1.

---

### Step 3: Create plan-readiness-reviewer agent

**File to create:**
- [ ] `plugins/compound-workflows/agents/workflow/plan-readiness-reviewer.md`

**Frontmatter:**

```yaml
---
name: plan-readiness-reviewer
description: "Dispatches plan readiness checks in parallel and aggregates findings into a work-readiness report"
model: inherit
---
```

**Architecture:** This agent IS an orchestrator — it discovers check modules, dispatches each as a parallel background agent, collects results from disk, deduplicates overlapping findings, and writes an aggregated report. This is a dispatch-within-dispatch pattern (the command dispatches the reviewer, the reviewer dispatches checks).

**Implementation note:** Agents dispatched via Task CAN themselves use Task with `run_in_background: true` to dispatch sub-agents. This nested dispatch pattern is architecturally sound — the reviewer is a foreground Task that spawns background Tasks for each check module.

**Agent instructions must cover:**

1. **Input parameters** (passed via prompt): plan file path, plan stem, output directory path, mode (`full` or `verify-only`), configuration (skip_checks list, provenance settings).

2. **Pre-flight check:** Read the plan. Count substantive lines (non-frontmatter, non-blank). If fewer than 20 substantive lines, skip all checks and report: "Plan too short for readiness analysis (N lines)." Create output directory: `mkdir -p .workflows/plan-research/<plan-stem>/readiness/checks/`.

3. **Config handling:** Read `./compound-workflows.md` (project root) for `plan_readiness_*` keys under the `## Plan Readiness` heading. If section is absent, use defaults (all checks enabled, 30-day expiry, conservative source policy). If file doesn't exist, use defaults and log "No compound-workflows.md found; using default configuration." Do NOT write config — only `/compound:setup` writes config. Validate skip_checks entries against discovered check names — warn on mismatches.

4. **Check module discovery:** Scan `agents/workflow/plan-checks/` for `.md` files (same filesystem scan pattern as deepen-plan Phase 2c). Read each file's YAML frontmatter for `name`, `type`, `description`, `verify_only`. Filter by: (a) not in skip_checks, (b) if mode is `verify-only`, only include checks where `verify_only: true` OR `type: mechanical`.

5. **Dispatch:** Launch all enabled checks in parallel using `run_in_background: true`. Each check agent receives: the plan file path (to read directly), the output path (`.workflows/plan-research/<plan-stem>/readiness/checks/<check-name>.md`), and any check-specific config (provenance settings for external-verification). Use disk-write pattern with mandatory output instructions.

6. **Collection:** Monitor completion via file existence. 3-minute timeout per check. Timed-out or crashed checks reported as "incomplete (timeout or failure)."

7. **Deduplication:** After collecting all check outputs, deduplicate findings: (a) group by plan location (section name or line range), (b) when multiple findings reference the same location and same values, merge into one finding with the highest severity and note which checks flagged it, (c) when findings reference the same location but different aspects, keep separate.

8. **Aggregation:** Write aggregated report to `.workflows/plan-research/<plan-stem>/readiness/report.md`. Include: plan file byte count (`wc -c` output, used by consolidator to detect if plan was modified between phases), overall severity summary, deduplicated findings in structured markdown (same output template as individual checks), incomplete checks list. When dispatched from deepen-plan, use run-numbered path: `.workflows/plan-research/<plan-stem>/readiness/run-<N>/report.md`.

9. **Write authority:** ZERO plan-file write authority. Metadata writes only (report, provenance log updates via external-verification check).

10. **Return:** 2-3 sentence summary to parent with issue count and severity breakdown.

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

2. **Plan integrity check:** Read the reviewer report's plan file byte count (from `wc -c`). Run `wc -c` on the plan file and compare. If mismatch: warn "Plan was modified after readiness review. Findings may be stale." and proceed with caution.

3. **Read full context:** Read the entire plan file and the full reviewer report. The consolidator operates on the full plan in a single pass — no section-by-section parsing or reassembly. This keeps the implementation simple while the pass-through and preservation rules (below) constrain what gets modified.

4. **Apply auto-fixes** (evidence-based, no user input):
   - Fix broken cross-references (target exists or doesn't — deterministic)
   - Strip superseded "Run N" annotations that conflict with current spec text
   - Deduplicate stale values ONLY when evidence is unambiguous (provenance log confirms value, or constants section defines canonical value)
   - Log each auto-fix to the consolidation report as it is applied (incremental writing protects against interruption)

5. **Pass-through rule:** Do NOT modify any content that has no associated findings from the reviewer. Write authority extends only to content with documented findings, and only to the specific issues described. Do not edit, reformat, or "improve" untouched content.

6. **Preservation rule:** NEVER strip text recording user decisions and reasoning. Patterns: "Rationale:", "Decision:", "Rejected because:", "User noted:", "Chose X over Y because". These are only reorganized (e.g., moved from an annotation block to the spec section), never deleted.

7. **Mechanical authority verification:** After writing the updated plan, run a verification pass:
   - Grep for all preservation-pattern lines in the original plan and verify every instance exists in the updated plan
   - If any preservation-pattern lines are missing, flag as a warning and restore them
   This is a deterministic check the consolidator runs on its own output.

8. **Batch user decisions:** Present all guardrailed items (ambiguous values, design disputes, spec gaps) as a batch via AskUserQuestion. Apply severity-based triage: CRITICAL individually, SERIOUS individually, MINOR as batch-accept option. Record user's reasoning for each decision.

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

Dispatch the plan-readiness-reviewer to verify the plan is work-ready.

**Dispatch:**

The reviewer is a foreground agent that internally dispatches check modules in parallel. Pass it:
- Plan file path
- Plan stem (derived from filename)
- Mode: `full` (first run after plan creation)
- Config: read from compound-workflows.md plan_readiness section

Show the reviewer's summary to the user: "Plan readiness check: [summary]"

**If issues found:**

1. Dispatch plan-consolidator (foreground). Pass: plan file path, reviewer report path.
2. Consolidator applies auto-fixes, then presents guardrailed items to user.
3. After consolidation, dispatch reviewer again in `verify-only` mode.
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

After all synthesis and red team edits are applied, verify the plan is work-ready.

**Dispatch:**

Set manifest status to `readiness_checking`.

The reviewer is a foreground agent that internally dispatches check modules in parallel. Pass it:
- Plan file path
- Plan stem
- Mode: `full`
- Config: read from compound-workflows.md plan_readiness keys
- Output directory: `.workflows/plan-research/<plan-stem>/readiness/run-<N>/`

Show the reviewer's summary to the user: "Plan readiness check: [summary]"

**If issues found:**

1. Dispatch plan-consolidator (foreground). Pass: plan file path, reviewer report path.
2. Consolidator applies auto-fixes, then presents guardrailed items to user.
3. After consolidation, dispatch reviewer again in `verify-only` mode.
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
   - If manifest status is `readiness_checking`: check if readiness output files exist; if report.md exists, skip to consolidator dispatch; otherwise re-run reviewer
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
- [ ] `plugins/compound-workflows/CLAUDE.md` — Update agent count (22 → 24), workflow agent count (3 → 5), add both agents to Agent Registry table, add `plan-checks/` to directory structure, document plan_readiness config keys, update config reads for plan.md and deepen-plan.md
- [ ] `plugins/compound-workflows/README.md` — Update component counts (22→24 agents in description and tables), add new agents to agent table
- [ ] `plugins/compound-workflows/CHANGELOG.md` — Add v1.7.0 section with: "### Added" listing plan-readiness-reviewer, plan-consolidator, 8 check modules, plan_readiness config, Phase 6.7 in plan.md, Phase 5.5 in deepen-plan.md
- [ ] `plugins/compound-workflows/.claude-plugin/plugin.json` — Bump version to 1.7.0 (MINOR: new agents). Update `description` field agent count (22→24)
- [ ] `.claude-plugin/marketplace.json` — Bump version to 1.7.0, update `ref` field to `v1.7.0`
- [ ] `plugins/compound-workflows/skills/disk-persist-agents/SKILL.md` — Add `readiness/` directory to the directory convention diagram
- [ ] `AGENTS.md` — Update agent count, add QA patterns for new files

**Agent Registry entries to add:**

| Agent | Category | Dispatched By | Model |
|-------|----------|---------------|-------|
| plan-readiness-reviewer | workflow | plan, deepen-plan | inherit |
| plan-consolidator | workflow | plan, deepen-plan | inherit |

**Directory structure update for CLAUDE.md:**

```
agents/
├── research/     # Research and knowledge agents (6)
├── review/       # Code review agents (13)
└── workflow/     # Workflow utility agents (5)
    └── plan-checks/  # Check modules for plan-readiness-reviewer (8)
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
- [ ] Each check module has correct frontmatter (name, type, description, verify_only)
- [ ] Reviewer agent correctly references check module discovery path
- [ ] Consolidator agent has preservation rule and pass-through rule
- [ ] plan.md Phase 6.7 is correctly placed between 6.5 and 7
- [ ] deepen-plan.md Phase 5.5 is correctly placed and manifest statuses added
- [ ] setup.md writes plan_readiness config with correct defaults
- [ ] All counts match across CLAUDE.md, README.md, AGENTS.md
- [ ] Version is consistent across plugin.json and marketplace.json

## Key Design Decisions

All decisions trace to the brainstorm (see brainstorm: `docs/brainstorms/2026-03-08-plan-readiness-agents-brainstorm.md`):

1. **Two agents, not one** — guardrail boundary (reviewer: zero write authority; consolidator: constrained write authority) is the primary justification (brainstorm decision #1)
2. **Both in agents/workflow/** — prevents auto-discovery during deepen-plan Phase 3 (brainstorm decision #2)
3. **Mechanical vs semantic checks** — deterministic scripts for pattern-matching, LLMs for judgment (brainstorm decision #9)
4. **Evidence-based auto-fix only** — auto-fix only when provenance makes correct value unambiguous; ambiguous cases route to user (brainstorm decision #4, red team C1)
5. **Preservation rule** — user decision rationale is never stripped, only reorganized (brainstorm decision #11, red team C2)
6. **Capped re-verification (max 1 cycle)** — reviewer → consolidator → verify-only → present remaining to user. No second consolidation. Simplified from brainstorm's 2-cycle cap based on deepen-plan review: 1 cycle captures 90% of value at lower integration complexity (brainstorm decision #10, deepen-plan run 1 S3)
7. **Consolidator reads full plan, no section parsing** — the consolidator reads the full plan + report in a single pass, applies fixes, and writes the result. Pass-through and preservation rules constrain what gets modified. Section-by-section parsing/reassembly was dropped because it doesn't actually reduce context within a single agent invocation (deepen-plan run 1 S2). The pass-through and preservation rules (from brainstorm decision #14) are retained as the essential guardrails.
8. **Dynamic dispatch with check modules** — reduces main context usage, immediately configurable and extensible (brainstorm decision #7)
9. **Constants-as-data pattern** — prevents stale-value proliferation at the source (brainstorm decision #12)
10. **Structured markdown output with machine-parseable format** — designed for programmatic aggregation by the reviewer. This is a new output format distinct from the free-form output used by existing review agents. No YAML/JSON for agent communication (brainstorm decision #6, reworded per deepen-plan run 1 S10)

## Design Decisions Made During Planning

These decisions resolve specflow questions that the brainstorm left open:

11. **Pass-through and preservation rules are the authority constraints** — no section parsing/reassembly, but the pass-through rule (don't modify content without findings) and preservation rule (never strip rationale text) are mechanically verified by the consolidator after writing. Resolves specflow Q1 differently: instead of parsing sections, the consolidator reads/writes the full plan with constrained authority.

12. **Cross-section dependencies handled via full report context** — the consolidator receives the full reviewer report when processing each section, so it knows about cross-section issues. It fixes the non-canonical location (the one that disagrees with the constants section or the most-detailed specification). Resolves specflow Q2.

13. **Deferred readiness findings go to plan's Open Questions** — ensures `/compound:work` Phase 1.1 surfaces them. Only on-disk storage would mean work.md needs a new step. Resolves specflow Q4.

14. **Single consolidator dispatch, internal section iteration** — one agent reads the full plan, processes sections sequentially within its context. Preserves cross-section awareness while keeping dispatch simple. Resolves specflow Q5.

15. **Verify-only mode = checks with `verify_only: true` OR `type: mechanical`** — all 3 mechanical checks + contradictions check. Underspecification, unresolved-disputes, accretion, external-verification are excluded from verify-only. Resolves specflow Q6.

16. **Consolidator writes report incrementally** — after each section is processed, the auto-fix log is appended to the consolidation report. Protects against interruption (specflow Gap 1).

17. **Pass-through rule for untouched sections** — sections with no findings pass through unchanged. Consolidator has no authority to "improve" sections without documented findings (specflow Gap 19).

18. **Reviewer shows summary to user before consolidation** — user sees "Plan readiness check found N SERIOUS, M MINOR issues. Running consolidation..." (specflow Q7).

19. **Batch user decisions use severity-based triage** — CRITICAL and SERIOUS individually, MINOR as batch-accept option. Same pattern as deepen-plan synthesis gate (specflow Gap 20).

20. **Minimum plan size check (20 substantive lines)** — plans under 20 lines skip all checks. Saves 8 agent dispatches on trivially small plans (specflow Gap 6).

## Dependency Graph

```
Step 1 (mechanical checks) ──┐
                              ├── Step 3 (reviewer) ── Step 4 (consolidator) ──┬── Step 5 (plan.md) ── Step 6 (deepen-plan.md)
Step 2 (semantic checks) ────┘                                                 │
                                                                               │
Step 7 (setup.md) ── independent ──────────────────────────────────────────────┘

All above ──► Step 8 (registry) ──► Step 9 (QA)
```

**Sequential dependencies:**
- Step 3 depends on Steps 1+2 (references check module paths and frontmatter)
- Step 4 depends on Step 3 (reads reviewer output format to know what it receives)
- Step 6 depends on Step 5 (Phase 5.5 adapts Phase 6.7's content)

**Parallel opportunities:**
- Steps 1 + 2 are independent (different files, same directory)
- Step 7 is independent of Steps 3-6

**Work-readiness notes:**
- Steps 1 and 2 each create multiple files but all follow the same template — a subagent can create all files in one step
- Step 3 (reviewer) is the most complex single file — orchestrator logic with dispatch patterns
- Step 4 (consolidator) is complex — full-plan processing with pass-through/preservation rules and mechanical verification
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
