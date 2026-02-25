---
name: compound-workflows:plan
description: Transform feature descriptions into plans with context-safe research agents
argument-hint: "[feature description, bug report, or improvement idea]"
---

# Create a Plan — Context-Safe Edition

**Note: Use the current year** when dating plans and searching for recent documentation.

Transform feature descriptions into well-structured plan files. Research agents persist outputs to disk to avoid context exhaustion.

**All research outputs are retained for traceability and learning.** Research is namespaced by plan stem. Prior research is NEVER deleted.

## Feature Description

<feature_description> #$ARGUMENTS </feature_description>

**If the feature description above is empty, ask the user:** "What would you like to plan? Please describe the feature, bug fix, or improvement you have in mind."

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
- Continue until clear OR user says "proceed"

**Gather research signals:** Note user familiarity, topic risk, uncertainty level.

## Main Tasks

### 1. Local Research (Parallel, Disk-Persisted)

Derive a plan stem from the feature description (e.g., `intellect-v6-pricing` or `cash-manager-reporting`).

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
- **Resolve now** — make a decision and document it
- **Defer with rationale** — carry into the plan's Open Questions section with context
- **Not relevant** — discard

**Do not proceed to planning with unresolved research contradictions.** Every finding must be explicitly addressed.

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

Use task lists (`- [ ]`) for trackable items that can be checked off during `/compound-workflows:work`.

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
- **Resolve now** — answer it and remove from Open Questions
- **Defer with rationale** — keep in Open Questions with explicit rationale; flag at handoff
- **Remove** — no longer relevant

**Do not hand off a plan with unresolved Open Questions** unless the user explicitly defers them.

### 7. Post-Generation Options

**If any items were deferred (from research gate, brainstorm cross-check, or Open Questions gate):**
Flag them explicitly: "Note: N deferred items remain in the plan's Open Questions section. `/compound-workflows:work` will verify these before execution."

Use **AskUserQuestion tool**:

**Question:** "Plan ready at `[plan_path]`. What would you like to do next?"

**Options:**
1. **Run `/compound-workflows:deepen-plan`** — Enhance with parallel research agents
2. **Review and refine** — Improve through structured self-review
3. **Start `/compound-workflows:work`** — Begin implementing this plan
4. **Create Issue** — Create issue in project tracker (GitHub/Linear)

## Key Principles

- **No unresolved items cross phase boundaries** — every open question, contradiction, or finding must be explicitly resolved, deferred with rationale, or removed before moving to the next phase
- **The brainstorm is the origin document** — if a brainstorm exists, the plan must trace back to it via `origin:` frontmatter and carry forward all decisions
- **Research informs, gates enforce** — research agents surface findings, but gates ensure nothing slips through unaddressed

NEVER CODE! Just research and write the plan.
