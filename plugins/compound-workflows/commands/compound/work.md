---
name: compound:work
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

### 1.2 Setup Worktree

**NEVER call `git worktree add` directly.** Always use `bd worktree` or the `worktree-manager.sh` script. Raw `git worktree add` creates worktrees in the wrong location and requires manual `.gitignore` entries.

Check current branch and worktree state:

```bash
current_branch=$(git branch --show-current)
default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [ -z "$default_branch" ]; then
  default_branch=$(git rev-parse --verify origin/main >/dev/null 2>&1 && echo "main" || echo "master")
fi
echo "Current: $current_branch | Default: $default_branch"
# Detect worktree tool availability
command -v bd >/dev/null 2>&1 && echo "BD=available" || echo "BD=not_available"
bd worktree info 2>/dev/null
```

**If already in a worktree:** Continue working there. No setup needed.

**If already on a feature branch** (not the default branch):
- **AskUserQuestion:** "Continue working on `[current_branch]`, or create a worktree for isolated development?"

**If on the default branch**, create a worktree (default) or opt out:
- **Default:** Create a worktree — provides isolated development. Then `cd` into the worktree path.
- **Opt-out:** Work directly on a feature branch (`git checkout -b feat/...`) — only if user explicitly prefers this.

```bash
# Primary: bd worktree (beads handles db redirect automatically)
# IMPORTANT: pass .worktrees/<name> — bd uses the path as-is, defaults to repo root otherwise
bd worktree create .worktrees/<descriptive-name>
cd .worktrees/<descriptive-name>

# Fallback (if bd not available): use worktree-manager.sh (already defaults to .worktrees/)
bash plugins/compound-workflows/skills/git-worktree/scripts/worktree-manager.sh create <descriptive-name>
cd .worktrees/<descriptive-name>
```

**Why worktrees are the default for subagent execution:** Subagents write code autonomously. If something goes wrong, you can nuke the worktree without touching your main working tree. No `git reset --hard`, no orphaned files.

**TodoWrite mode:** Skip worktree setup. Create a feature branch instead:
```bash
git checkout -b feat/<descriptive-name>
```

### 1.2.1 Create QA Hook Sentinel

Suppress the PostToolUse QA hook during `/compound:work` execution. Without this, every subagent commit triggers Tier 1 QA scripts — adding overhead and stderr noise per commit.

```bash
mkdir -p .workflows
date +%s > .workflows/.work-in-progress
```

This sentinel is checked by `.claude/hooks/plugin-qa-check.sh`. It is removed in Phase 4 (Ship) and cleaned up if stale in Phase 2.4 (Recovery).

### 1.3 Create or Resume Task Issues

**Check for existing issues first:**

```bash
bd list --status=open
bd list --status=in_progress
```

If issues already exist for this plan, this is a **resumed session**. Skip to Phase 2.

**If no existing issues**, decompose the plan into beads issues:

- One issue per implementation step/phase (5-10 issues typical)
- Each issue should represent 15-60 minutes of focused work
- Set up dependencies with `bd dep add` where tasks are sequential
- **Critical:** Each issue description MUST be self-contained enough for a subagent to execute independently. Include:
  - What to build/change
  - Which files to read for context/patterns
  - What tests to write or run
  - The plan file path for reference

**Example:**

```bash
bd create --title="Set up project structure" --type=task --priority=1 \
  --description="Plan: docs/plans/YYYY-MM-DD-feat-example-plan.md
Origin: docs/brainstorms/YYYY-MM-DD-example-brainstorm.md

Tasks:
- Create src/components/ directory structure
- Add base configuration files
- Reference: src/existing-component/ for conventions

Test: Run existing test suite to verify no regressions.
Commit when done with: feat(scaffold): set up project structure"

bd create --title="Implement core logic" --type=task --priority=2 \
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
9. Stage and commit your changes with the commit message suggested in the task description (or write an appropriate conventional commit message)
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

**Dispatch with:**

```
Task general-purpose (foreground): "[constructed prompt above]"
```

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
3. Check for stale sentinel file and clean up if needed:
   ```bash
   if [ -f .workflows/.work-in-progress ]; then
     sentinel_age=$(( $(date +%s) - $(cat .workflows/.work-in-progress) ))
     if [ "$sentinel_age" -ge 14400 ]; then
       echo "Stale sentinel detected ($(( sentinel_age / 3600 ))h old) — removing to re-enable QA hook"
       rm -f .workflows/.work-in-progress
     fi
   fi
   ```
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
   mkdir -p .workflows/work-review/

   Task code-simplicity-reviewer (run_in_background: true): "You are a code simplicity reviewer. Check for unnecessary complexity, YAGNI violations, and over-engineering.

   Review all changes on the current branch vs the base branch.
   Run: git diff [base-branch]...HEAD

   === OUTPUT INSTRUCTIONS (MANDATORY) ===
   Write your COMPLETE findings to: .workflows/work-review/code-simplicity.md
   After writing the file, return ONLY a 2-3 sentence summary.
   "
   ```

   Read review output files. Address critical issues only.

## Phase 4: Ship (Orchestrator)

1. **Final commit** (if quality fixes were needed):
   ```bash
   git add <files>
   git commit -m "$(cat <<'EOF'
   chore: address review feedback

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   ```

2. **Remove QA hook sentinel** (re-enable PostToolUse QA enforcement):
   ```bash
   rm -f .workflows/.work-in-progress
   ```

3. **Create PR** (if project uses PRs):
   ```bash
   git push -u origin [branch-name]
   gh pr create --title "[Description]" --body "$(cat <<'EOF'
   ## Summary
   - What was built
   - Why it was needed

   ## Testing
   - Tests added/modified

   ## Implementation Notes
   - Executed via subagent architecture (N steps dispatched independently)

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   ```

   > **Post-merge reminder:** After the PR is merged, run `/compound-workflows:version` or `/compound:compact-prep` to check for missing GitHub releases. Do not create releases automatically — the user decides when to cut a release.

4. **Update plan status** (if YAML frontmatter has `status` field):
   ```
   status: active  →  status: completed
   ```

5. **Clean up worktree** (if applicable):

   If working in a worktree, return to the main repo and offer cleanup:

   ```bash
   # Return to main repo
   cd $(git worktree list --porcelain | head -1 | sed 's/worktree //')
   # Remove the worktree
   bd worktree remove .worktrees/<worktree-name>
   # Fallback (if bd not available):
   bash plugins/compound-workflows/skills/git-worktree/scripts/worktree-manager.sh remove <worktree-name>
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

   If yes to any: "This session produced knowledge worth compounding. Run `/compound:compound` to capture it before context is lost."

   If no: skip silently.

## Key Principles

1. **Orchestrator never codes.** It reads the plan, manages bd, dispatches subagents, and ships. The only exception is trivial post-review fixes (< 5 lines).

2. **Each subagent is disposable.** It gets a self-contained prompt, does its work, commits, and returns a summary. No shared state between subagents except the git repo.

3. **Persistent state is the source of truth.** With beads: `bd ready` tells you exactly where to resume after compaction. With TodoWrite: the plan file's checkboxes + git log are your recovery path. Never rely on conversation history or in-memory state.

4. **No unresolved items cross phase boundaries.** Every open question, concern, or finding must be explicitly resolved, deferred with rationale, or removed before moving to the next phase.

5. **Parallel when safe, sequential when shared.** If steps touch completely separate files with no dependencies, parallel dispatch is equally safe and faster. Use sequential only when steps share files or have dependencies.

6. **Fail gracefully.** If a subagent can't complete its task, the orchestrator diagnoses and re-dispatches rather than trying to salvage partial work in its own context.

7. **Plan file tracks progress visually.** Checkboxes (`[ ]` → `[x]`) give you a human-readable view alongside bd's structured tracking.
