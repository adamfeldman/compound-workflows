---
name: resolve_pr_parallel
description: Resolve PR review comments in parallel
argument-hint: "[optional: PR number or current PR]"
disable-model-invocation: true
allowed-tools: Bash(gh *), Bash(git *), Read
---

# Resolve PR Comments in Parallel

Resolve all unresolved PR review comments by spawning parallel agents for each thread.

## Context Detection

Claude Code automatically detects git context:
- Current branch and associated PR
- All PR comments and review threads
- Works with any PR by specifying the number

## Workflow

### 1. Analyze

Fetch unresolved review threads using the GraphQL script:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/get-pr-comments PR_NUMBER
```

This returns only **unresolved, non-outdated** threads with file paths, line numbers, and comment bodies.

If the script fails, fall back to:
```bash
gh pr view PR_NUMBER --json reviews,comments
gh api repos/{owner}/{repo}/pulls/PR_NUMBER/comments
```

### 2. Plan

Create a TodoWrite list of all unresolved items grouped by type:
- Code changes requested
- Questions to answer
- Style/convention fixes
- Test additions needed

### 3. Implement (PARALLEL)

#### 3a. Determine Run Number

Before dispatching agents, determine the run number and create the output directory:

First, count existing runs:

```bash
ls -d .workflows/resolve-pr/PR_NUMBER/agents/run-* 2>/dev/null | wc -l | tr -d ' '
```

Read the output as the existing run count. Add 1 to get the new run number. Then create the output directory:

```bash
mkdir -p .workflows/resolve-pr/PR_NUMBER/agents/run-RUN_NUM/
```

Replace `PR_NUMBER` with the actual PR number.

#### 3b. Dispatch Agents with OUTPUT INSTRUCTIONS

Spawn a `pr-comment-resolver` agent for each unresolved item in parallel. Each agent MUST include OUTPUT INSTRUCTIONS that direct output to disk.

If there are 3 comments, spawn 3 agents:

1. Task pr-comment-resolver (run_in_background: true): "
   [comment 1 context: thread ID, file path, line number, comment body]

   === OUTPUT INSTRUCTIONS (MANDATORY) ===
   Write your complete Comment Resolution Report to: .workflows/resolve-pr/PR_NUMBER/agents/run-N/comment-1.md
   Include the thread ID and all changed file paths in your report.
   After writing the file, return ONLY a 2-3 sentence summary including the thread ID and changed file paths.
   "

2. Task pr-comment-resolver (run_in_background: true): "
   [comment 2 context: thread ID, file path, line number, comment body]

   === OUTPUT INSTRUCTIONS (MANDATORY) ===
   Write your complete Comment Resolution Report to: .workflows/resolve-pr/PR_NUMBER/agents/run-N/comment-2.md
   Include the thread ID and all changed file paths in your report.
   After writing the file, return ONLY a 2-3 sentence summary including the thread ID and changed file paths.
   "

3. Task pr-comment-resolver (run_in_background: true): "
   [comment 3 context: thread ID, file path, line number, comment body]

   === OUTPUT INSTRUCTIONS (MANDATORY) ===
   Write your complete Comment Resolution Report to: .workflows/resolve-pr/PR_NUMBER/agents/run-N/comment-3.md
   Include the thread ID and all changed file paths in your report.
   After writing the file, return ONLY a 2-3 sentence summary including the thread ID and changed file paths.
   "

Replace `PR_NUMBER` with the actual PR number and `N` with the run number from step 3a.

#### 3c. Monitor Completion

**DO NOT call TaskOutput** to retrieve full results. The files on disk ARE the results.

Poll for file existence to track completion:

```bash
ls .workflows/resolve-pr/PR_NUMBER/agents/run-N/
```

Compare the files present against the expected list (one `comment-*.md` per dispatched agent). When all expected files exist, proceed to step 4.

If an agent hasn't produced output after 3 minutes, mark it as timed out and proceed with the completed results.

### 4. Commit & Resolve

Use the agent summaries (which include thread IDs and changed file paths) to commit and resolve:

- Commit changes with a clear message referencing the PR feedback: use the **Write tool** to write the commit message to `.workflows/scratch/commit-msg-resolve-pr-<PR_NUMBER>.txt`, then run `git commit -F .workflows/scratch/commit-msg-resolve-pr-<PR_NUMBER>.txt`.
- For each resolved comment, use the thread ID from the agent summary to resolve the thread programmatically:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/resolve-pr-thread THREAD_ID
```

- Push to remote

If additional detail is needed beyond the summaries, read the resolution reports from disk:

```bash
cat .workflows/resolve-pr/PR_NUMBER/agents/run-N/comment-1.md
```

Resolution reports are typically ~20 lines each — reading them is acceptable when needed for commit message crafting or verifying resolution details.

### 5. Verify

Re-fetch comments to confirm all threads are resolved:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/get-pr-comments PR_NUMBER
```

Should return an empty array `[]`. If threads remain, repeat from step 1.

## Scripts

- [scripts/get-pr-comments](scripts/get-pr-comments) - GraphQL query for unresolved review threads
- [scripts/resolve-pr-thread](scripts/resolve-pr-thread) - GraphQL mutation to resolve a thread by ID

## Success Criteria

- All unresolved review threads addressed
- Changes committed and pushed
- Threads resolved via GraphQL (marked as resolved on GitHub)
- Empty result from get-pr-comments on verify
