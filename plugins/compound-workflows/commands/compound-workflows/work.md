---
name: compound-workflows:work
description: Execute work plans using beads for persistent progress tracking that survives context compaction
argument-hint: "[plan file, specification, or todo file path]"
---

# Work Plan Execution — Context-Safe Edition

Execute a work plan using **beads** for persistent task tracking instead of in-memory TodoWrite. Progress survives context compaction and session restarts.

## Input Document

<input_document> #$ARGUMENTS </input_document>

## Execution Workflow

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

### Phase 1: Quick Start

1. **Read Plan and Clarify**

   - Read the work document completely
   - Review any references or links provided in the plan
   - If the plan has an `origin:` field in frontmatter, note it for beads issue descriptions
   - **Check for unresolved items:** If the plan has an Open Questions section with deferred items, surface each to the user via **AskUserQuestion** before proceeding: "Plan has N deferred items. Resolve before implementation, or accept the risk?"
   - If anything is unclear or ambiguous, ask clarifying questions now
   - Get user approval to proceed
   - **Do not skip this** — better to ask questions now than build the wrong thing

2. **Setup Environment**

   First, check the current branch and worktree status:

   ```bash
   current_branch=$(git branch --show-current)
   default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
   if [ -z "$default_branch" ]; then
     default_branch=$(git rev-parse --verify origin/main >/dev/null 2>&1 && echo "main" || echo "master")
   fi
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

3. **Create Beads Issues from Plan**

   **Check for existing beads issues first:**

   ```bash
   bd list --status=open
   ```

   If issues already exist for this plan (check titles/descriptions), this is a **resumed session**. Skip to Phase 2 using existing issues.

   **If no existing issues**, decompose the plan into beads issues:

   - Create one issue per implementation task/step in the plan
   - Use the plan's phase structure for ordering
   - Set up dependencies with `bd dep add` where tasks are sequential
   - Reference the plan file path in each issue description

   ```bash
   # Example for a 3-phase plan:
   bd create --title="Phase 0: Foundation setup" --type=task --priority=1 --description="Plan: docs/plans/2026-02-10-feat-example-plan.md\nOrigin: docs/brainstorms/2026-02-10-example-brainstorm.md\n\nTasks:\n- Set up project structure\n- Configure dependencies\n- Create base components"

   bd create --title="Phase 1: Core implementation" --type=task --priority=2 --description="..."

   bd create --title="Phase 2: Polish and integration" --type=task --priority=2 --description="..."

   # Set dependencies
   bd dep add <phase-1-id> <phase-0-id>
   bd dep add <phase-2-id> <phase-1-id>
   ```

   **Granularity guidance:**
   - One issue per plan phase or major section (5-10 issues typical)
   - NOT one issue per line item (too granular, noisy)
   - Each issue should represent 15-60 minutes of work
   - Include enough context in the description to resume after compaction

### Phase 2: Execute

1. **Task Execution Loop**

   ```
   while (bd ready shows tasks):
     - Pick the next ready task: bd ready
     - Claim it: bd update <id> --status=in_progress
     - Read any referenced files from the plan
     - Look for similar patterns in codebase
     - Implement following existing conventions
     - Write tests for new functionality
     - Run System-Wide Impact Check (see below)
     - Run tests after changes
     - Close it: bd close <id>
     - Check off the corresponding item in the plan file ([ ] -> [x])
     - Evaluate for incremental commit (see below)
   ```

   **System-Wide Impact Check** — Before marking a task done, pause and ask:

   | Question | If coding | If analytical/strategic |
   |----------|-----------|----------------------|
   | **What does this trigger downstream?** | Trace callbacks, middleware, observers 2 levels out from your change | Who reads this? What decisions or actions follow from it? |
   | **Am I testing against reality?** | At least one integration test with real objects, not just mocks | Claims verified against primary sources (data, transcripts, docs) — not summaries or memory? |
   | **Can partial failure leave a mess?** | DB rows, cache entries, files orphaned if next step fails | Does this create commitments or expectations that outlive the document? (e.g., promising a timeline, implying a staffing model) |
   | **What else exposes this?** | Grep for the method in related classes, mixins, alt entry points | Who else is working on this topic or affected by it? Parallel efforts, conflicting initiatives? |
   | **Are strategies consistent across layers?** | Error classes, retry/fallback alignment across layers | Do different sections of this document contradict each other? Do assumptions hold across the whole argument? |

   **When to skip:** Trivial changes where the answer to all five is obviously "nothing."

   **IMPORTANT**: Always update the original plan document by checking off completed items. Use the Edit tool to change `- [ ]` to `- [x]` for each task you finish.

2. **Incremental Commits**

   | Commit when... | Don't commit when... |
   |----------------|---------------------|
   | Logical unit complete | Small part of a larger unit |
   | Tests pass + meaningful progress | Tests failing |
   | About to switch contexts | Purely scaffolding |
   | About to attempt risky changes | Would need a "WIP" message |

   ```bash
   git add <files related to this logical unit>
   git commit -m "feat(scope): description of this unit"
   ```

3. **Follow Existing Patterns**
   - Read referenced files from the plan first
   - Match naming conventions exactly
   - Reuse existing components
   - Follow CLAUDE.md conventions

4. **Test Continuously**
   - Run relevant tests after each significant change
   - Fix failures immediately
   - Add new tests for new functionality

5. **Track Progress with Beads**
   - `bd update <id> --status=in_progress` when starting a task
   - `bd close <id>` when done
   - `bd create --title="..." --type=bug` for unexpected discoveries
   - `bd ready` to see what's next

### Phase 2.5: Recovery After Compaction

If context was compacted and you're resuming:

1. Re-orient — check worktree and beads state:
   ```bash
   bd worktree info               # Are we in a worktree? Which one?
   bd list --status=in_progress   # What was being worked on
   bd ready                        # What's available next
   bd list --status=open           # Everything remaining
   ```

2. If `bd worktree info` shows you should be in a worktree but you're not, `cd` into it
3. Read the plan file to understand context
4. Check git log for recent commits to see what was already done
5. Resume from where you left off — beads tells you exactly where that is

### Phase 3: Quality Check

1. **Run Core Quality Checks**

   ```bash
   # Run full test suite (use project's test command)
   # Run linting (per CLAUDE.md)
   ```

2. **Consider Reviewer Agents** (Optional, for complex/risky changes)

   If reviewer agents are needed, use the **disk-write pattern** to avoid context exhaustion:

   ```
   mkdir -p .workflows/work-review/agents

   Task code-simplicity-reviewer (run_in_background: true): "You are a code simplicity reviewer. Check for unnecessary complexity, YAGNI violations, and over-engineering.

   Review the changes on the current branch. Run git diff against the base branch.

   === OUTPUT INSTRUCTIONS (MANDATORY) ===
   Write your COMPLETE findings to: .workflows/work-review/agents/code-simplicity.md
   After writing the file, return ONLY a 2-3 sentence summary.
   "

   # Same pattern for other reviewers
   ```

   After all reviewer agents complete, read their output files to address critical issues.

   **Do NOT delete review outputs.** The review directory at `.workflows/work-review/` is retained for traceability and learning. Prior review findings can inform future work sessions and help identify recurring patterns.

3. **Final Validation**
   - All beads issues closed: `bd list --status=open` shows none for this plan
   - All tests pass
   - Linting passes
   - Code follows existing patterns

### Phase 4: Ship It

1. **Create Commit**

   ```bash
   git add <relevant files>
   git status
   git diff --staged

   git commit -m "$(cat <<'EOF'
   feat(scope): description of what and why

   Brief explanation if needed.

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   ```

2. **Capture Screenshots** (if UI work — use agent-browser + imgup skills)

3. **Create Pull Request**

   ```bash
   git push -u origin feature-branch-name
   gh pr create --title "Feature: [Description]" --body "$(cat <<'EOF'
   ## Summary
   - What was built
   - Why it was needed

   ## Testing
   - Tests added/modified

   ## Screenshots
   [If applicable]

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   ```

4. **Update Beads**
   ```bash
   bd sync --flush-only
   ```

5. **Clean Up Worktree** (if applicable)

   If working in a worktree, return to the main repo and offer cleanup:

   ```bash
   # Return to main repo
   cd $(git worktree list --porcelain | head -1 | sed 's/worktree //')
   # Remove the worktree (has safety checks for uncommitted changes)
   bd worktree remove <worktree-name>
   ```

   Only remove after PR is created and pushed. If the user wants to keep the worktree (e.g., awaiting review feedback), skip this step.

6. **Notify User**
   - Summarize what was completed
   - Link to PR
   - Note any follow-up work (unclosed beads issues)

7. **Compound Check**

   Before closing out, assess whether this session produced compound-worthy knowledge:
   - Did you solve a non-obvious problem? (debugging insight, unexpected root cause, workaround for a tool/framework limitation)
   - Did you discover something surprising about the codebase, data, or domain?
   - Did you make a strategic or architectural decision with rationale worth preserving?
   - Did research surface reusable findings? (cost analysis, competitive intelligence, technical evaluation)

   If yes to any: "This session produced knowledge worth compounding. Run `/compound-workflows:compound` to capture it before context is lost."

   If no: skip silently.

## Key Principles

- **Beads is the source of truth** — not in-memory state, not conversation history
- **After compaction, `bd ready` tells you what's next** — no context needed
- **Each issue has enough description to resume** — include plan path, origin, and task details
- **No unresolved items cross phase boundaries** — every open question, concern, or finding must be explicitly resolved, deferred with rationale, or removed before moving to the next phase
- **Ship complete features** — don't leave issues open without reason
- **Test as you go** — run tests after each change, not at the end
