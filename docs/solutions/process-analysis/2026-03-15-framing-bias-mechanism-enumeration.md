---
title: "Framing Bias in Mechanism Enumeration"
category: process-analysis
date: 2026-03-15
confidence: high
problem_type: methodology-gap
domain: brainstorm-methodology
severity: medium
tags:
  - framing-bias
  - search-space-narrowing
  - mechanism-enumeration
  - brainstorm-methodology
  - inherited-assumptions
  - enforcement-architecture
origin_plan: docs/plans/2026-03-15-fix-worktree-session-isolation-v2-plan.md
origin_brainstorm: docs/brainstorms/2026-03-14-session-worktree-v2-brainstorm.md
reuse_triggers:
  - Brainstorm concludes something is "impossible" or "infeasible" within a specific framework
  - Problem statement pre-selects a tool or framework ("How can we use X to do Y?")
  - Workaround feels over-engineered for what should be a simple guarantee
  - Red team unanimously flags reliability/determinism concern
  - Plan explores hook systems, plugin systems, or layered middleware
---

# Framing Bias in Mechanism Enumeration

## Problem

During v2 session worktree isolation planning, the brainstorm explored enforcement mechanisms for "prevent commits to main when `session_worktree` is enabled." It tested Claude Code's PreToolUse hook — empirically showed it doesn't work (`auto-approve.sh` overrides exit 2). Concluded prose-only enforcement (AGENTS.md instructions) was the only option.

All 3 red team providers (Gemini, OpenAI, Claude Opus) flagged this as CRITICAL/SERIOUS. The fix was trivial: git's native `.git/hooks/pre-commit` — a ~15 line script that runs at the git level and can abort commits. This is a completely different hook system from Claude Code hooks, existing since git 1.0.

The brainstorm missed it because the entire exploration was framed around "Claude Code hooks." When PreToolUse failed, the conclusion was "hooks can't enforce this" — but the search space was "Claude Code hooks," not "all available hook mechanisms."

## Root Cause

**When a problem is framed within a specific technology's mechanism space, solutions outside that space become invisible — even when they are simpler, more reliable, and well-known.**

Three factors narrow the search space:

1. **Vocabulary anchoring.** The brainstorm used "hook" to mean "Claude Code hook." Git hooks are also "hooks" but occupied a different mental category. The shared term created an illusion of exhaustive coverage.

2. **Tool-centric decomposition.** "Claude Code needs to prevent the commit" constrains solutions to Claude Code mechanisms. "The commit needs to be prevented" opens all mechanisms in the stack.

3. **Sunk cost in the frame.** By the time PreToolUse failed, the brainstorm had invested significant analysis (6 upstream bugs, multi-hook interaction, auto-approve mapping). Expanding to a different mechanism category felt like starting over.

## The Pattern (Third Instance of ytlk)

| Instance | Bead | What was narrowed | What was missed |
|----------|------|-------------------|-----------------|
| Mixed bead populations | ytlk | Population boundary ("a bead is a bead") | Work-created vs manual beads with opposite estimation biases |
| SessionStart hooks broken | fyg9 | Failure attribution (hook tested as unit) | stdout + exit 0 works; only stderr + exit 2 is broken |
| Commit enforcement | (this) | Mechanism search space (Claude Code hooks only) | Git-native pre-commit hooks — simpler, deterministic, 20 years old |

All three: **an implicit boundary on the search space was never stated, so it was never available for challenge.**

### Ironic contrast

The git-index-isolation brainstorm (2026-03-13 — one day earlier) *did* enumerate git's pre-commit hook as a mechanism and explicitly analyzed it for commit enforcement. The knowledge existed; it wasn't transferred. Domain framing ("git safety" vs "Claude Code enforcement") determined whether the mechanism was salient.

## Solution

Defense-in-depth added to the v2 plan (Step 8):
- **AGENTS.md prose** (primary) — tells model to warn before committing on main
- **Git `.git/hooks/pre-commit`** (backstop) — deterministic, exits non-zero to abort, `--no-verify` escape hatch
- ~15 lines of bash, installed by `/do:setup`

## Process Recommendation

When a brainstorm explores enforcement, prevention, or constraint mechanisms:

1. **Enumerate mechanism layers before exploring any one layer.** For commit enforcement: Claude Code hooks, git hooks, filesystem permissions, CI checks, branch protection. State the layers, then explore within them.

2. **Name the frame.** "We are exploring Claude Code hooks for enforcement" makes the boundary explicit. Explicit boundaries can be challenged. Implicit boundaries cannot.

3. **When a mechanism fails within one layer, expand to adjacent layers before adding complexity within the same layer.** PreToolUse exit 2 failing should have triggered "what other hook systems exist?" — not "how do we make PreToolUse work with sentinels and subagent detection?"

This extends the ytlk "test before designing" principle:
1. **Test before designing** — verify the claimed constraint exists (fyg9)
2. **Enumerate before concluding** — verify the mechanism search space is complete before declaring something impossible (this finding)

## Assumptions That Could Invalidate

- Claude Code adds native `PreCommit` hook support → specific example weakens, methodology lesson remains
- Brainstorm prompts restructured to require mechanism enumeration → bias structurally prevented (in progress via ytlk v2)

## Cross-References

- `docs/solutions/process-analysis/2026-03-14-inherited-assumption-blind-spots.md` — pattern class definition
- `docs/brainstorms/2026-03-15-assumption-verification-v2-brainstorm.md` — unified ytlk+fyg9 framework
- `docs/brainstorms/2026-03-14-session-worktree-v2-brainstorm.md` — the brainstorm that missed the hook
- `docs/brainstorms/2026-03-13-git-index-isolation-brainstorm.md` — contrast case (DID enumerate git hooks, one day earlier)
- `docs/plans/2026-03-15-fix-worktree-session-isolation-v2-plan.md` — where the fix was added (Step 8)
- Research: `.workflows/compound-research/framing-bias-mechanism-enumeration/`
