---
name: compound:brainstorm
description: Explore requirements and approaches through collaborative dialogue before planning
argument-hint: "[feature idea or problem to explore]"
---

# Brainstorm a Feature or Improvement

**Note: Use the current year** when dating brainstorm documents.

Brainstorming answers **WHAT** to build through collaborative dialogue. It precedes `/compound:plan` which answers **HOW**.

**Process knowledge:** Load the `brainstorming` skill for detailed techniques.

## Feature Description

<feature_description> #$ARGUMENTS </feature_description>

**If empty, ask:** "What would you like to explore?"

## Execution Flow

### Phase 0: Assess Requirements Clarity

If requirements are already clear (specific criteria, referenced patterns, defined scope):
- Suggest: "Your requirements seem detailed enough for planning. Run `/compound:plan` instead?"

### Phase 1: Understand the Idea

#### 1.1 Repository Research

Derive a short topic stem from the feature description (e.g., `claude-code-cursor-dual-tool` from "how i can port my claude code workflow to cursor"). Use lowercase, hyphens, 3-6 words max.

Run a quick repo scan and broad context search in parallel:

```bash
mkdir -p .workflows/brainstorm-research/<topic-stem>
```

```
Task repo-research-analyst (run_in_background: true): "
You are a repository research analyst specializing in codebase pattern discovery and architectural analysis. Understand existing patterns related to: <feature_description>
Focus on: similar features, established patterns, CLAUDE.md guidance.

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write findings to: .workflows/brainstorm-research/<topic-stem>/repo-research.md
Return ONLY a 2-3 sentence summary.
"

Task context-researcher (run_in_background: true): "
You are a context researcher specializing in synthesizing project knowledge across documentation, solutions, brainstorms, plans, and institutional memory. Search ALL project knowledge for context related to: <feature_description>
Search locations: docs/solutions/, docs/brainstorms/, docs/plans/, memory/, Resources/
Tag each result by source type ([SOLUTION], [BRAINSTORM], [PLAN], [MEMORY], [RESOURCE]) and validation status.
Flag staleness risks for older documents. Note cross-references between documents.
Highlight any prior brainstorms on the same or adjacent topics — these are especially relevant.

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write findings to: .workflows/brainstorm-research/<topic-stem>/context-research.md
Return ONLY a 2-3 sentence summary.
"
```

#### 1.2 Collaborative Dialogue

Use **AskUserQuestion** to ask questions one at a time:
- Start broad (purpose, users) then narrow (constraints, edge cases)
- Validate assumptions explicitly
- Exit when idea is clear OR user says "proceed"

Read research files when ready:
- `.workflows/brainstorm-research/<topic-stem>/repo-research.md`
- `.workflows/brainstorm-research/<topic-stem>/context-research.md`

**Source trust hierarchy:** Solutions (validated) > Memory (reference) > Plans (actionable) > Resources (reference, check staleness) > Brainstorms (exploratory, check if superseded)

### Phase 2: Explore Approaches

Propose 2-3 concrete approaches. For each: brief description, pros/cons, when best suited.
Lead with recommendation. Apply YAGNI.

Use **AskUserQuestion** for user preference.

### Phase 3: Capture the Design

Write to `docs/brainstorms/YYYY-MM-DD-<topic>-brainstorm.md`.

Sections: What We're Building, Why This Approach, Key Decisions, Open Questions.

#### Phase 3 Gate: Resolve Open Questions

Before proceeding, check the Open Questions section of the brainstorm document. For each open question, present to the user via **AskUserQuestion**:

"[Open question]. How should we resolve this?"
- **Answer now** — resolve it and move the question + answer to a "Resolved Questions" section
- **Defer with rationale** — move to a "Deferred Questions" section with the reason it can't be resolved yet
- **Remove** — question is no longer relevant, delete it

**Do not proceed to Phase 3.5 with unresolved Open Questions.** Every question must be explicitly resolved, deferred, or removed.

**Do NOT delete research outputs.** The research directory at `.workflows/brainstorm-research/<topic-stem>/` is retained for traceability and learning. Future sessions can reference the research that informed this brainstorm.

### Phase 3.5: Red Team Challenge

After capturing the design, challenge it with three different model providers in parallel. Different training data produces genuinely different blind spots — using three providers maximizes coverage of assumptions Claude wouldn't question.

**Ask the user:**
"Run a red team challenge on this brainstorm? Three different AI models will try to poke holes in the reasoning. (~2-3 min)"

**If the user declines**, skip to Phase 4.

#### Step 1: Launch Red Team via 3 Providers (parallel)

Red team the brainstorm with ALL THREE model providers for maximum coverage:

**Provider 1 — Gemini (via PAL):**
```
mcp__pal__chat:
  model: [latest highest-end Gemini model, e.g. gemini-3.1-pro-preview — NOT gemini-2.5-pro]
  prompt: "You are a red team reviewer. Your job is to find flaws, not validate.

Read this brainstorm document and identify:
1. **Unexamined assumptions** — What is taken for granted that might be wrong?
2. **Missing alternatives** — What approaches were dismissed too quickly or not considered?
3. **Weak arguments** — Where is the reasoning thin or based on hope rather than evidence?
4. **Hidden risks** — What could go wrong that isn't acknowledged?
5. **Contradictions** — Does the document contradict itself anywhere?

Be specific. Quote the section you're challenging. For each challenge, rate severity:
- CRITICAL — Blocks the approach or invalidates a key conclusion
- SERIOUS — Should address before this becomes a plan
- MINOR — Worth noting but not blocking

Brainstorm document:"
  absolute_file_paths: ["<brainstorm-file-path>"]
```
Write response to: `.workflows/brainstorm-research/<topic-stem>/red-team--gemini.md`

**Provider 2 — OpenAI (via PAL):**

Run after Gemini completes so it can read the prior critique and avoid duplication:

```
mcp__pal__chat:
  model: [latest highest-end OpenAI model, e.g. gpt-5.4-pro — NOT gpt-5.4 or gpt-5.2-pro]
  prompt: "You are a red team reviewer. Your job is to find flaws, not validate.

IMPORTANT: A Gemini model has already reviewed this brainstorm. Read their critique first to avoid duplicating findings. Focus on what they MISSED.

Prior critique: .workflows/brainstorm-research/<topic-stem>/red-team--gemini.md

Read this brainstorm document and identify:
1. **Unexamined assumptions** — What is taken for granted that might be wrong?
2. **Missing alternatives** — What approaches were dismissed too quickly or not considered?
3. **Weak arguments** — Where is the reasoning thin or based on hope rather than evidence?
4. **Hidden risks** — What could go wrong that isn't acknowledged?
5. **Contradictions** — Does the document contradict itself anywhere?

Be specific. Quote the section you're challenging. For each challenge, rate severity:
- CRITICAL — Blocks the approach or invalidates a key conclusion
- SERIOUS — Should address before this becomes a plan
- MINOR — Worth noting but not blocking

Brainstorm document:"
  absolute_file_paths: ["<brainstorm-file-path>"]
```
Write response to: `.workflows/brainstorm-research/<topic-stem>/red-team--openai.md`

**Provider 3 — Claude Opus (via Task subagent, NOT PAL):**

Run in parallel with OpenAI (after Gemini completes). Do NOT use PAL for Claude — use a Task subagent instead (direct file access, no token relay overhead):

```
Task general-purpose (run_in_background: true): "
You are a red team reviewer. Your job is to find flaws, not validate.

IMPORTANT: Other models have already reviewed this brainstorm. Read their critiques to avoid duplicating findings. Focus on what they MISSED.

Prior critiques:
- .workflows/brainstorm-research/<topic-stem>/red-team--gemini.md
- .workflows/brainstorm-research/<topic-stem>/red-team--openai.md

Read the brainstorm document at <brainstorm-file-path> and identify:
1. **Unexamined assumptions** — What is taken for granted that might be wrong?
2. **Missing alternatives** — What approaches were dismissed too quickly or not considered?
3. **Weak arguments** — Where is the reasoning thin or based on hope rather than evidence?
4. **Hidden risks** — What could go wrong that isn't acknowledged?
5. **Contradictions** — Does the document contradict itself anywhere?

Be specific. Quote the section you're challenging. For each challenge, rate severity:
- CRITICAL — Blocks the approach or invalidates a key conclusion
- SERIOUS — Should address before this becomes a plan
- MINOR — Worth noting but not blocking

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write your COMPLETE findings to: .workflows/brainstorm-research/<topic-stem>/red-team--opus.md
After writing the file, return ONLY a 2-3 sentence summary.
"
```

**Execution order:** Launch Gemini first. Once Gemini completes, launch OpenAI and Claude Opus in parallel (both can read Gemini's critique; Opus can also read OpenAI's if it finishes first).

**If PAL MCP is not available:** Run only the Claude Opus Task subagent (Provider 3 above). The red team will have a single perspective instead of three, but this is an acceptable fallback.

#### Step 2: Surface CRITICAL and SERIOUS Items

Read all three red team critiques (or whichever completed). Deduplicate findings across providers — if multiple models flag the same issue, note it once with the strongest severity rating.

For each CRITICAL or SERIOUS item, present to the user via **AskUserQuestion**:

"[Red team challenge summary — note which provider(s) flagged it]. How should we handle this?"
- **Valid — update the brainstorm** (edit the doc to address it)
- **Disagree — note why** (add a "Considered and Rejected" note with the counterargument)
- **Defer — add to Open Questions** (move to Open Questions section with the red team's concern)

Apply the user's decision to the brainstorm document.

**Any CRITICAL items the user defers MUST be flagged in the Phase 4 handoff.** The plan skill needs to know about unresolved challenges.

#### Step 3: Surface MINOR Findings

After all CRITICAL and SERIOUS items are resolved, check for MINOR findings across all three red team critiques.

If MINOR findings exist, present them as a batch:

**AskUserQuestion:** "N MINOR findings remain from red team review. Review individually, or batch-accept as acknowledged?"

- **Batch-accept**: Note all as "acknowledged" in the resolution summary. No plan changes needed.
- **Review individually**: Present each MINOR finding via AskUserQuestion with the same options as CRITICAL/SERIOUS items.

### Phase 4: Handoff

**If any items were deferred (from Open Questions gate or red team challenge):**
Flag them explicitly: "Note: N deferred items remain — see Deferred Questions and Open Questions in the brainstorm doc. The plan must account for these."

Options:
1. **Review and refine** — Load `document-review` skill
2. **Proceed to planning** — `/compound:plan`
3. **Ask more questions** — Continue exploring before moving on
4. **Compound this brainstorm** — If the brainstorm surfaced surprising findings, novel frameworks, or reusable research, run `/compound:compound` to capture it
5. **Record a decision** — If the brainstorm's primary output is a choice between alternatives (not a design to implement), capture it as a decision record in `docs/decisions/YYYY-MM-DD-<topic>.md`. Scope is broad: technical, strategic, pricing, workflow, tooling, organizational. Include: context, decision, alternatives considered with pros/cons, tradeoffs accepted, and `revisit_trigger` in frontmatter. Different from compound (validated findings) — decisions document deliberate choices.
6. **Done for now** — Return later

**If user selects "Ask more questions":** Return to Phase 1.2 (Collaborative Dialogue) and continue asking questions one at a time to further refine the design. Probe deeper — edge cases, constraints, preferences, areas not yet explored. Continue until the user is satisfied, then return to Phase 4.

## Guidelines

- Stay focused on WHAT, not HOW
- Ask one question at a time
- Apply YAGNI — prefer simpler approaches
- Keep outputs concise (200-300 words per section max)
- **No unresolved items cross phase boundaries** — every open question, concern, or finding must be explicitly resolved, deferred with rationale, or removed before moving to the next phase
- NEVER CODE! Just explore and document decisions.
