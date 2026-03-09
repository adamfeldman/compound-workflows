---
title: "Task Completion Stats as Per-Agent Instrumentation"
type: analytical
category: plugin-infrastructure
date: 2026-03-09
tags: [cost-modeling, instrumentation, model-tiering]
origin_plan: docs/plans/2026-03-09-feat-workflow-quota-optimization-plan.md
origin_brainstorm: docs/brainstorms/2026-03-09-workflow-quota-optimization-brainstorm.md
related_beads: [voo, xu2, 22l]
---

# Task Completion Stats as Per-Agent Instrumentation

## Finding

Claude Code Task completion notifications already return per-subagent usage stats (`total_tokens`, `tool_uses`, `duration_ms`). No new tooling is needed for per-agent cost instrumentation — just persist what's already returned.

```
<usage>total_tokens: 20121, tool_uses: 13, duration_ms: 43364</usage>
```

This data is more actionable for optimization decisions than ccusage (daily aggregates across all sessions). ccusage answers "how much did I spend today?" — Task completion stats answer "which dispatch cost what and was it worth it?"

## Evidence

v2.0.0 work execution dispatched 8 subagents. All returned usage stats. First archived dataset at `.workflows/work-stats/2026-03-09-quota-optimization-v2.0.md`:

| Step | Task | Tokens | Tools | Duration | Complexity |
|------|------|--------|-------|----------|------------|
| 1 | Change 5 model: fields | 20,121 | 13 | 43s | Mechanical |
| 2 | Create red-team-relay agent | 38,105 | 16 | 102s | Spec-following |
| 5 | Insert ccusage step, renumber | 22,651 | 9 | 58s | Mechanical |
| 4 | Add prose section to deepen-plan | 24,399 | 13 | 82s | Moderate |
| 3 | Change 8 dispatch names + audit | 44,641 | 19 | 83s | Mechanical |
| 7 | Convergence advisor cleanup | 28,727 | 14 | 65s | Low |
| 6a | Update CLAUDE.md registry | 23,132 | 16 | 88s | Mechanical |
| 6b | Version/CHANGELOG/README | 43,867 | 21 | 105s | Moderate |

**Totals:** 245,643 tokens, 121 tool uses, 626s (10.4 min). ~80% mechanical, ~20% moderate judgment.

## Why Not ccusage?

| Approach | Granularity | What it answers |
|----------|-------------|-----------------|
| **ccusage** | Daily aggregate, all sessions | "How much did I spend today?" |
| **Task completion stats** | Per-dispatch, per-agent | "Which step cost what? Was it mechanical or judgment-heavy?" |
| **Session log parsing** | Per-turn, complex to parse | Unnecessary — Task completions already return clean data |

ccusage remains useful for daily spend visibility. Task completion stats are what drive optimization decisions. They're complementary, not competing.

## Key Insight: Complexity Classification Is Free

The orchestrator writes each subagent's task description. It already knows whether a step is "change 5 YAML fields" (mechanical) or "write CHANGELOG migration notes" (judgment-required). Tagging complexity at dispatch time — alongside the actual cost data — creates the full dataset for model-tiering decisions.

## Scope: All Orchestrator Commands

Every orchestrator command dispatches Tasks and receives stats:

| Command | Dispatch Points | What it instruments |
|---------|----------------|---------------------|
| `/compound:work` | N steps per plan | Work subagent cost/complexity |
| `/compound:deepen-plan` | 16+ agents + red team | Research, review, relay costs |
| `/compound:brainstorm` | Research + red team | Research and relay costs |
| `/compound:plan` | Research agents | Research agent costs |
| `/compound:review` | Parallel reviewers | Review agent costs |

Instrumenting all commands builds a cross-command cost profile.

## Implementation Path (Bead voo)

1. After each Task completion, parse the `<usage>` stats from the response
2. Append to a per-run stats file in `.workflows/` with: command, agent name, model, complexity classification, raw stats
3. Orchestrator classifies complexity at dispatch time (mechanical / analytical / judgment)
4. Over time, the accumulated dataset enables data-driven model-tier routing (bead xu2)

## Reuse Triggers

Re-read this when:
- Revisiting model-tiering decisions (which agents should be Sonnet vs Opus)
- Building new orchestrator commands (instrument from day one)
- Debugging unexpectedly high session costs (ccusage shows total, this shows attribution)
- Evaluating whether a Sonnet agent should be promoted to Opus or vice versa

## Invalidation Assumptions

- Task completion notification format changes (undocumented API surface, no stability guarantee)
- Claude Code adds native per-dispatch instrumentation (would make custom collection redundant)
- Model quality convergence makes tiering irrelevant
- Complexity classification doesn't correlate with model-tiering outcomes

## Dependency Chain

```
voo (collect + classify per-dispatch stats) → xu2 (use dataset for Sonnet work subagent decisions)
```

## Sources

- First dataset: `.workflows/work-stats/2026-03-09-quota-optimization-v2.0.md`
- Quota optimization brainstorm: Decision 4 (ccusage), MINOR resolution (per-agent gap)
- Quota optimization plan: Out of Scope (per-agent tracking), Step 5 (ccusage limitation)
- Performance oracle review: token volume asymmetry estimates needing validation
- Compound research: `.workflows/compound-research/task-completion-stats-instrumentation/agents/`
