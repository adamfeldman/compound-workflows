---
name: do:start
description: Manage session worktrees — resume, cleanup, rename, switch, create
argument-hint: "[cleanup|rename <name>|status]"
---

# Session Worktree Manager

Manage session worktrees interactively. Resume existing worktrees, clean up orphans,
rename the current session, or create new worktrees.

## Arguments

<subcommand> #$ARGUMENTS </subcommand>

**Argument parsing:**
- Empty or missing → **interactive mode** (default)
- `cleanup` → **cleanup subcommand** (skip to orphan cleanup)
- `rename <new-name>` → **rename subcommand** (rename current worktree)
- `status` → **status subcommand** (display-only, no action)
- Unrecognized subcommand → **interactive mode** (treat as no-arg)

---

## Shared: Worktree State Scanner

All modes begin by scanning worktree state from scratch. Do NOT rely on hook output —
state may have changed since the hook ran.

### Scanner Steps

1. **List session worktrees** (sorted by mtime, newest first):

```bash
ls -dt .worktrees/session-*
```

If no session worktrees exist, report "No session worktrees found." and exit (unless in
interactive mode, where "create new" is still offered).

2. **For each worktree**, gather state using separate Bash calls:

- **Mtime** (cross-platform): `stat -f '%m' <dir>` on macOS, `stat -c '%Y' <dir>` on Linux.
  If neither works, skip freshness for that worktree (treat as unknown age). Compute human-readable
  age from `(now - mtime)`.
- **PID liveness**: glob `.worktrees/.metadata/<name>/pid.*` files. Also check old-format
  `.worktrees/<name>/.session.pid` (backward compat). For each PID, run `kill -0 <pid>` to test
  liveness. Report: "alive" if ANY PID is alive, "dead" if all dead, "none" if no PID files.
- **Uncommitted tracked-file count**: `git -C <path> status --porcelain --untracked-files=no | wc -l`
- **Untracked file count**: `git -C <path> ls-files --others --exclude-standard | wc -l`
- **Unmerged commit count**: determine the default branch (`git symbolic-ref --short refs/remotes/origin/HEAD | sed 's|origin/||'`, fallback to `main`), get the worktree's branch (`git -C <path> rev-parse --abbrev-ref HEAD`), then `git log <default>..<branch> --oneline | wc -l`

3. **Build worktree table:**

```
| Worktree | Age | PID | Uncommitted | Untracked | Unmerged | Actions |
|----------|-----|-----|-------------|-----------|----------|---------|
```

Action column rules:
- PID alive → "resume" only (NOT "remove" — Decision 9 blocks it)
- PID dead + all counts zero → "remove, resume"
- PID dead + any count nonzero → "resume, cleanup" (dirty worktree)
- No PID files → same as PID dead (treat as unprotected)

---

## Interactive Mode (no arguments or unrecognized subcommand)

### Step 1: Scan

Run the Shared Worktree State Scanner above.

### Step 2: Present choices

If no session worktrees exist, skip to "create new" directly — generate a random 4-char hex
ID and create the worktree (see Step 3, "Create new").

If worktrees exist, present a single **AskUserQuestion** with:

1. **Issue warning** (if applicable): If any worktree has uncommitted changes, untracked files,
   or unmerged commits, display above the table:

   "N worktrees have unsaved work. Choose 'resume' to continue working, or 'cleanup' to review
   and resolve."

2. **Worktree table** (from scanner Step 3).

3. **Options:**
   - For each worktree, list its available actions (from the Actions column)
   - "create new" — create a fresh session worktree
   - "skip" — exit without action

Example prompt:

"Session worktrees found:

| Worktree | Age | PID | Uncommitted | Untracked | Unmerged | Actions |
|----------|-----|-----|-------------|-----------|----------|---------|
| session-a7f2 | 5m | alive | 3 | 1 | 2 | resume |
| session-x3k9 | 2d | dead | 0 | 0 | 0 | remove, resume |

Which worktree to use? (e.g., 'resume session-a7f2', 'remove session-x3k9', 'create new', 'skip')"

### Step 3: Execute user choice

**Resume:**
1. Capture Claude PID: `echo $PPID` in a separate Bash call.
2. If resuming a DIFFERENT worktree than the hook recommended (hook writes PID to
   the most-recent worktree), clean up the stale PID:
   `rm -f .worktrees/.metadata/<hook-recommended-name>/pid.<claude-pid>`
3. Write PID to chosen worktree:
   `bash ${CLAUDE_SKILL_DIR}/../../scripts/write-session-pid.sh <chosen-name> <claude-pid>`
4. Delete opt-out sentinel if present: `rm -f .worktrees/.opted-out`
5. `cd <absolute-path-to-worktree>`
6. Report: "Resumed session worktree `<name>`. Working directory: `<absolute-path>`"

**Remove:**
1. Capture Claude PID: `echo $PPID` in a separate Bash call.
2. Run Decision 9 via session-gc.sh in single-worktree mode:
   `bash ${CLAUDE_SKILL_DIR}/../../scripts/session-gc.sh <worktree-name> --caller-pid <claude-pid>`
3. Parse stdout:
   - `REMOVED <name>` → report success
   - `SKIPPED <name> <reason>` → explain why removal was blocked
   - `ERROR <name> <detail>` → report error
4. Return to Step 2 (re-scan and re-present if worktrees remain).

**Create new:**
1. Capture Claude PID: `echo $PPID` in a separate Bash call.
2. Clean up hook-written PID from previously recommended worktree (F10 fix):
   `rm -f .worktrees/.metadata/session-*/pid.<claude-pid>` (glob catches whichever worktree the hook chose).
3. Generate random 4-char hex ID: `openssl rand -hex 2`
4. `bd worktree create .worktrees/session-<id>`
5. If bd fails, retry once with a new random ID. If both fail, report error and exit.
6. Write PID: `bash ${CLAUDE_SKILL_DIR}/../../scripts/write-session-pid.sh session-<id> <claude-pid>`
7. Delete opt-out sentinel if present: `rm -f .worktrees/.opted-out`
8. `cd <absolute-path-to-new-worktree>`
9. Report: "Created session worktree `session-<id>`. Working directory: `<absolute-path>`"

**Skip:**
1. Capture Claude PID: `echo $PPID` in a separate Bash call.
2. Clean up hook-written PID if present — the hook pre-writes PID to the most-recent worktree.
   Remove it: `rm -f .worktrees/.metadata/session-*/pid.<claude-pid>` (glob catches whichever
   worktree the hook chose).
3. Report: "Skipped worktree selection. Working on current branch."

---

## Cleanup Subcommand (`/do:start cleanup`)

### Step 1: Scan and filter

Run the Shared Worktree State Scanner.

**Skip the worktree the user is currently inside.** Compare `pwd` output against each worktree's
absolute path. The current worktree is never a cleanup candidate — use `/do:compact-prep` to
merge the current session.

If no other session worktrees exist, report "No other session worktrees to clean up." and exit.

### Step 2: Run GC

Capture Claude PID: `echo $PPID` in a separate Bash call.

Run session-gc.sh on all eligible worktrees (passing captured PID for self-exclusion):

```bash
bash ${CLAUDE_SKILL_DIR}/../../scripts/session-gc.sh --caller-pid <claude-pid>
```

Parse each line of stdout:

- `REMOVED <name>` → count as removed
- `SKIPPED <name> untracked-files-present` → collect for user prompt (Step 3)
- `SKIPPED <name> <other-reason>` → count as retained with reason
- `ERROR <name> <detail>` → count as error

### Step 3: Handle untracked-files worktrees

For each worktree SKIPPED with "untracked-files-present":

**AskUserQuestion:** "Worktree `<name>` has untracked files. Delete anyway?"
- **Yes:** Re-run GC for that specific worktree with `--skip-untracked`:
  `bash ${CLAUDE_SKILL_DIR}/../../scripts/session-gc.sh <worktree-name> --caller-pid <claude-pid> --skip-untracked`
- **No:** Keep the worktree.

### Step 4: Report

"Cleanup complete. Removed N worktrees. M retained (reasons: ...)."

If all worktrees have active PIDs: "All worktrees have active sessions. Nothing to clean up."

---

## Rename Subcommand (`/do:start rename <new-name>`)

Parse `<new-name>` from the arguments (second word after `rename`).

If `<new-name>` is missing, use **AskUserQuestion**: "What should the new session name be?
(e.g., 'fix-login-bug', 'explore-caching')"

### Step 1: Guard — must be inside a session worktree

Check git plumbing (Decision 11):

```bash
git rev-parse --git-dir
git rev-parse --git-common-dir
```

If `git-dir == git-common-dir` → NOT in a worktree. Error: "Not inside a worktree.
`/do:start rename` must be run from inside a session worktree." Exit.

Also verify the worktree is a session worktree (path or branch contains `session-`).
If inside a work worktree or other type, error: "Inside a work worktree, not a session
worktree. `/do:start rename` only applies to session worktrees." Exit.

### Step 2: Guard — check for active `/do:work`

Check for sentinel files in `.workflows/.work-in-progress.d/`:

```bash
ls .workflows/.work-in-progress.d/
```

If sentinel files exist:
- Read `session_worktree_stale_minutes` from `compound-workflows.local.md` (default: 60).
- Check each sentinel's mtime. If ALL sentinels are older than the stale threshold, treat
  as stale from a crashed `/do:work`:
  "Stale /do:work sentinel found (<age> minutes old). No active /do:work detected.
  Cleaning up and proceeding with rename."
  Remove stale sentinels and proceed.
- If ANY sentinel is fresh (< stale threshold), block:
  "Work execution is in progress. Complete or abort /do:work before renaming.
  To abort: `rm .workflows/.work-in-progress.d/<id>` (verify no subagents are running first)."
  Exit.

### Step 3: Handle uncommitted and untracked files

Check untracked files:

```bash
git ls-files --others --exclude-standard
```

If untracked files exist, warn via output (not AskUserQuestion — just inform and offer):
"N untracked files found. These will be lost during rename unless staged."

Offer to stage: `git add <files>`

Commit all uncommitted changes (including any just-staged files):

Write checkpoint message to `.workflows/scratch/<session-id>-checkpoint-msg.txt` via the Write tool, then:
```bash
git add -u
git commit -F .workflows/scratch/<session-id>-checkpoint-msg.txt
```

Message: `session checkpoint before /do:start rename to <new-name>`

If nothing to commit (clean tree), skip the commit.

### Step 4: Rename branch

Extract the current branch name:

```bash
git rev-parse --abbrev-ref HEAD
```

Store as `<old-name>`. The new branch name is `session-<new-name>` (prefix `session-` if
the user didn't include it; if they did, use as-is).

```bash
git branch -m <old-name> session-<new-name>
```

### Step 5: Recreate worktree with new name

Capture Claude PID: `echo $PPID` in a separate Bash call.

**Critical ordering: write new PID FIRST, then delete old metadata.**
A crash between steps leaves stale metadata (minor leak), not data loss.

1. `cd` to main repo root (the parent of `.worktrees/`). Determine via
   `git worktree list --porcelain` (first line, strip `worktree ` prefix).

2. **Write new PID first** (crash-safe ordering):
   `bash <plugin-root>/scripts/write-session-pid.sh session-<new-name> <claude-pid>`
   (Use the absolute path to the script since CWD changed to main root.)

3. Delete old metadata: `rm -rf .worktrees/.metadata/<old-name>`

4. Remove old worktree: `bd worktree remove .worktrees/<old-name>`
   If `bd` unavailable, fall back: `git worktree remove .worktrees/<old-name>`

5. Create new worktree: `bd worktree create .worktrees/session-<new-name>`
   The branch was already renamed in Step 4, so bd will use the existing branch.

6. **If `bd worktree create` fails:** Emit recovery instructions:
   "Worktree recreation failed. Your work is safe on branch `session-<new-name>`.
   Recover with: `bd worktree create .worktrees/session-<new-name>`
   Or: `git worktree add .worktrees/session-<new-name> session-<new-name>`"
   Exit.

7. `cd` into new worktree: `cd <main-root>/.worktrees/session-<new-name>`

8. Report: "Renamed session worktree from `<old-name>` to `session-<new-name>`.
   Working directory: `<absolute-path>`"

---

## Status Subcommand (`/do:start status`)

### Step 1: Scan

Run the Shared Worktree State Scanner.

### Step 2: Display

Present the worktree table (same format as interactive mode Step 2).

**No AskUserQuestion** — display only, no action taken.

If no session worktrees exist, report: "No session worktrees found."
