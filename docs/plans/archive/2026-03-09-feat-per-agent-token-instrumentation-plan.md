---
title: "Per-Agent Token Instrumentation"
type: feat
status: active
date: 2026-03-09
origin: docs/brainstorms/2026-03-09-per-agent-token-instrumentation-brainstorm.md
bead: voo
related_beads: [xu2, 22l]
---

# Per-Agent Token Instrumentation

## Overview

Automate per-dispatch stats collection across all 5 orchestrator commands (work, brainstorm, plan, deepen-plan, review). Task completion notifications return `<usage>total_tokens, tool_uses, duration_ms</usage>` — persist these to per-command-run YAML files for cost/complexity analysis. Add a standalone classification skill and ccusage snapshot persistence.

Key decisions from [brainstorm](docs/brainstorms/2026-03-09-per-agent-token-instrumentation-brainstorm.md):
- Multi-document YAML (not JSONL — LLMs write YAML fluently, see brainstorm Decision 2)
- Per-command-run files in `.workflows/stats/` (see brainstorm Decision 3)
- 4-tier complexity + output_type dimension, classified post-hoc (see brainstorm Decision 5)
- Classification decoupled from compact-prep as standalone skill (see brainstorm Decision 5)
- Two independent settings toggles, missing = enabled (see brainstorm Decision 6)
- All 5 commands from day one (see brainstorm Decision 7)
- Warn on `<usage>` parse failure — never silently skip (see brainstorm Open Questions)

## Implementation Steps

### Step 1: Settings Infrastructure

Add `stats_capture` and `stats_classify` toggles to the config template and setup flow.

**Files:** `plugins/compound-workflows/commands/compound/setup.md`, `plugins/compound-workflows/skills/setup/SKILL.md`

- [ ] In setup.md Step 7b, add to `compound-workflows.local.md` template after `gh_cli`:
  ```
  stats_capture: true
  stats_classify: true
  ```
- [ ] In setup.md Step 7d (migration), add detection: if `compound-workflows.local.md` exists but lacks `stats_capture` key, append both keys with `true` defaults
- [ ] Mirror the same template and migration changes in `plugins/compound-workflows/skills/setup/SKILL.md`
- [ ] No interactive prompt needed — keys default to enabled silently (see brainstorm Decision 6: "Missing keys = enabled")

**Design note:** Each orchestrator command checks `stats_capture` inline — if the key is missing or any value other than `false`, capture proceeds. Setup migration adds keys for explicitness but isn't required for the feature to work.

### Step 2: Stats Capture Reference File

Create a shared reference document with the YAML schema, capture procedure, and error handling. Each orchestrator command includes a short inline instruction pointing to this file.

**Files:** `plugins/compound-workflows/resources/stats-capture-schema.md` (new directory + file)

- [ ] Create `plugins/compound-workflows/resources/` directory
- [ ] Write `stats-capture-schema.md` containing:
  - Full YAML schema with field descriptions
  - `<usage>` parse procedure (extract `total_tokens`, `tool_uses`, `duration_ms` from `<usage>` tag)
  - Error handling: warn on unrecognizable `<usage>` format, write null fields if `<usage>` absent
  - File naming: `.workflows/stats/<date>-<command>-<stem>.yaml`
  - File initialization: `mkdir -p .workflows/stats` before first write
  - Append semantics: if the stats file already exists, READ existing content, then WRITE existing content + `---` document separator + new entry. Do not rely on implicit append behavior from an LLM file write — always read-then-write-all to prevent truncation.
  - Post-dispatch validation: count YAML documents in stats file vs completed dispatches, warn on mismatch

**Schema (reference copy — authoritative version in the file):**
```yaml
---
command: work
bead: 22l
stem: quota-optimization
agent: general-purpose
step: "1"  # Polymorphic: bead issue number when command=work, agent role name for others
model: opus
tokens: 20121
tools: 13
duration_ms: 43364
timestamp: 2026-03-09T14:23:00Z
status: success
complexity: null
output_type: null
```

**Field reference:**

| Field | Source | Description |
|-------|--------|-------------|
| command | Fixed per command | work / brainstorm / plan / deepen-plan / review |
| bead | `bd show` output (work only) | Bead ID, null for non-work commands |
| stem | Derived per command (see table) | Links to `.workflows/` artifacts |
| agent | Task dispatch name | `general-purpose`, `repo-research-analyst`, etc. |
| step | Varies by command (see table) | Step number (work) or agent role name (others) |
| model | Agent YAML `model:` field or default (see resolution algorithm below) | opus / sonnet / haiku |
| tokens | `<usage>` total_tokens | null if `<usage>` absent |
| tools | `<usage>` tool_uses | null if `<usage>` absent |
| duration_ms | `<usage>` duration_ms | null if `<usage>` absent |
| timestamp | System time at capture | ISO 8601 with Z timezone |
| status | Dispatch outcome | success / failure / timeout |
| complexity | Classifier (post-hoc) | rote / mechanical / analytical / judgment / null |
| output_type | Classifier (post-hoc) | code-edit / research / review / relay / synthesis / null |

**Model resolution algorithm:**
1. Read the dispatched agent's YAML frontmatter `model:` field.
2. If the field specifies a concrete model (e.g., `model: sonnet`), use that value.
3. If the field says `model: inherit` or is absent, use the parent context's model (typically `opus` for orchestrator commands).
4. Known limitation: `CLAUDE_CODE_SUBAGENT_MODEL` environment variable override cannot be detected from within the command — if set, the recorded model may be inaccurate. Document in stats-capture-schema.md as a known limitation.

**Stem derivation per command:**

| Command | Derivation | Example |
|---------|-----------|---------|
| work | Plan filename: strip date prefix + `-plan.md` suffix. Fallback: branch name. | `feat-quota-optimization` |
| brainstorm | topic-stem (already derived in Phase 1.1) | `per-agent-token-instrumentation` |
| plan | plan-stem (already derived in Phase 1) | `per-agent-token-instrumentation` |
| deepen-plan | plan-stem (from plan filename, already derived) | `feat-quota-optimization` |
| review | topic-stem (already derived in Step 2) | `feat-user-dashboard` |

**Step derivation per command:**

| Command | Step Value | Example |
|---------|-----------|---------|
| work | Bead issue number or sequential loop counter | `"1"`, `"3"` |
| brainstorm | Agent role name | `"repo-research-analyst"` |
| plan | Agent role name | `"learnings-researcher"` |
| deepen-plan | Agent file prefix + name | `"research--security-sentinel"` |
| review | Agent role name | `"typescript-reviewer"` |

**Note:** The `step` field is polymorphic — it holds a bead issue number when `command=work`, and an agent role name for all other commands. Downstream consumers should always filter by `command` before aggregating by `step`.

### Step 3: work.md Instrumentation

work.md dispatches foreground sequential Tasks — the simplest capture path. `<usage>` is in the inline Task response. Implement first to validate the core mechanism before tackling background dispatches.

**Files:** `plugins/compound-workflows/commands/compound/work.md`

- [ ] Add `mkdir -p .workflows/stats` early in the command flow (before the dispatch loop)
- [ ] Add config check: read `compound-workflows.local.md`, check `stats_capture`. If `false`, skip all stats capture. If missing or any other value, proceed.
- [ ] After the foreground Task dispatch returns, add inline stats capture instruction:
  - Read `stats-capture-schema.md` (use dynamic plugin path resolution: try local `plugins/compound-workflows/resources/`, then `find "$HOME/.claude/plugins" -name "stats-capture-schema.md" -path "*/compound-workflows/*"`)
  - Extract `<usage>` from the Task response
  - Derive stem from plan filename (strip date prefix + `-plan.md` suffix)
  - Append YAML document to `.workflows/stats/<date>-work-<stem>.yaml`
  - Set: command=work, bead=current bead ID, agent=general-purpose, step=bead issue number, model from agent context
  - Set status: success if Task returned normally, failure if error
- [ ] Handle `<usage>` absent: write entry with tokens/tools/duration_ms as null, status as failure
- [ ] Handle `<usage>` unparseable: warn "Stats capture: `<usage>` format may have changed — consider filing a bug"
- [ ] After dispatch loop completes, add post-dispatch validation: count YAML documents in stats file vs completed bead count, warn if mismatch
- [ ] Edge case: no plan file (ad-hoc work) → derive stem from branch name

**Inline instruction template (~3 lines in command, references schema file):**

**Path resolution:** The `[resolved stats-capture-schema.md path]` placeholder is resolved at command-write time (Step 3) and baked into the command text as a literal path. Use the same dynamic resolution logic from the Step 3 checklist: try local `plugins/compound-workflows/resources/`, then `find "$HOME/.claude/plugins" -name "stats-capture-schema.md" -path "*/compound-workflows/*"`. The resulting absolute path replaces the placeholder in the template below.

```
### Stats Capture
If stats_capture ≠ false in compound-workflows.local.md: after each Task completion, read the stats capture procedure from <stats-capture-schema.md absolute path> and follow it. Use command=work, bead=<current-bead-id>, stem=<plan-stem>, step=<bead-number>. After all dispatches, validate entry count.
```

### Step 4: brainstorm.md Instrumentation

brainstorm.md dispatches all background parallel Tasks. `<usage>` appears in automatic Task completion notifications (distinct from TaskOutput). This step validates background capture.

**Files:** `plugins/compound-workflows/commands/compound/brainstorm.md`

- [ ] Add `mkdir -p .workflows/stats` before Phase 1.1
- [ ] Add config check: read `stats_capture` from `compound-workflows.local.md`
- [ ] Add inline stats capture instruction for background Tasks: "When you receive a background Task completion notification, extract the `<usage>` tag and append a YAML entry to the stats file. This is the automatic notification — do not call TaskOutput."
- [ ] Apply across all dispatch phases:
  - Phase 1.1 research: `repo-research-analyst`, `context-researcher` (2 agents)
  - Phase 3.5 Step 1 red team: 3 providers (3 agents — `red-team-relay` × 2 + `general-purpose` × 1)
  - Phase 3.5 Step 3a: MINOR triage (1 agent)
- [ ] Set: command=brainstorm, bead=null, stem=topic-stem, step=agent role name
- [ ] After each dispatch phase completes, validate entry count vs dispatched agent count
- [ ] Model field: read agent YAML frontmatter `model:` field. For `red-team-relay`, model=sonnet (its explicit model). For `general-purpose`, model=opus (inherits parent).

### Step 5: plan.md Instrumentation

plan.md has mixed dispatch: background research agents + foreground readiness agents.

**Files:** `plugins/compound-workflows/commands/compound/plan.md`

- [ ] Add `mkdir -p .workflows/stats` before Phase 1
- [ ] Add config check: read `stats_capture`
- [ ] Instrument background dispatches (Phase 1, 1.5b, 3): extract `<usage>` from Task completion notifications
  - Phase 1: `repo-research-analyst`, `learnings-researcher` (2 agents)
  - Phase 1.5b (conditional): `best-practices-researcher`, `framework-docs-researcher` (0-2 agents)
  - Phase 3: `spec-flow-analyzer` (1 agent)
- [ ] Instrument foreground dispatches (Phase 6.7):
  - Semantic checks agent (background → notification)
  - `plan-readiness-reviewer` (foreground → inline response)
  - `plan-consolidator` (foreground, conditional → inline response)
- [ ] Skip: bash script dispatches (stale-values.sh, broken-references.sh, audit-trail-bloat.sh) — no `<usage>`, out of scope
- [ ] Set: command=plan, bead=null, stem=plan-stem, step=agent role name
- [ ] Validate entry count after all phases complete

### Step 6: review.md Instrumentation

review.md dispatches all background parallel Tasks.

**Files:** `plugins/compound-workflows/commands/compound/review.md`

- [ ] Add `mkdir -p .workflows/stats` at start
- [ ] Add config check: read `stats_capture`
- [ ] Instrument all background review agent dispatches: extract `<usage>` from completion notifications
  - Base agents: `typescript-reviewer`, `pattern-recognition-specialist`, `architecture-strategist`, `security-sentinel`, `performance-oracle`, `code-simplicity-reviewer`, `agent-native-reviewer` (7 agents)
  - Conditional: `data-migration-expert`, `deployment-verification-agent`, `frontend-races-reviewer`, `schema-drift-detector`, `data-integrity-guardian` (0-5 agents)
- [ ] Set: command=review, bead=null, stem=topic-stem, step=agent role name
- [ ] Validate entry count against dispatched agent count (accounting for conditional agents)

### Step 7: deepen-plan.md Instrumentation

deepen-plan.md is the most complex: batched background + foreground synthesis + red team. Has run-N numbering and manifest tracking.

**Files:** `plugins/compound-workflows/commands/compound/deepen-plan.md`

- [ ] Add `mkdir -p .workflows/stats` early in Phase 0
- [ ] Add config check: read `stats_capture`
- [ ] Instrument Phase 3 batched background dispatches: extract `<usage>` from each completion notification across all batches (research → skill → learning → review agents, 10-15+ per batch)
- [ ] Instrument Phase 4 foreground dispatches:
  - Synthesis agent (foreground → inline response)
  - MINOR triage agent (foreground → inline response)
- [ ] Instrument Phase 4.5 red team dispatches: extract `<usage>` from completion notifications (3 agents — captures relay overhead only, not external model cost)
- [ ] Set: command=deepen-plan, bead=null, stem=plan-stem, step=agent file prefix + name (e.g., `research--security-sentinel`)
- [ ] Validate entry count against manifest agent count (use manifest batch groupings — each batch's dispatched agents should match YAML entries written during that batch)
- [ ] Stats go to centralized YAML only — do NOT add stats to the deepen-plan manifest (see brainstorm Decision 4: manifest tracks run status, not cost/complexity)

### Step 8: compact-prep ccusage Snapshot Persistence

Modify compact-prep to persist ccusage data as a YAML snapshot in the stats directory.

**Files:** `plugins/compound-workflows/skills/compact-prep/SKILL.md`

- [ ] After existing Step 7 (Daily Cost Summary), if ccusage data was successfully retrieved and parsed:
  - Add `mkdir -p .workflows/stats`
  - Write ccusage snapshot YAML to `.workflows/stats/<date>-ccusage-snapshot.yaml`
  - If file exists, append with `---` separator (read existing content, then write all — same pattern as stats-capture-schema.md)
  - Schema:
    ```yaml
    ---
    type: ccusage-snapshot
    timestamp: 2026-03-09T18:30:00Z
    total_cost_usd: 212.71
    input_tokens: 1234567
    output_tokens: 456789
    ```
- [ ] If ccusage not available or parse failed, skip (no snapshot — don't error)
- [ ] Add brief note in Step 7 output: "ccusage snapshot saved to .workflows/stats/"

### Step 9: classify-stats Skill

Create a new skill for post-hoc complexity and output_type classification. This is a skill (not a command) because the `commands/compound/` directory is at capacity (8/8). Invoked as `/compound-workflows:classify-stats`.

**Files:** `plugins/compound-workflows/skills/classify-stats/SKILL.md` (new directory + file)

- [ ] Create `plugins/compound-workflows/skills/classify-stats/` directory
- [ ] Write SKILL.md implementing the classification flow:
  1. Check `stats_classify` in `compound-workflows.local.md` — skip if `false`
  2. Read all `.workflows/stats/*.yaml` files (excluding `ccusage-snapshot` entries)
  3. Filter to unclassified entries (complexity is null)
  4. If none: "All stats entries are already classified."
  5. Dispatch a classifier subagent (`Task general-purpose`) that reads three input layers:
     - YAML stats entries (the unclassified entries)
     - Artifacts from `.workflows/` via stem field (skim, don't deep-read)
     - Session JSONL log: find at `~/.claude/projects/$(pwd | tr '/' '-')/*.jsonl`. If multiple `.jsonl` files exist, select the most recently modified one. Parse each line as JSON; look for a `timestamp` or `ts` field. Correlate by timestamp (read ±60s window around each entry's timestamp). If the JSONL format cannot be parsed, fall back to classification from stats + artifacts only (note reduced accuracy in the output).
  6. Classifier proposes per-entry:
     - `complexity`: rote / mechanical / analytical / judgment
     - `output_type`: code-edit / research / review / relay / synthesis
  7. Present proposals in batch table format (not one-by-one):
     ```
     | File | Agent | Tokens | Complexity | Output Type |
     | ... | ... | ... | mechanical | code-edit |
     ```
  8. User options: confirm all / override specific entries / skip
  9. Rewrite YAML files in place with classification fields added
- [ ] Handle edge cases:
  - Session log not found or unparseable → classify from stats + artifacts only (note reduced accuracy in classifier output)
  - Large entry count (20+) → paginate in groups of 10
  - Already-classified entries → skip (idempotent)
- [ ] Add YAML frontmatter to SKILL.md (disable-model-invocation: false — this skill has an interactive flow)

**Note:** The brainstorm names this `/compound:classify-stats`, but `commands/compound/` is at the 8-command limit. Uses the overflow pattern established by `plugin-changes-qa` and `recover` (see brainstorm Decision 5, project memory: "per-directory command limit ~8").

### Step 10: Version Bump + QA

- [ ] Bump version in `plugins/compound-workflows/.claude-plugin/plugin.json` (MINOR — new skill + command enhancements)
- [ ] Bump version in `.claude-plugin/marketplace.json`
- [ ] Update `plugins/compound-workflows/CHANGELOG.md` with all changes
- [ ] Update component counts in `plugins/compound-workflows/README.md`: skill count +1 (classify-stats)
- [ ] Run `/compound-workflows:plugin-changes-qa` — all Tier 1 + Tier 2 checks
- [ ] Fix any findings (especially `file-counts.sh` for new skill, `context-lean-grep.sh` for new Task dispatches)

## Design Decisions

### Background Task `<usage>` Capture

When a background Task completes, Claude Code sends an automatic completion notification to the orchestrator. This notification includes `<usage>` stats — the same mechanism as foreground Tasks. The orchestrator extracts `<usage>` from the notification without calling TaskOutput. The notification content beyond `<usage>` is not processed, preserving the context-lean pattern.

Implementation order validates this: work.md (foreground, known to work) is Step 3, brainstorm.md (background, validates assumption) is Step 4.

**Stop-gate (between Step 3 and Step 4):** After completing Step 3, manually verify that a background Task dispatch (e.g., in brainstorm.md) produces a task-notification containing `<usage>`. Run a brainstorm with stats capture enabled and inspect the notification content. If `<usage>` is present, proceed to Step 4. If not, STOP and reassess Steps 4-7 before proceeding. Fallback: if background notifications lack `<usage>`, modify Steps 4-7 to poll completed Task results via TaskOutput for `<usage>` extraction instead of relying on notification content.

### Shared Reference File

Each command includes a 3-line inline instruction pointing to `plugins/compound-workflows/resources/stats-capture-schema.md`. The reference file contains the full schema, parse procedure, and error handling. This follows the brainstorm's guidance: "If the instruction grows beyond 2-3 lines, extract to a separate reference file" (see brainstorm Decision 1).

Single schema definition avoids the "contradictory palimpsest" risk flagged in the learnings (see `docs/solutions/process-analysis/2026-03-08-deepen-plan-iteration-taxonomy.md`): inline instructions that grow iteratively across 5 files become inconsistent. One reference file is maintainable.

### Stats File Collision Handling

If a user runs the same command on the same stem twice in one day, entries append to the existing file. YAML multi-document format supports this naturally — each entry has a timestamp for distinguishing runs. No collision-avoidance suffix needed.

### classify-stats as Skill

The brainstorm names this `/compound:classify-stats`. The `commands/compound/` directory is at its ~8 command limit (work, brainstorm, plan, deepen-plan, review, compound, compact-prep, setup). classify-stats becomes `/compound-workflows:classify-stats`, following the overflow pattern used by `plugin-changes-qa` and `recover` (see brainstorm Decision 5, AGENTS.md).

### Post-Dispatch Validation

Each command includes a count check after the dispatch loop: YAML documents in stats file vs expected dispatch count. Mismatch triggers a warning. This catches inline instruction reliability failures (see brainstorm Open Questions: "Inline capture reliability") without blocking execution.

### Out of Scope

- **Bash script dispatches** (plan.md readiness checks): No `<usage>` tags, out of scope
- **External model costs** (red team relay): Captures relay agent's Claude tokens only. External costs (Gemini/OpenAI) tracked by their respective billing.
- **`.workflows/work-stats/` migration**: The manually-collected dataset stays as-is. New automated stats go to `.workflows/stats/`. No migration needed.
- **`run` field for deepen-plan**: The stem + timestamp are sufficient to distinguish runs. A dedicated `run` field can be added later if xu2 analysis requires it.

## Acceptance Criteria

- [ ] All 5 orchestrator commands capture per-dispatch stats to `.workflows/stats/` YAML files
- [ ] Stats capture is toggleable via `stats_capture: false` in `compound-workflows.local.md`
- [ ] Missing `stats_capture` key defaults to enabled (no breakage for existing users)
- [ ] Failed dispatches are captured with `status: failure/timeout` and null token fields
- [ ] `<usage>` parse failures produce a visible warning (never silently skip)
- [ ] Post-dispatch validation warns on missing entries (expected vs actual count)
- [ ] ccusage snapshots are persisted by compact-prep to `.workflows/stats/`
- [ ] `/compound-workflows:classify-stats` proposes complexity and output_type labels
- [ ] Classification is batch-presented (table format, not one-by-one)
- [ ] Setup migration adds `stats_capture` and `stats_classify` keys for existing users
- [ ] Plugin QA passes with zero findings

## Sources

- **Origin brainstorm:** [`docs/brainstorms/2026-03-09-per-agent-token-instrumentation-brainstorm.md`](docs/brainstorms/2026-03-09-per-agent-token-instrumentation-brainstorm.md) — All 9 key decisions carried forward: inline capture mechanism, YAML format, per-command-run files, schema, post-hoc classification, two settings toggles, all 5 commands, failed dispatch capture, xu2 data sufficiency.
- **Solution doc:** `docs/solutions/plugin-infrastructure/2026-03-09-task-completion-usage-persistence.md` — `<usage>` format definition, scope, first dataset.
- **Manual dataset:** `.workflows/work-stats/2026-03-09-quota-optimization-v2.0.md` — Schema baseline (8 dispatches, 245k tokens).
- **Research:** `.workflows/plan-research/per-agent-token-instrumentation/agents/` — Repo research (dispatch patterns), learnings (existing solutions), SpecFlow (gap analysis).
