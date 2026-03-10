---
title: "Add Red Team + Post-Edit Readiness Re-Check to /compound:plan"
date: 2026-03-10
bead: nn3
status: active
---

# What We're Building

Add two new phases to `/compound:plan`:

1. **Phase 6.8: Optional Red Team Challenge** — After readiness checks pass, offer a 3-provider red team (Gemini, OpenAI, Claude Opus) that challenges the plan's reasoning. Same Yes/Skip gate as brainstorm's Phase 3.5. Uses the plan-specific 6-dimension prompt from deepen-plan (not brainstorm's 5-dimension version).

2. **Phase 6.9: Conditional Readiness Re-Check** — If red team edits are applied to the plan, re-run readiness checks to catch edit-induced issues. If no edits were made (user skipped red team or red team found nothing actionable), skip straight to handoff.

3. **Phase 7 Decision Tree Update** — When red team is run and clean (no unresolved CRITICAL/SERIOUS), recommend work regardless of brainstorm origin or step count. Only route to deepen-plan when readiness failed/was skipped or unresolved CRITICAL findings remain.

## Why This Approach

**User rationale:** "goal is to avoid deepen-plan if possible" — deepen-plan repeats most of plan's work and wastes tokens. Its only unique value beyond what plan already does is red team + convergence. Adding red team to plan makes plan self-sufficient for most cases.

**Cost analysis:** Red team is light (~3 calls when clean, ~8-10 when findings exist and edits applied; ~5-6 min clean, ~8-12 min with triage) vs deepen-plan's agent swarm (~20+ calls, ~15-25 min). Adding red team to plan is low-friction — it doesn't make plan meaningfully slower, especially since it's opt-in.

**Deepen-plan's remaining value:** After this change, deepen-plan narrows to "mass specialist review" — 20+ agents analyzing every aspect of the plan. Useful for complex plans that need deep domain expertise, but not needed for most well-structured plans. Both commands keep their own independent red team — no detection logic, each reviews the current plan state.

## Key Decisions

### 1. Scope: Red team + re-check only, not merge with deepen-plan

**Decision:** Add red team + conditional re-check to plan. Do NOT merge plan and deepen-plan into a single command.

**Rationale:** Red team is light (~3-10 calls depending on findings). The agent swarm is heavy (~20+ calls). These are qualitatively different operations with different cost profiles. Merging would make plan enormous (384 → 800+ lines) and load all that complexity even for simple plans. User explored the merge idea and confirmed: "Red team + re-check only." (see brainstorm dialogue)

**Original design intent (Every.to guide):** The plan/deepen-plan split exists for user control — "get quick results first, opt into depth." This change preserves that philosophy while reducing how often deepen-plan is needed.

### 2. Phase ordering: readiness → red team → conditional re-check

**Decision:** Phase 6.7 (readiness) runs first, then Phase 6.8 (red team), then Phase 6.9 (re-check only if edits applied).

**Rationale:** "Readiness checks first catch mechanical/semantic issues. Red team then challenges the cleaned-up plan." (user's stated preference) This means red team reviews a plan that's already mechanically sound, so it focuses on reasoning quality rather than wasting effort on issues readiness would have caught.

**Considered and rejected:** Opus red team argued readiness-first creates double cost (2 readiness passes when edits applied) and that the "cleaned-up plan" rationale is thin since red team reviews reasoning, not mechanical issues. Rejected: the verify-only re-check cost is low (3 bash scripts + 1 lightweight semantic check), and the user explicitly chose readiness-first to ensure consistency.

**Re-check trigger:** Only if the plan document was edited during red team triage. "Why would we do [re-check] if no changes were made? I do want to re-run checks anytime edits are made." (user's exact words)

**Edit detection mechanism:** Compute SHA-256 hash of the plan file before red team triage begins. Compare after triage completes. If hash changed, trigger Phase 6.9 re-check. Implementation detail deferred to planning phase. [Red team fix: added per Gemini red team challenge — original text specified the trigger condition but not the detection mechanism.]

### 3. Decision tree: red team clean → recommend work

**Decision:** If plan passes readiness + survives red team with no unresolved CRITICAL/SERIOUS findings, recommend work. Route to deepen-plan when: readiness check failed/was skipped, OR unresolved CRITICAL/SERIOUS findings remain (from either readiness or red team). [Red team fix: original text said "unresolved CRITICAL" only — SERIOUS findings also trigger deepen-plan routing per Gemini + OpenAI red team challenge.]

**Rationale:** User asked "is [this] safe? why would we do [alternatives]?" — the red team itself validates reasoning quality, which is what the brainstorm-origin check (rule 5) was proxying for. A plan that survives a 3-provider adversarial review is validated regardless of whether a brainstorm preceded it. This dramatically reduces deepen-plan routing.

### 4. Yes/Skip gate: always offer, consistent with brainstorm

**Decision:** Always present "Run a red team challenge?" Yes/Skip gate, matching brainstorm's Phase 3.5 pattern.

**Rationale:** Simple, consistent UX. User chose this over auto-skip (which would have added routing logic) and auto-run (which removes user control). Red team is light enough (~5-6 min) that offering it is low-friction.

### 5. Deepen-plan: keep both red teams independent

**Decision:** Both plan and deepen-plan keep their own independent red team phases. No detection logic for "was red team already run?"

**Rationale:** Each reviews the current plan state. Deepen-plan may run after plan has been further modified. Simplest approach — no inter-command state sharing needed.

### 6. Red team prompt: use deepen-plan's 6-dimension version

**Decision:** Plan's red team uses the 6 plan-specific challenge dimensions from deepen-plan's Phase 4.5 (not brainstorm's 5 generic dimensions).

The 7 dimensions:
1. **Unexamined assumptions** — What does the plan take for granted that might be wrong?
2. **Architecture risks** — Where could the technical approach fail at scale or under pressure?
3. **Missing steps** — What implementation work is implied but not planned?
4. **Dependency risks** — What external factors could derail the plan?
5. **Overengineering** — Where is the plan more complex than necessary? Is it doing more than what was asked? Did research agents or prior analysis introduce unnecessary complexity?
6. **Contradictions** — Do research findings conflict with each other or the plan? Does the plan contradict itself?
7. **Problem selection** — Is this the right problem to solve? Were alternatives to the entire approach considered?

**Rationale:** Dimensions 1-6 originated from deepen-plan but are broadly applicable to any plan context. Dimension 5 covers both orchestrator-introduced and agent-introduced overengineering — same wording works for plan and deepen-plan. Dimension 6 checks inter-research conflicts even with fewer research outputs (low overhead, genuine signal). Dimension 7 was added per Opus red team challenge: rule 5 (no brainstorm → deepen-plan) proxied for problem-selection validation, not just plan quality. Without dimension 7, removing rule 5 leaves no proxy for "are we solving the right problem?"

**Cross-command alignment:** These 7 dimensions should be the canonical set for all plan-level red team reviews (both plan and deepen-plan). Brainstorm's red team should also add a problem-selection dimension — its current "Missing alternatives" asks about solution alternatives, not problem alternatives. [Red team fix: added dimension 7 per Opus challenge. Broadened dimensions 5-6 per MINOR triage discussion.]

### 7. Dispatch syntax: Agent tool (v2.1.0 pattern)

**Decision:** Use `Agent(subagent_type: ...)` dispatch syntax for all new red team code. Do NOT use the older `Task` syntax.

**Rationale:** Deepen-plan migrated to Agent dispatch in v2.1.0. Plan's new code should follow the same pattern. Brainstorm still uses Task syntax (not yet migrated), but new code should use the modern pattern.

### 8. Output paths: plan-research namespace

**Decision:** Red team output files go to `.workflows/plan-research/<plan-stem>/red-team--gemini.md`, `red-team--openai.md`, `red-team--opus.md`. Minor triage goes to `minor-triage-redteam.md`.

**Rationale:** Keeps plan's output separate from deepen-plan's `.workflows/deepen-plan/<plan-stem>/` namespace. Consistent with plan's existing research output directory.

### 9. Phase 6.9 re-check scope: full readiness (not verify-only)

**Decision:** The post-edit re-check runs a full Phase 6.7 readiness pass — all 3 mechanical scripts + full 5-pass semantic agent + reviewer aggregation + consolidator if issues found. Not verify-only mode.

**Rationale:** Red team edits can be structural — restructuring sections, adding implementation steps, revising architecture decisions. These are qualitatively different from consolidator tweaks. "We want to run full readiness after any major edits, regardless of phase." (user's exact words) The verify-only mode was designed for consolidator-scale edits, not adversarial review edits. [Red team fix: originally specified verify-only mode. Changed to full readiness per Opus + OpenAI red team challenge — red team edits can be structural enough to warrant full re-check.]

**Re-check failure path:** If Phase 6.9 re-check finds new CRITICAL/SERIOUS issues (introduced by red team edits), present them to the user for triage — same as Phase 6.7 (resolve now, defer, dismiss). Deferred findings feed into Phase 7 decision tree normally. No special handling needed — the existing readiness machinery handles it. [Red team fix: added per Gemini + Opus red team challenge — original text didn't specify the failure path.]

**Loop cap:** Still capped at 1 re-check cycle. If re-check finds issues → consolidator → user triage → done. No further re-check after the re-check. Per plan-readiness-agents brainstorm: "Re-verification loop capped at 1 cycle to avoid infinite loops."

### 10. Keep red team severity counts separate from readiness counts

**Decision:** The decision tree tracks red team deferred severities as a separate signal from readiness deferred severities. The recommendation message distinguishes them (e.g., "2 CRITICAL red team findings remain" vs "1 SERIOUS readiness finding remains").

**Rationale:** Per context research recommendation: "keeping them separate gives better signal transparency in the feedback log and in the recommendation message." Red team findings are reasoning/architecture issues; readiness findings are structural/consistency issues. Different risk types, different remediation paths.

### 11. Red team input: plan file + research outputs (no synthesis)

**Decision:** Plan's red team reads the plan file directly and may reference research outputs from `.workflows/plan-research/<plan-stem>/agents/`. Unlike deepen-plan's red team, there is no synthesis summary to read (plan doesn't produce one).

**Rationale:** Per context research gap analysis: "deepen-plan's red team reads the enhanced plan + synthesis summary. Plan has no synthesis." The plan file itself is the complete artifact for review.

### 13. Provider failure fallback chain

**Decision:** Explicit degradation chain: 3 providers → Opus-only → red team skipped. Each degradation level noted in the recommendation log.

1. **All 3 providers available** → normal 3-provider red team
2. **Gemini/OpenAI fail** (CLI unavailable, MCP error, timeout) → Opus-only red team (orchestrator is still running, so Opus subagent dispatch still works)
3. **Opus subagent also fails** → treat as "red team was skipped" — decision tree applies normal rules (which may route to deepen-plan per existing rules)

**Rationale:** If the Opus orchestrator itself fails, the whole `/compound:plan` command is dead, not just the red team. So the fallback chain only needs to handle external provider failures and subagent failures. [Red team fix: added per OpenAI challenge — original text didn't specify provider failure behavior.]

### 14. Bead aig dependency: copy dispatch pattern now, refactor later

**Decision:** Copy the red team dispatch pattern from deepen-plan.md Phase 4.5 as-is. Do NOT block on bead aig (red team model selection). When aig ships, it will refactor the pattern across all three commands in a single pass.

**Rationale:** Per context research: "nn3 can copy the current dispatch pattern from deepen-plan.md as-is. When aig ships, it will refactor the pattern across all three commands (brainstorm, deepen-plan, plan) in a single pass." No explicit dependency between nn3 and aig exists in bead graph.

## Resolved Questions

### Q: Should we merge plan and deepen-plan into a single iterative tool?

**Answer: No.** User explored this question: "do we merge plan and deepen-plan into a single iterative tool?" After researching the original design rationale (Every.to guide — user control, opt-into depth) and analyzing the cost difference (red team: ~3 calls, swarm: ~20+ calls), user confirmed: "Red team + re-check only." The merge was rejected because it would make plan enormous and impose the swarm's cost on every plan run.

### Q: Should deepen-plan be deprecated long-term?

**Answer: Not now, but narrowed.** Deepen-plan's unique remaining value is the agent swarm (mass specialist review). This is qualitatively different from red team (adversarial reasoning challenge). Keep both, but deepen-plan becomes truly optional — useful only when plans need deep domain expertise beyond what plan's red team provides.

### Q: Background agent Write permissions

**Discovered during this brainstorm:** Background agents get Write tool permission denied, causing silent failures. Root cause: `.claude/settings.local.json` doesn't include `Write(//.workflows/**)` and `Edit(//.workflows/**)`. Fixed locally for this repo. Captured as bead 3k3 to add to `/compound:setup` and ship recommended permissions.

## Deferred Questions

None — all design questions resolved. Operational follow-ups tracked as beads (3k3, e3x, rkq) in Follow-Up Tasks below.

## Follow-Up Tasks

- **Bead 3k3** (P2): Ship `.workflows/**` Write+Edit permissions in `settings.json` + setup command. Also analyze current permissions to build a recommended baseline that minimizes interactive prompts.
- **Bead e3x** (P3): Define success criteria + measurement for red team effectiveness across all 3 commands. Per OpenAI red team challenge: "red team validates reasoning quality is asserted, not proven."
- **Brainstorm.md red team prompt update:** Add problem-selection dimension to brainstorm's red team (currently 5 dimensions, missing "Is this the right problem?"). Can be done as part of nn3 implementation or as a separate patch.

## Sources

- Repo research: `.workflows/brainstorm-research/plan-red-team-readiness/repo-research.md`
- Context research: `.workflows/brainstorm-research/plan-red-team-readiness/context-research.md`
- Plan command: `plugins/compound-workflows/commands/compound/plan.md`
- Deepen-plan command: `plugins/compound-workflows/commands/compound/deepen-plan.md`
- Brainstorm command: `plugins/compound-workflows/commands/compound/brainstorm.md`
- Every.to compound engineering guide: `https://every.to/guides/compound-engineering`
- Plan readiness agents brainstorm: `docs/brainstorms/2026-03-08-plan-readiness-agents-brainstorm.md`
- Plan deepen recommendation brainstorm: `docs/brainstorms/2026-03-09-plan-deepen-recommendation-brainstorm.md`
- Iteration taxonomy solution: `docs/solutions/process-analysis/2026-03-08-deepen-plan-iteration-taxonomy.md`
- Bead nn3: `bd show nn3`
