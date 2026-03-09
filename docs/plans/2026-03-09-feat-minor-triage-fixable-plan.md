---
title: "feat: Three-category MINOR triage with fix proposals"
type: feat
status: active
date: 2026-03-09
origin: docs/brainstorms/2026-03-09-minor-triage-fixable-vs-defer-brainstorm.md
---

# Plan: Three-Category MINOR Triage

**Bead:** 12j

## Summary

Replace the binary MINOR triage ("batch-accept or review individually") with a three-category pattern: a subagent categorizes each MINOR finding as "fixable now" (with a proposed edit), "needs manual review" (present individually), or "no action needed" (acknowledge with reason). Update 3 files across 4 triage points. No new agents or skills — uses inline subagent dispatch at 3 points and inline categorization at the 4th (plan-consolidator).

## Scope

**Modified files:**
- `commands/compound/brainstorm.md` — Phase 3.5 Step 3
- `commands/compound/deepen-plan.md` — Synthesis Gate Step 4 + Red Team Step 3
- `agents/workflow/plan-consolidator.md` — Section 6 (guardrailed MINOR batch)
- Version files: `plugin.json`, `marketplace.json`, `CHANGELOG.md`

**Out of scope** (see brainstorm Decision 3):
- Changing severity system (CRITICAL/SERIOUS/MINOR stays as-is)
- Auto-fixing without user confirmation
- Changing how CRITICAL/SERIOUS items are triaged individually

## Shared Definitions

### Fixability Criteria (Aligned — see brainstorm Decision 8)

All three must hold for a MINOR finding to be "fixable now":

1. **Unambiguous** — only one reasonable fix exists
   - Pass: "Add rationale for X exclusion → append one sentence to Decision 5"
   - Fail: "Decide whether env vars should supplement or replace the config approach"
2. **Low effort** — a one-line or few-line edit, not a structural change
   - Pass: "Rename 'cache' to 'context retention' in one section"
   - Fail: "Restructure the precedence chain to address conflict handling"
3. **Low risk** — safe to change without ripple effects; no user decisions or reasoning involved
   - Pass: "Add review.md to the Out of Scope list"
   - Fail: "Change a term used in 5+ other documents"

**Alignment with plan-consolidator:** The consolidator's existing auto-fix criteria (Section 4: unambiguous + evidence-based + no user judgment) remain as the **stricter tier** for automatic application without user confirmation. The three-category fixability criteria apply to the **guardrailed MINOR tier** — items that failed auto-fix but are still simple enough to fix with user confirmation. The consolidator gains a middle tier between "auto-fix" and "present individually."

(See brainstorm Decision 2 for criteria rationale, Decision 8 for alignment rationale.)

### Three Categories

| Category | Semantics | User Action |
|----------|-----------|-------------|
| **Fixable now** | Meets all 3 criteria; subagent proposes concrete edit | Apply (batch or cherry-pick) or decline |
| **Needs manual review** | Valid finding but fails ≥1 criterion | Present individually (Valid/Disagree/Defer) |
| **No action needed** | Observation with no concrete edit implied | Acknowledge with reason (not an issue / actively disagree / already resolved) |

**Synthesis gate variant:** At the synthesis gate (deepen-plan Step 4), semantics are inverted because MINOR changes are already applied to the plan. "Fixable now" = the synthesis change needs a small correction or revert (subagent proposes the corrective edit). "No action needed" = the synthesis change was appropriate, keep as-is. "Needs manual review" = the change needs complex adjustment. The categories and UX structure are the same; the subagent prompt is tailored to review existing changes rather than propose new ones.

### Categorization Output Format

The subagent writes a structured file to disk. Numbers are sequential across all categories to support cherry-pick references (e.g., "Apply 1, 3"):

```markdown
# MINOR Triage Categorization

## Summary
- Total: N MINOR findings
- Fixable now: M items
- Needs manual review: K items
- No action needed: J items

## Fixable Now

### 1. [Finding summary]
- Source: [provider or synthesis agent]
- Proposed fix: [concrete edit — what to change, where in the document]
- Location: [section/heading in target document]

### 2. [Finding summary]
...

## Needs Manual Review

### M+1. [Finding summary]
- Source: [provider or synthesis agent]
- Why manual: [which fixability criterion fails]

## No Action Needed

### M+K+1. [Finding summary]
- Source: [provider or synthesis agent]
- Reason: [not an issue / actively disagree / already resolved]
```

### Presentation Template

The orchestrator reads the categorization file from disk and presents to the user. Omit any empty category section. If zero fixable items, remove the "Apply all" option and shift recommendation to option 3 or 4.

```
"N MINOR findings from [source]:

**Fixable now** (M items):
1. [summary] → [proposed edit]
2. [summary] → [proposed edit]

**Needs manual review** (K items):
3. [summary]

**No action needed** (J items):
4. [summary] — [reason]

What would you like to do?"

Options:
1. Apply all fixes + acknowledge no-action items (Recommended)
2. Apply specific fixes (e.g., "1, 2") + acknowledge rest
3. Review all individually
4. Acknowledge all (no fixes)
```

After the batch decision:
- Applied fixes → orchestrator applies via Edit tool, then runs post-fix verification
- "Needs manual review" items → present individually with Valid/Disagree/Defer options (same options as CRITICAL/SERIOUS — see brainstorm Decision 3)
- "No action needed" items → recorded as acknowledged with reason

**Partial acceptance parsing:** The orchestrator interprets the user's natural language response (e.g., "1, 3", "all except 2", "first two"). If ambiguous, ask for clarification rather than guessing.

### Fix Application + Post-Fix Verification

After the user confirms which fixes to apply:

1. Orchestrator applies each accepted fix using the Edit tool (one edit per fix, sequential)
2. After all edits applied, re-read the modified sections of the document
3. Verify each applied edit matches the proposal by content (not line number — earlier edits may shift lines)
4. If drift detected (edit doesn't match proposal), flag to user before proceeding

**Synthesis gate reverts:** For synthesis MINORs where the fix is to revert the synthesis change, the categorization output must include both the synthesis-applied text (as `old_string` for Edit tool) and the original pre-synthesis text (as `new_string`). The subagent obtains the original text from the synthesis summary file (`.workflows/deepen-plan/<stem>/run-<N>-synthesis.md`), which records what was changed. For corrections (not full reverts), the subagent provides the synthesis-applied text as `old_string` and the corrected text as `new_string`.

(See brainstorm Decision 6 for verification rationale. Consistent with plan-consolidator Section 10 re-verify pattern.)

### Context-Lean Consideration

Reading the categorization file into orchestrator context is a bounded-read exception to the context-lean convention. The file size is proportional to MINOR finding count (typically 3-10 items, ~50-100 lines). This is comparable to reading the readiness reviewer's summary, which the orchestrator already does. The exception should be documented in the context-lean convention section of CLAUDE.md when implemented.

### Provenance Formats

Extend the existing provenance annotation system (from finding-resolution-provenance, v1.9.1):

- **Applied fixes:** `**Fixed (batch):** M MINOR fixes applied. [see <categorization-file>]`
- **No-action items:** `**Acknowledged (batch):** J MINOR findings, no action needed. [see <categorization-file>]`
- **User declines all proposed fixes:** `**Acknowledged (batch):** N MINOR findings accepted (M fixable declined). [see <categorization-file>]`
- **Partial acceptance:** `**Fixed (batch):** M of N fixable MINOR items applied (items 1, 3). [see <categorization-file>]`
- **Manual review items:** individual resolution lines using existing CRITICAL/SERIOUS format

Brainstorm triage points use inline annotations (no provenance pointers — brainstorm docs are written once, see repo-research finding §1a). Deepen-plan triage points use provenance pointers following the existing `[see .workflows/...]` convention.

### Edge Cases

- **Zero fixable items:** Omit "Fixable now" section. Remove "Apply all fixes" option. Recommend "Review all individually" if manual-review items exist, or "Acknowledge all" if only no-action items.
- **All fixable items:** Omit empty sections. "Acknowledge rest" in option 2 has nothing to acknowledge.
- **Conflicting proposals:** If two fixable items propose conflicting edits to the same section, re-categorize both as "needs manual review" with the conflict noted. The subagent should detect this during categorization.
- **User rejects all proposed fixes:** Record as `**Acknowledged (batch):**` with "(M fixable declined)" annotation.

## Implementation

### Phase 1: Update brainstorm.md (Phase 3.5 Step 3)

Replace the binary MINOR triage at lines ~315-325 with three-category pattern.

- [ ] Add inline `Task` subagent dispatch block for MINOR categorization before the AskUserQuestion. The subagent reads the 3 red team files from `.workflows/brainstorm-research/<topic-stem>/` and the brainstorm document, filters to MINOR-severity findings, categorizes each using the fixability criteria, proposes fixes for fixable items, and writes output to `.workflows/brainstorm-research/<topic-stem>/minor-triage.md`. The dispatch prompt must include: (a) the fixability criteria and categorization output format from the Shared Definitions sections above, (b) instruction to read all red team files and filter to MINOR findings by severity, (c) instruction to read the brainstorm document to propose location-specific edits, (d) OUTPUT INSTRUCTIONS per disk-persist-agents pattern (write to specified path, return only 2-3 sentence summary). Use `Task` with `run_in_background: true` — this is an inline dispatch, not a named agent.
- [ ] Replace binary AskUserQuestion ("batch-accept or review individually") with the three-category presentation template. Orchestrator reads categorization file from disk and constructs the presentation.
- [ ] Add fix application instructions: after user confirms, orchestrator applies accepted fixes to the brainstorm document via Edit tool.
- [ ] Add post-fix verification: re-read modified sections, verify edits match proposals.
- [ ] After "needs manual review" items, present individually with the existing Valid/Disagree/Defer options (same as CRITICAL/SERIOUS in brainstorm.md's red team Step 2).
- [ ] Handle edge cases: zero fixable, all fixable, conflicting proposals (per Edge Cases section above).
- [ ] Brainstorm uses inline annotations (no provenance pointers) — applied fixes get noted in the Red Team Resolution Summary table.

### Phase 2: Update deepen-plan.md (both triage points)

**Synthesis Gate Step 4** (lines ~328-343):

- [ ] Add subagent dispatch for synthesis MINOR categorization. The subagent receives a variant prompt: instead of proposing NEW edits, it reviews the synthesis agent's MINOR changes already applied to the plan and categorizes them. "Fixable now" means the synthesis change needs a small correction or revert. "No action needed" means the change was appropriate (keep as-is). Subagent reads the synthesis summary from `.workflows/deepen-plan/<stem>/run-<N>-synthesis.md` and the current plan, writes output to `.workflows/deepen-plan/<stem>/agents/run-<N>/minor-triage-synthesis.md`.
- [ ] Replace binary AskUserQuestion ("batch-accept or review individually") with three-category presentation. For synthesis MINORs, "Apply fix" means applying a correction to the already-applied synthesis change (not applying the original finding).
- [ ] Add fix application + post-fix verification for accepted corrections/reverts. For reverts, the categorization output includes both synthesis-applied text (`old_string`) and pre-synthesis original text (`new_string`) sourced from the synthesis summary file. For corrections, synthesis-applied text as `old_string` and corrected text as `new_string`.
- [ ] Update provenance format: `**Fixed (batch):** M MINOR synthesis corrections applied. [see .workflows/deepen-plan/<stem>/agents/run-<N>/minor-triage-synthesis.md]`. Replace existing `**Acknowledged (batch):**` line with the appropriate new format.
- [ ] Preserve existing deepen-plan Step 5 "Apply" logic — resolution lines for all verdicts remain.

**Red Team Step 3** (lines ~589-598):

- [ ] Add subagent dispatch for red team MINOR categorization (same structure as brainstorm variant). Subagent reads 3 red team files from `.workflows/deepen-plan/<stem>/agents/run-<N>/` and the plan, writes output to `.workflows/deepen-plan/<stem>/agents/run-<N>/minor-triage-redteam.md`.
- [ ] Replace binary AskUserQuestion with three-category presentation template.
- [ ] Add fix application + post-fix verification.
- [ ] Update provenance format: replace existing `**Acknowledged (batch):**` line with appropriate new formats. Provider attribution on provenance pointers follows existing convention: `[see .workflows/deepen-plan/<stem>/agents/run-<N>/red-team--<provider>.md]`.
- [ ] After "needs manual review" items, present individually with existing deepen-plan red team Step 2 options (Valid/Disagree/Defer).

### Phase 3: Update plan-consolidator.md (Section 6)

Update Section 6 "Batch User Decisions (Guardrailed Items)" to use three-category inline categorization for MINOR items.

- [ ] Replace binary MINOR batch ("present as a batch with an accept-all option") with inline three-category categorization. The consolidator already has all findings in context — no subagent dispatch needed (nested dispatch doesn't work). Consolidator categorizes MINOR guardrailed items using the shared fixability criteria.
- [ ] Update fixability criteria language: add shared criteria (unambiguous + low effort + low risk) as the classification standard for MINOR guardrailed items. Clarify relationship to auto-fix criteria (Section 4): auto-fix is the stricter tier (automatic, no confirmation); fixable-now is the lighter tier (with user confirmation).
- [ ] Add three-category presentation via AskUserQuestion (same template as other triage points, adapted for readiness context).
- [ ] Add fix application for fixable guardrailed MINORs (consolidator applies via Edit tool, consistent with its existing Section 5 mechanics).
- [ ] Add a new Section 10d "Batch-fix content check" to the existing re-verify pass: after applying MINOR batch fixes, verify each applied edit matches its proposal by content comparison (not line number). This is distinct from 10a (preservation patterns), 10b (accretion), and 10c (size change).
- [ ] Note that conflicting fixable items across the same plan section should route to "needs manual review."
- [ ] If AskUserQuestion is unavailable (per existing Section 6 fallback), write all three categories to the consolidation report with status `requires-user-decision` and return to parent command.

### Phase 4: Version bump + changelog

- [ ] Bump version in `plugin.json`: 1.9.1 → 1.10.0 (MINOR: new behavior in existing commands)
- [ ] Bump version in `marketplace.json` to match
- [ ] Add CHANGELOG.md entry under `[1.10.0]` heading
- [ ] Verify README.md component counts — no new agents or skills, counts should be unchanged (25 agents, 18 skills, 8 commands)

## Parallel Dispatch Opportunities

Phases 1-3 touch separate files with no dependencies:
- Phase 1: `brainstorm.md` only
- Phase 2: `deepen-plan.md` only
- Phase 3: `plan-consolidator.md` only

These can run in parallel during `/compound:work`. Phase 4 (version bump) depends on Phases 1-3 completing.

## Acceptance Criteria

1. All 4 triage points use three-category MINOR presentation instead of binary batch-accept
2. Fixability criteria are aligned across all triage points (same three criteria with domain-appropriate examples)
3. Subagent writes categorization to disk at 3 triage points (brainstorm red team, deepen-plan synthesis, deepen-plan red team); consolidator handles inline
4. User can apply all fixes, cherry-pick specific fixes, review individually, or acknowledge all
5. Post-fix verification runs after applying any fixes at all 4 triage points
6. "Needs manual review" items are presented individually with Valid/Disagree/Defer options
7. Provenance formats include `**Fixed (batch):**` annotation for applied fixes (deepen-plan only; brainstorm uses inline annotations)
8. Edge cases handled: zero fixable, all fixable, conflicting proposals
9. No new agents or skills added — agent count stays at 25, skill count at 18
10. Plan-consolidator auto-fix tier (Section 4) unchanged; three-category pattern applies only to remaining guardrailed MINORs (Section 6)

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-03-09-minor-triage-fixable-vs-defer-brainstorm.md` — Key decisions: three-category pattern (D1-D4), subagent delegation (D5), post-fix verification (D6), all triage points (D7), taxonomy alignment (D8)
- **Repo research:** `.workflows/plan-research/minor-triage-fixable/agents/repo-research.md` — Current triage implementations at all 4 points, consolidator auto-fix taxonomy, context-lean constraints, synthesis vs red team asymmetry
- **Learnings:** `.workflows/plan-research/minor-triage-fixable/agents/learnings.md` — Provenance format extension needs, taxonomy alignment approach, empirical fixable ratios (0-75% across 4 brainstorms), edit-induced finding relevance
- **SpecFlow:** `.workflows/plan-research/minor-triage-fixable/agents/specflow.md` — Synthesis gate inversion (keep/revert vs apply/skip), fix application mechanics, zero-fixable edge case, conflicting proposals, context-lean bounded-read exception for categorization file
