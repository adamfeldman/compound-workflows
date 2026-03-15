# Brainstorm: Assumption Discovery, Verification, and Validation (v2)

**Date:** 2026-03-15
**Beads:** #ytlk (inherited-assumption blind spots), #fyg9 (upstream dependency verification)
**Supersedes:** `docs/brainstorms/2026-03-14-assumption-blind-spots-brainstorm.md` (v1)
**Origin:** `docs/solutions/process-analysis/2026-03-14-inherited-assumption-blind-spots.md`

## What We're Building

An integrated system that discovers, verifies, and validates assumptions across the entire review pipeline — brainstorm, plan, and deepen-plan. This merges two previously separate concerns:

- **Inherited-assumption blind spots (#ytlk):** Implicit premises carried forward from prior work propagate undetected. The pipeline checks what you said, not what you took for granted.
- **Upstream dependency verification (#fyg9):** External dependencies are assumed to work without checking. A 5-minute search would catch publicly known failures before hours of design work.

The unified insight: **assumptions need to be discovered, stated, verified against evidence, and validated analytically — not just surfaced.** Surfacing without verification (v1) leaves the user with a list of assumptions but no way to know which ones are wrong. Verification without discovery (fyg9 alone) only checks what you already know you depend on.

### The Changes

1. **Brainstorm Assumptions section** — always-present section with evidence of categories checked, verification status taxonomy, and cited evidence
2. **Plan Inherited Assumptions section** — always-present section with two subsections: "Carried Forward" (with verification status) and "Newly Identified" (plan-specific)
3. **Plan-readiness Pass 6** — new `inherited-assumptions` semantic check verifying the plan has an Inherited Assumptions section
4. **Unified assumption agent** — a single agent that discovers, verifies, and validates assumptions across all three phases (brainstorm, plan, deepen-plan). Replaces v1's deepen-plan-only assumption-validator.
5. **Red team dimension** — generalized "inherited assumption validation" dimension on plan and deepen-plan red teams, with explicit instruction to challenge assumption evidence and coverage
6. **"Test before designing" principle** — dialogue instruction + agent mandate: verify assumed failures, capabilities, and constraints before committing design decisions
7. **Bead origin metadata** — explicit origin metadata on `/do:work` bead creation (already implemented — commit 80ea033)

### Design Philosophy

**Primary defense (changes 1-3):** Surface and verify assumptions proactively during brainstorm and plan creation. Make the implicit explicit and the unverified verified before it enters the pipeline.

**Active verification (changes 4, 6):** A unified agent discovers what the user doesn't know they depend on, proposes verification scope, and checks against external evidence — with user consent.

**Safety net (changes 5):** Red team challenges assumptions, the verification evidence, and whether any assumptions were missed entirely.

**Layered defense:** Adaptive dialogue (best effort) → verification agent (empirical) → structured output section (forcing function) → readiness check (structural verification) → red team (best-effort safety net). Layers 1, 3, and partially 2 share the same model family and may share failure modes. Layer 4 (structural check) is genuinely independent. Layer 5 (multi-provider red team) uses different models but has already demonstrated failure on this exact problem class — treat it as best-effort, not a reliable independent layer.

**Considered alternatives:**
1. **Reframe existing layers instead of adding new ones.** Rejected: the existing "Unexamined assumptions" dimension already failed even with its current framing. The issue was assumptions being invisible, not poorly framed. Assumption *discovery and verification* (proactive + empirical) is structurally different from assumption *challenging* (reactive).
2. **Do nothing and accept the risk.** Two incidents may represent a low base rate. The audit of prior brainstorms (Decision 8) will test this — if base rate is near zero, the system should be scaled back. See falsifiability condition in Decision 8.
3. **Static checklist instead of an agent.** A checklist ("Have you checked for upstream bugs? Y/N") could catch some cases at minimal cost. Rejected as primary defense because checklists can't *discover* assumptions the user hasn't recognized — but a checklist could be a lightweight fallback if the agent proves too expensive. Worth revisiting if cost/benefit analysis is unfavorable.
4. **Spike-first instead of analyze-first.** In standard development, you write a 10-line spike and run it rather than analyzing assumptions. The pipeline's value is in planning complex multi-phase work where spikes are expensive — but Gemini's challenge is valid: adding more upfront analysis to fix upfront analysis failures has a recursive quality. The circuit breakers and cost model (Decision 3) bound this risk.
5. **Train the user, not the model.** The user already learned to check assumptions (they created fyg9). A one-line reminder might catch most cases. Counter: the user can't be present for every brainstorm in every session — the system needs to work without relying on one person's memory.

## Why This Approach

### The Two Incidents

**Incident 1 (ytlk):** A bead population assumption survived 8+ research agents, a 3-provider red team, and multiple readiness checks because none asked "are these items actually comparable?" The pipeline had no mechanism to surface implicit assumptions.

**Incident 2 (fyg9):** SessionStart hooks were assumed to work through an entire brainstorm → 3 deepen-plan runs → 9 implementation beads. Three open GitHub issues document the failure. The pipeline had no mechanism to verify external dependencies. A second example within the workaround brainstorm showed three more assumptions treated as ground truth without testing — each spawning unnecessary design layers.

### Why Integration

The two incidents expose the same structural gap from different angles:
- ytlk: "we didn't know we were assuming something" (discovery failure)
- fyg9: "we assumed something without checking" (verification failure)

Solving one without the other leaves half the gap open. Discovering an assumption without verifying it produces a list of unknowns. Verifying only what you know you depend on misses the assumptions you don't know you're making.

### Generalization Beyond Software

This is not just about GitHub issues or software dependencies. The same principle applies to any domain:
- A brainstorm about a business process that assumes a regulatory framework still applies
- A plan that assumes a third-party API exists and works as documented
- A design that assumes a user behavior pattern without evidence

The verification mechanism adapts: `gh search issues` for software, web search for regulations, user interview for behavior patterns. The principle is constant: **verify before building.**

### "Test Before Designing" Principle

Three directions of the same principle:
1. **Don't design around assumed failures** — "Before we build a workaround for X being broken, have we confirmed X is broken?" (Caught: v2 workaround brainstorm assumed hooks were fully broken; only exit 2 was.)
2. **Don't build on assumed capabilities** — "Before we build a feature on X, have we confirmed X works?" (Caught: s7qj assumed SessionStart hooks work; they don't.)
3. **Don't accept assumed constraints** — "Before we accept this limitation, have we verified it actually exists?" (General: user says "we can't do X" — is that verified?)

**Bounds:** This principle requires limits to avoid recursive verification of every assumption:
- **Depth limit:** Verify direct dependencies only, not dependencies of dependencies. One level deep.
- **Cost threshold:** If verification would cost more than the risk it mitigates, mark as "unverified" and proceed. The verification agent should estimate effort before starting.
- **Trust defaults:** Do not verify assumptions about language standard libraries, stable OS primitives, or well-established tool behavior. Verify assumptions about external services, upstream tools with known issues, and any capability the design critically depends on.

## Key Decisions

### 1. Always-present sections with verification status taxonomy
**Decision:** Both brainstorm and plan get always-present Assumptions/Inherited Assumptions sections. Each assumption includes a verification status and cited evidence. Empty sections must name the categories the model checked.

**Verification status taxonomy (six levels — evidence sources, not a quality hierarchy):**
- **unverified** — nobody has checked
- **docs-checked** — official documentation confirms it (note: docs can be stale — the fyg9 incident was docs-verified but wrong)
- **user-attested** — user asserts it from direct experience (a real evidence source, not something to override)
- **externally-checked** — searched external sources, no contradicting evidence found (absence of contradiction is not proof — this is the weakest "checked" level)
- **empirically-verified** — tested in this specific context and confirmed working (strongest evidence, but impractical during brainstorm — achievable in plan and deepen-plan phases only)
- **contradicted** — verification found evidence the assumption is wrong. Triggers: severity assessment (blocker vs edge case), surfaced to user immediately, redesign or scope change required before proceeding.

These are evidence sources, not a strict quality hierarchy. Docs-checked can be wrong (fyg9 proved this). User-attested can be outdated. Externally-checked means "no contradicting evidence found," not "confirmed correct." Only empirically-verified actually proves the assumption. All evidence should be viewed with appropriate skepticism.

Evidence includes citations: URLs, quotes from sources, search queries used, issue numbers. Evidence lives in a separate artifact (`verification.md` in the research directory), with a one-line summary + status inline in the Assumptions section.

**Why:** The v1 brainstorm identified that surfacing assumptions without evidence is half the solution — a list of unverified assumptions is only marginally better than no list. The taxonomy distinguishes evidence types so users can calibrate confidence appropriately. Citations make evidence auditable and reproducible.

### 2. Adaptive multi-stage dialogue for assumption surfacing
**Decision:** During brainstorm Phase 1.2, ask about assumptions using a multi-stage adaptive approach with integrated "test before designing" probes. Category list (population, temporal, scope, definitional, environmental) is available as reference. Dialogue includes: "What upstream mechanisms does this design depend on? Have any been tested?" and "Before we design around X not working, have we confirmed it doesn't work?"
**Why:** Carried forward from v1. User's word is a valid verification source — the dialogue helps the user discover assumptions they haven't stated, not interrogate them about what they already know.

### 3. Unified assumption agent across all three phases
**Decision:** One agent that does discovery, verification, and validation. Runs in brainstorm (Phase 1, parallel with research agents), plan (research phase), and deepen-plan (review batch). Lean toward unified; final one-vs-two-agents decision deferred to plan phase with empirical testing.

**Phase behavior:**
- **Brainstorm:** Discovery + quick verification. Identify external dependencies from the feature description and repo context. Propose verification scope. Execute approved verifications.
- **Plan:** Re-verify carried-forward assumptions (things may have changed). Verify new assumptions introduced by concrete implementation decisions.
- **Deepen-plan:** Deep validation + thorough re-verification. Full cross-cutting analysis with research context. Wired to readiness gate — CRITICAL findings block the plan.

**Agent flow (tiered consent):**
1. Agent discovers dependencies from feature description + repo context
2. **Read-only verification runs automatically:** web search, `gh search issues` — low cost, no side effects
3. **Code execution requires explicit consent:** agent proposes scope, user approves before any empirical testing
4. Agent writes findings to `verification.md`
5. Findings feed dialogue and Assumptions section

**Circuit breakers:** Max 3 tool calls per assumption verification. If the agent can't verify within that budget, mark as "unverified" with a note explaining what was attempted. This prevents token exhaustion from scaffolding test harnesses or chasing verification rabbit holes.

**Tools:** Web search, `gh` CLI, and code execution for empirical testing.

**Two-agent alternative (for plan-phase A/B testing):**
If the unified agent proves too broad, the split would be:
- **Assumption-verifier** (empirical): discovery + external verification using web/gh/tests. Runs in all three phases. Has the consent gate and circuit breakers.
- **Assumption-validator** (analytical): cross-cutting consistency analysis. Reads the verifier's output + plan context. Runs in deepen-plan review batch only. Wired to readiness gate.
Two consent gates (one per agent) or a coordinator would be needed. Phase behavior splits along empirical/analytical lines rather than adapting one agent to three modes.

**Why:** v1's assumption-validator ran only in deepen-plan — meaning an entire brainstorm→plan cycle could build on invalid assumptions before anyone checks. Moving validation upstream prevents compounding errors and wasted work. The user expressed concern about over-extending existing agents, so this is a new agent rather than modifying existing ones.

**Note:** This diverges from the solution doc, which recommended modifying existing agents ("not a new agent... existing agents just need the mandate"). The user chose a new agent during v1 brainstorm dialogue because assumption work is a cross-cutting concern that doesn't fit any single existing agent's domain. This brainstorm supersedes the solution doc on this point.

**Cost tradeoff:** One agent adds ~1 file, ~1 registry entry, ~5-15k tokens per phase run. Running in three phases vs one increases total token cost ~3x for the assumption agent. Whether this overhead is justified depends on the base rate of assumption-caused rework — the plan phase must model this: frequency of assumption failures × mean rework cost vs constant overhead of three agent runs. If the audit (Decision 8) finds a near-zero base rate, the three-phase approach should be scaled back to deepen-plan only or a static checklist.

**Testing approach (for plan phase):**
- A/B on known failure case: run both one-agent and two-agent configurations against the SessionStart hooks case. Compare discovery completeness, evidence quality, and analytical depth.
- Quality rubric: define what "good" verification and validation look like. Score both configs on 2-3 brainstorms.
- Cost/quality tradeoff: measure token cost and output quality. If unified is within 80% of split quality at 60% of the cost, unified wins.

### 4. Red team relationship with assumption analysis
**Decision:** The red team challenges three layers: (1) the assumptions themselves, (2) whether the verification agent's evidence is thorough, and (3) whether any assumptions were missed entirely. Red team prompts explicitly instruct: "Aggressively challenge and attempt to invalidate all items listed in the Assumptions and Inherited Assumptions sections. Also challenge the verification evidence: were the right sources checked? Were search terms comprehensive? Could a different search have found contradicting evidence?"
**Why:** The verification agent produces evidence. The red team meta-challenges that evidence. Without meta-challenge, the red team might treat verified assumptions as settled. With it, even "externally-verified" assumptions are targets.

### 5. New readiness Pass 6
**Decision:** Add `inherited-assumptions` as Pass 6 in semantic-checks.md (new pass), not extend Pass 3 (underspecification). verify_only: false.
**Why:** Carried forward from v1. Clean separation of concerns.

### 6. Plan Inherited Assumptions has two subsections
**Decision:** "Carried Forward" (from brainstorm, with verification status per assumption) and "Newly Identified" (assumptions the plan introduces about existing systems). Each entry includes verification level and evidence citation.
**Why:** Carried forward from v1. Extended with verification status from this v2 brainstorm.

### 7. One plan, all changes
**Decision:** Implement all changes in a single plan rather than phased rollout. Add per-change instrumentation so each layer's output is independently observable.
**Why:** Carried forward from v1. Changes are significant in scope (prompt modifications across 4 skill files + 1 new agent file, new verification taxonomy, new evidence artifact format, tiered consent flow) but tightly coupled — the dependency chain means the full system needs to exist to test meaningfully. Per-change instrumentation preserves regression attribution.

### 8. Validation strategy
**Decision:** Test with three named historical cases, audit 3-5 recent brainstorms for base rate, and ship and observe on new work.

**Named test cases:**
1. **SessionStart hooks (fyg9/wxco)** — primary case. Tests both ytlk (surfacing "hooks work" assumption) and fyg9 (discovering GitHub issues). Environmental/upstream dependency assumption.
2. **Permissionless bash generation (dndn)** — assumptions about what triggers Claude Code's permission heuristics required empirical correction. Tool behavior assumption.
3. **Session-worktree v2 "What v1 Got Wrong"** — three false assumptions in one brainstorm (hooks fully broken, EnterWorktree is right tool, model won't comply). Cascading assumption failures.

**Falsifiability condition:** If the audit of 3-5 prior brainstorms finds zero assumption-related gaps, the full three-phase agent system is over-engineered. In that case, scale back to: (a) a static checklist in the brainstorm template + (b) the assumption agent in deepen-plan only. The audit must have a defined exit ramp, not just confirm what we expect to find.

**Why:** Three test cases across three domains (upstream deps, tool behavior, cascading false premises) validate generalization better than N=1. The falsifiability condition prevents building a permanent system for a rare failure mode.

## Assumptions

- **Prompt changes plus empirical verification are sufficient for reliable assumption handling.** [unverified] The always-present section with CoT evidence forces the model to demonstrate analysis. The verification agent provides external evidence. But a model could still cargo-cult the section. Mitigations: CoT reasoning requirement, deterministic detection elements, verification agent with real tools. To verify: test against three named cases.
- **A single unified agent can effectively cover discovery, verification, and validation across three phases.** [unverified] No prior example of a unified agent covering three phases in this codebase. If analysis is too shallow, split into verifier + validator. Plan-phase A/B testing will verify.
- **The "test before designing" principle generalizes beyond software.** [user-attested] The user stated the principle should be general. Evidence beyond software is limited to analogy (regulatory, market research). Empirical verification would require testing on a non-software brainstorm.
- **The pipeline has capacity for additional mechanisms without diminishing returns.** [unverified] The brainstorm adds significant scope to an already multi-layered pipeline. The falsifiability condition (Decision 8) is the mechanism for testing this — if the audit finds low base rate, scale back.
- **The brainstorm Assumptions section and plan Inherited Assumptions section are template-coupled.** [docs-checked] Confirmed by reading both skill files. The plan's Phase 0 carry-forward reads brainstorm content. Format changes to one require updates to the other.
- **Tiered consent (read-only auto, code execution gated) prevents token waste while reducing friction.** [unverified] Replaces the original full-consent gate. No UX testing. May need adjustment based on observed user behavior.

## Open Questions

*(All dialogue questions resolved. Remaining uncertainties — cargo-cult risk, category completeness, agent split decision, consent gate effectiveness — are tracked as assumptions above and remain unverified.)*

## Resolved Questions

1. **Format of Assumptions section** — Always present with verification status taxonomy (5 levels) and cited evidence. Adaptive dialogue during Phase 1.2.
2. **Conditional vs always-present plan section** — Always present, two subsections with verification status per assumption.
3. **Pass 6 vs extend Pass 3** — New Pass 6, clean separation.
4. **Modify existing agents vs new agent** — New unified assumption agent. Discovery + verification + validation in one agent across all three phases.
5. **One agent vs two** — Lean toward unified. Final decision deferred to plan phase with A/B testing, quality rubric, and cost/quality tradeoff analysis.
6. **Brainstorm red team needs new dimension?** — No. The Assumptions section feeds the existing "Unexamined assumptions" dimension.
7. **Red team relationship to assumptions** — Three-layer challenge: assumptions themselves, verification evidence, and coverage gaps.
8. **Agent batch placement** — Brainstorm: Phase 1 parallel. Plan: research phase. Deepen-plan: review batch with readiness gate.
9. **Verification status taxonomy** — Six levels: unverified, docs-checked, user-attested, externally-checked, empirically-verified, contradicted. Evidence sources, not a quality hierarchy. User is a valid evidence source.
10. **Evidence location** — Separate artifact (verification.md), one-line summary + status inline in Assumptions section.
11. **Agent tools** — Full toolset: web search, gh CLI, code execution. Tiered consent: read-only auto, code execution requires approval. Circuit breakers: max 3 tool calls per verification.
12. **"Test before designing" principle** — Both dialogue instruction and agent mandate. Three directions with bounds: depth limit (one level), cost threshold, trust defaults.
13. **Domain generalization** — Not just GitHub issues or software. Any external dependency in any domain.
14. **v1/v2 relationship** — v2 supersedes v1 entirely, with v1 lineage noted.
15. **One plan vs phased rollout** — One plan, all changes. Per-change instrumentation for regression attribution. Scope is significant.
16. **Validation approach** — Three named test cases (SessionStart, permissionless bash, session-worktree v2) + audit with falsifiability condition + ship and observe.

## v1 Lineage

**Decisions carried forward from v1:**
- Always-present Assumptions/Inherited Assumptions sections (Decision 1 — extended with verification taxonomy)
- Adaptive multi-stage dialogue (Decision 2 — extended with "test before designing" probes)
- New readiness Pass 6 (Decision 5/v1 Decision 6 — unchanged)
- Plan two subsections: Carried Forward + Newly Identified (Decision 6/v1 Decision 7 — extended with verification status)
- One plan for all changes (Decision 7/v1 Decision 8 — unchanged)
- Generalized red team dimension, not population-homogeneity-specific (v1 Decision 5 — extended with meta-challenge)

**Decisions revised in v2:**
- v1 Decision 3 (new agent, deepen-plan only) → v2 Decision 3 (unified agent, all three phases). Rationale: deepen-plan-only leaves brainstorm→plan cycle unchecked, allowing compounding errors.
- v1 Decision 4 (review batch, blocking) → v2 Decision 3 (phase-adaptive, consent-gated). Rationale: integrated into the unified agent with phase-specific behavior.
- v1 Decision 9 (test known case + ship and observe) → v2 Decision 8 (known case + different case + audit + ship and observe). Rationale: v1 red team flagged confirmation bias.

**New in v2 (from fyg9 integration):**
- Verification status taxonomy (6 levels with cited evidence, including "contradicted")
- Unified agent with tiered consent → circuit breakers → verification flow
- "Test before designing" principle (three directions, with bounds)
- Domain generalization beyond software
- A/B testing plan for one-vs-two-agent decision (with two-agent alternative sketched)
- Red team meta-challenge (challenge the evidence, not just the assumptions)
- Considered alternatives section (5 alternatives documented)
- Falsifiability condition for the audit
- Three named test cases for validation

## Red Team Resolution Summary

**Providers:** Gemini, OpenAI, Claude Opus (3-provider parallel review; Gemini required retry due to network failure)

| # | Finding | Severity | Resolution |
|---|---------|----------|------------|
| 1 | "Externally-verified" is epistemically weak; missing "invalidated" status | CRITICAL | **Fixed:** Renamed to "externally-checked", added "contradicted" status, defined failure handling |
| 2 | Architecture contradiction: unified agent both declared and deferred | CRITICAL | **Fixed:** Two-agent alternative sketched in Decision 3 for genuine comparison |
| 3 | Code execution has no circuit breakers; token exhaustion risk | CRITICAL | **Fixed:** Max 3 tool calls per verification; mark unverified if can't verify quickly |
| 4 | Pipeline simplification dismissed without consideration | CRITICAL | **Fixed:** 5 considered alternatives documented in Design Philosophy |
| 5 | Consent gate will be rubber-stamped (consent fatigue) | SERIOUS | **Fixed:** Tiered consent — read-only auto, code execution requires approval |
| 6 | "Test before designing" has no bounds or stopping condition | SERIOUS | **Fixed:** Depth limits, cost thresholds, trust defaults added |
| 7 | N=2 evidence base with no falsifiability condition | SERIOUS | **Fixed:** Falsifiability condition added to Decision 8 |
| 8 | Verification taxonomy conflates source with quality | SERIOUS | **Fixed:** Reframed as evidence sources with epistemic caveats per level |
| 9 | Layered defense overstates independence; red team already failed this class | SERIOUS | **Fixed:** Red team reframed as "best-effort safety net" in Design Philosophy |
| 10 | No simpler alternatives considered (checklist, do nothing, spike-first) | SERIOUS | **Fixed:** 5 alternatives documented with rejection rationale |
| 11 | Cost/benefit claim unsubstantiated | SERIOUS | **Fixed:** Cost model requirement added; conditioned on audit base rate |
| 12 | v1 lineage heading says "unchanged" for extended items | MINOR | **Fixed (batch):** Heading changed to "carried forward from v1" |
| 13 | "All questions resolved" overstates certainty | MINOR | **Fixed (batch):** Scoped to "dialogue questions"; noted assumptions remain unverified |
| 14 | "Empirically-verified" impractical during brainstorm | MINOR | **Fixed:** Phase annotation added to taxonomy (achievable in plan/deepen only) |
| 15 | Scope understated as "moderate" | MINOR | **Fixed:** Recharacterized as "significant" |
| 16 | Brainstorm doesn't apply its own verification taxonomy | MINOR | **Fixed:** Verification status added to each assumption |
| 17 | Second test case not identified | MINOR | **Fixed:** Three named test cases: SessionStart hooks, permissionless bash, session-worktree v2 |
| 18 | Domain generalization claimed but not designed for | MINOR | **No action:** Covered by SERIOUS-severity handling; aspiration is acknowledged |
| 19 | Red team vs empirical verification tension | MINOR | **No action:** Intentional design — meta-challenge methodology, not proven facts |
