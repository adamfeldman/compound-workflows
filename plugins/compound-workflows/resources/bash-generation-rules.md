## Bash Generation Rules

> Injected by `/compound:setup` — teaches the model to generate bash that avoids Claude Code's permission prompt heuristics.

These rules apply to the command string submitted to the Bash tool — what Claude Code's heuristic inspector evaluates. They do NOT apply to script files written via the Write tool (heuristics don't inspect file content).

**Principle:** You SHOULD avoid patterns that trigger Claude Code's permission prompt heuristics in Bash tool commands. Default to split-call or temp-script alternatives. Use `$()` only when: (a) the value would change between separate Bash calls (atomic operation), or (b) split-calls have caused problems in the current conversation. Verbosity is not a justification — more Bash calls is fine; wrong results isn't.

**Do NOT append `2>/dev/null` reflexively.** It enables heuristic triggers when combined with globs (`ls *.md 2>/dev/null`) or quoted-dash strings in compounds (`cmd 2>/dev/null; echo "---"`). Let stderr show — it's almost never harmful in conversation.

### Avoidance Patterns

| # | Instead of | Use |
|---|-----------|-----|
| 1 | `VAR=$(cmd)` | Run `cmd` alone, read output, use value in next Bash call |
| 2 | `for ...; do val=$(cmd); done` | Run each command separately, synthesize results |
| 3 | `echo "$(date)"` | Run `date` alone, incorporate output in next call |
| 4 | `$(( x + y ))` | `python3 -c "print(x + y)"` or `echo "x + y" \| bc` |
| 5 | `git commit -m "$(cat <<'EOF'...)"` | Write tool creates file, then `git commit -F file` |
| 6 | Complex loops/pipelines with `$()` | Write tool creates .sh script, then `bash script.sh` |
| 7 | `ls *.md 2>/dev/null` | `ls *.md` (let stderr show) |
| 8 | `TS="$(date)" && cat >> f` | Get timestamp first, then Write tool appends |

### When $() Is Acceptable

- **Atomic operations** — the value would change between separate Bash tool calls
- **Practical escape valve** — split-calls have caused problems in the current conversation

### Notes

- Variables do NOT persist across Bash tool calls (each is a fresh shell). CWD does persist.
- Commands covered by `Bash(X:*)` static rules (git, for, python3, bd, cat) can use any pattern — static rules suppress heuristics entirely.
- These rules apply to in-conversation bash only. Script files (.sh) use normal shell idioms.
