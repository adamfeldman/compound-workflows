---
title: "Session Worktree Isolation v2 — Fix Hook Delivery + Worktree Persistence"
type: fix
status: active
date: 2026-03-15
origin: docs/brainstorms/2026-03-14-session-worktree-v2-brainstorm.md
---

# Session Worktree Isolation v2

## Problem

v3.2.0 shipped session worktree isolation using `EnterWorktree` (Claude Code native tool) triggered by a SessionStart hook. Two bugs discovered empirically:

1. **SessionStart hooks using stderr + exit 2 don't deliver output to the model** — output is discarded for new sessions. stdout + exit 0 works. (see brainstorm: empirical evidence table, Decision 1)
2. **EnterWorktree auto-cleans worktrees on session exit** — directory AND branch deleted, losing committed-but-unmerged work. `bd worktree create` persists. (see brainstorm: Decision 3)

These two bugs mean the v3.2.0 feature is non-functional — the hook instruction never reaches the model, and even if it did, EnterWorktree would destroy work on exit.

## Solution

Replace the v3.2.0 approach with a simpler design validated through empirical testing (14 tests documented in brainstorm):

1. **Hook output**: stderr + exit 2 → stdout + exit 0
2. **Worktree tool**: EnterWorktree → `bd worktree create .worktrees/session-<name>` + `cd`
3. **AGENTS.md wording**: conditional ("when hook instructs") → unconditional ("before doing anything else, create a session worktree")
4. **Path namespace**: `.claude/worktrees/` → `.worktrees/session-*`
5. **Resume detection**: CWD-based → `ls -d .worktrees/session-*` + explicit "cd into it" instruction
6. **Exit mechanism**: ExitWorktree → `cd <main-repo>` (CWD persists between Bash calls)
7. **Bug fix**: `session-merge.sh` line 48 `git status --porcelain` → `git status --porcelain --untracked-files=no`

## Write Safety: Main vs Worktree

Session worktrees isolate git operations, but some writes must always target main. Analysis of write paths confirms no gap exists:

| Write type | Location | Why it's safe |
|-----------|----------|---------------|
| `.claude/hooks/`, `.claude/settings.json` | **Committed** — tracked, copied to worktree | Edits in worktree merge normally at session end |
| `.claude/settings.local.json`, `.claude/memory/` | **Gitignored** — repo root only | Worktrees don't get a copy |
| `.beads/` database | Dolt DB with `bd worktree` redirect | Shared across sessions by design |
| `compound-workflows.local.md` | Gitignored — only at repo root | Not in worktree |
| Memory files (compact-prep) | Written after exiting worktree (Step 4.5.2 cd to main) | Compact-prep exits first |
| Code changes, `.workflows/` artifacts | Worktree branch → merged at session end | Normal worktree merge flow |

**Key invariant:** Gitignored files exist only at the repo root and are inherently main-scoped. Committed files (including `.claude/hooks/` and `.claude/settings.json`) exist in worktrees and merge normally. All git-tracked writes merge to main via session-merge.sh during compact-prep.

## Scope

### In scope
- All files listed in the brainstorm's "What Changes from v3.2.0" table
- Version bump, CHANGELOG, QA

### Out of scope
- New features (no sentinel files, no `/do:start` skill — see brainstorm Decisions 6, 7, 10)
- `safe-commit.sh` — no changes needed (logic lives in skills that reference it)
- Portability to non-bd environments (bd required, warn if missing — brainstorm Decision 9)
- **Worktree dependency bootstrapping** — git worktrees don't copy gitignored files (`node_modules/`, `.venv/`, `.env`). In user code repos, tests/builds in the worktree will fail without dependency bootstrapping (symlinks, reinstall). This is a pre-existing limitation (affects v3.2.0 equally). Tracked as bead gu2z. [red-team--gemini, see .workflows/plan-research/fix-worktree-session-isolation-v2/red-team--gemini.md]

## Implementation Steps

### Step 1: Rewrite session-worktree.sh template
**Files:** `plugins/compound-workflows/templates/session-worktree.sh`
**Estimate:** 30 min

The core fix. Rewrite the SessionStart hook template:

- [ ] Change output mechanism from `printf '%s\n' "$OUTPUT" >&2` to `printf '%s\n' "$OUTPUT"` (stdout)
- [ ] Change all `exit 2` to `exit 0` for model-facing output paths. True error conditions (e.g., `set -e` failures) may retain non-zero exits.
- [ ] Update comment block (lines 6-8) to document new exit behavior: "stdout + exit 0 = output delivered as system-reminder"
- [ ] Bump version comment from `v1.0.0` to `v2.0.0`
- [ ] Add hook self-version check: near the top (after config read), compare the hook's own version comment against the template version shipped with the plugin. If stale (e.g., installed hook is v1.0.0 but template is v2.0.0), output warning: "Session worktree hook is outdated (v1.0.0, current: v2.0.0). Run /do:setup to update." Exit 0 after warning. Implementation: hook reads its own first line for version, reads the template version from a known path (plugin cache or a version file). (red team MINOR — adoption guard for stale hooks)
- [ ] Add bd availability check: if `command -v bd` fails, output warning ("Session worktree isolation requires bd (beads). Install beads or set session_worktree: false to disable this warning.") and exit 0. Place after config read (Step 1), before worktree detection. (see brainstorm: Decision 9 — "warn over silent skip")
- [ ] Replace Step 3 resume detection: remove `*/.claude/worktrees/*` CWD case match. Replace with: `EXISTING=$(ls -d .worktrees/session-* 2>/dev/null | head -1)`. If non-empty, extract branch name via `git -C $EXISTING branch --show-current` and output resume instruction with path and branch. (see brainstorm: Decision 12)
- [ ] Add PID-based active session detection: on worktree creation, write `$PPID` (Claude Code process PID) to `.worktrees/session-<name>/.session.pid`. On resume detection, read the PID file and check `kill -0 $PID 2>/dev/null`. If process alive → append to output: "Warning: another session may be actively using this worktree. Say 'skip worktree' to avoid conflicts." If process dead → safe to resume, remove stale PID file. (red team Finding 5 — concurrent session detection)
- [ ] Replace Step 7 new-session instruction: remove `EnterWorktree` reference. New text: "Session worktree isolation is enabled. Before doing anything else — before reading files, running commands, or responding to the user — create a session worktree: run bd worktree create .worktrees/session-\<name\> (pick a short descriptive name) then cd into it. If the user says 'stay on main' or 'skip worktree', skip it."
- [ ] Update all GC paths from `.claude/worktrees/` to `.worktrees/session-*` (Step 2 disabled-feature GC at lines 30-40, Step 4 GC at lines 63-72, Step 5 orphan detection at lines 75-116)
- [ ] Update orphan display paths: `git -C .claude/worktrees/${wt_name}` → appropriate `.worktrees/session-*` paths
- [ ] Update orphan remediation instructions: discard command should use `bd worktree remove .worktrees/session-<name>` instead of `git worktree remove .claude/worktrees/<name>`

**Resume instruction text:**
```
Session worktree exists at .worktrees/session-<name> (branch: <branch>). Before doing anything else — before reading files, running commands, or responding to the user — run cd .worktrees/session-<name> to resume working in it.
```

**Multiple session worktrees edge case (specflow G1):** If `ls -d .worktrees/session-*` returns multiple entries, sort by modification time (`ls -dt`), pick the most recent, and instruct the model to `cd` into it. Append a note listing the other worktree(s) with their branch names so the model can inform the user. The model cannot present interactive choices at hook time — the hook fires before any model response. Example output: "2 session worktrees found. Resuming most recent: .worktrees/session-foo (branch: session-foo). Others: .worktrees/session-bar (branch: session-bar)."

**Legacy `.claude/worktrees/` cleanup (specflow G6):** The GC loops should also scan `.claude/worktrees/` as a one-time migration path. If legacy worktrees exist and are fully merged, clean them up. If unmerged, list them alongside the orphan output. This prevents invisible orphans for v3.2.0 upgraders.

**`bd worktree create` error handling (specflow G3):** Add to the new-session instruction text: "If `bd worktree create` fails, warn the user and proceed on main." The pre-commit safety check (AGENTS.md) catches commits to main when session_worktree is enabled — this is the safety net.

**Test:** After rewriting, verify the hook runs correctly: `bash plugins/compound-workflows/templates/session-worktree.sh` should produce stdout output and exit 0 (will need a mock environment or test in a configured project).

### Step 2: Fix session-merge.sh
**Files:** `plugins/compound-workflows/scripts/session-merge.sh`
**Estimate:** 15 min

Two fixes:

- [ ] Line 48: Change `git status --porcelain` to `git status --porcelain --untracked-files=no`. This fixes false exit 4 (dirty main) when untracked files are present. Untracked files don't affect merge safety. (see brainstorm: Section 4 — discovered 2026-03-15)
- [ ] Line 138: Change `WORKTREE_DIR="$REPO_ROOT/.claude/worktrees"` to `WORKTREE_DIR="$REPO_ROOT/.worktrees"`. Additionally, update the cleanup match pattern from `"$WORKTREE_DIR"/*` to a two-stage filter: first match `"$WORKTREE_DIR"/*` (any worktree in `.worktrees/`), then check `[[ "$(basename "$wt_path")" == session-* ]]` to only clean up session worktrees. This prevents accidental removal of `/do:work` worktrees while working correctly with the glob pattern. (specflow G7, red team Finding 2 — original `session-` prefix approach broke the `/*` glob)

**Note:** The `git status --porcelain` at line 126 in session-worktree.sh (Step 6 dirty-main warning) should keep showing untracked files — that's a user warning, not a merge safety gate. Only the merge script's check needs `--untracked-files=no`.

### Step 3: Update AGENTS.md
**Files:** `AGENTS.md`
**Estimate:** 10 min

Replace the "Session Worktree Isolation" section (lines 189-203) with the v2 canonical wording from the brainstorm:

- [ ] Replace entire section with this v2 text:

```markdown
## Session Worktree Isolation

**At session start, before doing anything else, create a session worktree.**
Run `bd worktree create .worktrees/session-<name>` and `cd` into it.
Do not read files, run commands, or respond to the user first.

- Name the worktree after the task if known: `session-s7qj` or `session-fix-typo`
- User can say "stay on main" / "skip worktree" to opt out
- If you're already in a worktree (post-compact resume), skip — you're already isolated
- If `bd worktree create` fails, warn the user and proceed on main
- If the hook warns that bd is unavailable, skip worktree creation
- At session end, `/do:compact-prep` merges back to the default branch
- Any git operations before creating the worktree happen on the default branch
- Before committing, if session_worktree is enabled and you're NOT in a worktree,
  warn the user: "You're committing to main without worktree isolation. Continue?"

**Beads database (.beads/) is shared across all sessions.** Worktree isolation covers git state only. Bead operations are concurrency-safe at the SQL level (Dolt) but not coordination-safe at the business logic level.
```

### Step 4: Update do-compact-prep/SKILL.md
**Files:** `plugins/compound-workflows/skills/do-compact-prep/SKILL.md`
**Estimate:** 20 min

Update Step 4.5 (session worktree merge) and related detection:

- [ ] Update "Detect Worktree Status" description: remove `.claude/worktrees/` from accepted paths. Detection should check if CWD is inside a `.worktrees/session-*` path.
- [ ] Step 4.5.2 (Exit worktree): Replace `ExitWorktree(action: "keep")` with: "Extract the main repo path from `git worktree list --porcelain` output (first line, strip `worktree ` prefix). Run `cd <extracted-path>` via Bash tool." Make this the primary method, not a fallback.
- [ ] Remove ExitWorktree fallback text — `cd` is now the only exit method
- [ ] Step 4.5.8 or cleanup: Update cleanup command from `git worktree remove .claude/worktrees/<name>` to `bd worktree remove .worktrees/session-<name>`
- [ ] Read `session_worktree` value from `compound-workflows.local.md` using: `grep -m1 '^session_worktree:' compound-workflows.local.md | sed 's/#.*//' | awk -F: '{print $2}' | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]'`. If file missing or key absent, treat as disabled (no warning needed).
- [ ] Summary line enhancement: When `session_worktree: true` but session is NOT in a worktree, the summary should read: `Worktree: not in worktree (WARNING — session_worktree enabled but no worktree entered)` instead of just `not in worktree`
- [ ] Make Step 2→Step 4.5 ordering explicit: Add a gate before Step 4.5 that checks `git -C <worktree-path> status --porcelain` for uncommitted changes. Gate behavior by mode: (a) **Regular mode, user did not skip commit:** uncommitted changes shouldn't exist — warn and proceed. (b) **Regular mode, user skipped commit:** warn "Worktree has N uncommitted changes that will NOT be included in the merge. Continue?" via AskUserQuestion. (c) **Abandon mode:** warn in summary but proceed (abandon auto-proceeds, doesn't prompt). No auto-commit in any mode — committing without user consent risks capturing broken state. (specflow G2, red team Finding 4)

### Step 5: Update do-work/SKILL.md
**Files:** `plugins/compound-workflows/skills/do-work/SKILL.md`
**Estimate:** 15 min

Update Phase 1.2 (session worktree detection):

- [ ] Line 87: Change "created by the SessionStart hook via `EnterWorktree`" to "created by the SessionStart hook via `bd worktree create`"
- [ ] Line 87: Change "Session worktrees live in `.claude/worktrees/` — a different namespace from bd-managed `.worktrees/`" to "Session worktrees live in `.worktrees/` with a `session-` prefix, distinguishing them from `/do:work` worktrees in the same directory"
- [ ] Update detection logic: Check for `session-` prefix in the worktree path instead of `.claude/worktrees/` in the path
- [ ] Line 97 comment: Update "Why not `bd worktree info`" explanation — the namespace distinction is now prefix-based (`session-` vs work worktrees), not directory-based
- [ ] Line 99: Update condition from "If CWD is inside a session worktree (`.claude/worktrees/`)" to "If CWD is inside a session worktree (`.worktrees/session-*`)"

### Step 6: Update do-setup/SKILL.md
**Files:** `plugins/compound-workflows/skills/do-setup/SKILL.md`
**Estimate:** 25 min

Three areas to update:

- [ ] Step 7k (.gitignore): Change from checking/adding `.claude/worktrees/` to verifying `.worktrees/` is present (it should already be there for bd-managed worktrees). Remove the `.claude/worktrees/` specific logic.
- [ ] Step 8c (AGENTS.md injection): Replace the v1 Session Worktree Isolation block with the v2 canonical text from the brainstorm. The injected block must match what Step 3 puts in this repo's AGENTS.md.
- [ ] Step 8c idempotency: The existing check (`grep -q '## Session Worktree Isolation'`) will find v1 blocks and skip injection. Add v1→v2 migration: check if `## Session Worktree Isolation` heading exists AND any of the next 5 non-empty lines contain `EnterWorktree` (tighter detection — avoids false matches on user notes elsewhere in the file). If v1 detected, replace the entire section up to the next `##` heading with v2 canonical text. Note 'v1→v2 updated' in the setup summary report. (red team MINOR — tighter migration detection per Opus Finding 8)

### Step 7: Update recover/SKILL.md + do-merge/SKILL.md
**Files:** `plugins/compound-workflows/skills/recover/SKILL.md`, `plugins/compound-workflows/skills/do-merge/SKILL.md`
**Estimate:** 20 min

**recover/SKILL.md — Phase 6 (worktree recovery):**
- [ ] Step 6.2: Change filter from "path contains `.claude/worktrees/`" to "path contains `.worktrees/session-`"
- [ ] Step 6.3: Update all `.claude/worktrees/` references to `.worktrees/session-*`
- [ ] Step 6.4 (orphan branch detection): Change branch pattern from `worktree-*` to `session-*` (bd worktree creates branches matching the worktree name)
- [ ] Step 6.3 discard option: use `bd worktree remove .worktrees/session-<name>` (consistent with Step 1 remediation instructions)
- [ ] Step 6.5 (state-snapshot.md): Update path references

**do-merge/SKILL.md:**
- [ ] Line 19: Change filter from `.claude/worktrees/` to `.worktrees/session-` (session worktrees distinguished by `session-` prefix, not directory)
- [ ] Line 43: Change "should NOT point to a `.claude/worktrees/` path" to "should NOT contain `.worktrees/session-`"

### Step 8: Add git pre-commit hook template
**Files:** `plugins/compound-workflows/templates/pre-commit-worktree-check.sh`, `plugins/compound-workflows/skills/do-setup/SKILL.md`
**Estimate:** 20 min

Deterministic enforcement: a git-level pre-commit hook that blocks commits to main when `session_worktree: true`. Defense-in-depth alongside the AGENTS.md prose instruction — the prose tells the model to create a worktree, the git hook catches failures. (red team Finding 1 — all 3 providers flagged prose-only enforcement)

- [ ] Create `plugins/compound-workflows/templates/pre-commit-worktree-check.sh` (~15 lines):
  - Read `session_worktree` from `compound-workflows.local.md` (same grep pattern as SessionStart hook)
  - If not `true`, exit 0 (feature disabled, allow commit)
  - Check if CWD is inside `.worktrees/session-*`
  - If yes, exit 0 (in a session worktree, commit is safe)
  - If no, print warning to stderr: "session_worktree is enabled but you're committing to the default branch. Use --no-verify to bypass." Exit 1 (block commit).
- [ ] Update do-setup to install this as `.git/hooks/pre-commit` (or append to existing pre-commit hook if one exists)
- [ ] Update do-setup summary to report pre-commit hook status
- [ ] User escape hatch: `git commit --no-verify` bypasses the hook for intentional main commits

**Why git hook, not Claude Code hook:** PreToolUse exit 2 doesn't block when auto-approve.sh returns "allow" first (empirically proven). PostToolUse fires after the commit. A `.git/hooks/pre-commit` runs at the git level before the commit — it can abort it. (see brainstorm: process lesson — enumerate all available mechanisms)

### Step 9: Integration test + QA + Version Bump + CHANGELOG
**Files:** `plugins/compound-workflows/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `plugins/compound-workflows/CHANGELOG.md`, `plugins/compound-workflows/README.md`
**Estimate:** 30 min

**Integration test (red team Finding 7 — script test ≠ hook delivery test):**
- [ ] Install the updated session-worktree.sh template to a test project's `.claude/hooks/`
- [ ] Start a new Claude Code session and verify the system-reminder appears in model context
- [ ] Verify model creates worktree and cd's into it before responding
- [ ] Test resume: exit session, start new session, verify model cd's into existing worktree
- [ ] Test pre-commit hook: attempt `git commit` on main with `session_worktree: true`, verify it blocks
- [ ] Test abandon mode: verify worktree merge works via `/do:abandon`

**Version + QA:**
- [ ] Bump version in plugin.json (MINOR bump → v3.3.0)
- [ ] Bump version in marketplace.json (match)
- [ ] Add CHANGELOG entry: lead with user benefit ("Session worktree isolation now works — hook output delivered, worktrees persist across sessions"). Frame as "Fixed" not "Added" despite MINOR bump.
- [ ] Verify README component counts (template count increases by 1 for pre-commit-worktree-check.sh)
- [ ] Run Tier 1 QA scripts — verify no stale `EnterWorktree`, `ExitWorktree`, or `.claude/worktrees/` references remain in plugin files
- [ ] Run Tier 2 semantic QA agents
- [ ] Fix any QA findings

**QA note:** `stale-references.sh` should flag any remaining v1 references. After this change, `EnterWorktree`, `ExitWorktree`, and `.claude/worktrees/` in plugin files are stale patterns. Brainstorm docs and the superseded plan are excluded from stale checks (they're historical records).

## Dependencies

Steps 1-3 are independent (template, merge script, AGENTS.md — separate files).
Steps 4-7 depend on knowing the v2 patterns but can execute in parallel (separate skill files).
Step 8 (pre-commit hook) is independent but logically groups with Steps 1-3.
Step 9 depends on all previous steps being complete.

All steps are executed sequentially by `/do:work` — "parallel" means logically independent (no file overlap), not literal parallel dispatch. If any step produces text that differs from the plan, subsequent steps must use the actual text. (red team Finding 9)

```
Steps 1, 2, 3, 8  (logically independent — separate files)
    ↓
Steps 4, 5, 6, 7  (logically independent — separate skill files)
    ↓
Step 9  (sequential — integration test + QA + version)
```

## Acceptance Criteria

1. SessionStart hook delivers output to model as system-reminder (stdout + exit 0) — verified via integration test
2. Session worktrees persist after `/exit` (bd worktree, not EnterWorktree)
3. Model auto-creates worktree before responding on new session (strong AGENTS.md wording)
4. Model cd's into existing worktree on resume (hook detects .worktrees/session-*)
5. `session-merge.sh` doesn't false-positive on untracked files
6. Git pre-commit hook blocks commits to main when `session_worktree: true` and not in worktree
7. No references to `EnterWorktree`, `ExitWorktree`, or `.claude/worktrees/` remain in plugin files (excluding brainstorms and superseded plan)
8. Compact-prep warns when session_worktree enabled but not in worktree
9. All QA checks pass (Tier 1 + Tier 2)

## Inherited Assumptions

Load-bearing assumptions this plan inherits. Per ytlk/fyg9 framework (see `docs/brainstorms/2026-03-15-assumption-verification-v2-brainstorm.md`).

### Carried Forward (from brainstorm empirical testing)

| # | Assumption | Verification | Status | Risk if wrong |
|---|-----------|-------------|--------|---------------|
| 1 | `stdout + exit 0` delivers SessionStart hook output as system-reminder | Tested 2026-03-14/15 on Claude Code ~2.1.74, macOS | **Verified (single version)** | Feature non-functional — same as v3.2.0 bug. Step 9 integration test detects. |
| 2 | `bd worktree create .worktrees/session-foo` creates branch `session-foo` | Tested 2026-03-15 | **Verified (single test)** | Orphan detection, merge, GC all break. Step 9 integration test detects. |
| 3 | `cd` in Bash tool changes CWD for ALL subsequent tool calls (Read, Edit, Glob, Grep) | Core Claude Code behavior, used throughout this project and all worktree features | **Assumed (undocumented)** | Worktree isolation fundamentally broken — model reads/writes main repo while in worktree. No mitigation possible; would require abandoning the worktree approach entirely. |
| 4 | SessionStart hook fires before any model action | Tested empirically (model received instruction before responding) | **Verified (single version)** | Model acts on main before seeing worktree instruction. Pre-commit hook (Step 8) is backstop. |
| 5 | session-merge.sh retry loop handles concurrent merges via git's `index.lock` | Tested in original s7qj brainstorm with overlapping and disjoint file scenarios | **Verified** | Concurrent merge corruption. Git's own locking prevents this — well-established git behavior. |
| 6 | Compact-prep runs before session end | By convention, not enforced. Crashes/kills skip it. | **Assumed (by design)** | Uncommitted worktree changes orphaned. Handled by crash recovery flow (SessionStart orphan detection + /compound-workflows:recover). |
| 7 | `$PPID` in SessionStart hook is the Claude Code process | Untested. Depends on how Claude Code spawns hooks (fork+exec vs bash -c). User uses tmux — process chain is tmux→zsh→claude→hook. | **Unverified** | PID locking gives false "safe to resume" (false negative, not false positive). Fallback: resume works normally, just without concurrent-session warning. Verify in Step 9: check if `$PPID` matches the claude process. If not, consider `pgrep -f claude` as alternative. |

### Newly Identified (plan-specific)

None — all assumptions trace to the brainstorm or prior implementation.

## Resolved Questions (from specflow analysis)

1. **Multiple orphan worktrees (G1)** — Hook picks most recently modified, lists others. Model can't present choices pre-response. Resolved: specified in Step 1.
2. **bd branch naming (G11/Q2)** — Empirically verified in prior session: `bd worktree create .worktrees/session-foo` creates branch `session-foo`. Branch name matches final path component.
3. **Compact-prep ordering (G2/Q3)** — Execute phase runs in strict dependency order. Added explicit gate in Step 4 to verify no uncommitted changes before merge.
4. **Legacy .claude/worktrees/ (G6/Q4)** — Added one-time migration GC to Step 1 hook. Scans both old and new paths.
5. **Post-cd verification (G5)** — Accepted risk. `cd` failure after successful `bd worktree create` is extremely rare (would require external deletion between two sequential commands). The pre-commit safety check in AGENTS.md catches the failure mode at commit time. Adding a post-cd verification step would add complexity without meaningful safety improvement.
6. **Setup v1→v2 migration (G8/Q6)** — Step 6 specifies: check for `EnterWorktree` inside existing block as v1 indicator, replace entire section.
7. **Merge cleanup scope (G7/Q8)** — Two-stage filter: match `.worktrees/*` then check `session-*` basename. Original prefix approach (`session-`) broke the `/*` glob pattern. [red-team--opus, see .workflows/plan-research/fix-worktree-session-isolation-v2/red-team--opus.md]
8. **Error handling (G3/Q7)** — Added to AGENTS.md text: "If `bd worktree create` fails, warn the user and proceed on main."
9. **bd-missing + AGENTS.md conflict (G9)** — Added to AGENTS.md text: "If the hook warns that bd is unavailable, skip worktree creation."
10. **Pre-commit check mechanism (G10/Q5)** — Defense-in-depth: AGENTS.md prose instruction (primary) + git `.git/hooks/pre-commit` script (deterministic backstop). Added as Step 8. PreToolUse exit 2 doesn't work (auto-approve.sh overrides), but git-native pre-commit hooks run at the git level and can abort commits. [red-team--openai, red-team--gemini, red-team--opus — all 3 providers flagged prose-only enforcement]
11. **Concurrent name collision (G12)** — Accepted risk. Concurrent sessions are rare, `bd worktree create` fails loudly, model can retry with different name.
12. **QA stale references (G13)** — Already covered in Step 8. stale-references.sh catches `EnterWorktree`, `ExitWorktree`, `.claude/worktrees/` patterns.
13. **Naming collision vs resume (G4)** — Hook runs first and detects existing session-* worktrees. If any exist, hook instructs resume (not create). AGENTS.md's "if already in a worktree, skip" is the secondary guard.

## Resolved Questions (from red team)

1. **Non-deterministic enforcement** (all 3 providers, OpenAI CRITICAL) — Resolved: added git pre-commit hook (Step 8) as deterministic backstop. AGENTS.md prose + git hook = defense-in-depth. PreToolUse blocking doesn't work (auto-approve.sh overrides exit 2). [red-team--openai, red-team--gemini, red-team--opus]
2. **session-merge.sh glob pattern** (Opus SERIOUS) — Resolved: changed from prefix-based WORKTREE_DIR to two-stage filter (match `.worktrees/*` then check `session-*` basename). Original `session-` suffix broke `/*` glob. [red-team--opus]
3. **Compact-prep gate behavior** (Opus SERIOUS) — Resolved: specified gate behavior for all 3 modes (regular+commit, regular+skip, abandon). No auto-commit — warn and let user decide. [red-team--opus]
4. **No integration test** (Opus SERIOUS) — Resolved: added integration test checkpoint to Step 9 (install hook, start session, verify delivery, test resume, test pre-commit, test abandon). [red-team--opus]
5. **Resume active vs orphaned** (OpenAI + Opus SERIOUS) — Resolved: added PID-based detection to Step 1. Hook writes `$PPID` to `.session.pid`, checks `kill -0` on resume. If alive → warn about concurrent session. [red-team--openai, red-team--opus]
6. **Gitignored files absent in worktree** (Gemini CRITICAL) — Valid for user code repos. Out of scope for this fix plan (pre-existing limitation). Tracked as bead gu2z (P1). [red-team--gemini]
7. **Native tool CWD desync** (Gemini CRITICAL) — Dismissed: factually incorrect. Claude Code's `cd` in Bash DOES change CWD for all subsequent tool calls (Read, Edit, etc.). This is core Claude Code behavior. [red-team--gemini]
8. **Config reading while in worktree** (Gemini CRITICAL) — Compact-prep reads config at startup (may be in worktree). Read tool uses absolute paths, so config file at repo root is accessible from worktree. Compact-prep also exits worktree (Step 4.5.2) before merge actions. No change needed. [red-team--gemini]

## Open Questions

1. **Model compliance consistency** — tested twice (create + resume). Need more sessions to confirm reliability across model versions and context sizes. Not a blocker for implementation — monitor empirically post-release. (carried from brainstorm)
2. ~~**Version bump level (specflow G14)**~~ — **Resolved: MINOR (v3.3.0).** Scope is significant (new hook mechanism, new paths, removed tool dependencies) even though it's fixing a broken feature. User decision: signals to upgraders that attention is needed.

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-03-14-session-worktree-v2-brainstorm.md` — 13 key decisions, 14 empirical tests, full "What Changes" table. All implementation details flow from this document.
- **Superseded plan:** `docs/plans/2026-03-14-fix-worktree-session-isolation-plan.md` (status: superseded) — v3.2.0 implementation that this plan fixes
- **Repo research:** `.workflows/plan-research/fix-worktree-session-isolation-v2/agents/repo-research.md` — line-by-line inventory of all files and references needing changes
- **Learnings:** `.workflows/plan-research/fix-worktree-session-isolation-v2/agents/learnings.md` — s7qj plan-vs-deepen role separation, .claude/ write restrictions, script-file bypass patterns
- **SpecFlow analysis:** `.workflows/plan-research/fix-worktree-session-isolation-v2/agents/specflow.md` — 14 gaps identified (G1-G14), 12 resolved, 2 carried as open questions
- **Red team (Gemini):** `.workflows/plan-research/fix-worktree-session-isolation-v2/red-team--gemini.md` — 3 CRITICAL (1 dismissed, 1 out-of-scope, 1 no-change-needed), 2 SERIOUS, 3 MINOR
- **Red team (OpenAI):** `.workflows/plan-research/fix-worktree-session-isolation-v2/red-team--openai.md` — 1 CRITICAL (resolved via Step 8), 4 SERIOUS, 2 MINOR
- **Red team (Opus):** `.workflows/plan-research/fix-worktree-session-isolation-v2/red-team--opus.md` — 5 SERIOUS (all resolved), 7 MINOR
