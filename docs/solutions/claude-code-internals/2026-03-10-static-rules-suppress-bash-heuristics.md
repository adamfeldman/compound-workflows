---
date: 2026-03-10
category: claude-code-internals
tags: [permission-system, bash-safety-heuristics, static-allow-rules, settings-json, pretooluse-hook]
origin_brainstorm: docs/brainstorms/2026-03-10-plugin-heuristic-audit-brainstorm.md
related_beads: [jak, msm, 3k3, ywug]
fragility: HIGH — based on 3 empirical tests of undocumented Claude Code internals (1 disproved generalization)
verification_cadence: after every Claude Code update (<60 seconds)
reuse_triggers:
  - designing commands that emit bash with $() or heredocs
  - adding/removing static rules in settings.json
  - debugging unexpected permission prompts
  - designing Permissive profile (bead msm)
  - after Claude Code version updates
---

# Static Allow Rules Suppress Claude Code's Built-in Bash Safety Heuristics

## Finding

Claude Code's static allow rules (`Bash(X:*)` in settings.json / settings.local.json) suppress **most** built-in bash safety heuristics when the command's first token matches — but not all. Heredoc (`<<`) is a "hard" heuristic that fires even with a matching static rule. The permission evaluation order is:

```
Command submitted
    │
    ├─ 1. Static allow rules (Bash(X:*) patterns)
    │      Match on first token? → APPROVE immediately, skip all below
    │
    ├─ 2. Built-in heuristics ($(), {", <<, backticks)
    │      Pattern detected? → PROMPT (skip hook)
    │      NOTE: << (heredoc) appears to be "hard" — fires even with matching static rule
    │
    ├─ 3. PreToolUse hook (auto-approve.sh)
    │      Hook approves? → APPROVE
    │
    └─ 4. Interactive prompt → user decides
```

This contradicts the prior documented belief: "No hook, static rule, or permission setting can suppress heuristics — only `--dangerously-skip-permissions`."

**Correction:** Static rules CAN suppress **most** heuristics (they fire before heuristics), but `<<` heredoc is an exception — it prompts even with a matching static rule. Hooks CANNOT suppress any heuristic (they fire after heuristics). `--dangerously-skip-permissions` suppresses everything.

## Evidence

| Test | Command | Static Rule | Heuristic | Result |
|------|---------|-------------|-----------|--------|
| 1 | `bd create --metadata '{"impact":"none"}'` | `Bash(bd:*)` | `{"` expansion obfuscation | Auto-approved |
| 2 | `git commit --allow-empty -m "$(echo 'test')"` | `Bash(git:*)` | `$()` command substitution | Auto-approved |
| 3 | Multi-line bash (assignments + echo, no `$()`) | N/A | None | Auto-approved |
| 4 | `RESULT=$(echo "test")` | None | `$()` command substitution | **Prompted** |
| 5 | `cat >> "file" <<EOF` | `Bash(cat:*)` | `<<` heredoc | **Prompted** |

Tests 1-2: static rules suppress `$()` and `{"` heuristics. Test 3: no multi-line heuristic exists. Test 4: control — confirms heuristic fires without a matching rule. **Test 5: `<<` heredoc is a "hard" heuristic — NOT suppressed by static rules even when first token matches.** This disproves the generalization from tests 1-2 that all heuristics are suppressible.

## What Static Rules Fix

Commands where the first token matches a rule — **most** heuristic-triggering patterns within are suppressed:
- `git commit -m "$(cat <<'EOF'...)"` → `Bash(git:*)` suppresses `$()`
- `bd create --metadata '{"impact":...}'` → `Bash(bd:*)` suppresses `{"`

**Note:** `git commit` with heredoc works because `$()` is the primary trigger and IS suppressed by `git:*`. The `<<` inside `$()` is not separately evaluated. Standalone `<<` (e.g., `cat >> file <<EOF`) is NOT suppressed — see Test 5.

## What Static Rules Cannot Fix

**1. VAR=$(...) patterns** — first token is a variable assignment, no static rule can match:
- `ENTRY_COUNT=$(grep -c '^---$' "$STATS_FILE")` → first token `ENTRY_COUNT=`
- `PLUGIN_ROOT=$(find ...)` → first token `PLUGIN_ROOT=`
- `SNAPSHOT_FILE="$(date ...)"` → first token `SNAPSHOT_FILE=`

These require plugin-side rewrites (restructure commands to avoid `$()`) or acceptance as unavoidable prompts.

**2. Heredoc patterns (`<<`)** — "hard" heuristic not suppressed by static rules, even when the first token matches:
- `cat >> "$SNAPSHOT_FILE" <<EOF` → `Bash(cat:*)` present, but `<<` heuristic still fires (Test 5)

Empirically verified: screenshot evidence from bead ywug session shows the prompt despite `cat:*` rule in settings.local.json. The fix is to move the heredoc into a script file (invisible to heuristic inspector) — same pattern as capture-stats.sh for `$()`.

## Fragility

**HIGH.** The evaluation order is undocumented. Anthropic could change it in any Claude Code update without notice.

**Mitigants:**
- Verification takes <60 seconds: re-run tests 1 and 2
- Backup plans pre-designed: Write tool + `git commit -F` for P7, validate-stats.sh for P4
- Hook is independently defensive — continues working regardless of evaluation order

**Verify after:** Every Claude Code update. Before any release recommending static rules to users.

## Assumptions That Could Invalidate

| Assumption | If Broken |
|------------|-----------|
| Static rules evaluate before heuristics | All "already solved" classifications wrong — commands prompt again |
| First-token matching is the static rule mechanism | Rules might stop matching or match unintended commands |
| No multi-line heuristic exists | Init blocks prompt for a second reason beyond `$()` |
| ~~Two test cases generalize to all heuristic types~~ | ~~Some heuristics might be "hard" (unsuppressible)~~ **BROKEN:** `<<` heredoc IS a hard heuristic (Test 5, bead ywug). `$()` and `{"` are suppressible; `<<` is not. |

## Corrections Applied

1. **Private memory (MEMORY.md)** — updated: static rules suppress heuristics, no multi-line heuristic
2. **Project memory (project.md)** — needs update: line 42 says nothing can suppress heuristics except `--dangerously-skip-permissions`
3. **v2.4.0 plan edge cases** — should note static rules suppress heuristics, not just hooks

## Cross-References

- **Origin:** `docs/brainstorms/2026-03-10-plugin-heuristic-audit-brainstorm.md` (Critical Empirical Finding section)
- **Prior incorrect belief:** bead msm notes, `memory/project.md` line 42
- **Informs:** bead jak (plugin-side rewrites scoped by this finding), bead msm (Permissive profile design)
