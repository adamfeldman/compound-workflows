---
name: compound:review
description: Context-safe code review using multi-agent analysis with disk-persisted outputs
argument-hint: "[PR number, GitHub URL, branch name, or latest]"
---

# Review Command — Context-Safe Edition

Perform exhaustive code reviews using multi-agent analysis. All agent outputs are persisted to disk to avoid context exhaustion from 13+ parallel agent transcripts.

## Prerequisites

- Git repository with GitHub CLI (`gh`) installed and authenticated
- Clean main/master branch

## Main Tasks

### 1. Determine Review Target & Setup

<review_target> #$ARGUMENTS </review_target>

- Determine review type: PR number, GitHub URL, file path (.md), or empty (current branch)
- Check current git branch
- If on target branch, proceed. If different branch, offer worktree via `skill: git-worktree`
- Fetch PR metadata: `gh pr view --json title,body,files,baseRefName`
- Checkout the review branch if needed

### 2. Create Working Directory

Derive a short topic stem from the review target: use branch name for branches (e.g., `feat-user-dashboard-redesign`), `pr-NNN` for PRs, or filename stem (strip date prefix and type suffix) for document reviews (e.g., `reporting-strategy` from `2026-02-23-reporting-strategy-brainstorm.md`).

```bash
mkdir -p .workflows/code-review/<topic-stem>/agents
```

### 3. Launch Review Agents (Disk-Persisted)

**CRITICAL: Every agent writes to disk, returns only a summary.**

Launch ALL review agents in parallel with `run_in_background: true`. Each agent gets the same instruction block appended:

**The disk-write instruction (append to every agent prompt):**

```
=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write your COMPLETE findings to: .workflows/code-review/<topic-stem>/agents/<agent-name>.md
Structure with: ## Summary, ## Critical Findings, ## Recommendations, ## Details
After writing the file, return ONLY a 2-3 sentence summary.
DO NOT return your full analysis in your response.
```

**Standard agents (always run):**

```
Task typescript-reviewer (run_in_background: true): "You are a TypeScript code reviewer focused on type safety, modern patterns, and maintainability. Review PR changes. Run git diff against base branch. [disk-write instructions for: typescript.md]"
Task pattern-recognition-specialist (run_in_background: true): "You are a pattern recognition specialist. Analyze for design patterns, anti-patterns, naming conventions, and duplication. [disk-write for: pattern-recognition.md]"
Task architecture-strategist (run_in_background: true): "You are an architecture strategist. Review architectural impact, pattern compliance, and design integrity. [disk-write for: architecture.md]"
Task security-sentinel (run_in_background: true): "You are a security auditor. Check for vulnerabilities, input validation, auth/authz issues, and OWASP compliance. [disk-write for: security.md]"
Task performance-oracle (run_in_background: true): "You are a performance analyst. Check for bottlenecks, algorithmic complexity, database queries, memory usage. [disk-write for: performance.md]"
Task code-simplicity-reviewer (run_in_background: true): "You are a code simplicity reviewer. Check for unnecessary complexity, YAGNI violations, and over-engineering. [disk-write for: simplicity.md]"
Task agent-native-reviewer (run_in_background: true): "You are an agent-native reviewer. Verify any action a user can take, an agent can also take. [disk-write for: agent-native.md]"
```

**Conditional agents (run if PR matches criteria):**

- If PR has database migrations: `Task data-migration-expert` ("You are a data migration expert. Validate migrations, backfills, and production data transformations."), `Task deployment-verification-agent` ("You are a deployment verification specialist. Produce Go/No-Go checklists with SQL verification queries and rollback procedures.")
- If PR has frontend code: `Task frontend-races-reviewer` ("You are a frontend concurrency reviewer. Check for race conditions, stale closures, unhandled promises, and UI state synchronization issues.")

**Adapt agent selection to the actual codebase.** Match conditional agents to the stack detected in the PR.

### 4. Monitor Agent Completion

**DO NOT call TaskOutput.** Instead, poll for file existence:

```bash
ls .workflows/code-review/<topic-stem>/agents/
```

Compare against expected agent files. When all files exist (or after 3 minutes for stragglers), proceed.

Mark timed-out agents and move on — don't let one slow agent block everything.

### 5. Synthesize Findings

Read all agent output files from disk:

```bash
ls .workflows/code-review/<topic-stem>/agents/*.md
# Then Read tool on each file
```

**Synthesize:**
- Discard findings that flag `docs/plans/` or `docs/solutions/` for deletion (protected artifacts)
- Categorize: security, performance, architecture, quality
- Assign severity: P1 (critical, blocks merge), P2 (important), P3 (nice-to-have)
- Deduplicate overlapping findings
- Estimate effort per finding

### 6. Create Todo Files

Use the file-todos skill to create todo files for ALL findings:

```bash
mkdir -p todos/

# For each finding, create a todo file:
# {issue_id}-pending-{priority}-{description}.md
```

Follow the file-todos template structure:
- YAML frontmatter: status, priority, issue_id, tags, dependencies
- Problem Statement, Findings, Proposed Solutions, Acceptance Criteria

### 7. Summary Report

Present to user:

```markdown
## Code Review Complete

**Review Target:** PR #XXXX - [Title]
**Branch:** [branch-name]
**Plan:** [plan path, if known from PR description or branch context]
**Origin:** [brainstorm path, if traceable from plan's origin: field]

### Findings:
- **P1 (Critical):** [count] — BLOCKS MERGE
- **P2 (Important):** [count]
- **P3 (Nice-to-have):** [count]

### Created Todos:
- `001-pending-p1-{finding}.md` — {description}
- `002-pending-p2-{finding}.md` — {description}
...

### Next Steps:
1. Address P1 findings (blocks merge)
2. Triage: `ls todos/*-pending-*.md`
3. Work approved items: `/resolve_todo_parallel`
```

### 8. Retain Review Outputs

**Do NOT delete review outputs.** The review directory at `.workflows/code-review/<topic-stem>/` is retained for traceability and learning. Prior review findings can inform future reviews and help identify recurring patterns.

### 9. Optional End-to-End Testing

Offer appropriate testing based on project type:
- Web: `/test-browser`
- iOS: `/xcode-test`

## Protected Artifacts

Never flag for deletion:
- `docs/plans/*.md` — living plan documents
- `docs/solutions/*.md` — compound knowledge documents

## Key Principle

Agent outputs go to disk. Parent context stays lean. Findings go to todo files. Nothing is lost if context compacts.
