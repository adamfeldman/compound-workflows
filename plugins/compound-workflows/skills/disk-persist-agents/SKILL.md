---
name: disk-persist-agents
description: Pattern for running subagents that write complete outputs to disk, keeping the parent context lean. Use when orchestrating multiple research or review agents in parallel.
user-invocable: false
---

# Disk-Persisted Agent Pattern

A reusable pattern for dispatching subagents that write their complete output to disk files instead of returning results in the conversation context. This prevents context exhaustion during multi-agent workflows.

## The Problem

When you launch 5-15 parallel agents and each returns a full analysis (1000+ tokens), the parent context fills up fast. After a few rounds, you hit compaction or lose working memory.

## The Solution

Every agent writes its complete findings to a file on disk and returns only a 2-3 sentence summary. The parent context stays lean. A synthesis step reads all files from disk.

## The Output Instruction Block

Append this block to **every** agent prompt that should persist to disk:

```
=== OUTPUT INSTRUCTIONS (MANDATORY) ===

Write your COMPLETE findings to this file using the Write tool:
  <output-file-path>

Include ALL analysis, code examples, recommendations, and references in that file.
Structure the file with clear markdown headers.

After writing the file, return ONLY a 2-3 sentence summary.
Example: "Found 3 security issues (1 critical). 2 performance recommendations. Full analysis at <path>."

DO NOT return your full analysis in your response. The file IS the output.
```

## Directory Convention

All workflow outputs go under `.workflows/` in the project root:

```
.workflows/
├── brainstorm-research/<topic-stem>/
│   ├── repo-research.md
│   ├── context-research.md
│   └── red-team-critique.md
├── plan-research/<plan-stem>/
│   └── agents/
│       ├── repo-research.md
│       ├── learnings.md
│       ├── best-practices.md
│       ├── framework-docs.md
│       └── specflow.md
├── deepen-plan/<plan-stem>/
│   ├── manifest.json
│   ├── agents/
│   │   ├── run-1/
│   │   │   ├── research--*.md
│   │   │   ├── review--*.md
│   │   │   └── red-team--critique.md
│   │   └── run-2/
│   │       └── ...
│   ├── run-1-synthesis.md
│   └── run-2-synthesis.md
├── compound-research/<topic-stem>/
│   └── agents/
│       ├── context.md
│       ├── solution.md
│       ├── related-docs.md
│       ├── prevention.md
│       └── category.md
├── code-review/<topic-stem>/
│   └── agents/
│       ├── security.md
│       ├── performance.md
│       ├── architecture.md
│       └── ...
└── work-review/
    └── agents/
        └── code-simplicity.md
```

### Topic Stems

Derive a short stem from the task context:
- **Brainstorm:** From the feature description (e.g., `claude-code-cursor-dual-tool`)
- **Plan:** From the plan filename (e.g., `api-rate-limiting`)
- **Review:** From the branch name or PR number (e.g., `feat-user-dashboard-redesign`, `pr-123`)
- **Compound:** From the problem/finding (e.g., `bq-cost-measurement`)

Use lowercase, hyphens, 3-6 words max.

## Monitoring Completion

**DO NOT use TaskOutput** to retrieve full agent results. Instead, poll for file existence:

```bash
ls .workflows/<workflow-type>/<topic-stem>/agents/
```

Compare the files present against the expected list. When all expected files exist, the batch is complete.

### Timeout Handling

If an agent hasn't produced output after 3 minutes:
1. Mark it as timed out in your tracking (manifest.json if using deepen-plan, mental note otherwise)
2. Move on to the next phase
3. Don't let one slow agent block the entire workflow

## Retention Policy

**Never delete research outputs.** All agent outputs, manifests, and synthesis files are retained for:

1. **Traceability** — understand what informed a decision
2. **Learning** — future sessions can reference prior research
3. **Recovery** — if context compacts, disk files survive
4. **Iteration** — deepen-plan supports multiple runs, each in its own `run-N/` directory

The `.workflows/` directory should be added to `.gitignore` (it's working state, not source code) unless the team wants to version-control research outputs.

## Batch Dispatch Pattern

For workflows with many agents (review, deepen-plan), dispatch in batches:

1. **Batch 1: Research agents** — these produce context that review agents benefit from
2. **Batch 2: Review agents** — can reference research output files
3. **Batch 3: Synthesis** — reads all output files, produces consolidated findings

Launch each batch with `run_in_background: true`. Wait for the batch to complete (file existence check) before launching the next.

Batch size: 10-15 agents per batch. More than that risks overwhelming the system.

## Example: Dispatching a Research Agent

```
Task repo-research-analyst (run_in_background: true): "
You are a repository research analyst specializing in codebase pattern discovery.
Research existing patterns related to: [feature description]
Focus on: similar features, established patterns, project conventions.
Read the codebase, not just file names.

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write your COMPLETE findings to: .workflows/plan-research/my-feature/agents/repo-research.md
After writing the file, return ONLY a 2-3 sentence summary.
"
```

## Anti-Patterns

- **Calling TaskOutput** to read full agent results into context — defeats the whole purpose
- **Pasting agent results into subsequent prompts** — give agents the file path to read instead
- **Deleting outputs between runs** — you lose traceability and recovery capability
- **Skipping the output instruction block** — agents will return full results in context by default
- **Running all agents in a single batch** — batch by dependency order (research → review → synthesis)
