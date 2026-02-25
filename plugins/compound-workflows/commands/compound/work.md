---
name: compound:work
description: Execute work plans using subagent dispatch — context stays lean, progress survives compaction
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

**If beads (`bd`) is available:** Use `bd create`, `bd update`, `bd close`, `bd ready` for all task tracking. Progress survives context compaction.

**If beads is NOT available:** Use TodoWrite for task tracking instead. Same phase structure, but progress is lost if context compacts. The `bd` commands below should be mentally replaced with their TodoWrite equivalents:
- `bd create --title="..."` → `TodoWrite: add task "..."`
- `bd update <id> --status=in_progress` → `TodoWrite: mark in_progress`
- `bd close <id>` → `TodoWrite: mark completed`
- `bd ready` → `TodoWrite: list pending tasks`

**Note:** With TodoWrite, recovery after compaction requires re-reading the plan file and checking git log to infer progress. Beads makes this automatic.

### 1.1 Read and Clarify the Plan

- Read the plan document completely
- Review references and links
- If the plan has an `origin:` field in frontmatter, note it for beads issue descriptions and subagent context
- **Check for unresolved items:** If the plan has an Open Questions section with deferred items, surface each to the user via **AskUserQuestion** before proceeding: "Plan has N deferred items. Resolve before implementation, or accept the risk?"
- If anything is unclear, ask clarifying questions now
- Get user approval to proceed
- **Do not skip this** — the orchestrator must understand the plan before dispatching work

### 1.2 Setup Worktree

Check current branch and worktree state:

```bash
current_branch=$(git branch --show-current)
default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [ -z "$default_branch" ]; then
  default_branch=$(git rev-parse --verify origin/main >/dev/null 2>&1 && echo "main" || echo "master")
fi
echo "Current: $current_branch | Default: $default_branch"
bd worktree info 2>/dev/null
```

**If already in a worktree:** Continue working there. No setup needed.

**If already on a feature branch** (not the default branch):
- Ask: "Continue working on `[current_branch]`, or create a worktree for isolated development?"

**If on the default branch**, create a worktree (default) or opt out:
- **Default:** Create a worktree with `bd worktree create <name>` — provides isolated development with shared beads state. Then `cd` into the worktree path.
- **Opt-out:** Work directly on a feature branch (`git checkout -b feat/...`) — only if user explicitly prefers this.

```bash
# Default: worktree (beads handles db redirect automatically)
bd worktree create <descriptive-name>
cd .worktrees/<descriptive-name>
```

**Why worktrees are the default for subagent execution:** Subagents write code autonomously. If something goes wrong, you can nuke the worktree (`bd worktree remove <name>`) without touching your main working tree. No `git reset --hard`, no orphaned files.

### 1.3 Create or Resume Beads Issues

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
  --description="Plan: docs/plans/2026-02-20-feat-example-plan.md
Origin: docs/brainstorms/2026-02-20-example-brainstorm.md

Tasks:
- Create src/components/ directory structure
- Add base configuration files
- Reference: src/existing-component/ for conventions

Test: Run existing test suite to verify no regressions.
Commit when done with: feat(scaffold): set up project structure"

bd create --title="Implement core logic" --type=task --priority=2 \
  --description="Plan: docs/plans/2026-02-20-feat-example-plan.md

Tasks:
- Implement the FooService class following pattern in src/services/bar_service.rb
- Add unit tests in test/services/foo_service_test.rb
- Handle edge cases: empty input, nil values

Test: ruby -Itest test/services/foo_service_test.rb
Commit when done with: feat(foo): implement core logic"

# Phase 1 depends on Phase 0
bd dep add <phase-1-id> <phase-0-id>
```

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

**Why foreground, not background:** Steps are usually sequential (each builds on the prior commit). Background execution would cause merge conflicts and race conditions. Use foreground so each subagent sees the prior subagent's committed code.

**Exception — parallel dispatch:** If `bd ready` shows multiple issues with NO dependency between them, you MAY dispatch them in parallel using `run_in_background: true`. But only if they touch completely separate files. When in doubt, run sequentially.

### 2.2 Building the Subagent Prompt

Each subagent gets a self-contained prompt. The orchestrator constructs it from the bd issue description plus standard context.

**Template:**

```
You are executing one step of a larger work plan. Your job is to implement ONLY the tasks described below, commit your work, and return a summary.

## Your Task

[Paste the bd issue description here — title + full description field]

## Context

- **Plan file:** [path] — Read this for overall context but only implement YOUR step
- **Origin brainstorm:** [path from plan's origin: field, or "none"] — Reference for why decisions were made
- **Working directory:** [cwd] (this may be a worktree — that's normal, treat it as the repo root)
- **Current branch:** [branch name]
- **Prior steps completed:** [list recent git log --oneline -5 or bd list --status=closed summary]

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

**Failure path:**
If the subagent reports it couldn't complete the task:
1. Read the subagent's explanation
2. Check what was partially done (`git status`, `git diff`)
3. Decide:
   - **Fixable context issue:** Update the bd issue description with more detail, re-dispatch
   - **Dependency problem:** Create a new blocking issue, update deps
   - **Needs human input:** Ask the user with AskUserQuestion
   - **Small remaining work:** Handle it in-orchestrator (exception to the "never code" rule — only for trivial fixes like import statements or typos)

### 2.4 Recovery After Compaction

If context compacts mid-execution, recovery is simple:

1. Re-orient — check worktree and beads state:
   ```bash
   bd worktree info               # Are we in a worktree? Which one?
   bd list --status=in_progress   # What was being worked on
   bd ready                        # What's available next
   bd list --status=closed | tail -5  # What was recently completed
   ```
2. If `bd worktree info` shows you should be in a worktree but you're not, `cd` into it
3. Check git log for recent commits:
   ```bash
   git log --oneline -10
   ```
4. Read the plan file to re-orient
5. Resume the dispatch loop from step 2.1

**This is the whole point of the architecture.** No in-memory state to lose. bd + git + worktree info + plan file = complete recovery.

## Phase 3: Quality Check (Orchestrator)

After all bd issues are closed:

1. **Verify completeness:**
   ```bash
   bd list --status=open    # Should be empty for this plan
   git log --oneline -20    # Review all commits from this session
   ```

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

2. **Create PR** (if project uses PRs):
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

3. **Update beads:**
   ```bash
   bd sync --flush-only
   ```

4. **Update plan status** (if YAML frontmatter has `status` field):
   ```
   status: active  →  status: completed
   ```

5. **Clean up worktree** (if applicable):

   If working in a worktree, return to the main repo and offer cleanup:

   ```bash
   # Return to main repo
   cd $(git worktree list --porcelain | head -1 | sed 's/worktree //')
   # Remove the worktree (has safety checks for uncommitted changes)
   bd worktree remove <worktree-name>
   ```

   Only remove after PR is created and pushed. If the user wants to keep the worktree (e.g., awaiting review feedback), skip this step.

6. **Notify user** with summary:
   - Steps completed (N/N issues closed)
   - PR link
   - Any follow-up work (unclosed issues)

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

3. **bd is the source of truth.** Not conversation history, not TodoWrite, not in-memory state. After compaction, `bd ready` tells you exactly where to resume.

4. **No unresolved items cross phase boundaries.** Every open question, concern, or finding must be explicitly resolved, deferred with rationale, or removed before moving to the next phase.

5. **Foreground by default, parallel only when safe.** Sequential dispatch prevents conflicts. Parallel only when issues touch completely separate files with no dependencies.

6. **Fail gracefully.** If a subagent can't complete its task, the orchestrator diagnoses and re-dispatches rather than trying to salvage partial work in its own context.

7. **Plan file tracks progress visually.** Checkboxes (`[ ]` → `[x]`) give you a human-readable view alongside bd's structured tracking.
