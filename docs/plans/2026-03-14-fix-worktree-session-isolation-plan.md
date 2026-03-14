---
title: "Worktree-Per-Session Isolation"
type: fix
status: active
date: 2026-03-14
origin: docs/brainstorms/2026-03-13-git-index-isolation-brainstorm.md
---

# Worktree-Per-Session Isolation

**Bead:** s7qj
**Problem:** Concurrent Claude Code sessions share `.git/index` — cross-contaminated commits. Empirical data: 74 concurrent session pairs across 87 sessions, 40% edit overlapping files, 1.3s tightest same-file collision on disk.

## Design Summary

Every Claude Code session enters a git worktree via `EnterWorktree` (Claude Code native tool) at session start. Sessions work in isolation — own branch, own index, own file copies. At session end (compact-prep/abandon), changes are committed in the worktree, then merged into main via `git merge --no-ff` with a retry loop. Claude auto-resolves conflicts and presents resolutions for user review before applying.

**Key decisions from brainstorm (see brainstorm: docs/brainstorms/2026-03-13-git-index-isolation-brainstorm.md):**
- Model 1 (always-worktree) — no detection race, solo merges fast-forward
- `EnterWorktree`/`ExitWorktree` (Claude Code native) — switches CWD, refreshes caches on exit
- Merge serialization: git's own `index.lock` handles it; retry loop (1-3s, 3 attempts). Tested empirically.
- `bd` auto-discovers beads DB from worktrees (tested empirically)
- `GIT_INDEX_FILE` wrapper deferred to follow-up (not v1)

## Configuration

### `compound-workflows.local.md`

```
session_worktree: true
```

| Key | Default | Effect |
|-----|---------|--------|
| `session_worktree` | `true` | When `false`: SessionStart hook skips EnterWorktree instruction, compact-prep skips merge step, no orphan/dirty-main warnings. Everything works exactly as today. |

**Per-session override:** When `session_worktree: true`, user can still say "skip worktree" / "stay on main" at session start to opt out for that session. Reasoning: user may know they're in a single non-concurrent session and want to skip the overhead — e.g., a quick CHANGELOG fix where the merge step at session end adds friction for zero safety benefit.

## Implementation Steps

**Implementation order constraint:** Create `skills/do-merge/SKILL.md` (Step 6) BEFORE modifying compact-prep/recover/AGENTS.md to reference `/do:merge`. Otherwise `stale-references.sh` fires SERIOUS on intermediate commits. Recommended order: Step 6 → Step 1-5 → Step 7-10.

### Step 1: SessionStart Hook Script

Create `.claude/hooks/session-worktree.sh`.

**Behavior:**

1. Read `session_worktree` from `compound-workflows.local.md`:
   ```bash
   CONFIG="compound-workflows.local.md"
   if [[ ! -f "$CONFIG" ]]; then
     exit 0  # No config = feature not set up, silent skip
   fi
   VALUE=$(grep -m1 '^session_worktree:' "$CONFIG" | sed 's/#.*//' | awk -F: '{print $2}' | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' || true)
   # Detect default branch for orphan commit counts
   DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)
   DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
   if [[ "$VALUE" == "false" ]]; then
     # Feature disabled — still check for orphaned worktrees (prevent silent orphaning)
     # ... orphan check only, then exit 0
   fi
   ```
   **Parsing contract:** Only explicit `false` disables. Missing key, empty value, `true`, or any other value = enabled. This is a bash script, not LLM-interpreted — must use explicit extraction.
2. Check if CWD is inside `.claude/worktrees/`:
   - **Yes (post-compact resume):** Output resume message to stderr and **exit 2 immediately** — skip steps 3-5 (no orphan/dirty checks needed when already in a worktree): "You are in worktree `<dirname>` on branch `<branch>`. Continue working here. At session end, compact-prep will merge your changes into main."
   - **No (fresh session start):** Continue to step 3.
3. Check for orphaned worktrees: `ls .claude/worktrees/` minus current CWD (if applicable).
   - For each orphan, gather: branch name (`git -C <path> branch --show-current`), uncommitted file count (`git -C <path> status --short | wc -l`), committed-but-unmerged count (`git log $DEFAULT_BRANCH..<branch> --oneline | wc -l`).
   - If other worktrees found: append to output buffer:
     ```
     Note: N worktrees from other sessions detected (may be active or orphaned):
       - <name> (branch: <branch>, N uncommitted files, M unmerged commits)
         Inspect: git -C .claude/worktrees/<name> status
         Merge:   /do:merge
         Discard: git worktree remove .claude/worktrees/<name> && git branch -D <branch>
     ```
   - Uses "other sessions" not "orphaned" — the hook cannot distinguish active concurrent sessions from genuinely abandoned worktrees. The user decides. This covers the primary crash case (context exhaustion where compact-prep never ran) while avoiding false-alarm noise for active concurrent sessions.
4. Check for dirty main: `git status --porcelain`.
   - If dirty: append to output buffer: "Warning: main has uncommitted changes. These will NOT be visible in the worktree (branches from HEAD commit)."
5. Append to output buffer: "Session isolation active. Call `EnterWorktree` to work in an isolated worktree. Say 'stay on main' to skip."
6. **Output entire buffer to stderr and exit 2.** Single exit point for the fresh-start path (steps 3-5 accumulate output, step 6 emits it all).

**Output mechanism:** stderr with exit 2 (shown as feedback to model). Two exit points: step 2 (resume, early exit) and step 6 (fresh start, after all checks).

**Hook does NOT:** call EnterWorktree (can't — subprocess limitation), change CWD, or block the session.

### Step 2: Register SessionStart Hook

Add to `.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [{
      "matcher": "",
      "hooks": [{"type": "command", "command": "bash .claude/hooks/session-worktree.sh"}]
    }],
    ...existing hooks...
  }
}
```

### Step 3: AGENTS.md Worktree Instructions

Add to AGENTS.md Key Conventions section:

```markdown
## Session Worktree Isolation

When the SessionStart hook instructs you to call `EnterWorktree`, do so BEFORE any
other action — before reading files, running commands, or processing other tasks.
This isolates your session's git index and working tree from concurrent sessions.

- Call `EnterWorktree` as your FIRST action at session start (hook will prompt you)
- User can say "stay on main" / "skip worktree" to opt out for the session
- At session end, `/do:compact-prep` handles the merge back to the default branch
- When compact-prep or abandon instructs you to call `ExitWorktree`, comply — this is a programmatic exit, not a proactive one
- If you're already in a worktree (post-compact resume), continue working there
- Any git operations before EnterWorktree happen on the default branch — the contamination scenario this exists to prevent
```

### Step 4: Merge Script

Create `plugins/compound-workflows/scripts/session-merge.sh`.

**Interface:**
```bash
bash session-merge.sh <worktree-branch-name>
```

**Behavior:**

0. **Detect default branch:**
   ```bash
   DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
   DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"  # fallback for repos without remote HEAD
   ```
   Use `$DEFAULT_BRANCH` everywhere the script references `main`. This makes the plugin work for repos using `master`, `develop`, or any default branch.

1. **Verify on default branch:** `git branch --show-current` must return `$DEFAULT_BRANCH`. If not, exit 1 with error.

2. **Check for dirty default branch:** `git status --porcelain`
   - If dirty: **refuse to merge.** Exit with code 4 and message: "`$DEFAULT_BRANCH` has uncommitted changes. Cannot merge safely — another session may be working on `$DEFAULT_BRANCH`. Clean up and retry. Your worktree branch is preserved."
   - Reasoning: auto-committing could commit another concurrent session's in-progress work. The safe path is to refuse and let the user decide. (See G9 resolution.)

3. **Merge with retry loop:**
   ```
   for attempt in 1 2 3; do
     git merge --no-ff <branch> && break
     if error contains "index.lock"; then
       sleep $((attempt))  # 1s, 2s, 3s backoff
       continue
     fi
     # Non-lock error (conflict or other) — break and handle
     break
   done
   ```

4. **Handle merge result:**
   - **Success (exit 0):** Proceed to cleanup.
   - **Conflict:** Exit with code 2 and list of conflicted files. Caller (compact-prep) handles resolution.
   - **Retry exhaustion (3 index.lock failures):** Exit with code 3. Caller warns user, leaves worktree unmerged.
   - **Exit 4 (dirty main):** Warn: "Main has uncommitted changes (possibly from a concurrent session). Cannot merge safely. Worktree branch `<name>` preserved — clean up main and retry with `git merge --no-ff <branch>`."
   - **Exit 1 (other error):** Show error, offer retry/skip/abort per compact-prep's standard per-step retry semantics.

5. **Cleanup (on success only):**
   ```bash
   git worktree remove .claude/worktrees/<name>
   git branch -d <branch>  # Should work — branch is merged
   # Fallback if -d fails:
   git branch -D <branch>  # Inside script — bypasses auto-approve heuristics
   ```

**Location:** `plugins/compound-workflows/scripts/session-merge.sh` — auto-approves via `bash <path>` static rule.

### Step 5: Modify compact-prep/SKILL.md

**Changes to the execute phase:**

Insert new Step 4.5 between Step 4 (commit compound docs) and Step 5 (version actions):

#### Step 4.5: Session Worktree Merge

**Skip if:** `session_worktree: false` in config, OR session is NOT in a worktree (detected via `git worktree list` — if CWD is not a worktree, skip).

**Procedure:**

1. **Record worktree info before exiting:**
   - Worktree branch name: `git branch --show-current`
   - Worktree path: `pwd`

2. **Exit worktree:** Call `ExitWorktree(action: "keep")`.
   - If ExitWorktree fails or is a no-op: fall back to a model-level `cd <main-repo-path>` via the Bash tool (CWD persists between Bash calls — this is NOT a cd inside a script). Extract main repo path via `git worktree list | head -1 | awk '{print $1}'` (first listed worktree is always the main one).

3. **Run merge script:** Use `${CLAUDE_SKILL_DIR}/../../scripts/session-merge.sh` (standard skill convention — resolves from the compact-prep skill directory, not from `$PLUGIN_ROOT` which may be stale after ExitWorktree cache clear):
   ```bash
   bash ${CLAUDE_SKILL_DIR}/../../scripts/session-merge.sh <worktree-branch-name>
   ```

4. **Handle merge script result:**
   - **Exit 0 (success):** Announce "Session worktree merged and cleaned up." Proceed to Step 5.
   - **Exit 2 (conflict):** Claude reads conflicted files, auto-resolves (keep both sides for additive markdown, attempt semantic merge for others). Present resolution summary to user: "Resolved N conflicts: [file: resolution summary]."
     - **Normal mode:** AskUserQuestion: "Accept merge resolutions?" Options: "Accept" / "Review specific files" / "Abort merge (keep worktree)". If accepted: `git add` resolved files + `git commit --no-edit`. If aborted: run `git merge --abort` to clean up the mid-merge state, then warn user that worktree branch is unmerged.
     - **Abandon mode:** Auto-accept additive-only resolutions (both sides kept, no content lost). For non-additive conflicts (divergent rewrites, code): run `git merge --abort`, preserve worktree branch, warn: "Non-trivial conflict during abandon — worktree preserved. Run `/do:merge` to resolve later." Do NOT block with AskUserQuestion during abandon — the user has explicitly said they're leaving.
   - **Exit 3 (retry exhaustion):** Warn: "Could not merge — another session is merging. Worktree branch `<name>` is unmerged. Merge manually with `git merge --no-ff <branch>` from main."
   - **Exit 4 (dirty main):** Warn: "Main has uncommitted changes (possibly from a concurrent session). Cannot merge safely. Worktree branch `<name>` preserved — clean up main and retry with `/do:merge`."
   - **Exit 1 (other error):** Show error, offer retry/skip/abort per compact-prep's standard per-step retry semantics.

5. **Branch guard before compact-prep Step 6:** Verify `git branch --show-current` returns the default branch before proceeding to push.

#### Modifications to existing steps:

- **Compact-prep Steps 1-4:** No changes. They run inside the worktree (commit to worktree branch). This is correct — memory updates, commits, and compound all happen in the isolated worktree.
- **Compact-prep Step 5 (version actions):** Now runs from main (after merge). Tags are created on main. Correct.
- **Compact-prep Step 6 (push):** Now pushes from main (after merge). Add branch guard: `git branch --show-current` must return the default branch. If not, warn and skip push.

### Step 6: `/do:merge` Skill

Create `plugins/compound-workflows/skills/do-merge/SKILL.md`.

**YAML frontmatter:**
```yaml
---
name: do:merge
description: Retry a deferred worktree merge — used when compact-prep's merge couldn't complete
argument-hint: "[branch-name (optional)]"
---
```

**Purpose:** Retry a deferred worktree merge. Used when compact-prep's merge step couldn't complete (dirty main, retry exhaustion, user aborted). Single-phase skill — the merge script handles validation internally.

**Skill body structure:**

```markdown
# Merge Deferred Worktree

Merge an unmerged session worktree branch into main.

## Arguments

<branch_name> #$ARGUMENTS </branch_name>

## Execution

### 1. Detect unmerged worktrees

Run `git worktree list` and identify worktrees in `.claude/worktrees/`
whose branches have not been merged into main:

    git worktree list
    # For each .claude/worktrees/<name>, check:
    git log main..<branch> --oneline | head -1

### 2. Select branch

- **Branch argument provided:** Use it directly (no confirmation needed).
- **No argument, exactly 1 unmerged worktree:** Auto-select with announcement:
  "Merging worktree branch `<name>` into main."
- **No argument, multiple unmerged worktrees:** AskUserQuestion:
  "Which worktree to merge?" with branch list + uncommitted/unmerged counts.
- **No unmerged worktrees found:** Announce "No unmerged worktree branches found." Stop.

### 3. Verify on main

Verify CWD is the main repo (not inside a worktree). If inside a worktree,
warn: "Cannot merge from inside a worktree. Exit the worktree first."

### 4. Run merge script

    bash ${CLAUDE_SKILL_DIR}/../../scripts/session-merge.sh <branch>

### 5. Handle result

- **Exit 0:** "Merged and cleaned up."
- **Exit 2 (conflict):** Read conflicted files, auto-resolve additive markdown,
  present resolution summary. AskUserQuestion: Accept / Review / Abort.
  If accepted: `git add` + `git commit --no-edit`.
- **Exit 3 (retry exhaustion):** "Another session is merging. Try again shortly."
- **Exit 4 (dirty main):** "Main has uncommitted changes. Commit or stash them,
  then run `/do:merge` again."
- **Exit 1 (other):** Show error.
```

**Minimum line count:** ≥20 lines in the skill body (satisfies `truncation-check.sh`).

**Discoverability — hint to user in these contexts:**
- Compact-prep Step 4.5 merge failure (exit 1/3/4): "Run `/do:merge` to retry when ready."
- Compact-prep conflict abort: "Worktree preserved. Run `/do:merge` to retry."
- SessionStart orphan warning: "To merge an orphaned worktree: `/do:merge`"
- `/compound-workflows:recover` worktree detection: "Unmerged worktree found. Run `/do:merge` to merge."

### Step 7: Modify `/do:setup`

Full portability setup — all components installed for any repo using the plugin, not just this repo.

**Changes to `plugins/compound-workflows/skills/do-setup/SKILL.md`:**

#### 7a. Config key (Step 8b initial generation + Step 8d migration)

Add `session_worktree` to the config generation step that writes `compound-workflows.local.md`. Default value: `true`. Add alongside existing keys (`tracker`, `gh_cli`, `stats_capture`, etc.).

**Idempotent:** If `session_worktree` already exists, preserve the user's value. Only add if missing. Same pattern as all other setup config keys.

```
# Session worktree isolation (concurrent session safety)
# Set to false to disable worktree-per-session — sessions work directly on main
session_worktree: true
```

Also add to Step 8d migration table: `grep -q 'session_worktree' compound-workflows.local.md` — if missing, append with default `true`. Existing users who re-run setup get the key.

#### 7b. Hook script installation (follows auto-approve.sh template pattern)

Create `plugins/compound-workflows/templates/session-worktree.sh` — the hook template distributed with the plugin.

`/do:setup` copies it to `.claude/hooks/session-worktree.sh`:
- Check if `.claude/hooks/session-worktree.sh` exists
- If missing: copy from `$PLUGIN_ROOT/templates/session-worktree.sh`
- If exists: compare versions (same pattern as auto-approve.sh Step 7b — version comment at top of script, skip if same or newer)
- Ensure `.claude/hooks/` directory exists first (`mkdir -p`)
- After copy: `chmod +x .claude/hooks/session-worktree.sh` (same as auto-approve.sh pattern)

#### 7c. SessionStart hook registration in settings.json

Add SessionStart hook entry to `.claude/settings.json` using the existing jq merge pattern from Step 7c (which already handles PreToolUse):
- Read existing `.claude/settings.json`
- Check if `SessionStart` hook array already contains a `session-worktree.sh` entry
- If missing: merge the new entry (check-before-add, don't clobber existing SessionStart hooks)
- If present: skip (idempotent)

```json
"SessionStart": [{
  "matcher": "",
  "hooks": [{"type": "command", "command": "bash .claude/hooks/session-worktree.sh"}]
}]
```

#### 7d. `.gitignore` entry

Add `.claude/worktrees/` to the user's `.gitignore`:
- Check if `.claude/worktrees/` is already in `.gitignore`
- If missing: append (same pattern as `compound-workflows.local.md` gitignore check in Step 6)
- Silent addition, no user prompt needed

#### 7e. AGENTS.md worktree instructions (Step 8c extension)

Add the worktree isolation instructions to the canonical routing section that `/do:setup` Step 8c injects into the user's AGENTS.md:
- Gate on `session_worktree` config — only inject if `session_worktree` is not `false`
- Add the "Session Worktree Isolation" block (same content as Step 3) to the routing section template
- Idempotent: check if the section already exists before adding

#### 7f. Update plugin CLAUDE.md inventories

- Add `session_worktree` to the config key inventory under `### compound-workflows.local.md` with "reads" attribution: `do-compact-prep`, `session-worktree.sh` hook, `/do:work` Phase 1.2.
- Add `session-worktree.sh` to the `templates/` directory listing.
- Add `session-merge.sh` to the `scripts/` directory listing.
- Add `do-merge/` to the `skills/` directory listing.

**All five components (config, hook, settings, gitignore, AGENTS.md) are bundled together.** A user who runs `/do:setup` gets the full working feature, not a config key that does nothing.

### Step 8: Modify `/do:work` Phase 1.2

Add session worktree detection to `/do:work`'s worktree setup:

```
# At start of Phase 1.2, before worktree creation:
# Check if CWD is inside a session worktree (path-based, not bd-based)
pwd  # Check if output contains .claude/worktrees/
```

If `pwd` output contains `.claude/worktrees/` (session worktree, not a bd-managed `.worktrees/`):
- **Skip:** `bd worktree create` (or `worktree-manager.sh` fallback) and `cd` into worktree — already in one
- **Keep:** `.work-in-progress.d` sentinel setup in the session worktree's `.workflows/` directory
- **Keep:** Branch detection for informational purposes (report current branch name)
- Announce: "Already in session worktree — working directly here (no nested worktree)."

**Why `pwd` not `bd worktree info`:** `bd worktree info` detects bd-managed worktrees in `.worktrees/` (used by `/do:work`). Session worktrees live in `.claude/worktrees/` (different namespace). Path-based detection is correct, works without `bd`, and is the same mechanism the SessionStart hook uses.

### Step 9: Modify `/compound-workflows:recover`

Add worktree recovery to the existing recover skill. Insert after existing JSONL-based session recovery, before the final summary.

**Detection:**
```bash
git worktree list
# Filter for entries containing .claude/worktrees/
# Exclude current CWD if already in a worktree
```

**For each worktree in `.claude/worktrees/` that isn't the current CWD:**

1. Gather info:
   - Branch name: `git -C <path> branch --show-current`
   - Uncommitted files: `git -C <path> status --short | wc -l`
   - Unmerged commits: `git log $DEFAULT_BRANCH..<branch> --oneline | wc -l`
   - Last modified: `stat -f '%Sm' <path>` (macOS) or `stat -c '%y' <path>` (Linux)

2. Present each worktree via AskUserQuestion:
   "Found worktree `<name>` (branch: `<branch>`, N uncommitted files, M unmerged commits, last active: <date>). What would you like to do?"
   - **Merge** — "Run `/do:merge <branch>` to merge into $DEFAULT_BRANCH"
   - **Inspect** — Show `git -C <path> status` and `git -C <path> log --oneline -5` output, then re-ask
   - **Discard** — Confirm: "This will delete all uncommitted work in this worktree. Proceed?" Then: `git worktree remove <path> --force && git branch -D <branch>`
   - **Skip** — Leave for later

3. If multiple worktrees: process one at a time (AskUserQuestion per worktree). Cap at 5 — if >5, show count and suggest cleanup: "N worktrees found. Showing first 5."

**Output:** Include worktree recovery results in the recover skill's final manifest (alongside JSONL recovery results).

### Step 10: Test Matrix

Add test for `/do:merge`:

- [ ] **T14: /do:merge retry** — Dirty main blocks merge → user cleans main → runs `/do:merge` → merge succeeds
- [ ] **T15: /do:merge orphan** — Orphaned worktree from crashed session → `/do:merge` merges it

Verify these scenarios before shipping:

- [x] **A1: ExitWorktree post-compact** — Enter worktree → compact → call ExitWorktree. PASSED (2026-03-14). Tool-level session state survives compaction.
- [ ] **A2: EnterWorktree via hook instruction** — Does model call EnterWorktree when instructed by SessionStart hook despite tool description saying "only when user asks"?
- [ ] **A3: ExitWorktree via compact-prep instruction** — Does model call ExitWorktree when instructed by compact-prep Step 4.5 despite tool description saying "only when user asks"?
- [ ] **T1: Solo session, no conflicts** — Enter worktree → edit files → compact-prep → merge (should fast-forward) → push from main
- [ ] **T2: Concurrent sessions, disjoint files** — Two worktrees, different files → both merge → clean
- [ ] **T3: Concurrent sessions, overlapping file** — Two worktrees both edit `memory/project.md` → first merges clean → second gets conflict → auto-resolve → user reviews
- [ ] **T4: index.lock contention** — Two sessions merge simultaneously → one fails → retry succeeds
- [ ] **T5: Dirty main at merge** — Uncommitted changes on main → merge script refuses (exit 4) → worktree branch preserved → user cleans main → retries merge
- [ ] **T6: Opt-out** — User says "stay on main" → no worktree → compact-prep skips merge step
- [ ] **T7: Config disable** — `session_worktree: false` → no hook output, no merge step, everything as before
- [ ] **T8: Orphaned worktree detection** — Leave a worktree from a prior session → new session warns
- [ ] **T9: `git branch -d` after --no-ff merge** — Verify merged branch deletes without `-D`
- [ ] **T10: `bd` operations in worktree** — `bd show`, `bd create`, `bd close` all work (already verified in brainstorm)
- [ ] **T11: /do:work in session worktree** — `/do:work` detects session worktree and skips its own worktree creation, works directly in session worktree
- [ ] **T12: Retry exhaustion** — 3 index.lock failures → warn user, leave worktree unmerged
- [ ] **T13: Conflict resolution rejection** — User says "abort merge" → worktree preserved, user warned
- [ ] **T16: Subagent in session worktree** — Verify Task subagents dispatched from a session worktree do NOT trigger SessionStart hook double-enter
- [ ] **T17: QA scripts from worktree CWD** — Verify Tier 1 QA scripts resolve PLUGIN_ROOT correctly from inside `.claude/worktrees/<name>/`

## Assumptions (Verify During Implementation)

**A1: ExitWorktree survives compact — VERIFIED.** Tested 2026-03-14: EnterWorktree → compact → ExitWorktree(remove) succeeded. Tool-level session state survives compaction (process lifetime, not context window). The test used `action: "remove"` while the implementation uses `action: "keep"` — both require session recognition; `keep` is simpler, so if `remove` works, `keep` certainly works.

**A2: AGENTS.md overrides EnterWorktree tool description.** EnterWorktree's tool description says "ONLY when user explicitly asks." AGENTS.md is system-prompt level and should override individual tool descriptions. If the model refuses, the user can say "enter worktree" once per session (minimal friction). The AGENTS.md instruction is the primary mechanism; the hook reinforces it.

**A3: AGENTS.md/skill instructions override ExitWorktree tool description.** ExitWorktree's tool description says "Do NOT call this proactively — only when the user asks." Compact-prep Step 4.5 instructs the model to call `ExitWorktree(action: "keep")` programmatically. AGENTS.md now includes "When compact-prep or abandon instructs you to call ExitWorktree, comply." Same class as A2 — if the model refuses, the fallback `cd` path recovers CWD but loses cache refresh. Test alongside A2.

## Files Changed

| File | Change |
|------|--------|
| `.gitignore` | Add `.claude/worktrees/` (defense-in-depth — git worktrees have `.git` files preventing parent traversal, but explicit ignore is safer) |
| `plugins/compound-workflows/templates/session-worktree.sh` | **New** — Hook template (distributed with plugin, copied to user's `.claude/hooks/` by `/do:setup`) |
| `.claude/hooks/session-worktree.sh` | **Installed by `/do:setup`** — SessionStart hook script (copied from template) |
| `.claude/settings.json` | Add SessionStart hook registration (by `/do:setup` Step 7c merge) |
| `plugins/compound-workflows/scripts/session-merge.sh` | **New** — Merge + retry + cleanup script |
| `plugins/compound-workflows/skills/do-compact-prep/SKILL.md` | Add Step 4.5 (worktree merge), branch guard on compact-prep Step 6 |
| `AGENTS.md` | Add worktree isolation instructions |
| `compound-workflows.local.md` | Add `session_worktree` config key (via `/do:setup`) |
| `plugins/compound-workflows/skills/do-setup/SKILL.md` | Full portability: config key (8b+8d), hook install (7b), SessionStart registration (7c), gitignore (Step 6), AGENTS.md injection (8c) |
| `plugins/compound-workflows/skills/do-merge/SKILL.md` | **New** — Retry deferred worktree merge |
| `plugins/compound-workflows/skills/do-work/SKILL.md` | Phase 1.2: detect session worktree, skip own worktree creation |
| `plugins/compound-workflows/skills/recover/SKILL.md` | Add orphaned worktree detection and recovery flow |
| `plugins/compound-workflows/CHANGELOG.md` | Document new skill and feature (user-benefit lead) |
| `plugins/compound-workflows/README.md` | Update skill count 29 -> 30, add `/do:merge` to commands table |
| `plugins/compound-workflows/CLAUDE.md` | Add `do-merge/` to skills directory listing, `session-merge.sh` to scripts listing, `session_worktree` to config key inventory |
| `plugins/compound-workflows/.claude-plugin/plugin.json` | Version bump (3.1.7 -> 3.2.0 MINOR) |
| `.claude-plugin/marketplace.json` | Version bump (3.1.7 -> 3.2.0 MINOR) |

## Scope Boundaries

**In scope (v1):**
- SessionStart hook + AGENTS.md instruction for worktree entry
- Compact-prep merge step with conflict resolution
- Merge script with retry loop and cleanup
- Config toggle (`session_worktree`)
- Per-session verbal opt-out
- Orphaned worktree warnings
- Dirty main detection — refuse merge if main is dirty, preserve worktree branch
- `/do:work` session worktree awareness — skip nested worktree creation
- `/compound-workflows:recover` worktree recovery — detect orphans, offer merge/discard

**Deferred to follow-up:**
- `GIT_INDEX_FILE` wrapper as defense-in-depth for non-worktree contexts
- Stale base mitigation (periodic `git merge main` during long sessions)
- Merge commit message customization

**Cross-bead coordination:** Sequence s7qj before bead i9u3 (compact-prep rename) and coordinate with bead -7k6 (also adds SessionStart hook).

## Gap Resolutions

All gaps from specflow analysis resolved:

| Gap | Resolution |
|-----|-----------|
| G1 Hook output format | stderr with exit 2 — shown as feedback to model |
| G2 Model compliance | AGENTS.md instruction (system-prompt level) overrides tool description. Assumption A2. |
| G3 Post-compact disambiguation | If CWD is inside a worktree, suppress orphan warning for THAT worktree. Warn about others. |
| G4 ExitWorktree session scope | **VERIFIED** — A1 tested, ExitWorktree works post-compact. Fallback path retained but not needed. |
| G5 Retry exhaustion | Leave worktree unmerged, warn user with branch name, suggest manual merge. |
| G6 Conflict resolution UX | Show diff summary in conversation. AskUserQuestion: "Accept resolutions?" with option to review specific files or abort. |
| G7 Dirty main at merge | Merge script refuses to merge if main is dirty — could be another session's in-progress work. Warns user, preserves worktree branch. |
| G8 Crash recovery | **In v1.** SessionStart hook shows per-orphan details (branch, uncommitted count, unmerged commits) with inspect/merge/discard commands. `/compound-workflows:recover` updated to handle worktree recovery. Primary case: context exhaustion where compact-prep never ran. |
| G9 Mixed isolation | Acceptable — user opted out knowing the risk. Merge script's dirty-main refusal (G7) prevents auto-committing another session's work. |
| G10 Nested worktrees | `/do:work` detects it's in a session worktree and skips its own worktree creation. Works directly in the session worktree. No nesting. |
| G11 Merge step placement | Steps 1-4 in worktree → Step 4.5 (exit + merge + resolve + cleanup) → Steps 5-6 from main. |
| G12 Cleanup method | `git worktree remove` + `git branch -d`. Fallback `-D` inside script if needed. |
| G13 AGENTS.md "backup" | Clarified: AGENTS.md instruction serves as backup for the hook (redundant trigger), not a file backup. |
| G14 Push branch guard | `git branch --show-current` check before compact-prep Step 6 push. Must return default branch (detected at runtime, not hardcoded). |
| G15 Opt-out mechanism | Verbal per-session ("stay on main") + config toggle (`session_worktree: false`). |
| G16 .workflows/ state files | Committed as part of worktree commits, merge to main. Same as current behavior. |
| G17 Merge commit message | Accept default ("Merge branch 'worktree-X' into main"). |
| G18 Auto-approve | Merge script in `plugins/compound-workflows/scripts/`. Auto-approves via `bash <path>` rule. |
| G19 Branch deletion | `git branch -d` after --no-ff merge. Fallback `-D` inside script. |

## Red Team Resolution (Plan Phase)

Red team run with 3 providers (Opus, OpenAI, Gemini). Findings deduplicated and triaged:

| Finding | Provider(s) | Severity | Resolution |
|---------|-------------|----------|------------|
| EnterWorktree tool description contradicts automation | All 3 | CRITICAL | **Valid — strengthened.** AGENTS.md now says "BEFORE any other action." A2 remains blocking test. [red-team--opus, red-team--openai, red-team--gemini] |
| `.claude/worktrees/` not gitignored | Opus | CRITICAL | **Valid — fixed.** Added `.gitignore` entry to Files Changed. Defense-in-depth (git worktrees have `.git` files preventing parent traversal). [red-team--opus] |
| ExitWorktree session scoping ambiguous | Opus | CRITICAL | **Disagree.** Empirically tested 2026-03-14: EnterWorktree → compact → ExitWorktree succeeded. "Session" = process lifetime, verified. [red-team--opus] |
| CWD fallback via bash cd won't work | Gemini | CRITICAL | **Disagree (misread).** Fallback `cd` is a model-level Bash tool call (CWD persists), not inside a script. Clarified in plan. [red-team--gemini] |
| Hook not installed by /do:setup | Gemini | CRITICAL | **Valid — resolved.** Step 7 now includes full portability: template in `plugins/.../templates/`, setup copies hook, registers SessionStart, adds gitignore, injects AGENTS.md. [red-team--gemini] |
| Dirty main creates persistent unmerged branches | Opus, OpenAI | SERIOUS | **Disagree with severity.** `/do:merge` handles recovery. Not unrecoverable, just deferred until user commits Session A's work. [red-team--opus, red-team--openai] |
| Orphan false positive on active sessions | Opus | SERIOUS | **Valid — fixed.** Changed warning language from "orphaned" to "worktrees from other sessions (may be active or orphaned)." [red-team--opus] |
| Auto-resolve conflicts in prompt files | OpenAI | SERIOUS | **Disagree.** Plan already gates: additive markdown auto-merge + user review via AskUserQuestion before committing. [red-team--openai] |
| Branch name `main` hardcoded | OpenAI | SERIOUS | **Valid — resolved.** Step 4 now detects default branch at runtime via `git symbolic-ref refs/remotes/origin/HEAD` with `main` fallback. All references updated. [red-team--openai] |
| Stale base / logically incorrect merges | Opus | SERIOUS | **Disagree.** Inherent to all branching models. Git handles correctly. Acceptable for additive markdown. [red-team--opus] |
| EnterWorktree version/availability gating | OpenAI | SERIOUS | **Disagree.** Over-engineering for v1. Core Claude Code tools. [red-team--openai] |
| Full worktrees overengineered vs GIT_INDEX_FILE | Gemini | SERIOUS | **Disagree.** Problem is BOTH index AND working tree (1.3s same-file collision). GIT_INDEX_FILE only solves index. Resolved in brainstorm v3→v4. [red-team--gemini] |
| **Fixed (batch):** 4 MINOR findings acknowledged. [see .workflows/plan-research/worktree-session-isolation/red-team--opus.md, red-team--openai.md, red-team--gemini.md] | | | |

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-03-13-git-index-isolation-brainstorm.md` — 4 design iterations (lock → --only → GIT_INDEX_FILE → worktree), 4 red team rounds, empirical collision data (1.3s tightest), merge serialization test
- **Research:** `.workflows/plan-research/worktree-session-isolation/agents/repo-research.md` — 6 git callsites, compact-prep flow, hook patterns
- **Learnings:** `.workflows/plan-research/worktree-session-isolation/agents/learnings.md` — "eliminate sharing" precedent pattern
- **SpecFlow:** `.workflows/plan-research/worktree-session-isolation/agents/specflow.md` — 7 user flows, 19 gaps resolved
- **Red team:** `.workflows/plan-research/worktree-session-isolation/red-team--opus.md`, `red-team--openai.md`, `red-team--gemini.md` — 3-provider challenge, 4 findings accepted, 8 disagreed with reasoning
- **Deepen-plan (Run 1):** `.workflows/deepen-plan/fix-worktree-session-isolation/agents/run-1/` — 11 agents (4 research + 7 review), synthesis at `.workflows/deepen-plan/fix-worktree-session-isolation/run-1-synthesis.md`. Primary purpose: infrastructure integration gaps. 0 CRITICAL, 3 SERIOUS, 10 MINOR findings. Highest-consensus finding (6/11 agents): missing release housekeeping from Files Changed table.
- **Bead:** s7qj (bug), related: 8one (usage-pipe race — same class)
