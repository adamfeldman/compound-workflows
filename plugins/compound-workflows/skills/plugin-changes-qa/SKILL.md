---
name: plugin-changes-qa
description: Run QA checks on the compound-workflows plugin
disable-model-invocation: true
---

# Plugin Changes QA

Run hybrid QA checks on the compound-workflows plugin: deterministic Tier 1 bash scripts for structural validation, followed by Tier 2 LLM agents for semantic analysis.

**Findings are informational.** Bead tracking operations require explicit user confirmation.

## Phase 1: Tier 1 (Deterministic Scripts)

Discover and run all bash scripts in the plugin-qa directory. These are fast, deterministic checks that validate structural properties.

### Step 1.1: Resolve Plugin Root

```bash
# Find plugin root: local repo (dev) or installed plugin
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PLUGIN_ROOT="$REPO_ROOT/plugins/compound-workflows"
if [[ ! -f "$PLUGIN_ROOT/CLAUDE.md" ]]; then
  PLUGIN_ROOT=$(find "$HOME/.claude/plugins" -name "CLAUDE.md" -path "*/compound-workflows/*" -exec dirname {} \; 2>/dev/null | head -1)
fi
echo "Plugin root: $PLUGIN_ROOT"
ls "$PLUGIN_ROOT/CLAUDE.md" 2>/dev/null && echo "VALID" || echo "NOT FOUND"
```

If the plugin root is not found, report the error and stop.

### Step 1.2: Discover and Run Scripts

```bash
ls "$PLUGIN_ROOT/scripts/plugin-qa"/*.sh
```

Run each `.sh` script via the Bash tool, passing the plugin root path as the first argument:

```bash
bash "$PLUGIN_ROOT/scripts/plugin-qa/<script>.sh" "$PLUGIN_ROOT"
```

**Error handling:**
- If a script exits 1 (script error): note the error, continue with remaining scripts
- If a script exits 0 with findings: collect the output (scripts always exit 0 for findings)
- Run all scripts regardless of individual failures

Collect all script outputs for Phase 3 aggregation.

## Phase 2: Tier 2 (Semantic Agents)

Dispatch three LLM agents in parallel for semantic analysis that bash scripts cannot perform. All agents use the disk-persist pattern.

**Important:** In the Task prompts below, substitute `$PLUGIN_ROOT` with the value resolved in Step 1.1.

### Step 2.1: Create Output Directory

```bash
mkdir -p .workflows/plugin-qa/agents/
```

### Step 2.2: Launch Agents (Parallel, Disk-Persisted)

Launch all three agents in a single message with `run_in_background: true`:

**Agent A: Context-Lean Reviewer**

```
Task general-purpose (run_in_background: true): "
You are a context-lean compliance reviewer for the compound-workflows plugin.

Read ALL command files in: $PLUGIN_ROOT/commands/compound/

For each command file, verify:
1. **No large agent returns in orchestrator context** — every Task dispatch must include OUTPUT INSTRUCTIONS that direct the agent to write to disk and return only a 2-3 sentence summary
2. **MCP calls wrapped in subagents** — any mcp__pal__clink or mcp__pal__chat call must be inside a Task block, never called directly by the orchestrator
3. **OUTPUT INSTRUCTIONS present** — every Task dispatch (except trivial inline tasks) must have an === OUTPUT INSTRUCTIONS (MANDATORY) === block
4. **TaskOutput is banned** — no command should instruct the orchestrator to call TaskOutput; file-existence polling is the correct pattern
5. **Disk-persist pattern used** — agents write to .workflows/ directories, orchestrator reads from disk

**Severity guide:**
- CRITICAL: data flows through orchestrator context (MCP response not wrapped, full agent output returned)
- SERIOUS: missing OUTPUT INSTRUCTIONS on a background Task, TaskOutput usage
- INFO: style observations that are not functional violations

**Known by-design patterns (do NOT flag as violations):**
- Foreground Task dispatches that delegate to agent .md files for output instructions — this is a DRY pattern, the agent file contains the instructions
- Summary format variations (e.g., 5 bullet points vs 2-3 sentences) — informational at most (INFO), not a violation
- Lines marked with `context-lean-exempt` — explicitly excluded from checks

For each violation found, report:
- File path
- Line number or section
- What the violation is
- Severity (using the guide above)

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write your COMPLETE findings to: .workflows/plugin-qa/agents/context-lean-review.md
Structure with: ## Summary, ## Findings (grouped by file), ## Recommendations
After writing the file, return ONLY a 2-3 sentence summary.
DO NOT return your full analysis in your response.
"
```

**Agent B: Role Description Reviewer**

```
Task general-purpose (run_in_background: true): "
You are a role description consistency reviewer for the compound-workflows plugin.

Read the agent registry in: $PLUGIN_ROOT/CLAUDE.md
Read all agent definition files in: $PLUGIN_ROOT/agents/

Then read all command files in: $PLUGIN_ROOT/commands/compound/
And all skill files matching: $PLUGIN_ROOT/skills/*/SKILL.md

For each Task dispatch in commands and skills, verify:
1. **Agent name matches** — the Task dispatch references a valid agent from the registry
2. **Role description is accurate** — the inline role description in the Task dispatch matches the agent definition file's description
3. **Allowed-tools consistency** — if the agent definition specifies allowed tools, the Task dispatch does not ask the agent to use tools outside that set
4. **Model specification** — if the agent definition specifies a model override (e.g., haiku), verify it is respected in the dispatch
5. **Agent existence** — flag any Task dispatches referencing agents that do not have definition files

**Severity guide:**
- SERIOUS: wrong agent name, missing agent definition, incompatible tools, wrong model
- INFO: inline role description drift (simplified/paraphrased descriptions are expected — commands use inline descriptions for graceful fallback, not exact copies of agent definitions)

**Important:** Inline role descriptions are intentionally simplified summaries, not verbatim copies. A paraphrased or shortened description is expected by-design. Only flag as SERIOUS if the description is factually wrong or describes a different agent's purpose.

For each mismatch found, report:
- Command/skill file and the agent being dispatched
- What the mismatch is (expected vs actual)
- Severity (using the guide above)

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write your COMPLETE findings to: .workflows/plugin-qa/agents/role-description-review.md
Structure with: ## Summary, ## Findings (grouped by agent), ## Recommendations
After writing the file, return ONLY a 2-3 sentence summary.
DO NOT return your full analysis in your response.
"
```

**Agent C: Command Completeness Reviewer**

```
Task general-purpose (run_in_background: true): "
You are a command completeness and conventions reviewer for the compound-workflows plugin.

Read ALL command files in: $PLUGIN_ROOT/commands/compound/
Read the Command Conventions section in: $PLUGIN_ROOT/CLAUDE.md

For each command file, verify:
1. **AskUserQuestion usage** — commands must use AskUserQuestion (the tool) for user interaction, never raw conversational questions without the tool
2. **Phase/step numbering** — verify commands have clear phase and step numbering (Phase 1, Step 1.1, etc.) with no gaps or duplicates
3. **YAML frontmatter** — verify name, description, and appropriate fields are present
4. **Required sections** — commands should have clear prerequisites, main tasks, and output/report sections
5. **compound: namespace** — the name field should use the compound: prefix
6. **Argument handling** — if the command accepts arguments, it should reference #$ARGUMENTS and handle empty arguments gracefully

For each issue found, report:
- File path
- What is missing or incorrect
- Severity: SERIOUS (missing critical convention), MINOR (style/completeness)

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write your COMPLETE findings to: .workflows/plugin-qa/agents/completeness-review.md
Structure with: ## Summary, ## Findings (grouped by command), ## Recommendations
After writing the file, return ONLY a 2-3 sentence summary.
DO NOT return your full analysis in your response.
"
```

### Step 2.3: Monitor Agent Completion

**DO NOT call TaskOutput** to retrieve agent results. Monitor completion via file existence:

```bash
ls .workflows/plugin-qa/agents/
```

Expected files:
- `context-lean-review.md`
- `role-description-review.md`
- `completeness-review.md`

Poll periodically. When all three files exist (or after 5 minutes for stragglers), proceed to Phase 3. Mark timed-out agents and move on.

## Phase 3: Aggregation

### Step 3.1: Collect All Results

Read all Tier 1 script outputs (from Phase 1) and all Tier 2 agent files (from Phase 2):

```bash
ls .workflows/plugin-qa/agents/*.md
```

Read each agent output file using the Read tool.

### Step 3.2: Count Aggregated Findings

Count total findings across all Tier 1 scripts and Tier 2 agents. Track this count — it determines whether Phase 3.3 runs.

**If zero findings across all checks:** skip Phase 3.3 entirely and proceed directly to Step 3.4 (report "All checks passed.").

### Phase 3.3: Beads Cross-Reference

Cross-reference aggregated QA findings against open beads to identify which findings are already tracked and which need new beads.

**Zero-findings gate:** If Step 3.2 counted zero total findings, skip this entire phase and proceed to Step 3.4.

#### Step 3.3.1: Check Beads Availability

Two-step availability check. Both must succeed to proceed.

**Step A — Check if `bd` is installed:**

```bash
bd version 2>/dev/null && echo "BD_INSTALLED=true" || echo "BD_INSTALLED=false"
```

If `BD_INSTALLED=false`: output the following warning and skip to Step 3.4:

> ⚠️ Beads (`bd`) is not installed. Skipping bead cross-reference. Findings will be presented without tracking status.

**Step B — Fetch open beads:**

```bash
mkdir -p .workflows/plugin-qa/
bd search "" --status open --json --limit 100 2>/dev/null
```

**Important:** Use `bd search "" --status open --json --limit 100`, NOT `bd list --json` (which does not produce valid JSON).

Write the JSON output to `.workflows/plugin-qa/open-beads.json` (single-fetch pattern — fetched once here, referenced by all subsequent steps in Phase 3.3).

**If the search command fails** (non-zero exit or empty output): output the following warning and skip to Step 3.4:

> ⚠️ Beads search failed. Skipping bead cross-reference. Findings will be presented without tracking status.

**If >100 beads in JSON output:** warn the user and truncate to the 100 most recently updated beads:

> ⚠️ Found N open beads (limit: 100). Using 100 most recently updated. Consider grooming your backlog.

After successful completion, proceed to Step 3.3.2.

#### Step 3.3.2: Deterministic Text Matching

Match Tier 1 findings against open beads using fast, deterministic string comparison. This runs in the orchestrator (not a subagent) because data volumes are bounded (max ~50 Tier 1 findings, 100 beads) and the matching is simple string comparison.

**Tier 2 findings bypass this step entirely.** Tier 2 findings are free-form prose without structured check-name or file fields — they go directly to the LLM subagent (Step 3.3.3).

**Input:**
- Tier 1 findings from Phase 1 (format: `- **[SEVERITY]** \`relative/file/path\` (line N): pattern-name — Description text`)
- Beads JSON from `.workflows/plugin-qa/open-beads.json` (written in Step 3.3.1)

**For each Tier 1 finding**, extract the `check-name` (the pattern-name after the line number) and `file-path` (the backtick-quoted path). Then search the beads JSON in priority order — stop at the first match:

1. **Provenance token match** (strongest): Any bead's description contains the exact string `qa-finding:<check-name>:<file-path>`. This is a fingerprint left by prior QA runs — it is definitive. Mark the finding as `tracked` with that bead's ID.

2. **Check-name + file match** (strong): Any bead's title or description contains the `check-name` AND also references the same `file-path`. Mark as `tracked` with that bead's ID.

3. **Check-name only match** (moderate): Any bead's title or description contains the `check-name` but does NOT reference the same file. Still mark as `tracked` — check-names (e.g., `stale-task-dispatch`, `missing-output-instructions`) are specific enough that a bead mentioning one almost certainly covers this finding category.

4. **File-path-only match** (weak): Skip — too many false positives. A bead mentioning a file does not mean it tracks a specific QA finding about that file. Leave these for the LLM subagent.

**Fingerprint dedup:** Before classifying any finding as `untracked`, check whether its provenance token (`qa-finding:<check-name>:<file-path>`) already exists in ANY bead's description or notes. If it does, that finding is already tracked regardless of other matching criteria — mark it as `tracked` with that bead's ID and move on.

**Output — two lists for subsequent steps:**

1. **Matched findings** — each entry contains: the finding text, the match type (provenance/check-name+file/check-name-only), and the matched bead ID. These go to the coverage assessment subagent (Step 3.3.4).

2. **Unmatched findings** — all Tier 1 findings that did not match any bead via the rules above, plus ALL Tier 2 findings (which were never candidates for deterministic matching). These go to the LLM matching subagent (Step 3.3.3).

**If all Tier 1 findings matched and there are no Tier 2 findings:** skip Step 3.3.3 (LLM matching) and proceed directly to Step 3.3.4 (coverage assessment).

#### Step 3.3.3: LLM Semantic Matching (Unmatched Findings)

Match findings that the deterministic text pass could not resolve. This covers all Tier 2 findings (free-form prose) and any Tier 1 findings without a bead match.

**Skip this step if zero unmatched findings remain after Step 3.3.2.**

Create the output directory (if not already present):

```bash
mkdir -p .workflows/plugin-qa/
```

Dispatch a disk-persist subagent:

```
Task general-purpose (run_in_background: true): "
You are a QA finding-to-bead matching agent.

Your task: read the open beads JSON from disk, then classify each QA finding as matched, uncertain, or untracked against those beads.

**Input findings to classify:**
[Insert the list of unmatched Tier 1 findings + ALL Tier 2 findings here. For each finding, include: source (script name or agent name), file path if available, severity, and the finding description.]

**Beads data:** Read the open beads JSON from `.workflows/plugin-qa/open-beads.json`. This file contains all open beads with their IDs, titles, descriptions, and notes.

**Classification rules:**
For each finding, search the beads for a match and classify as one of:
- **matched** — high confidence this finding is tracked by a specific bead. The bead's title, description, or notes clearly cover this finding's domain AND specific issue.
- **uncertain** — possible match to a bead, but not confident. Use this when the finding shares a file or domain with a bead but the bead's scope does not clearly include this specific finding.
- **untracked** — no matching bead found after reviewing all open beads.

When multiple beads could match, pick the strongest match. Do not assign the same finding to multiple beads.

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write your COMPLETE classification to: .workflows/plugin-qa/bead-cross-ref-matches.md

Use this EXACT structure:

## Matched
- [finding description] → bead [id]: [title] (confidence: high)

## Uncertain
- [finding description] → possibly bead [id]: [title] (reason for uncertainty)

## Untracked
- [finding description] — no matching bead found

If a section has no entries, include the header with '(none)' underneath.

After writing the file, return ONLY a 2-3 sentence summary of how many findings fell into each category.
DO NOT return your full classification in your response.
"
```

**Monitor completion via file existence check:**

```bash
ls .workflows/plugin-qa/bead-cross-ref-matches.md 2>/dev/null && echo "EXISTS" || echo "NOT_FOUND"
```

**Timeout: 2 minutes.** Poll periodically. If the output file does not appear within 2 minutes, skip this pass and present findings without cross-reference data (same degradation path as beads-unavailable in Step 3.3.1). **If Step 3.3.3 times out, also skip Step 3.3.4** — proceed directly to Step 3.4.

When the file exists, read results from `.workflows/plugin-qa/bead-cross-ref-matches.md` using the Read tool. Merge any `matched` results with the deterministic matches from Step 3.3.2 to build the combined matched-findings list for the next step.

#### Step 3.3.4: Coverage Assessment (Matched Beads)

Assess whether matched beads adequately describe the findings they are tracking, and draft description additions for gaps.

**Skip this step if zero matched findings exist** (from both Step 3.3.2 deterministic matches and Step 3.3.3 LLM matches combined).

Dispatch a disk-persist subagent:

```
Task general-purpose (run_in_background: true): "
You are a bead coverage assessment agent.

Your task: for each QA finding that has been matched to a bead, assess whether the bead's description adequately covers that specific finding.

**Matched finding→bead pairs to assess:**
[Insert the combined list of matched findings from Step 3.3.2 (deterministic) and Step 3.3.3 (LLM). For each pair, include: the finding description, the matched bead ID, and the bead title.]

**Beads data:** Read the full bead details from `.workflows/plugin-qa/open-beads.json` to access each bead's description and notes.

**Coverage definitions:**
- **Full coverage** — the bead's description or notes already mention the specific file AND the specific finding pattern. No update needed.
- **Partial coverage** — the bead covers the general domain but does not mention this specific instance (e.g., bead tracks 'stale references' generally but doesn't mention the specific file this finding is about). Draft a proposed description addition.

For partial coverage, draft a concise proposed addition that could be appended to the bead's existing description to cover this specific finding.

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write your COMPLETE assessment to: .workflows/plugin-qa/bead-cross-ref-coverage.md

Use this EXACT structure:

## Full Coverage
- [finding] → bead [id]: description already covers this finding

## Partial Coverage (updates proposed)
- [finding] → bead [id]: [proposed description addition]

If a section has no entries, include the header with '(none)' underneath.

After writing the file, return ONLY a 2-3 sentence summary of how many findings have full vs partial coverage.
DO NOT return your full assessment in your response.
"
```

**Monitor completion via file existence check:**

```bash
ls .workflows/plugin-qa/bead-cross-ref-coverage.md 2>/dev/null && echo "EXISTS" || echo "NOT_FOUND"
```

**Timeout: 2 minutes.** Poll periodically. If the output file does not appear within 2 minutes, present matches without coverage data and note the omission in the Step 3.4 summary:

> ⚠️ Coverage assessment timed out. Matches are shown without coverage status.

When the file exists, read results from `.workflows/plugin-qa/bead-cross-ref-coverage.md` using the Read tool.

#### Step 3.3.5: Present Tracking Status

Present all proposed bead operations as a batch for user confirmation, or skip if everything is already tracked.

**Read subagent results from disk:**
- `.workflows/plugin-qa/bead-cross-ref-matches.md` (LLM matching results from Step 3.3.3, if it ran)
- `.workflows/plugin-qa/bead-cross-ref-coverage.md` (coverage assessment from Step 3.3.4, if it ran)

Combine these with the deterministic matching results from Step 3.3.2 to build the complete tracking picture.

**If all findings are already tracked with full coverage:** skip the batch confirmation entirely. Report the following in the QA summary and proceed directly to Step 3.4:

> All N findings are tracked by existing beads.

**Otherwise,** build the tracking status presentation. Categorize every finding into exactly one of these four groups:

```markdown
### Tracking Status

**Already tracked (full coverage):**
- [finding] → bead [id]: [title]

**Already tracked (partial coverage — updates proposed):**
- [finding] → bead [id]: [title]
  Proposed update: [description addition]

**Uncertain matches — please confirm:**
- [finding] → possibly bead [id]: [title]? [Link / Not related]

**Untracked (will create beads):**
- [SERIOUS] [finding] → new bead: [proposed title] (P2)
- [MINOR] [finding] → Create bead? / Skip tracking
```

**Category details:**

1. **Already tracked (full coverage):** Findings matched (deterministic or LLM) to a bead where the coverage assessment said "full coverage." No action needed — listed for completeness.

2. **Already tracked (partial coverage — updates proposed):** Findings matched to a bead where the coverage assessment said "partial coverage." Shows the proposed description addition from the coverage subagent. If confirmed, the bead description will be updated.

3. **Uncertain matches — please confirm:** Findings the LLM subagent classified as `uncertain`. Each has a "Link / Not related" choice for the user. Uncertain matches do NOT include coverage assessment (the coverage subagent ran before the user confirmed these matches). If the user links an uncertain match, the user assesses coverage manually for that finding.

4. **Untracked (will create beads):** Findings with no match (deterministic or LLM). Severity-to-priority mapping: CRITICAL→P1, SERIOUS→P2, MINOR→P3. CRITICAL and SERIOUS findings will create beads if confirmed. MINOR findings have a per-item "Create bead? / Skip tracking" choice.

**Write the batch to disk** (recovery artifact + context-lean):

Write the composed tracking status presentation to `.workflows/plugin-qa/bead-cross-ref-batch.md`. This file serves two purposes: (1) recovery if context compacts during the confirmation flow, and (2) keeping the full presentation data on disk rather than solely in context.

**Present to user via AskUserQuestion** with three options:

1. **Apply all** — execute all proposed operations: create beads for untracked findings (except MINOR items the user chose to skip), update descriptions for partial-coverage beads, add notes on matched beads, and add provenance tokens to confirmed uncertain matches
2. **Review individually** — present each operation category for individual approval
3. **Skip bead operations** — do not create or update any beads; just show findings as in the existing QA flow (proceed to Step 3.4)

**If the user chooses "Review individually":**

Present operations grouped by category in this order (most interactive first):

1. **Uncertain matches** — present each one individually for "Link / Not related" decision. These need the most user attention. For confirmed links: include retroactive provenance token addition to the matched bead's description (format: `qa-finding:<check-name>:<file>`) so that future deterministic matching runs find them automatically.

2. **Untracked MINOR findings** — present as a batch with per-item "Create bead? / Skip tracking" choice. CRITICAL and SERIOUS untracked findings are not presented individually — they always create beads.

3. **Coverage updates** — present as a batch. These are description additions on partially-covered beads. User can approve all, reject all, or cherry-pick.

After all confirmations are collected, proceed to Step 3.3.6 (Execute Bead Operations) with the confirmed operation set.

#### Step 3.3.6: Execute Bead Operations

Execute confirmed bead operations from Step 3.3.5, tracking success and failure for each command.

**Skip this step if the user chose "Skip bead operations" in Step 3.3.5.** Proceed directly to Step 3.4.

**Initialize counters:** `created=0`, `updated=0`, `notes_added=0`, `failed=0`, `consecutive_failures=0`.

**Consecutive failure abort:** Before each `bd` command, check `consecutive_failures`. If it reaches 3 or more, stop all remaining operations immediately and report:

> Beads database appears unavailable (3 consecutive failures). Remaining operations skipped. N created, N updated, N notes added, N failed.

After each successful `bd` command, reset `consecutive_failures` to 0. After each failed command, increment both `failed` and `consecutive_failures`.

---

**1. Create beads for confirmed untracked findings:**

For each confirmed creation (CRITICAL, SERIOUS, or user-approved MINOR findings):

```bash
bd create --title="[check-name]: [file] — [finding summary]" \
  --type=bug \
  --priority=<priority> \
  --description="Found by plugin-changes-qa [check-name]:
[finding description]

File: [file path]
Line: [line number]
Severity: [CRITICAL|SERIOUS|MINOR]
Check: [script or agent name]

Provenance: qa-finding:[check-name]:[file]"
```

Severity-to-priority mapping: CRITICAL → `--priority=1` (P1), SERIOUS → `--priority=2` (P2), MINOR → `--priority=3` (P3).

Check the exit code. On success: increment `created`, reset `consecutive_failures` to 0. On failure: increment `failed` and `consecutive_failures`, record the error message for the failure report.

---

**2. Add notes on matched beads:**

For each confirmed note addition on a matched bead:

**Dedup check first:** Read the bead's current notes to check if a note with this provenance token already exists. Run:

```bash
bd show <id> --json
```

Parse the JSON output. If the bead's notes already contain the provenance token `qa-finding:<check-name>:<file>`, skip this note addition (it is a duplicate from a prior QA run) — do not count it as a failure.

If the provenance token is NOT present in existing notes, append the new note:

```bash
bd update <id> --append-notes "QA finding (YYYY-MM-DD): [check-name] — [finding summary]. Provenance: qa-finding:[check-name]:[file]"
```

**Important:** Use `--append-notes` (NOT `--notes`). The `--notes` flag overwrites all existing notes. `--append-notes` adds to them with a newline separator.

Check the exit code. On success: increment `notes_added`, reset `consecutive_failures` to 0. On failure: increment `failed` and `consecutive_failures`, record the error.

---

**3. Update descriptions for partial-coverage beads:**

For each confirmed coverage update on a partially-covered bead:

**Stale-data guard:** Re-read the bead's current description immediately before updating:

```bash
bd show <id> --json
```

Parse the JSON output and extract the current description text.

**Verify provenance token is still present:** Check that the bead's description still contains the expected provenance token (`qa-finding:<check-name>:<file>`). If the provenance token is missing (meaning someone externally modified the bead's description since the cross-reference ran), output a warning and skip this update:

> ⚠️ Skipping coverage update for bead [id]: provenance token no longer present in description (external modification detected).

Do not count skipped updates as failures.

**If the provenance token is present:** Update the description by appending the proposed coverage addition:

```bash
bd update <id> --description "[current description]

Additional coverage: [proposed addition from Step 3.3.4]"
```

Check the exit code. On success: increment `updated`, reset `consecutive_failures` to 0. On failure: increment `failed` and `consecutive_failures`, record the error.

---

**4. Add provenance tokens to confirmed uncertain matches:**

For each uncertain match the user confirmed as "Link" in Step 3.3.5:

Re-read the bead's current description:

```bash
bd show <id> --json
```

Parse the current description, then append the provenance token so future deterministic matching runs (Step 3.3.2) will find this match automatically:

```bash
bd update <id> --description "[current description]

Provenance: qa-finding:[check-name]:[file]"
```

Check the exit code. On success: increment `updated`, reset `consecutive_failures` to 0. On failure: increment `failed` and `consecutive_failures`, record the error.

---

**5. Report summary:**

After all operations complete (or after a consecutive failure abort), present the operation summary:

> Bead operations complete: N created, N updated, N notes added, N failed.

**If any failures occurred:** list each failed operation with its error details:

```markdown
**Failed operations:**
- CREATE [proposed title]: [error message]
- UPDATE bead [id] (note): [error message]
- UPDATE bead [id] (coverage): [error message]
```

Proceed to Step 3.4 (Present Aggregated Summary).

### Step 3.4: Present Aggregated Summary

Synthesize all findings into a single summary for the user:

```markdown
## Plugin QA Results

### Tier 1: Structural Checks (Scripts)
- **stale-references:** N findings
- **file-counts:** N findings
- **truncation-check:** N findings
- **context-lean-grep:** N findings

### Tier 2: Semantic Analysis (Agents)
- **context-lean-review:** N findings
- **role-description-review:** N findings
- **completeness-review:** N findings

### Findings by Severity
- **CRITICAL:** N
- **SERIOUS:** N
- **MINOR:** N

### Details
[Group findings by check, showing severity and description for each]
```

**If zero findings across all checks:** "All checks passed."

**No codebase mutation.** Bead creation/updates are presented for user approval before execution.

## Rules

- **NEVER modify the codebase.** Bead operations are the only side effect, and require user confirmation.
- **NEVER call TaskOutput.** Poll for file existence instead.
- **NEVER push to remote.** This is a local analysis command.
- **Bead creation and updates require explicit user approval via staged batch confirmation.**
- Agent outputs go to `.workflows/plugin-qa/agents/`. Second runs overwrite prior results (always want latest).
- If a Tier 1 script fails with exit 1, report the error and continue with remaining scripts.
- If a Tier 2 agent times out, note it in the summary and present available results.
