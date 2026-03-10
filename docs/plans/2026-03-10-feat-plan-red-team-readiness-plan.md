---
title: "feat: Add Red Team + Readiness Re-Check to /compound:plan"
type: feat
status: completed
date: 2026-03-10
origin: docs/brainstorms/2026-03-10-plan-red-team-readiness-brainstorm.md
---

# Add Red Team + Readiness Re-Check to /compound:plan

## Problem

The `/compound:plan` command produces plans but has no adversarial validation step. The only way to challenge a plan's reasoning is to run `/compound:deepen-plan`, which repeats most of plan's work (research agents, readiness checks) at high token cost (~20+ agent calls, ~15-25 min). Deepen-plan's unique value is two things: (1) a 20+ agent specialist swarm, and (2) a 3-provider red team. Adding the red team to plan directly makes plan self-sufficient for most cases, narrowing deepen-plan to "deep research augmentation only."

(see brainstorm: docs/brainstorms/2026-03-10-plan-red-team-readiness-brainstorm.md — Decision 1)

## Approach

Add two new phases to plan.md between the existing Phase 6.7 (readiness check) and Phase 7 (post-generation options):

1. **Phase 6.8: Red Team Challenge (Optional)** — Yes/Skip gate, 3-provider parallel dispatch (Gemini, OpenAI, Claude Opus), 7-dimension prompt, CRITICAL/SERIOUS/MINOR triage
2. **Phase 6.9: Conditional Readiness Re-Check** — Only runs if the plan was edited during red team triage (detected via SHA-256 hash comparison). Full readiness pass, not verify-only.
3. **Phase 7 Decision Tree Update** — Red team clean → recommend work. CRITICAL/SERIOUS unresolved → recommend deepen-plan.

Plus cross-command alignment: add 7th dimension (problem selection) to deepen-plan and brainstorm red team prompts.

## Acceptance Criteria

- [ ] Phase 6.8 presents Yes/Skip gate after readiness check
- [ ] 3-provider red team dispatches in parallel using Agent syntax
- [ ] 7-dimension prompt used (all 7 dimensions present)
- [ ] CRITICAL/SERIOUS findings triaged individually with user
- [ ] MINOR findings use three-category triage (fixable/manual/no-action)
- [ ] SHA-256 hash comparison detects plan edits
- [ ] Phase 6.9 runs full readiness (not verify-only) when plan was edited
- [ ] Phase 6.9 skipped when plan unchanged
- [ ] Re-check loop capped at 1 cycle
- [ ] Decision tree routes to work when red team clean (regardless of brainstorm origin)
- [ ] Decision tree routes to deepen-plan when CRITICAL/SERIOUS unresolved
- [ ] Red team severity tracked separately from readiness severity
- [ ] Provider fallback chain works (3 → Opus-only → skipped)
- [ ] Feedback loop tracks red team data
- [ ] Deepen-plan Phase 4.5 updated to 7 dimensions
- [ ] Brainstorm Phase 3.5 updated to add problem-selection dimension
- [ ] CLAUDE.md agent registry updated (red-team-relay dispatched by plan)
- [ ] QA passes with zero findings

## Implementation Steps

### Step 1: Add Phase 6.8 to plan.md — Red Team Challenge

**File:** `plugins/compound-workflows/commands/compound/plan.md`
**Insert after:** Phase 6.7 (line ~302, after "Proceed to Phase 7.")

This is the largest step — Phase 6.8 has 4 sub-steps (gate, dispatch, CRITICAL/SERIOUS triage, MINOR triage). Copy the dispatch pattern from deepen-plan.md Phase 4.5 and adapt for plan's context.

#### 6.8.0: Yes/Skip Gate

Copy the AskUserQuestion pattern from brainstorm.md Phase 3.5:

```markdown
### 6.8. Red Team Challenge (Optional)

**AskUserQuestion:** "Run a red team challenge on this plan? Three different AI models will challenge the reasoning. (~5-6 min when clean, ~8-12 min if findings need triage)"
- **Yes** — proceed with red team
- **Skip** — go directly to Phase 7

**If the user declines**, skip to Phase 7.
```

**If Phase 6.7 readiness check failed:** Still offer the gate, but add context: "Note: readiness check was incomplete. Red team reviews plan reasoning, not structural quality." This preserves user control — they may want adversarial reasoning review even on a plan with known structural issues.

(see brainstorm: Decision 4 — always offer Yes/Skip)

#### 6.8.1: SHA-256 Hash Capture

Before launching red team, capture the plan file hash for later comparison:

```bash
PLAN_HASH_BEFORE=$(shasum -a 256 <plan-path> | cut -d' ' -f1)
```

(see brainstorm: Decision 2 — edit detection mechanism)

#### 6.8.2: Runtime CLI Detection + 3-Provider Dispatch

- [ ] Runtime detection: `which gemini`, `which codex`, check PAL MCP availability
- [ ] Provider 1 — Gemini: `Agent(subagent_type: "compound-workflows:workflow:red-team-relay", model: "sonnet", run_in_background: true, ...)` via `mcp__pal__clink` (clink preferred) or `mcp__pal__chat` fallback
- [ ] Provider 2 — OpenAI: Same pattern, `cli_name: codex` or `mcp__pal__chat` with latest OpenAI model
- [ ] Provider 3 — Claude Opus: `Agent(subagent_type: "general-purpose", run_in_background: true, ...)` — direct file access, NOT PAL
- [ ] All three launched in parallel in a single message
- [ ] Poll for output files: `ls .workflows/plan-research/<plan-stem>/red-team--*.md`
- [ ] Output paths: `.workflows/plan-research/<plan-stem>/red-team--gemini.md`, `red-team--openai.md`, `red-team--opus.md`

**Adaptations from deepen-plan dispatch block** (checklist for implementer):
1. Remove synthesis summary from `absolute_file_paths` — plan has no synthesis
2. Remove `run-<N>` from output paths — plan is not iterative
3. Update prompt to reference "the plan" not "the enhanced plan and its synthesis summary"
4. Set output paths to `.workflows/plan-research/<plan-stem>/red-team--{gemini,openai,opus}.md`
5. For Gemini/OpenAI clink: `absolute_file_paths` contains only the plan file path — passing research files would increase cost and dilute focus
6. For Opus subagent: may optionally read research files at `.workflows/plan-research/<plan-stem>/agents/` for additional context (supports dimension 6 — contradictions between research findings and the plan)
7. No manifest.json updates needed (plan has no manifest)

(see brainstorm: Decision 7 — Agent dispatch syntax, Decision 8 — output paths, Decision 11 — plan file + research as input, Decision 14 — copy deepen-plan pattern)

**7-dimension red team prompt** (adapted from deepen-plan's 6 + brainstorm's Decision 6):

```
You are a red team reviewer for a software implementation plan. Your job is to find flaws, not validate.

Read the plan file. Then identify:
1. **Unexamined assumptions** — What does the plan take for granted?
2. **Architecture risks** — Where could the technical approach fail at scale or under pressure?
3. **Missing steps** — What implementation work is implied but not planned?
4. **Dependency risks** — What external factors could derail the plan?
5. **Overengineering** — Where is the plan more complex than necessary? Is it doing more than what was asked? Did research agents or prior analysis introduce unnecessary complexity?
6. **Contradictions** — Do research findings conflict with each other or the plan? Does the plan contradict itself?
7. **Problem selection** — Is this the right problem to solve? Were alternatives to the entire approach considered?

Be specific. Reference plan sections by name. Rate each finding:
- CRITICAL — Plan will fail or produce wrong outcome if not addressed
- SERIOUS — Significant risk that should be addressed before implementation
- MINOR — Worth noting for awareness
```

(see brainstorm: Decision 6 — 7 dimensions with rationale for each)

**Provider failure fallback chain:**
1. All 3 providers available → normal 3-provider red team
2. Gemini/OpenAI fail → Opus-only red team
3. Opus also fails → treat as "red team was skipped" — decision tree applies normal rules

(see brainstorm: Decision 13 — explicit degradation chain)

#### 6.8.3: CRITICAL and SERIOUS Triage

Copy from deepen-plan Phase 4.5 Step 2:

- [ ] Read all red team files from disk, deduplicate across providers
- [ ] For each CRITICAL or SERIOUS finding, AskUserQuestion:
  - **Valid — update the plan** (edit to address it)
  - **Disagree — note why** (add footnote with counterargument including user's reasoning)
  - **Defer — flag for implementation** (add to Open Questions section with concern)
- [ ] Track deferred severity counts separately as "red team deferred" (distinct from "readiness deferred")
- [ ] **"Deferred" = unresolved** for decision tree purposes. "Valid" and "Disagree" are both resolved (user took action). "Defer" leaves the finding as an open risk. This is consistent with Phase 6.7's existing deferred-severity tracking.

**Provenance pointers:** `[red-team--<provider>, see .workflows/plan-research/<plan-stem>/red-team--<provider>.md]`

(see brainstorm: Decision 10 — separate severity counts)

#### 6.8.4: MINOR Three-Category Triage

Copy from deepen-plan Phase 4.5 Step 3:

- [ ] **Step 3a:** Dispatch Agent subagent to categorize MINOR findings:
  ```
  Agent(subagent_type: "general-purpose", prompt: "...categorize MINOR findings...")
  ```
  Output to: `.workflows/plan-research/<plan-stem>/minor-triage-redteam.md`
  Three categories: Fixable Now (unambiguous + low effort + low risk), Needs Manual Review, No Action Needed
  Fixable items include `old_string`/`new_string` pairs
  Conflict detection: conflicting proposals → both to manual review

- [ ] **Step 3b:** Present three-category triage via AskUserQuestion:
  Options: Apply all fixes + acknowledge (Recommended), Apply specific, Review individually, Acknowledge all
  Omit empty category sections

- [ ] **Step 3c:** Apply accepted fixes with Edit tool (one at a time, sequential). Verify by content comparison. Flag drift.

- [ ] **Step 3d:** Present "needs manual review" items individually (same options as CRITICAL/SERIOUS)

**MINOR provenance formats** (same as deepen-plan):
- Applied: `**Fixed (batch):** M MINOR red team fixes applied. [see .workflows/plan-research/<plan-stem>/minor-triage-redteam.md]`
- Declined: `**Acknowledged (batch):** N MINOR findings accepted (M fixable declined). [see ...]`
- Partial: `**Fixed (batch):** M of N fixable MINOR items applied (items 1, 3). [see ...]`

#### 6.8.5: Timeout Handling

- [ ] Set 5-minute timeout per provider agent. If a provider hasn't produced output after 5 minutes, proceed with whatever providers completed.
- [ ] Log any timeouts in the recommendation log.
- [ ] If all providers time out, treat as "red team failed" and proceed to Phase 7 with red team status "failed."

#### 6.8.6: SHA-256 Hash Comparison

After all triage is complete:

```bash
PLAN_HASH_AFTER=$(shasum -a 256 <plan-path> | cut -d' ' -f1)
if [ "$PLAN_HASH_BEFORE" != "$PLAN_HASH_AFTER" ]; then
  echo "PLAN_CHANGED=true — proceed to Phase 6.9"
else
  echo "PLAN_CHANGED=false — skip to Phase 7"
fi
```

**Note:** The hash comparison is intentionally coarse — any edit triggers re-check, including MINOR fixes. User's explicit instruction: "I do want to re-run checks anytime edits are made." The cost of a false positive (unnecessary re-check after a typo fix) is ~5-10 min; the cost of a false negative (missing structural edit) could result in implementing a broken plan.

### Step 2: Add Phase 6.9 to plan.md — Conditional Readiness Re-Check

**File:** `plugins/compound-workflows/commands/compound/plan.md`
**Insert after:** Phase 6.8

Phase 6.9 only runs if `PLAN_CHANGED=true` from Step 1's hash comparison.

- [ ] Gate: "Plan was modified during red team triage. Running full readiness re-check."
- [ ] Run the same Phase 6.7 readiness dispatch (all 3 mechanical scripts + full 5-pass semantic agent + reviewer + consolidator if issues found)
- [ ] Same triage as Phase 6.7 for any new findings (resolve/defer/dismiss)
- [ ] Track re-check deferred severities alongside readiness and red team severities
- [ ] Loop cap: no further re-check after this cycle. If re-check finds issues → consolidator → triage → done.
- [ ] If plan unchanged, show: "Plan unchanged during red team triage — skipping re-check."

**Re-check output directory:** Write to `.workflows/plan-research/<plan-stem>/readiness/re-check/checks/` (separate from Phase 6.7's `.workflows/plan-research/<plan-stem>/readiness/checks/`). This preserves both readiness passes for traceability — consistent with the project principle "All research outputs are retained for traceability and learning."

**Re-check deferred severities:** Phase 6.9 findings are readiness-type issues (structural/consistency) even though they were caused by red team edits. Track re-check deferred severities under the readiness counter, not the red team counter.

(see brainstorm: Decision 9 — full readiness not verify-only, Decision 2 — re-check trigger)

**Key constraint from brainstorm:** "We want to run full readiness after any major edits, regardless of phase." Verify-only mode was designed for consolidator-scale edits, not adversarial review edits that can restructure sections.

### Step 3: Update Phase 7 in plan.md — Decision Tree

**File:** `plugins/compound-workflows/commands/compound/plan.md`
**Modify:** Phase 7 "Recommendation Computation" section

#### 3a: Additional data to gather at Phase 7 time

Add to existing data-gathering section:
- [ ] **Red team status:** Did red team run? (yes/no from Yes/Skip gate)
- [ ] **Red team deferred CRITICAL count** (from Phase 6.8)
- [ ] **Red team deferred SERIOUS count** (from Phase 6.8)
- [ ] **Plan modified by red team:** yes/no (from SHA-256 comparison)
- [ ] **Re-check ran:** yes/no (from Phase 6.9 conditional)
- [ ] **Re-check deferred severities** (from Phase 6.9, if it ran)

#### 3b: Updated decision tree

The current 6-rule tree becomes a 7-rule tree. Changes:

**New rule (insert as rule 4, before current rule 4):**
> **Red team ran and clean (no unresolved CRITICAL/SERIOUS from red team) AND readiness clean** → Recommend: work
> - Message: "Plan passed readiness checks and survived red team challenge — ready for work."
> - This supersedes rule 5 (no brainstorm + 4 steps) when red team has run and passed.

**Modify current rule 4 (becomes rule 5):**
> Consolidator resolved CRITICAL or SERIOUS findings (plan materially modified) and verify passed clean → Recommend: deepen-plan
> - Keep as-is but renumber.

**Modify current rule 5 (becomes rule 6):**
> No brainstorm origin AND plan has 4+ top-level steps **AND red team was not run or was skipped** → Recommend: deepen-plan
> - Add the "red team not run" guard. If red team ran and was clean, rule 4 already caught this case.

**Current rule 6 (becomes rule 7):**
> Clean or MINOR-only findings, brainstorm exists or plan small → Recommend: work
> - Keep as-is but renumber.

**Updated decision tree (complete):**
1. Reviewer failed or was skipped → deepen-plan
2. Any CRITICAL finding remains (readiness or red team, active or deferred) → deepen-plan
3. Any SERIOUS finding remains (readiness or red team, active or deferred) → deepen-plan
4. **Red team ran and clean (no unresolved CRITICAL/SERIOUS from any source) → work** *(NEW)*
5. Consolidator resolved CRITICAL/SERIOUS + verify clean **+ red team not run** → deepen-plan *(modified from 4)*
6. No brainstorm + 4+ steps **+ red team not run** → deepen-plan *(modified from 5)*
7. Clean or MINOR-only, brainstorm exists or plan small → work *(renumbered from 6)*

**Rule 4 vs Rule 5 interaction:** If Phase 6.7 consolidator materially modified the plan (resolving CRITICAL/SERIOUS) but Phase 6.8 red team then validated the modified plan (clean), rule 4 fires first and recommends work. The red team IS the adversarial validation that rule 5 was routing to deepen-plan for. Rule 5 only fires when consolidator materially modified the plan AND the user skipped red team — leaving the modifications unvalidated.

**Recommendation messages** distinguish red team from readiness:
- "2 CRITICAL red team findings remain (overengineering, problem selection). Deepen-plan recommended."
- "1 SERIOUS readiness finding remains (stale-values). Deepen-plan recommended."
- "Plan passed readiness checks and survived red team challenge — ready for work."

(see brainstorm: Decision 3 — red team clean → work, Decision 10 — separate severity counts)

#### 3c: Updated feedback loop

Add new fields to `.workflows/plan-research/<plan-stem>/recommendation-log.md`:

```markdown
## <date>
- Readiness severity counts: N CRITICAL, N SERIOUS, N MINOR (final state)
- Readiness deferred: N CRITICAL, N SERIOUS (if any)
- Red team ran: yes/no
- Red team severity counts: N CRITICAL, N SERIOUS, N MINOR (if ran)
- Red team deferred: N CRITICAL, N SERIOUS (if any)
- Plan modified by red team: yes/no
- Re-check ran: yes/no
- Consolidator materially modified plan: yes/no
- Brainstorm origin: yes/no
- Step count: N
- Recommendation: <option> [Recommended]
- User choice: <option selected>
```

### Step 4: Update CLAUDE.md — Agent Registry

**File:** `plugins/compound-workflows/CLAUDE.md`

- [ ] In the Agent Registry table, update `red-team-relay`'s "Dispatched By" column from `brainstorm, deepen-plan` to `brainstorm, deepen-plan, plan`
- [ ] No new agents are created. Agent count remains 26.

### Step 5: Update deepen-plan.md — Add 7th Dimension

**File:** `plugins/compound-workflows/commands/compound/deepen-plan.md`
**Modify:** Phase 4.5 red team prompt in all 5 variants (Gemini clink, Gemini chat, OpenAI clink, OpenAI chat, Opus subagent)

- [ ] Read `deepen-plan.md` Phase 4.5 to identify current dimension 5 and 6 text in each variant. Current dimension 5 is likely "Overengineering — Where is the plan more complex than necessary?" and dimension 6 is likely "Contradictions — Do research findings conflict with each other or the plan?"
- [ ] Replace dimension 5 with expanded version: "Where is the plan more complex than necessary? Is it doing more than what was asked? Did research agents or prior analysis introduce unnecessary complexity?"
- [ ] Replace dimension 6 with expanded version: "Do research findings conflict with each other or the plan? Does the plan contradict itself?"
- [ ] Add dimension 7 to the red team prompt in each variant:
  ```
  7. **Problem selection** — Is this the right problem to solve? Were alternatives to the entire approach considered?
  ```
- [ ] Update any count references from "6" to "7" in surrounding text

(see brainstorm: Decision 6 — "These 7 dimensions should be the canonical set for all plan-level red team reviews")

### Step 6: Update brainstorm.md — Add Problem-Selection Dimension

**File:** `plugins/compound-workflows/commands/compound/brainstorm.md`
**Modify:** Phase 3.5 red team prompt in all 5 variants (Gemini clink, Gemini chat, OpenAI clink, OpenAI chat, Opus subagent)

- [ ] Insert dimension 6 after the existing dimension 5 in each prompt variant:
  ```
  6. **Problem selection** — Is this the right problem to solve? Were alternatives to the entire approach considered?
  ```
- [ ] Do NOT change the text of existing dimensions 1-5 — brainstorm's dimensions describe design concerns, not implementation concerns
- [ ] Do NOT change dispatch syntax — brainstorm still uses Task (migration is a separate effort per v2.1.0 pattern)

**Note:** Brainstorm's red team dimensions are intentionally different from plan's. Brainstorm challenges the *design* (assumptions, alternatives, arguments, risks, contradictions, problem selection). Plan challenges the *implementation* (assumptions, architecture, missing steps, dependencies, overengineering, contradictions, problem selection). The "problem selection" dimension is shared across both.

(see brainstorm: Decision 6 — "Brainstorm's red team should also add a problem-selection dimension")

### Step 7: Version Bump + CHANGELOG + QA

- [ ] Bump version from 2.1.0 to 2.2.0 in `plugins/compound-workflows/.claude-plugin/plugin.json` (MINOR bump — new feature, no breaking changes)
- [ ] Bump version from 2.1.0 to 2.2.0 in `.claude-plugin/marketplace.json`
- [ ] Update `plugins/compound-workflows/CHANGELOG.md` with entry for v2.2.0
- [ ] Verify `plugins/compound-workflows/README.md` component counts (agents: 26, skills: 19, commands: 8 — no count changes expected)
- [ ] Run `/compound-workflows:plugin-changes-qa` — all checks must pass with zero findings

## Technical Considerations

### Line Count Impact

plan.md is currently ~384 lines. Phase 6.8 will add ~200-250 lines (gate + dispatch + triage patterns). Phase 6.9 will add ~30-40 lines (conditional re-run reference). Phase 7 updates will add ~20-30 net lines. Total: plan.md grows to ~650-700 lines.

This is significant but unavoidable — the red team dispatch pattern requires explicit per-provider blocks for clink/chat variants. When bead aig ships (red team model selection refactor), the dispatch blocks will shrink via skill reference.

### Execution Order Guarantee

Phase ordering is critical:
1. Phase 6.7 (readiness) — catch mechanical/semantic issues first
2. Phase 6.8 (red team) — challenge reasoning on a clean plan
3. Phase 6.9 (re-check) — verify edits didn't introduce new issues
4. Phase 7 (decision tree) — consume all signals for recommendation

Each phase depends on the prior one's output. No parallelization possible between these phases.

### Context Lean Compliance

All red team dispatches use the disk-persist pattern:
- Relay agents (Gemini, OpenAI) write MCP responses to disk, return 2-3 sentence summary
- Opus subagent writes findings to disk, returns 2-3 sentence summary
- MINOR triage subagent writes categorization to disk, returns summary
- Orchestrator reads files from disk, never receives full agent output in context

### Existing Dispatch Style

plan.md currently uses `Task` dispatch syntax throughout (pre-migration). Phase 6.8's new code uses `Agent(subagent_type: ...)` syntax per brainstorm Decision 7. This creates a style inconsistency within plan.md — the existing research dispatches use Task while the new red team dispatches use Agent. This is acceptable: the migration will be done command-by-command (as with deepen-plan in v2.1.0). A future migration pass can convert plan.md's research dispatches to Agent syntax.

## Risks

1. **plan.md grows to ~700 lines** — Large prompt files can cause LLM attention drift. Mitigated by clear phase numbering and section headers. Will shrink when aig refactors dispatch into a skill.
2. **SHA-256 hash comparison is coarse** — any edit triggers re-check, even whitespace-only changes. Acceptable: false positive (unnecessary re-check) is cheap; false negative (missing structural edit) is expensive.
3. **Re-check adds ~5-10 min when triggered** — Full readiness pass is not free. But it only runs when the plan was actually modified, and the user explicitly chose to run red team. Opt-in cost.

## Out of Scope

- Merging plan and deepen-plan into a single command (explicitly rejected — see brainstorm Decision 1)
- Migrating plan.md's existing Task dispatches to Agent syntax (separate migration effort)
- Red team model selection/precedence chain (bead aig — copy pattern now, refactor later)
- Brainstorm.md dispatch syntax migration to Agent (separate from adding dimension 6)
- `listmodels` call before dispatch (aig will add this)
- Detecting whether red team was already run by another command (Decision 5 — independent red teams)

## Sources

**Origin brainstorm:** `docs/brainstorms/2026-03-10-plan-red-team-readiness-brainstorm.md` — 14 key decisions, all resolved. Key decisions carried forward: scope (Decision 1), phase ordering (Decision 2), decision tree update (Decision 3), Yes/Skip gate (Decision 4), independent red teams (Decision 5), 7-dimension prompt (Decision 6), Agent dispatch (Decision 7), output paths (Decision 8), full re-check (Decision 9), separate severity counts (Decision 10), plan-only input (Decision 11), provider fallback (Decision 13), copy dispatch pattern (Decision 14).

**Research files:**
- `.workflows/plan-research/plan-red-team-readiness/agents/repo-research.md` — Current plan.md structure, deepen-plan Phase 4.5 dispatch pattern, brainstorm Phase 3.5 gate pattern, agent definitions, readiness check scripts
- `.workflows/plan-research/plan-red-team-readiness/agents/learnings.md` — 7 relevant institutional learnings, implementation path, gotchas to avoid
- `.workflows/plan-research/plan-red-team-readiness/agents/context-research.md` — 10+ relevant documents across brainstorms, plans, solutions, memory
- `.workflows/plan-research/plan-red-team-readiness/agents/specflow.md` — 24 gaps identified across 7 categories. Critical gaps resolved: MINOR edit trigger (Gap 1), rule ordering (Gaps 4-6), deferred semantics (Gap 7), file scope for providers (Gap 9), re-check output dir (Gap 13), timeout handling (Gap 21), readiness-failed gate behavior (Gap 23)

**Related docs:**
- `docs/brainstorms/2026-03-09-plan-deepen-recommendation-brainstorm.md` — Phase 7 decision tree design (bead 1mx, shipped v1.9.1)
- `docs/brainstorms/2026-03-08-plan-readiness-agents-brainstorm.md` — Phase 6.7 architecture (shipped v1.7.0)
- `docs/solutions/process-analysis/2026-03-08-deepen-plan-iteration-taxonomy.md` — Empirical basis for feature
- `docs/brainstorms/2026-03-09-minor-triage-fixable-vs-defer-brainstorm.md` — Three-category triage pattern
- `docs/brainstorms/2026-03-08-red-team-model-selection-brainstorm.md` — Dispatch pattern and model selection (bead aig)
