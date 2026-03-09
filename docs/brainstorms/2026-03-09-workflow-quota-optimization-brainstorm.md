---
title: "Reduce Compound Workflow Quota Consumption"
type: feat
status: active
date: 2026-03-09
bead: 22l
---

# Reduce Compound Workflow Quota Consumption

## What We're Building

Three-tier model selection for compound-workflows agents, token tracking integration, and conservative dynamic agent selection — reducing quota consumption while maintaining quality where it matters.

## Why This Approach

Compound workflows dispatch 50-80+ subagents in a full feature cycle (brainstorm → plan → deepen-plan → work → review). Currently 24 of 26 agents inherit Opus from the calling context. Empirical observation: many agents perform mechanical tasks (search, relay, aggregation) that don't benefit from Opus-level reasoning. Upstream (EveryInc) has the same pattern — only 2 Haiku agents, no Sonnet tier.

User's goals: reduce both dollar cost and wall-clock time. User's constraints: brainstorming and planning orchestration must stay Opus ("Sonnet doesn't think as hard or broadly"). Quality of verification, review, and synthesis must not degrade.

## Key Decisions

### Decision 1: Three-Tier Model Assignment for Named Agents

Agents get a `model` field in YAML frontmatter: `haiku`, `sonnet`, `opus`, or `inherit`.

**Sonnet tier (7 agents):**
- All 5 research agents: repo-research-analyst, context-researcher, learnings-researcher, best-practices-researcher, framework-docs-researcher
  - Rationale: search + summarize tasks. Well within Sonnet's capability. context-researcher and learnings-researcher were on Haiku but promoted to Sonnet for better summary quality.
- Red team relay wrappers (2 dispatch points in brainstorm.md + deepen-plan.md, using general-purpose subagents)
  - Rationale: zero reasoning — call MCP tool, write response to disk. External model does the thinking. 95%+ confidence.

**Opus tier (19+ agents — everything else):**
- All review agents (security-sentinel, architecture-strategist, pattern-recognition, performance-oracle, code-simplicity, agent-native, typescript, python, frontend-races, data-migration, deployment-verification, schema-drift)
  - Rationale: user chose all-Opus for review. "Review quality is too important to risk."
- Workflow agents: spec-flow-analyzer, plan-consolidator, convergence-advisor, plan-readiness-reviewer, semantic-checks, synthesis agent, bug-reproduction-validator, pr-comment-resolver
  - Rationale: these involve judgment, cross-document reasoning, or produce outputs that drive critical downstream decisions.
- MINOR triage analyst (3 dispatch points)
  - Rationale: user chose Opus. Triage quality directly affects what gets fixed vs deferred.
- All compound agents (context-analyzer, solution-extractor, related-docs-finder, prevention-strategist, category-classifier)
  - Rationale: user chose Opus. "Compound captures institutional knowledge. Want maximum quality."

**No Haiku tier in v1.** The 2 agents previously on Haiku (context-researcher, learnings-researcher) move UP to Sonnet.

### Decision 2: Model Tier Is a Property of the Agent, Not the Command

The `model` field lives in agent YAML frontmatter. Same agent, same model, regardless of which command dispatches it. No per-command overrides in v1.

Rationale: simpler mental model. If data shows per-command control is needed, add it later ("Agent property now, contextual later").

### Decision 3: Work Subagents — Needs Validation

`/compound:work` dispatches `general-purpose` subagents with inline prompts. The Agent tool has no `model` parameter at dispatch time. Model selection only works for named agents via frontmatter.

**Proposed mechanism:** Create a named `work-step-executor.md` agent with `model: sonnet` in frontmatter. Work command dispatches through this agent instead of `general-purpose`.

**Status: NEEDS VALIDATION.** Must test that:
1. Named agent dispatch with a dynamic prompt works correctly
2. `model: sonnet` in frontmatter actually changes the model at runtime
3. Quality of Sonnet work subagents is acceptable

**Configurable per-step** (Opus for complex steps, Sonnet for mechanical ones) is a v2 idea. For v1, either all work subagents use the executor (Sonnet) or stay on general-purpose (Opus).

User rationale: "I want to build confidence in myself and others that Sonnet produces great work."

### Decision 4: Token Tracking via ccusage Integration

Integrate ccusage (https://github.com/ryoppippi/ccusage) into `/compound:compact-prep` as a step. Surfaces session cost before compaction.

Rationale: without measurement, optimization is based on heuristics. ccusage provides empirical data on actual token consumption per session.

### Decision 5: Conservative Dynamic Agent Selection for Deepen-Plan

Deepen-plan currently dispatches from the full agent registry (10-15+ agents per run). Optimization: skip agents with zero plan relevance.

**Conservative rules:**
- Only skip agents whose domain has zero overlap with plan content (e.g., frontend-races-reviewer for a pure bash project)
- Keep ALL "core" agents that might contribute cross-domain insights
- Never skip: security-sentinel (produces valuable non-security insights), architecture-strategist, spec-flow-analyzer

User rationale: "Security sentinel sometimes has interesting findings on non-computer-security topics." Cross-domain insight risk is real — aggressive skipping would lose value.

**Evaluation mechanism:** The orchestrator decides during Phase 3 agent selection. No separate evaluation step — the orchestrator already reads the plan in Phase 1 and has context to determine relevance. Marginal cost: a few lines of reasoning within existing orchestrator work. This is cheaper than dispatching an irrelevant agent (full subagent lifecycle: init, file reads, analysis, disk write).

## Estimated Impact

### Token Savings from Model Tiering

**Per deepen-plan run (~20-33 dispatches):**
- ~5 research agents move to Sonnet: ~30-40% cheaper per agent
- ~2 relay wrappers move to Sonnet: ~30-40% cheaper per wrapper
- Net: ~7 of ~20 LLM dispatches at Sonnet → ~10-15% total token reduction per run

**Per brainstorm (~6 dispatches):**
- 2 research agents + 2 relay wrappers → Sonnet
- Net: 4 of 6 dispatches at Sonnet → ~20-25% reduction

**Full cycle (brainstorm + plan + deepen-plan + work + review):**
- Conservative estimate: ~10-15% overall token reduction from model tiering alone
- Work subagents (if validated for Sonnet): additional ~15-20% reduction
- Dynamic agent selection: additional ~5-10% reduction on deepen-plan runs

### Wall-Clock Savings

Sonnet is faster than Opus per-agent. However, parallel batches complete at the speed of the slowest agent. For deepen-plan (the heaviest command), review agents (Opus) are in the same batch as research agents, so research moving to Sonnet provides minimal wall-clock improvement. Wall-clock gains are most likely for brainstorm, where 4 of 6 dispatches move to Sonnet.

## Open Questions

(None — all resolved)

## Resolved Questions

1. **Should we use more Haiku?** No — Haiku summaries are too thin. The 2 existing Haiku agents are promoted to Sonnet.
   - User rationale: Sonnet is the right balance of quality and cost for research.

2. **Should red teaming be skippable for small changes?** No. "Red teaming is super valuable." Keep it always-on.
   - User rationale: the value of catching blind spots outweighs the cost.

3. **Should we investigate ccusage before making tier decisions?** No. "Decide tiers now." Token tracking is additive, not a prerequisite.
   - User rationale: pragmatic — make decisions based on task analysis, validate with data later.

4. **Does upstream (EveryInc) use Sonnet tiers?** No — upstream has the same 2-Haiku-rest-inherit pattern. We'd be pioneering Sonnet tiering.

5. **Is the Agent tool model parameter investigation a blocker?** For named agents, no — frontmatter `model` field works. For work subagents, the mechanism needs validation but doesn't block other tier changes.

6. **How to control model for general-purpose dispatches (relay wrappers)?** Convert from inline `general-purpose` dispatch to named agent files with `model: sonnet` frontmatter. The mechanism is the same as `model: haiku` (proven by context-researcher, learnings-researcher). Implementation: create `red-team-relay.md` agent files. Validate empirically after implementation.

## Red Team Resolution Summary

**CRITICAL:**
- Model dispatch mechanism doesn't work for general-purpose subagents (Gemini, Opus) → **Reopened as Open Question 1.** Path: convert to named agents, validate.

**SERIOUS:**
- Savings estimates speculative (all 3) → **Acknowledged.** Estimates are directional, not commitments. ccusage will provide real data.
- Review agents classified Sonnet-viable in research but kept Opus in decisions (Opus) → **Valid — gap acknowledged.** Research suggests Sonnet-viable; user preference overrides. Revisit with empirical quality comparison in v2.
- No empirical quality data for Sonnet (Opus) → **Valid — acknowledged.** Decision is pragmatic: start with highest-confidence changes, expand based on data.
- "No open questions" premature (OpenAI, Opus) → **Fixed.** Open Question 1 reopened.
- Always-on red team cost (OpenAI) → **Disagree.** Red team value exceeds cost. Skipping undermines workflow purpose.
- Work subagent quality risk (Gemini) → **Acknowledged.** Decision 3 already flags as NEEDS VALIDATION.
- Relay "zero reasoning" untested (OpenAI) → **Acknowledged.** Relay wrappers stay Sonnet (not Haiku) for error handling buffer. Test both in v2.

**MINOR:** Fixed (batch): 2 items applied (agent count 25→26, wall-clock savings qualified). 3 manual items acknowledged: ccusage granularity gap (session-level, not per-agent — noted as limitation), security-sentinel never-skip (user's conscious choice based on cross-domain value), dynamic selection rules vague (design deferred to implementation). 2 no-action: prompt minimization (out of scope), Haiku→Sonnet promotion (intentional quality tradeoff).

## Sources

- **Repo research:** `.workflows/brainstorm-research/workflow-quota-optimization/repo-research.md`
- **Context research:** `.workflows/brainstorm-research/workflow-quota-optimization/context-research.md`
- **Upstream analysis:** EveryInc/compound-engineering-plugin — 24 agents, 2 Haiku, rest inherit, no Sonnet tier
- **Iteration taxonomy:** `docs/solutions/process-analysis/2026-03-08-deepen-plan-iteration-taxonomy.md`
- **Adjacent brainstorm:** `docs/brainstorms/2026-03-08-red-team-model-selection-brainstorm.md` (bead aig — external model selection)
