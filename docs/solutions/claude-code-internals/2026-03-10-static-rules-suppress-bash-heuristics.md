---
date: 2026-03-10
category: claude-code-internals
tags: [permission-system, bash-safety-heuristics, static-allow-rules, settings-json, pretooluse-hook]
origin_brainstorm: docs/brainstorms/2026-03-10-plugin-heuristic-audit-brainstorm.md
related_beads: [jak, msm, 3k3]
fragility: HIGH — based on 2 empirical tests of undocumented Claude Code internals
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

Claude Code's static allow rules (`Bash(X:*)` in settings.json / settings.local.json) completely suppress built-in bash safety heuristics when the command's first token matches. The permission evaluation order is:

```
Command submitted
    │
    ├─ 1. Static allow rules (Bash(X:*) patterns)
    │      Match on first token? → APPROVE immediately, skip all below
    │
    ├─ 2. Built-in heuristics ($(), {", <<, backticks)
    │      Pattern detected? → PROMPT (skip hook)
    │
    ├─ 3. PreToolUse hook (auto-approve.sh)
    │      Hook approves? → APPROVE
    │
    └─ 4. Interactive prompt → user decides
```

This contradicts the prior documented belief: "No hook, static rule, or permission setting can suppress heuristics — only `--dangerously-skip-permissions`."

**Correction:** Static rules CAN suppress heuristics (they fire before heuristics). Hooks CANNOT (they fire after heuristics). `--dangerously-skip-permissions` suppresses everything.

## Evidence

| Test | Command | Static Rule | Heuristic | Result |
|------|---------|-------------|-----------|--------|
| 1 | `bd create --metadata '{"impact":"none"}'` | `Bash(bd:*)` | `{"` expansion obfuscation | Auto-approved |
| 2 | `git commit --allow-empty -m "$(echo 'test')"` | `Bash(git:*)` | `$()` command substitution | Auto-approved |
| 3 | Multi-line bash (assignments + echo, no `$()`) | N/A | None | Auto-approved |
| 4 | `RESULT=$(echo "test")` | None | `$()` command substitution | **Prompted** |

Tests 1-2: static rules suppress heuristics. Test 3: no multi-line heuristic exists. Test 4: control — confirms heuristic fires without a matching rule.

## What Static Rules Fix

Commands where the first token matches a rule — all heuristic-triggering patterns within are suppressed:
- `git commit -m "$(cat <<'EOF'...)"` → `Bash(git:*)` suppresses `$()` and `<<`
- `bd create --metadata '{"impact":...}'` → `Bash(bd:*)` suppresses `{"`
- `cat >> "$SNAPSHOT_FILE" <<EOF` → `Bash(cat:*)` suppresses `<<` and `>>`

## What Static Rules Cannot Fix

**VAR=$(...) patterns** — first token is a variable assignment, no static rule can match:
- `ENTRY_COUNT=$(grep -c '^---$' "$STATS_FILE")` → first token `ENTRY_COUNT=`
- `PLUGIN_ROOT=$(find ...)` → first token `PLUGIN_ROOT=`
- `SNAPSHOT_FILE="$(date ...)"` → first token `SNAPSHOT_FILE=`

These require plugin-side rewrites (restructure commands to avoid `$()`) or acceptance as unavoidable prompts.

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
| Two test cases generalize to all heuristic types | Some heuristics might be "hard" (unsuppressible) |

## Corrections Applied

1. **Private memory (MEMORY.md)** — updated: static rules suppress heuristics, no multi-line heuristic
2. **Project memory (project.md)** — needs update: line 42 says nothing can suppress heuristics except `--dangerously-skip-permissions`
3. **v2.4.0 plan edge cases** — should note static rules suppress heuristics, not just hooks

## Cross-References

- **Origin:** `docs/brainstorms/2026-03-10-plugin-heuristic-audit-brainstorm.md` (Critical Empirical Finding section)
- **Prior incorrect belief:** bead msm notes, `memory/project.md` line 42
- **Informs:** bead jak (plugin-side rewrites scoped by this finding), bead msm (Permissive profile design)
