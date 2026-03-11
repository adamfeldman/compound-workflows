---
title: User Input Gates Before Automated Work
bead: 42s
date: 2026-03-10
status: brainstorm
---

# What We're Building

A triage UX pattern: **in triage flows, ask the user first, then do automated work.** The goal is optimizing the user's wall-clock time and attention.

1. **Don't waste user time** — if there's a pending question, ask it immediately. The user is sitting idle while the system churns through auto-fixes before finally asking. That's dead time. User: "dont do automated work while the user is sitting there waiting for you to ask a pending manual question, that wastes their time."
2. **Don't invalidate work** — user decisions may change direction. Automated fixes applied before user input may get thrown away, wasting tokens.

This pattern applies to **triage flows** (red team findings, MINOR fixes, review findings) where user input is uncertain and may change direction. It does not apply to **execution flows** (work dispatch) where steps are well-specified and parallel execution is preferred — speed matters more than token savings there.

## Why This Approach

The triggering incident: plan command applied 2 MINOR fixes before presenting 3 manual review items. The user was idle waiting for the auto-fixes to complete, then had to review manual items that could have been asked upfront. If the manual review changed direction, those fixes would have been wasted.

The fix is **execution sequencing**, not just display ordering. The actual bug: Step 3c (apply fixes) runs before Step 3d (present manual-review items individually). The user confirms the batch in 3b, fixes are applied in 3c, and only then are manual-review items presented one-by-one in 3d. If a manual-review decision in 3d invalidates a fix already applied in 3c, that fix used stale context.

The fix: resolve manual-review items individually first (current 3d), then re-evaluate and apply batch fixes (current 3c). No cancellation mechanism needed — fixes simply haven't run yet when manual decisions are made.

## Key Decisions

### Decision 1: Execution sequencing + completion enforcement
Two failure modes, both from the same root cause (automated work before user input):

1. **Wrong order** — Step 3c (apply fixes) runs before Step 3d (manual review). Fixes may use stale context if manual decisions change the document.
2. **Skipped steps** — LLM misinterprets the Step 3b batch choice ("Apply all fixes + acknowledge no-action") as resolving ALL MINOR items, skipping Step 3d entirely. Manual review items (Category 2) are never presented. Discovered during jak plan red team (bead icn): model jumped from Step 3b → plan edits → hash comparison, skipping 3d.

The fix addresses both:
- **Resequence**: resolve manual-review items individually (current Step 3d) BEFORE applying batch fixes (current Step 3c). No cancellation mechanism needed — fixes haven't run yet when decisions are made.
- **Completion gate**: explicit checkpoint before any post-triage work (hash comparison, plan edits) verifying all triage categories are resolved. Catches both wrong-order and skipped-step failures.
- **Label clarity**: batch choice options must state what they cover and what comes next (e.g., "— manual review items presented next").

**Rationale:** The original framing (ordering only) missed the omission failure mode. The brainstorm assumed all steps would execute and focused on sequence. But when an LLM executes the command, ambiguous batch choice wording can cause it to skip steps entirely — not just reorder them. The completion gate is the deterministic safeguard.

### Decision 2: Triage flows only
Applies to the 3 commands with MINOR triage flows: brainstorm.md, plan.md, deepen-plan.md.

The other 4 commands are not affected:
- **work.md** — parallel execution, don't pause (user chose option A). Speed matters more during execution than token savings from pausing. Considered and rejected: "direction changes are rare" frequency argument — irrelevant, since the speed preference holds regardless of frequency.
- **setup.md** — already fully interactive (detect → ask → configure at every step).
- **compact-prep.md** — sequential checklist, each step gates on the previous.
- **compound.md** — no triage flow.

### Decision 3: Resolve manual-review items before applying fixes
The three-category display order in Step 3b (Fixable now, Needs manual review, No action needed) is cosmetic (user sees all at once). The real change: Step 3d (individual manual-review resolution) must run before Step 3c (batch fix application). After manual decisions are made, re-evaluate proposed fixes against the updated document state before applying.

**Considered and rejected: cognitive load concern.** Red team flagged that front-loading hard manual decisions before clearing trivial auto-fixes may overwhelm the user. Counter: do the hard things first — decision fatigue is real, and you make better decisions when freshest. Quick wins can wait.

### Decision 4: Add as QA check (two tiers)
- **Tier 1 (grep):** Pattern match on step headings in command files — verify manual-review resolution appears before fix application in the execution flow. Catches structural reordering.
- **Tier 2 (LLM):** Add to the existing command completeness reviewer checklist — verify any triage flow follows the input-gates pattern. Catches semantic drift (e.g., new triage flow that doesn't follow the pattern).

## Scope

### In scope
1. Audit brainstorm.md, plan.md, deepen-plan.md for execution sequencing violations AND step omission risks
2. Fix Step 3c/3d ordering in all affected commands (resolve manual items before applying fixes)
3. Add completion gates before post-triage work (hash comparison, document edits) — explicit checklist of all triage categories resolved
4. Clarify batch choice option labels to state scope and what comes next
5. Fix any other instances in triage commands where automated work runs before pending user questions
6. Add Tier 2 QA check for the pattern (covers both ordering and completion enforcement)

### Out of scope
- work.md execution flow (intentionally parallel, no pause)
- setup.md, compact-prep.md, compound.md (already correct)
- Cancellation mechanisms
- Optimistic concurrent execution (run auto-fixes in background while asking manual questions, discard on conflict) — conceptually nice but requires rollback/conflict detection. Revisit if sequential approach feels slow. User: "if we didnt need rollback, it'd be nice"

### Related beads
- **wtn** — Harden plugin commands for cheaper-model robustness. 42s is a specific instance of the broader robustness problem: LLMs skipping steps, conflating scope, ignoring gates. The completion gate and label clarity fixes from 42s are applications of wtn's robustness principles (completion gates, unambiguous step scope, fail loud).
- **icn** (closed, merged into 42s) — Concrete reproduction case from jak plan red team. Step 3d skipped entirely after Step 3b batch choice.
- **a6t** — Agent timeout/recovery. Same class: LLM judgment failure (impatience) instead of deterministic verification.

## Resolved Questions

### Q1: Is the plan-consolidator a 42s violation?
**No.** The consolidator already handles this correctly in Section 4: "If a section has ANY guardrailed findings → hold ALL findings for that section (including auto-fixable ones) until user decisions are made." Auto-fixes only run on sections with zero user decisions. This is intentionally correct — not a 42s violation. Out of scope.

### Q2: Can CRITICAL/SERIOUS edits make MINOR categorizations stale?
**Yes — same class of bug as the CRITICAL finding.** If resolving a CRITICAL item edits the document, pre-categorized MINOR "Fixable now" items may be stale. The fix: MINOR triage categorization should happen (or be re-evaluated) AFTER CRITICAL/SERIOUS resolutions are applied. Add this to the execution resequencing scope.

### Q3: What does the Tier 2 QA check look for?
The check verifies: in commands with three-category triage, manual-review resolution (Step 3d) appears before fix application (Step 3c) in the execution flow. Mechanically: grep for the step ordering pattern in the command files. Lightweight — pattern match on step headings and sequencing.

### Q4: Why didn't the original brainstorm cover step omission?
The brainstorm was framed as an **ordering** problem — "which step runs first?" It assumed all steps would execute and focused on their sequence. The icn incident revealed a different failure mode: the LLM executing the command **skips steps entirely** when batch choice wording is ambiguous. The brainstorm's mental model was "human user makes choices, automation runs in wrong order" — it didn't account for the LLM misinterpreting which items a batch choice covers. The completion gate addresses this blind spot with a deterministic checkpoint.
