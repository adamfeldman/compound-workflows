---
title: "Multi-Round QA Testing Patterns"
date: 2026-03-17
category: qa-infrastructure
tags: [qa-process, multi-round-testing, cross-model-review, fail-open-antipattern, dry-run-pattern, semantic-tokens]
confidence: high
origin_plan: docs/plans/2026-03-16-feat-session-worktree-start-flow-plan.md
origin_brainstorm: docs/brainstorms/2026-03-15-session-worktree-start-flow-brainstorm.md
---

# Multi-Round QA Testing Patterns

## Problem

v3.4.0 QA for session worktree start flow (hb4a) — 30 files, 9 implementation steps — was expected to be a single Tier 1 + Tier 2 pass. It expanded to 7 Tier 2 rounds, a cross-model red team, scenario tracing, and an end-to-end smoke test. Each round found real bugs the previous rounds missed.

## Key Findings

### 1. "Run Until Clean" Is Necessary But Not Sufficient

Tier 2 found new bugs on rounds 1, 4, 5, and 6 — even after rounds 2-3 were clean. **Root cause:** each fix changes files, creating new review surface that wasn't present in prior rounds. A clean round means the *unchanged* codebase is clean, not the *fixed* codebase.

**Rule:** After any fix round that modifies files, run at least one more Tier 2 pass. Stop only after a clean round where no files were modified since the previous round.

**Decision heuristic:** If fixes touched files not in the original changeset or introduced new control flow, run again. If fixes were purely textual (typos, wording), stop.

### 2. Cross-Model Red Team Catches Same-Model Blind Spots

3 CRITICAL bugs were found by Gemini and OpenAI that 21 same-model (Claude) Tier 2 dispatches never flagged:
- Fail-open `|| true` on safety-critical git checks
- Path traversal in worktree name argument
- Using destructive GC script as a read-only liveness probe

**Rule:** For safety-critical changes (deletion logic, permission checks), add a cross-model red team after Tier 2 converges. This complements Tier 2, not replaces it.

**Limit:** Cross-model review catches *model-specific* blind spots but not *shared structural* blind spots (see `docs/solutions/process-analysis/2026-03-14-inherited-assumption-blind-spots.md` — all 3 providers missed the same population homogeneity issue).

### 3. The `|| true` Fail-Open Anti-Pattern

`command || true` suppresses failures. In non-critical code, this is defensive programming. **In safety-critical code guarding destructive operations, it's fail-open** — if the guard command fails, the destructive operation proceeds unchecked.

**Example:** `git status --porcelain 2>/dev/null || true` — if git fails (lock contention, corrupt index), output is empty, which the script interprets as "clean" and proceeds to delete the worktree.

**Fix:** Fail-closed. If the guard fails, block the destructive operation:
```bash
if ! result=$(git status --porcelain 2>/dev/null); then
  echo "SKIPPED $name git-check-failed:status"
  return 0  # Don't delete — can't verify safety
fi
```

**Generalized rule:** Every destructive operation needs an explicit answer to "what happens if the safety check itself fails?" If the answer is "proceed anyway," that's fail-open.

### 4. `--dry-run` Flag for Destructive Scripts

Add `--dry-run` to destructive scripts rather than creating separate check scripts. One script to maintain, same detection logic, no drift risk.

**Output token design matters:** Use distinct tokens — `REMOVABLE` (dry-run: would be removed) vs `REMOVED` (real: was removed). Callers parse these tokens to make decisions.

### 5. SKIPPED Token Semantic Classification

When a script outputs `SKIPPED <name> <reason>`, callers must classify on the `(token, reason)` pair, not the token alone:
- `SKIPPED ... another-session-active` → **block** (concurrent session)
- `SKIPPED ... new-session-claimed-during-gc` → **block** (race detection)
- `SKIPPED ... gc-lock-busy` → **retry**
- `SKIPPED ... unmerged-commits` → **proceed** (state issue, handled elsewhere)

Failing to classify caused a real bug: do-work only handled `REMOVABLE` and `another-session-active`, so the common case (`unmerged-commits`) fell through to undefined behavior.

### 6. Pre-Existing Bugs Surface During Feature QA

Feature QA found 4 pre-existing bugs (fixed) and created 3 beads for deferred ones. Large changesets touching shared infrastructure expose latent issues because reviewers examine code paths that haven't been reviewed since introduction.

**Rule:** File pre-existing bugs as separate beads. Track whether the changeset introduced them or merely exposed them.

## Quantitative Evidence

| Metric | Value |
|--------|-------|
| Tier 2 rounds | 7 |
| Tier 2 agent dispatches | 21 |
| Real bugs from Tier 2 | 5 |
| Findings by round | R1:1, R2:0, R3:0, R4:2, R5:1, R6:1, R7:0 |
| Cross-model findings | 3 CRITICAL + 3 SERIOUS + 1 MINOR |
| CRITICALs missed by Tier 2 | 3/3 (100%) |
| Pre-existing bugs fixed | 4 |
| Beads created | 3 |
| Scenario traces | 3 paths, 1 gap found |

## When to Apply

| Trigger | Action |
|---------|--------|
| `/do:work` on >5 steps touching safety-critical scripts | Budget 2-4 Tier 2 rounds, add cross-model red team |
| Designing bash scripts guarding destructive ops | Audit for `|| true` on guard checks; ensure fail-closed |
| Adding output tokens to scripts consumed by LLM skills | Define full token vocabulary; classify each reason |
| Considering "run Tier 2 one more time?" | If fixes touched files, yes. If no files changed, stop |
| Feature QA surfaces pre-existing bugs | Separate beads, don't block feature merge |

## Assumptions That Could Invalidate

- **Tier 2 agents become stateful** — fix-induced surface area may not produce new findings
- **Cross-model quality converges** — if models stop having complementary blind spots, cross-model review becomes redundant
- **Automated test framework adopted** — manual "one more round?" becomes CI
- **Work splits into smaller PRs** — single-pass QA may suffice for <5-file changes

## Related Documents

- `docs/solutions/process-analysis/2026-03-08-deepen-plan-iteration-taxonomy.md` — edit-induced inconsistency taxonomy
- `docs/solutions/qa-infrastructure/2026-03-08-bash-qa-script-patterns.md` — Tier 1 QA patterns, `|| true` precedence bug
- `docs/brainstorms/2026-03-08-deepen-plan-convergence-brainstorm.md` — convergence-advisor design
- `docs/brainstorms/2026-03-08-red-team-model-selection-brainstorm.md` — 3-provider architecture
- `docs/solutions/process-analysis/2026-03-14-inherited-assumption-blind-spots.md` — shared blind spot limit
- `plugins/compound-workflows/scripts/session-gc.sh` — canonical fail-closed + --dry-run + SKIPPED protocol implementation
