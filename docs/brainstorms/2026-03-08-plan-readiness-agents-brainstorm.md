---
title: Plan Readiness Agents — plan-readiness-reviewer + plan-consolidator
date: 2026-03-08
type: feature
status: brainstorm
tags: [agents, plan-quality, deepen-plan, work-readiness]
---

# Plan Readiness Agents

## What We're Building

Two new agents that run at the end of every `/compound:plan` and `/compound:deepen-plan` execution to ensure the plan is work-ready — meaning `/compound:work` can execute it without needing additional deepen-plan rounds.

### Agent 1: plan-readiness-reviewer (agents/workflow/)

**Purpose:** Dispatcher/aggregator that discovers check modules, dispatches each as a parallel background agent, collects results from disk, and produces an aggregated work-readiness report.

**Architecture:** Follows the same dispatch pattern as deepen-plan itself — discover → batch dispatch → collect from disk → synthesize. This keeps the main context lean (only sees the aggregated summary).

```
Main context (plan/deepen-plan)
  └─ dispatches plan-readiness-reviewer (foreground)
       └─ discovers check modules from agents/workflow/plan-checks/
       └─ reads project config for enabled/disabled checks
       └─ dispatches N check agents (background, parallel, disk-write)
           ├─ mechanical checks use deterministic scripts (bash/regex)
           └─ semantic checks use LLM agents
       └─ collects results from disk
       └─ writes aggregated report to disk
       └─ returns 2-3 sentence summary to main context
```

**Check modules** (each a `.md` file in `agents/workflow/plan-checks/`):

*Mechanical checks (deterministic scripts — faster, cheaper, reproducible):*
1. **stale-values** — same value (constants, counts, thresholds) appearing in multiple locations with different numbers. If the plan uses a constants-as-data section, verifies references match the defined values.
2. **broken-references** — labels like "(R26)", "(S3)" that point to wrong or non-existent resolutions
3. **audit-trail-bloat** — "Run N Review Findings" sections that contain superseded or contradictory annotations. Ratio of spec-to-annotation text.

*Semantic checks (LLM agents — for judgment-requiring analysis):*
4. **contradictions** — sections that disagree with each other (e.g., step 4 says 3 iterations, step 7 says 2)
5. **unresolved-disputes** — tradeoffs flagged by reviewers that were never explicitly decided. Reads prior gate decisions from `.workflows/` to distinguish settled decisions from ongoing disagreements — does NOT re-flag disputes the user already resolved.
6. **underspecification** — steps too vague for a subagent to execute without judgment calls (missing function signatures, undefined data shapes, unspecified interfaces). This is the only check with clear value at round 1 (before any edits have been made).
7. **accretion** — layered corrections where the same feature has 3+ descriptions at different points in its evolution
8. **external-verification** — verify externally-sourced facts (IRS limits, API behavior, legal thresholds) against current reality via WebSearch. Reads provenance log first to skip recently-verified values. Writes verified results back to provenance log with source, date, plan locations, and confidence level (high/medium/low based on source quality).

**Configuration:** Projects can enable/disable checks and customize verification policy via `compound-workflows.md`:
```yaml
plan_readiness:
  skip_checks: [audit-trail-bloat]  # disable specific checks
  provenance_expiry_days: 30         # how long verified facts are trusted
  verification_source_policy: conservative  # conservative|permissive
  # conservative (default): only trust .gov, official API docs, primary sources
  # permissive: trust blog posts, Stack Overflow, secondary sources
  # Users can add custom instructions for source evaluation
```

**Output:** Aggregated structured markdown report with consistent section headings and severity tags (CRITICAL/SERIOUS/MINOR). Each finding includes: check name, severity, location (section name or line range), description, and suggested fix. plan-consolidator reads this markdown directly.

**Write authority:** Zero plan-file write authority. Metadata writes are permitted (provenance log in `.workflows/`, aggregated report to disk). This distinction is load-bearing for the guardrail model — the reviewer never modifies the artifact under review.

**Category:** `agents/workflow/` — explicitly dispatched by plan/deepen-plan at end-of-run. Not auto-discovered during deepen-plan's Phase 3 review agent batches. This avoids the fragile pattern of putting it in `agents/review/` and requiring a hardcoded filter to skip it.

### Agent 2: plan-consolidator (agents/workflow/)

**Purpose:** Fix issues detected by plan-readiness-reviewer. Applies evidence-based mechanical fixes automatically; flags judgment calls for user decision.

**Auto-fixes (mechanical, evidence-based — no user input needed):**
- Fix broken cross-references (deterministic: target exists or doesn't)
- Strip superseded "Run N" annotations that conflict with current spec text
- Deduplicate stale values **only when provenance makes the correct value unambiguous** (e.g., provenance log confirms IRS limit, or a constants section defines the canonical value). When values conflict and correct answer is ambiguous, route to user via AskUserQuestion.

**Flags for user (guardrailed, requires AskUserQuestion):**
- Ambiguous stale values where correct answer requires domain judgment
- Section rewrites that change meaning (not just cleanup)
- Unresolved design disputes (presents the dispute, asks for a decision to record)
- Spec gaps that need domain knowledge to fill

**Preservation rule:** The consolidator MUST preserve any text that records user decisions and reasoning. Patterns like "Rationale:", "Decision:", "Rejected because:", "User noted:", "Chose X over Y because" are NEVER stripped, only reorganized. User decision rationale is the most valuable content in the plan — misclassifying it as stale annotation is a critical failure mode.

**Section-by-section processing:** To avoid context window exhaustion on large plans (1,500+ lines), the consolidator processes the plan section-by-section. Each section + its relevant findings from the reviewer = one consolidation pass. Sections are reassembled at the end. This prevents the context degradation that motivates the entire architecture.

**Batch decision pattern:** Auto-fixes run first (no user interaction). Then all guardrailed items are presented as a batch at the end, rather than interrupting the user mid-rewrite. This allows the rewrite phase to complete without blocking.

**Category:** `agents/workflow/` — modifies files, dispatched explicitly by plan/deepen-plan, not auto-discovered.

**Input:** Plan file path + plan-readiness-reviewer's structured output file path.

**Output:** Rewritten plan file + consolidation report (what was auto-fixed, what needs user decision).

### Re-verification Loop

After the consolidator finishes, the reviewer runs again in **verify-only mode** (a lightweight subset of checks focused on edit-induced issues: contradictions, stale-values, broken-references). This catches issues the consolidator introduced.

**Loop cap:** Maximum 2 cycles (reviewer → consolidator → reviewer-verify → if issues remain, present to user). The consolidator suffers the same paradox it aims to fix — edits create ~0.5-1.0 new issues per fix. Capping prevents infinite loops. If issues remain after 2 cycles, the user sees the remaining findings and decides.

## Why This Approach

### The Problem (empirically validated from session logs)

Analysis of WhatsNext project sessions (retirement simulator: 8 deepen-plan rounds, stock dashboard: 4 rounds) revealed:

- **Rounds 1-3** find genuine domain errors and architectural bugs (high value)
- **Rounds 4+** mostly find bugs **introduced by the fixing process itself** (~0.5-1.0 new issues created per issue fixed)
- The plan becomes a palimpsest — corrections layered on original text, 3-6 copies of the same value, cross-references that break when numbering changes
- The retirement simulator's plan reached 1,501 lines but only ~700 were actual spec; 420 lines were stale "Run N Review Findings" annotations
- Code-simplicity vs domain-fidelity disputes were re-flagged in runs 2, 3, 4, 5, 6, 7, 8 without ever being resolved

**Note on evidence base:** This analysis is drawn from 2 projects in one domain (financial planning HTML apps). The pattern of edit-induced inconsistencies driving late-round iteration is likely general, but the specific check distribution may need adjustment for other domains. The configurable check modules allow per-project tuning.

### Why Two Agents, Not One

- **Guardrail boundary is the primary justification.** The reviewer has zero plan-file write authority. The consolidator has constrained write authority. This is a clean, enforceable boundary. A single agent with "sometimes write, sometimes don't" is harder to reason about.
- **Separation of concerns.** The reviewer's output is useful even without the consolidator (e.g., user might want to manually fix). The consolidator can't run without the reviewer's input.
- **The "different skills" argument is secondary.** LLMs don't have fixed skills — they follow instructions. But the guardrail boundary and separation of concerns are strong architectural reasons regardless.

### Why Full Agent Dispatch, Not Inline Check

- The parent context is degraded after long gate sessions (processing dozens of findings). Fresh agent context catches what compressed context misses.
- The agent gets the full plan in its context window, not a truncated/compressed version.
- Disk-write pattern means findings survive compaction.
- Follows established architecture — every other verification in the system uses agent dispatch.
- **Exception:** Mechanical checks (broken-references, stale-values, audit-trail-bloat) use deterministic scripts within the agent dispatch. The agent dispatch provides the infrastructure (disk-write, parallel execution); the check itself uses regex/parsing, not LLM inference. This is faster, cheaper, and reproducible for pattern-matching tasks.

### Constants-as-Data Pattern

Plans SHOULD define a constants section for values that appear in multiple locations:

```markdown
## Constants
| Name | Value | Source |
|------|-------|--------|
| CATCH_UP_CONTRIBUTION_LIMIT | $7,500 | IRS Notice 2025-67 |
| SALT_CAP | $40,000 | OBBBA 2025 |
```

When a plan uses this pattern, the stale-values check verifies that all references match the constants section. This prevents the duplication problem at the source rather than detecting it post-hoc. The plan and deepen-plan commands should encourage this pattern when writing plans with repeated domain values.

### Integration Point

Both agents run at the end of **every** `/compound:plan` and `/compound:deepen-plan` execution:

1. Plan/deepen-plan completes its normal phases (including gates, red team, etc.)
2. **plan-readiness-reviewer** runs (foreground — dispatches check agents internally, returns summary)
3. Orchestrator reads reviewer output
4. If issues found: **plan-consolidator** runs (foreground — processes section-by-section, batches user decisions at end)
5. **Re-verify:** Reviewer runs again in verify-only mode (lightweight: contradictions, stale-values, broken-refs only)
6. If re-verify finds issues: present to user (max 2 cycles, then human decides)
7. User reviews consolidated plan via `git diff`
8. Then proceeds to handoff options (start work, deepen further, etc.)

If the reviewer finds zero issues, the consolidator and re-verify are skipped entirely.

**Round 1 note:** Most checks (stale-values, broken-references, audit-trail-bloat, accretion) will find nothing at round 1 because no edits have been made yet. The underspecification check is the primary value at round 1 — it catches steps too vague for subagent execution before any deepen-plan rounds. The overhead of running the full check suite at round 1 is acceptable because mechanical checks are fast (scripts) and LLM checks that find nothing return quickly.

### Operational Constraints

- **Timeout:** Check agents have a 3-minute timeout (consistent with deepen-plan's agent timeout). Timed-out checks are reported as "incomplete" in the aggregated report, not silently dropped.
- **Parallelism cap:** All 8 checks dispatch in parallel (same batch size as deepen-plan). No cap needed at this scale.
- **Estimated cost:** 3 mechanical checks (negligible — script execution) + 5 LLM checks (each reads the plan once, ~comparable to one deepen-plan review agent). Total: roughly 5 additional agent dispatches per plan/deepen-plan run, or ~30-50% increase per run for the reviewer phase. Consolidator adds 1 more agent dispatch.
- **Failure fallback:** If the reviewer fails entirely, the plan/deepen-plan run proceeds to handoff without readiness verification. The user is warned: "Readiness check failed — consider running manually before starting work."
- **Partial results:** If some checks complete and others timeout, the aggregated report includes available findings and notes which checks are incomplete.

## Key Decisions

1. **Two agents, not one** — detection and fixing are separate concerns with different authority levels. Rationale: the reviewer has zero plan-file write authority; the consolidator has constrained write authority. This guardrail boundary is the primary justification — it's clean and enforceable.

2. **Both agents in agents/workflow/** — both are explicitly dispatched by plan/deepen-plan at end-of-run. Neither is auto-discovered during deepen-plan's Phase 3 review agent batches. Rationale: putting the reviewer in `agents/review/` would require a fragile hardcoded filter to skip it during auto-discovery, violating the convention that category = dispatch behavior. All 3 red team providers flagged this as an architectural smell.

3. **Runs at end of every plan/deepen-plan, not just late rounds** — the underspecification check has clear value at round 1. Other checks (stale-values, accretion) add minimal overhead at round 1 because mechanical checks are fast scripts and LLM checks that find nothing return quickly. The goal is work-readiness at every handoff point. Rationale: catching issues early prevents the accretion that causes rounds 4+.

4. **Detect + fix with evidence-based guardrails** — mechanical fixes are auto-applied only when the correct answer is unambiguous (e.g., provenance confirms a value, or a single constants section defines it). Ambiguous cases route to user. Rationale: all 3 red team providers flagged "pick the most recent/correct value" as a domain judgment, not a mechanical task. The evidence rule ensures auto-fixes are truly safe.

5. **External value verification with provenance and confidence** — reviewer verifies externally-sourced facts via WebSearch, tracks results in `.workflows/plan-research/<plan-stem>/provenance.md` with configurable expiry and confidence levels (high/medium/low based on source quality). Default conservative source policy: only trust .gov, official API docs, primary sources. Users can customize via plugin settings. Rationale: session log analysis showed "external info" CRITICALs were actually missed existing facts. But WebSearch reliability varies — false negatives (outdated result marked "verified") are worse than not checking. Confidence levels prevent false confidence.

6. **Structured markdown output** — consistent with all other review agents. No YAML/JSON for agent-to-agent communication. Provenance log uses YAML because it's a structured data store (dates, sources, confidence levels), not agent communication — different artifact, different consumer.

7. **Dynamic dispatch with check modules** — each check is a separate `.md` file in `agents/workflow/plan-checks/`, dispatched as a parallel background agent by the reviewer. Projects configure enabled checks via `compound-workflows.md`. Rationale: (a) reduces main context usage — core rule for all compound skills; (b) immediately configurable and extensible; (c) follows the same discover → dispatch → collect pattern as deepen-plan itself.

8. **Reduce main context usage** — guiding principle for all compound skills. The main context dispatches the reviewer, reads its summary, and dispatches the consolidator if needed. All heavy analysis happens in subagents. Rationale: user-stated rule — context is the scarcest resource.

9. **Mechanical checks use deterministic scripts, semantic checks use LLM agents** — broken-references, stale-values, and audit-trail-bloat are pattern-matching tasks better suited to regex/parsing than LLM inference. Faster, cheaper, reproducible. LLM agents are reserved for judgment-requiring analysis: contradictions, underspecification, disputes, accretion, external verification. Rationale: all 3 red team providers flagged using LLMs for deterministic tasks as wasteful.

10. **Capped re-verification loop (max 2 cycles)** — after consolidation, the reviewer runs again in verify-only mode. If issues remain, they're presented to the user rather than triggering another consolidation. Rationale: the consolidator suffers the same paradox it aims to fix (edits create new issues). Capping prevents infinite loops while ensuring the goal of a clean plan is pursued.

11. **Consolidator preserves user decision rationale** — text recording user decisions/reasoning is NEVER stripped, only reorganized. Rationale: Opus red team flagged that "consolidate layered corrections into clean spec text" could destroy the most valuable content in the plan — the user's stated reasoning behind choices.

12. **Constants-as-data pattern recommended for plans** — plans with repeated domain values should define a constants section. The stale-values check verifies references against it. Rationale: Opus red team noted this prevents the duplication problem at the source. Session log analysis showed values appearing in 3-6 locations as a primary driver of edit-induced inconsistencies.

13. **Check modules read prior decision logs** — the unresolved-disputes check reads prior gate decisions from `.workflows/` to distinguish settled decisions from ongoing disagreements. Rationale: Opus red team flagged that without this, the reviewer would re-litigate decisions the user already made — the exact Category 5 problem from session logs.

14. **Section-by-section consolidation** — the consolidator processes the plan section-by-section to avoid context window exhaustion. Rationale: Gemini red team flagged that a single agent taking a 1,500-line plan + full report hits the same context degradation the architecture tries to avoid.

## Resolved Questions

1. **Q: Should the reviewer run during deepen-plan's regular review agent batches?**
   A: No — it runs at the end of the phase, after all gates have applied their edits. Both agents are in `agents/workflow/` so they are never auto-discovered. Commands explicitly dispatch them at end-of-run.

2. **Q: What if the consolidator introduces its own bugs?**
   A: Capped re-verification loop (max 2 cycles). After consolidation, the reviewer runs again in verify-only mode. If issues remain after 2 cycles, they're presented to the user. The user also reviews via `git diff` before proceeding. Rationale: the consolidator IS an editor and will sometimes create new issues. The cap prevents infinite loops while the re-verify catches regressions.

3. **Q: Should there be a cap on deepen-plan rounds once these agents exist?**
   A: Not yet — let the agents prove their value first. If they reliably make plans work-ready in 2-3 rounds, a cap becomes natural. Premature capping could mask legitimate domain complexity. Rationale: the stock dashboard legitimately needed 4 rounds due to cross-cutting complexity, not process failure.

4. **Q: Should plan-readiness-reviewer verify externally-sourced values (IRS limits, API behavior, legal thresholds)?**
   A: Yes — full external verification via WebSearch with conservative source policy and confidence levels. Analysis of retirement simulator sessions showed run 6 CRITICALs (OBBBA SALT cap, IRS limits) weren't new information — they were existing facts that earlier research rounds missed. Rationale: user corrected the assumption that these were "new legislation" — the OBBBA was already in place, just not caught earlier.

5. **Q: Where should provenance tracking for verified external facts live?**
   A: `.workflows/plan-research/<plan-stem>/provenance.md` — YAML-formatted log of verified facts with source, date, plan locations, confidence level, and configurable expiry (default 30 days). Rationale: research artifacts already live in `.workflows/`, provenance IS research output, the directory persists across runs (never deleted). YAML is appropriate here because provenance is a structured data store, unlike agent output which uses markdown.

6. **Q: Should plan-readiness-reviewer's checks be configurable per project?**
   A: Yes — build dynamic dispatch now. Each check is a separate module in `agents/workflow/plan-checks/`, discovered and dispatched by the reviewer. Projects configure enabled/disabled checks via `compound-workflows.md`. Rationale: dynamic dispatch also solves the "reduce main context usage" principle, and the modular design is not significantly more complex than monolithic when each check is already a self-contained concern.

7. **Q: Should other review agents produce YAML/JSON machine-readable output?**
   A: No — none of the existing 13 review agents use machine-readable output. All use markdown. The plan-readiness-reviewer follows this convention. Rationale: LLMs parse structured markdown reliably; a novel YAML pattern adds complexity without proven benefit.

## Deferred Questions

(None remaining — all questions resolved.)

## Red Team Challenge Summary

**Providers:** Gemini (gemini-3.1-pro-preview), OpenAI (Codex CLI), Claude Opus

**Findings by severity:** 2 CRITICAL, 8 SERIOUS, 9 MINOR

**All findings resolved:**
- C1 (stale value auto-fix not mechanical): **Valid — added evidence rule.** Auto-fix only when provenance makes correct value unambiguous; ambiguous cases route to user.
- C2 (consolidator destroys user rationale): **Valid — added preservation rule.** Text recording user decisions/reasoning is never stripped.
- S1 (consolidator paradox): **Valid — added capped re-verify loop.** Max 2 cycles, then user decides.
- S2 (auto-discovery filter fragile): **Valid — moved both agents to agents/workflow/.** No auto-discovery, no fragile filters.
- S3 (external verification trust model): **Valid — added confidence levels + source policy.** Default conservative; user-customizable.
- S4 (reviewer write authority contradiction): **Valid — clarified.** Zero plan-file write authority; metadata writes (provenance log) permitted.
- S5 (consolidator context exhaustion): **Valid — added section-by-section processing.**
- S6 (settled decisions re-flagged): **Valid — check modules read prior decision logs.**
- S7 (constants-as-data not considered): **Valid — added as recommended plan pattern.**
- S8 (foreground/background inconsistency): **Fixed in text.**
- 9 MINOR findings: All fixed (operational constraints section added, duplicate key decisions merged, YAML distinction explained, two-agent justification strengthened, round-1 overhead addressed, mid-run consolidation noted for future, provenance scaling addressed via expiry + confidence, batch decision pattern added, cost estimate added).

## Sources

- **Session log analysis** (`.workflows/brainstorm-research/fix-verification-agent/session-log-analysis.md`): Empirical analysis of WhatsNext retirement simulator (8 runs) and stock dashboard (4 runs) revealing the five categories of iteration-driving issues
- **Repo research** (`.workflows/brainstorm-research/fix-verification-agent/repo-research.md`): Agent structure patterns, gate mechanics, disk-write conventions, agent category implications
- **Context research** (`.workflows/brainstorm-research/fix-verification-agent/context-research.md`): Cross-referencing plan/deepen-plan architecture, identifying the post-gate verification gap
- **Red team — Gemini** (`.workflows/brainstorm-research/fix-verification-agent/red-team--gemini.md`): 1 CRITICAL, 4 SERIOUS, 1 MINOR
- **Red team — OpenAI** (`.workflows/brainstorm-research/fix-verification-agent/red-team--openai.md`): 1 CRITICAL, 4 SERIOUS, 2 MINOR
- **Red team — Claude Opus** (`.workflows/brainstorm-research/fix-verification-agent/red-team--opus.md`): 1 CRITICAL, 7 SERIOUS, 9 MINOR
