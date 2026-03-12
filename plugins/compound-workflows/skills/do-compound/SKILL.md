---
name: do:compound
description: Document a solved problem to compound team knowledge
argument-hint: "[optional: brief context about the fix]"
---

# /compound — Context-Lean Edition

Capture problem solutions while context is fresh. Uses parallel subagents with disk persistence.

## Usage

```bash
/do:compound                    # Document the most recent fix
/do:compound [brief context]    # Provide additional context hint
```

## Preconditions

- Problem has been solved or finding has been validated (not in-progress speculation)
- Solution has been verified working OR analysis has been confirmed against evidence
- Non-trivial insight (not simple typo or routine task)

## Mode Detection

Assess whether this is a **code solution** or **analytical/strategic finding**:

| Signal | Code Solution | Analytical/Strategic |
|--------|--------------|---------------------|
| Artifacts | Code changes, config fixes, test results | Documents, models, research findings, decisions |
| Verification | Tests pass, bug no longer reproduces | Evidence checked against primary sources, logic validated |
| Value | "Next time this breaks, do X" | "Next time this question comes up, here's what we found" |

**If analytical/strategic:** Use the modified agent prompts and doc template described below. The same Phase 1->2->3 structure applies, but agents focus on different things.

## Execution: Two-Phase Orchestration

### Phase 1: Parallel Research (Disk-Persisted)

Derive a short topic stem from the problem or finding being compounded (e.g., `redis-cache-invalidation` or `api-versioning-strategy`). Use lowercase, hyphens, 3-6 words max.

```bash
mkdir -p .workflows/compound-research/<topic-stem>/agents
```

Launch 5 subagents in parallel with `run_in_background: true`:

**1. Context Analyzer**
```
Task general-purpose (run_in_background: true): "
You are a context analyzer specializing in problem classification and root cause identification. Analyze the conversation history. Identify problem type, component, symptoms.
Validate against schema categories: build-errors, test-failures, runtime-errors,
performance-issues, database-issues, security-issues, ui-bugs, integration-issues, logic-errors.

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write YAML frontmatter skeleton to: .workflows/compound-research/<topic-stem>/agents/context.md
Return ONLY a 2-3 sentence summary.
"
```

**2. Solution Extractor**
```
Task general-purpose (run_in_background: true): "
You are a solution extractor specializing in distilling actionable knowledge from problem-solving sessions. Extract the key solution, evidence chain, alternatives considered and why they were rejected, and the decision rationale.

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write findings to: .workflows/compound-research/<topic-stem>/agents/solution.md
Return ONLY a 2-3 sentence summary.
"
```

**3. Related Docs Finder**
```
Task general-purpose (run_in_background: true): "
You are a documentation researcher specializing in connecting new findings to existing institutional knowledge. Find related brainstorms, plans, solutions, and prior analyses. Map how this finding connects to existing knowledge.

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write findings to: .workflows/compound-research/<topic-stem>/agents/related-docs.md
Return ONLY a 2-3 sentence summary.
"
```

**4. Prevention Strategist**
```
Task general-purpose (run_in_background: true): "
You are a prevention strategist specializing in root cause analysis and recurrence prevention. Identify: How could this have been caught earlier? What systemic changes would prevent recurrence? What monitoring or tests should be added?

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write findings to: .workflows/compound-research/<topic-stem>/agents/prevention.md
Return ONLY a 2-3 sentence summary.
"
```

**5. Category Classifier**
```
Task general-purpose (run_in_background: true): "
You are a knowledge classifier specializing in taxonomizing technical findings for future retrieval. Classify the problem type and determine the best category directory for the solution document.

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write findings to: .workflows/compound-research/<topic-stem>/agents/category.md
Return ONLY a 2-3 sentence summary.
"
```

Monitor completion via file existence. DO NOT call TaskOutput.

#### Analytical/Strategic Mode — Agent Adaptations

When in analytical/strategic mode, the same 5 agents run but with adapted focus:

1. **Context Analyzer** — Identify the question/problem type, domain area, and what triggered the investigation. Categories include: competitive-intelligence, cost-modeling, organizational-dynamics, technical-evaluation, strategic-positioning, data-analysis, stakeholder-management.
2. **Solution Extractor** — Extract the key finding, the evidence chain that supports it, alternatives that were considered and why they were rejected, and the decision rationale.
3. **Related Docs Finder** — Find related brainstorms, plans, meeting transcripts, and prior analyses. Map how this finding connects to existing knowledge.
4. **Prevention Strategist** -> **Reuse Strategist** — Instead of "how to prevent recurrence," capture: When would this analysis be relevant again? What triggers should prompt re-reading this? What assumptions could invalidate the finding?
5. **Category Classifier** — Same role, broader categories (see list in #1 above).

### Phase 2: Assembly & Write

After all Phase 1 agents complete:

1. Read all files from `.workflows/compound-research/<topic-stem>/agents/`
2. Assemble complete markdown file from the pieces
3. Validate YAML frontmatter against schema. Include traceability fields:
   ```yaml
   origin_plan: docs/plans/YYYY-MM-DD-<name>-plan.md      # if traceable
   origin_brainstorm: docs/brainstorms/YYYY-MM-DD-<name>-brainstorm.md  # if traceable
   ```
   Trace the origin chain: check recent git log, beads issues, or conversation context for the plan and brainstorm that led to this solution. If not traceable, omit the fields.
4. Create directory if needed: `mkdir -p docs/solutions/[category]/`
5. Write the SINGLE final file: `docs/solutions/[category]/[filename].md`

### Phase 3: Optional Enhancement

Based on problem type, optionally run specialized review agents:

```
Task performance-oracle (run_in_background: true): "You are a performance specialist. Review the solution for performance implications, scalability concerns, and optimization opportunities.
Read the solution doc at: docs/solutions/[category]/[filename].md
=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write findings to: .workflows/compound-research/<topic-stem>/agents/perf-review.md
Return ONLY a 2-3 sentence summary."

Task security-sentinel (run_in_background: true): "You are a security reviewer. Review the solution for security implications, vulnerability exposure, and hardening opportunities.
Read the solution doc at: docs/solutions/[category]/[filename].md
=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write findings to: .workflows/compound-research/<topic-stem>/agents/security-review.md
Return ONLY a 2-3 sentence summary."

Task data-integrity-guardian (run_in_background: true): "You are a data integrity specialist. Review the solution for data consistency, migration safety, and schema implications.
Read the solution doc at: docs/solutions/[category]/[filename].md
=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write findings to: .workflows/compound-research/<topic-stem>/agents/data-review.md
Return ONLY a 2-3 sentence summary."
```

Run only the agents relevant to the problem type. Read output files and incorporate significant findings into the solution doc.

### Retain Research

**Do NOT delete research outputs.** The research directory at `.workflows/compound-research/<topic-stem>/` is retained for traceability and learning.

## What It Captures

### Code Solutions
- Problem symptom (exact error messages)
- Investigation steps tried
- Root cause analysis
- Working solution with code examples
- Prevention strategies
- Cross-references to related docs

### Analytical/Strategic Findings
- Question or problem that triggered the investigation
- Evidence chain (data, transcripts, documents, external sources)
- Key finding and why it matters
- Decision rationale — what was chosen and what was rejected
- Assumptions that could invalidate the finding
- Reuse triggers — when to re-read this (e.g., "next time pricing comes up", "before any vendor evaluation meeting")
- Stakeholder implications — who is affected and how
- Cross-references to brainstorms, plans, meeting transcripts

## Output

Single file: `docs/solutions/[category]/[filename].md`

## The Compounding Philosophy

Each documented solution compounds knowledge:
1. First occurrence: Research (30 min)
2. Document: 5 min
3. Next occurrence: Quick lookup (2 min)

**Each unit of engineering work should make subsequent units easier — not harder.**
