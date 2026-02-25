# Orchestrating-Swarms SKILL.md — Per-Instance Audit

## Summary

26 total references found requiring transformation. 20 namespace updates, 3 agent renames, 3 removals. This confirms the plan's HIGH-effort rating — per-instance review is required, not bulk replace.

## Transformation Manifest

### Namespace Updates (20 references)

| # | Line | Old Text | New Text |
|---|------|----------|----------|
| 1 | 315 | `From the 'compound-engineering' plugin` | `From the 'compound-workflows' plugin` |
| 2 | 321 | `"compound-engineering:review:security-sentinel"` | `"compound-workflows:review:security-sentinel"` |
| 3 | 328 | `"compound-engineering:review:performance-oracle"` | `"compound-workflows:review:performance-oracle"` |
| 4 | 342 | `"compound-engineering:review:architecture-strategist"` | `"compound-workflows:review:architecture-strategist"` |
| 5 | 349 | `"compound-engineering:review:code-simplicity-reviewer"` | `"compound-workflows:review:code-simplicity-reviewer"` |
| 6 | 355 | `**All review agents from compound-engineering:**` | `**All review agents from compound-workflows:**` |
| 7 | 375 | `"compound-engineering:research:best-practices-researcher"` | `"compound-workflows:research:best-practices-researcher"` |
| 8 | 382 | `"compound-engineering:research:framework-docs-researcher"` | `"compound-workflows:research:framework-docs-researcher"` |
| 9 | 389 | `"compound-engineering:research:git-history-analyzer"` | `"compound-workflows:research:git-history-analyzer"` |
| 10 | 414 | `"compound-engineering:workflow:bug-reproduction-validator"` | `"compound-workflows:workflow:bug-reproduction-validator"` |
| 11 | 801 | `"compound-engineering:review:security-sentinel"` | `"compound-workflows:review:security-sentinel"` |
| 12 | 809 | `"compound-engineering:review:performance-oracle"` | `"compound-workflows:review:performance-oracle"` |
| 13 | 817 | `"compound-engineering:review:code-simplicity-reviewer"` | `"compound-workflows:review:code-simplicity-reviewer"` |
| 14 | 857 | `"compound-engineering:research:best-practices-researcher"` | `"compound-workflows:research:best-practices-researcher"` |
| 15 | 934 | `"compound-engineering:research:best-practices-researcher"` | `"compound-workflows:research:best-practices-researcher"` |
| 16 | 1434 | `"compound-engineering:review:security-sentinel"` | `"compound-workflows:review:security-sentinel"` |
| 17 | 1451 | `"compound-engineering:review:performance-oracle"` | `"compound-workflows:review:performance-oracle"` |
| 18 | 1467 | `"compound-engineering:review:architecture-strategist"` | `"compound-workflows:review:architecture-strategist"` |
| 19 | 1518 | `"compound-engineering:research:best-practices-researcher"` | `"compound-workflows:research:best-practices-researcher"` |
| 20 | 1550 | `"compound-engineering:review:security-sentinel"` | `"compound-workflows:review:security-sentinel"` |

### Agent Renames (3 references)

| # | Line | Old Text | New Text |
|---|------|----------|----------|
| 21 | 363 | `` `julik-frontend-races-reviewer` - JavaScript race conditions `` | `` `frontend-races-reviewer` - JavaScript race conditions `` |
| 22 | 364 | `` `kieran-python-reviewer` - Python best practices `` | `` `python-reviewer` - Python best practices `` |
| 23 | 366 | `` `kieran-typescript-reviewer` - TypeScript best practices `` | `` `typescript-reviewer` - TypeScript best practices `` |

### Removals (3 references)

| # | Line(s) | Content | Action |
|---|---------|---------|--------|
| 24 | 333-338 | kieran-rails-reviewer example block | REMOVE entire block |
| 25 | 362 | `` `dhh-rails-reviewer` - DHH/37signals Rails style `` | REMOVE line |
| 26 | 403-409 | "Design Agents" section (figma-design-sync example) | REMOVE entire section |

## Totals

- **Namespace updates**: 20
- **Agent renames**: 3
- **Removals**: 3
- **Total**: 26 references

## Company-Specific Content

- Line 362: "DHH/37signals" — external public figure reference, handled by removal of dropped agent line
- No "Every Inc", "Kieran", "Julik" beyond agent names handled above
- No proprietary URLs, emails, or internal tool names

## Skills Referenced

All skills referenced in orchestrating-swarms examples are either:
- Being ported (security-sentinel, performance-oracle, architecture-strategist, etc.)
- Being removed with their section (figma-design-sync → design section removed)

No references to skills NOT being ported that would remain as dead references.

## Execution Guidance

While there are 20 namespace updates that look like bulk-replaceable `s/compound-engineering/compound-workflows/g`, the 3 removals and 3 renames make blind bulk replace dangerous. Recommended approach:

1. Do the bulk namespace replace first: `compound-engineering:` → `compound-workflows:` (catches 20 of 26)
2. Then handle the 3 renames manually (lines 363, 364, 366)
3. Then remove the 3 blocks (lines 333-338, 362, 403-409)
4. Final grep to verify zero remaining `compound-engineering` references
