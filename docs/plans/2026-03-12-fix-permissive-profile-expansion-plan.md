---
title: "fix: expand permissive profile with missing safe rules"
type: fix
status: completed
date: 2026-03-12
---

# Fix: Expand Permissive Profile with Missing Safe Rules

## Context

Audit of a real user's `settings.local.json` against the permissive profile in `do:setup` revealed gaps that force users to accumulate ad-hoc rules. The permissive profile should reduce prompts to near-zero for trusted environments.

Already completed: removed `rm:*` from permissive (zvux, committed in 3.0.2).

## Step 0 Verification Results

Empirical testing in Claude Code 2.1.74 revealed:

| Test | Result | Meaning |
|------|--------|---------|
| `sed --version` | Auto-approved | Static rules work (sed:* not in hook) |
| `bd stats > /dev/null` | Auto-approved | `bd:*` DOES match `bd <subcommand>` (redirect bypasses hook, static rule approved) |
| `bd show $(echo u1fd)` | Prompted | $() is a hard heuristic (not suppressible by static rules) |
| `bd search $(echo ...)` | Prompted | Same — $() hard even with `bd search:*` in rules |
| `git log $(echo ...)` | Prompted | Same — $() hard even with `git:*` in rules |
| `cp --version` | Prompted | `cp` has a hard heuristic ("cp with flags requires manual approval") |

**Key findings:**
1. **`Bash(bd:*)` DOES match `bd <subcommand>`** — the original claim was wrong. The user's earlier prompts were caused by $() being hard, not by pattern mismatch.
2. **$() is a hard heuristic** — static rules cannot suppress it. This contradicts CLAUDE.md documentation which lists $() as soft. Filed for documentation update.
3. **`WebFetch(domain:*)` is valid syntax** — already in use in user's settings.local.json.
4. **13 bd subcommand rules DROPPED** — unnecessary since `bd:*` covers all subcommands.

## Rules to Add

### Permissive Profile (11 rules)

| Rule | Rationale |
|------|-----------|
| `Bash(git:*)` | Fundamental — used constantly. Bypasses hook's `is_dangerous_git()` — gets ⚠ warning. |
| `Bash(mkdir:*)` | Basic, safe — model generates bare `mkdir -p` |
| `Bash(md5:*)` | Used regularly for hash checks in plugin workflows |
| `Bash(ls:*)` | Basic, safe — avoids prompts on `ls` with flags |
| `Bash(bd:*)` | Beads is a core plugin tool — verified to match all subcommands |
| `Bash(if:*)` | Shell control flow — suppresses redirect/quote heuristics in conditionals |
| `Bash(for:*)` | Shell control flow — suppresses heuristics in loops |
| `Bash([[:*)` | Shell control flow — conditional checks |
| `Bash(xargs:*)` | Pipeline tool — safe, used in data processing |
| `Bash(tee:*)` | Pipeline tool — safe, used for logging output |
| `WebFetch(domain:*)` | Research agents and defuddle skill fetch URLs — in addition to existing `WebSearch`. Verified syntax. |

### Not Adding (personal preference, not universal)

| Rule | Why excluded |
|------|-------------|
| `Read(//Users/adamf/.claude/**)` | User-specific path |
| `mcp__pal__thinkdeep` | Not all users have PAL |
| `mcp__pal__analyze` | Not all users have PAL |

## Implementation

- [x] **Step 0:** Verify pattern matching behavior (see results above)
- [x] **Step 1:** Add 11 rules to permissive profile rule list in `skills/do-setup/SKILL.md` (line ~460)
- [x] **Step 2:** Update permissive summary block (line ~435 area):
  ```
  ⚠ bash:*    — allows arbitrary script execution (BYPASSES hook guardrails)
  ⚠ python3:* — allows arbitrary code execution (BYPASSES hook guardrails)
  ⚠ git:*     — allows all git operations including destructive (BYPASSES hook is_dangerous_git)
  ⚠ cat:*     — bypasses Read tool path restrictions
  Plus: gh, grep, find, claude, ccusage, head, tail, sed, cp, timeout, open,
        ls, mkdir, md5, bd, if, for, [[, xargs, tee, WebFetch
  ```
- [x] **Step 3:** Update CHANGELOG.md. Add new version section:
  ```
  - **Expand permissive profile** — Add 11 rules: git, ls, mkdir, md5, bd, shell constructs (if, for, [[, xargs, tee), WebFetch. Add safe git patterns and ls to standard add-on. Existing permissive users: re-run `/do:setup` to pick up new rules.
  - **Documentation: $() is a hard heuristic** — Step 0 verification discovered that static rules do NOT suppress the $() heuristic in Claude Code 2.1.74, contradicting prior documentation. This means `Bash(X:*)` rules only help for commands without $() — the Bash Generation Rules (avoiding $()) remain the primary mitigation.
  ```
- [x] **Step 4:** Update standard profile add-on (line ~718 area):
  - Add `ls` (basic, safe — same class as existing `which`, `echo`, `mkdir`)
  - Add specific safe git patterns: `Bash(git log:*)`, `Bash(git diff:*)`, `Bash(git status:*)`, `Bash(git branch:*)` (NOT broad `Bash(git:*)` — that would bypass hook's `is_dangerous_git()` check)
- [x] **Step 5:** Bump version to 3.0.5 in `plugin.json` and `marketplace.json` (PATCH). Current version is 3.0.4.
- [x] **Step 6:** Run QA — this touches a skill file

## Resolved Questions

- **Standard profile add-on gets `ls` and safe git subcommands.** Yes — `ls` is basic/safe. `git` is scoped to read-only operations (`git log`, `git diff`, `git status`, `git branch`) to avoid bypassing hook guardrails. Standard add-on becomes: `which`, `echo`, `mkdir`, `ls`, `git log`, `git diff`, `git status`, `git branch`.
- **13 bd subcommand rules dropped.** Step 0 proved `Bash(bd:*)` matches all subcommands. The user's original prompts were from $() being hard, not pattern mismatch. Bead ptxp (conditional bd rules) is still relevant for making the single `bd:*` rule conditional on beads detection.
- **$() is hard.** Static rules suppress redirects (`>`) but NOT command substitution (`$()`). The Bash Generation Rules remain the primary mitigation for $()-triggered prompts.

## Red Team Resolution

Red team challenge run 2026-03-12 with 3 providers (Gemini, OpenAI, Claude Opus).

### CRITICAL — Resolved

| Finding | Providers | Resolution |
|---------|-----------|------------|
| `bd:*` claim unverified + no behavioral validation | All 3 | **Valid — Step 0 completed.** Verification disproved the original claim: `bd:*` DOES match subcommands. 13 rules dropped. |
| Rules redundant with `Bash(bash:*)` | Opus | **Disagree:** `Bash(bash:*)` matches commands starting with `bash`. LLM generates bare commands (`git status`, `ls -la`) — separate rules needed. |
| `WebFetch(domain:*)` trust-surface expansion | OpenAI, Opus | **Disagree on trust concern:** permissive already has `bash:*`/`python3:*`. **Valid on syntax:** verified in user's settings. |

### SERIOUS — Resolved

| Finding | Providers | Resolution |
|---------|-----------|------------|
| `bd show:*` space-in-prefix untested | Opus | **Moot — 13 subcommand rules dropped.** `bd:*` covers all subcommands. |
| Shell constructs enable arbitrary execution | All 3 | **Disagree:** permissive already has `bash:*`/`python3:*`. Trust-the-model stance. |
| Count contradictions (18 vs 24, General 10 vs 11) | Opus, OpenAI | **Fixed.** Now 11 rules (was 24 before dropping bd subcommands). |
| Hardcoded bd subcommand list is brittle | Gemini, OpenAI | **Moot — 13 subcommand rules dropped.** |
| N=1 user audit | Opus | **Disagree:** plugin author is primary user; patterns are representative. |
| Missing version/release steps | OpenAI | **Valid — added Step 5.** |

### MINOR — Resolved

| Finding | Providers | Resolution |
|---------|-----------|------------|
| `git` in standard bypasses hook guardrails | Opus | **Valid — Step 4 uses safe patterns** (`git log:*`, `git diff:*`, `git status:*`, `git branch:*`). |
| No re-run guidance for existing users | Opus | **Valid — folded into Step 3 CHANGELOG.** |
| `bd:*` redundant alongside subcommand rules | Gemini, OpenAI | **Resolved — subcommand rules dropped.** `bd:*` is the only rule needed. |
| No cleanup strategy for glob bug fix | Gemini | **Moot — no glob bug exists.** `bd:*` works correctly. |

## Readiness Resolution

6 findings from semantic checks (0 CRITICAL, 3 SERIOUS, 3 MINOR). All auto-fixed. See `.workflows/plan-research/fix-permissive-profile-expansion/readiness/checks/semantic-checks.md`.

## Sources

- Red team files: `.workflows/plan-research/fix-permissive-profile-expansion/red-team--{gemini,openai,opus}.md`
- Readiness checks: `.workflows/plan-research/fix-permissive-profile-expansion/readiness/checks/`
- Step 0 verification: Claude Code 2.1.74, empirical testing 2026-03-12
