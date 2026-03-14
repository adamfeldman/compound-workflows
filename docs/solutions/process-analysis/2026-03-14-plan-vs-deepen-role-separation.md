---
title: "Plan vs Deepen-Plan: Role Separation and When Deepen Is Non-Optional"
category: process-analysis
date: 2026-03-14
confidence: high
tags:
  - workflow-design
  - integration-gaps
  - plan-audit-distinction
  - cross-cutting-changes
origin_plan: docs/plans/2026-03-14-fix-worktree-session-isolation-plan.md
origin_brainstorm: docs/brainstorms/2026-03-13-git-index-isolation-brainstorm.md
beads:
  - s7qj (worktree-per-session isolation — source incident)
  - jvcl (P0 — auto-recommend deepen for multi-component changes)
  - cs5z (P3 — deepen beads integration throughout plugin)
---

# Plan vs Deepen-Plan: Role Separation and When Deepen Is Non-Optional

## Key Finding

`/do:plan` and `/do:deepen-plan` serve fundamentally different roles:

- **Plan** researches the **problem space** to create a solution design. "What do I need to know about git worktrees and concurrency?"
- **Deepen** researches **the plan itself** to find integration gaps against the existing codebase. "Given this plan adds new files, what plugin infrastructure needs updating?"

For changes that introduce new components or modify 3+ existing files, deepen is non-optional. Plan's problem-focused research systematically misses cross-cutting infrastructure concerns (setup changes, config key registration, QA updates, versioning touchpoints) regardless of how many review iterations it runs.

## Evidence: The s7qj Incident

The worktree-per-session isolation plan (bead s7qj) went through 8 review iterations:

1. Brainstorm with 4 design iterations + 4 red team rounds
2. SpecFlow analysis: 7 user flows, 19 gaps (G1-G19), all resolved
3. Readiness check round 1: 2 CRITICAL + 5 SERIOUS, all fixed
4. Readiness check round 2: 1 new SERIOUS, fixed
5. 3-provider red team (Opus + OpenAI + Gemini): 12+ unique findings, 4 accepted
6. Post-red-team readiness re-check: clean

**Despite all this, the plan missed that adding a new skill (`/do:merge`) and config key (`session_worktree`) requires `/do:setup` changes.**

The gap only surfaced because:
- Gemini flagged hook installation in its red team review
- The orchestrator dismissed it as "defer — committed to this repo"
- The user pushed back: "how did the plan miss including /do:setup changes?"

### Why Every Review Layer Missed It

Every review layer analyzed **internal consistency** and **problem-domain correctness**. None cross-referenced the plan's Files Changed against the plugin's infrastructure requirements:

| Review Layer | What It Checks | Why It Missed |
|-------------|----------------|---------------|
| SpecFlow | User-facing flows | Doesn't analyze developer/infrastructure flows |
| Readiness (8 checks) | Internal consistency — stale values, contradictions, underspecification | Doesn't check "does this plan account for all infrastructure it touches?" |
| Red team (7 dimensions) | Assumptions, architecture, missing steps, dependencies, overengineering, contradictions, problem selection | None targets infrastructure integration completeness |
| Research agents (4) | Problem domain — "what do I need to know about worktrees?" | Scoped to feature description, not plan's structural implications |

## Root Cause

Plan's research agents are **problem-focused by design**. Their prompts all receive the feature description: "Research existing patterns related to: \<feature\_description\>." They answer "what should the solution look like?" They do not answer "what existing infrastructure must be updated to accommodate this solution?"

That second question is deepen's job. Deepen dispatches 20+ agents that review **the plan document**, not the problem domain. An architecture-strategist reading the plan sees "this adds a new skill" and can flag "setup needs updating." Plan's repo-research-analyst reading the feature description sees "git worktree isolation" and has no reason to think about setup.

## Generalized Principle

Generative analysis ("what should we build?") and integration analysis ("what must change to accommodate what we build?") are orthogonal concerns. No amount of iteration on the former compensates for skipping the latter.

## When Deepen Is Non-Optional

| Signal | Why |
|--------|-----|
| Plan adds 2+ new files under `plugins/` | New files create integration obligations (CLAUDE.md inventory, README counts, plugin.json, QA, setup) |
| Plan modifies 3+ existing skills | Multiple integration contracts at play |
| Plan spans infrastructure boundary (scripts + skills + hooks + settings) | Implicit contracts between subsystems |
| Plan adds config keys | Setup must generate them, skills must read them |

## When Deepen Can Be Skipped

- Single-file fixes (typo, bug in one skill)
- Changes entirely within one component (e.g., improving a prompt in one agent)
- Documentation-only changes

## Reuse Triggers

Re-read this when:
- A plan passes readiness clean but wasn't deepened — clean readiness != clean integration
- Red team returns 0 CRITICAL on a 5+ step plan — red team challenges logic, not infrastructure fit
- A plan's research agents focused on external domain knowledge rather than internal infrastructure

## What Would Invalidate This Finding

1. Plan gains an infrastructure-integration research agent that cross-references Files Changed against CLAUDE.md/setup/QA
2. Integration contracts become machine-checkable (e.g., adding a skill auto-generates a checklist)
3. SpecFlow analysis expands to include infrastructure flows alongside user flows
4. QA scripts catch integration gaps at commit time (late but deterministic)

## Open Questions (Bead jvcl, P0)

- Should plan detect scope early and fast-track to deepen?
- Should deepen fold into plan automatically for big changes?
- Is there a simple heuristic (new files + modified files count) that reliably predicts when deepen adds value?
- Should the Phase 7 decision tree penalize "big change without deepen" the same way it penalizes "no brainstorm + 4+ steps"?

## Related

- `docs/solutions/process-analysis/2026-03-08-deepen-plan-iteration-taxonomy.md` — what happens during deepen rounds (complementary: that doc covers iteration dynamics, this one covers when to start)
- `docs/brainstorms/2026-03-09-plan-deepen-recommendation-brainstorm.md` — designed the Phase 7 decision tree (missing the infrastructure signal)
- `docs/brainstorms/2026-03-10-plan-red-team-readiness-brainstorm.md` — added red team to plan, making deepen easier to skip (potentially worsening this gap)
- `memory/feedback_deepen-plan-for-big-changes.md` — the memory file capturing this learning
