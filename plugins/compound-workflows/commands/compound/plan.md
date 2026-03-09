---
name: compound:plan
description: Transform feature descriptions into implementation plans
argument-hint: "[feature description, bug report, or improvement idea]"
---

# Create a Plan — Context-Lean Edition

**Note: Use the current year** when dating plans and searching for recent documentation.

Transform feature descriptions into well-structured plan files. Research agents persist outputs to disk to avoid context exhaustion.

**All research outputs are retained for traceability and learning.** Research is namespaced by plan stem. Prior research is NEVER deleted.

## Feature Description

<feature_description> #$ARGUMENTS </feature_description>

**If the feature description above is empty**, use **AskUserQuestion**: "What would you like to plan? Please describe the feature, bug fix, or improvement you have in mind."

Do not proceed until you have a clear feature description from the user.

### 0. Idea Refinement

**Check for brainstorm output first:**

```bash
ls -la docs/brainstorms/*.md 2>/dev/null | head -10
```

**Relevance criteria:** A brainstorm is relevant if the topic (from filename or YAML frontmatter) semantically matches the feature description and was created within the last 14 days.

**If multiple brainstorms could match:**
Use **AskUserQuestion** to ask which brainstorm to use, or whether to proceed without one.

**If a relevant brainstorm exists:**
1. Read the brainstorm document **thoroughly** — every section matters
2. Announce: "Found brainstorm from [date]: [topic]. Using as foundation for planning."
3. Extract and carry forward **ALL** of the following into the plan:
   - Key decisions and their rationale
   - Chosen approach and why alternatives were rejected
   - Constraints and requirements discovered during brainstorming
   - Open/deferred questions (flag these for resolution during planning)
   - Success criteria and scope boundaries
   - Any specific technical choices or patterns discussed
4. **Skip the idea refinement questions below** — the brainstorm already answered WHAT to build
5. Use brainstorm content as the **primary input** to research and planning phases
6. **The brainstorm is the origin document.** Throughout the plan, reference specific decisions with `(see brainstorm: docs/brainstorms/<filename>)`. Do not paraphrase decisions in a way that loses their original context — link back to the source.

**If no brainstorm found, run idea refinement:**

Use **AskUserQuestion tool** to ask questions one at a time:
- Purpose, constraints, success criteria
- **Record the user's reasoning, not just their answer.** When the user explains *why* they want something or *why* they chose one approach over another, capture that rationale in the plan. The "why" prevents future sessions from relitigating settled decisions.
- Continue until clear OR user says "proceed"

**Gather research signals:** Note user familiarity, topic risk, uncertainty level.

## Main Tasks

### 1. Local Research (Parallel, Disk-Persisted)

Derive a plan stem from the feature description (e.g., `api-rate-limiting` or `user-dashboard-reporting`).

Create a working directory namespaced to this plan:

```bash
mkdir -p .workflows/plan-research/<plan-stem>/agents
```

Launch research agents with **disk-write pattern**:

```
Task repo-research-analyst (run_in_background: true): "
You are a repository research analyst specializing in codebase pattern discovery.

Research existing patterns related to: <feature_description>
Focus on: similar features, established patterns, CLAUDE.md guidance.
Read the codebase, not just file names.

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write your COMPLETE findings to: .workflows/plan-research/<plan-stem>/agents/repo-research.md
After writing the file, return ONLY a 2-3 sentence summary.
"

Task learnings-researcher (run_in_background: true): "
You are an institutional knowledge researcher. Search docs/solutions/ for relevant past solutions.

Search docs/solutions/ for relevant past solutions for: <feature_description>
Check tags, categories, and modules for overlap.

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write your COMPLETE findings to: .workflows/plan-research/<plan-stem>/agents/learnings.md
After writing the file, return ONLY a 2-3 sentence summary.
"
```

**DO NOT call TaskOutput to retrieve full results.** Monitor completion by checking file existence:

```bash
ls .workflows/plan-research/<plan-stem>/agents/
```

### 1.5. Research Decision

Based on signals from Step 0 and local research files:

- **High-risk topics** (security, payments, external APIs) → always do external research
- **Strong local context** → skip external research
- **Uncertainty** → research

### 1.5b. External Research (Conditional, Disk-Persisted)

If external research is needed:

```
Task best-practices-researcher (run_in_background: true): "
You are a best practices researcher specializing in external documentation and community standards.

Research best practices for: <feature_description>

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write your COMPLETE findings to: .workflows/plan-research/<plan-stem>/agents/best-practices.md
After writing the file, return ONLY a 2-3 sentence summary.
"

Task framework-docs-researcher (run_in_background: true): "
You are a framework documentation researcher specializing in official docs and version-specific constraints.

Research framework documentation for: <feature_description>

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write your COMPLETE findings to: .workflows/plan-research/<plan-stem>/agents/framework-docs.md
After writing the file, return ONLY a 2-3 sentence summary.
"
```

### 1.6. Consolidate Research

**Read the research output files from disk** (not from conversation context):

```bash
ls .workflows/plan-research/<plan-stem>/agents/
# Then use Read tool on each file
```

Consolidate:
- Relevant file paths from repo research
- Institutional learnings from docs/solutions/
- External documentation URLs and best practices
- CLAUDE.md conventions

#### Research Gate: Resolve Unknowns

If research surfaced contradictions, unknowns, or open questions:

For each, present to the user via **AskUserQuestion**:

"Research found: [contradiction or unknown]. How should we handle this?"
- **Resolve now** — make a decision and document it, including the user's reasoning
- **Defer with rationale** — carry into the plan's Open Questions section with the user's stated reason for deferral
- **Not relevant** — discard

**Do not proceed to planning with unresolved research contradictions.** Every finding must be explicitly addressed. When recording resolutions, capture *why* the user chose that path — not just the choice itself.

### 2. Issue Planning & Structure

**Title & Categorization:**
- Draft clear title using conventional format (e.g., `feat: Add user authentication`)
- Convert to filename: `YYYY-MM-DD-<type>-<descriptive-name>-plan.md`

**Content Planning:**
- Choose detail level: MINIMAL / MORE / A LOT (see templates below)
- List all sections needed

### 3. SpecFlow Analysis (Disk-Persisted)

```
Task spec-flow-analyzer (run_in_background: true): "
You are a specification flow analyst specializing in completeness, edge cases, and user flow gaps.

Analyze this feature specification for completeness, edge cases, and user flow gaps:

Feature: <feature_description>

Read the research findings from: .workflows/plan-research/<plan-stem>/agents/
Use them to inform your analysis.

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write your COMPLETE analysis to: .workflows/plan-research/<plan-stem>/agents/specflow.md
After writing the file, return ONLY a 2-3 sentence summary.
"
```

Read the specflow output file. Incorporate gaps and edge cases into the plan.

### 4. Choose Detail Level

#### MINIMAL (Quick Issue)
Problem statement, acceptance criteria, essential context.

#### MORE (Standard Issue)
Everything from MINIMAL plus: background, technical considerations, success metrics, dependencies.

#### A LOT (Comprehensive Issue)
Everything from MORE plus: implementation phases, alternatives considered, risk analysis, resource requirements.

### 5. Write the Plan

Write to: `docs/plans/YYYY-MM-DD-<type>-<descriptive-name>-plan.md`

Include YAML frontmatter:

```yaml
---
title: [Plan Title]
type: [feat|fix|refactor]
status: active
date: YYYY-MM-DD
origin: docs/brainstorms/YYYY-MM-DD-<topic>-brainstorm.md  # if originated from brainstorm, otherwise omit
---
```

Include a **Sources** section at the end of the plan:
- **Origin brainstorm:** `docs/brainstorms/<filename>` — if the plan originated from a brainstorm, link it and summarize 2-3 key decisions carried forward
- Research files, related docs, external references

Use task lists (`- [ ]`) for trackable items that can be checked off during `/compound:work`.

### 6. Retain Research

**Do NOT delete research outputs.** The research directory at `.workflows/plan-research/<plan-stem>/` is retained for traceability and learning. Future sessions, deepen-plan runs, and work execution can reference the original research that informed the plan.

### 6.5. Pre-Handoff Gates

#### Brainstorm Cross-Check (if plan originated from a brainstorm)

Re-read the brainstorm document and verify:
- [ ] Every key decision from the brainstorm is reflected in the plan
- [ ] The chosen approach matches what was decided in the brainstorm
- [ ] Constraints and requirements are captured in acceptance criteria
- [ ] Open/deferred questions from the brainstorm are either resolved or flagged
- [ ] The `origin:` frontmatter field points to the brainstorm file
- [ ] The Sources section includes the brainstorm with carried-forward decisions

If anything was dropped, add it to the plan before proceeding.

#### Plan Open Questions Gate

If the plan has an Open Questions section, resolve each item via **AskUserQuestion**:
- **Resolve now** — answer it with the user's reasoning and remove from Open Questions
- **Defer with rationale** — keep in Open Questions with the user's explicit rationale; flag at handoff
- **Remove** — no longer relevant

**The goal is zero untriaged items at handoff.** Every question must be explicitly resolved, deferred by the user, or removed. Nothing should remain open by accident — if it's in the plan, the user has seen it and made a call. Deferred items are fine when the user consciously chooses to defer, but flag them clearly so `/compound:work` knows what's unresolved.

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
5. **Track deferred finding severities** for Phase 7 recommendation: when the user defers a finding, note its severity level (CRITICAL, SERIOUS, MINOR). Carry these deferred severity counts forward to Phase 7 alongside the final reviewer summary.
6. Show user: "Readiness check complete. N auto-fixes applied, M items resolved, K deferred."

**If zero issues found:**

Skip consolidator and re-verify. Show: "Plan readiness check: no issues found."

**If reviewer fails:**

Warn: "Readiness check failed — consider running /compound:deepen-plan before starting work."
Proceed to Phase 7.

### 7. Post-Generation Options

**If any items were deferred:**
Flag them explicitly: "Note: N deferred items remain in the plan. `/compound:work` will surface these before execution — the orchestrator may need to pause and ask you to resolve them."

**Work readiness note:** Before presenting options, assess whether the plan's steps are well-sized for `/compound:work` (subagent dispatch). Flag if:
- Any step has 20+ checkboxes or heavy inline specs — suggest splitting during work setup
- Steps share large reference data — note that the orchestrator should point subagents to the file path, not inline the data
- Steps can run in parallel (touch separate files with no dependencies) — note the opportunity

#### Recommendation Computation

Compute the recommended next step by evaluating the following decision tree **in order** (first match wins). Use data from Phase 6.7: the reviewer's severity summary (in context from foreground dispatch), deferred finding severities (tracked per step 5 above), and post-verify severity counts (if verify ran).

**Additional data to gather at Phase 7 time:**

1. **Brainstorm existence:** Read the plan file's YAML frontmatter. If `origin:` exists and points to a `docs/brainstorms/*.md` file, a brainstorm exists. Otherwise, no brainstorm preceded this plan.
2. **Step count:** Count the top-level numbered sections in the plan's implementation section (the items that become `/compound:work` execution units — the same ones assessed in the work readiness note above).

**Decision tree (evaluate in order, first match wins):**

1. **Reviewer failed or was skipped** → Recommend: deepen-plan
   - Message: "Readiness check incomplete — deepen-plan recommended to verify plan quality."

2. **Any CRITICAL finding remains (active or deferred)** → Recommend: deepen-plan
   - Message: "N CRITICAL findings remain (check-categories). Deepen-plan recommended."
   - Example: "2 CRITICAL findings remain (underspecification, contradictions). Deepen-plan recommended."

3. **Any SERIOUS finding remains (active or deferred)** → Recommend: deepen-plan
   - Message: "N SERIOUS findings remain (check-categories). Deepen-plan recommended."
   - Example: "1 SERIOUS finding remains (stale-values). Deepen-plan recommended."

4. **Consolidator resolved CRITICAL or SERIOUS findings (plan materially modified) and verify passed clean** → Recommend: deepen-plan
   - Detect by comparing: initial reviewer had CRITICAL or SERIOUS counts > 0, post-verify counts are 0 for those severities.
   - Message: "Plan was modified during readiness checks. Deepen-plan recommended to review changes."

5. **No brainstorm origin AND plan has 4+ top-level implementation steps** → Recommend: deepen-plan
   - Message: "No brainstorm preceded this plan. Deepen-plan recommended to catch unvalidated assumptions."

6. **Clean or MINOR-only findings, brainstorm exists or plan is small (< 4 steps)** → Recommend: work
   - Message: "Plan readiness checks passed — ready for work. Deepen-plan available for adversarial review if desired (~2-5 min, agent swarm + red team)."

#### Handoff

Use **AskUserQuestion tool**:

**Question:** "Plan ready at `[plan_path]`. [Recommendation message from decision tree above.] [Any work-readiness flags, e.g., 'Note: Steps 7-8 are large — the `/compound:work` orchestrator should split them into smaller issues.'] What would you like to do next?"

**Options** (annotate exactly one with `**[Recommended]**` based on the decision tree result):
1. **Run `/compound:deepen-plan`** — Enhance with parallel research agents **[Recommended]** ← if decision tree recommends deepen-plan
2. **Review and refine** — Improve through structured self-review
3. **Start `/compound:work`** — Begin implementing this plan **[Recommended]** ← if decision tree recommends work [If CRITICAL readiness findings were deferred, always append: "— Warning: unresolved CRITICAL findings"]
4. **Create Issue** — Create issue in project tracker (GitHub/Linear)

The `**[Recommended]**` annotation appears on exactly one option per run (never zero, never two). The option order is fixed — only the annotation moves.

#### Feedback Loop

After the user responds to the AskUserQuestion above, append an entry to `.workflows/plan-research/<plan-stem>/recommendation-log.md` to track recommendation accuracy for future calibration:

```markdown
## <date>
- Severity counts: N CRITICAL, N SERIOUS, N MINOR (final state)
- Deferred: N CRITICAL, N SERIOUS (if any)
- Consolidator materially modified plan: yes/no
- Brainstorm origin: yes/no
- Step count: N
- Recommendation: <option> [Recommended]
- User choice: <option selected>
```

The "Consolidator materially modified plan" field is "yes" if the consolidator resolved any CRITICAL or SERIOUS findings (material modification per decision tree rule 4), "no" otherwise.

## Key Principles

- **Zero untriaged items at handoff** — every open question, contradiction, or finding must be explicitly resolved, deferred by the user, or removed. Nothing slips through unseen. Deferred items are acceptable when the user consciously chooses to defer — but they must be flagged clearly so `/compound:work` knows what's unresolved.
- **The brainstorm is the origin document** — if a brainstorm exists, the plan must trace back to it via `origin:` frontmatter and carry forward all decisions
- **Research informs, gates enforce** — research agents surface findings, but gates ensure nothing slips through unaddressed
- **Record the why, not just the what** — when the user makes a decision, explains a preference, or rejects an alternative, capture their reasoning in the plan. User rationale evaporates with conversation context; the plan is the only durable record.

NEVER CODE! Just research and write the plan.
