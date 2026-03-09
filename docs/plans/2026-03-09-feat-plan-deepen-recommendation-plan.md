---
title: "feat: Plan handoff recommends deepen-plan based on readiness findings"
type: feat
status: active
date: 2026-03-09
origin: docs/brainstorms/2026-03-09-plan-deepen-recommendation-brainstorm.md
---

# Plan: Phase 7 Deepen-Plan Recommendation

**Bead:** 1mx

## Summary

Modify `/compound:plan`'s Phase 7 handoff to recommend whether to run `/compound:deepen-plan` based on Phase 6.7 readiness report findings. Currently Phase 7 presents a static menu with no guidance. After this change, exactly one option gets a `[Recommended]` annotation based on a decision tree that consumes readiness severity counts, deferred findings, consolidation state, and brainstorm existence.

## Scope

- **Modified file:** `plugins/compound-workflows/commands/compound/plan.md` (Phase 7 section only)
- **Versioning files:** plugin.json, marketplace.json, CHANGELOG.md
- **No new agents, commands, scripts, or skills**

## Implementation

### Phase 1: Modify Phase 7 in plan.md

Replace the current Phase 7 section (lines ~297-322) with the updated version below. The changes are:

1. Add a recommendation computation block between the readiness status text and the AskUserQuestion
2. Update the AskUserQuestion options to include `[Recommended]` annotation on exactly one option
3. Replace the readiness status text with a unified recommendation message
4. Add a feedback loop log write after user selection
5. Preserve the existing CRITICAL-deferral warning on option 3

#### Data Sources for Decision Tree

The recommendation logic uses data already available in the orchestrator's context from Phase 6.7 execution:

1. **Severity counts:** The reviewer's return summary (e.g., "Found 7 issues (1 CRITICAL, 3 SERIOUS, 3 MINOR)") is already in context. The LLM orchestrator can extract counts from this format natively — no regex or disk read needed. This is consistent with the brainstorm's "no brittle parsing" constraint (which targeted bash regex, not LLM comprehension).

2. **Deferred finding severities:** The orchestrator is in context for all Phase 6.7 consolidation interactions. When findings are presented to the user and deferred, the orchestrator sees each finding's severity. Carry these forward to Phase 7 by noting: "Track which severities were deferred during Phase 6.7 consolidation for use in the Phase 7 recommendation."

3. **Material modification detection:** Compare the initial reviewer severity counts (from step 1) with the post-verify severity counts (from step 3's verify-mode reviewer return). If the initial report had CRITICAL or SERIOUS findings and the post-verify report has none, the consolidator materially modified the plan.

4. **Post-verify counts (final state):** If verify-mode ran, the verify-mode reviewer's return summary provides the post-consolidation severity counts. If verify was skipped (zero issues initially), the initial counts (all zeros) apply.

#### Decision Tree

The recommendation evaluates the **final state** after Phase 6.7 completes:
- If verify-mode ran: use post-verify severity counts + deferred severities tracked during consolidation
- If consolidator ran but verify didn't: use post-consolidation state
- If no issues found: counts are 0/0/0
- If reviewer failed: treat as "unknown quality"

Additional rules:
- **Deferred findings retain their severity** for recommendation purposes (a deferred CRITICAL is still a CRITICAL risk)
- **Dismissed findings do not count** (user explicitly chose to ignore them — stronger signal than deferral)
- **Material modification:** If initial report had CRITICAL or SERIOUS findings and post-verify report is clean, the consolidator materially modified the plan — recommend deepen-plan

```
Recommendation decision tree (evaluate in order, first match wins):

1. Reviewer failed or skipped
   → Deepen-plan [Recommended]
   → Message: "Readiness check incomplete — deepen-plan recommended to verify plan quality."

2. Any CRITICAL finding remains (active or deferred)
   → Deepen-plan [Recommended]
   → Message: "N CRITICAL findings remain (<check-categories>). Deepen-plan recommended."

3. Any SERIOUS finding remains (active or deferred)
   → Deepen-plan [Recommended]
   → Message: "N SERIOUS findings remain (<check-categories>). Deepen-plan recommended."

4. Consolidator resolved CRITICAL or SERIOUS findings (plan materially modified), verify passed clean
   → Deepen-plan [Recommended]
   → Message: "Plan was modified during readiness checks. Deepen-plan recommended to review changes."

5. No brainstorm origin (plan's `origin:` frontmatter absent or doesn't point to a brainstorm) AND plan has 4+ top-level implementation steps
   → Deepen-plan [Recommended]
   → Message: "No brainstorm preceded this plan. Deepen-plan recommended to catch unvalidated assumptions."

6. Clean or MINOR-only findings, brainstorm exists or plan is small
   → Work [Recommended]
   → Message: "Plan readiness checks passed — ready for work. Deepen-plan available for adversarial review if desired (~2-5 min, agent swarm + red team)."
```

- [ ] Replace current Phase 7 "Plan readiness status" block with unified recommendation message
- [ ] Remove existing "Consider running `/compound:deepen-plan`" text from readiness status (replaced by option annotation)
- [ ] Add `[Recommended]` suffix to exactly one option, matching deepen-plan.md's annotation pattern: `**[Recommended]**` after the em-dash description
- [ ] Preserve the existing CRITICAL-deferral warning suffix on option 3 ("Start `/compound:work`")
- [ ] Recommendation message goes in the handoff text above the AskUserQuestion options (facts + guidance), not inside the option text
- [ ] Cite severity counts and check categories in dirty-plan messages (e.g., "2 CRITICAL (underspecification), 1 SERIOUS (contradictions)")

#### Brainstorm Existence Detection

At Phase 7 time, check the plan file's `origin:` frontmatter field:
- If `origin:` exists and points to a `docs/brainstorms/*.md` file → brainstorm exists
- Otherwise → no brainstorm

This is on disk and survives compaction, unlike relying on in-context memory from Phase 0.

#### Step Count Detection

"Steps" = top-level numbered sections in the plan's implementation section (the ones that become `/compound:work` execution units). These are the same items flagged in the "Work readiness note" assessment.

### Phase 2: Add Feedback Loop Log

After the user selects an option from the AskUserQuestion, write a single entry to the recommendation log:

- [ ] After AskUserQuestion response, append entry to `.workflows/plan-research/<plan-stem>/recommendation-log.md`
- [ ] Entry format:

```markdown
## <date>
- Severity counts: N CRITICAL, N SERIOUS, N MINOR (final state)
- Deferred: N CRITICAL, N SERIOUS (if any)
- Consolidator materially modified plan: yes/no (yes = resolved any CRITICAL or SERIOUS findings per decision tree rule 4)
- Brainstorm origin: yes/no
- Step count: N
- Recommendation: <option> [Recommended]
- User choice: <option selected>
```

### Phase 3: Version Bump and Changelog

- [ ] Bump version in `plugins/compound-workflows/.claude-plugin/plugin.json` (PATCH bump)
- [ ] Bump version in `.claude-plugin/marketplace.json` to match
- [ ] Add CHANGELOG.md entry under new version heading

## Acceptance Criteria

1. When readiness finds CRITICAL or SERIOUS issues (remaining after consolidation), deepen-plan option gets `[Recommended]`
2. When readiness is clean and brainstorm exists (or plan is small), work option gets `[Recommended]`
3. When no brainstorm and 4+ steps, deepen-plan option gets `[Recommended]` even with clean readiness
4. When consolidator materially modified the plan (resolved CRITICAL/SERIOUS), deepen-plan gets `[Recommended]` even if verify passes clean
5. Menu option order stays fixed across all runs (no dynamic reordering)
6. Existing CRITICAL-deferral warning on work option is preserved
7. Feedback loop entry is written after every Phase 7 user selection
8. `[Recommended]` annotation matches deepen-plan.md's suffix pattern

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-03-09-plan-deepen-recommendation-brainstorm.md` — Key decisions: readiness-only signals (Option A), static menu with annotations (not dynamic reordering), de-emphasize don't drop, feedback loop tracking
- **Repo research:** `.workflows/plan-research/plan-deepen-recommendation/agents/repo-research.md` — Phase 7 current state, readiness report format, deepen-plan `[Recommended]` pattern
- **Learnings:** `.workflows/plan-research/plan-deepen-recommendation/agents/learnings.md` — Iteration taxonomy (out of scope for this change but informs signal selection)
- **Specflow:** `.workflows/plan-research/plan-deepen-recommendation/agents/specflow.md` — 16 gaps identified, all resolved (post-verify counts, deferred retention, [Consider]→[Recommended] collapse, origin: frontmatter, feedback format)
