---
date: 2026-03-10
topic: plugin-heuristic-audit
bead: jak
status: brainstorm
---

# Plugin Heuristic Audit — Brainstorm

## What We're Building

Audit all plugin command files (brainstorm.md, plan.md, deepen-plan.md, work.md, review.md, compact-prep.md, setup.md) for bash patterns that trigger Claude Code's built-in safety heuristics — `$()`, heredocs (`<<`), `>>` redirects, backticks, multi-line scripts — and rewrite the worst offenders to eliminate mid-workflow permission prompts. Init-block prompts (one per workflow phase start) are accepted as unavoidable; the target is mid-workflow prompts that interrupt work.

### Scope

Plugin-side rewrites plus sentinel-related hook changes. The sentinel redesign (Decision 7) requires coordinated changes to both plugin commands (work.md) and the PostToolUse hook (plugin-qa-check.sh), so jak owns the full sentinel change. Other hook-side gaps (missing safe prefixes, Permissive profile rebuild, custom prefix support) stay in bead msm.

---

## Why This Approach

**Static rules are the primary fix** for most heuristic-triggering patterns. The empirical finding (see Critical Empirical Finding below) showed that static `Bash(X:*)` rules suppress Claude Code's built-in heuristics entirely — if the first token matches, the command is approved before any heuristic fires. This means P7 (git commit heredoc), P9 (cat >> heredoc), and bd metadata JSON are already solved for users with `git:*`, `gh:*`, `cat:*`, `bd:*`. The Permissive profile rebuild (msm) ensures new users get these rules.

**Plugin-side fixes target only what static rules can't cover:** VAR=$(...) patterns where the first token is a variable assignment (no static rule can match these). Specifically: ENTRY_COUNT validation (mid-workflow), sentinel cleanup via rm (mid-workflow), and trivial `$(echo $VAR)` cleanup (hygiene).

**Accept init-block prompts.** Init blocks (PLUGIN_ROOT detection, date, RUN_ID, stats file path) contain `$()` which is the sole heuristic trigger — NOT multi-line per se. Empirically verified: multi-line blocks without `$()` auto-approve fine. Init blocks prompt because they contain `$(find ...)`, `$(uuidgen ...)`, `$(date ...)`. One prompt at the start of each workflow phase is acceptable; it's not mid-workflow and doesn't interrupt momentum. The split-call pattern could theoretically eliminate these prompts by removing `$()`, but was rejected for reliability reasons (model error surface), not because "multi-line prompts anyway."

**Not chosen: split-call pattern.** Running `date` as a separate bash call, then having the model incorporate the literal output into subsequent commands. Rejected because: model error surface (silent wrong file paths if model misreads output), more total bash calls, and the multi-line heuristic fires anyway. The reliability cost outweighs the prompt reduction.

**Not chosen: MCP server.** A `cw_init_session()` MCP tool would eliminate all bash for utility operations, but the build cost (new project, distribution, user setup friction) is not justified for jak's scope. Plugin is currently dependency-free; this changes that unnecessarily.

**Not chosen: model-substituted date.** Model doesn't reliably know the current date.

**Backup option: Write tool + file-reference.** If static rules ever prove insufficient for P7 (e.g., Permissive profile is rejected), the Write tool can write commit messages / PR bodies to files, then `git commit -F` / `gh pr create --body-file` reference them. This eliminates heredocs and `$()` entirely. Kept as a fallback, not the primary approach.

---

## Key Decisions

### Decision 1: Target only mid-workflow prompts

Init blocks prompt because they contain `$()` — not because they are multi-line. Multi-line blocks without `$()` auto-approve fine (empirically verified). The split-call pattern could eliminate init-block `$()` but introduces reliability risks (model error surface for computed values). Init-block prompts occur once per workflow phase start and don't interrupt momentum.

**Rationale:** User said "accept one init-block prompt per workflow phase" — not painful in practice. The painful prompts are mid-workflow (stats validation after each dispatch batch, sentinel cleanup at workflow end).

### Decision 2: P7 (git commit/gh pr heredocs) — already solved by static rules

`git commit -m "$(cat <<'EOF'...EOF)"` first token is `git` → `Bash(git:*)` static rule suppresses all heuristics. Same for `gh pr create --body "$(cat <<EOF...)"` → `Bash(gh:*)`. No plugin rewrite needed.

For users without these static rules: msm's Permissive profile rebuild should include `git:*` and `gh:*`. Plugin-side Write tool rewrite is unnecessary complexity — the static rule is the correct fix.

**Backup option if Write tool approach is ever needed:** Write tool writes to `.workflows/.commit-msg`, then `git commit -F .workflows/.commit-msg`. Also `gh pr create --body-file .workflows/.pr-body.md` (`-F` flag confirmed).

### Decision 3: Replace ENTRY_COUNT with validate-stats.sh

`ENTRY_COUNT=$(grep -c '^---$' "$STATS_FILE")` (VAR=$() pattern, always prompts, 2-3 times per command) replaced with a new `validate-stats.sh` script called once at the end of each phase:

```
bash $PLUGIN_ROOT/scripts/validate-stats.sh "$STATS_FILE" $EXPECTED_COUNT
```

- **capture-stats.sh stays fire-and-forget** — `exits 0 always` invariant preserved. No change to existing script behavior.
- **validate-stats.sh** is the integrity check — `grep -c '^---$'` happens inside the script (hidden from Claude Code heuristics), returns non-zero + warning on count mismatch.
- **Cross-batch validation retained.** One call per phase replaces 2-3 mid-workflow ENTRY_COUNT prompts. Detection without recovery is still better than silent data loss.

**Dependency:** Requires `bash:*` static rule (in Permissive profile). Without it, the `bash validate-stats.sh` call itself prompts — but that's one prompt per phase instead of 2-3. Net improvement even without the rule. Plan should specify that all capture/validate calls use literal arguments (no `$()`).

**Rationale:** User: "should we be making the stats capture more robust instead?" — yes. Moving validation into the script (exit codes) is both more robust (fails loudly at point of failure) and prompt-free (no VAR=$() needed). Cross-batch validation ("did all N land?") dropped — no recovery path exists anyway.

### Decision 4: Fix P5 trivially

`CACHED_SUBAGENT_MODEL=$(echo $CLAUDE_CODE_SUBAGENT_MODEL)` → `CACHED_SUBAGENT_MODEL=$CLAUDE_CODE_SUBAGENT_MODEL`. No subshell needed. Two occurrences (work.md, review.md).

### Decision 5: Add QA regression check

A new grep pattern in `context-lean-grep.sh` (or a new QA script) flags any `$()` appearing in generated bash command examples within plugin command files. Prevents the patterns from growing back as contributors add new features. Excludes init blocks (accepted) via a suppress comment pattern.

### Decision 6: jak absorbs plugin-side items from msm

Bead msm originally included "Fix: restructure plugin commands to avoid `$()` in compound chains" and "bd metadata JSON triggers heuristic." These are plugin-side fixes — jak owns them. msm stays hook-side and setup-side (missing safe prefixes, Permissive profile rebuild, custom prefix support).

### Decision 7: Sentinel redesign — clear marker, not rm

`rm -f .workflows/.work-in-progress` in work.md (×2) prompts because `rm:*` is too dangerous as a static rule. This is a sentinel REDESIGN, not a simple rm→Write swap.

**Current pattern:** Sentinel created with `touch .workflows/.work-in-progress`, checked with `[[ -f .workflows/.work-in-progress ]]`, cleared with `rm -f`.

**Problem with naive Write:** Writing a "cleared" marker means the file still exists — the `[[ -f ]]` existence check still finds it. The entire sentinel pattern needs redesign:
- **Option A:** Write tool writes sentinel content on create (e.g., timestamp), clears by writing "cleared". Check changes from `[[ -f ]]` to content-based: `grep -qv "cleared" .workflows/.work-in-progress`.
- **Option B:** Use a different signal — e.g., sentinel contains a session ID, and "clearing" means writing a new session ID or empty string. Check: `[[ -s .workflows/.work-in-progress ]]` (non-empty = active).

Design detail deferred to planning. The key constraint: no `rm` for sentinel cleanup.

**Planning prerequisite (per Opus red team):** Full inventory of all sentinel touchpoints — work.md (×2 create, ×2 clear), plugin-qa-check.sh (read + numeric age check at lines 34-47), recovery logic. The hook's age check expects numeric content (`grep -qE '^[0-9]+$'`), so the clear-marker approach must be compatible. 6+ locations need coordinated changes. Edge cases to address: stale/corrupt markers, crash recovery, concurrent runs.

`rm -rf .workflows/plan-research/<stem>/` in plan.md is a separate problem (directory cleanup, not sentinel). Accept the prompt — one-off per plan run.

**Rationale:** User: "adding rm is a terrible idea, should switch the sentinel to write a clear marker."

### Decision 8: chmod one-time prompt accepted

`chmod +x .claude/hooks/auto-approve.sh` in setup.md prompts, but setup is a one-time operation. Adding `chmod:*` as a permanent static rule for a one-time use is not worthwhile.

### Decision 9: ccusage:* added to recommended static rules

`ccusage daily --json ... --since $(date +%Y%m%d)` in compact-prep contains `$()` causing hook fallthrough. `ccusage:*` static rule suppresses the heuristic. Safe — ccusage is read-only. Added to settings.local.json.

---

## Patterns Catalogue

From repo research — all 7 active command files contain `$()`. Compound.md is the only clean file.

| ID | Pattern | Commands | Fix | Mid-workflow? |
|----|---------|----------|-----|---------------|
| P1 | `PLUGIN_ROOT=$(find ...)` | 6/8 | Accept (init block) | No |
| P2 | `STATS_FILE=".workflows/stats/$(date ...)"` | 6/8 | Accept (init block) | No |
| P3 | `RUN_ID=$(uuidgen \| cut -c1-8)` | 5/8 | Accept (init block) | No |
| P4 | `ENTRY_COUNT=$(grep -c ...)` | 5/8 (×2-3 each) | Replace with exit code check on capture-stats.sh | Yes — fix |
| P5 | `CACHED_MODEL=$(echo $VAR)` | 2/8 | `$VAR` directly | Init block hygiene — no prompt saved |
| P6 | `cd $(git worktree list ...)` | work.md | Accept (low frequency) | No |
| P7 | `git commit -m "$(cat <<EOF...)"` | work.md | Static rule `git:*` covers it (backup: Write tool → `git commit -F`) | No — already solved |
| P7b | `gh pr create --body "$(cat <<EOF...)"` | work.md | Static rule `gh:*` covers it (backup: Write tool → `--body-file`) | No — already solved |
| P8 | `sentinel_age=$(( $(date +%s) - ... ))` | work.md | Accept (low frequency) | No |
| P9 | `cat >> "$SNAPSHOT_FILE" <<EOF` | compact-prep.md | Accept (one-off) | No |
| P10 | `for d in ...; do` loops | setup.md | Accept (one-off setup) | No |
| P11a | `rm -f .workflows/.work-in-progress` | work.md (×2) | Sentinel redesign — clear marker, not rm (see Decision 7) | Yes — fix |
| P11b | `rm -rf .workflows/plan-research/<stem>/` | plan.md | Accept prompt (directory cleanup, one-off per plan) | No |
| P12 | `ccusage daily ... --since $(date ...)` | compact-prep.md | `ccusage:*` static rule (done) | Yes — fixed |
| P13 | `chmod +x .claude/hooks/auto-approve.sh` | setup.md | Accept (one-time setup) | No |

**bd metadata** (`bd create --metadata '{"impact":...}'`): `Bash(bd:*)` static rule suppresses the `{"` heuristic — empirically confirmed. No plugin change needed.

---

## Critical Empirical Finding

**Static rules suppress heuristics.** Tested: `bd create --metadata '{"impact":"none"}'` — the `{"` heuristic did NOT prompt because `Bash(bd:*)` matched first. Prior session memory stated "no static rule can suppress heuristics" — this was wrong for at least the `{"` case.

**Verified with two data points:** (1) `Bash(bd:*)` suppresses `{"` heuristic — `bd create --metadata '{"impact":"none"}'` auto-approved. (2) `Bash(git:*)` suppresses `$()` heuristic — `git commit --allow-empty -m "$(echo 'test')"` auto-approved. Two different heuristic types, both suppressed by matching static rules. The generalization that static rules suppress all heuristics is well-supported.

**Inferred evaluation order:**
1. Static allow rules (settings.json + settings.local.json) — if matched, command approved immediately, no further checks
2. Heuristic check — fires only if no static rule matched
3. PreToolUse hook — fires after heuristics (from prior session evidence)
4. Interactive prompt

**Consequence for jak scope:** Commands where the first token is covered by a static rule (`git:*`, `gh:*`, `bd:*`, `cat:*`, etc.) are already auto-approved regardless of `$()` or `{"` content. The ONLY commands that still prompt are those where the first token is NOT in any static rule — primarily **VAR=$(...)** patterns (first token is a variable assignment like `ENTRY_COUNT=`, `PLUGIN_ROOT=`, `STATS_FILE=`).

**Revised pattern status:**

| Pattern | First Token | Static Rule | Still prompts? |
|---------|------------|-------------|----------------|
| `git commit -m "$(cat <<EOF...)"` | `git` | `git:*` | No — already solved |
| `gh pr create --body "$(cat <<EOF...)"` | `gh` | `gh:*` | No — already solved |
| `cat >> "$SNAPSHOT_FILE" <<EOF` | `cat` | `cat:*` | No — already solved |
| `bd create --metadata '{"impact":...}'` | `bd` | `bd:*` | No — already solved |
| `ENTRY_COUNT=$(grep -c ...)` | `ENTRY_COUNT=` | none | **Yes** |
| `PLUGIN_ROOT=$(find ...)` | `PLUGIN_ROOT=` | none | **Yes** (init block — accepted) |
| `STATS_FILE="$(date ...)"` | `STATS_FILE=` | none | **Yes** (init block — accepted) |
| `RUN_ID=$(uuidgen ...)` | `RUN_ID=` | none | **Yes** (init block — accepted) |

**The real problem is narrower than thought:** Only VAR=$(...) first-token patterns prompt unconditionally (no static rule can match variable assignment first tokens). These are: init blocks (accepted), ENTRY_COUNT (mid-workflow — replace with exit code check), and sentinel rm (mid-workflow — redesign sentinel pattern).

**BUT:** This only holds for users who have the right static rules. New users getting the Permissive profile from `/compound:setup` may not have `git:*`, `gh:*`, `bd:*`, `cat:*`. The Permissive profile rebuild (msm) becomes MORE important than jak's plugin rewrites for fixing the new-user experience.

---

## Resolved Questions

**Q1: Does `Bash(bd:*)` static rule suppress the `{"` heuristic?**
A: Yes — empirically confirmed. `bd create --metadata '{"impact":"none"}'` ran without prompting. Static rules suppress heuristics entirely. Prior memory ("no static rule can suppress heuristics") was wrong.

**Q2: Does `gh pr create --body-file` exist?**
A: Yes — confirmed via `gh pr create --help`. Flag is `-F` / `--body-file`.

**Q: Should jak absorb plugin-side items from msm?**
A: Yes. msm = hook/settings side. jak = plugin command rewrites. Cleaner scoping.

**Q: Split-call pattern for init blocks (date, uuidgen, plugin root)?**
A: No. Reliability risk (model error surface, silent wrong paths) outweighs prompt reduction. Accept one init-block prompt per workflow phase.

**Q: MCP server for utility operations?**
A: No. jak-scoped — overkill. Build cost not justified for this scope.

**Q: Model-substituted date (model knows today's date)?**
A: No. Model is unreliable at knowing the current date.

**Q: Remove ENTRY_COUNT validation?**
A: Replace with validate-stats.sh (new script). capture-stats.sh stays fire-and-forget (exits 0 always — invariant preserved). validate-stats.sh does cross-batch count check inside the script (hidden from heuristics). Called once per phase, not after every dispatch. Prompt-free with bash:* static rule.

---

## Deferred Questions

1. **Scope of prose rewrite.** Patterns appear in both code blocks AND prose templates. Full prose audit needed for all 7 files. Deferred to planning — plan must include explicit prose audit step.

2. **QA check design.** Should the regression check live in `context-lean-grep.sh` (existing) or a new script? What's the suppress comment convention for accepted init blocks? Deferred to planning.

## Resolved Questions (from settings audit)

**Q: Permissive profile vs plugin rewrites?**
A: Static rules are the correct fix for P7/P9/P12 — not plugin rewrites. msm's Permissive profile rebuild should include `git:*`, `gh:*`, `cat:*`, `bd:*`, `ccusage:*`. Plugin-side rewrites only needed where no static rule can help (VAR= first-token patterns).

**Q: Add `rm:*` to static rules for sentinel cleanup?**
A: No — "adding rm is a terrible idea." Plugin should switch sentinel cleanup to Write tool (clear marker). User's exact words.

**Q: Add `chmod:*` for setup?**
A: No — one-time operation, permanent broad rule not justified. Accept the single prompt.

**Q: Add `ccusage:*`?**
A: Yes — safe (read-only), fixes compact-prep mid-workflow prompt. Added.

---

## Red Team Resolution

**Providers:** OpenAI (completed), Opus (completed), Gemini (503 — unavailable)

### OpenAI Findings

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| 1 | CRITICAL | Single data point generalization → "already solved" | **Fixed.** Verified with second test: `git:*` suppresses `$()` heuristic. Two heuristic types confirmed. |
| 2 | SERIOUS | Problem selection mis-prioritized (profile > plugin rewrites) | **Disagree.** jak explicitly defers to msm for profile work and calls msm "MORE important." jak cleans up what static rules can't cover — complementary, not competing. |
| 3 | SERIOUS | Security risk of broad allow-rules under-addressed | **Noted, deferred to msm.** Threat model belongs in Permissive profile design (msm scope). jak documents the dependency, not the risk acceptance framework. |
| 4 | SERIOUS | Cross-batch validation dropped without justification | **Fixed.** Replaced with validate-stats.sh (separate script, cross-batch check, prompt-free). |
| 5 | SERIOUS | Sentinel redesign underspecified (crash recovery, concurrency) | **Acknowledged as planning requirement.** Brainstorm notes edge cases and blast radius; state model deferred to plan. |
| 6 | MINOR | Acceptance criteria subjective ("one prompt acceptable") | **Acknowledged.** Measurable targets come at plan time. |

### Opus Findings

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| 1 | CRITICAL | "Already solved" classifications depend on undocumented Claude Code evaluation order; fragile to updates | **Valid — planning constraint.** Backup (Write tool + git commit -F) must be pre-designed at plan time. Behavior verified with 2 tests but undocumented. |
| 2 | SERIOUS | Decision 3 exit codes contradict capture-stats.sh "exits 0 always" invariant | **Fixed.** New design: capture-stats.sh stays fire-and-forget. New validate-stats.sh handles cross-batch checks. Invariant preserved. |
| 3 | SERIOUS | Sentinel redesign blast radius (6+ touchpoints) not enumerated | **Fixed.** Added planning prerequisite with touchpoint inventory and edge cases to Decision 7. |
| 4 | SERIOUS | Hook $() pre-check + bash:* interaction undocumented | **Addressed.** Plan must specify literal arguments for all capture/validate calls. Covered by bash:* static rule. |
| 5 | SERIOUS | jak/msm scope boundary unclear for sentinel (touches hook code) | **Fixed.** jak expanded to own sentinel changes including plugin-qa-check.sh. Scope statement updated. |
| 6 | MINOR | No before/after prompt count | **Acknowledged.** Plan should include concrete prompt counts for representative workflow. |
| 7 | MINOR | QA regression false positives in documentation | **Acknowledged.** Suppress mechanism design deferred to planning. |
| 8 | MINOR | Pattern table conflates resolution mechanisms with different reliability | **Acknowledged.** Table relies on static rules (undocumented order) — fragility noted in CRITICAL #1. |
| 9 | MINOR | "Init blocks will always prompt" overstated | **Fixed.** The "multi-line heuristic" doesn't exist as a separate trigger. Multi-line blocks without `$()` auto-approve. `$()` is the sole heuristic trigger for init blocks. Brainstorm updated — init blocks prompt because of `$()`, not multi-line. Split-call rejection rationale unchanged (reliability), but the framing was corrected. |

