# Command Cross-Reference Analysis

## Per-Command Breakdown

### 1. brainstorm.md (198 lines)
- **Agents**: `repo-research-analyst` (Task bg), `context-researcher` (Task bg), `general-purpose` (red team, bg)
- **Skills**: `brainstorming` (line 13), `document-review` (line 181)
- **compound-engineering refs**: 0
- **Company-specific examples**: None
- **Plan coverage**: FULLY COVERED

### 2. plan.md (278 lines)
- **Agents**: `repo-research-analyst` (bg, ~line 73), `learnings-researcher` (bg, ~line 85), `best-practices-researcher` (bg, ~line 116), `framework-docs-researcher` (bg, ~line 126), `spec-flow-analyzer` (bg, ~line 178)
- **Skills**: None directly loaded
- **compound-engineering refs**: 0
- **Examples**: `intellect-v6-pricing`, `cash-manager-reporting` (~line 62) — MARKED in Phase 5a
- **Plan coverage**: COVERED

### 3. work.md (318 lines)
- **Agents**: `code-simplicity-reviewer` (Phase 3, ~line 212, optional)
- **Skills**: `agent-browser`, `imgup` (~line 253, screenshot)
- **compound-engineering refs**: 0
- **Examples**: None company-specific
- **Plan coverage**: No changes needed

### 4. work-agents.md (390 lines)
- **Agents**: `code-simplicity-reviewer` (Phase 3, ~line 290, optional)
- **Skills**: None
- **compound-engineering refs**: 0
- **Examples**: None
- **Plan coverage**: No changes needed

### 5. review.md (162 lines)
- **Agents**:
  - `kieran-typescript-reviewer` (~line 55) — TO RENAME
  - `pattern-recognition-specialist` (~line 56)
  - `architecture-strategist` (~line 57)
  - `security-sentinel` (~line 58)
  - `performance-oracle` (~line 59)
  - `code-simplicity-reviewer` (~line 60)
  - `agent-native-reviewer` (~line 61)
  - `kieran-rails-reviewer` (~line 67, conditional) — DROPPED
  - `dhh-rails-reviewer` (~line 67, conditional) — DROPPED
  - `julik-frontend-races-reviewer` (~line 68) — TO RENAME
- **Skills**: `git-worktree` (~line 24), `file-todos` (~line 102)
- **compound-engineering refs**: 0 direct (agent names from CE but no namespace prefix)
- **Examples**: `feat-cash-management-ui` (~line 30) — MARKED in Phase 5a
- **Plan coverage**: WELL COVERED

### 6. compound.md (141 lines)
- **Agents**: `general-purpose` (~line 50, context analyzer)
- **Skills**: None
- **compound-engineering refs**: 0
- **Examples**: `bq-cost-measurement`, `upstream-fork-management` (~line 40), `"before any Xiatech meeting"` (~line 126) — MARKED in Phase 5a
- **Plan coverage**: COVERED

### 7. deepen-plan.md (446 lines)
- **Agents**: Multiple indirect through discovery (lines 98-107)
- **Skills**: Reads from setup skill (~lines 78-86)
- **compound-engineering refs**: Lines 104-106 have compound-engineering-specific filter logic — MARKED for redesign in Phase 5b
- **Examples**: `feat-cash-management-reporting-app` (~line 27)
- **Plan coverage**: PARTIALLY COVERED — discovery logic redesign flagged but generic filter replacement not fully specified

### 8. setup.md (192 lines)
- **Agents**: None directly
- **Skills**: References `setup` skill (implied by Phase 4a)
- **compound-engineering refs**: Multiple (~lines 49, 157, 179)
- **Examples**: None company-specific
- **Plan coverage**: COVERED — Phase 5c full rewrite planned

## Critical Gaps Found

### Gap 1: deepen-plan.md line ~27 genericization not listed
The example `feat-cash-management-reporting-app` in deepen-plan.md is not explicitly listed in Phase 5b changes. Phase 5b only mentions the discovery logic rewrite, not the example project name on line 27.

**Impact**: Minor — easy to catch during execution.

### Gap 2: deepen-plan discovery filter replacement underspecified
Phase 5b says "remove compound-engineering-specific filter" and "replace with generic filter" but doesn't specify the exact replacement logic. Current filter (lines 104-106):
```
For compound-engineering plugin:
- USE: agents/review/*, agents/research/*, agents/design/*, agents/docs/*
- SKIP: agents/workflow/*
```
Plan says remove design/* and docs/* but doesn't specify the replacement block structure.

**Impact**: Medium — implementer needs to design the generic filter during execution.

### Gap 3: review.md output file path
review.md references `kieran-typescript.md` as output filename. Plan Phase 5a says "update output file path: kieran-typescript.md → typescript.md (if referenced)" but this is conditional/uncertain phrasing.

**Impact**: Low — should be definitive, not conditional.

## Verification: "5 of 7" Claim

Plan says 5 commands need changes:
1. plan.md (5a: minor text swap) ✓
2. compound.md (5a: minor text swap) ✓
3. review.md (5a: minor text + agent rename) ✓
4. deepen-plan.md (5b: discovery logic rewrite) ✓
5. setup.md (5c: full rewrite) ✓

NOT needing changes: brainstorm.md, work.md (and work-agents.md)

**VERDICT: "5 of 7" is accurate.** (Note: with work-agents merge, becomes "5 of 7" → effectively "5 of 6")
