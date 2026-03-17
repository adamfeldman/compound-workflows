---
name: classify-stats
description: Classify stats entries with complexity and output_type labels
disable-model-invocation: false
---

# Classify Stats — Post-Hoc Complexity and Output Type Classification

Reads unclassified stats entries from `$WORKFLOWS_ROOT/stats/*.yaml`, dispatches a classifier subagent to propose `complexity` and `output_type` labels, presents proposals in batch table format for user confirmation, then rewrites YAML files in place with classification fields added.

## Phase 1: Config Check and Entry Discovery

### Step 1.1: Check Classification Toggle

Read `compound-workflows.local.md` and check the `stats_classify` key.

- If `stats_classify: false` (exact match): report "Stats classification is disabled (`stats_classify: false` in `compound-workflows.local.md`)." and stop.
- If the key is missing or any other value: proceed (missing = enabled).

### Step 1.2: Discover Stats Files

```bash
ls $WORKFLOWS_ROOT/stats/*.yaml 2>/dev/null
```

If no files found: report "No stats files found in `$WORKFLOWS_ROOT/stats/`." and stop.

### Step 1.3: Read and Filter Entries

Read all `$WORKFLOWS_ROOT/stats/*.yaml` files. For each multi-document YAML file, parse individual entries separated by `---` document markers.

**Exclude** entries with `type: ccusage-snapshot` — these are cost snapshots from compact-prep, not agent dispatch records.

**Filter to unclassified entries only:** entries where `complexity` is `null` (or absent). Already-classified entries (complexity has a non-null value) are skipped — this makes the skill idempotent.

If zero unclassified entries remain after filtering: report "All stats entries are already classified." and stop.

### Step 1.4: Incomplete File Detection

Check each stats file for suspiciously low entry counts relative to command type. Flag files as "possibly incomplete" using these minimum thresholds:

| Command | Minimum Expected Entries | Rationale |
|---------|-------------------------|-----------|
| work | 1 | Single bead dispatch is valid |
| brainstorm | 2 | At minimum: 2 research agents |
| plan | 3 | At minimum: 2 research + 1 readiness |
| review | 5 | 7 standard agents, 5+ expected |
| deepen-plan | 5 | Batched research/review, 5+ expected |

For files below the minimum threshold, include a warning in the classification table:

> Warning: `<filename>` has N entries (expected at least M for `<command>`). This file may be from an interrupted run.

This is informational only — classification proceeds on whatever entries exist.

## Phase 2: Classify Entries

### Step 2.1: Resolve Plugin Root

Run `bash ${CLAUDE_SKILL_DIR}/../../scripts/init-values.sh classify-stats`. Read the output and track REPO_ROOT, PLUGIN_ROOT, MAIN_ROOT, WORKFLOWS_ROOT, DATE, and RUN_ID values.

**All `.workflows/` paths in this skill use `$WORKFLOWS_ROOT` (the main repo root's `.workflows/` directory), NOT relative `.workflows/`.**

### Step 2.2: Prepare Classification Input

Build the input payload for the classifier subagent. For each unclassified entry, extract:

- **File path** (which stats file it came from)
- **Entry index** (position within the file, for rewrite targeting)
- **agent** name
- **command** (work / brainstorm / plan / deepen-plan / review)
- **step** value
- **model** (opus / sonnet / haiku)
- **tokens** count
- **stem** (links to `.workflows/` artifacts)

### Step 2.3: Pagination Check

Count total unclassified entries. If 20 or more, split into groups of 10 for paginated processing. Each page is classified and confirmed independently before proceeding to the next page.

If fewer than 20: process all entries in a single batch.

### Step 2.4: Dispatch Classifier Subagent

For each page (or single batch if under 20 entries), dispatch a classifier:

```
Agent general-purpose: "
You are a stats entry classifier for the compound-workflows plugin.

Your task: propose `complexity` and `output_type` labels for each unclassified stats entry based on two input layers.

## Input Layer 1: Stats Entries

[Insert unclassified entries here — agent, command, step, model, tokens for each]

## Input Layer 2: Artifacts

For each entry, skim (do not deep-read) the corresponding artifacts in `$WORKFLOWS_ROOT/` using the `stem` field to locate them. The actual agent output reveals what work was done:
- `$WORKFLOWS_ROOT/brainstorm-research/<stem>/` — brainstorm artifacts
- `$WORKFLOWS_ROOT/plan-research/<stem>/` — plan artifacts
- `$WORKFLOWS_ROOT/deepen-plan-research/<stem>/` — deepen-plan artifacts
- `$WORKFLOWS_ROOT/reviews/` — review artifacts
- `$WORKFLOWS_ROOT/work/` — work artifacts (if present)

Look at file names and skim first ~20 lines of each artifact to understand what the agent produced. Do not read entire files.

## Classification Dimensions

### Complexity (4-tier)
- **rote**: Formulaic output requiring no judgment. Examples: relay agents passing MCP responses to disk, template-filling agents.
- **mechanical**: Structured analysis following explicit rules. Examples: security-sentinel checking known vulnerability patterns, truncation-check validation, pattern-recognition-specialist.
- **analytical**: Requires synthesis across multiple inputs or domain reasoning. Examples: architecture-strategist evaluating tradeoffs, plan-readiness-reviewer assessing completeness, convergence-advisor finding consensus.
- **judgment**: Novel reasoning, creative problem-solving, or subjective evaluation. Examples: brainstorm research agents exploring open-ended questions, red team agents evaluating from adversarial perspective, plan-synthesizer integrating diverse research.

### Output Type (5 categories)
- **code-edit**: Agent produced or modified code/config files. Examples: work.md subagents implementing plan steps.
- **research**: Agent gathered and organized information. Examples: repo-research-analyst, learnings-researcher, best-practices-researcher, framework-docs-researcher, context-researcher.
- **review**: Agent evaluated existing work and produced findings/recommendations. Examples: all review-category agents (security-sentinel, architecture-strategist, etc.), plan-readiness-reviewer.
- **relay**: Agent relayed external content to disk without substantial interpretation. Examples: red-team-relay (MCP provider dispatch), agents wrapping MCP tool responses.
- **synthesis**: Agent combined multiple inputs into a unified output. Examples: plan-consolidator, convergence-advisor, plan-synthesizer, MINOR triage agents.

## Classification Heuristics

Use these heuristics when artifacts are sparse or unavailable:
- `red-team-relay` agents: almost always mechanical/relay
- Research-category agents (repo-research-analyst, learnings-researcher, etc.): typically analytical/research
- Review-category agents during `/do:review`: typically mechanical/review or analytical/review depending on token count (high token count suggests deeper analysis)
- `plan-consolidator`: typically mechanical/synthesis
- `convergence-advisor`: typically analytical/synthesis
- `plan-readiness-reviewer`: typically analytical/review
- `general-purpose` during red team (MINOR triage): typically analytical/synthesis
- `general-purpose` during work: depends entirely on artifacts — could be any combination

## Output Format

Return your classifications as a structured list. For each entry:

Entry N:
- File: <stats file path>
- Agent: <agent name>
- Command: <command>
- Tokens: <token count>
- Complexity: <rote|mechanical|analytical|judgment>
- Output Type: <code-edit|research|review|relay|synthesis>
- Reasoning: <1 sentence explaining the classification>

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write your COMPLETE classification to: $WORKFLOWS_ROOT/stats/classify-proposals-<DATE>-<RUN_ID>.md
After writing the file, return ONLY a 2-3 sentence summary of how many entries you classified and the distribution across complexity tiers.
DO NOT return your full classification in your response.
"
```

### Step 2.5: Read Classifier Output

After the classifier subagent completes, read the proposals from disk:

```bash
ls $WORKFLOWS_ROOT/stats/classify-proposals-<DATE>-<RUN_ID>.md 2>/dev/null && echo "EXISTS" || echo "NOT_FOUND"
```

Read `$WORKFLOWS_ROOT/stats/classify-proposals-<DATE>-<RUN_ID>.md` using the Read tool. Parse the structured classification proposals.

## Phase 3: User Confirmation

### Step 3.1: Present Batch Table

Present all proposed classifications in a batch table:

```markdown
### Classification Proposals

| # | File | Agent | Tokens | Complexity | Output Type | Reasoning |
|---|------|-------|--------|------------|-------------|-----------|
| 1 | 2026-03-10-work-... | general-purpose | 20121 | mechanical | code-edit | Implemented plan step with code edits |
| 2 | 2026-03-10-plan-... | security-sentinel | 15432 | analytical | review | Deep security analysis of plan |
| ... | ... | ... | ... | ... | ... | ... |
```

If incomplete file warnings were generated in Step 1.4, show them above the table.

If paginating (20+ entries), show page header: "Page 1 of N (entries 1-10)"

### Step 3.2: User Options

Present three options using AskUserQuestion:

1. **Confirm all** — accept all proposed classifications as-is
2. **Override specific entries** — user specifies entry numbers and replacement values (e.g., "#3: complexity=analytical, #7: output_type=synthesis")
3. **Skip** — do not write any classifications; exit without modifying files

If the user chooses **Override specific entries**: parse the overrides, apply them to the proposals, and re-display the affected rows for final confirmation before proceeding.

If paginating: after confirming a page, proceed to the next page. The user confirms each page independently.

## Phase 4: Write Classifications

### Step 4.1: Apply Classifications to YAML Files

For each stats file that has entries to classify:

1. **Read** the full file content
2. **Parse** the multi-document YAML into individual entries
3. **Modify** the `complexity` and `output_type` fields on confirmed entries (replace `null` values with the confirmed classification strings)
4. **Write** the modified content to `<filename>` using the Write tool

**Important:** The YAML rewrite must preserve all existing fields exactly (tokens, tools, duration_ms, timestamp, status, run_id, etc.). Only `complexity` and `output_type` change from `null` to their classified values. Do not reformat, reorder, or drop any fields.

### Step 4.2: Cleanup

```bash
rm -f $WORKFLOWS_ROOT/stats/classify-proposals-<DATE>-<RUN_ID>.md
```

Remove the temporary proposals file after successful classification.

### Step 4.3: Report

Report the results:

```markdown
## Classification Complete

- **Entries classified:** N
- **Files modified:** N
- **Complexity distribution:** N rote, N mechanical, N analytical, N judgment
- **Output type distribution:** N code-edit, N research, N review, N relay, N synthesis
```

If any file write failed, report the error and note which entries were not classified.

## Rules

- **Idempotent**: Already-classified entries are never re-classified. Running this skill multiple times is safe.
- **Non-destructive**: Write tool writes are atomic. Original files are never partially overwritten.
- **User-confirmed**: No classifications are written without explicit user confirmation.
- **ccusage entries excluded**: Entries with `type: ccusage-snapshot` are always skipped.
- **Session JSONL correlation deferred**: v1 relies on stats entries + `.workflows/` artifacts for classification context. Session log correlation is deferred to a future version.
