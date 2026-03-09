---
name: compound:compact-prep
description: Prepare for context compaction — save memory, commit, queue next task
argument-hint: "[optional: task to resume after compaction]"
---

# /compact-prep — Pre-Compaction Checklist

Run this before `/compact` to preserve session context. Execute all steps in order.

## Input

<post_compaction_task> #$ARGUMENTS </post_compaction_task>

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

If beads is not available, skip this step.

## Step 3: Commit Check (pre-compound)

Run `git status` to check for uncommitted work.

- **If there are meaningful changes:** Use **AskUserQuestion**: "There are uncommitted changes. Commit before compacting?"
  - **Yes** — commit (ask for message or suggest one)
  - **No** — proceed without committing
- **If clean:** Say "Nothing to commit" and move on.

This runs before compound so that current work is saved first.

## Step 4: Compound Check

Assess whether this session produced knowledge worth compounding:

- Non-obvious problem solved? (debugging insight, unexpected root cause, workaround)
- Surprising discovery about the codebase, data, or domain?
- Strategic/architectural decision with reusable rationale?
- Research that surfaced reusable findings?

**If yes**, use **AskUserQuestion**:

"This session has compound-worthy knowledge: [1-2 sentence summary of what's worth capturing]. Run `/compound:compound` now? (Must run before compacting — compound needs the full conversation context.)"
- **Yes — run /compound:compound now** — pause compact-prep, user runs compound, then resume at Step 5
- **Skip** — proceed without compounding

**If no:** Say "Nothing to compound" and move on.

## Step 5: Commit Check (post-compound)

If compound was run in Step 4, check `git status` again — compound creates docs that should be committed.

- **If there are new changes:** Use **AskUserQuestion**: "Compound created new docs. Commit them?"
  - **Yes** — commit
  - **No** — proceed without committing
- **If clean or compound was skipped:** Move on.

## Step 6: Version Check

Run the version check script to compare source, installed, and released versions:

```bash
# Find version-check.sh: local repo (dev) or installed plugin
VERSION_CHECK="plugins/compound-workflows/scripts/version-check.sh"
[[ -f "$VERSION_CHECK" ]] || VERSION_CHECK=$(find "$HOME/.claude/plugins" -name "version-check.sh" -path "*/compound-workflows/*" 2>/dev/null | head -1)
[[ -n "$VERSION_CHECK" ]] && bash "$VERSION_CHECK" || echo "version-check.sh not found — skipping"
```
- **If all versions match** (exit code 0): Say "Versions OK." and move on.
- **If STALE or UNRELEASED detected** (exit code 1): Present the script's full output to the user, then use **AskUserQuestion** for each actionable item:
  - **STALE** — "Plugin is stale. Update now?"
    - **Yes** — run `claude plugin update compound-workflows@compound-workflows-marketplace`
    - **No** — proceed without updating
  - **UNRELEASED** — "Version X.Y.Z has no release. Create one now?"
    - **Yes** — create tag and release: `git tag vX.Y.Z && git push origin vX.Y.Z && gh release create vX.Y.Z --title "vX.Y.Z" --notes "<changelog entry>"`
    - **No** — proceed without releasing

## Step 7: Queue Post-Compaction Task

If the user provided a post-compaction task in `#$ARGUMENTS`, confirm it back to them clearly:

> **After compaction, say `resume` and I'll:** [restate the task]

If no task was provided, ask:

> **Anything specific to pick up after compaction, or just `resume`?**

## Step 8: Ready to Compact

Output a brief summary block:

```
Ready to compact.
- Memory: [updated X files / no updates needed]
- Beads: [synced, N issues closed / no beads / N issues still in_progress]
- Compound: [done / run NOW before compacting / nothing to compound]
- Git: [clean / uncommitted changes — user declined commit]
- Versions: [all match / updated plugin / released vX.Y.Z / user declined]
- After compaction: [task description / general resume]

Run /compact when ready.
```
