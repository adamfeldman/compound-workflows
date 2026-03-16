---
title: "Assumption Verification Enforcement — From Documentation to Gates"
category: process-analysis
date: 2026-03-16
origin_plan: docs/plans/2026-03-15-fix-worktree-session-isolation-v2-plan.md
origin_brainstorm: docs/brainstorms/2026-03-15-session-worktree-start-flow-brainstorm.md
related:
  - docs/solutions/process-analysis/2026-03-14-inherited-assumption-blind-spots.md
  - docs/solutions/process-analysis/2026-03-15-framing-bias-mechanism-enumeration.md
beads: [hb4a, ytlk, b3by, fyg9]
tags: [assumption-verification, enforcement-gates, happy-path-bias, process-gap]
reuse_triggers:
  - Adding an Inherited Assumptions table to a plan
  - Designing integration tests for session-stateful features
  - Reviewing plan-readiness check definitions
  - When an "unverified" assumption is about to be implemented
---

# Assumption Verification Enforcement

## Problem

Two structural process gaps discovered during v2 session worktree integration testing (hb4a):

1. **Happy-path-only verification** — testing covers "does it work?" but not "what happens when the environment resists?" Failure, edge, and resume paths are systematically neglected.

2. **Toothless assumption framework** — the ytlk Inherited Assumptions table surfaces unverified assumptions with risk descriptions, but has no enforcement mechanism. "UNVERIFIED" is a label, not a gate.

Both produce false confidence: test plans that look thorough but miss failure modes, assumption tables that look rigorous but don't prevent proceeding.

## Evidence

### Finding 1: Happy-path verification bias

v3.3.0 session worktree integration testing verified success paths only:
- "bd worktree create works in hook" — tested
- "cd compliance is high" — tested
- "What happens on resume with existing worktree?" — NOT tested until user asked
- "What if bd fails?" — NOT tested until user asked
- "What if model ignores the instruction?" — discovered after 4 sessions

Same pattern as v3.2.0: hook output not delivered (stderr+exit 2) and worktrees deleted on exit were both happy-path-invisible bugs.

The failure mode: **test plans enumerate what the feature does, not what the environment does to the feature.**

### Finding 2: ytlk framework lacks enforcement

Plan assumption #7 (`$PPID` is the Claude Code process):
- **Surfaced correctly** — flagged as UNVERIFIED in Inherited Assumptions table
- **Risk described** — "PID locking gives false safe-to-resume"
- **Implemented anyway** — PID detection built into Step 1 of the plan
- **Three problems materialized** — PID inside worktree (cleanup friction), doesn't survive exit/resume, $PPID may not be Claude Code process

The risk description became a rationalization for proceeding. The more articulate the justification, the more confidently the team proceeded with an unverified assumption.

## Solution

### For happy-path bias: Failure-mode column in plan step tables

Each implementation step includes "how it fails" alongside "what it does":

```
| Step | What it does | How it fails | Test |
|------|-------------|-------------|------|
| Hook creates worktree | bd worktree create in bash | bd missing, name collision, already exists | Test each failure path |
| Model cd's into worktree | Reads hook output, runs cd | Model ignores instruction, cd fails | Fresh + resumed session |
```

Plan-readiness can verify this column exists and is non-empty.

For session-stateful features, integration tests must cover: fresh start, resume after exit, resume after crash, concurrent operation, feature disabled, dependency missing.

### For assumption enforcement: Resolution workflow with blocking gates

Add resolution status to each assumption:

| Status | Meaning | Blocks plan? |
|--------|---------|-------------|
| verified | Empirically confirmed | No |
| accepted-risk | User explicitly accepted | No |
| mitigated | Alternative design avoids it | No |
| unresolved | Not yet addressed | Yes, if load-bearing + high-risk |

**The gate:** Plan-readiness checks that no unresolved assumptions are both load-bearing AND high-risk. This converts documentation into enforcement.

**Load-bearing vs advisory:** Not all assumptions are equal. $PPID was load-bearing (concurrency detection designed around it). `stat -f '%m'` is advisory (graceful degradation if wrong). Only load-bearing + unverified + high-risk triggers the gate.

## Root Cause

Both findings share a root cause: **the process creates documentation artifacts that satisfy the form of rigor without the substance.** Tests that only cover success paths look thorough. Assumption tables with risk descriptions look like risk management. Both produce false confidence.

The fix is the same structural pattern: **convert documentation into workflow with gates.** The artifact isn't the end — it's the input to a process that ensures action.

## Cross-References

- **ytlk** — created the Inherited Assumptions framework. This finding identifies the enforcement gap.
- **fyg9** — framing bias in mechanism enumeration. Third instance of the ytlk pattern class.
- **b3by** — red-team-added steps bypass specflow. Related: late-added solutions don't get flow-analyzed.
- **hb4a** — the integration testing session where both findings were discovered empirically.
- `docs/brainstorms/2026-03-15-assumption-verification-v2-brainstorm.md` — v2 brainstorm that unified ytlk+fyg9 with verification taxonomy. Partially addresses Finding 2 but lacks blocking gates.
