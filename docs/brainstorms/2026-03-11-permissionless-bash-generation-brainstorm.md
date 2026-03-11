---
title: Permissionless Bash Generation
date: 2026-03-11
bead: dndn
status: complete
---

# Permissionless Bash Generation

## What We're Building

CLAUDE.md instructions that teach Claude Code to generate bash for the Bash tool that avoids triggering Claude Code's built-in permission prompt heuristics during normal conversation.

**Scope:** Only Bash tool input — the command string that Claude Code's heuristic inspector evaluates. Does NOT apply to script files written via the Write tool (heuristics don't inspect file content), nor to existing plugin command/skill templates (already handled by v2.5.0).

**Problem:** When Claude Code generates ad-hoc bash during conversation (debugging, data analysis, iteration, bead management), it frequently uses patterns that trigger permission prompts:
- `$()` command substitution: `for id in ...; do est=$(bd show ... | grep ...); done`
- `$(())` arithmetic: `echo $((count + 1))`
- "Quoted characters in flag names": redirect + quoted dash string in compound commands (empirically verified — see Empirical Findings below)
- Heredocs in compound chains: `mkdir -p dir && cat > file << 'EOF'`
- Variable assignments with `$()`: `RESULT=$(grep pattern file)`
- Compound `&&` chains mixing clean commands with `$()` segments

These prompts interrupt flow and require manual approval for commands that are safe. JSONL analysis estimates 5-15 permission prompts per session from ad-hoc bash generation alone.

**Root cause:** The model has no instructions guiding its bash generation style. It defaults to idiomatic shell (using `$()` freely) rather than heuristic-clean patterns. The v2.5.0 work proved these patterns are avoidable — but that knowledge lives in command templates, not in generation rules.

## Empirical Findings

### "Quoted characters in flag names" — Root Cause Identified

Empirical testing isolated the trigger to: **redirect (`2>/dev/null`) + quoted dash string (`"---"`) in a compound command**, when the first token lacks a static rule.

| Command | Result | Why |
|---------|--------|-----|
| `echo "---"` alone | approved | Hook: `echo` in safe prefix list |
| `bd ready; echo "---"` | approved | Static rule `bd:*` suppresses |
| `echo "---" 2>/dev/null` | approved | Hook: single command, `echo` safe prefix |
| `echo test 2>/dev/null; echo "---"` | **prompted** | No `Bash(echo:*)` static rule; heuristic fires on redirect + quoted dashes |
| `bd ready 2>/dev/null; echo "---"` | **prompted** | Same — redirect + quoted dashes in compound |
| `bd ready 2>/dev/null; echo "separator"` | approved | No quoted dash string |
| `bd ready; echo "---"` (no redirect) | approved | No redirect in command |

**Key insight:** `--flag=value` alone is NOT a heuristic trigger. The trigger is the combination of redirect characters and quoted strings containing dashes in compound commands. The heuristic likely interprets `"---"` as a quoted flag name in the context of redirect-containing commands.

**Model fix:** Don't use `echo "---"` as a separator in compound commands. Use separate Bash tool calls instead of chaining with `; echo "---";`.

### JSONL Session Log Analysis

Analyzed 6 main sessions + 15 subagent sessions. Top 5 actionable patterns NOT covered by existing static rules:

1. **`VAR=$(cmd)`** — Variable assignment with command substitution (9 unique patterns, HIGH frequency). First token is `VAR=`, no static rule can match.
2. **`which cmd && cmd --flag $(cmd2)`** — Availability check + usage chain (MEDIUM frequency). `which` has no static rule.
3. **`tmpfile=$(mktemp) && ...`** — Temp file workflows (LOW-MEDIUM frequency).
4. **`mkdir -p dir && cat > file << 'EOF'`** — File creation chains where `cat` isn't the first token (MEDIUM frequency).
5. **`$((expression))` in assignments** — Arithmetic expansion triggers same heuristic as `$()` (LOW frequency).

Full analysis: `.workflows/brainstorm-research/permissionless-bash-generation/jsonl-heuristic-analysis.md`

### Patterns Already Handled by Static Rules

These ad-hoc patterns are suppressed by existing `Bash(X:*)` rules and need no CLAUDE.md guidance:
- `for` loops with `$()` inside → `Bash(for:*)` suppresses entire command
- `python3 << 'PYEOF'` → `Bash(python3:*)` suppresses heredoc
- `bd create --metadata '{"impact":...}'` → `Bash(bd:*)` suppresses `{"`
- `git commit -m "$(cat <<'EOF'..."` → `Bash(git:*)` suppresses `$()` + `<<`
- ~~`cat >> file <<'EOF'` → `Bash(cat:*)` suppresses heredoc + redirect~~ **DISPROVED:** `<<` heredoc is a "hard" heuristic NOT suppressed by static rules (bead ywug, Test 5 in solution doc). Fix: move heredoc into a script file (append-snapshot.sh).

### `2>/dev/null` — The Common Enabler

`2>/dev/null` (stderr suppression) appears in nearly every exploratory command. Empirical testing reveals it is the **common enabler** for multiple heuristic triggers. Without it, globs and quoted dash strings are fine. With it, they prompt.

**Empirical findings (all verified):**

| Command | Result | Why |
|---------|--------|-----|
| `ls *.md` | approved | Glob alone is fine |
| `ls file.md 2>/dev/null` | approved | Redirect alone is fine |
| `ls *.md 2>/dev/null` | **prompted** | Glob + redirect triggers |
| `ls docs/*.md 2>/dev/null` | **prompted** | Same — path glob + redirect |
| `echo "---"` | approved | Quoted dashes alone is fine |
| `echo "---" 2>/dev/null` (single cmd) | approved | Single command with redirect OK |
| `cmd 2>/dev/null; echo "---"` | **prompted** | Redirect + quoted dashes in compound |
| `bd ready; echo "---"` (no redirect) | approved | No redirect = no trigger |
| `bd ready 2>/dev/null; echo "separator"` | approved | No quoted dashes = no trigger |

**Two confirmed trigger combinations:**
1. **Glob (`*`) + redirect (`>`)** in same command — e.g., `ls *.md 2>/dev/null`
2. **Quoted dash string (`"---"`) + redirect in compound command** — e.g., `cmd 2>/dev/null; echo "---"`

**Model fix: stop appending `2>/dev/null` by default.** Let stderr show. It's almost never harmful in conversation. The model adds it reflexively to suppress error output, but this directly causes permission prompts when combined with common patterns (globs, separators). Dropping `2>/dev/null` eliminates an entire class of triggers at zero cost.

## Why Not Do Nothing

5-15 permission prompts per session at ~2 seconds each is 10-30 seconds of wall time. The cost isn't the seconds — it's the 15 cognitive context switches. Each prompt forces the user to stop what they're reading, evaluate a bash command, decide if it's safe, and click approve. This breaks flow disproportionate to its time cost. In long sessions with complex workflows, prompt fatigue leads to reflexive "yes" clicking — which defeats the security purpose of the prompts and trains the user to ignore them for commands that actually warrant attention.

## Why This Approach

### Approach: CLAUDE.md principles + concrete before/after examples

**Chosen over:**
- Hook-based nudging (PostToolUse feedback) — adds moving parts, doesn't prevent the prompt
- Examples only (no principles) — principles explain the *why*, helping the model adapt to novel cases
- Strict enforcement (hard ban) — too rigid; some rare cases genuinely need `$()` and the alternative would produce wrong results

### Delivery mechanism

1. **Plugin CLAUDE.md** — new top-level "Bash Generation Rules" section. Ships with the plugin, applies everywhere it's installed. Clear signal this is about ALL bash the model generates in conversation, not just plugin internals.
2. **User's global `~/.claude/CLAUDE.md`** — optional augmentation for personal preferences or stricter rules.

### Enforcement level

**Strong advisory** — "you SHOULD avoid" not "you MUST never use." Default to clean patterns. Use `$()` only when the alternative would likely produce wrong results (not just more verbose).

## Key Decisions

### D1: Scope is Bash tool input only
The rules apply to the command string submitted to the Bash tool — what Claude Code's heuristic inspector evaluates. Content of script files (.sh) written via Write tool is exempt. This is the same insight that makes init-values.sh work: `$()` inside a .sh file is invisible to heuristics.

**Rationale:** Script files are normal shell programming. Constraining their content would make them worse. The problem is specifically the Bash tool command parameter.

### D2: Location is a new top-level CLAUDE.md section
Not nested under "Permission Architecture" or "Command Robustness Principles" — those address plugin development. This section addresses ALL in-conversation bash generation.

### D3: Strong advisory, not strict enforcement
Avoid `$()` unless the alternative would likely produce wrong results. The model exercises judgment but defaults to clean patterns. This handles the rare case where split-calls genuinely can't work (e.g., atomic operations where a value must be captured and used in the same shell invocation).

### D4: Plugin ships defaults, global augments
Core rules in plugin CLAUDE.md. Users can add stricter or project-specific rules in their global `~/.claude/CLAUDE.md`. This matches the existing config split pattern (compound-workflows.md committed + compound-workflows.local.md gitignored).

### D5: Patterns derived from v2.5.0 work
The avoidance techniques are proven: split-calls, script delegation, model-side tracking, Write tool + `-F`/`--body-file`. We're extracting these from command templates and generalizing them as model behavior rules.

### D6: Opt-in via setup injection (revised after red team)
~~Config key `reduce_bash_prompts`~~ — red team (all 3 providers) correctly identified that an LLM can't reliably deactivate loaded CLAUDE.md instructions based on a config value. Replaced with: `/compound:setup` asks "Enable bash prompt reduction?" and writes the rules into the project's CLAUDE.md only if the user opts in. Not loaded = not active. No runtime config check needed.

### D7: $() acceptable only for atomic operations or practical escape valve
Default to split-calls. Allow `$()` only when (a) the value would change between separate calls (race condition), or (b) split-calls have caused problems in the current conversation. Verbosity is never a justification.

## Avoidance Patterns (Before/After)

These are the concrete patterns to include in CLAUDE.md. Derived from the v2.5.0 heuristic audit work.

### Pattern 1: Variable capture → split-call

```bash
# AVOID — triggers $() heuristic:
HASH=$(shasum -a 256 file.txt | cut -d' ' -f1)
echo "Hash: $HASH"

# PREFER — run command, read output, use value in next call:
shasum -a 256 file.txt
# (read hash from output, then use it in next Bash call)
```

### Pattern 2: Loop with capture → separate commands

```bash
# AVOID — triggers $() heuristic:
for id in dndn yod wtn; do est=$(bd show "$id" | grep estimate); echo "$id: $est"; done

# PREFER — run each command separately:
bd show compound-workflows-marketplace-dndn
bd show compound-workflows-marketplace-yod
bd show compound-workflows-marketplace-wtn
# (read outputs, synthesize results)
```

### Pattern 3: Inline date/uuid → let the tool provide it

```bash
# AVOID — triggers $() heuristic:
echo "Report generated: $(date +%Y-%m-%d)"

# PREFER — use date command directly:
date +%Y-%m-%d
# (read output, incorporate into next command)
```

### Pattern 4: Arithmetic → deterministic computation

```bash
# AVOID — triggers $(()) heuristic:
TOTAL=$(( count1 + count2 ))

# PREFER — use a deterministic tool for dynamic values:
python3 -c "print(5 + 3)"
# or: echo "5 + 3" | bc
# For known constants, substitute the literal directly.
# Do NOT do model-side math on dynamic/parsed values — use a tool.
```

### Pattern 5: Heredoc in commit → Write tool + -F

```bash
# AVOID — triggers $() + heredoc heuristics:
git commit -m "$(cat <<'EOF'
Fix the bug

Detailed description here.
EOF
)"

# PREFER — Write tool creates file, then:
git commit -F .workflows/tmp/commit-msg.txt
```

### Pattern 6: Complex logic → temp script (red team addition)

```bash
# AVOID — loop with $() in Bash tool input:
for id in $(bd list --json | jq -r '.[].id'); do
  count=$(grep -c "$id" log.txt)
  echo "$id: $count"
done

# PREFER — Write tool creates a .sh script, then execute:
# (Write tool writes to .workflows/tmp/analysis.sh with the loop logic)
bash .workflows/tmp/analysis.sh
# $() inside the script is invisible to heuristics.
```

### Pattern 7: Don't append 2>/dev/null reflexively

```bash
# AVOID — redirect enables heuristic triggers:
ls *.md 2>/dev/null
bd ready 2>/dev/null; echo "---"

# PREFER — let stderr show:
ls *.md
bd ready; echo "---"
# Stderr is almost never harmful in conversation.
# Only suppress stderr when error output would genuinely confuse.
```

### Pattern 8: Compound chain with $() → split into calls

```bash
# AVOID — $() poisons entire compound chain:
TIMESTAMP="$(date +%s)" && cat >> file.yaml <<EOF
timestamp: $TIMESTAMP
EOF

# PREFER — get timestamp first, then write:
date +%s
# (read timestamp, then use Write tool to append to file)
```

## Resolved Questions

### Q1: What triggers "quoted characters in flag names"?
**Resolved via empirical testing.** The trigger is redirect + quoted dash string (`"---"`) in compound commands, NOT `--flag=value` syntax. See Empirical Findings section above.

### Q3: Should redirects (>, >>) be addressed?
**Resolved: yes — `2>/dev/null` is the primary enabler.** Empirical testing showed `2>/dev/null` is the common enabler for the "quoted characters in flag names" heuristic. Glob + redirect and quoted dashes + redirect both trigger, but neither triggers without the redirect. **The model should stop reflexively appending `2>/dev/null`.** Let stderr show — it's almost never harmful in conversation.

### Q2: When is $() acceptable?
**Resolved:** Two cases justify `$()` in Bash tool input:
1. **Atomic operations** — the value would change between separate Bash tool calls (race conditions, transactional reads).
2. **Practical escape valve** — the model has tried split-calls and they've caused problems in the current conversation (e.g., value tracking errors, excessive back-and-forth).

Verbosity alone is not a justification. More Bash calls is fine; wrong results isn't.

**User rationale:** The goal is pragmatic — default to clean patterns, but don't force the model into a corner where it can't get the job done.

### Q4: Impact on other projects
**Resolved:** Rules are opt-in via `/compound:setup`. Setup asks "Enable bash prompt reduction?" and writes the rules into the project's CLAUDE.md only if the user opts in. Projects that don't run setup or decline the option don't get the rules. Not loaded = not active — no runtime config toggle needed.

**User rationale (revised after red team):** An LLM can't reliably deactivate loaded instructions via a config value. The mechanism must be "not loaded = not active." Setup injection is the cleanest approach.

## Red Team Resolution Summary

Red team by Gemini, OpenAI, Claude Opus on 2026-03-11.

### CRITICAL Resolutions

| # | Finding | Providers | Resolution |
|---|---------|-----------|------------|
| C1 | Wrong abstraction layer — fix heuristics not model | All 3 | **Valid — hybrid approach.** Expand static rules for coverable patterns AND add CLAUDE.md rules for uncoverable ones (VAR=$()). Both layers. |
| C2 | Split-call cost unexamined — may cost more than prompts | Gemini, Opus | **Valid — offer both patterns.** Split-calls for simple cases (1-2 values), temp .sh scripts for complex cases (loops, pipelines). Model chooses. |
| C3 | Config opt-out non-functional — LLM can't deactivate loaded rules | All 3 | **Valid — replaced with setup injection.** Rules written to project CLAUDE.md only during `/compound:setup` opt-in. Not loaded = not active. |

### SERIOUS Resolutions

| # | Finding | Providers | Resolution |
|---|---------|-----------|------------|
| S1 | Write temp scripts as primary strategy | Gemini, Opus | **Valid — incorporated.** Added as equal-weight alternative to split-calls in D7. Model chooses based on complexity. |
| S2 | Split-calls break shell semantics (variables, CWD, exit codes) | Gemini, Opus | **Valid — note in rules.** CLAUDE.md rules must note: variables don't persist across Bash calls, exit code propagation lost. CWD does persist (Claude Code maintains it). These are reasons to use temp scripts for complex chains. |
| S3 | Model may not reliably follow syntax-level CLAUDE.md rules | Opus | **Accepted limitation.** CLAUDE.md is the only mechanism available for shaping ad-hoc generation. Training priors for `$()` are strong. We hope the rules work, iterate if needed. No alternative exists short of upstream Claude Code changes. |
| S4 | Additional static rules not explored | Opus | **Valid — incorporate.** Setup should suggest adding `Bash(which:*)`, `Bash(echo:*)`, etc. for patterns that static rules can cover. CLAUDE.md rules are only for the remainder. |
| S5 | Pattern 4 (model-side arithmetic) → correctness risk | OpenAI | **Valid — revise Pattern 4.** Replace "compute the value yourself" with "use `python3 -c`, `bc`, or `awk` for arithmetic." Model-side math on dynamic values is error-prone. |
| S6 | Echo "---" fix too aggressive — just use different separator | Gemini | **Moot after redirect finding.** The real fix is "don't use `2>/dev/null`" which eliminates the entire trigger class. If redirect is unavoidable, a different separator works too. |
| S7 | Heredoc guidance contradicts AGENTS.md | Opus | **Valid — note exception.** `Bash(git:*)` static rule suppresses heredoc heuristic for git commits. CLAUDE.md rules should note: "git commands are covered by static rules and can use any pattern including heredocs." No contradiction when properly scoped. |

**Fixed (batch):** 7 SERIOUS items resolved — 5 incorporated as changes, 1 accepted limitation, 1 moot.

### MINOR Resolutions

7 MINOR findings triaged. 1 fixable (applied: "never" → "not" tone fix). 3 manual review: #2 already resolved by post-red-team revisions; #3 deferred to new bead vqb3 (sunset mechanism, P3); #4 qualitative argument sufficient (prompts break flow, not just seconds); #5 "why not do nothing" paragraph added. 3 no-action: #6 opt-out already resolved, #7 heredoc already resolved, #8 "proven" limitation already acknowledged.
