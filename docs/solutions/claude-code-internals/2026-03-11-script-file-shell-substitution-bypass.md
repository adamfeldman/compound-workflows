---
date: 2026-03-11
finding_type: technical-evaluation
domain: claude-code-plugin-development
subdomain: permission-prompt-optimization
confidence: validated
status: actionable
tags: [claude-code-internals, bash-heuristics, shell-substitution, hooks, plugin-patterns, init-values]
related_beads: [3l7, jak]
origin_brainstorm: docs/brainstorms/2026-03-11-heuristic-audit-scope-expansion-brainstorm.md
fragility: HIGH
---

# Script-File Shell Substitution Bypass

## Finding

Claude Code's `$()` heuristic inspects the **Bash tool input string only**, not the contents of executed script files. A command like `bash init-values.sh` contains no `$()` in the tool input, so no heuristic fires and the command auto-approves universally — regardless of how much `$()` the script uses internally.

This is a **third suppression mechanism** alongside:
1. Static `Bash(X:*)` rules (fire before heuristics)
2. `--dangerously-skip-permissions` (suppresses everything)
3. **Script-file delegation** (no `$()` in tool input → no heuristic to suppress)

## Why It Matters

The compound-workflows plugin has 27+ `VAR=$(cmd)` patterns in command init blocks that trigger permission prompts. Static rules can't suppress `VAR=$(...)` patterns (first token is a variable assignment, no rule matches). Hooks can't help either (heuristics fire before hooks, and the hook explicitly bails on `$()` at line 84-86 of auto-approve.sh).

Script-file delegation is the only approach that:
- Works universally (no static rules, no hooks, no setup required)
- Keeps `$()` entirely out of the Bash tool input
- Is safe (unlike `bash -c` which is a universal bypass for arbitrary inline code)

## The Pattern: init-values.sh

```bash
# Inside the command (.md file) — clean, no $():
bash plugins/compound-workflows/scripts/init-values.sh brainstorm

# Inside init-values.sh — $() is fine here, heuristic doesn't see it:
PLUGIN_ROOT="plugins/compound-workflows"
[[ -f "$PLUGIN_ROOT/CLAUDE.md" ]] || PLUGIN_ROOT=$(find "$HOME/.claude/plugins" ...)
RUN_ID=$(uuidgen | cut -c1-8)
STATS_DATE=$(date +%Y-%m-%d)
echo "PLUGIN_ROOT=$PLUGIN_ROOT"
echo "RUN_ID=$RUN_ID"
echo "DATE=$STATS_DATE"
```

Model reads the labeled output and tracks values for the rest of the command.

**Bootstrap:** The script needs to be found first. Try the local path (`bash plugins/compound-workflows/scripts/init-values.sh`), fall back to a clean find call (`find ~/.claude/plugins -name "init-values.sh" -path "*/compound-workflows/*" | head -1`) — also no `$()` in tool input.

## Evidence Chain

1. **Empirical test 1:** `bash -c 'TEST_VAL=$(echo "hello"); echo $TEST_VAL'` auto-approved via `Bash(bash:*)` static rule. Confirmed `$()` inside quoted string is suppressed by static rule matching first token.
2. **Empirical test 2:** `bash -c 'PLUGIN_ROOT=$(find ...); RUN_ID=$(uuidgen ...); echo ...'` — all patterns auto-approved in one call.
3. **Key insight:** `bash script.sh` has NO `$()` in the tool input at all. No heuristic fires. No static rule needed. Auto-approves by default.
4. **Precedent:** `validate-stats.sh` (jak v2.4.1) already uses this pattern — `bash validate-stats.sh "$STATS_FILE" N` replaced inline `ENTRY_COUNT=$(grep -c ...)`. Retroactively confirmed as the same bypass mechanism.

## Alternatives Ruled Out

| Approach | Why rejected |
|----------|-------------|
| `bash -c` wrapper | Requires `Bash(bash:*)` or `Bash(bash -c:*)` static rule. `bash -c` is a universal bypass for arbitrary inline code — no path scoping possible. Unsafe for "safe" profile. |
| Split-calls | Works (no `$()`) but model must track 3-5 values across separate calls. Sonnet robustness concern. |
| Hook modification | Dead end. Hooks fire AFTER heuristics. Hook explicitly bails on any command containing `$(`. Even if modified, cannot override heuristic. |
| Framework env vars | Not available in Claude Code plugin architecture. |

## Fragility

**HIGH** — This finding depends on undocumented Claude Code internals:

- Heuristic behavior is observed, not specified. Could change in any Claude Code update.
- If Claude Code begins inspecting script file contents before approving, the bypass closes.
- The hook's `$()` bail-out (line 84-86) is defensive but irrelevant — heuristics fire first anyway.
- During `/compound:work`, hooks are suppressed via `.work-in-progress` sentinel — the bypass is unmitigated.

**Verification cadence:** <60 seconds after any Claude Code version update. Test: `bash -c 'echo $(date)'` should auto-approve with `Bash(bash:*)` rule; `bash script-with-dollar-paren.sh` should auto-approve without any rule.

## Additional Findings (Same Session)

- **`bash -c` is unsafe as a static rule:** `Bash(bash -c:*)` auto-approves arbitrary inline code. Universal bypass with no path scoping. Permissive profile only.
- **Multi-word static rule prefixes work:** `Bash(for id:*)` confirmed in settings.local.json. Multi-word matching is supported.
- **Zero `$()` in agent YAML files:** Confirmed empirically. Agent files are system prompts, not model-interpreted bash. QA scanning agents is future-proofing.

## Reuse Triggers

Re-read this document when:
- Adding any `bash script.sh` invocation to a command, agent, or skill file
- After any Claude Code release (check for heuristic changes)
- Designing QA checks that scan command files for `$()` patterns
- Evaluating whether hooks can enforce bash safety at the tool-call level
- Someone proposes `bash -c` as a solution to permission prompts

## Cross-References

- **Extends:** `docs/solutions/claude-code-internals/2026-03-10-static-rules-suppress-bash-heuristics.md` — adds script-file delegation as a third mechanism
- **Grounds:** `docs/brainstorms/2026-03-11-heuristic-audit-scope-expansion-brainstorm.md` (bead 3l7, D2) — provides empirical basis for init-values.sh approach
- **Explains:** jak v2.4.1 validate-stats.sh — retroactively confirms why script delegation eliminated ENTRY_COUNT prompts
