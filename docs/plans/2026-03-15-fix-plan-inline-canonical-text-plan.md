# Fix: Plans should inline canonical text, not cross-reference brainstorms (5pa5)

**Bead:** 5pa5
**Status:** Ready to implement
**Estimated:** 30m
**File:** `plugins/compound-workflows/skills/do-plan/SKILL.md`

## Problem

Line 80 tells the model to "reference specific decisions with `(see brainstorm: ...)`" — this encourages cross-references for everything, including actionable content like code blocks, config patterns, and exact strings. /do:work subagents then can't complete steps without reading the brainstorm, violating "plans must be fully specified."

## Root Cause

The DRY instinct from coding conflicts with the plan self-containment convention. The current instruction doesn't distinguish between:
- **Rationale cross-refs** (why a decision was made) — fine to cross-reference
- **Actionable content** (code blocks, config patterns, exact strings a subagent needs to implement) — must be inlined

## Fix

### Change 1: Line 80 — Split the instruction

**Before (line 80):**
```
6. **The brainstorm is the origin document.** Throughout the plan, reference specific decisions with `(see brainstorm: docs/brainstorms/<filename>)`. Do not paraphrase decisions in a way that loses their original context — link back to the source.
```

**After:**
```
6. **The brainstorm is the origin document.** Always include `(see brainstorm: docs/brainstorms/<filename>)` cross-references for traceability — both for rationale and for actionable content. However, **actionable content must also be inlined in the plan** — code blocks, config patterns, exact strings, CLI commands, file paths, and any text a /do:work subagent needs to implement a step. The cross-ref tells the reader where it came from; the inline text means the subagent doesn't need to read the brainstorm. Both, not either/or. Plans must be self-contained for autonomous subagent execution.
```

### Change 2: Lines 304-312 — Add inline check to brainstorm cross-check

Add a new checkbox after the existing checklist items:

```
- [ ] Actionable content from the brainstorm is inlined in plan steps (code blocks, config patterns, exact strings, CLI commands) with cross-references back to the brainstorm for traceability
```

## Scope

- Line 80 — split rationale vs actionable content instruction
- Lines 304-312 — add inline check to brainstorm cross-check
- No version bump needed? Actually this IS inside `plugins/compound-workflows/`, so version bump required.

## Version Bump

1. Bump patch version in `plugins/compound-workflows/.claude-plugin/plugin.json`: 3.2.2 → 3.2.3
2. Bump patch version in `.claude-plugin/marketplace.json`: 3.2.2 → 3.2.3
3. Add CHANGELOG entry in `plugins/compound-workflows/CHANGELOG.md`
4. Verify README component counts (no change expected)

## QA

Run Tier 1 QA scripts after changes. Tier 2 optional — this is a prompt wording change, not structural.
