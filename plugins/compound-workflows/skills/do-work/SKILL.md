---
name: do:work
description: Execute work plans using subagent dispatch
argument-hint: "[plan file, specification, or todo file path]"
---

# Work Plan Execution — Subagent Architecture

Execute a work plan by dispatching each step to an independent subagent. The orchestrator never reads source files or writes code directly — this prevents context exhaustion during long plans.

## Input Document

<input_document> #$ARGUMENTS </input_document>

## Phase 1: Setup (Orchestrator)

### Task Tracking Detection

Detect the available task tracking system:

```bash
if bd version 2>/dev/null; then
  echo "TRACKER=beads"
else
  echo "TRACKER=todowrite"
fi
```

**If beads (`bd`) is available:** Use beads for all task tracking. Progress survives context compaction. Follow the beads paths below.

**If beads is NOT available (TodoWrite mode):** Use TodoWrite for task tracking. Same phase structure, but with these differences:
- **No worktrees** — work on a feature branch directly (Phase 1.2 is skipped)
- **No dependencies** — steps execute in plan order, not priority order
- **No `bd ready`** — iterate through TodoWrite tasks sequentially
- **Recovery is manual** — after compaction, re-read the plan file and check git log to infer progress

Each phase below includes a "**TodoWrite mode:**" block where the paths diverge.

### 1.1 Read and Clarify the Plan

- Read the plan document completely
- Review references and links
- If the plan has an `origin:` field in frontmatter, note it for beads issue descriptions and subagent context
- **Check for unresolved items:** If the plan has an Open Questions section with deferred items, surface each to the user via **AskUserQuestion** before proceeding: "Plan has N deferred items. Resolve before implementation, or accept the risk?"
- If anything is unclear, ask clarifying questions now

**Plan structure check:** After reading the plan, assess whether the steps need adjustment for subagent dispatch:
- **Single-file plans** (all steps write to one file): Steps must be fully sequential. No parallel dispatch. This is fine — subagent overhead per step is minor compared to the risk of context exhaustion in a single session.
- **Large steps** (20+ checkboxes, heavy inline specs): Consider splitting into smaller beads issues during Phase 1.3. A subagent that runs out of context mid-step loses all progress for that step.
- **Heavy shared reference data** (tables, schemas that every step needs): Extract the reference data path into each beads issue description so subagents can read it from disk rather than receiving it inline.

Flag any concerns to the user before proceeding.

- Use **AskUserQuestion** to get user approval to proceed
- **Do not skip this** — the orchestrator must understand the plan before dispatching work

### 1.1.1 Stats Capture Setup

Initialize per-dispatch stats collection. This runs once at command start; all dispatches in this run share the same identifiers.

Derive `STEM` from the plan filename by stripping the date prefix and `-plan.md` suffix (e.g., `docs/plans/2026-03-10-feat-per-agent-token-instrumentation-plan.md` becomes `feat-per-agent-token-instrumentation`). If no plan file is provided (ad-hoc work), omit the stem — the script will auto-detect from the current branch name.

```bash
bash ${CLAUDE_SKILL_DIR}/../../scripts/init-values.sh work <stem>
```

If no stem is known yet (ad-hoc work, no plan file), run without stem:

```bash
bash ${CLAUDE_SKILL_DIR}/../../scripts/init-values.sh work
```

Read the output. Track the values PLUGIN_ROOT, MAIN_ROOT, WORKFLOWS_ROOT, RUN_ID, DATE, STEM, STATS_FILE, WORKTREE_MGR, CACHED_MODEL (and NOTE if emitted) for use in subsequent steps. If init-values.sh fails or any value is empty, warn the user and stop.

**All `.workflows/` paths in this skill use `$WORKFLOWS_ROOT` (the main repo root's `.workflows/` directory), NOT relative `.workflows/`.** Exception: `.workflows/.work-in-progress.d/` remains relative (per-worktree) — see Phase 1.2.1.

**Config check:** Read `compound-workflows.local.md` and check the `stats_capture` key. If the value is `false`, skip all stats capture for this run (do not read the schema file, do not call `capture-stats.sh`). If the key is missing or any other value, proceed with stats capture.

**Stats file path:** Use the STATS_FILE value from init-values.sh output.

**Model resolution:** For each dispatch, resolve the `model` field using `CACHED_MODEL`. The `general-purpose` agent uses `model: inherit`, so use `CACHED_MODEL` as its model value. If a dispatch uses an explicit model override, use that instead. See `$PLUGIN_ROOT/resources/stats-capture-schema.md` for the full 4-step model resolution algorithm.

### 1.2 Setup Worktree

**NEVER call `git worktree add` directly.** Always use `bd worktree` or the `worktree-manager.sh` script. Raw `git worktree add` creates worktrees in the wrong location and requires manual `.gitignore` entries.

#### Session Worktree Detection

Before any worktree creation, check if the current working directory is already inside a session worktree (created by the SessionStart hook via `bd worktree create`). Session worktrees live in `.worktrees/` with a `session-` prefix, distinguishing them from `/do:work` worktrees in the same directory.

```bash
git worktree list --porcelain
```

Parse the output: find the worktree entry whose path matches the current working directory. If that path contains `.worktrees/session-`, this is a session worktree.

**Why `git worktree list --porcelain` not `pwd`:** `pwd` is not in the auto-approve hook's `is_safe_prefix()` list and would trigger a permission prompt on every `/do:work` invocation inside a session worktree. `git worktree list --porcelain` auto-approves via the `git` first-token rule and provides the same information.

**Why not `bd worktree info`:** `bd worktree info` detects bd-managed worktrees but doesn't distinguish session worktrees from `/do:work` worktrees. The `session-` prefix in the worktree path is the distinguishing signal — path-based detection with prefix matching is correct.

**If CWD is inside a session worktree (`.worktrees/session-*`):** trigger the session-to-work transition (see below). Set `IN_SESSION_WORKTREE=true` (tracked in orchestrator context for Phase 2.2 safe-commit.sh decision).

**If CWD is NOT inside a session worktree**, skip the transition and proceed to Normal Worktree Detection below.

#### Session-to-Work Transition

When `/do:work` launches inside a session worktree, it transitions the session work to the default branch and creates a dedicated work worktree. This separates the session lifecycle (ephemeral, user-driven) from the work lifecycle (plan-driven, subagent-dispatched). If any transition step fails, the safe fallback is to work inside the session worktree directly.

**Step 1.2-A — Check uncommitted and untracked files:**

Check for uncommitted tracked changes and untracked files before attempting the merge transition. This is a data-safety gate — AskUserQuestion is intentional here (user-decided, overrides "automate, don't ask" for data-safety reasons).

Check tracked changes:
```bash
git status --porcelain --untracked-files=no
```

Check untracked files:
```bash
git ls-files --others --exclude-standard
```

- **If tracked changes exist:** Use **AskUserQuestion** — "Session worktree has N uncommitted changes. Commit with checkpoint message, or discard?"
  - Commit: Write message to `.workflows/scratch/<session-id>-checkpoint-msg.txt` via the Write tool, then `git add -u && git commit -F .workflows/scratch/<session-id>-checkpoint-msg.txt` (message: "session checkpoint before /do:work transition")
  - Discard: `git checkout -- .`
- **If untracked files exist:** Use **AskUserQuestion** — "Session worktree has N untracked files (list first 5). Stage them before transition? They will be lost otherwise."
  - Stage: Write message to `.workflows/scratch/<session-id>-checkpoint-msg.txt` via the Write tool, then `git add <files> && git commit -F .workflows/scratch/<session-id>-checkpoint-msg.txt` (message: "session checkpoint: stage untracked files before /do:work transition")
  - Skip: proceed (user accepts loss)

**Step 1.2-B — PID liveness check via session-gc.sh (CQ2 fix):**

Verify no other session is using this worktree before merging it away.

Capture the Claude PID:
```bash
echo $PPID
```

Read the output as `CLAUDE_PID`. Then run session-gc.sh in single-worktree **dry-run** mode (liveness probe only — does NOT delete):

```bash
bash ${CLAUDE_SKILL_DIR}/../../scripts/session-gc.sh <worktree-name> --caller-pid <CLAUDE_PID> --dry-run
```

Parse the output line for this worktree:
- **`REMOVABLE <name>`:** No other sessions active, worktree is safe to transition. Proceed to Step 1.2-C.
- **`SKIPPED <name> another-session-active:PID=<val>`:** Another session is active. **Block** with message: "Another session (PID <val>) is using this worktree. Cannot transition to work worktree. Working inside session worktree instead." Set `IN_SESSION_WORKTREE=true`, skip remaining transition steps, continue to Phase 1.2.1 (Create QA Hook Sentinel).
- **`SKIPPED <name> gc-lock-busy`:** Another GC is running. Retry once after 2 seconds. If still busy, fall back to working inside session worktree.

**PID mismatch handling:** If own PID (`pid.<CLAUDE_PID>`) does not exist in `.worktrees/.metadata/<worktree-name>/`:
- Warn: "PID mismatch — session PID not found in metadata. This may indicate $PPID inconsistency. Proceeding with full liveness checks (safe). If ALL PIDs are dead, transition will continue."
- Pass `--caller-pid 0 --dry-run` to session-gc.sh (no self-exclusion — all PIDs are checked for liveness).
- If session-gc.sh reports live PIDs: check if those PIDs are Claude processes:
  ```bash
  ps -p <PID> -o args=
  ```
  If `args` output contains `claude` (case-insensitive): **block** — genuine concurrent session.
  If none are Claude processes: Use **AskUserQuestion** — "PID check found live processes but none are Claude sessions. These are likely recycled PIDs. Force transition? (stale PID files will be cleaned.)"
  - If user confirms: prune all PID files in `.worktrees/.metadata/<worktree-name>/` and re-run session-gc.sh.
  - If user declines: **block**, fall back to working inside session worktree.
- If all PIDs dead: proceed to Step 1.2-C.

**If no other live PIDs (normal path):** proceed to Step 1.2-C.

**Step 1.2-C — Merge session worktree to default branch:**

Navigate to the main repo root and merge the session branch.

Extract the main repo root path:
```bash
git worktree list --porcelain
```

Read the first `worktree` line as the main repo root path. Then `cd` into it.

Extract the session branch name:
```bash
git branch --show-current
```

Read the output as `SESSION_BRANCH`. Then run the merge:

```bash
CALLER_PID=<CLAUDE_PID> bash ${CLAUDE_SKILL_DIR}/../../scripts/session-merge.sh <SESSION_BRANCH>
```

Handle ALL exit codes:

- **Exit 0 (success):** Continue to Step 1.2-D.
- **Exit 2 (conflict):** Create work worktree from default branch directly, leave session worktree as-is. Warn: "Session worktree <session-name> has merge conflicts with the default branch. Work worktree created from default branch. Resolve <session-name> separately via `/do:start`." Skip to Step 1.2-E (create work worktree from default branch, not from session).
- **Exit 3 (retry exhaustion):** Fall back to working inside session worktree. Warn: "session-merge.sh exhausted retries (index.lock contention). Working inside session worktree." Set `IN_SESSION_WORKTREE=true`, continue to Phase 1.2.1.
- **Exit 4 (dirty main):** Fall back to working inside session worktree. Warn: "Default branch has uncommitted changes. Working inside session worktree." Set `IN_SESSION_WORKTREE=true`, continue to Phase 1.2.1.
- **Exit 5 (file overlap):** Fall back to working inside session worktree. Warn: "File overlap detected between session and default branch. Working inside session worktree." Set `IN_SESSION_WORKTREE=true`, continue to Phase 1.2.1.
- **Exit 1 (other error):** Fall back to working inside session worktree. Warn with the error output. Set `IN_SESSION_WORKTREE=true`, continue to Phase 1.2.1.

**Step 1.2-D — Remove session worktree (defensive):**

session-merge.sh (Step 2 in the plan) is the primary owner of worktree removal and metadata cleanup on exit 0. This step is purely defensive — it catches cases where session-merge.sh's cleanup was incomplete.

Check if the worktree still exists:
```bash
ls -d .worktrees/<session-name>
```

If the worktree still exists: `bd worktree remove .worktrees/<session-name>` (NO `--force`). If removal fails: warn and continue — do not block work.

If the worktree was already removed by session-merge.sh: no-op.

Check if metadata still exists:
```bash
ls -d .worktrees/.metadata/<session-name>
```

If metadata exists: `rm -rf .worktrees/.metadata/<session-name>`. If already removed: no-op.

Continue to Step 1.2-E.

**Step 1.2-E — Create work worktree:**

Create a dedicated work worktree for subagent dispatch:

```bash
bd worktree create .worktrees/work-<task-name>
cd .worktrees/work-<task-name>
```

Create the QA hook sentinel in the work worktree (fresh worktree has no `.workflows/`):
```bash
mkdir -p .workflows/.work-in-progress.d
```
Then create the `$RUN_ID` sentinel file:
```bash
date +%s > .workflows/.work-in-progress.d/$RUN_ID
```

Set `IN_BD_WORKTREE=true`. Continue to Phase 1.3 (skip Phase 1.2.1 — sentinel already created above).

**Worktree state summary (for safe-commit.sh decision in Phase 2.2):**
- `IN_SESSION_WORKTREE=true` → set when transition failed and working inside `.worktrees/session-*`
- `IN_BD_WORKTREE=true` → set when transition succeeded and working in `.worktrees/work-*`, OR already in `.worktrees/` non-session, OR after `bd worktree create` in normal path
- Both unset → not in any worktree (opt-out or TodoWrite mode) → use safe-commit.sh

#### Normal Worktree Detection

**If CWD was inside a session worktree**, the transition flow above already handled worktree setup. Do NOT enter this section — the transition either created a work worktree (Step 1.2-E) or fell back to working in the session worktree. In either case, proceed to Phase 1.2.1 or Phase 1.3 as directed above.

Check current branch and worktree state. The STEM value from init-values.sh output contains the auto-detected branch name (slugified). For branch display, run `git branch --show-current` as a separate command:

```bash
git branch --show-current
```

Read the output as the current branch name. Then check worktree/tool state:

```bash
# Detect worktree tool availability
command -v bd >/dev/null 2>&1 && echo "BD=available" || echo "BD=not_available"
bd worktree info 2>/dev/null
```

**If already in a bd-managed worktree (`.worktrees/`):** Continue working there. No setup needed. Set `IN_BD_WORKTREE=true`.

**If already on a feature branch** (not the default branch):
- **AskUserQuestion:** "Continue working on `[current_branch]`, or create a worktree for isolated development?"

**If on the default branch**, create a worktree (default) or opt out:
- **Default:** Create a worktree — provides isolated development. Then `cd` into the worktree path. Set `IN_BD_WORKTREE=true`.
- **Opt-out:** Work directly on a feature branch (`git checkout -b feat/...`) — only if user explicitly prefers this. Set `IN_ANY_WORKTREE=false`.

```bash
# Primary: bd worktree (beads handles db redirect automatically)
# IMPORTANT: pass .worktrees/<name> — bd uses the path as-is, defaults to repo root otherwise
bd worktree create .worktrees/<descriptive-name>
cd .worktrees/<descriptive-name>

# Fallback (if bd not available): use the WORKTREE_MGR value from init-values.sh output
bash "<WORKTREE_MGR>" create <descriptive-name>
cd .worktrees/<descriptive-name>
```

**Why worktrees are the default for subagent execution:** Subagents write code autonomously. If something goes wrong, you can nuke the worktree without touching your main working tree. No `git reset --hard`, no orphaned files.

**TodoWrite mode:** Skip worktree setup. Create a feature branch instead:
```bash
git checkout -b feat/<descriptive-name>
```

### 1.2.1 Create QA Hook Sentinel

Suppress the PostToolUse QA hook during `/do:work` execution. Without this, every subagent commit triggers Tier 1 QA scripts — adding overhead and stderr noise per commit.

```bash
mkdir -p .workflows/.work-in-progress.d
date +%s > .workflows/.work-in-progress.d/$RUN_ID
```

This sentinel directory is checked by `.claude/hooks/plugin-qa-check.sh`. Each session creates its own sentinel file using `$RUN_ID`. It is cleared via `rm -f` in Phase 4 (Ship) and cleaned up if stale in Phase 2.4 (Recovery). The hook iterates all files in the directory — QA is suppressed if ANY file has a recent timestamp.

### 1.3 Create or Resume Task Issues

**Check for existing issues first:**

```bash
bd list --status=open
bd list --status=in_progress
```

If issues already exist for this plan, this is a **resumed session**. Skip to Phase 2.

**If no existing issues**, decompose the plan into beads issues:

- One issue per implementation step/phase (5-10 issues typical)
- Each issue should be one coherent unit of work completable in a single subagent dispatch
- Set up dependencies with `bd dep add` where tasks are sequential
- **Critical:** Each issue description MUST be self-contained enough for a subagent to execute independently. Include:
  - What to build/change
  - Which files to read for context/patterns
  - What tests to write or run
  - The plan file path for reference

**Origin metadata (mandatory):** Every `bd create` call MUST include `--metadata '{"origin": "work", "plan": "<plan-file>"}'` where `<plan-file>` is the full plan file path from the skill arguments. This makes work steps structurally distinguishable from beads for analytics. The `Plan:` description prefix is kept for human readability; the metadata serves machine queryability. Both coexist.

**Example:**

```bash
bd create --title="Set up project structure" --type=task --priority=1 \
  --metadata '{"origin": "work", "plan": "docs/plans/YYYY-MM-DD-feat-example-plan.md"}' \
  --description="Plan: docs/plans/YYYY-MM-DD-feat-example-plan.md
Origin: docs/brainstorms/YYYY-MM-DD-example-brainstorm.md

Tasks:
- Create src/components/ directory structure
- Add base configuration files
- Reference: src/existing-component/ for conventions

Test: Run existing test suite to verify no regressions.
Commit when done with: feat(scaffold): set up project structure"

bd create --title="Implement core logic" --type=task --priority=2 \
  --metadata '{"origin": "work", "plan": "docs/plans/YYYY-MM-DD-feat-example-plan.md"}' \
  --description="Plan: docs/plans/YYYY-MM-DD-feat-example-plan.md

Tasks:
- Implement the FooService class following pattern in src/services/bar_service.rb
- Add unit tests in test/services/foo_service_test.rb
- Handle edge cases: empty input, nil values

Test: ruby -Itest test/services/foo_service_test.rb
Commit when done with: feat(foo): implement core logic"

# Phase 1 depends on Phase 0
bd dep add <phase-1-id> <phase-0-id>
```

**TodoWrite mode:** Instead of `bd create` and `bd dep add`, use TodoWrite to create a task list from the plan steps. One task per implementation step. Include the same self-contained description content (what to build, which files to read, what tests to run, plan file path). Tasks will be executed in list order since TodoWrite has no dependency tracking.

**Granularity guidance:**
- Too coarse (1-2 issues): subagents get overwhelmed, lose focus
- Too granular (20+ issues): orchestrator overhead dominates
- Sweet spot: 5-10 issues, each a coherent unit of work

## Phase 2: Execute (Dispatch Loop)

This is the core loop. The orchestrator dispatches one subagent per ready issue.

### 2.1 The Dispatch Loop

```
while bd ready shows issues:

  1. Pick next ready issue (lowest priority number first)
  2. Read its full description: bd show <id>
  3. Claim it: bd update <id> --status=in_progress
  4. Build the subagent prompt (see 2.2)
  5. Dispatch subagent via Task tool (foreground, NOT background)
  6. Review the subagent's summary
  7. If successful: bd close <id>, check off plan item
  8. If failed: assess, fix issue description, re-dispatch or handle manually
  9. Loop
```

**Foreground by default:** When steps have dependencies or touch shared files, run them sequentially (foreground) so each subagent sees the prior subagent's committed code.

**Parallel dispatch:** If `bd ready` shows multiple issues with NO dependency between them AND they touch completely separate files, dispatch them in parallel using `run_in_background: true`. Parallel is equally safe in this case and significantly faster. When steps share files or have dependencies, run sequentially.

**TodoWrite mode dispatch loop:**
```
for each pending TodoWrite task (in list order):

  1. Read the task description
  2. Mark it in_progress
  3. Build the subagent prompt (see 2.2)
  4. Dispatch subagent via Task tool (foreground)
  5. Review the subagent's summary
  6. If successful: mark completed, check off plan item
  7. If failed: assess, update task description, re-dispatch
  8. Next task
```

### 2.2 Building the Subagent Prompt

Each subagent gets a self-contained prompt. The orchestrator constructs it from the bd issue description plus standard context.

**Template:**

```
You are executing one step of a larger work plan. Your job is to implement ONLY the tasks described below, commit your work, and return a summary.

## Your Task

[Paste the bd issue description (or TodoWrite task description) here — title + full description]

## Context

- **Plan file:** [path] — Read this for overall context but only implement YOUR step
- **Origin brainstorm:** [path from plan's origin: field, or "none"] — Reference for why decisions were made
- **Working directory:** [cwd] (this may be a worktree — that's normal, treat it as the repo root)
- **Current branch:** [branch name]
- **Prior steps completed:** [list recent git log --oneline -5, or bd list --status=closed summary, or TodoWrite completed tasks]

## Instructions

1. Read the plan file for context (skim — don't load the whole thing into your working memory if it's long)
2. Read CLAUDE.md and AGENTS.md for project conventions
3. Read the specific files mentioned in your task description
4. Look for existing patterns to follow (grep/glob for similar code)
5. Implement the tasks described above
6. Write tests if specified in the task
7. Before finalizing, run the **System-Wide Impact Check**:
   - What does this trigger downstream? (callbacks, observers, dependent systems)
   - Am I testing against reality? (integration test with real objects, not just mocks)
   - Can partial failure leave a mess? (orphaned state, duplicated records)
   - What else exposes this? (related classes, alt entry points, parity needed)
   - Are strategies consistent across layers? (error handling, retry alignment)
   Skip if trivial (leaf-node change, no callbacks, no state persistence).
8. Run tests to verify your changes work
9. Stage and commit your changes: only stage files you directly created or edited — do NOT stage regenerated outputs, build artifacts, or files modified as a side effect of running scripts. Use the commit message suggested in the task description (or write an appropriate conventional commit message). Use the **Write tool** to write the message to `$WORKFLOWS_ROOT/scratch/commit-msg-<TASK_ID>.txt`, then run `git commit -F $WORKFLOWS_ROOT/scratch/commit-msg-<TASK_ID>.txt`.
10. Do NOT push to remote — the orchestrator handles that
11. Do NOT create PRs
12. Do NOT modify beads issues (bd commands) — the orchestrator handles that

## Output

Return a summary with:
- What you implemented (1-3 bullet points)
- Files created or modified
- Test results (pass/fail, which tests)
- Any issues encountered or concerns for subsequent steps
- If you could NOT complete the task, explain what blocked you
```

**safe-commit.sh integration (non-worktree mode):**

If the orchestrator detected that it is NOT in any worktree (neither session worktree nor bd-managed worktree — i.e., `IN_SESSION_WORKTREE` and `IN_BD_WORKTREE` are both false/unset), append this instruction to the subagent prompt template's Instructions section:

> Use `bash ${PLUGIN_ROOT}/scripts/safe-commit.sh` instead of raw `git commit` for all commits. Pass the same arguments: `bash ${PLUGIN_ROOT}/scripts/safe-commit.sh -F <msg-file> <files...>`

The `${PLUGIN_ROOT}` path is resolved at dispatch time by the orchestrator (already available from init-values.sh). The blanket instruction ("for all commits") is intentionally non-enumerative: the template is LLM-interpreted, so the model follows the instruction across all commit operations without needing a callsite list.

When in a worktree (session or bd-managed), do NOT add this instruction — worktrees already provide index isolation, so `safe-commit.sh` is unnecessary.

**Dispatch with:**

```
Task general-purpose (foreground): "[constructed prompt above]" <!-- context-lean-exempt: work subagents commit code, return inline summary -->
```

### Stats Capture
If stats_capture ≠ false in compound-workflows.local.md: after each Task completion, extract `total_tokens`, `tool_uses`, and `duration_ms` values from the `<usage>` notification and pass as arg 9: `bash $PLUGIN_ROOT/scripts/capture-stats.sh "$STATS_FILE" work general-purpose "<step>" "<model>" "$STEM" "<bead>" "$RUN_ID" "total_tokens: N, tool_uses: N, duration_ms: N"`. If `<usage>` is absent, pass `"null"` as arg 9. Use the bead issue number (or sequential loop counter) as `<step>`. Use the bead ID as `<bead>` (null if no bead). See `$PLUGIN_ROOT/resources/stats-capture-schema.md` for field derivation rules.

### 2.3 Handling Subagent Results

After each subagent returns:

**Success path:**
1. Verify the subagent committed (check `git log --oneline -3`)
2. Close the issue: `bd close <id>`
3. Update the plan file: change `- [ ]` to `- [x]` for completed items
4. Continue to next issue

**TodoWrite mode success:** Mark the TodoWrite task as completed, check off plan items, continue to next task.

**Failure path:**
If the subagent reports it couldn't complete the task:
1. Read the subagent's explanation
2. Check what was partially done (`git status`, `git diff`)
3. Decide:
   - **Fixable context issue:** Update the bd issue description with more detail, re-dispatch
   - **Dependency problem:** Create a new blocking issue, update deps
   - **Needs human input:** Use **AskUserQuestion** to get guidance
   - **Small remaining work:** Handle it in-orchestrator (exception to the "never code" rule — only for trivial fixes like import statements or typos)

**TodoWrite mode failure:** Update the TodoWrite task description with more detail and re-dispatch. For dependency problems, add a new TodoWrite task before the current one.

### 2.4 Recovery After Compaction

If context compacts mid-execution, recovery is simple:

1. Re-orient — check worktree and beads state:
   ```bash
   bd worktree info 2>/dev/null || git worktree list  # Are we in a worktree? Which one?
   bd list --status=in_progress   # What was being worked on
   bd ready                        # What's available next
   bd list --status=closed | tail -5  # What was recently completed
   ```
2. If worktree info shows you should be in a worktree but you're not, `cd` into it
3. Check for stale sentinel files and clean up if needed:
   ```bash
   bash ${CLAUDE_SKILL_DIR}/../../scripts/check-sentinel.sh .workflows/.work-in-progress.d
   ```
   Read the output. If output is `STALE:<N>`, there are stale sentinel files — **IMMEDIATELY** remove them using `find .workflows/.work-in-progress.d -type f -mmin +240 -delete` before proceeding to Phase 3. Do not continue with stale sentinels active. If `ACTIVE`, proceed normally. If `NOT_FOUND`, the sentinel directory is empty or does not exist — skip.
4. Check git log for recent commits:
   ```bash
   git log --oneline -10
   ```
5. Read the plan file to re-orient
6. Resume the dispatch loop from step 2.1

**This is the whole point of the architecture.** No in-memory state to lose. bd + git + worktree info + plan file = complete recovery.

**TodoWrite mode recovery:** After compaction, TodoWrite state is lost. Recover manually:
1. Read the plan file — check which items are checked off (`[x]`)
2. Check git log for recent commits — infer which steps completed
3. Rebuild a TodoWrite task list for remaining unchecked items
4. Resume dispatching from the first incomplete task

### 2.5 Post-Dispatch Stats Validation

After the dispatch loop completes (all issues closed or all TodoWrite tasks completed), if stats capture is enabled, validate that the stats file contains the expected number of entries:

```bash
bash $PLUGIN_ROOT/scripts/validate-stats.sh "$STATS_FILE" <DISPATCH_COUNT>
```

Track `DISPATCH_COUNT` by incrementing a counter after each successful `capture-stats.sh` call during the dispatch loop. If validate-stats.sh reports a mismatch, warn with the names of missing agents — do not fail the command. This is a diagnostic warning only.

## Phase 3: Quality Check (Orchestrator)

After all issues are closed (or all TodoWrite tasks completed):

1. **Verify completeness:**
   ```bash
   bd list --status=open    # Should be empty for this plan
   git log --oneline -20    # Review all commits from this session
   ```
   **TodoWrite mode:** Check that all TodoWrite tasks are marked completed. Verify plan file has all items checked off (`[x]`). Review git log for commits.

2. **Run quality gates** (if the project has them):
   ```bash
   # Run full test suite — use project's test command
   # Run linting — per CLAUDE.md
   ```

3. **Optional: Dispatch reviewer subagent** for complex changes:
   ```
   mkdir -p $WORKFLOWS_ROOT/work-review/<RUN_ID>/

   Task code-simplicity-reviewer (run_in_background: true): "You are a code simplicity reviewer. Check for unnecessary complexity, YAGNI violations, and over-engineering.

   Review all changes on the current branch vs the base branch.
   Run: git diff [base-branch]...HEAD

   === OUTPUT INSTRUCTIONS (MANDATORY) ===
   Write your COMPLETE findings to: $WORKFLOWS_ROOT/work-review/<RUN_ID>/code-simplicity.md
   After writing the file, return ONLY a 2-3 sentence summary.
   "
   ```

   Read review output files. Address critical issues only.

   **Stats capture (reviewer):** If stats capture is enabled and the reviewer was dispatched, extract `total_tokens`, `tool_uses`, and `duration_ms` values from the `<usage>` notification and pass as arg 9: `bash $PLUGIN_ROOT/scripts/capture-stats.sh "$STATS_FILE" work code-simplicity-reviewer "reviewer" "<model>" "$STEM" "<bead>" "$RUN_ID" "total_tokens: N, tool_uses: N, duration_ms: N"`. If `<usage>` is absent, pass `"null"` as arg 9. Use `"reviewer"` as the step value. Include this entry in the post-dispatch validation count.

## Phase 4: Ship (Orchestrator)

1. **Final commit** (if quality fixes were needed):
   ```bash
   git add <files>
   ```
   Use the **Write tool** to write the commit message to `$WORKFLOWS_ROOT/scratch/commit-msg-<RUN_ID>.txt` (use the tracked RUN_ID value). Then run:
   ```bash
   git commit -F $WORKFLOWS_ROOT/scratch/commit-msg-<RUN_ID>.txt
   ```

2. **Clear QA hook sentinel** (re-enable PostToolUse QA enforcement):

   Clear the QA hook sentinel: `rm -f .workflows/.work-in-progress.d/$RUN_ID`

3. **Create PR** (if project uses PRs):
   ```bash
   git push -u origin [branch-name]
   ```
   Use the **Write tool** to write the PR body to `$WORKFLOWS_ROOT/scratch/pr-body-<RUN_ID>.txt` (use the tracked RUN_ID value). Include Summary, Testing, and Implementation Notes sections. Then run:
   ```bash
   gh pr create --title "[Description]" --body-file $WORKFLOWS_ROOT/scratch/pr-body-<RUN_ID>.txt
   ```

   > **Post-merge reminder:** After the PR is merged, run `/compound-workflows:version` or `/do:compact-prep` to check for missing GitHub releases. Do not create releases automatically — the user decides when to cut a release.

4. **Update plan status** (if YAML frontmatter has `status` field):
   ```
   status: active  →  status: completed
   ```

5. **Clean up worktree** (if applicable):

   If working in a worktree, return to the main repo and offer cleanup:

   Return to main repo. Run `git worktree list --porcelain | head -1 | sed 's/worktree //'` and read the output as the main repo path. Then run `cd <path>`.

   ```bash
   # Remove the worktree
   bd worktree remove .worktrees/<worktree-name>
   # Fallback (if bd not available): use the WORKTREE_MGR value from init-values.sh output
   bash "<WORKTREE_MGR>" remove <worktree-name>
   ```

   Only remove after PR is created and pushed. If the user wants to keep the worktree (e.g., awaiting review feedback), skip this step.

   **TodoWrite mode:** No worktree to clean up. Skip this step.

6. **Notify user** with summary:
   - Steps completed (N/N issues closed, or N/N tasks completed in TodoWrite mode)
   - PR link
   - Any follow-up work (unclosed issues or remaining tasks)

7. **Compound Check**

   Before closing out, assess whether this session produced compound-worthy knowledge:
   - Did you solve a non-obvious problem? (debugging insight, unexpected root cause, workaround for a tool/framework limitation)
   - Did you discover something surprising about the codebase, data, or domain?
   - Did you make a strategic or architectural decision with rationale worth preserving?
   - Did research surface reusable findings? (cost analysis, competitive intelligence, technical evaluation)

   If yes to any: "This session produced knowledge worth compounding. Run `/do:compound` to capture it before context is lost."

   If no: skip silently.

## Key Principles

1. **Orchestrator never codes.** It reads the plan, manages bd, dispatches subagents, and ships. The only exception is trivial post-review fixes (< 5 lines).

2. **Each subagent is disposable.** It gets a self-contained prompt, does its work, commits, and returns a summary. No shared state between subagents except the git repo.

3. **Persistent state is the source of truth.** With beads: `bd ready` tells you exactly where to resume after compaction. With TodoWrite: the plan file's checkboxes + git log are your recovery path. Never rely on conversation history or in-memory state.

4. **No unresolved items cross phase boundaries.** Every open question, concern, or finding must be explicitly resolved, deferred with rationale, or removed before moving to the next phase.

5. **Parallel when safe, sequential when shared.** If steps touch completely separate files with no dependencies, parallel dispatch is equally safe and faster. Use sequential only when steps share files or have dependencies.

6. **Fail gracefully.** If a subagent can't complete its task, the orchestrator diagnoses and re-dispatches rather than trying to salvage partial work in its own context.

7. **Plan file tracks progress visually.** Checkboxes (`[ ]` → `[x]`) give you a human-readable view alongside bd's structured tracking.
