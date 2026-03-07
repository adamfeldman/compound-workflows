---
name: compound:compact-prep
description: Prepare for context compaction — update memory, check for compound-worthy learnings, commit, and queue post-compaction task
argument-hint: "[optional: task to resume after compaction]"
---

# /compact-prep — Pre-Compaction Checklist

Run this before `/compact` to preserve session context. Execute all steps in order.

## Input

<post_compaction_task> $ARGUMENTS </post_compaction_task>

## Step 1: Update Memory

Review the conversation for anything worth persisting to `memory/`. Focus on:

- **Facts learned** — names, roles, relationships, financial details, confirmed data points
- **Working style observations** — editing patterns, communication preferences, questioning style, iteration approach
- **Terms/jargon** — new acronyms, shorthand, or project codenames used
- **Decision rationale** — scan the user's responses for *why* they chose something, not just *what* they chose. The "because" clauses in their replies are the high-value context. Decisions often survive in documents; the reasoning behind them often doesn't. Persist rationale to memory as context alongside the core information being remembered.
- **Corrections** — anything that contradicts existing memory (update or remove the old entry)

Read relevant memory files first, then update only if there's genuinely new information. Don't duplicate what's already stored.

Tell the user what you updated and why (1-2 sentences per update, not a wall of text).

## Step 2: Beads Check

If beads (`bd`) is available:

1. Check for in-progress issues:
   ```bash
   bd list --status=in_progress
   ```
   If any exist, warn the user: "N issues are still in_progress. Close or note them before compacting — you'll lose track of where you were otherwise."

2. Sync beads:
   ```bash
   bd sync --flush-only
   ```

If beads is not available, skip this step.

## Step 3: Commit Check (pre-compound)

Run `git status` to check for uncommitted work.

- **If there are meaningful changes:** Ask the user if they want to commit before compacting. Don't auto-commit.
- **If clean:** Say "Nothing to commit" and move on.

This runs before compound so that current work is saved first.

## Step 4: Compound Check

Assess whether this session produced knowledge worth compounding:

- Non-obvious problem solved? (debugging insight, unexpected root cause, workaround)
- Surprising discovery about the codebase, data, or domain?
- Strategic/architectural decision with reusable rationale?
- Research that surfaced reusable findings?

**If yes:** Tell the user: "This session has compound-worthy knowledge — run `/compound:compound` **now, before compacting**. Compound needs the full conversation context to extract what happened; after compaction, the details are gone."

**Wait for the user to run compound (or decline) before proceeding.** If they run it, compound will create new files — Step 5 handles committing those.

**If no:** Say "Nothing to compound" and move on.

## Step 5: Commit Check (post-compound)

If compound was run in Step 4, check `git status` again — compound creates docs that should be committed.

- **If there are new changes:** Ask the user if they want to commit.
- **If clean or compound was skipped:** Move on.

## Step 6: Queue Post-Compaction Task

If the user provided a post-compaction task in `$ARGUMENTS`, confirm it back to them clearly:

> **After compaction, say `resume` and I'll:** [restate the task]

If no task was provided, ask:

> **Anything specific to pick up after compaction, or just `resume`?**

## Step 7: Ready to Compact

Output a brief summary block:

```
Ready to compact.
- Memory: [updated X files / no updates needed]
- Beads: [synced, N issues closed / no beads / N issues still in_progress]
- Compound: [done / run NOW before compacting / nothing to compound]
- Git: [clean / uncommitted changes — user declined commit]
- After compaction: [task description / general resume]

Run /compact when ready.
```
