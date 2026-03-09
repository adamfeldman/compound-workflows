---
title: Bash QA Script Patterns for Plugin Quality Enforcement
date: 2026-03-08
category: qa-infrastructure
tags: [bash, grep, hooks, subagent-dispatch, false-positives, performance]
severity: medium
component: plugins/compound-workflows/scripts/plugin-qa
origin_plan: docs/plans/2026-03-08-feat-context-lean-enforcement-plan.md
origin_brainstorm: docs/brainstorms/2026-03-08-context-lean-enforcement-brainstorm.md
---

## Problem

During v1.8.0 implementation of 4 Tier 1 bash QA scripts (`file-counts.sh`, `truncation-check.sh`, `stale-references.sh`, `context-lean-grep.sh`) and a PostToolUse hook for automatic enforcement, six distinct problems emerged:

1. **While-loop variables vanishing** -- counters and arrays modified inside `grep | while read` loops were always zero after the loop.
2. **Script timeouts** -- line-by-line processing with per-line grep spawned ~50,000 processes on 93 files, causing hangs.
3. **English phrase false positives** -- `Task [a-z]+` matched "Task system", "Task within" in natural prose.
4. **Ban-text self-detection** -- `DO NOT call TaskOutput` flagged as TaskOutput usage.
5. **Proximity window too small** -- 20-line lookahead for OUTPUT INSTRUCTIONS missed legitimate Task blocks with ~15-line embedded MCP prompts.
6. **Subagent permission failure** -- subagent dispatched to create `.claude/hooks/` files hit a platform-level write restriction.

## Root Cause Analysis

### 1. Pipe-Subshell Variable Loss

- **Symptom:** `finding_count` always 0 after `grep -rn ... | while read` loop.
- **Root cause:** In bash, the right side of a pipe runs in a subshell. Variables modified in the subshell are not visible to the parent. Additionally, `grep ... || true | while` has unexpected precedence -- `||` binds lower than `|`, so `|| true` captures the exit, and the while loop never receives input.
- **Why not caught earlier:** No shellcheck integration. ShellCheck flags this as SC2030/SC2031.

### 2. Line-by-Line Processing Performance

- **Symptom:** Scripts hung or timed out on the 93-file plugin directory.
- **Root cause:** Iterating every line of every file and spawning a `grep` subprocess per line is O(lines x files) process creation. On a 93-file codebase with ~5,000 total lines, this means ~50,000 subprocess spawns.
- **Why not caught earlier:** No performance test. A `time` invocation on the full directory would have revealed the issue in seconds.

### 3. Regex Over-Matching Natural Language

- **Symptom:** Scripts reported findings for English phrases like "each Task system" and "the Task within".
- **Root cause:** `Task [a-z]+` is too broad. The codebase convention is that all agent names contain hyphens (e.g., `code-simplicity-reviewer`), but the regex did not require them.
- **Why not caught earlier:** No negative test fixtures containing English phrases with "Task".

### 4. Self-Referential Pattern Detection

- **Symptom:** Lines like `DO NOT call TaskOutput` flagged as TaskOutput usage.
- **Root cause:** The detection regex searches for `TaskOutput` without distinguishing usage from prohibition. Files that document the ban inevitably contain the banned term.
- **Why not caught earlier:** No fixture file containing only ban text. This is a general problem class: any script that detects pattern X in files that also ban X.

### 5. Insufficient Proximity Window

- **Symptom:** Legitimate Task blocks with MCP relay prompts (~15 lines of embedded content) flagged as missing OUTPUT INSTRUCTIONS.
- **Root cause:** Window was set to 20 lines without measuring actual content distances. The longest legitimate Task-to-OUTPUT-INSTRUCTIONS distance was ~25 lines.
- **Why not caught earlier:** Window size was a magic number with no documented rationale or empirical measurement.

### 6. Subagent .claude/ Write Restriction

- **Symptom:** Subagent dispatched to create `.claude/hooks/commit-qa.sh` failed with a permission error.
- **Root cause:** Claude Code restricts subagent (Task/Agent tool) filesystem access to `.claude/` as a platform-level security boundary. Only the main orchestrator context can write there.
- **Why not caught earlier:** Constraint is documented in MEMORY.md but the work plan still dispatched the step to a subagent.

## Solution

### 1. Process Substitution Over Pipes

Replace pipe-connected while loops with process substitution so the loop runs in the current shell:

```bash
# BROKEN -- while runs in subshell, variables don't propagate
grep -rn "pattern" . | while IFS=: read -r file line_num content; do
  finding_count=$((finding_count + 1))
done

# FIXED -- while runs in current shell via process substitution
while IFS=: read -r file line_num content; do
  finding_count=$((finding_count + 1))
done < <(grep -rn "pattern" . || true)
```

The `|| true` goes inside the process substitution, avoiding the precedence trap where `|| true | while` silently swallows grep output. This approach was chosen over temp files because it avoids cleanup logic and over here-strings because multi-line grep output doesn't work with `<<<`.

### 2. Batch-Then-Filter Architecture

Use a single bulk `grep -rn` to find all matches, then run expensive checks only on matching lines:

```bash
# BROKEN -- spawns grep per line (O(lines x files) processes)
for file in *.md; do
  while IFS= read -r line; do
    echo "$line" | grep -q "pattern" && ...
  done < "$file"
done

# FIXED -- one grep, post-filter only matches
while IFS=: read -r file line_num content; do
  # Expensive check (e.g., code-block detection) only on the ~dozen matches
  block_count=$(head -n "$line_num" "$file" | grep -c '^```')
  if (( block_count % 2 == 0 )); then
    add_finding ...
  fi
done < <(grep -rn "pattern" "$search_dir" || true)
```

Chosen over awk-based approaches because individual scripts remain readable and the performance gain (from O(lines x files) to O(matches)) is sufficient.

### 3. Codebase-Convention Regex Tightening

Exploit naming conventions to eliminate false positives without reducing true positives:

```bash
# BROKEN -- matches English phrases ("Task system", "Task within")
grep -En 'Task [a-z]+' "$file"

# FIXED -- require hyphens (all agent names contain hyphens per CLAUDE.md Agent Registry)
grep -En 'Task [a-z][a-z0-9]*-[a-z][a-z0-9-]*' "$file"
```

This works because the codebase enforces hyphenated agent names. The constraint is free (no false negatives) and eliminates the entire class of English-phrase false positives.

### 4. Pre-Filter Prohibition Lines

Skip lines that ban a pattern before checking for usage of that pattern:

```bash
# Before checking if $content uses TaskOutput, skip prohibition lines
if echo "$content" | grep -qE '(DO NOT|NEVER|do not|never|banned).*TaskOutput'; then
  continue
fi
```

Applied to any detection script where the codebase contains documentation of the banned pattern. A `lib.sh` helper `is_prohibition_line` could generalize this for future scripts.

### 5. Measured Proximity Windows with Documented Rationale

Set window sizes based on empirical measurement, with margin and documentation:

```bash
# Max measured: 25 lines (brainstorm.md Opus relay block with ~15-line embedded prompt)
# Window: 30 lines (20% margin)
# Revisit if Task block structure changes (e.g., longer embedded prompts)
LOOKAHEAD_WINDOW=30
```

The 20% margin was chosen as a balance between catching real violations and tolerating format variation.

### 6. Split Protected Path Writes to Orchestrator

Design task dispatch so the higher-privilege context handles protected paths:

```
Orchestrator (main context):
  1. Create/modify .claude/hooks/* files       <-- protected, orchestrator only
  2. Update .claude/settings.local.json        <-- protected, orchestrator only
  3. Dispatch subagent for remaining work

Subagent:
  1. Modify plugin files, scripts, docs        <-- unprotected
  2. Manage .workflows/.work-in-progress       <-- unprotected
```

Any plan that touches `.claude/`, `.git/`, or other system directories must assign those steps to the orchestrator. The work command should pre-scan plans for protected paths before dispatching.

## Prevention

### Immediate (v1.8.0)

- **ShellCheck integration:** Run `shellcheck -e SC1091 scripts/plugin-qa/*.sh` to catch pipe-subshell issues statically. SC1091 is suppressed because shellcheck cannot follow `source lib.sh` with dynamic paths.
- **Banned constructs in lib.sh header:** Document that `cmd | while read` (when modifying state) and `grep ... || true | while` are banned patterns.
- **Performance rule in lib.sh:** "Never iterate lines of files and spawn per-line subprocesses. Use bulk grep first, post-filter matches."
- **Design checklist for detection scripts:** "Does the codebase contain prohibition/documentation of the pattern you're detecting? If yes, add pre-filters for negation phrases."
- **Subagent constraints in AGENTS.md:** "Subagents cannot write to `.claude/`, `.git/`, or other system-protected directories."

### Deferred (v2 Fixture-Based Tests)

Test fixtures directory at `plugins/compound-workflows/scripts/plugin-qa/tests/fixtures/`:

- **`passing/`** -- Zero-finding fixtures with well-formed commands, agents, and correct CLAUDE.md counts. All 4 scripts must report `Total findings: 0`.
- **`failing/`** -- One violation per fixture file. Includes `taskoutput-ban-only.md` (negative test: contains only ban text, must report 0 findings), `pattern-b.md` (1 finding), `bare-mcp-call.md` (1 finding).
- **`stale-refs/`** -- Old namespace references, missing commands, missing agents.
- **Boundary tests:** OUTPUT INSTRUCTIONS at line 28 (within 30-line window, 0 findings) and at line 31 (outside window, 1 finding).

Test runner (`run-tests.sh`) uses `assert_finding_count` helper:

```bash
assert_finding_count() {
  local script="$1" fixture_root="$2" expected="$3" label="$4"
  local actual
  actual=$("$SCRIPT_DIR/$script" "$fixture_root" 2>/dev/null \
    | grep -oE 'Total findings: [0-9]+' | grep -oE '[0-9]+')
  if [ "${actual:-0}" -ne "$expected" ]; then
    echo "FAIL: $label -- expected $expected findings, got ${actual:-0}"
    failures=$((failures + 1))
  else
    echo "PASS: $label"
  fi
}
```

Key fixture design principles:
1. One violation per fixture file for clear traceability.
2. Negative fixtures are as important as positive ones (ban-text, English-phrase, large-window tests).
3. Fixture CLAUDE.md/plugin.json counts match the fixture directory (self-contained, no real plugin references).
4. Each file 10-30 lines max; full suite runs in <2 seconds.

## Related Documents

### Direct Lineage
- **Origin brainstorm:** `docs/brainstorms/2026-03-08-context-lean-enforcement-brainstorm.md` -- 7 key decisions including hook-based enforcement and hybrid Tier 1/Tier 2 QA.
- **Origin plan:** `docs/plans/2026-03-08-feat-context-lean-enforcement-plan.md` -- 5-phase plan, 4 bash scripts, 1 command, hook config.
- **Deepen-plan synthesis:** `.workflows/deepen-plan/feat-context-lean-enforcement/run-1-synthesis.md` -- 21 findings from 14 agents (1 CRITICAL, 7 SERIOUS, 13 MINOR).

### Research Files (Bash Scripts)
- `.workflows/deepen-plan/feat-context-lean-enforcement/agents/run-1/research--bash-qa-scripts.md` -- Portable bash conventions, code block handling, proximity detection, false positive sources.
- `.workflows/plan-research/context-lean-enforcement/agents/repo-research.md` -- File-by-file audit of every file to modify.

### Research Files (Hooks)
- `.workflows/deepen-plan/feat-context-lean-enforcement/agents/run-1/research--hooks-api.md` -- PostToolUse event, exit 2 semantics, stdin JSON schema, matcher regex, timeout handling.
- `.workflows/plan-research/context-lean-enforcement/agents/specflow.md` -- Hook API as highest-risk unknown (resolved by deepen-plan).

### Research Files (Subagent Dispatch)
- `.workflows/deepen-plan/feat-context-lean-enforcement/agents/run-1/research--mcp-wrapping.md` -- MCP tool access inherited by subagents, transformation template.
- `.workflows/deepen-plan/feat-context-lean-enforcement/agents/run-1/review--architecture.md` -- CRITICAL sentinel file gap, worktree race condition, `git diff-tree` recommendation.

### Antecedent Work
- `docs/plans/2026-03-08-feat-plan-readiness-agents-plan.md` (v1.7.0) -- Established the `lib.sh` pattern, `|| true` convention, and output format used by the v1.8.0 scripts.
- `docs/solutions/process-analysis/2026-03-08-deepen-plan-iteration-taxonomy.md` -- Iteration taxonomy; Category 3 (edit-induced inconsistencies) is what `context-lean-grep.sh` proximity detection addresses.

### Session Research
- `.workflows/compound-research/context-lean-qa-scripts/agents/` -- The 5 agent outputs (context.md, solution.md, related-docs.md, prevention.md, category.md) synthesized into this document.

## Reuse Triggers

Re-read this document when:

- **Writing bash scripts that process grep output** -- process substitution pattern, `|| true` placement, batch-then-filter architecture.
- **Creating PostToolUse hooks** -- exit code semantics (0/2/non-zero), sentinel file suppression, `git diff-tree` for inspecting committed files, `.claude/settings.local.json` registration.
- **Dispatching subagents to write config files** -- `.claude/` is a protected path; split writes so orchestrator handles protected paths.
- **Building grep-based linters or detection scripts** -- false positive reduction via codebase naming conventions, self-referential ban text pre-filtering, proximity window sizing with documented rationale.
- **Designing test fixtures for QA scripts** -- one violation per file, negative fixtures for false positive exclusion, boundary tests for window edges, self-contained fixture directories.
- **Adding new Tier 1 QA checks** -- follow the `lib.sh` shared library pattern, use the standard output format (`## Findings` / `## Summary`), integrate with the hook via the common runner.
