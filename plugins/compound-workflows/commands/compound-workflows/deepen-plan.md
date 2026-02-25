---
name: compound-workflows:deepen-plan
description: Context-safe plan enhancement with parallel research agents that persist outputs to disk
argument-hint: "[path to plan file]"
---

# Deepen Plan — Context-Safe Edition

## Introduction

**Note: Use the current year** when dating documents and searching for recent documentation.

This command enhances an existing plan with parallel research, skill, and review agents. Unlike the default version, it **persists all agent outputs to disk** to avoid context exhaustion. The parent agent stays lean as a coordinator — it never holds full agent outputs in context.

**All outputs are retained across runs for traceability and learning.** Each run gets its own numbered directory. Prior run data is NEVER deleted.

## Plan File

<plan_path> #$ARGUMENTS </plan_path>

**If the plan path above is empty:**
1. Check for recent plans: `ls -la docs/plans/`
2. Ask the user which plan to deepen. Do not proceed without a valid path.

## Phase 0: Setup Working Directory

Derive a short stem from the plan filename (e.g., `feat-cash-management-reporting-app` from `YYYY-MM-DD-feat-cash-management-reporting-app-plan.md`).

**Determine run number:**

```bash
# Check for existing runs
ls .workflows/deepen-plan/<plan-stem>/run-*-manifest.json 2>/dev/null
```

If prior runs exist, increment the run number (e.g., if `run-2-manifest.json` exists, this is run 3). If no prior runs exist, this is run 1.

**CRITICAL: NEVER delete prior run directories or files.** All agent outputs, synthesis files, and manifests from prior runs are retained for traceability and learning.

```bash
mkdir -p .workflows/deepen-plan/<plan-stem>/agents/run-<N>
```

**Check for interrupted current run:** If `.workflows/deepen-plan/<plan-stem>/manifest.json` exists AND its `status` is NOT `"synthesized"`, this may be an interrupted run. Skip to Phase 5 (Recovery).

Create `manifest.json` (the "current run" pointer):

```json
{
  "plan_path": "<full path to plan>",
  "plan_stem": "<plan-stem>",
  "origin_brainstorm": "<path from plan's origin: frontmatter, or null>",
  "started_at": "<ISO timestamp>",
  "status": "parsing",
  "run": <N>,
  "agents": []
}
```

## Phase 1: Parse Plan Structure

Read the plan file and extract:
- Overview/Problem Statement
- Proposed Solution sections
- Technical Approach/Architecture
- Implementation phases/steps
- Technologies/frameworks mentioned
- Domain areas (data models, APIs, UI, security, performance, etc.)

Create a section manifest — a numbered list of major sections that will each get dedicated research.

**Review prior run findings (if any):** If prior runs exist, read the prior synthesis files (`run-<N-1>-synthesis.md`, etc.) to understand what was already found. This helps focus the new run on areas that need fresh analysis or deeper investigation. Prior findings may inform which agents to launch, but **do not skip agents just because a prior run covered the topic** — prefer re-running to ensure findings reflect the current state of the document.

Update `manifest.json` status to `"discovered"`.

## Phase 2: Discover Available Skills, Learnings, and Agents

### Step 2a: Discover skills

```bash
ls .claude/skills/ 2>/dev/null
ls ~/.claude/skills/ 2>/dev/null
find ~/.claude/plugins/cache -type d -name "skills" 2>/dev/null
```

For each discovered skill, read its SKILL.md. Match skills to plan content by domain relevance.

### Step 2b: Discover learnings

```bash
find docs/solutions -name "*.md" -type f 2>/dev/null
```

Read frontmatter of each learning file. Filter by tag/category overlap with plan technologies.

### Step 2c: Discover review/research agents

```bash
find ~/.claude/plugins/cache -path "*/agents/*.md" 2>/dev/null
find .claude/agents -name "*.md" 2>/dev/null
find ~/.claude/agents -name "*.md" 2>/dev/null
```

For compound-engineering plugin:
- USE: `agents/review/*`, `agents/research/*`, `agents/design/*`, `agents/docs/*`
- SKIP: `agents/workflow/*`

### Step 2d: Build agent roster

For each matched skill, learning, research topic, and review agent, add an entry to `manifest.json`:

```json
{
  "name": "security-sentinel",
  "type": "review",
  "file": "agents/run-<N>/review--security-sentinel.md",
  "status": "pending"
}
```

**When in doubt about whether to include an agent, include it.** Prefer producing the best output over reducing repeated work. It is always acceptable to re-run research on topics that prior runs covered — the document may have changed, and fresh analysis catches things prior runs missed.

Update `manifest.json` status to `"agents_planned"`. Write the file to disk.

## Phase 3: Launch Agents in Batches

**CRITICAL: Context-safe agent launch pattern.**

### The Disk-Write Instruction Block

Every agent prompt MUST end with this block (fill in the actual path):

```
=== OUTPUT INSTRUCTIONS (MANDATORY) ===

Write your COMPLETE findings to this file using the Write tool:
  .workflows/deepen-plan/<plan-stem>/agents/run-<N>/<agent-file>

Include ALL analysis, code examples, recommendations, and references in that file.
Structure the file with clear markdown headers.

After writing the file, return ONLY a 2-3 sentence summary.
Example: "Found 3 security issues (1 critical). 2 performance recommendations. Full analysis at .workflows/deepen-plan/example/agents/run-3/review--security-sentinel.md"

DO NOT return your full analysis in your response. The file IS the output.
```

### Batch Size

Launch agents in batches of **10-15 at a time**. Wait for each batch to complete (check file existence) before launching the next batch.

**Batch order:**
1. **Research agents first** (Explore agents for each plan section + Context7 queries + WebSearch). These produce context that review agents benefit from.
2. **Skill agents** (one per matched skill).
3. **Learning agents** (one per filtered learning).
4. **Review agents last** (security, performance, architecture, etc.). Review agents can reference research output files in their prompts.

### Launching a Batch

For each agent in the batch, use `Task` with `run_in_background: true`:

```
Task [agent-type] (run_in_background: true): "
[Agent-specific instructions — what to review/research, the plan content or path to read]

The plan file is at: <plan_path>
Read it directly.

[For review agents in later batches, optionally:]
Research findings are available at: .workflows/deepen-plan/<plan-stem>/agents/run-<N>/research--*.md
You may read these for additional context.

[If prior runs exist, optionally:]
Prior run findings are at: .workflows/deepen-plan/<plan-stem>/agents/run-<N-1>/
You may read these for context on what was previously found.

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write your COMPLETE findings to: .workflows/deepen-plan/<plan-stem>/agents/run-<N>/<agent-file>
[...rest of instruction block...]
"
```

### Monitoring Batch Completion

After launching a batch, poll for completion by checking file existence:

```bash
ls .workflows/deepen-plan/<plan-stem>/agents/run-<N>/
```

Compare against expected files for this batch. When all files in the batch exist, the batch is complete. Move to the next batch.

**DO NOT call TaskOutput to retrieve full results.** The files on disk ARE the results.

If a background agent sends a task-notification, note the status but do not process the full result. Just check whether its output file exists.

After each batch completes, update the corresponding agent entries in `manifest.json` to `"status": "completed"`.

### Handling Slow/Failed Agents

- If an agent hasn't produced output after 3 minutes, mark it as `"status": "timeout"` in the manifest and move on.
- If a task-notification reports failure, mark `"status": "failed"` and move on.
- Do not let one slow agent block the entire workflow.

## Phase 4: Synthesis

Once all batches are complete (or timed out), launch a **single synthesis agent**:

```
Task general-purpose: "
You are synthesizing findings from multiple review and research agents into plan enhancements.

## Source Files

Read ALL agent output files from: .workflows/deepen-plan/<plan-stem>/agents/run-<N>/

List the directory first, then read each .md file.

## Original Plan

Read the plan at: <plan_path>

## Your Job

1. Read every agent output file
2. For each plan section, collect relevant findings from all agents
3. Deduplicate overlapping recommendations
4. Prioritize by impact (critical > high > medium > low)
5. Flag any contradictions between agents

## Output

Write TWO files:

### File 1: Enhanced Plan
Write to: <plan_path>
Preserve all original content. For each section that has findings, add:

### Review Findings

**Critical:**
- [finding with source agent name]

**Recommendations:**
- [recommendation with source agent name]

**Implementation Details:**
- [concrete code/config examples]

### File 2: Synthesis Summary
Write to: .workflows/deepen-plan/<plan-stem>/run-<N>-synthesis.md
Include:
- Date, run number, and agent count
- Top findings by severity
- Sections with most feedback
- Agents that found nothing relevant
- Any contradictions between agents

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
After writing both files, return a brief summary of the top 5 findings.
"
```

**After synthesis, archive the current run tracking files:**

```bash
# Copy current manifest as run-specific archive
cp .workflows/deepen-plan/<plan-stem>/manifest.json .workflows/deepen-plan/<plan-stem>/run-<N>-manifest.json
# Also copy synthesis to the standard location for easy access
cp .workflows/deepen-plan/<plan-stem>/run-<N>-synthesis.md .workflows/deepen-plan/<plan-stem>/synthesis.md
```

Update `manifest.json` status to `"synthesized"`.

### Synthesis Gate: Resolve Contradictions

If the synthesis flagged contradictions between research agents or unresolved questions:

For each, present to the user via **AskUserQuestion**:

"Synthesis found conflicting recommendations: [summary]. How should we resolve this?"
- **Choose one** — adopt the recommended approach, note the alternative was considered
- **Defer** — carry into the plan's Open Questions section
- **Needs more research** — flag for the red team to investigate specifically

**Do not proceed to red team with unresolved contradictions.** The red team should challenge a coherent plan, not arbitrate between the synthesis's own internal conflicts.

## Phase 4.5: Red Team Challenge

After synthesis, challenge the enhanced plan with a different model. The research and review agents are all Claude-based and share similar training biases — a different model catches blind spots they'd collectively miss.

### Step 1: Launch Red Team via PAL

Use PAL `chat` with a non-Claude model:

```
mcp__pal__chat:
  model: gemini-2.5-pro
  prompt: "You are a red team reviewer for a software implementation plan. Your job is to find flaws, not validate.

Read the enhanced plan and its synthesis summary. Then identify:
1. **Unexamined assumptions** — What does the plan take for granted?
2. **Architecture risks** — Where could the technical approach fail at scale or under pressure?
3. **Missing steps** — What implementation work is implied but not planned?
4. **Dependency risks** — What external factors could derail the plan?
5. **Overengineering** — Where is the plan more complex than necessary?
6. **Contradictions** — Do the research findings conflict with each other or with the plan?

Be specific. Reference plan sections by name. Rate each finding:
- CRITICAL — Plan will fail or produce wrong outcome if not addressed
- SERIOUS — Significant risk that should be addressed before implementation
- MINOR — Worth noting for awareness

Plan file and synthesis summary:"
  absolute_file_paths: [
    "<plan_path>",
    ".workflows/deepen-plan/<plan-stem>/run-<N>-synthesis.md"
  ]
```

**If PAL MCP is not available**, use a Claude subagent instead:

```
Task general-purpose (run_in_background: true): "
You are a red team reviewer for a software implementation plan. Your job is to find flaws, not validate. Approach this adversarially — assume the plan has weaknesses and find them.

Read the enhanced plan at: <plan_path>
Read the synthesis summary at: .workflows/deepen-plan/<plan-stem>/run-<N>-synthesis.md

Then identify:
1. **Unexamined assumptions** — What does the plan take for granted?
2. **Architecture risks** — Where could the technical approach fail at scale or under pressure?
3. **Missing steps** — What implementation work is implied but not planned?
4. **Dependency risks** — What external factors could derail the plan?
5. **Overengineering** — Where is the plan more complex than necessary?
6. **Contradictions** — Do the research findings conflict with each other or with the plan?

Be specific. Reference plan sections by name. Rate each finding:
- CRITICAL — Plan will fail or produce wrong outcome if not addressed
- SERIOUS — Significant risk that should be addressed before implementation
- MINOR — Worth noting for awareness

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write your COMPLETE findings to: .workflows/deepen-plan/<plan-stem>/agents/run-<N>/red-team--critique.md
After writing the file, return ONLY a 2-3 sentence summary.
"
```

Write PAL's response to: `.workflows/deepen-plan/<plan-stem>/agents/run-<N>/red-team--critique.md`

Update `manifest.json` to include the red team agent entry with `"status": "completed"`.

### Step 2: PAL Consensus on Disputed Points (Optional)

If the red team raises CRITICAL findings that directly contradict the synthesis recommendations, use PAL `consensus` to get a multi-model ruling:

```
mcp__pal__consensus:
  models: [
    { model: "gemini-2.5-pro", stance: "against", stance_prompt: "Argue why this plan recommendation is flawed" },
    { model: "gpt-5.2", stance: "for", stance_prompt: "Defend the plan's approach given the evidence" }
  ]
  step: "Evaluate: [specific disputed recommendation from the plan]. Context: [brief summary of what red team said vs. what synthesis recommended]"
  relevant_files: ["<plan_path>"]
```

**If PAL MCP is not available**, use a Claude subagent instead:

```
Task general-purpose (run_in_background: true): "
You are evaluating a disputed recommendation from a software plan. Two perspectives exist:

**The plan's synthesis recommends:** [specific disputed recommendation]
**The red team argues against it:** [brief summary of red team critique]

Your job:
1. Read the plan at: <plan_path>
2. Read the red team critique at: .workflows/deepen-plan/<plan-stem>/agents/run-<N>/red-team--critique.md
3. Evaluate BOTH sides fairly. Consider evidence strength, risk severity, and implementation practicality.
4. Deliver a ruling: adopt the plan's approach, adopt the red team's alternative, or propose a third option.
5. Explain your reasoning clearly.

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write your COMPLETE analysis to: .workflows/deepen-plan/<plan-stem>/agents/run-<N>/red-team--consensus-<topic>.md
After writing the file, return ONLY a 2-3 sentence summary.
"
```

Write consensus results to: `.workflows/deepen-plan/<plan-stem>/agents/run-<N>/red-team--consensus-<topic>.md`

**Skip this step if no CRITICAL contradictions exist.** Don't burn tokens on consensus for MINOR or SERIOUS items — the red team critique alone is sufficient for those.

### Step 3: Surface Unresolved Items

Read the red team critique (and consensus results if any). For each CRITICAL or SERIOUS item, present to the user via **AskUserQuestion**:

"[Challenge summary]. How should we handle this?"
- **Valid — update the plan** (edit the plan to address it)
- **Disagree — note why** (add a footnote with the counterargument)
- **Defer — flag for implementation** (add to a "Risks and Open Questions" section in the plan)

Apply the user's decision to the plan file.

**Any CRITICAL items the user defers MUST appear in the Phase 6 report.** The work skill needs to know about unresolved challenges before implementation begins.

## Phase 5: Recovery (Resume After Compaction)

If `.workflows/deepen-plan/<plan-stem>/manifest.json` exists when this command starts:

1. Read the manifest to get the current run number
2. Check which agent output files actually exist on disk:
   ```bash
   ls .workflows/deepen-plan/<plan-stem>/agents/run-<N>/
   ```
3. Compare against the agent roster in the manifest
4. Any agent with `"status": "pending"` or `"status": "timeout"` whose file does NOT exist → needs re-running
5. If all agent files exist → skip to Phase 4 (Synthesis)
6. If some are missing → resume from Phase 3, launching only missing agents

Tell the user: "Resuming deepen-plan run <N> from <timestamp>. X/Y agents completed. Re-launching Z agents."

## Phase 6: Cleanup and Report

After synthesis and red team challenge are complete:

1. Tell the user the plan has been enhanced
2. Show a brief summary of top findings (from the synthesis agent's return value)
3. **If red team challenge was run and CRITICAL items were deferred:** Flag them explicitly: "Warning: N unresolved critical challenges from red team review — see Risks and Open Questions in the plan. Address these before starting `/compound-workflows:work`."
4. **Do NOT delete any working files.** All agent outputs, manifests, and synthesis files are retained.
5. Offer options:
   - **View diff**: `git diff <plan_path>`
   - **View full synthesis**: Read `.workflows/deepen-plan/<plan-stem>/run-<N>-synthesis.md`
   - **Start `/compound-workflows:work`**: Begin implementing
   - **Deepen further**: Run another round on specific sections
   - **Revert**: `git checkout <plan_path>`

## Rules

- **NEVER delete prior run data.** Agent outputs, manifests, and synthesis files from ALL runs are retained for traceability and learning. Each run writes to `agents/run-<N>/` and `run-<N>-synthesis.md`.
- **NEVER call TaskOutput to retrieve full agent results.** Read the output files from disk instead.
- **NEVER paste full plan content into your own context if you can give agents the file path to read.**
- **Prefer re-running agents over skipping them.** When in doubt about whether an agent needs to run again, run it. The goal is the best possible output, not minimizing redundant work. Documents change between runs, and fresh analysis catches things prior runs missed.
- Agents write to disk. The parent reads summaries. The synthesis agent reads from disk.
- If context is getting heavy, compact before continuing. The manifest enables recovery.
- NEVER CODE. This command only researches and enhances plans.
