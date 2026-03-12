---
title: "feat: Session-end capture + compact-prep batch refactor"
type: feat
status: active
date: 2026-03-12
bead: ka3w
origin: docs/brainstorms/2026-03-12-session-end-capture-brainstorm.md
---

# Session-End Capture + compact-prep Batch Refactor

## Summary

Rewrite compact-prep from a sequential 9-step checklist with 4-5 interactive prompts into a two-phase check-then-act architecture with a single consolidated batch prompt. Add `--abandon` mode for sessions that won't be resumed. Add 5 config toggles for optional steps. Create `/do:abandon` as a thin skill alias. Add auto-detect routing in AGENTS.md for session-end language.

**Key decisions carried forward from brainstorm (see brainstorm: docs/brainstorms/2026-03-12-session-end-capture-brainstorm.md):**

1. **Check-then-act batch execution** (Decision 2) — all checks run silently first, one consolidated prompt, then execute. Inverted multi-select: user selects actions to SKIP (empty = proceed with all).
2. **Abandon mode is a flag on compact-prep** (Decision 4) — `--abandon` flag controls behavior, `/do:abandon` is a thin skill entrypoint that delegates to compact-prep. Skips queue-next-task, adapts summary. [red-team M5: clarify flag vs skill distinction]
3. **Memory writes deferred via temp files** (Decision 6) — proposed changes written to `.workflows/compact-prep/<run-id>/memory-pending/` during check phase, copied after approval. Prevents LLM drift.
4. **Per-step retry on failure** (Decision 7) — retry/skip/abort at each execute-phase step.
5. **Push gated behind remote detection** (Decision 3) — `git remote -v` check; omit if no remote.
6. **Config toggles for optional steps** (Decision 9, expanded) — 5 keys in `compound-workflows.local.md`.
7. **Auto-detect routing** (Decision 5) — inline text suggestion for `/do:abandon` with suppression after 2 ignores.

## Acceptance Criteria

- [ ] compact-prep presents ONE consolidated batch prompt instead of 4-5 sequential prompts
- [ ] `--abandon` flag skips queue-next-task and adapts summary wording
- [ ] `/do:abandon` thin skill invokes `/do:compact-prep --abandon`
- [ ] 5 config toggles respected: toggled-off steps don't appear in check phase or batch prompt
- [ ] Memory writes go to temp files during check, copied after approval
- [ ] Execute phase follows hard ordering: memory-copy → commit → compound → commit compound docs → version actions → ccusage snapshot → push
- [ ] Per-step retry (retry/skip/abort) on any execute-phase failure
- [ ] Push omitted from batch if no git remote configured
- [ ] Session-end language detection in AGENTS.md suggests `/do:abandon` inline
- [ ] Suggestion suppressed after user dismisses or ignores twice
- [ ] Free-text "Other" option in batch prompt with parsing rules
- [ ] All Tier 1 QA scripts pass
- [ ] Tier 2 semantic agents pass

## Implementation

### Phase 1: Config Toggle Infrastructure

**File:** `plugins/compound-workflows/skills/do-setup/SKILL.md`

**1.1 Add config keys to Step 8b template:**

Add 5 new keys to the `compound-workflows.local.md` template:

```
compact_version_check: false
compact_cost_summary: true
compact_auto_commit: false
compact_compound_check: true
compact_push: true
```

Defaults: all enabled (preserves current behavior) except `compact_auto_commit` (defaults `false`, opt-in to auto-execute) and `compact_version_check` (defaults `false` — only relevant to plugin developers, not regular users).

- [ ] Add keys to Step 8b template in do-setup SKILL.md
- [ ] Add migration logic in Step 8d: first check file exists (`touch compound-workflows.local.md` or `[ -f ... ]` guard), then for each of the 5 keys, `grep -q 'key_name:' compound-workflows.local.md`. If absent, append `key_name: <default>` at end of file. Handle each key independently (partial presence expected during migration). Defaults: `compact_version_check: false`, `compact_cost_summary: true`, `compact_auto_commit: false`, `compact_compound_check: true`, `compact_push: true` [red-team M1: config file may not exist]
- [ ] Add keys to reference skill (`plugins/compound-workflows/skills/setup/SKILL.md`) Step 8b template and migration. Note: this is a separate skill from do-setup — it provides reference material and has its own config template that must be kept in sync manually (see plugin CLAUDE.md "Setup: Three-Way Relationship")

**1.2 Document config reading pattern in compact-prep:**

Config keys are read via `Read compound-workflows.local.md` at the start of compact-prep. For each key: if present, use its value; if absent, use the default. Most keys default to `true` (enabled) when missing. Exceptions: `compact_auto_commit` defaults to `false` (opt-in auto-execute) and `compact_version_check` defaults to `false` (only relevant to plugin developers). This follows the existing `stats_capture` convention where missing = enabled, with documented exceptions for keys where the default should be off.

### Phase 2: Rewrite compact-prep SKILL.md

**File:** `plugins/compound-workflows/skills/do-compact-prep/SKILL.md`

This is the core change — restructuring from 9 sequential steps into a two-phase (check → execute) architecture with a batch prompt in between.

#### 2.0 Input & Initialization

- [ ] Parse `#$ARGUMENTS` for `--abandon` flag (LLM-interpreted — the LLM reads the argument string and understands the intent semantically, not via regex or substring matching)
- [ ] Read `compound-workflows.local.md` for all 5 config toggle keys
- [ ] Run `init-values.sh compact-prep` to get PLUGIN_ROOT, VERSION_CHECK, DATE, DATE_COMPACT, TIMESTAMP, SNAPSHOT_FILE
- [ ] Generate a run ID and create run directory: `mkdir -p .workflows/compact-prep/<run-id>/memory-pending/`

**Flag detection:** The LLM reads `$ARGUMENTS` and determines whether abandon mode is intended. This is semantic interpretation, not bash parsing — no regex or token-boundary detection needed. Strip `--abandon` from arguments to get the remaining post-compaction task (if any — unlikely in abandon mode, but don't break if provided).

#### 2.1 Check Phase

All checks run with no side effects on production files (temp writes to `.workflows/scratch/` are permitted). Results are collected for the batch prompt. Config-toggled-off steps are skipped entirely — they don't run and don't appear later.

**Check A: Memory scan**
- Review conversation for memory-worthy information. Scan for:
  - **Facts learned** — names, roles, relationships, financial details, confirmed data points
  - **Working style observations** — editing patterns, communication preferences, questioning style
  - **Terms/jargon** — new acronyms, shorthand, or project codenames
  - **Decision rationale** — *why* the user chose something (the "because" clauses in their replies)
  - **Corrections** — anything that contradicts existing memory (update or remove the old entry)
- Read existing memory files first. Only write if there's genuinely new information.
- For each proposed update: create parent directories if needed (`mkdir -p` for the temp file's parent dir), then write the **complete new file content** to `.workflows/compact-prep/<run-id>/memory-pending/<path>` (mirror the target path structure — e.g., `memory/patterns.md` → `memory-pending/patterns.md`, `memory/sub/file.md` → `memory-pending/sub/file.md`). Do NOT write to `memory/`. [red-team--gemini: handle nested memory paths]
- Record: number of updates identified, which files, **abbreviated diff per file** showing key additions/removals (these diffs appear in the batch prompt so the user can review the actual changes they're approving, not just descriptions) [red-team--opus S3: show diffs not just descriptions]

**Check B: Beads check** (informational only — no batch action)
- If `bd` available: run `bd list --status=in_progress`
- Record: count of in-progress issues. This is display-only in the summary — no "skip beads" action in the batch. The user is warned but there's no automated fix (beads require manual judgment to close or leave open).

**Check C: Git status**
- Run `git status`
- Record: number of uncommitted files, brief description

**Check D: Compound assessment** (skip if `compact_compound_check: false`)
- Assess whether this session produced knowledge worth compounding:
  - Non-obvious problem solved? (debugging insight, unexpected root cause, workaround)
  - Surprising discovery about the codebase, data, or domain?
  - Strategic/architectural decision with reusable rationale?
  - Research that surfaced reusable findings?
- Record: worthy/not-worthy, 1-2 sentence summary if worthy

**Check E: Version check** (skip if `compact_version_check: false`)
- Run `version-check.sh` (uses VERSION_CHECK from init-values.sh — init-values.sh always runs in 2.0 regardless of this toggle since it provides DATE/TIMESTAMP/etc.)
- Record: versions match / STALE / UNRELEASED status
- The check always makes the network call (unless config-toggled off). Results are informational in the summary line. STALE/UNRELEASED findings generate actionable items in the batch prompt (user can skip acting on them).

**Check F: Cost summary** (skip if `compact_cost_summary: false`; informational only — no batch action)
- Check ccusage availability, run `ccusage daily --json --breakdown --since DATE_COMPACT --offline`
- Parse defensively (costUSD / totalCost / totalCostUSD field names)
- Calculate Sonnet savings if breakdown available
- Record: cost string, savings string. Display-only in summary — no associated batch action.

**Check-phase failure handling:** If any check fails (e.g., `version-check.sh` errors, `ccusage` crashes, `bd` unavailable), note it as "unavailable" in the summary and omit the corresponding batch action. Do not halt or retry during the check phase — failures are informational. Example: `- Versions: unavailable (version-check.sh failed)`.

**Check G: Push remote detection** (skip if `compact_push: false`)
- Run `git remote -v`
- Record: has_remote (boolean) — determines whether push appears in batch

**Ordering:** Check phase is order-independent (all side-effect-free). Memory scan writes to temp files only. Run checks in whatever order is natural for the LLM.

#### 2.2 Batch Prompt

Build the consolidated prompt from check results. Only include actions for checks that ran AND produced actionable results.

**Summary section** (always shown — provides visibility into what the checks found):

```
Session end summary:
- Memory: N updates identified
  - patterns.md: +2 lines (bash heuristic discovery), -0 lines
  - project.md: ~3 lines changed (ka3w status → plan phase)
- Beads: N issues still in_progress / clean
- Git: N uncommitted files / clean
- Compound: worthy (summary) / nothing to compound    [omit line if check skipped]
- Versions: all match / STALE / UNRELEASED             [omit line if check skipped]
- Cost: today $X.XX (saved ~$Y.YY via Sonnet)          [omit line if check skipped]
```

Memory detail is important: the user is approving writes based on these descriptions, not blind counts. Show the per-file descriptions from Check A.

**Action list** — inverted multi-select AskUserQuestion:

Build the skip-list dynamically based on what's actionable:

| Condition | Action in batch |
|-----------|----------------|
| Memory updates identified | "Skip memory updates" |
| Uncommitted files AND `compact_auto_commit` is false | "Skip commit" |
| Compound-worthy | "Skip compound" (includes compound + its commit as one unit) |
| ~~STALE version~~ | ~~removed from batch~~ — separate dedicated prompt (see 2.3.5a) |
| ~~UNRELEASED version~~ | ~~removed from batch~~ — separate dedicated prompt (see 2.3.5a) |
| has_remote is true | "Skip push" |

**Omissions:**
- If `compact_auto_commit: true`: commit doesn't appear in the action list — it auto-executes in the execute phase
- Steps toggled off via config: summary line shows "skipped (config)" for transparency, but no action appears in the batch list [red-team S4: marked skipped, not hidden]
- Steps with no actionable result (e.g., git clean, versions match): no action in list, but summary line still shows

**If zero actions are actionable:** Skip the AskUserQuestion entirely. Show the summary, say "Nothing to act on," and proceed directly to Section 2.4 (queue task) / 2.5 (summary).

**AskUserQuestion format:**

```
Use **AskUserQuestion**:
question: "[summary text above]\n\nSelect actions to SKIP (leave empty to proceed with all):"
multiSelect: true
options:
  - label: "Skip memory updates"
    description: "N files to update (file1.md, file2.md)"
  - label: "Skip commit"
    description: "N uncommitted files"
  - label: "Skip compound"
    description: "[1-2 sentence summary]"
  - label: "Skip push"
    description: "Push commits to remote"
```

Note: AskUserQuestion automatically adds an "Other" option with free-text input — do not add it to the options list manually.

**Empty selection confirmation:** If the user submits with nothing selected (empty = proceed with all), add a single confirmation: "Proceed with all N actions?" via AskUserQuestion (Yes/No). This prevents accidental approval from a quick Enter press. [red-team S7: inverted multi-select UX safety]

**Free-text handling (when user selects "Other"):**
If the user selects "Other" and provides free text:
- **Best-effort interpretation** — the LLM applies reasonable judgment, not deterministic parsing [red-team M6: free-text parsing is inherently unreliable]
- If unambiguous (e.g., "commit with message 'fix typo'"): apply it
- If ambiguous (e.g., "just do the important stuff"): ask a single clarifying follow-up
- The per-step retry/skip/abort mechanism in the execute phase is the real safety net — if the LLM misinterprets free text, the user can correct at execution time
- Common free-text use case: specifying a commit message (e.g., "commit with message 'session end cleanup'")

**Batch-to-execute mapping:** Each batch item maps to one or more execute steps. The batch prompt shows the user-facing decision; the execute phase handles implementation details:

| Batch item | Execute steps |
|------------|--------------|
| "Skip memory updates" | Step 1 (copy temp files) |
| "Skip commit" | Step 2 (commit pre-compound) only |
| "Skip compound" | Step 3 (compound) + Step 4 (commit compound docs) |
| "Skip plugin update" | Step 5 (STALE update) |
| "Skip release" | Step 5 (UNRELEASED release) |
| "Skip push" | Step 7 (push) |

Skipping "compound" skips both the compound run AND its post-compound commit (one logical unit). Skipping "commit" skips only the pre-compound commit (Step 2). Step 4 (commit compound docs) is always tied to compound — if compound ran and produced output, its docs are committed regardless of the "Skip commit" selection.

**Commit message handling:** The LLM auto-suggests descriptive commit messages based on what changed (e.g., "docs: update memory files" for pre-compound, "docs: compound solution — [topic]" for post-compound). The user can override via the "Other" free-text field. If `compact_auto_commit: true`, commit messages are always auto-generated.

#### 2.3 Execute Phase

Execute approved actions in hard dependency order. Per-step retry on failure.

**Execution ordering (strict — do not reorder):**

1. **Copy memory temp files** — if memory updates approved:
   - Copy each file from `.workflows/compact-prep/<run-id>/memory-pending/<filename>` to `memory/<filename>`
   - Tell the user what was updated (1-2 sentences per update)

2. **Commit (pre-compound)** — if commit approved OR `compact_auto_commit: true`:
   - Re-run `git status` (fresh, not stale Check C results — memory files were copied in step 1 and must be included) [red-team--openai: stale file set fix]
   - Stage all modified tracked files from the fresh status, commit
   - If auto-commit: suggest a commit message and execute without prompting
   - If manual: ask for message or suggest one

3. **Run compound** — if compound approved:
   - Write batch state to `.workflows/compact-prep/<run-id>.json` (approved actions, current step = 3, config, abandon flag)
   - Tell user: "Running /do:compound now. Resume compact-prep after compound completes."
   - Pause — user runs `/do:compound`
   - On resume: read state file from `.workflows/compact-prep/<run-id>.json`, continue at step 4

4. **Commit compound docs** — if compound ran:
   - Check `git status` for new files from compound
   - If no new files (compound ran but produced nothing): no-op, proceed silently — do NOT trigger retry/skip/abort
   - If new files and auto-commit: commit automatically
   - If new files and manual: commit (already approved via "don't skip commit")

5. **Version actions** — NOT part of the batch. Re-run `version-check.sh` to get fresh status (check-phase results may be stale) [red-team M7: re-verify before acting]. If version check finds STALE or UNRELEASED, present a **separate dedicated AskUserQuestion** at this point in the execute phase:

   **If STALE:** "Plugin is stale (installed X.Y.Z, released A.B.C). Update now?"
   - Yes → run `claude plugin update compound-workflows@compound-workflows-marketplace`
   - No → skip

   **If UNRELEASED (source repo only):** "Version X.Y.Z has no release. Create one now?"
   - Yes → create local tag (`git tag vX.Y.Z`). If push was NOT skipped, also push and release. If push was skipped, tag stays local. If `gh release create` fails after tag was created, clean up the orphan tag (`git tag -d vX.Y.Z` + `git push origin :refs/tags/vX.Y.Z` if pushed). [red-team--openai: release flow respects push gate] [red-team M11: rollback partial version actions]
   - No → skip

   **Why separated from batch:** Version actions are high-impact (install new plugin, create GitHub release) and deserve explicit consent, not batch-defaulting via inverted selection. [red-team--opus: accidental releases in abandon mode]

6. **Persist ccusage snapshot** — if cost summary ran and succeeded (non-interactive, no batch action):
   - Run `append-snapshot.sh` — this is a background housekeeping step that always runs if data is available
   - Placed in execute phase (not check phase) to respect the "no side effects during check" principle, even though it's non-user-facing

7. **Push** — if push approved:
   - Run `git push -u origin HEAD` (sets upstream tracking if not already set) [red-team M2: handle branches with no upstream]

**Per-step retry semantics:**
On failure at any step, present:
- **Retry** — re-attempt the failed step
- **Skip** — proceed to next step
- **Abort** — stop executing, proceed to summary with partial results

**Compound is special:** Compound pauses compact-prep entirely (user runs `/do:compound` separately). If compound fails or user cancels mid-compound, that's handled by compound's own error handling — compact-prep resumes at step 4 regardless.

#### 2.4 Queue Post-Compaction Task (Step 8)

**Regular mode:** Same as current behavior — confirm task back to user or ask for one.

**Abandon mode:** Skip this step entirely. Do not ask about post-compaction tasks — the user isn't coming back.

#### 2.5 Summary (Step 9)

Always shown in both modes. Adapt wording:

**Regular mode:**
```
Ready to compact.
- Memory: [updated X files / no updates needed / skipped]
- Beads: [N issues in_progress / clean / no beads]
- Compound: [done / nothing to compound / failed — run manually before compacting / skipped / skipped (config)]
- Git: [clean / uncommitted — user skipped commit / auto-committed]
- Versions: [all match / updated / released / user skipped / skipped (config)]
- Cost: [today $X.XX, saved ~$Y.YY / ccusage not installed / skipped (config)]
- After compaction: [task description / general resume]

Run /compact when ready.
```

**Abandon mode:**
```
Session captured.
- Memory: [updated X files / no updates needed]
- Beads: [N issues in_progress / clean / no beads]
- Compound: [done / nothing to compound / skipped (config)]
- Git: [clean / uncommitted — user skipped commit]
- Versions: [all match / updated / released / user skipped / skipped (config)]
- Cost: [today $X.XX, saved ~$Y.YY / ccusage not installed / skipped (config)]

Session knowledge preserved. Safe to close.
```

#### 2.6 Frontmatter updates

Update SKILL.md frontmatter:
```yaml
name: do:compact-prep
description: Prepare for context compaction — save memory, commit, queue next task
argument-hint: "[--abandon] [optional: task to resume after compaction]"
```

### Phase 3: Create /do:abandon Thin Skill

**File:** `plugins/compound-workflows/skills/do-abandon/SKILL.md` (NEW)

```yaml
---
name: do:abandon
description: Capture session knowledge before abandoning — runs compact-prep in abandon mode
argument-hint: ""
---
```

Body (~15-20 lines):

```markdown
# /abandon — Capture session knowledge before closing

> This is a thin wrapper around `/do:compact-prep --abandon`.

Invoke `/do:compact-prep --abandon` immediately with any user arguments appended.

Abandon mode runs the full compact-prep checklist (memory, beads, git, compound, versions, cost)
but skips queuing a post-compaction task — the session won't be resumed.

Do not add any logic beyond this delegation.
```

No `allowed-tools` or model specifications needed — compact-prep handles its own tools. Pass through any additional arguments after `--abandon`.

**Divergence from brainstorm:** Decision 4 specified a thin alias command in `commands/compound/`. Changed to a skill because research found the 8-command registration cap in `commands/compound/` — adding a 9th risks silent loss. [red-team S6: document divergence for traceability]

- [ ] Create skills/do-abandon/SKILL.md
- [ ] Verify skill frontmatter matches plugin conventions

### Phase 4: Auto-Detect Routing

**File:** `AGENTS.md` (root)

**4.1 Add /do:abandon to routing table:**

Add entry after the existing compact-prep line:
```
- **Abandoning a session** ("done for today", "wrapping up for the day", "closing out", "ending the session"): `/do:abandon` — do not just close the terminal
```

**4.2 Add auto-detect inline suggestion instruction:**

Add as a **separate subsection** under Routing (not mixed into the imperative routing list). This is a soft suggestion, not a hard route — the LLM must not block user actions or force `/do:abandon`:

```markdown
### Session-End Detection

When you detect session-end language ("done for today", "wrapping up for the day", "closing out",
"ending the session", "abandoning"), add an inline text suggestion: [red-team M10: dropped "I'm done" and "that's all" — too ambiguous, fire on task completion]

> Tip: run `/do:abandon` to capture session knowledge before closing.

**This is a suggestion, not a gate.** Do not ask, do not block, do not repeat if the user continues working.

**Suppression rules:**
- Suppress after the user dismisses it or ignores it twice in the same session (track in conversation context)
- Ambiguous phrases ("I'm done", "that's all") excluded from triggers — they fire on task completion, creating cry-wolf pattern [red-team M10]
- If the user says "stop suggesting /abandon", stop immediately for the remainder of the session
```

**Suppression tracking:** The LLM tracks ignore count in conversation context (no persistent file). This degrades after compaction, but that's acceptable — compaction implies the user ran compact-prep, so the suggestion is no longer relevant anyway.

**4.3 Update do-setup canonical routing (Step 8c):**

**File:** `plugins/compound-workflows/skills/do-setup/SKILL.md`

Copy the exact text from Phase 4.1 (routing entry) and Phase 4.2 (session-end detection subsection) into do-setup Step 8c's canonical routing template, after the existing routing entries. The text is identical — no adaptation needed for the setup context.

- [ ] Add /do:abandon routing entry to AGENTS.md
- [ ] Add session-end detection section to AGENTS.md
- [ ] Update do-setup Step 8c canonical routing

### Phase 5: Plugin Manifests

- [ ] Bump version in `plugins/compound-workflows/.claude-plugin/plugin.json` (MINOR — new skill. Read current version, increment middle number, reset patch to 0)
- [ ] Bump version in `.claude-plugin/marketplace.json`
- [ ] Update `plugins/compound-workflows/CHANGELOG.md`
- [ ] Update `plugins/compound-workflows/README.md` — verify skill count (new: do-abandon)
- [ ] Update `plugins/compound-workflows/CLAUDE.md` — add do-abandon to skills directory listing, update do-compact-prep description

### Phase 6: QA

- [ ] Run `/compound-workflows:plugin-changes-qa` (both tiers)
- [ ] Verify all Tier 1 scripts pass (especially file-counts.sh after adding new skill)
- [ ] Verify Tier 2 semantic agents pass
- [ ] Manual test: run `/do:compact-prep` in a test session, verify single batch prompt
- [ ] Manual test: run `/do:abandon`, verify Step 8 skipped
- [ ] Manual test: set `compact_version_check: false`, verify version check omitted from batch
- [ ] Manual test: set `compact_auto_commit: true`, verify commit auto-executes

## Design Notes

### compact_auto_commit semantics

Unlike the other 4 toggles which are skip toggles (false = step doesn't run), `compact_auto_commit` is an auto-execute toggle (true = step runs automatically without appearing in the batch prompt). When enabled:
- Git status check still runs in the check phase (to detect uncommitted changes)
- "Skip commit" does NOT appear in the batch action list
- In the execute phase, commit executes automatically with a suggested message
- The summary shows the commit result

Default is `false` (opt-in) because auto-committing is a stronger behavior change than skipping informational steps.

### Compound pause-and-resume

Compound is the one execute-phase step that can't be fully automated within compact-prep. When the user approves compound:
1. compact-prep writes batch approval state to `.workflows/compact-prep/<run-id>.json` (approved actions, current step index, config toggles, abandon mode flag)
2. compact-prep tells the user to run `/do:compound`
3. The user runs compound (which has its own multi-step flow)
4. After compound completes, compact-prep reads the state file and resumes at the correct step deterministically

**State file schema:** `{ "run_id": "<id>", "abandon_mode": bool, "approved_actions": [...], "skipped_actions": [...], "current_step": 4, "completed_steps": [1, 2, 3], "config": { ... }, "timestamp": "..." }`

The state file persists to `.workflows/compact-prep/` (not `scratch/`) because it has analytics value — run-ID-scoped compact-prep execution records can be mined for workflow timing and behavior patterns.

**State file lifecycle:** Written at the start of the execute phase (after batch approval). Updated after each step completes. Read on resume after compound. Retained after completion for analytics (not cleaned up).

### /do:abandon as skill vs command

The brainstorm originally specified a thin alias command in `commands/compound/`. Research found the 8-command registration cap in `commands/compound/` — adding a 9th risks silent loss. Resolved by making `/do:abandon` a thin skill instead, which:
- Avoids the command cap entirely
- Fits the `do:` namespace naturally
- Is discoverable via `/do:abandon` (same as other workflow skills)
- No backwards-compat alias needed (it's new)

### Config toggle interaction with batch prompt

When a config toggle disables a step:
1. The check phase skips that check entirely (no work done)
2. The summary marks the line as "skipped (config)" for transparency — the user sees it was suppressed and why [red-team S4: marked skipped, not hidden]
3. The batch action list doesn't include that step's action (nothing to skip or approve)
4. The execute phase has nothing to execute for that step

### Temp file naming and cleanup

**Naming convention:** Temp files live under the run-ID-scoped directory: `.workflows/compact-prep/<run-id>/memory-pending/`. Files mirror target paths — `memory/patterns.md` → `memory-pending/patterns.md`. Temp files contain **complete new file content** (full replacement, not diffs) — the execute phase copies them via simple file copy. [red-team S8: scoped under run-ID, not flat scratch directory]

**Startup:** At the start of the check phase (step 2.0), generate a run ID and create the run directory: `mkdir -p .workflows/compact-prep/<run-id>/memory-pending/`. No cleanup of prior runs needed — each run gets its own scoped directory.

**Lifecycle:** The run directory (`.workflows/compact-prep/<run-id>/`) contains both the batch state file and memory temp files. It is retained after completion for analytics value (see "Compound pause-and-resume" section). No separate cleanup step is needed — the directory doesn't leak because it's scoped and intentionally kept.

## Risk Analysis

| Risk | Mitigation |
|------|------------|
| LLM fails to follow two-phase architecture (runs actions during check phase) | Explicit "NO SIDE EFFECTS" instruction at check phase header. Memory writes go to temp dir as structural enforcement. |
| LLM ignores inverted selection (treats selections as approvals instead of skips) | Defensive redundancy: repeat "selecting = SKIP, empty = proceed with all" at the prompt and in the execute-phase header. |
| `--abandon` flag not detected in arguments | LLM-interpreted (semantic, not regex). Robust to natural language variation. |
| Config key missing from local config | Missing = default (enabled, except auto_commit = disabled). Follows existing convention. |
| Compound pause-and-resume breaks batch flow | Compound is structurally isolated — it pauses compact-prep entirely. Same pattern as current design, well-tested. |
| Per-step retry creates infinite retry loops | No automatic retry — user must explicitly choose "Retry." If user retries and it fails again, same three options presented. User can always choose "Skip" or "Abort." |

### init-values.sh context argument

Both regular and abandon mode pass `compact-prep` to `init-values.sh`. The context argument affects stats file naming and any context-dependent behavior. Abandon mode is compact-prep, just with a flag — not a different command. No distinction needed.

## Specflow Resolution Summary

Specflow analysis identified 27 gaps and 12 questions. Resolutions incorporated into the plan above:

| # | Gap/Question | Resolution |
|---|-------------|------------|
| Q1 | Config key list | All 5 in scope. Defaults specified in Phase 1.1. |
| Q2 | Skill vs command | Skill at `skills/do-abandon/` — avoids 8-command cap. |
| Q3 | Batch-to-execute mapping | Table added in Phase 2.2. Compound + its commit = one unit. |
| Q4 | auto_commit default | `false` (opt-in). Missing key = false. |
| Q5 | Commit messages | LLM auto-suggests. Override via "Other" free text. |
| Q6 | Abandon mode + version check | Runs unless config-toggled off. Not implicitly skipped. |
| Q7 | Memory visibility in batch | Per-file descriptions in summary (not blind counts). |
| Q8 | Routing format | Separate "Session-End Detection" subsection. Soft suggestion, not imperative. |
| Q9 | Temp file cleanup | Run-ID-scoped directory (`.workflows/compact-prep/<run-id>/memory-pending/`). Retained for analytics. |
| Q10 | Check-phase failures | Note as "unavailable" in summary, omit batch action. |
| Q11 | Empty batch | Skip AskUserQuestion, show "Nothing to act on." |
| Q12 | auto_commit timing | Execute phase (after batch approval), not before. |
| Gap 1 | Batch item count | 4-6 items depending on findings. Compound = one unit. |
| Gap 3 | Beads informational | Explicitly display-only, no batch action. |
| Gap 5 | Compound no output | No-op, no retry prompt. |
| Gap 14 | Suppression tracking | Conversation context (degrades after compaction — acceptable). |
| Gap 16 | Three routing locations | Phase 4 covers AGENTS.md + do-setup Step 8c. Plugin CLAUDE.md auto-derives from AGENTS.md. |
| Gap 18-19 | Temp file naming | Mirror target filenames. Full content, not diffs. |
| Gap 20 | Check-phase failures | Handled gracefully — note unavailable, omit batch action. |
| Gap 25 | init-values context | Always `compact-prep` in both modes. |
| Gap 26 | Stats capture placement | Execute phase (after batch approval). |

*Full specflow analysis: `.workflows/plan-research/session-end-capture-batch-refactor/agents/specflow.md`*

## Red Team Resolution Summary

Three-provider red team (Gemini, OpenAI, Opus). All findings resolved:

| # | Rating | Finding | Resolution |
|---|--------|---------|------------|
| C1 | CRITICAL | Compound pause-and-resume loses batch state | Persist to `.workflows/compact-prep/<run-id>.json` |
| C2 | CRITICAL | Release pushes tags when Skip push selected | Gate all network ops behind Skip push |
| C3 | CRITICAL | Commit stages stale file set (before memory copy) | Re-run git status before each commit |
| C4 | CRITICAL | Nested memory file paths fail mkdir | mkdir -p parent dirs per file |
| S1 | SERIOUS | Config toggles overengineered | Keep all 5 (user decision) |
| S2 | SERIOUS | Version actions dangerous in abandon mode | Dedicated prompt in both modes (not batch) |
| S3 | SERIOUS | Memory scan quality ungoverned | Show abbreviated diffs in batch prompt |
| S4 | SERIOUS | Config-disabled summary behavior contradiction | Marked "skipped (config)" for transparency |
| S5 | SERIOUS | --abandon parsing naive substring | LLM-interpreted, no regex needed |
| S6 | SERIOUS | /abandon command→skill divergence undocumented | Added divergence note in Phase 3 |
| S7 | SERIOUS | Inverted multi-select UX (empty = approve all) | Confirmation prompt on empty selection |
| S8 | SERIOUS | Temp directory cleanup missing | Scoped under run-ID directory; no separate cleanup needed |

| M1 | MINOR | Config file may not exist during migration | touch/existence check before grep |
| M2 | MINOR | Git push fails with no upstream branch | Use `git push -u origin HEAD` |
| M3 | MINOR | Inline suggestion ignore-count unreliable | Acceptable — best-effort, not safety-critical |
| M4 | MINOR | Ship in slices | No action — contradicts prior user decisions |
| M5 | MINOR | "Flag, not skill" wording confusing | Rephrased key decision #2 |
| M6 | MINOR | Free-text "Other" parsing unenforceable | Downgraded to best-effort; retry/skip/abort is safety net |
| M7 | MINOR | Execute phase acts on stale version-check data | Re-run version-check.sh before version actions |
| M8 | MINOR | AskUserQuestion "Other" auto-add unverified | Verified — it does auto-add. No action |
| M9 | MINOR | do-setup migration details terse | Adequate as-is (Opus concurs). No action |
| M10 | MINOR | Session-end detection triggers too broadly | Narrowed phrases; dropped "I'm done"/"that's all" |
| M11 | MINOR | No rollback for partial version actions | Delete orphan tag if release fails |
| M12 | MINOR | Premature "no open questions" claim | Fixed — added Red Team Resolution Summary |

*Full red team outputs: `.workflows/plan-research/session-end-capture-batch-refactor/red-team--{gemini,openai,opus}.md`*

## Open Questions

None — all questions resolved during brainstorm, specflow, and red team phases.

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-03-12-session-end-capture-brainstorm.md` — 9 decisions, 3-provider red team, all items resolved. Key decisions: check-then-act batch (D2), abandon as flag (D4), deferred memory writes (D6), per-step retry (D7), config toggles (D9).
- **Research:** `.workflows/plan-research/session-end-capture-batch-refactor/agents/repo-research.md` — current compact-prep structure, AskUserQuestion patterns, thin alias conventions, config reading patterns.
- **Learnings:** `.workflows/plan-research/session-end-capture-batch-refactor/agents/learnings.md` — command registration cap (8 commands in compound/), inverted selection constraint, execute-phase ordering, memory drift risk.
- **Specflow:** `.workflows/plan-research/session-end-capture-batch-refactor/agents/specflow.md` — 27 gaps, 12 questions. All resolved (see Specflow Resolution Summary).
- **Related bead:** 4a1o — Plugin-wide config toggles for skippable steps and gates (extends ka3w's config pattern to other commands).
