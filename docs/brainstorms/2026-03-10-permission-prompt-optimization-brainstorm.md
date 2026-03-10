---
date: 2026-03-10
topic: permission-prompt-optimization
status: active
absorbs: 3k3
---

# Permission Prompt Optimization

## What We're Building

A layered permission system that reduces interactive permission prompts to near-zero for standard operations while preserving safety prompts for destructive or out-of-scope actions. Three components:

1. **Minimal committed baseline** (`.claude/settings.json`) — only the rules subagents need to function (Write/Edit `.workflows/**`). Verified empirically: subagents DO inherit `.claude/settings.json` from the project root.

2. **PreToolUse hook** (`.claude/settings.json`) — a programmable auto-approve script that handles scoped approvals with path validation, logging, and dynamic logic. Primary mechanism for permission optimization.

3. **Immediate fix (developer-only, not shipped)** — consolidate the developer's own settings.local.json (56 rules → clean patterns). Personal workspace cleanup, separate from the plugin feature.

4. **Setup command enhancement** — `/compound:setup` adds the hook and optional static rules to `.claude/settings.local.json` with three profile options (Surgical/Conservative/Aggressive) showing estimated impact. Explains what will be done before writing.

## Why This Approach

### The Problem

Analysis of session JSONL logs across all sessions in this project found:
- **2,637 total Bash tool calls** across all sessions
- **~500 (~19%) would trigger permission prompts** — not covered by allow rules
- **56 existing Bash allow rules** in settings.local.json, most auto-accumulated one-off approvals (exact command strings, version-specific paths)
- **Subagents don't inherit parent session permission grants** — background Agent dispatches (research, red team) get blocked on Write despite `Write(//.workflows/**)` in settings.local.json. Causes silent data loss.

Top prompt offenders (unmatched Bash commands):

| Count | Command | Risk | Note |
|-------|---------|------|------|
| 73 | sleep | None | Polling/waiting |
| 69 | cd | None | Directory navigation |
| 54 | cat | None | File reading (should be Read tool) |
| 40 | # | None | Comments in multi-line scripts |
| 37 | which | None | CLI detection |
| 30 | gh (uncovered) | Low | Missing gh pr, gh run patterns |
| 26 | rm | Medium | Needs project-directory scoping |
| 17 | cp | Low | File copying |
| 16 | head | None | File reading |
| 12 | echo | None | Output |
| 10 | claude | None | CLI info commands |
| 7 | ccusage | None | Read-only cost analysis |

### Data Source

Permission prompts are NOT logged as structured events in session JSONL. Two signals exist:
- **Denials** appear as `tool_result` with content `"The user doesn't want to proceed with this tool use"` — 40 found in one session (single-session sample; denial rates may vary across sessions and users — profile impact estimates should be treated as approximate, not precise measurements)
- **Approvals are invisible** — they execute normally with no distinguishing marker
- The `Notification` hook with `permission_prompt` matcher fires on every prompt (could be modified to log)

### Why Hooks Over Static Rules

Red team (all 3 providers) identified that static wildcard rules (`Bash(bash:*)`, `Bash(rm:*)`, `Bash(cat:*)`) create sandbox escapes — a prompt-injected subagent could run arbitrary code. Web research confirmed hooks as the right approach:

- **Officially recommended** — Claude Code v2.0+ docs recommend PreToolUse hooks as the primary auto-approval mechanism over static rules or `--dangerously-skip-permissions`
- **Deny rules are broken** — multiple GitHub issues (#27040, #6699, #8961) confirm deny rules in settings.json are non-functional. PreToolUse hooks are the ONLY reliable way to block dangerous operations
- **Path scoping** — a hook script can validate that `rm` targets are within the project directory
- **Input modification** — since v2.0.10, hooks can rewrite tool inputs before execution (sandboxing, path correction)
- **No accretion** — logic lives in a reviewable script, not accumulated rules
- **Auditable** — the hook can log what it approved and why
- **Least privilege for subagents** — committed baseline stays minimal; the hook adds intelligence
- **Aligns with user preference** — "deterministic over probabilistic", "why aren't we using hooks??"

Hook auto-approve output format: `{"hookSpecificOutput": {"permissionDecision": "allow"}}`

### Verified Assumptions

- **Subagent settings inheritance** — empirically verified 2026-03-10. A distinctive allow rule in `.claude/settings.json` was inherited by a spawned subagent. Subagents load project-level settings from the working directory.

## Key Decisions

1. **Hooks as primary mechanism** — PreToolUse hook script handles scoped auto-approvals. Static rules are the minimal committed baseline only. Rationale: red team flagged that static wildcards (`Bash(bash:*)`, `Bash(python3:*)`) are sandbox escapes; hooks can do path-scoped approval.

2. **Minimal committed baseline** — only `Write(//.workflows/**)` and `Edit(//.workflows/**)` in `.claude/settings.json`. No Bash interpreters, no file-reading commands. Keeps the supply chain attack surface small. Rationale: anyone who clones/forks this repo gets committed rules; they should be minimal.

3. **Project-only scope** — rules go in project `.claude/settings.local.json` and `.claude/settings.json`. NOT in global `~/.claude/settings.json`. Rationale: "i want the setup command to help users set reasonable rules" — each project configures its own permissions.

4. **Three profile options with impact estimates** — Surgical (fills gaps), Conservative (safe commands), Aggressive (includes interpreters for risk-accepting users). Impact shown as estimated ranges, not exact percentages. User rationale: liked the 3-option menu with impact stats.

5. **Setup command writes directly** — after explaining what will be added. User rationale: reduces friction, users can remove rules they don't want.

6. **Interpreters opt-in only** — `Bash(bash:*)`, `Bash(python3:*)`, `Bash(cat:*)` NOT in default profiles. Available as opt-in for users who accept the risk. Rationale: red team (all 3 providers) flagged these as sandbox escapes enabling arbitrary code execution.

7. **Absorbs bead 3k3** — "Setup: ship .workflows permissions in settings.json + setup command" is the same problem. This brainstorm supersedes it.

8. **Setup is idempotent** — safe to re-run anytime. Merge, not replace. Report what changed.

## Design: Committed Baseline (`.claude/settings.json`)

Minimal rules subagents need. Kept small to limit supply chain risk:

```json
{
  "permissions": {
    "allow": [
      "Write(//.workflows/**)",
      "Edit(//.workflows/**)"
    ]
  }
}
```

Plus a PreToolUse hook for programmable auto-approval (see Hook Design below).

## Design: PreToolUse Hook

A bash script at `.claude/hooks/auto-approve.sh` that receives tool call JSON on stdin and returns `{"hookSpecificOutput": {"permissionDecision": "allow"}}` for known-safe operations:

**Scope of auto-approval (hook logic):**
- `Bash(mkdir -p .workflows/*)` — directory creation within .workflows
- `Bash(ls ...)` — directory listing (always safe)
- `Bash(which ...)` — CLI detection (always safe)
- `Bash(sleep ...)` — polling/waiting (always safe)
- `Bash(echo ...)` — output (always safe, but not `echo > file`)
- `Bash(wc ...)` — counting (always safe)
- `Bash(cd ...)` — directory navigation (always safe)
- `Bash(bd ...)` — beads workflow (project tool)
- `Bash(git ...)` — git operations (scoped: no `push --force`, no `reset --hard`)
- `Bash(rm ...)` — **only if path is within project directory** (path validation)
- `Bash(bash scripts/...)` — **only project scripts** (path validation)

Everything else → no decision (falls through to normal prompting).

**Safety guardrails in hook:**
- Never approve `rm -rf /`, `rm -rf ~`, or paths outside project root
- Never approve `git push --force` or `git reset --hard`
- Log all approvals to `.workflows/hook-audit.log` for traceability
- Exit code 0 with no output = no decision (falls through to prompt)

## Design: Setup Command Permission Step

### Three Profiles

The setup command presents three options with estimated impact:

#### Surgical (low impact)

Only adds the committed baseline + hook. No additional static rules. User still gets prompted for uncommon operations.

#### Conservative (moderate impact)

Committed baseline + hook + safe static rules:

```
Bash(gh:*)           # GitHub CLI
Bash(grep:*)         # content search
Bash(find:*)         # file search
Bash(claude:*)       # Claude CLI info
Bash(ccusage:*)      # cost analysis
```

#### Aggressive (high impact)

Everything in Conservative, plus interpreter access for risk-accepting users:

```
Bash(bash:*)         # WARNING: allows arbitrary script execution
Bash(python3:*)      # WARNING: allows arbitrary code execution
Bash(cat:*)          # WARNING: bypasses Read tool path restrictions
Bash(head:*)
Bash(tail:*)
Bash(sed:*)
Bash(cp:*)
Bash(rm:*)           # WARNING: unscoped — hook provides scoping but static rule is broader
Bash(timeout:*)
Bash(open:*)
Bash(for:*)
mcp__pal__clink
mcp__pal__chat
mcp__pal__listmodels
WebSearch
```

**Each WARNING rule is explained before the user chooses.** The setup command lists the risks, not just the convenience.

### Idempotent Re-Run

1. **Read existing rules** from both settings files
2. **Merge, not replace** — add missing rules, never remove user-added rules
3. **Skip already-present rules** — no duplicates
4. **Report what changed** — "Added N new rules, M already present"
5. **Profile upgrade** — if user previously chose Conservative and now picks Aggressive, add the delta rules only
6. **One-time migration** — on first run, offer to consolidate auto-accumulated one-off rules into clean patterns. This IS a replace operation, but only offered once with explicit confirmation.

## Red Team Resolution Summary

### CRITICAL

| # | Finding | Providers | Resolution |
|---|---------|-----------|------------|
| C1 | Subagent settings inheritance unverified | Opus | **Verified empirically** — subagents DO inherit .claude/settings.json |
| C2 | Interpreters (bash:*, python3:*, cat:*) = sandbox escape | Gemini, OpenAI | **Fixed** — removed from default profiles, opt-in only with warnings |
| C3 | PreToolUse hooks not explored | Opus | **Valid — adopted** — hooks are now the primary mechanism |

### SERIOUS

| # | Finding | Providers | Resolution |
|---|---------|-----------|------------|
| S1 | `Bash(rm:*)` unscoped | All 3 | **Fixed** — hook does path validation within project dir |
| S2 | Profile percentages unjustified | Opus, OpenAI | **Fixed** — softened to qualitative impact levels (low/moderate/high) |
| S3 | Committed settings.json = supply chain risk | Opus | **Fixed** — minimal baseline (Write/Edit .workflows/** only) |
| S4 | "Merge not replace" contradicts "immediate rewrite" | OpenAI | **Fixed** — clarified: one-time migration (replace with confirmation) vs ongoing merge |
| S5 | Permission accretion (rules only grow) | OpenAI | **Fixed** — hooks don't accumulate; logic in script |
| S6 | Conflates subagent data loss with interactive friction | Opus | **Fixed** — hooks for subagents, static rules for baseline |
| S7 | Subagent least privilege | Gemini | **Fixed** — committed baseline is minimal |

### MINOR

**Fixed (batch):** 3 MINOR fixes applied (sample caveat, safety criterion in objective, Component 3 labeled developer-only).

**Resolved by research:** 3 manual-review items resolved by web research:
- Upstream Claude Code: hooks ARE the official v2.0+ recommendation — we're aligned
- Deny rules as safety net: deny rules are broken (GitHub #27040, #6699, #8961) — hooks are the only reliable guardrail
- Settings file conflicts: hooks in settings.json are less conflict-prone than dozens of permission rules

**No action needed:** 3 items already resolved by CRITICAL/SERIOUS triage (cat removal, minimal baseline, hook-based mechanism).

## Resolved Questions

1. **Where do rules live?** → Minimal committed baseline in `.claude/settings.json` (Write/Edit .workflows/** only), user-specific static rules in `.claude/settings.local.json`, programmable auto-approve in PreToolUse hook. Rationale: subagents need committed rules; hooks provide the intelligence.

2. **How aggressive?** → Three profiles (Surgical/Conservative/Aggressive). Interpreters are Aggressive-only with explicit warnings. Rationale: red team flagged sandbox escape risk.

3. **Global vs project?** → Project-only. Rationale: "i want the setup command to help users set reasonable rules."

4. **Setup UX?** → Direct write after explanation, three profile options with impact estimates. Rationale: reduces friction + informed choice.

5. **Merge with 3k3?** → Yes. Same problem domain.

6. **Subagent inheritance?** → Verified empirically. Subagents load `.claude/settings.json` from project root.

7. **Re-run safety?** → Idempotent merge + one-time migration with confirmation. "Setup must always be safe to re-run."

8. **Static rules vs hooks?** → Hooks as primary mechanism. Static rules for minimal baseline + user-chosen profile additions. Rationale: hooks provide path scoping, auditability, no accretion.
