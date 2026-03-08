---
title: Context-Lean Enforcement and QA Enhancement
date: 2026-03-08
topic: context-lean-enforcement
---

# Context-Lean Enforcement and QA Enhancement

## What We're Building

Three deliverables in a single plan:

1. **Fix all context-lean violations** — 3 MODERATE (MCP red team wrapping, resolve-pr-parallel disk-persist) + 4 MINOR (documentation naming/conventions)
2. **Create `/compound:plugin-changes-qa` command** — hybrid QA: deterministic scripts for structural checks + LLM agents for semantic analysis. No codebase mutation (writes only to gitignored `.workflows/`).
3. **Add hook-based enforcement** — Claude Code hook in this repo that auto-triggers QA when plugin files change. True enforcement, not just convention.
4. **Track swarms broader review** — mark orchestrating-swarms skill as beta with warning banner, create bead for broader review when swarms go GA.

## Why This Approach

**User's core goal:** "just want to ensure its good and is always run."

**Three enforcement layers:**
- **Convention layer:** AGENTS.md + CLAUDE.md document context-lean as a named principle
- **Command layer:** `/compound:plugin-changes-qa` makes running all checks a one-command action
- **Hook layer:** Claude Code hook auto-triggers QA when plugin source files change — true enforcement that doesn't rely on voluntary invocation

**Why hooks, not just a command:** (Red team finding, all 3 providers) Convention-as-enforcement is documentation, not enforcement. The existing 4 checks in AGENTS.md were documented but violations still occurred — proof that documentation alone is insufficient. A hook ensures QA actually runs.

**Why hybrid static+LLM checks:** (Red team finding, Gemini) Using LLM agents for basic string-matching (stale refs, truncation) is expensive and non-deterministic. Deterministic scripts handle structural checks; LLM agents handle semantic analysis (context-lean architecture, role description quality).

**No codebase mutation:** The QA command writes agent outputs to `.workflows/plugin-qa/` (gitignored) but never modifies source code. Artifacts are retained per retention policy.

**Self-validation reframed:** (Red team finding, Opus) The QA command doesn't validate itself — it validates the codebase. The command's own correctness is verified by manual review during the work plan's quality check phase.

## Key Decisions

### 1. Wrap MCP red team calls in subagents
**Decision:** Wrap Gemini and OpenAI `mcp__pal__clink`/`mcp__pal__chat` calls in `Task general-purpose (run_in_background: true)` subagents that make the MCP call, write the exact unedited response to disk, and return only a summary.

**Empirically validated:** In this brainstorm session, both Gemini and OpenAI red team subagents successfully called `mcp__pal__clink` and wrote results to disk. Subagents DO inherit MCP tool access. (Red team finding invalidated — all 3 providers flagged this as CRITICAL, but empirical evidence confirms it works.)

**Implementation note:** (Red team finding, Gemini) Subagents must write the exact, unedited MCP response to disk before summarizing. This prevents summarization loss — the subagent's summary is for the orchestrator's triage; the full critique on disk is the authoritative record.

**Affects:** brainstorm.md (Phase 3.5), deepen-plan.md (Phase 4.5)

### 2. resolve-pr-parallel gets disk-persist
**Decision:** Add `.workflows/resolve-pr/<pr-number>/agents/` directory and OUTPUT INSTRUCTIONS to each `pr-comment-resolver` dispatch.

**Rationale:** It dispatches agents that return full results to the orchestrator's context — a real (if small) violation of the context-lean principle. The agents' primary output is code changes (committed to git), but the resolution reports also consume context unnecessarily. (Updated rationale per red team: dropped "consistency" framing since swarms is deferred for a different reason — beta status + broad review scope.)

### 3. orchestrating-swarms marked as beta/future
**Decision:** Don't fix the swarms skill now. Add a warning banner noting it's beta and unreviewed for context-lean compliance. Track broader review in a bead for when swarms go GA.

**Rationale (user):** "swarms are in beta right now. the broader review is a future task... to be done when we start testing swarms, likely when they're GA. at that point would do the broader review."

**Interim guardrail:** (Red team finding, OpenAI) Add a warning banner at the top of the skill noting beta status and that the patterns shown don't include disk-persist for teammate outputs. This prevents someone from copying the patterns verbatim without awareness of the gap.

### 4. "Context-lean" becomes the canonical term
**Decision:** Standardize on "context-lean" as the named principle across CLAUDE.md, README.md, and AGENTS.md.

**Agent files — centralized note, not 22 file edits:** (Red team finding, Opus) Instead of adding a one-liner to all 22 agent files (high blast radius, couples agent definitions to a specific pattern), add a single note in CLAUDE.md's agent registry section: "All agents expect callers to include OUTPUT INSTRUCTIONS per the disk-persist-agents skill." One place, not 22.

### 5. Command named `/compound:plugin-changes-qa`
**Decision:** Not `/compound:qa` — more descriptive of what it validates.

**Rationale (user):** "rename it to plugin-changes-qa. it should run just static checks."

### 6. Hybrid QA architecture
**Decision:** The QA command uses two tiers:
- **Tier 1 (deterministic scripts):** Bash/grep scripts for structural checks — stale references, truncation verification, year reference scan, file count validation. Fast, reproducible, zero LLM cost.
- **Tier 2 (LLM agents):** Dispatched agents for semantic checks — context-lean architecture analysis, role description quality, AskUserQuestion completeness. With disk-persist pattern.

**Rationale:** (Red team finding, Gemini) "Using 5 parallel LLM agents for basic string-matching is expensive, slow, and non-deterministic." Scripts for what scripts do well; LLM for what requires reasoning.

### 7. Hook-based enforcement for this repo
**Decision:** Add a Claude Code hook that auto-triggers `/compound:plugin-changes-qa` when commits touch plugin source files (`commands/`, `agents/`, `skills/`).

**Rationale:** (Red team finding, all 3 providers) "Convention-as-enforcement is documentation, not enforcement." A hook ensures QA actually runs without relying on voluntary invocation.

**Scope:** This hook is for the plugin development repo only. It does NOT ship with the plugin to end users.

## Failure Modes

(Added per red team finding, Opus: "No failure mode or rollback analysis")

### MCP wrapping adds latency
**Risk:** Each red team provider now spawns a subagent → initializes → calls MCP → writes to disk → returns. Could add 10-30s per provider.
**Mitigation:** All three providers launch in parallel, so wall-clock time is max(provider latencies), not sum. The current pattern already takes ~60-90s for three red team reviews. Adding subagent overhead of ~5-10s per provider is acceptable.

### Check 5 false positives
**Risk:** The LLM semantic check for context-lean architecture flags a legitimate pattern as a violation.
**Mitigation:** Check 5 reports findings with confidence level and specific evidence (file, line, pattern). The orchestrator presents findings to the user who makes the final call. False positives are annoying but not dangerous — they don't block anything automatically.

### Legitimate in-context MCP usage
**Risk:** A future command legitimately needs to make decisions based on MCP response content before writing to disk. The context-lean principle has no escape hatch.
**Mitigation:** Document an explicit exception: "MCP responses may transit orchestrator context when the orchestrator needs to make routing/triage decisions based on response content before persisting. Document the rationale inline." The principle is "minimize," not "eliminate."

### Hook triggers on irrelevant changes
**Risk:** The hook fires on every commit touching `commands/`, even for typo fixes, adding friction.
**Mitigation:** The hook can check if the changes are substantive (not just whitespace/comments) before triggering a full QA run. Or use a lightweight pre-check that runs only Tier 1 (scripts) and skips Tier 2 (LLM) for trivial changes.

## Scope Summary

### Files to modify (violations)
- `commands/compound/brainstorm.md` — wrap MCP red team in subagents
- `commands/compound/deepen-plan.md` — wrap MCP red team in subagents
- `skills/resolve-pr-parallel/SKILL.md` — add disk-persist pattern

### Files to modify (documentation)
- `plugins/compound-workflows/CLAUDE.md` — add Context-Lean Convention section + centralized agent note
- `plugins/compound-workflows/README.md` — standardize "context-lean" terminology

### Files to modify (swarms interim guardrail)
- `skills/orchestrating-swarms/SKILL.md` — add beta warning banner only

### Files to create
- `commands/compound/plugin-changes-qa.md` — the new QA command (hybrid architecture)
- QA scripts (bash) for Tier 1 structural checks
- Claude Code hook configuration for auto-triggering QA

### Files to update (meta)
- `AGENTS.md` — add Check 5 (context-lean validation), update to reflect hybrid architecture
- `plugins/compound-workflows/CHANGELOG.md` — document changes
- `plugins/compound-workflows/.claude-plugin/plugin.json` — version bump
- `.claude-plugin/marketplace.json` — version bump

### Beads to create
- Track "orchestrating-swarms broader review" for when swarms go GA

### Files NOT to modify
- `agents/**/*.md` (22 files) — centralized note in CLAUDE.md instead (red team finding)
- `skills/orchestrating-swarms/SKILL.md` — beyond the warning banner, deferred to swarms GA
- `docs/plans/2026-02-26-smoke-test-plan.md` — smoke testing is a separate concern
- Any command logic beyond the MCP wrapping fix

## Resolved Questions

**Q: Should the QA command dispatch work to subagents?**
A: Yes for semantic checks (Tier 2). Structural checks (Tier 1) use deterministic scripts. (User chose "hybrid" approach per Gemini's suggestion.)

**Q: Should the swarms skill get a focused fix or broader review?**
A: Neither now. Warning banner added for interim safety. Broader review tracked in bead for swarms GA. (User: "swarms are in beta right now... to be done when we start testing swarms, likely when they're GA.")

**Q: Should agent definition files get the OUTPUT INSTRUCTIONS note?**
A: No — centralize in CLAUDE.md instead. (Red team finding: 22-file blast radius for a one-liner is high; centralized documentation is better.)

**Q: How is QA enforced?**
A: Hook-based. Claude Code hook auto-triggers on commits touching plugin files. (User: "I am thinking hook-based, do you agree?" — red team agreed: all 3 providers said convention-as-enforcement is insufficient.)

**Q: Does the QA command have side effects?**
A: It writes to `.workflows/plugin-qa/` (gitignored) but never mutates source code. (Red team finding: redefine "no side effects" as "no codebase mutation.")

## Red Team Resolution Summary

### CRITICAL (2 findings, both resolved)
1. **MCP subagent wrapping untested** (all 3 providers) — **Invalid.** Empirically confirmed in this session. Both Gemini and OpenAI subagents successfully called `mcp__pal__clink`.
2. **"No side effects" contradicts disk-persist** (Gemini + OpenAI) — **Valid.** Reworded to "no codebase mutation." QA writes to gitignored `.workflows/` only.

### SERIOUS (6 findings, all resolved)
3. **Convention-as-enforcement insufficient** (all 3) — **Valid.** Added hook-based enforcement layer.
4. **Check 5 underspecified** (Opus) — **Valid.** Specified hybrid architecture: deterministic scripts for structural, LLM for semantic.
5. **Self-validating QA is circular** (Opus) — **Disagree.** QA validates the codebase, not itself. QA command correctness is verified by manual review during work plan quality check. (User: "Disagree — reframe.")
6. **Consistency contradiction** (Opus) — **Valid.** Updated rationale for resolve-pr-parallel: real violation, not "consistency." Swarms deferred for different reason (beta + broad scope). (User: "Fix it — update rationale.")
7. **No failure mode analysis** (Opus) — **Valid.** Added Failure Modes section.
8. **Deterministic scripts for structural checks** (Gemini) — **Valid.** Adopted hybrid architecture. (User: "Yes — scripts for structural, LLM for semantic.")

### MINOR (7 findings, all resolved)
- **resolve-pr-parallel non-problem** — Disagree; it's a real (small) violation. Fixed.
- **22-file blast radius** — Valid. Centralized note in CLAUDE.md instead.
- **~30s estimate** — Valid. Removed specific time claim.
- **Preventive enforcement** — Partially addressed by hook-based enforcement.
- **Subagent summarization loss** — Valid. Mandated exact unedited MCP response to disk.
- **File-type inconsistency** — Acknowledged. Agent files are `.md` with YAML frontmatter; AGENTS.md description is loose.
- **Beta deferral risk debt** — Valid. Added warning banner as interim guardrail.

## Sources
- Research: `.workflows/brainstorm-research/context-lean-enforcement/repo-research.md`
- Research: `.workflows/brainstorm-research/context-lean-enforcement/context-research.md`
- Red team: `.workflows/brainstorm-research/context-lean-enforcement/red-team--gemini.md`
- Red team: `.workflows/brainstorm-research/context-lean-enforcement/red-team--openai.md`
- Red team: `.workflows/brainstorm-research/context-lean-enforcement/red-team--opus.md`
- Audit plan: `docs/plans/2026-03-08-fix-context-lean-audit-plan.md`
- Existing QA: `AGENTS.md` (4 parallel checks)
- Smoke test plan: `docs/plans/2026-02-26-smoke-test-plan.md` (13 categories, separate concern)
