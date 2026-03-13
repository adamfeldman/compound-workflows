---
name: do:compact-prep
description: Prepare for context compaction — save memory, commit, queue next task
argument-hint: "[--abandon] [optional: task to resume after compaction]"
---

# /compact-prep — Pre-Compaction Checklist

Run this before `/compact` to preserve session context. Uses a two-phase architecture: gather all information first (check phase), present a single consolidated prompt (batch phase), then execute approved actions (execute phase).

## Input & Initialization

<arguments> #$ARGUMENTS </arguments>

### Parse Arguments

The LLM reads `<arguments>` and determines:

1. **Abandon mode** — whether `--abandon` is intended. This is semantic interpretation, not regex or substring matching. Variations like `--abandon`, `abandon`, `abandoning session`, etc. all trigger abandon mode.
2. **Post-compaction task** — any remaining text after stripping the abandon flag (if present). Unlikely in abandon mode, but don't break if provided.

### Read Config

Read `compound-workflows.local.md` for these 5 config keys. For each key: if the file doesn't exist, the key is absent, or the value is unreadable, use the default.

| Key | Default | Effect when `false` |
|-----|---------|-------------------|
| `compact_version_check` | `false` | Skip version check entirely |
| `compact_cost_summary` | `true` | Skip cost summary entirely |
| `compact_auto_commit` | `false` | N/A — this is an auto-execute toggle, not a skip toggle (see below) |
| `compact_compound_check` | `true` | Skip compound assessment entirely |
| `compact_push` | `true` | Skip push remote detection entirely |

**`compact_auto_commit` semantics:** Unlike the other 4 toggles which are skip toggles (false = step doesn't run), `compact_auto_commit` is an auto-execute toggle. When `true`: git status check still runs in the check phase, "Skip commit" does NOT appear in the batch action list, and commit executes automatically with a suggested message in the execute phase.

### Initialize Values

Run init-values.sh to get shared values:

```bash
bash ${CLAUDE_SKILL_DIR}/../../scripts/init-values.sh compact-prep
```

Read the output and track these values for use throughout: PLUGIN_ROOT, VERSION_CHECK, DATE, DATE_COMPACT, TIMESTAMP, SNAPSHOT_FILE. If init-values.sh fails or any critical value is empty, warn the user and stop.

### Generate Run ID

Generate a short run ID (e.g., 8 hex chars) for scoping state files if needed later (see Step 3).

---

## Check Phase

**NO SIDE EFFECTS on production files.** All checks run silently, collecting results for the batch prompt. Config-toggled-off checks are skipped entirely — they don't run and don't appear later.

**Check-phase failure handling:** If any check fails (e.g., `version-check.sh` errors, `ccusage` crashes, `bd` unavailable), note it as "unavailable" in the summary and omit the corresponding batch action. Do not halt or retry during the check phase — failures are informational.

**Ordering:** Checks are order-independent (all side-effect-free). Run them in whatever order is natural.

### Check A: Memory Scan

Review the conversation for memory-worthy information. Scan for:

- **Facts learned** — names, roles, relationships, financial details, confirmed data points
- **Working style observations** — editing patterns, communication preferences, questioning style
- **Terms/jargon** — new acronyms, shorthand, or project codenames
- **Decision rationale** — *why* the user chose something (the "because" clauses in their replies)
- **Corrections** — anything that contradicts existing memory (update or remove the old entry)

Read existing memory files first. Only write if there's genuinely new information.

Record: number of updates identified, which files, and a **1-2 sentence description per file** of what will be added or changed.

### Check B: Beads Check (informational only — no batch action)

If `bd` is available:

```bash
bd list --status=in_progress
```

Record: count of in-progress issues. This is display-only in the summary — no "skip beads" action in the batch. Beads require manual judgment to close or leave open.

If `bd` is not available, skip silently.

### Check C: Git Status

```bash
git status
```

Record: number of uncommitted files, brief description of what changed.

### Check D: Compound Assessment

**Skip entirely if `compact_compound_check: false`.**

Assess whether this session produced knowledge worth compounding:

- Non-obvious problem solved? (debugging insight, unexpected root cause, workaround)
- Surprising discovery about the codebase, data, or domain?
- Strategic/architectural decision with reusable rationale?
- Research that surfaced reusable findings?

Record: worthy/not-worthy. If worthy, include a 1-2 sentence summary.

### Check E: Version Check

**Skip entirely if `compact_version_check: false`.**

Run `version-check.sh` using the VERSION_CHECK path from init-values.sh:

```bash
bash <VERSION_CHECK>
```

If VERSION_CHECK is empty or the script is not found, note as "unavailable."

Record: versions match / STALE / UNRELEASED status, and the full script output for reference.

Note: The check always makes the network call (unless config-toggled off). Results are informational in the summary line. STALE/UNRELEASED findings are NOT part of the batch — they get a separate dedicated prompt in the execute phase (Section 2.3.5).

### Check F: Cost Summary (informational only — no batch action)

**Skip entirely if `compact_cost_summary: false`.**

Check if `ccusage` is installed:

```bash
which ccusage
```

If available, run:

```bash
ccusage daily --json --breakdown --since <DATE_COMPACT> --offline
```

Parse the JSON output defensively — field naming varies across ccusage versions:
- Individual items use `costUSD`
- Totals sections use `totalCost`
- Summary level uses `totalCostUSD`

Check for all three field names when extracting cost data.

**Sonnet savings estimate:** If breakdown data shows both Opus and Sonnet usage, calculate estimated savings: `sonnet_cost * 4` (what those tokens would have cost on Opus minus what they actually cost on Sonnet — Sonnet is ~5x cheaper, so savings = sonnet_cost * 4). Calculate percentage: `savings / (total_cost + savings) * 100`.

Record: cost string, savings string. Display-only in summary — no associated batch action.

If JSON parsing fails, note the raw summary output rather than erroring.

If cost data was successfully retrieved, persist the snapshot now:

```bash
bash ${CLAUDE_SKILL_DIR}/../../scripts/append-snapshot.sh "<SNAPSHOT_FILE>" "<TIMESTAMP>" <total_cost> <input_tokens> <output_tokens> [additional_key=value pairs]
```

This is non-interactive housekeeping — no user approval needed.

### Check G: Push Remote Detection

**Skip entirely if `compact_push: false`.**

```bash
git remote -v
```

Record: has_remote (boolean) — determines whether push appears in the batch.

---

## Batch Prompt

Build the consolidated prompt from check results. Only include actions for checks that ran AND produced actionable results.

**CRITICAL: Selecting = SKIP (not approve). Empty selection = proceed with all actions.**

### Summary Section (always shown)

Display the summary to provide visibility into what the checks found:

```
Session end summary:
- Memory: N updates identified
  - patterns.md: add bash heuristic discovery
  - project.md: update ka3w status
- Beads: N issues still in_progress / clean
- Git: N uncommitted files / clean
- Compound: worthy (summary) / nothing to compound    [omit line if check skipped]
- Versions: all match / STALE / UNRELEASED             [omit line if check skipped]
- Cost: today $X.XX (saved ~$Y.YY via Sonnet)          [omit line if check skipped]
```

Memory detail is important: the user is approving writes based on these descriptions, not blind counts. Show the per-file descriptions from Check A.

For config-disabled steps, show the summary line as "skipped (config)" for transparency.

### Action List — Inverted Multi-Select

Build the skip-list dynamically based on what's actionable:

| Condition | Action in batch |
|-----------|----------------|
| Memory updates identified | "Skip memory updates" |
| Uncommitted files AND `compact_auto_commit` is false | "Skip commit" |
| Compound-worthy | "Skip compound" |
| has_remote is true | "Skip push" |

**Omissions — do NOT include these in the action list:**
- If `compact_auto_commit: true`: commit doesn't appear — it auto-executes
- Steps toggled off via config: summary line shows "skipped (config)" but no batch action
- Steps with no actionable result (e.g., git clean, versions match, nothing to compound): no action in list, but summary line still shows
- Version actions are NOT in the batch — they get a separate dedicated prompt in the execute phase

**If zero actions are actionable:** Skip the AskUserQuestion entirely. Show the summary, say "Nothing to act on," and proceed directly to the Queue Task / Summary sections.

### AskUserQuestion Format

Use **AskUserQuestion**:

```
question: "[summary text above]\n\nSelect actions to SKIP (leave empty to proceed with all):"
multiSelect: true
options:
  - label: "Skip memory updates"
    description: "N files to update (file1.md, file2.md)"
  - label: "Skip commit"
    description: "N uncommitted files"
  - label: "Skip compound"
    description: "[1-2 sentence summary of what's worth capturing]"
  - label: "Skip push"
    description: "Push commits to remote"
```

Note: AskUserQuestion automatically adds an "Other" option with free-text input — do not add it to the options list manually.

### Empty Selection Confirmation

If the user submits with nothing selected (empty = proceed with all), add a single confirmation via **AskUserQuestion** (Yes/No): "Proceed with all N actions?" This prevents accidental approval from a quick Enter press.

### Free-Text Handling (when user selects "Other")

If the user selects "Other" and provides free text:
- **Best-effort interpretation** — apply reasonable judgment, not deterministic parsing
- If unambiguous (e.g., "commit with message 'fix typo'"): apply it
- If ambiguous (e.g., "just do the important stuff"): ask a single clarifying follow-up
- The per-step retry/skip/abort mechanism in the execute phase is the real safety net — if free text is misinterpreted, the user can correct at execution time
- Common free-text use case: specifying a commit message (e.g., "commit with message 'session end cleanup'")

### Batch-to-Execute Mapping

Each batch item maps to one or more execute steps:

| Batch item | Execute steps |
|------------|--------------|
| "Skip memory updates" | Step 1 (write memory updates) |
| "Skip commit" | Step 2 (commit pre-compound) only |
| "Skip compound" | Step 3 (compound) + Step 4 (commit compound docs) |
| "Skip push" | Step 6 (push) |

Skipping "compound" skips both the compound run AND its post-compound commit (one logical unit). Skipping "commit" skips only the pre-compound commit (Step 2). Step 4 (commit compound docs) is always tied to compound — if compound ran and produced output, its docs are committed regardless of the "Skip commit" selection.

### Commit Message Handling

Auto-suggest descriptive commit messages based on what changed (e.g., "docs: update memory files" for pre-compound, "docs: compound solution -- [topic]" for post-compound). The user can override via the "Other" free-text field. If `compact_auto_commit: true`, commit messages are always auto-generated.

---

## Execute Phase

Execute approved actions in **strict dependency order**. Do not reorder. Per-step retry on failure.

**Reminder: selecting = SKIP in the batch prompt. If the user selected "Skip X", do NOT execute X.**

### Step 1: Write Memory Updates

**Skip if:** user selected "Skip memory updates" OR no memory updates were identified.

Read existing memory files, apply the updates identified in Check A, and write directly to `memory/` using the **Read tool** and **Edit tool** (or **Write tool** for new files). Create parent directories as needed.

Tell the user what was updated (1-2 sentences per update, not a wall of text).

### Step 2: Commit (pre-compound)

**Skip if:** user selected "Skip commit" AND `compact_auto_commit` is false.
**Execute if:** user did NOT select "Skip commit" OR `compact_auto_commit` is true.

Re-run `git status` to get a **fresh file set** — do NOT use stale Check C results. Memory files were written in Step 1 and must be included in this commit.

- If **auto-commit** (`compact_auto_commit: true`): suggest a commit message and execute without prompting. Use the **Write tool** to write the message to `.workflows/scratch/commit-msg-compact-prep.txt`, then run `git add` for modified/new files and `git commit -F .workflows/scratch/commit-msg-compact-prep.txt`.
- If **manual**: ask the user for a message or suggest one. Use the **Write tool** to write the agreed message to `.workflows/scratch/commit-msg-compact-prep.txt`, then run `git add` for modified/new files and `git commit -F .workflows/scratch/commit-msg-compact-prep.txt`.
- If no uncommitted changes exist at this point: no-op, proceed silently.

### Step 3: Run Compound

**Skip if:** user selected "Skip compound" OR compound was not worthy.

Before pausing:
1. Create the run directory: `mkdir -p .workflows/compact-prep/<run-id>/`
2. Use the **Write tool** to write batch state to `.workflows/compact-prep/<run-id>.json` with: `{ "run_id": "<run-id>", "abandon_mode": <bool>, "approved_actions": [...], "skipped_actions": [...], "current_step": 3, "completed_steps": [<list>], "config": { <5 config keys> }, "timestamp": "<timestamp>" }`
3. Tell the user: "Running /do:compound now. Resume compact-prep after compound completes."
4. Pause — the user runs `/do:compound` separately.
5. On resume: read state file from `.workflows/compact-prep/<run-id>.json`, continue at Step 4.

### Step 4: Commit Compound Docs

**Skip if:** compound was skipped (Step 3 was skipped).

Check `git status` for new files from compound.

- If **no new files** (compound ran but produced nothing): no-op, proceed silently. Do NOT trigger retry/skip/abort.
- If **new files** and auto-commit: commit automatically with a suggested message (e.g., "docs: compound solution -- [topic]"). Use the **Write tool** to write the message to `.workflows/scratch/commit-msg-compact-prep-compound.txt`, then run `git add` for the new files and `git commit -F .workflows/scratch/commit-msg-compact-prep-compound.txt`.
- If **new files** and manual: commit with a suggested or user-provided message using the same Write-then-commit-F pattern.

### Step 5: Version Actions

**This step is NOT part of the batch prompt.** Version actions are high-impact (install new plugin, create GitHub release) and deserve explicit consent.

**Skip entirely if `compact_version_check: false`.**

Re-run `version-check.sh` to get **fresh status** (check-phase results may be stale after commits):

```bash
bash <VERSION_CHECK>
```

**If STALE:** Present a **separate dedicated AskUserQuestion**:

"Plugin is stale (installed X.Y.Z, released A.B.C). Update now?"
- **Yes** — run `claude plugin update compound-workflows@compound-workflows-marketplace`
- **No** — skip

**If UNRELEASED (source repo only):** Present a **separate dedicated AskUserQuestion**:

"Version X.Y.Z has no release. Create one now?"
- **Yes** — create local tag (`git tag vX.Y.Z`). If push was NOT skipped in the batch, also push the tag and create a release (`git push origin vX.Y.Z` then `gh release create vX.Y.Z --title "vX.Y.Z" --notes "<changelog entry>"`). If push WAS skipped, the tag stays local only. If `gh release create` fails after the tag was created, clean up the orphan tag: `git tag -d vX.Y.Z` and `git push origin :refs/tags/vX.Y.Z` (if it was pushed).
- **No** — skip

If versions match or version check is unavailable: no-op, proceed silently.

### Step 6: Push

**Skip if:** user selected "Skip push" OR has_remote is false OR `compact_push: false`.

```bash
git push -u origin HEAD
```

The `-u` flag sets upstream tracking if not already set.

### Per-Step Retry Semantics

On failure at any step (1-6), present via **AskUserQuestion**:
- **Retry** — re-attempt the failed step
- **Skip** — proceed to the next step
- **Abort** — stop executing, proceed to summary with partial results

No automatic retry — the user must explicitly choose. If user retries and it fails again, present the same three options.

**Compound is special:** Compound pauses compact-prep entirely (user runs `/do:compound` separately). If compound fails or the user cancels mid-compound, that's handled by compound's own error handling — compact-prep resumes at Step 4 regardless.

---

## Queue Post-Compaction Task

**Abandon mode:** Skip this step entirely. Do not ask about post-compaction tasks — the user isn't coming back.

**Regular mode:** If the user provided a post-compaction task in the arguments, confirm it back clearly:

> **After compaction, say `resume` and I'll:** [restate the task]

If no task was provided, ask:

> **Anything specific to pick up after compaction, or just `resume`?**

---

## Summary

Always shown in both modes. Adapt wording based on mode.

**Regular mode:**

```
Ready to compact.
- Memory: [updated X files / no updates needed / skipped]
- Beads: [N issues in_progress / clean / no beads]
- Compound: [done / nothing to compound / failed -- run manually before compacting / skipped / skipped (config)]
- Git: [clean / uncommitted -- user skipped commit / auto-committed]
- Versions: [all match / updated / released / user skipped / skipped (config)]
- Cost: [today $X.XX, saved ~$Y.YY / ccusage not installed / skipped (config)]
- After compaction: [task description / general resume]

Run /compact when ready.
```

**Abandon mode:**

```
Session captured.
- Memory: [updated X files / no updates needed / skipped]
- Beads: [N issues in_progress / clean / no beads]
- Compound: [done / nothing to compound / skipped / skipped (config)]
- Git: [clean / uncommitted -- user skipped commit / auto-committed]
- Versions: [all match / updated / released / user skipped / skipped (config)]
- Cost: [today $X.XX, saved ~$Y.YY / ccusage not installed / skipped (config)]

Session knowledge preserved. Safe to close.
```
