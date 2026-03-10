---
title: "Native Agent Discovery for deepen-plan"
type: feat
status: active
date: 2026-03-09
bead: null
---

# Native Agent Discovery for deepen-plan

## What We're Building

Replace deepen-plan's Phase 2 filesystem-based agent and skill discovery with Claude Code's native subagent_type system. The current approach uses `find ~/.claude/plugins/cache` to crawl the filesystem, read YAML frontmatter, and build agent/skill rosters. This is fragile (sandbox restrictions break `find` silently), generates a cascade of bash permission prompts before useful work begins, and reconstructs information that's already available natively.

The subagent_type registry already contains every installed plugin's agents with descriptions, model specs, and dispatch capabilities. Deepen-plan should use this instead — both for agent discovery and skill discovery.

## Why This Approach

**The root pain:** deepen-plan's Phase 2 generates multiple bash approval prompts for filesystem discovery commands that frequently fail due to sandbox restrictions. The user ends up debugging `find` patterns instead of getting plan analysis. User's words: "I was triggered when it seemed fragile and I had to keep approving bash commands so deepen-plan could start."

**The redundancy:** Three sources already encode the agent roster without filesystem access:
1. **Subagent_type registry** — all installed plugin agents, with descriptions, available in the system prompt
2. **CLAUDE.md Agent Registry table** — all 26 agents with category, dispatch info, model config
3. **review.md pattern** — hardcoded roster with `Task <agent-name>`, no discovery needed

Deepen-plan is the **only command** that does filesystem discovery. Every other command (review, brainstorm, plan) hardcodes its agent names.

**User-defined extensibility:** The subagent_type system picks up user-defined agents automatically. Users who add their own review agents (e.g., `.claude/agents/review/go-reviewer.md` for a Go project) get them included in deepen-plan runs without editing command files. This is the real extensibility value — not third-party plugins, but users extending their stack's review coverage. User: "I want D so users can add their own review agents for other programming langs."

## Key Decisions

### Decision 1: Dynamic discovery (D) primary, hardcoded fallback (A)

**Primary (Approach D):** The command instructs the LLM to read its available subagent_types, filter for `*:review:*` and `*:research:*` patterns, and dispatch those. This is fully dynamic — user-defined agents and agents from any installed plugin get picked up automatically.

**Fallback (Approach A):** A hardcoded list of compound-workflows core agents ensures reliability if dynamic parsing fails or produces an incomplete roster.

**Invariant check (red team fix):** After D builds its roster, verify that required core agents are present (at minimum: `security-sentinel`, `architecture-strategist`). If any invariant agents are missing, merge with A's hardcoded list. This catches partial omissions that a simple empty-check would miss.

**Why not filesystem (current approach):** Fragile under sandbox restrictions. Generates bash approval cascades. Reconstructs information already available natively.

**Why not CLAUDE.md-driven (Approach B):** CLAUDE.md is already loaded into context, but parsing a markdown table adds format-coupling fragility.

### Decision 2: Agent descriptions via manifest.json

The synthesis agent and human reviewers need to know what each dispatched agent does. Currently descriptions come from YAML frontmatter read during filesystem discovery.

With Approach D, the parent LLM sees descriptions in its system prompt. It writes them into `manifest.json` agent entries during roster construction. The synthesis agent reads the manifest to attribute findings. This preserves traceability without filesystem access.

### Decision 3: Stack-based filtering stays as-is

The Step 2e relevance assessment (stack-based skip rules, never-skip protection for security-sentinel and architecture-strategist) remains unchanged. It's applied after the subagent_type roster is built instead of after filesystem discovery. The filtering logic itself is sound — only the discovery source changes.

### Decision 4: Agent tool dispatch (not Task)

Agents are dispatched via Agent tool with `subagent_type` parameter rather than the current Task dispatch pattern. Both Task and Agent support `subagent_type` (red team confirmed Task already has this capability). The Agent tool is preferred because it has an explicit `model` parameter for dispatch-time model override — validated empirically (dispatched with `model: "haiku"`, completed in 995ms vs 13s at opus).

Dispatch-time model control enables cost optimization experiments without editing agent YAML frontmatter. User: "model override matters."

### Decision 5: Skills discovery also migrates (scope expanded)

Originally scoped to agent discovery only. Red team (Opus) correctly flagged that skills discovery uses the same fragile `find ~/.claude/plugins/cache -type d -name "skills"` path — the same sandbox problem, exempted without evidence.

Scope expanded: both agent and skill discovery in Phase 2 migrate away from filesystem crawling. Learnings discovery (`find docs/solutions/`) stays as-is — it searches the project directory, not the plugin cache, and doesn't hit sandbox issues.

### Decision 6: Sequence with voo

This change ships first. voo's plan needs updates:
- **Step 7** (deepen-plan instrumentation): Reference Agent dispatch instead of Task dispatch. The `<usage>` mechanism is identical (validated — see Q1), so only the dispatch syntax changes.
- **All steps**: voo should adopt Agent dispatch for all 5 commands (not just deepen-plan) to standardize the pattern and eliminate the temporary divergence introduced by this change.

These updates happen during `/compound:deepen-plan` on voo's plan, which is the next workflow step.

## Resolved Questions

### Q1: Does the Agent tool include `<usage>` in background completion notifications?

**Resolved: Yes.** Empirically observed during this brainstorm session. Three background Agent dispatches (repo-research-analyst, context-researcher, code-simplicity-reviewer) all returned `<usage>` in their completion notifications with `total_tokens`, `tool_uses`, and `duration_ms` fields — identical format to Task completion notifications. This means switching from Task to Agent dispatch does not break voo's instrumentation design. Edge-case testing (error/timeout paths, cross-model consistency) deferred to implementation.

### Q2: Graceful fallback when plugin is uninstalled

**Resolved: Not a concern.** Research surfaced the "graceful fallback" convention — Task with inline role descriptions works even if the plugin is later uninstalled. However, deepen-plan IS a compound-workflows command. If the plugin is uninstalled, deepen-plan can't run at all. User: "If the plugin is uninstalled, deepen-plan shouldn't run at all — it IS the plugin."

### Q3: Should other commands also switch to Agent tool dispatch?

**Resolved: Deepen-plan only for now.** Other commands (review, brainstorm, plan) work fine with Task dispatch and hardcoded rosters — they don't have the filesystem discovery problem. Scope limited to deepen-plan. voo will touch all 5 commands later; if Agent dispatch proves superior, voo can standardize the pattern.

### Q4: Integration with voo (per-agent token instrumentation)

**Resolved: Sequence — this first, then update voo's plan.** This change ships first. voo's Step 7 then references Agent dispatch. User chose sequencing over merging to keep plans cleanly scoped.

### Q5: Research agent counterarguments

**Resolved: Addressed.** Research agents raised three concerns:

1. **"Mid-session staleness — subagent_type registry is a session-start snapshot"** — True but irrelevant. Deepen-plan dispatches existing, installed agents. It never creates agents mid-session.

2. **"No model parameter on Agent tool"** — Factually incorrect. The Agent tool has `model: enum["sonnet", "opus", "haiku"]`. Validated empirically: dispatched with `model: "haiku"`, completed in 995ms. Prior memory/project.md entry was outdated — corrected.

3. **"Graceful fallback convention"** — Addressed in Q2 above.

### Q6: `model` parameter existence

**Resolved: Exists and works.** memory/project.md previously said "Agent tool has no `model` parameter." This was outdated — the parameter was added in a Claude Code update. Validated by dispatching code-simplicity-reviewer with `model: "haiku"` (995ms, 0 tool uses — haiku-speed). Memory entry corrected.

### Q7: Agent tool vs Task tool

**Resolved: Both support subagent_type.** Red team (Gemini, Opus) noted Task already supports `subagent_type`, so a "migration" framing is misleading. The choice is Agent over Task because Agent has the `model` parameter for dispatch-time model override. Both are valid dispatch mechanisms; Agent is preferred for the additional capability.

### Q8: subagent_type prefix (`compound:` vs `compound-workflows:`)

**Resolved: Likely aliases.** orchestrating-swarms skill uses `compound:` prefix, brainstorm and system prompt use `compound-workflows:` prefix. User believes they're aliases. Validate during implementation.

### Q9: LLM self-reading reliability

**Resolved: Mitigated by invariant check + fallback.** All three red team providers flagged LLM self-reading as unreliable. Mitigated by: (1) invariant check ensures core agents are always present, (2) hardcoded fallback catches total parsing failures. User confirmed this mitigation is sufficient.

### Q10: Extensibility contradiction

**Resolved: Reframed.** Red team (all 3) flagged that the brainstorm dismisses extensibility as "never used" then designs for it. Reframed: the value isn't third-party plugin extensibility (which hasn't happened) — it's user-defined agents for their own stack (e.g., go-reviewer.md). This is a real, concrete use case.

## Deferred Questions

### Q1: Does the command executor reliably parse subagent_types from its own context?

Approach D depends on the LLM reading its available subagent_types from the system prompt and filtering by naming convention (`*:review:*`, `*:research:*`). Needs validation across context sizes and models.

**Deferred rationale:** The invariant check + hardcoded fallback fully mitigate this risk. Validate empirically during implementation.

## Red Team Resolution Summary

| # | Finding | Severity | Source | Resolution |
|---|---------|----------|--------|------------|
| C1 | Extensibility contradiction | CRITICAL | All 3 | **Reframed** — value is user-defined agents, not third-party plugins (Q10) |
| C2 | Approach A should be primary | CRITICAL | Gemini, Opus | **Disagree** — D serves user-defined agent extensibility. A is fallback with invariant check. User: "I want D so users can add their own review agents." |
| C3 | Agent tool may not exist separately | CRITICAL | Opus, Gemini | **Noted** — both Task and Agent support subagent_type. Agent preferred for `model` parameter (Q7) |
| C4 | model parameter contradicts memory | CRITICAL | Opus | **Fixed** — validated empirically, memory corrected (Q6) |
| C5 | Fallback misses partial omissions | CRITICAL | OpenAI | **Valid — fixed** — added invariant check for core agents (Decision 1) |
| S1 | Skills discovery same fragility | SERIOUS | Opus | **Valid — scope expanded** — skills discovery also migrates (Decision 5) |
| S2 | subagent_type prefix inconsistency | SERIOUS | Opus | **Noted** — likely aliases, validate during implementation (Q8) |
| S3 | LLM self-reading unreliable | SERIOUS | All 3 | **Mitigated** — invariant check + fallback (Q9) |
| S4 | Task already supports subagent_type | SERIOUS | Gemini | **Noted** — Agent preferred for model override capability (Q7) |

**Fixed (batch):** 1 MINOR fix applied (softened `<usage>` validation claim). [see .workflows/brainstorm-research/native-agent-discovery/minor-triage.md]
**Acknowledged (batch):** 5 MINOR findings: #2 bundling deferred to plan, #3 pattern divergence addressed by Q3 (deepen-plan only, voo standardizes later), #4 addressed by Decision 5 (skills in scope), #5 covered by fallback, #6 added to Considered and Rejected. [see .workflows/brainstorm-research/native-agent-discovery/minor-triage.md]

## Considered and Rejected

**Sandbox permission allow-listing:** Configure Claude Code's sandbox to allow `find` on `~/.claude/plugins/cache`. Would fix the approval cascades without code changes. Rejected: sandbox config is per-user and not plugin-controllable — a plugin can't ship this fix. The redundancy argument ("why reconstruct what's natively available?") stands independently of the sandbox trigger.

## Sources

- deepen-plan.md Phase 2 (Steps 2a-2e) — current filesystem discovery implementation
- review.md — hardcoded roster comparison pattern
- CLAUDE.md Agent Registry — existing centralized agent metadata
- Agent tool system prompt — subagent_type descriptions and capabilities
- v2.0.0 changelog — stack-based dynamic agent selection (bead 22l)
- memory/project.md — version history, critical discoveries (model parameter corrected)
- Red team findings: `.workflows/brainstorm-research/native-agent-discovery/red-team--{gemini,openai,opus}.md`
