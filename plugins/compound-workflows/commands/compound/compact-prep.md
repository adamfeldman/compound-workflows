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
bash plugins/compound-workflows/scripts/init-values.sh compact-prep
```

Read the output. Track the values PLUGIN_ROOT, VERSION_CHECK, DATE, DATE_COMPACT, TIMESTAMP, SNAPSHOT_FILE for use in subsequent steps. If init-values.sh fails or any value is empty, warn the user and stop.

Then run the version check using the VERSION_CHECK value from the output:

```bash
bash <VERSION_CHECK>
```

If VERSION_CHECK is empty or the script is not found, say "version-check.sh not found — skipping".
- **If all versions match** (exit code 0): Say "Versions OK." and move on.
- **If STALE or UNRELEASED detected** (exit code 1): Present the script's full output to the user, then use **AskUserQuestion** for each actionable item:
  - **STALE** — "Plugin is stale. Update now?"
    - **Yes** — run `claude plugin update compound-workflows@compound-workflows-marketplace`
    - **No** — proceed without updating
  - **UNRELEASED** — only act on this if `plugins/compound-workflows/` exists locally (you're in the plugin source repo). For regular users, UNRELEASED is informational only — skip it.
    - **In source repo** — "Version X.Y.Z has no release. Create one now?"
      - **Yes** — create tag and release: `git tag vX.Y.Z && git push origin vX.Y.Z && gh release create vX.Y.Z --title "vX.Y.Z" --notes "<changelog entry>"`
      - **No** — proceed without releasing

## Step 7: Daily Cost Summary

Check if `ccusage` is installed and report today's cost/token usage:

```bash
which ccusage 2>/dev/null
```

**If ccusage is available:**

Use the DATE_COMPACT value from init-values.sh output:

```bash
ccusage daily --json --breakdown --since <DATE_COMPACT> --offline 2>/dev/null
```

Parse the JSON output defensively — field naming varies across ccusage versions:
- Individual items use `costUSD`
- Totals sections use `totalCost`
- Summary level uses `totalCostUSD`

Check for all three field names when extracting cost data.

**Display format:** "Today's cost: $X.XX (input: Nk tokens, output: Mk tokens)" — include per-model breakdown if `--breakdown` data is available.

**Sonnet savings estimate:** If breakdown data shows both Opus and Sonnet usage, calculate estimated savings: `sonnet_cost * 4` (what those tokens would have cost on Opus minus what they actually cost on Sonnet — Sonnet is ~5x cheaper, so savings = sonnet_cost * 4). Calculate percentage: `savings / (total_cost + savings) * 100`. Display as: "Estimated Sonnet savings: ~$X.XX (N% — Sonnet tokens would have cost ~$Y.YY on Opus)".

If JSON parsing fails for any reason, show the raw summary output rather than erroring.

**If ccusage is not available:** "ccusage not installed — skip token tracking. Install: `npm install -g ccusage`"

> **Limitation:** ccusage tracks daily aggregate usage across all sessions, not per-session or per-agent breakdowns.

### Step 7b: Persist ccusage Snapshot

If ccusage data was successfully retrieved and parsed in Step 7 (i.e., ccusage was available AND JSON parsing succeeded), persist a snapshot to the stats directory. If ccusage was not available or parsing failed, skip this entirely — do not error.

```bash
mkdir -p .workflows/stats
```

Write the snapshot via atomic append (`cat >>`). Use the SNAPSHOT_FILE and TIMESTAMP values from init-values.sh output:

```bash
cat >> "<SNAPSHOT_FILE>" <<EOF
---
type: ccusage-snapshot
timestamp: <TIMESTAMP>
total_cost_usd: <total cost from parsed data>
input_tokens: <total input tokens from parsed data>
output_tokens: <total output tokens from parsed data>
EOF
```

**Core fields (always include):** `type`, `timestamp`, `total_cost_usd`, `input_tokens`, `output_tokens`.

**Extensible fields:** If the parsed ccusage output includes additional data (e.g., `cache_read_tokens`, `cache_write_tokens`, per-model cost breakdown), append them as additional YAML keys in the same `cat >>` block. The schema is extensible — unknown fields are preserved for future analysis.

After writing, add a brief note to the Step 7 output: "ccusage snapshot saved to .workflows/stats/"

If the file already exists (multiple compact-prep runs on the same day), the `cat >>` naturally appends with the `---` YAML document separator — each run becomes a separate document in the same file.

## Step 8: Queue Post-Compaction Task

If the user provided a post-compaction task in `#$ARGUMENTS`, confirm it back to them clearly:

> **After compaction, say `resume` and I'll:** [restate the task]

If no task was provided, ask:

> **Anything specific to pick up after compaction, or just `resume`?**

## Step 9: Ready to Compact

Output a brief summary block:

```
Ready to compact.
- Memory: [updated X files / no updates needed]
- Beads: [synced, N issues closed / no beads / N issues still in_progress]
- Compound: [done / run NOW before compacting / nothing to compound]
- Git: [clean / uncommitted changes — user declined commit]
- Versions: [all match / updated plugin / released vX.Y.Z / user declined]
- Cost: [today $X.XX, saved ~$Y.YY via Sonnet / ccusage not installed / parse error — raw output shown]
- After compaction: [task description / general resume]

Run /compact when ready.
```
