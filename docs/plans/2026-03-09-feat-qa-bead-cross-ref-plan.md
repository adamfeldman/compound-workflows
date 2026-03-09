---
title: "feat: Add QA finding → bead cross-reference to plugin-changes-qa"
type: feat
status: active
date: 2026-03-09
origin: docs/brainstorms/2026-03-09-qa-bead-cross-ref-brainstorm.md
---

# feat: Add QA Finding → Bead Cross-Reference

Add a Phase 3.3 to `plugin-changes-qa` that cross-references aggregated QA findings against open beads. Uses hybrid matching (deterministic text first, LLM for remainder). All bead operations require staged batch confirmation — no auto-creation. Changes the skill's identity from pure reporter to reporter+tracker.

## Background

After QA aggregates findings, the user manually cross-references against open beads by running `bd search` or `bd list`. This is tedious (both directions: "is this finding tracked?" and "did I miss creating a bead?") and error-prone. The user has developed the pattern of asking "is everything connected to an open bead?" after every QA run — this should be automated.

The brainstorm (see origin) resolved all key design decisions through three-provider red team challenge. All CRITICAL and SERIOUS findings were addressed.

## Scope

**Single file modified:** `plugins/compound-workflows/skills/plugin-changes-qa/SKILL.md`

**Plus version bump files:** `.claude-plugin/plugin.json`, `CHANGELOG.md`, `README.md`, `marketplace.json`

**Out of scope:**
- PostToolUse hook changes (hook stays Tier 1 only, speed-optimized)
- Auto-closing beads when findings are resolved (separate concern)
- Changing the Tier 1/Tier 2 QA architecture

## Acceptance Criteria

- [ ] Phase 3.3 (Beads Cross-Reference) exists between current Phase 3.2 (aggregation) and presentation
- [ ] Two-step beads availability check: `bd version 2>/dev/null` then `bd search "" --status open --json --limit 100`
- [ ] If beads unavailable: warn once, skip cross-ref, present findings as today
- [ ] If >100 open beads: warn and truncate to 100 most recent
- [ ] Deterministic text matching runs first (check-name, file path, provenance token)
- [ ] LLM subagent handles unmatched findings (disk-persist to `.workflows/plugin-qa/bead-cross-ref-matches.md`)
- [ ] Second LLM subagent assesses coverage on matched beads (disk-persist to `.workflows/plugin-qa/bead-cross-ref-coverage.md`)
- [ ] Staged batch confirmation via AskUserQuestion with three options (Apply all / Review individually / Skip)
- [ ] Uncertain LLM matches escalated to user for manual linking
- [ ] MINOR findings ask user per-item: Create bead? / Skip tracking
- [ ] `bd create` includes provenance token in description (format: `qa-finding:<check-name>:<file>`)
- [ ] `bd update --append-notes` adds finding as note on matched beads (append, not overwrite)
- [ ] `bd update --description` for coverage updates on partially-covered beads
- [ ] Note dedup: check existing bead notes for provenance token before appending
- [ ] Deterministic matching applies to Tier 1 findings only; Tier 2 findings go directly to LLM subagent
- [ ] Single-fetch beads pattern: fetch JSON once to `.workflows/plugin-qa/open-beads.json`, reuse for all matching
- [ ] Skip-if-empty gates: skip LLM subagent if zero unmatched, skip coverage subagent if zero matched, skip batch if all tracked
- [ ] Consecutive failure abort: stop remaining bd operations after 3 consecutive failures
- [ ] Confirmed uncertain matches include retroactive provenance token addition to matched bead
- [ ] Fingerprint dedup: skip if provenance token already exists in any bead
- [ ] Per-item status tracking: report "N created, N updated, N notes added, N failed" at end
- [ ] Severity-to-priority mapping: CRITICAL→P1, SERIOUS→P2, MINOR→P3
- [ ] All four identity rules updated (lines 11, 209, 213, 216)
- [ ] Version bump: MINOR version (new feature)

## Implementation Phases

### Phase 1: Availability Gating + Phase Structure

Insert Phase 3.3 skeleton into SKILL.md between current Step 3.2 (aggregation) and the presentation section. Renumber existing Phase 3.2 presentation to Phase 3.4.

- [ ] Verify `bd update` CLI supports required flags: `--append-notes`, `--description`. Run `bd update --help` during implementation to confirm exact syntax.
- [ ] Add `### Phase 3.3: Beads Cross-Reference` section header after Step 3.2
- [ ] **Zero-findings gate:** If Phase 3.2 aggregation produced zero total findings, skip Phase 3.3 entirely and proceed to Phase 3.4
- [ ] Add `#### Step 3.3.1: Check Beads Availability` with two-step check:
  ```bash
  bd version 2>/dev/null && echo "BD_INSTALLED=true" || echo "BD_INSTALLED=false"
  ```
  If installed:
  ```bash
  bd search "" --status open --json --limit 100 2>/dev/null
  ```
  **Important:** Use `bd search "" --status open --json --limit 100`, NOT `bd list --json` (which doesn't produce JSON — see brainstorm Decision 7).
- [ ] Write beads JSON to `.workflows/plugin-qa/open-beads.json` (single-fetch pattern — one fetch, multiple consumers)
- [ ] Gate: if either check fails, output warning and skip to Phase 3.4
- [ ] If >100 beads in JSON output: warn user, truncate to 100 most recently updated
- [ ] Renumber existing "Present Aggregated Summary" section to `### Step 3.4: Present Aggregated Summary`

### Phase 2: Deterministic Text Matching

Add the first matching pass — fast, free, provably correct for exact/near-exact matches. Applies to **Tier 1 findings only** (they have structured check-name, file, line fields from lib.sh). Tier 2 findings are free-form prose without structured fields and go directly to the LLM subagent in Phase 3.

- [ ] Add `#### Step 3.3.2: Deterministic Text Matching`
- [ ] Read beads JSON from `.workflows/plugin-qa/open-beads.json`
- [ ] For each Tier 1 finding, search the beads JSON for (match priority order):
  1. **Provenance token match** (strongest) — bead description contains `qa-finding:<check-name>:<file>` → auto-match
  2. **Check-name match** (strong) — bead title or description contains the check-name AND references the same file → auto-match
  3. **Check-name only match** (moderate) — bead title or description contains the check-name but no file overlap → auto-match (check-names are specific enough)
  4. **File-path-only match** (weak) — skip, too many false positives. Let LLM handle these.
- [ ] Mark matched findings as `tracked` with the matched bead ID
- [ ] Collect unmatched Tier 1 findings + ALL Tier 2 findings for LLM pass

### Phase 3: LLM Matching Subagent (Pass 1)

Dispatch a disk-persist subagent for semantic matching of findings the text pass couldn't match.

- [ ] Add `#### Step 3.3.3: LLM Semantic Matching (Unmatched Findings)`
- [ ] Skip this step if zero unmatched findings remain after Step 3.3.2
- [ ] Create output directory: `mkdir -p .workflows/plugin-qa/`
- [ ] Dispatch Task subagent (disk-persist pattern):
  - Input: list of unmatched Tier 1 findings + all Tier 2 findings + beads JSON file path (`.workflows/plugin-qa/open-beads.json`)
  - Task: read beads JSON from disk, then for each finding classify as:
    - `matched` — high confidence this finding is tracked by bead [id]
    - `uncertain` — possible match to bead [id] but not confident
    - `untracked` — no matching bead found
  - Output: `.workflows/plugin-qa/bead-cross-ref-matches.md`
  - Return: 2-3 sentence summary only
- [ ] Monitor completion via file existence check. **Timeout: 2 minutes.** If output file does not appear, skip this pass and present findings without cross-reference data (same as beads-unavailable degradation path). If Pass 1 times out, also skip Pass 2.
- [ ] Read results from disk

### Phase 4: Coverage Assessment Subagent (Pass 2)

Separate subagent assesses whether matched beads adequately describe the findings.

- [ ] Add `#### Step 3.3.4: Coverage Assessment (Matched Beads)`
- [ ] Skip this step if zero matched findings (from both text and LLM passes)
- [ ] Dispatch Task subagent (disk-persist pattern):
  - Input: list of matched finding→bead pairs
  - Task: for each pair, assess:
    - Does the bead description cover this specific finding?
    - If not, draft a proposed description addition
  - Output: `.workflows/plugin-qa/bead-cross-ref-coverage.md`
  - Return: 2-3 sentence summary only
- [ ] Monitor completion via file existence check. **Timeout: 2 minutes.** If output file does not appear, present matches without coverage data and note the omission.
- [ ] Read results from disk

### Phase 5: Staged Batch Confirmation

Present all proposed bead operations as a batch for user confirmation.

- [ ] Add `#### Step 3.3.5: Present Tracking Status`
- [ ] Read results from both subagent output files
- [ ] **If all findings are already tracked with full coverage:** skip batch confirmation, report "All N findings are tracked by existing beads" in QA summary. Proceed to Phase 3.4.
- [ ] Otherwise, build the tracking status presentation:

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

- [ ] Write the composed batch to `.workflows/plugin-qa/bead-cross-ref-batch.md` (recovery artifact + context-lean)
- [ ] Use AskUserQuestion with three options:
  1. **Apply all** — creates + updates + notes
  2. **Review individually** — present each operation for approval
  3. **Skip bead operations** — just show findings (existing behavior)
- [ ] For "Review individually": group by category — uncertain matches first (need individual attention), then untracked MINOR findings as batch, then coverage updates as batch
- [ ] Confirmed uncertain matches: include retroactive provenance token addition to the matched bead's description (so future runs find them deterministically)
- [ ] Uncertain matches do NOT include coverage assessment (Pass 2 ran before user confirmed). User assesses coverage manually for these.

### Phase 6: Execute Bead Operations

Execute confirmed operations with per-item status tracking.

- [ ] Add `#### Step 3.3.6: Execute Bead Operations`
- [ ] For each confirmed creation:
  ```bash
  bd create --title="[check-name]: [file] — [finding summary]" \
    --type=bug \
    --priority=<severity-mapping> \
    --description="Found by plugin-changes-qa [check-name]:
  [finding description]

  File: [file path]
  Line: [line number]
  Severity: [CRITICAL|SERIOUS|MINOR]
  Check: [script or agent name]

  Provenance: qa-finding:[check-name]:[file]"
  ```
- [ ] For each confirmed note addition on matched beads:
  - First check if bead already has a note with this provenance token (dedup)
  - If not: `bd update <id> --append-notes "QA finding ([date]): [check-name] — [finding summary]. Provenance: qa-finding:[check-name]:[file]"`
  - Use `--append-notes` (not `--notes`) to preserve existing notes
- [ ] For each confirmed coverage update:
  - Re-read the bead's current description via `bd show <id> --json` immediately before updating (guard against stale data)
  - Verify the provenance token is still present in the existing description
  - If provenance token is missing (external modification): warn and skip this coverage update
  - If present: `bd update <id> --description "[current description]\n\nAdditional coverage: [proposed addition]"`
- [ ] For confirmed uncertain matches: add provenance token to matched bead's description via `bd update <id> --description`
- [ ] Track success/failure of each command
- [ ] **Consecutive failure abort:** if 3+ consecutive bd commands fail, stop remaining operations and report "Beads database appears unavailable"
- [ ] Report summary: "N created, N updated, N notes added, N failed"
- [ ] If any failures: list the failed operations with error details

### Phase 7: Identity Rule Updates

Update all identity statements in SKILL.md to reflect the reporter+tracker role.

- [ ] Line 11: Change `**Findings are informational only.** This command does not modify the codebase.` to `**Findings are informational.** Bead tracking operations require explicit user confirmation.`
- [ ] Line 209 area: Change `**No codebase mutation.** Findings are informational only. The user decides what to act on.` to `**No codebase mutation.** Bead creation/updates are presented for user approval before execution.`
- [ ] Line 213 area: Change `**NEVER modify the codebase.** This command only reports findings.` to `**NEVER modify the codebase.** Bead operations are the only side effect, and require user confirmation.`
- [ ] Line 216: Change `**NEVER modify beads issues.** QA findings are presented to the user, not tracked automatically.` to `**Bead creation and updates require explicit user approval via staged batch confirmation.**`

### Phase 8: Version Bump + Documentation

- [ ] Bump version in `.claude-plugin/plugin.json` (MINOR bump)
- [ ] Update `CHANGELOG.md` with feature description
- [ ] Verify component counts in `README.md` (no new components — this modifies an existing skill)
- [ ] Update version in `marketplace.json`
- [ ] Verify no new agents need registration in `CLAUDE.md` (the subagents are ad-hoc Task dispatches, not registered agents)

## Key Design Decisions

All decisions were made during brainstorming with three-provider red team validation (see brainstorm: `docs/brainstorms/2026-03-09-qa-bead-cross-ref-brainstorm.md`).

1. **Hybrid matching** — deterministic text first, LLM for remainder, uncertain escalated to user. Addresses reliability concerns flagged by all three red team providers. (Brainstorm Decision 1)

2. **Staged batch confirmation** — no auto-creation. Resolves the contradiction between "explicit approval" and "auto-create" flagged by all three providers. (Brainstorm Decision 2)

3. **Two-pass subagent** — Pass 1 matches, Pass 2 assesses coverage. Splitting tasks improves accuracy by giving each agent a narrower focus. (Brainstorm Decision 3)

4. **Idempotency via fingerprint + provenance token** — prevents duplicate beads and notes on re-runs. Deterministic matching finds tokens; LLM is the backup. (Brainstorm Decision 4)

5. **Identity shift acknowledged** — QA becomes reporter+tracker. All four identity rules updated explicitly. (Brainstorm Decision 5)

6. **`bd search` not `bd list` for JSON** — empirically confirmed that `bd list --json` doesn't produce JSON. `bd search "" --status open --json --limit 100` does. (Brainstorm Decision 7)

7. **Cap at 100 beads** — prevents prompt-size issues. Projects with 200+ beads need backlog grooming, not larger matching windows. (Brainstorm Decision 9)

## Technical Notes

### Finding Format (from lib.sh)

Tier 1 findings follow this format:
```
- **[SEVERITY]** `relative/file/path` (line N): pattern-name
  Description text
```

Tier 2 findings are prose grouped by file under `## Findings` headers (no structured check-name or line number). The orchestrator normalizes these for the LLM subagent: source agent name serves as the "check-name" equivalent, and file paths are extracted from the prose where present.

### Fingerprint Construction

Provenance token format (no line number — lines shift between edits, breaking idempotency):

```
qa-finding:<check-name>:<relative-file-path>
```

Example: `qa-finding:context-lean-grep:commands/compound/work.md`

For Tier 2 findings: `qa-finding:<agent-name>:<file-path>` (e.g., `qa-finding:context-lean-review:commands/compound/work.md`)

Line number is stored in the finding description but NOT in the provenance token. This ensures re-runs match even when code shifts.

### Subagent Output Files

Both subagent passes write to `.workflows/plugin-qa/`:
- `bead-cross-ref-matches.md` — Pass 1 matching results
- `bead-cross-ref-coverage.md` — Pass 2 coverage assessment

These overwrite on each QA run (same convention as existing Tier 2 agent outputs).

### Subagent Prompt Requirements

Both subagents are inline Task dispatches in SKILL.md (not registered agents). The implementer writes the prompts, but they must include:

**Pass 1 (Matching Subagent):**
- Role: "You are a QA finding-to-bead matching agent."
- Input: unmatched findings list (normalized format) + path to `.workflows/plugin-qa/open-beads.json`
- Task: read beads JSON, classify each finding as matched/uncertain/untracked
- Output schema (required headers in `.workflows/plugin-qa/bead-cross-ref-matches.md`):
  ```
  ## Matched
  - [finding description] → bead [id]: [title] (confidence: high)

  ## Uncertain
  - [finding description] → possibly bead [id]: [title] (reason for uncertainty)

  ## Untracked
  - [finding description] — no matching bead found
  ```
- Confidence threshold: "uncertain" = the finding shares a file or domain with a bead but the bead's scope doesn't clearly include this specific finding
- OUTPUT INSTRUCTIONS block (mandatory)

**Pass 2 (Coverage Subagent):**
- Role: "You are a bead coverage assessment agent."
- Input: list of matched finding→bead pairs (from deterministic + Pass 1 matches)
- Task: for each pair, assess coverage level (full/partial) and draft description additions for partial
- Output schema (required headers in `.workflows/plugin-qa/bead-cross-ref-coverage.md`):
  ```
  ## Full Coverage
  - [finding] → bead [id]: description already covers this finding

  ## Partial Coverage (updates proposed)
  - [finding] → bead [id]: [proposed description addition]
  ```
- Coverage definition: "full" = bead description or notes mention the specific file and finding pattern; "partial" = bead covers the domain but not the specific instance
- OUTPUT INSTRUCTIONS block (mandatory)

### Context-Lean Compliance

- Beads JSON fetched once via bash, written to `.workflows/plugin-qa/open-beads.json` (not loaded raw into orchestrator context)
- Both subagents use disk-persist pattern (write to file, return summary)
- Subagents read beads JSON from the disk file (orchestrator passes the file path, not the content)
- Orchestrator reads subagent result files from disk only when needed for presentation
- Staged batch written to disk (`.workflows/plugin-qa/bead-cross-ref-batch.md`) before presentation
- Follows existing Tier 2 agent dispatch pattern in Phases 2.1–2.3
- **Deterministic matching runs in orchestrator** (not in a subagent). Rationale: data volumes are bounded (max ~50 Tier 1 findings, 100 beads), the matching is simple string comparison, and subagent startup latency would exceed the savings. Acceptable context cost for a bounded operation.

### Tier 2 Finding Handling

Tier 2 findings (context-lean-review, role-description-review, completeness-review) are free-form prose without structured check-name/file fields. They bypass deterministic matching entirely and go directly to the LLM subagent in Phase 3. The LLM handles the semantic interpretation needed to match prose findings to beads.

### bd update Flags (Verified)

- `--append-notes "text"` — appends to existing notes with newline separator (does NOT overwrite)
- `--notes "text"` — sets/overwrites notes (do NOT use for adding findings)
- `--description "text"` — sets/overwrites description (use for coverage updates)
- `bd update --help` confirms these flags exist as of 2026-03-09

## Open Questions

(none — all resolved during brainstorming and red team triage)

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-03-09-qa-bead-cross-ref-brainstorm.md` — Key decisions carried forward: hybrid matching (#1), staged batch confirmation (#2), two-pass subagent (#3), idempotency (#4), identity shift (#5), bd search for JSON (#7), 100-bead cap (#9)
- **Brainstorm research:** `.workflows/brainstorm-research/qa-bead-cross-ref/` — repo research, context research, 3 red team reviews
- **Plan research:** `.workflows/plan-research/qa-bead-cross-ref/` — repo research, learnings, specflow analysis
- **QA script patterns:** `docs/solutions/qa-infrastructure/2026-03-08-bash-qa-script-patterns.md`
- **Primary file:** `plugins/compound-workflows/skills/plugin-changes-qa/SKILL.md`
- **Reference patterns:** `commands/compound/work.md` (beads integration), `commands/compound/compact-prep.md` (read-only beads check)
