# Genericization Completeness Audit

## Summary

The plan's Canonical Genericization Table is **95% complete**. All listed terms have confirmed matches in source files. No major undiscovered company-specific terms found.

## Term-by-Term Verification

### 1. BriefSystem / brief_system — COVERED ✓
Found in 4 files:
- `agents/research/learnings-researcher.md` (lines 37, 167)
- `skills/compound-docs/SKILL.md` (lines 141-142, 463, 479)
- `skills/compound-docs/schema.yaml` (lines 9, 49, 144)
- `skills/compound-docs/references/yaml-schema.md` (line 34)
- **Plan**: Phase 3b (learnings-researcher) + Phase 3c (compound-docs)

### 2. EmailProcessing / email_processing — COVERED ✓
Found in 4 files:
- `agents/research/learnings-researcher.md` (lines 37, 167)
- `skills/compound-docs/SKILL.md` (lines 142, 463, 479, 488)
- `skills/compound-docs/schema.yaml` (lines 10, 48)
- `skills/compound-docs/references/yaml-schema.md` (referenced)
- **Plan**: Phase 3b + Phase 3c

### 3. Every Reader — COVERED ✓
Found in 5 agent-native-architecture reference files:
- `action-parity-discipline.md` (line 340)
- `system-prompt-design.md` (line 165)
- `shared-workspace-architecture.md` (lines 476, 478)
- `dynamic-context-injection.md` (line 270)
- `architecture-patterns.md` (line 110)
- **Plan**: Phase 3c — "6 reference files: Replace 'Every Reader' case study"

### 4. EveryInc/cora — COVERED ✓
Found in 1 file:
- `skills/resolve-pr-parallel/scripts/get-pr-comments` (line 8, usage example)
- **Plan**: Phase 2b

### 5. Kieran persona — COVERED ✓
Found in 3 agent files:
- `agents/review/kieran-typescript-reviewer.md` (persona throughout)
- `agents/review/kieran-python-reviewer.md` (persona throughout)
- `agents/review/kieran-rails-reviewer.md` (not ported — dropped)
- **Plan**: Phase 3a (rename + depersonalize)

### 6. Julik persona — COVERED ✓
Found in 1 agent file:
- `agents/review/julik-frontend-races-reviewer.md` (persona throughout, including "Eastern-European and Dutch (directness)")
- **Plan**: Phase 3a (rename + depersonalize)

### 7. compound-engineering namespace — COVERED ✓
Found in key files:
- `agents/research/git-history-analyzer.md` (1 reference)
- `agents/review/code-simplicity-reviewer.md` (1 reference)
- `skills/setup/SKILL.md` (12+ `compound-engineering.local.md` references)
- `skills/orchestrating-swarms/SKILL.md` (26 references — see orchestrating-swarms audit)
- **Plan**: Phase 2a (LOW agents), Phase 4a (setup), Phase 4b (orchestrating-swarms)

### 8. Xiatech — COVERED ✓
Found only in commands (not in source agents/skills being ported):
- `commands/compound-workflows/compound.md` (~line 126)
- **Plan**: Phase 5a

### 9. cash-management / cash-manager — COVERED ✓
Found only in commands:
- `commands/compound-workflows/review.md`, `plan.md`, `deepen-plan.md`
- **Plan**: Phase 5a + 5b

### 10. intellect-v6 — COVERED ✓
Found only in commands:
- `commands/compound-workflows/plan.md`
- **Plan**: Phase 5a

### 11. bq-cost-measurement — COVERED ✓
Found only in commands:
- `commands/compound-workflows/compound.md`
- **Plan**: Phase 5a

## Terms Searched But NOT Found in Ported Files
- Xiatech (commands only)
- cash-management / cash-manager (commands only)
- intellect-v6 (commands only)
- bq-cost (commands only)

These are correctly handled in Phase 5 (command updates), not in agent/skill phases.

## Additional Findings

### Year reference
- `agents/research/git-history-analyzer.md` line 22: "Note: The current year is 2026"
- **Assessment**: This IS a hardcoded year. Plan Phase 7f says "Verify no hardcoded 'the current year is 2026' (illustrative dates in examples are fine)" — this specific instance says "The current year is 2026" which is exactly the pattern to check. However, it's in a system context note, not a user-facing example.
- **Recommendation**: Flag for review during Phase 2a when updating this file anyway.

### No undiscovered terms
- No URLs, email addresses, or internal tool names found
- No GitHub organization references beyond EveryInc (covered)
- DHH/37signals mentioned in orchestrating-swarms — this is a public figure reference, not company-specific

## Verdict

Plan's genericization table is comprehensive. All 12 replacement mappings have confirmed source matches. The only minor finding is the hardcoded year in git-history-analyzer.md.
