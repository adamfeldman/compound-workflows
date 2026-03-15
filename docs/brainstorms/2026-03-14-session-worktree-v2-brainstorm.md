---
title: "Session Worktree Isolation v2 — SessionStart + bd worktree"
type: fix
date: 2026-03-15
origin_bead: wxco
related_beads: [s7qj, wr96, fyg9, ytlk]
supersedes: docs/brainstorms/2026-03-14-session-worktree-hook-workaround-brainstorm.md
---

# Session Worktree Isolation v2

**Bead:** wxco
**Problem:** v3.2.0 shipped session worktree isolation using `EnterWorktree` (Claude Code native tool) triggered by a SessionStart hook. Two issues discovered empirically:
1. SessionStart hooks using stderr + exit 2 don't deliver output to the model (output discarded for new sessions)
2. EnterWorktree auto-cleans worktrees on session exit — committed-but-unmerged work is lost

## Why v2

The v1 brainstorm explored a complex PreToolUse bridge (sentinel, dual-hook detection, subagent skip, `/do:start` skill) to work around SessionStart delivery issues. Empirical testing during that brainstorm revealed:

1. **SessionStart hooks DO work with stdout + exit 0** — the delivery problem was exit code, not the hook type
2. **Strong AGENTS.md wording + hook reinforcement makes the model auto-comply** — no user confirmation needed (better than A2's one-confirm)
3. **BUT: EnterWorktree auto-cleans worktrees on session exit** — directory AND branch deleted, losing committed-but-unmerged work
4. **`bd worktree create` already exists** — creates persistent worktrees in `.worktrees/`, handles beads DB redirect, no auto-cleanup

These findings eliminate the entire PreToolUse architecture. The fix is much simpler.

## Empirical Evidence (2026-03-14/15)

| Test | Result |
|------|--------|
| SessionStart stderr + exit 2 | Hook runs but output discarded for new sessions ✗ |
| SessionStart stdout + exit 0 | Output delivered to model as system-reminder ✓ |
| Multiple SessionStart hooks | All fire (global bd prime + project hooks) ✓ |
| Weak hook wording ("Call EnterWorktree") | Model ignores, just says "hi" ✗ |
| Strong hook wording ("Before doing anything else...") + strong AGENTS.md | Model auto-creates worktree without user confirmation ✓ |
| EnterWorktree persistence | Worktree + branch auto-cleaned on session exit ✗ |
| EnterWorktree on resume | Worktree gone, CWD back to main ✗ |
| PreToolUse exit 2 blocking | Does NOT block when auto-approve.sh returns "allow" first ✗ |
| PreToolUse additionalContext | Field works, model sees it ✓ (but not needed) |
| Multiple PreToolUse hooks | Both fire independently, no short-circuit ✓ |
| bd worktree create via model | Model runs `bd worktree create` + `cd` as instructed ✓ |
| bd worktree persistence after /exit | Worktree + branch persist after clean session exit ✓ |
| Hook detects existing worktree | Model cd's into existing worktree on new session ✓ |
| session-merge.sh with session-* branch | Works, but `git status --porcelain` false-positives on untracked files (bug) |

## What We're Building

### 1. SessionStart hook (stdout + exit 0)

Modify `session-worktree.sh` to output via stdout + exit 0 instead of stderr + exit 2.

**Two output modes based on state:**

**No existing session worktree (new session):**
```
Session worktree isolation is enabled. Before doing anything else — before reading files, running commands, or responding to the user — create a session worktree: run bd worktree create .worktrees/session-<name> (pick a short descriptive name) then cd into it. If the user says 'stay on main' or 'skip worktree', skip it.
```

**Existing session worktree found (resume / new session after crash):**
```
Session worktree exists at .worktrees/session-<name> (branch: <branch>). Before doing anything else — before reading files, running commands, or responding to the user — run cd .worktrees/session-<name> to resume working in it.
```

The hook detects existing worktrees via `ls -d .worktrees/session-* 2>/dev/null`. [Tested 2026-03-15: model complied with both create and cd instructions]

**bd not available:** If `command -v bd` fails, output a warning: "Session worktree isolation requires bd (beads). Install beads or set session_worktree: false to disable this warning." Exit 0. Don't silently skip — "warn over silent skip" is a project convention. [User decision: "why not warn for 1"]

Everything else in the hook stays the same: config read, orphan detection, GC of merged worktrees, dirty-main warning, mid-merge detection.

**Exit code:** 0 (not 2). SessionStart with exit 2 = output discarded. Exit 0 = output delivered as system-reminder.

### 2. AGENTS.md directive (unconditional)

```markdown
## Session Worktree Isolation

**At session start, before doing anything else, create a session worktree.**
Run `bd worktree create .worktrees/session-<name>` and `cd` into it.
Do not read files, run commands, or respond to the user first.

- Name the worktree after the task if known: `session-s7qj` or `session-fix-typo`
- User can say "stay on main" / "skip worktree" to opt out
- If you're already in a worktree (post-compact resume), skip — you're already isolated
- At session end, `/do:compact-prep` merges back to the default branch
- Any git operations before creating the worktree happen on the default branch
- Before committing, if session_worktree is enabled and you're NOT in a worktree,
  warn the user: "You're committing to main without worktree isolation. Continue?"
```

Key changes from v1:
- Unconditional ("at session start, create a worktree") not conditional ("when the hook instructs you"). The model treats system-reminders as background context, not directives — the AGENTS.md instruction must stand on its own.
- Pre-commit safety check: if session_worktree is enabled but model is NOT in a worktree, warn before committing. Catches the case where the hook instruction was silently ignored. [User: "when the user asks to commit, check if they're in a worktree first"]

### 3. `bd worktree` instead of EnterWorktree

Use `bd worktree create .worktrees/session-<name>` + `cd` instead of `EnterWorktree`.

**Why:**
- Worktrees persist until explicitly removed — no auto-cleanup on session exit
- Beads DB redirect handled automatically
- `.worktrees/` already in `.gitignore`
- `bd` commands are in auto-approve static rules — no permission prompts
- Same tooling as `/do:work` worktrees — one pattern, not two

**Naming convention:** `session-` prefix distinguishes session worktrees from `/do:work` worktrees. `/do:work` Phase 1.2 checks the worktree name prefix to decide whether to skip nested creation.

**No separate `.claude/worktrees/` namespace.** That was EnterWorktree's location. With bd worktree, everything lives in `.worktrees/`. Simpler.

### 4. Compact-prep merge (already built, minor fixes needed)

`session-merge.sh` (v3.2.0) handles the merge. Compact-prep Step 4.5 calls it. The merge flow works — just needs path updates and a bug fix.

**Bug fix:** `session-merge.sh` line 48 uses `git status --porcelain` which catches untracked files, causing false exit 4 (dirty main) when untracked files are present. Fix: `git status --porcelain --untracked-files=no`. Untracked files don't affect merge safety. [Discovered 2026-03-15: merge test failed with exit 4 due to untracked brainstorm docs]

Compact-prep changes:
- Exit worktree: `cd <main-repo>` via Bash tool (CWD persists) instead of ExitWorktree
- Cleanup: `bd worktree remove .worktrees/session-<name>` instead of `git worktree remove .claude/worktrees/<name>`

### 5. Observability (no sentinel files)

**No sentinel files needed.** Worktree functionality is observable through existing mechanisms:

- **Successful worktree use:** merge commits (`--no-ff "Merge session worktree"`) + compact-prep summary line (`Worktree: merged`)
- **Silent failure detection:** compact-prep checks if `session_worktree: true` but session is NOT in a worktree → adds warning to summary: `Worktree: not in worktree (WARNING — session_worktree enabled but no worktree entered)`. This gets committed in the session's commit message.
- **Session frequency:** already tracked by JSONL session logs and ccusage
- **Crash cases:** worktree persists, SessionStart hook warns about orphans

User reasoning: "do we get session frequency from other data sources?" — yes. "do we need analytics/logging on if worktree functionality is working properly?" — compact-prep summary is sufficient, no sentinel infrastructure needed. [User decision: skip sentinel files]

### 6. Crash recovery

Worktrees created via `bd worktree` persist through crashes, context exhaustion, and clean exits without compact-prep. The SessionStart hook's orphan detection finds them. `/compound-workflows:recover` and `/do:merge` handle recovery.

This is actually **better** than EnterWorktree — crashed sessions leave recoverable worktrees instead of auto-cleaned nothing.

## Key Decisions

1. **stdout + exit 0 for SessionStart** — empirically verified. stderr + exit 2 = output discarded. stdout + exit 0 = delivered as system-reminder. [Tested 2026-03-14]

2. **Strong unconditional AGENTS.md wording** — "before doing anything else, create a session worktree." Combined with hook reinforcement, the model auto-complies without user confirmation. [Tested 2026-03-14/15: model called bd worktree create before responding to "hi"]

3. **bd worktree over EnterWorktree** — EnterWorktree auto-cleans on exit, losing work. bd worktree persists. User: "why not use the bd worktree command?" [Tested: EnterWorktree worktree + branch gone after /exit; bd worktree persists]

4. **`.worktrees/` not `.claude/worktrees/`** — no separate namespace. User: "why do we care about using .claude/worktrees vs .worktrees?" Answer: we don't. EnterWorktree's location is irrelevant now.

5. **`session-` naming prefix** — distinguishes session worktrees from work worktrees in the same directory. `/do:work` checks prefix to skip nested creation.

6. **No PreToolUse workaround** — the v1 brainstorm's entire PreToolUse architecture (sentinel, dual-hook detection, subagent skip, `/do:start`) is unnecessary. SessionStart works with the right output mechanism.

7. **No `/do:start` skill** — the model creates the worktree directly via bd commands. No intermediate skill needed. wr96 (adaptive ceremony router) is a separate initiative that doesn't depend on this.

8. **CLI wrapper rejected** — Gemini proposed `alias claude='bash setup-worktree.sh && command claude'`. Simpler but: not portable via plugin, can't use EnterWorktree (native tool), doesn't integrate with compact-prep/merge/recover flow, breaks `claude --resume`.

9. **bd required, warn if missing** — session worktrees require bd. If bd not available, hook warns (not silent skip). No `git worktree add` fallback — keeps design simple, bd is already a soft dependency. User: "why not warn for 1" — project convention is "warn over silent skip."

10. **No sentinel files** — observability via compact-prep summary warning when session_worktree enabled but not in worktree. Session frequency from JSONL/ccusage. No additional infrastructure. User: "do we get session frequency from other data sources?" — yes.

11. **Pre-commit safety check in AGENTS.md** — if session_worktree enabled and not in worktree, warn before committing. Catches silently-ignored hook instruction. User: "when the user asks to commit, check if they're in a worktree first?"

12. **Hook detects existing worktrees for resume** — on session start, if `.worktrees/session-*` exists, hook says "cd into it" not "create a new one." CWD resets to main on exit/resume, so the model needs explicit instruction to re-enter. [Tested 2026-03-15: model complied]

13. **Process lesson captured** — bead fyg9 created for "verify upstream feature availability during brainstorm/plan." Memory feedback saved.

## What Changes from v3.2.0

| Component | v3.2.0 (shipped) | v2 (this fix) |
|-----------|------------------|---------------|
| Hook output | stderr + exit 2 | stdout + exit 0 |
| Hook resume detection | Check if CWD in `.claude/worktrees/` | Check if `.worktrees/session-*` exists, instruct cd |
| Hook bd check | Not needed (used EnterWorktree) | `command -v bd`, warn if missing |
| Worktree creation | EnterWorktree (native tool) | `bd worktree create .worktrees/session-<name>` |
| Worktree location | `.claude/worktrees/` | `.worktrees/` |
| AGENTS.md wording | Conditional ("when hook instructs") | Unconditional ("before doing anything else") + pre-commit check |
| Compact-prep exit | ExitWorktree(action: "keep") | `cd <main-repo>` (CWD persists between Bash calls) |
| Compact-prep cleanup | `git worktree remove .claude/worktrees/<name>` | `bd worktree remove .worktrees/session-<name>` |
| Compact-prep summary | Worktree status line | Same + WARNING if session_worktree enabled but not in worktree |
| session-merge.sh | `git status --porcelain` (catches untracked) | `git status --porcelain --untracked-files=no` (fix false exit 4) |
| /do:work detection | Check `.claude/worktrees/` in path | Check `session-` prefix in worktree name |
| /do:setup gitignore | Add `.claude/worktrees/` | No change (`.worktrees/` already handled) |
| /do:setup hook install | Copy template + register SessionStart | Same, but template uses stdout + exit 0 + existing-worktree detection |
| Recover/orphan detection | Check `.claude/worktrees/` | Check `.worktrees/session-*` |
| EnterWorktree/ExitWorktree | Required (native tools) | Not used |

## Resolved Questions

1. **bd availability** — require bd. Warn if missing, don't silently skip. No `git worktree add` fallback.

2. **Analytics/observability** — compact-prep summary warning is sufficient. No sentinel files. Session frequency from existing JSONL/ccusage.

3. **Resume handling** — hook detects existing `.worktrees/session-*` and instructs model to cd into it. Tested and verified.

4. **session-merge.sh compatibility** — works with `session-*` branches (takes branch name, path-agnostic). Bug found: `git status --porcelain` false-positives on untracked files. Fix: add `--untracked-files=no`.

5. **Pre-commit safety net** — AGENTS.md instructs model to check worktree status before committing. Warns if session_worktree enabled but not in worktree.

## Open Questions

1. **Model compliance consistency** — tested twice (create + resume). Need more sessions to confirm reliability. May vary with model version or context size. Not a blocker for implementation — monitor empirically.

## What v1 Brainstorm Got Wrong

The v1 brainstorm spent significant effort on a PreToolUse workaround based on three incorrect assumptions:

1. **"SessionStart hooks are broken"** — partially true. stderr + exit 2 is broken. stdout + exit 0 works. The brainstorm didn't test output mechanisms independently.

2. **"EnterWorktree is the right tool"** — it auto-cleans on exit. This was discovered during v1 testing but wasn't known during the original s7qj plan. `bd worktree` was available the whole time and doesn't have this problem.

3. **"The model won't comply without enforcement"** — strong AGENTS.md wording + hook reinforcement is sufficient. The model auto-complied without user confirmation. The PreToolUse exit 2 blocking mechanism wasn't needed (and didn't work anyway — auto-approve.sh overrides it).

**Root cause of the roundabout:** Each assumption was treated as ground truth and designed around, rather than tested first. The v1 brainstorm spent 2 red team rounds and ~15 design decisions building on unverified foundations. A 2-minute test at the start (change exit code, check if output arrives) would have short-circuited the entire exploration.

**Process lesson (reinforces beads fyg9, ytlk):** Test the simplest version of the mechanism first, before designing workarounds for its failure. This extends beyond "check GitHub issues" (fyg9 original lesson) to: verify each assumption empirically before building on it. Related to ytlk (inherited-assumption blind spots) — assumptions propagated undetected across brainstorm phases.

## Sources

- **v1 brainstorm:** `docs/brainstorms/2026-03-14-session-worktree-hook-workaround-brainstorm.md` — superseded but retained for traceability
- **v1 research:** `.workflows/brainstorm-research/session-worktree-hook-workaround/` — repo research, context research, 2 rounds of red team (6 provider reviews)
- **Empirical tests (2026-03-14/15):** All tests listed in evidence table above
- **Session logs analyzed:** `9fd9cb46` (PreToolUse test), `a8c9e161` (EnterWorktree auto-cleanup + bd worktree create compliance)
- **Upstream issues:** 6 Claude Code GitHub issues (see v1 brainstorm for full table — still relevant for SessionStart stderr+exit2 behavior)
