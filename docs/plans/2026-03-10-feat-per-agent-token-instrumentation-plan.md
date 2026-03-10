---
title: "Per-Agent Token Instrumentation"
type: feat
status: completed
date: 2026-03-10
origin: docs/brainstorms/2026-03-09-per-agent-token-instrumentation-brainstorm.md
bead: voo
related_beads: [xu2, 22l]
---

# Per-Agent Token Instrumentation

## Overview

Automate per-dispatch stats collection across all 5 orchestrator commands (work, brainstorm, plan, deepen-plan, review). Task/Agent completion notifications return `<usage>total_tokens, tool_uses, duration_ms</usage>` — persist these to per-command-run YAML files for cost/complexity analysis. Add a standalone classification skill and ccusage snapshot persistence.

Key decisions from [brainstorm](docs/brainstorms/2026-03-09-per-agent-token-instrumentation-brainstorm.md):
- Multi-document YAML (LLMs read/rewrite YAML fluently during classification; bash constructs it reliably for capture — see brainstorm Decision 2, updated by red team)
- Per-command-run files in `.workflows/stats/` (see brainstorm Decision 3)
- Bash helper script (`capture-stats.sh`) for deterministic atomic append — orchestrator extracts `<usage>` and calls the script (red team: all 3 providers flagged LLM-mediated file I/O as top risk)
- 4-tier complexity + output_type dimension, classified post-hoc (see brainstorm Decision 5)
- Classification decoupled from compact-prep as standalone skill (see brainstorm Decision 5)
- Two independent settings toggles, missing = enabled (see brainstorm Decision 6)
- All 5 commands from day one (see brainstorm Decision 7)
- Warn on `<usage>` parse failure — never silently skip (see brainstorm Open Questions)

### What Changed Since the Archived Plan

The archived plan (2026-03-09) was written before v2.0-2.2 command rewrites. All 5 instrumentation targets have structurally changed:

- **plan.md** gained Phase 6.8 (3-provider red team, 3 Agent dispatches + 1 Agent MINOR triage) and Phase 6.9 (conditional readiness re-check, 2-3 Task dispatches). Phase 6.7 verify-only re-dispatches (2-3 Tasks after consolidation) are also new instrumentation points.
- **deepen-plan.md** migrated all research/review batches from Task to Agent dispatch (v2.1). Convergence-advisor is now a named dispatch. Red team Phase 4.5 uses Agent dispatch.
- **brainstorm.md** added 6th red team dimension and MINOR triage dispatch (background Task).
- **work.md** still uses Task dispatch (foreground sequential) — no structural change, but worktree execution creates a stats persistence gap (see Worktree Handling below).
- **review.md** still uses Task dispatch (all background) — no structural change.

The core capture mechanism (`<usage>` tag extraction) is empirically validated and carries forward. The execution model changed significantly: the archived plan used LLM-mediated read-then-write-all; this plan uses a bash helper script (`capture-stats.sh`) for deterministic atomic append, addressing the top risk identified by all 3 red team providers. Agent tool dispatches produce identical `<usage>` to Task dispatches (validated 2026-03-09, see `memory/project.md`).

## Implementation Steps

### Step 1: Settings Infrastructure

Add `stats_capture` and `stats_classify` toggles to the config template and setup flow.

**Files:** `plugins/compound-workflows/commands/compound/setup.md`, `plugins/compound-workflows/skills/setup/SKILL.md`

- [x] In setup.md Step 7b, add to `compound-workflows.local.md` template after `gh_cli`:
  ```
  stats_capture: true
  stats_classify: true
  ```
- [x] In setup.md Step 7d (migration), add detection: if `compound-workflows.local.md` exists but lacks `stats_capture` key, append both keys with `true` defaults
- [x] Mirror the same template and migration changes in `plugins/compound-workflows/skills/setup/SKILL.md`
- [x] No interactive prompt needed — keys default to enabled silently (see brainstorm Decision 6: "Missing keys = enabled")

**Design note:** Each orchestrator command checks `stats_capture` inline — if the key is missing or any value other than `false`, capture proceeds. Setup migration adds keys for explicitness but isn't required for the feature to work.

### Step 2: Stats Capture Script + Reference File

Create a bash helper script for deterministic atomic append and a shared reference document with the YAML schema. Each orchestrator command includes a short inline instruction: extract `<usage>`, call the script.

**Files:** `plugins/compound-workflows/scripts/capture-stats.sh` (new), `plugins/compound-workflows/resources/stats-capture-schema.md` (new directory + file)

- [x] Create `plugins/compound-workflows/scripts/capture-stats.sh`:
  - Usage: `bash capture-stats.sh <stats-file> <command> <agent> <step> <model> <stem> <bead> <run_id> <usage_line>`
  - Parses `<usage_line>` with sed/awk to extract `total_tokens`, `tool_uses`, `duration_ms`
  - Constructs YAML entry with all fields (including `run_id`, `timestamp`, `status`, null complexity/output_type)
  - Appends atomically via `cat >> <stats-file>` (no read-then-rewrite — `>>` is atomic for single writes)
  - Prepends `---` document separator before each entry
  - If `<usage_line>` is empty or "null": writes entry with null token fields, status=failure
  - If `<usage_line>` is unparseable: writes entry with null fields, status=failure, prints warning to stderr: "Stats capture: `<usage>` format may have changed — consider filing a bug"
  - `<usage>` format health check: validate that the line matches `<usage>total_tokens: \d+, tool_uses: \d+, duration_ms: \d+</usage>` pattern. If not, warn but still attempt best-effort extraction.
  - Exit 0 always (stats capture should never block command execution)
  - Timeout entry variant: `bash capture-stats.sh --timeout <stats-file> <command> <agent> <step> <model> <stem> <bead> <run_id>` — writes entry with null token fields, status=timeout
- [x] Create `plugins/compound-workflows/resources/` directory
- [x] Write `stats-capture-schema.md` containing:
  - Full YAML schema with field descriptions (including `run_id`)
  - Where to find `<usage>`: "Look for `<usage>...</usage>` in the Task/Agent response (foreground inline) or in the completion notification (background). The format is identical in all four scenarios."
  - How to call `capture-stats.sh`: extract the full `<usage>...</usage>` line, pass as last argument
  - File naming: `.workflows/stats/<date>-<command>-<stem>.yaml`
  - Post-dispatch validation: count YAML documents in stats file vs completed dispatches, warn on mismatch (include missing agent names in warning, not just count delta)
  - Worktree handling section (see below)
  - Model resolution algorithm (see below)
  - Note: `<usage>` is an observed API, not a documented contract. A future Claude Code update may require parser updates in capture-stats.sh.
- [x] Empirically verify worktree cwd: before implementing Steps 3-7, run a simple test during Step 2 to confirm which directory the orchestrator's cwd resolves to during worktree-based work execution. If the orchestrator enters the worktree, the capture instruction must use an absolute path to the main repo's `.workflows/stats/` (derive via `git worktree list --porcelain | head -1`).

**Schema (reference copy — authoritative version in the file):**
```yaml
---
command: work
bead: 22l
stem: quota-optimization
agent: general-purpose
step: "1"
model: opus
run_id: a1b2c3d4
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
| agent | Dispatch agent name | `general-purpose`, `repo-research-analyst`, etc. |
| step | Varies by command (see table) | Step number (work) or agent role name (others) |
| model | Resolved per algorithm below | opus / sonnet / haiku |
| run_id | Generated at command start | Short UUID (`uuidgen \| cut -c1-8`), shared by all entries in one command run |
| tokens | `<usage>` total_tokens | null if `<usage>` absent |
| tools | `<usage>` tool_uses | null if `<usage>` absent |
| duration_ms | `<usage>` duration_ms | null if `<usage>` absent |
| timestamp | System time at capture | ISO 8601 with Z timezone |
| status | Dispatch outcome | success / failure / timeout |
| complexity | Classifier (post-hoc) | rote / mechanical / analytical / judgment / null |
| output_type | Classifier (post-hoc) | code-edit / research / review / relay / synthesis / null |

**Model resolution algorithm (4-step priority chain):**
1. If the dispatch includes an explicit `model:` parameter (Agent tool dispatch override), use that value.
2. Read the dispatched agent's YAML frontmatter `model:` field. If it specifies a concrete model (e.g., `model: sonnet`), use that.
3. If the agent has `model: inherit` or no model field, check `CLAUDE_CODE_SUBAGENT_MODEL` env var. If set, use that value.
4. If no env var, use the parent context's model (typically `opus` for orchestrator commands).

**Required implementation:** Check the env var once at the start of each command run (alongside `mkdir -p` and config check) via `echo $CLAUDE_CODE_SUBAGENT_MODEL` and cache the result. Pass the cached value to `capture-stats.sh` as the `<model>` argument for agents with `model: inherit`. This is required (not optional) because xu2's Sonnet routing analysis depends on accurate model attribution — recording "opus" when the agent ran on Sonnet corrupts the downstream dataset.

**Stem derivation per command:**

| Command | Derivation | Example |
|---------|-----------|---------|
| work | Plan filename: strip date prefix + `-plan.md` suffix. Fallback: branch name. | `quota-optimization` |
| brainstorm | topic-stem (already derived in Phase 1.1) | `per-agent-token-instrumentation` |
| plan | plan-stem (already derived in Phase 1) | `per-agent-token-instrumentation` |
| deepen-plan | plan-stem (from plan filename, already derived) | `per-agent-token-instrumentation` |
| review | topic-stem (already derived in Step 2) | `feat-user-dashboard` |

**Step derivation per command:**

| Command | Step Value | Example |
|---------|-----------|---------|
| work | Bead issue number or sequential loop counter | `"1"`, `"3"` |
| brainstorm | Agent role name | `"repo-research-analyst"` |
| plan | Agent role name | `"learnings-researcher"` |
| deepen-plan | Category--agent-name | `"research--security-sentinel"`, `"synthesis--convergence-advisor"` |
| review | Agent role name | `"typescript-reviewer"` |

**Note:** The `step` field is polymorphic — it holds a bead issue number when `command=work`, and an agent role name for all other commands. Downstream consumers should always filter by `command` before aggregating by `step`.

**Timeout detection:** Set status to `timeout` when a background Task/Agent does not produce a completion notification within the command's configured timeout period (e.g., plan.md's 5-minute red team timeout). If the task eventually completes after being marked as timed out, do not retroactively update the entry.

#### Worktree Handling (work.md)

`/compound:work` runs subagents inside git worktrees by default. Worktrees have independent `.workflows/` directories (gitignored, local-only). Worktree cleanup destroys `.workflows/stats/` along with the worktree.

**Solution:** The orchestrator (not the subagent) captures stats. The orchestrator runs in the main conversation context, which is the main repo — NOT the worktree. The inline stats capture instruction writes to `.workflows/stats/` relative to the orchestrator's cwd (main repo root). Subagent completion notifications arrive in the main conversation context regardless of where the subagent ran.

**Key invariant:** Stats capture always happens in the orchestrator's context (main repo), never inside a subagent. This is enforced by the capture pattern: the orchestrator reads `<usage>` from the Task/Agent response or completion notification and writes the entry itself. Background agents cannot write stats anyway (permission denied for background writes — see `memory/project.md`).

**Validation:** After implementing Step 3 (work.md), verify that running `/compound:work` with a worktree produces stats files in the main repo's `.workflows/stats/`, not in the worktree's `.workflows/stats/`. Check: `ls .workflows/stats/` from the main repo root after a work run.

### Step 3: work.md Instrumentation

work.md dispatches foreground sequential Tasks — the simplest capture path. `<usage>` is in the inline Task response. Implement first to validate the core mechanism before tackling background dispatches.

**Files:** `plugins/compound-workflows/commands/compound/work.md`

- [x] Add `mkdir -p .workflows/stats` early in the command flow (before the dispatch loop)
- [x] Add PLUGIN_ROOT resolution bash block (same pattern as plan.md Phase 6.7) before the dispatch loop, to resolve the path to `$PLUGIN_ROOT/resources/stats-capture-schema.md`
- [x] Add config check: read `compound-workflows.local.md`, check `stats_capture`. If `false`, skip all stats capture (do not read the schema file). If missing or any other value, proceed.
- [x] Generate `run_id` at command start: `RUN_ID=$(uuidgen | cut -c1-8)`
- [x] Cache model resolution: check `CLAUDE_CODE_SUBAGENT_MODEL` env var once, cache for all dispatches
- [x] After each foreground Task dispatch in the Phase 2 dispatch loop:
  - Extract the `<usage>...</usage>` line from the Task response
  - Call: `bash $PLUGIN_ROOT/scripts/capture-stats.sh <stats-file> work <agent> <step> <model> <stem> <bead> $RUN_ID "<usage-line>"`
  - The script handles YAML construction, atomic append, error handling, and parse failure warnings
  - Derive stem from plan filename (strip date prefix + `-plan.md` suffix; fallback: branch name)
- [x] Instrument Phase 3 optional reviewer (`code-simplicity-reviewer`, background): capture from completion notification if dispatched
- [x] After dispatch loop completes, add post-dispatch validation: count YAML documents in stats file vs completed dispatches (bead count + 1 if reviewer ran), warn if mismatch
- [x] Edge case: no plan file (ad-hoc work) → derive stem from branch name

**Inline instruction template (~4 lines in command, references schema file):**

```
### Stats Capture
If stats_capture ≠ false in compound-workflows.local.md: after each Task/Agent completion, extract the `<usage>...</usage>` line and call `bash $PLUGIN_ROOT/scripts/capture-stats.sh <stats-file> work <agent> <step> <model> <stem> <bead> $RUN_ID "<usage-line>"`. See [resolved stats-capture-schema.md path] for field derivation rules. After all dispatches, validate entry count matches completed dispatch count (include missing agent names in warning).
```

**Stop-gate:** After completing Step 3 and running at least one work execution with stats capture, verify:
1. Stats file exists at `.workflows/stats/<date>-work-<stem>.yaml`
2. YAML entries match completed dispatches
3. Token/tool/duration fields are populated (not null)
4. File is in the main repo (not a worktree) if worktree was used

This validates the capture mechanism before proceeding to Steps 4-7. The stop-gate is confirmatory (Agent `<usage>` was already validated empirically), but provides a formal checkpoint.

### Step 4: brainstorm.md Instrumentation

brainstorm.md dispatches all background Tasks. `<usage>` appears in automatic Task completion notifications. This step validates background capture.

**Files:** `plugins/compound-workflows/commands/compound/brainstorm.md`

- [x] Add `mkdir -p .workflows/stats` before Phase 1.1
- [x] Add PLUGIN_ROOT resolution bash block (same pattern as plan.md Phase 6.7) to resolve the path to `$PLUGIN_ROOT/resources/stats-capture-schema.md`
- [x] Add config check: read `stats_capture` from `compound-workflows.local.md`
- [x] Add inline stats capture instruction for background Tasks: "When you receive a background Task completion notification containing `<usage>`, extract the tag and append a YAML entry to the stats file. Do not call TaskOutput."
- [x] Apply across all dispatch phases:
  - Phase 1.1 research: `repo-research-analyst`, `context-researcher` (2 agents)
  - Phase 3.5 Step 1 red team: 3 providers (3 agents — `red-team-relay` × 2 + `general-purpose` × 1)
  - Phase 3.5 Step 3a: MINOR triage (1 agent, **background** — capture from completion notification, NOT inline response)
- [x] Set: command=brainstorm, bead=null, stem=topic-stem, step=agent role name
- [x] After each dispatch phase completes, validate entry count vs dispatched agent count
- [x] Model field: use the 4-step resolution algorithm. For `red-team-relay` dispatched with `model: sonnet`, record sonnet (step 1 — dispatch override). For `general-purpose` with no override, check env var (step 3), then default to opus (step 4).

**Note:** The 6th red team dimension (problem selection) is a prompt-level change within existing dispatches — no additional instrumentation points.

### Step 5: plan.md Instrumentation

plan.md has the most dispatch points: background research agents, foreground readiness agents, mixed Agent/Task dispatch in red team phases, and conditional re-check/verify dispatches.

**Files:** `plugins/compound-workflows/commands/compound/plan.md`

- [x] Add `mkdir -p .workflows/stats` before Phase 1
- [x] Add PLUGIN_ROOT resolution bash block (same pattern as plan.md Phase 6.7) to resolve the path to `$PLUGIN_ROOT/resources/stats-capture-schema.md`
- [x] Add config check: read `stats_capture`
- [x] Instrument background Task dispatches (Phases 1, 1.5b, 3): extract `<usage>` from completion notifications
  - Phase 1: `repo-research-analyst`, `learnings-researcher` (2 agents)
  - Phase 1.5b (conditional): `best-practices-researcher`, `framework-docs-researcher` (0-2 agents)
  - Phase 3: `spec-flow-analyzer` (1 agent)
- [x] Instrument Phase 6.7 readiness dispatches:
  - Semantic-checks agent (background Task → completion notification)
  - `plan-readiness-reviewer` (foreground Task → inline response)
  - `plan-consolidator` (foreground Task, conditional → inline response)
- [x] Instrument Phase 6.7 verify-only re-dispatches (conditional, after consolidation):
  - Re-dispatched semantic-checks agent (background Task → completion notification)
  - Re-dispatched `plan-readiness-reviewer` (foreground Task → inline response)
  - Use step=`"semantic-checks-verify"` and `"plan-readiness-reviewer-verify"` to distinguish from initial dispatches
- [x] Instrument Phase 6.8 red team dispatches (Agent tool):
  - `red-team-relay` Gemini (background Agent → completion notification)
  - `red-team-relay` OpenAI (background Agent → completion notification)
  - `general-purpose` Claude Opus (background Agent → completion notification)
  - `general-purpose` MINOR triage (foreground Agent → inline response)
- [x] Instrument Phase 6.9 conditional re-check dispatches (if PLAN_CHANGED=true — set by plan.md Phase 6.8.6 hash comparison; dispatches only run when red team triage modified the plan):
  - Same agent set as Phase 6.7: semantic-checks (background Task), plan-readiness-reviewer (foreground Task), plan-consolidator (foreground Task, conditional)
  - Use step=`"semantic-checks-recheck"`, `"plan-readiness-reviewer-recheck"`, `"plan-consolidator-recheck"` to distinguish
- [x] Skip: bash script dispatches (stale-values.sh, broken-references.sh, audit-trail-bloat.sh) — no `<usage>`, not agent dispatches
- [x] Set: command=plan, bead=null, stem=plan-stem, step=agent role name (with suffixes for verify/recheck variants)
- [x] Validate entry count after all phases complete. Account for conditionals (external research, consolidator, verify, red team, re-check).

### Step 6: review.md Instrumentation

review.md dispatches all background Tasks — straightforward capture from completion notifications.

**Files:** `plugins/compound-workflows/commands/compound/review.md`

- [x] Add `mkdir -p .workflows/stats` at start
- [x] Add PLUGIN_ROOT resolution bash block (same pattern as plan.md Phase 6.7) to resolve the path to `$PLUGIN_ROOT/resources/stats-capture-schema.md`
- [x] Add config check: read `stats_capture`
- [x] Instrument all background Task dispatches: extract `<usage>` from completion notifications
  - Standard agents (always): `typescript-reviewer`, `pattern-recognition-specialist`, `architecture-strategist`, `security-sentinel`, `performance-oracle`, `code-simplicity-reviewer`, `agent-native-reviewer` (7 agents)
  - Conditional: `data-migration-expert`, `deployment-verification-agent`, `frontend-races-reviewer` (0-3 agents)
- [x] Set: command=review, bead=null, stem=topic-stem, step=agent role name
- [x] Track dispatched agent count (standard + conditional). Validate entry count against actual dispatched count after all completions. Warn if entry count < dispatched count.

### Step 7: deepen-plan.md Instrumentation

deepen-plan.md has the most agents per run (15-25+): batched background Agent dispatches, foreground synthesis/triage, red team, and readiness checks.

**Files:** `plugins/compound-workflows/commands/compound/deepen-plan.md`

- [x] Add `mkdir -p .workflows/stats` early in Phase 0
- [x] Add PLUGIN_ROOT resolution bash block (same pattern as plan.md Phase 6.7) to resolve the path to `$PLUGIN_ROOT/resources/stats-capture-schema.md`
- [x] Add config check: read `stats_capture`
- [x] Instrument Phase 3 batched background Agent dispatches: extract `<usage>` from each completion notification across all batches.
  - Research agents: `repo-research-analyst`, `learnings-researcher`, `best-practices-researcher`, `framework-docs-researcher`, `git-history-analyzer`, `context-researcher` (variable — depends on manifest)
  - Review agents: `security-sentinel`, `architecture-strategist`, `performance-oracle`, `code-simplicity-reviewer`, `agent-native-reviewer`, etc. (variable)
- [x] Instrument Phase 4 foreground Agent dispatches:
  - Synthesis agent (foreground Agent → inline response)
  - MINOR triage agent (foreground Agent → inline response)
- [x] Instrument Phase 4.5 red team dispatches (background Agent):
  - `red-team-relay` Gemini, OpenAI (background Agent → completion notification)
  - `general-purpose` Claude Opus (background Agent → completion notification)
  - Phase 4.5 Step 2 MINOR triage (foreground Agent → inline response)
- [x] Instrument convergence-advisor dispatch (Phase 5.75/6 — background Agent → completion notification, if dispatched)
- [x] Instrument Phase 5.5 readiness check dispatches:
  - Semantic-checks agent (background Agent → completion notification)
  - `plan-readiness-reviewer` (foreground Agent → inline response)
  - `plan-consolidator` (foreground Agent, conditional → inline response)
- [x] Set: command=deepen-plan, bead=null, stem=plan-stem, step=category--agent-name (e.g., `research--security-sentinel`, `review--architecture-strategist`, `red-team--gemini`, `synthesis--plan-synthesizer`, `synthesis--convergence-advisor`)
- [x] Stats go to centralized YAML only — do NOT add stats to the deepen-plan manifest (see brainstorm Decision 4: manifest tracks run status, not cost/complexity)
- [x] After all phases complete, validate total entry count vs total dispatched agent count. Single total check (not per-batch) — simpler than cross-referencing manifest batch groupings. [red-team--gemini, simplified per triage]

### Step 8: compact-prep ccusage Snapshot Persistence

Modify compact-prep to persist ccusage data as a YAML snapshot in the stats directory.

**Files:** `plugins/compound-workflows/skills/compact-prep/SKILL.md`

- [x] After existing Step 7 (Daily Cost Summary), if ccusage data was successfully retrieved and parsed:
  - Add `mkdir -p .workflows/stats`
  - Write ccusage snapshot YAML to `.workflows/stats/<date>-ccusage-snapshot.yaml`
  - If file exists, append with `---` separator via `cat >>` (atomic append — same pattern as capture-stats.sh, NOT read-then-write-all)
  - Schema:
    ```yaml
    ---
    type: ccusage-snapshot
    timestamp: 2026-03-09T18:30:00Z
    total_cost_usd: 212.71
    input_tokens: 1234567
    output_tokens: 456789
    ```
- [x] Capture these 5 core fields. If ccusage output includes additional fields (e.g., cache_read_tokens, cache_write_tokens, per_model_breakdown), include them as additional YAML keys. The schema is extensible — unknown fields are preserved.
- [x] If ccusage not available or parse failed, skip (no snapshot — don't error)
- [x] Add brief note in Step 7 output: "ccusage snapshot saved to .workflows/stats/"

### Step 9: classify-stats Skill

Create a new skill for post-hoc complexity and output_type classification. This is a skill (not a command) because `commands/compound/` is at capacity (8/8). Invoked as `/compound-workflows:classify-stats`.

**Files:** `plugins/compound-workflows/skills/classify-stats/SKILL.md` (new directory + file)

- [x] Create `plugins/compound-workflows/skills/classify-stats/` directory
- [x] Write SKILL.md implementing the classification flow:
  1. Check `stats_classify` in `compound-workflows.local.md` — skip if `false`
  2. Read all `.workflows/stats/*.yaml` files (excluding `ccusage-snapshot` entries by checking for `type: ccusage-snapshot`)
  3. Filter to unclassified entries (complexity is null)
  4. If none: "All stats entries are already classified."
  5. Dispatch a classifier subagent (`Agent general-purpose`) that reads two input layers:
     - YAML stats entries (the unclassified entries — agent name, command, step, model, token count)
     - Artifacts from `.workflows/` via stem field (skim, don't deep-read — the actual agent output reveals what work was done)
     - **Note:** Session JSONL log correlation was considered but deferred to a future version (see bead for v2 stats). Stats + artifacts are sufficient for reliable classification in most cases — agent name + command + token count predict complexity well (e.g., security-sentinel during review = analytical/review, red-team-relay = mechanical/relay).
  6. Classifier proposes per-entry:
     - `complexity`: rote / mechanical / analytical / judgment
     - `output_type`: code-edit / research / review / relay / synthesis
  7. Present proposals in batch table format (not one-by-one):
     ```
     | File | Agent | Tokens | Complexity | Output Type |
     | ... | ... | ... | mechanical | code-edit |
     ```
  8. User options: confirm all / override specific entries / skip
  9. Rewrite YAML files in place with classification fields added (strategy: read full file, modify in memory, write to `<filename>.tmp`, then `mv` to replace original — prevents partial-write corruption if interrupted)
- [x] Handle edge cases:
  - Large entry count (20+) → paginate in groups of 10
  - Already-classified entries → skip (idempotent)
  - Partial stats files (low entry count relative to command type) → surface as "possibly incomplete" with a warning
- [x] Add YAML frontmatter to SKILL.md (disable-model-invocation: false — this skill has an interactive flow)

**Note:** The brainstorm names this `/compound:classify-stats`, but `commands/compound/` is at the 8-command limit. Uses the overflow pattern established by `plugin-changes-qa` and `recover` (see brainstorm Decision 5, `memory/project.md`: "per-directory command limit ~8").

### Step 10: Version Bump + QA

- [x] Bump version in `plugins/compound-workflows/.claude-plugin/plugin.json` (MINOR — new skill + command enhancements)
- [x] Bump version in `.claude-plugin/marketplace.json`
- [x] Update `plugins/compound-workflows/CHANGELOG.md` with all changes
- [x] Update component counts in `plugins/compound-workflows/README.md`: skill count +1 (classify-stats)
- [x] Update agent/skill/command counts in `plugins/compound-workflows/CLAUDE.md` if needed
- [x] Run `/compound-workflows:plugin-changes-qa` — all Tier 1 + Tier 2 checks
- [x] Fix any findings (especially `file-counts.sh` for new skill, `context-lean-grep.sh` for new capture instructions)

## Design Decisions

### Bash Script for Capture, Not LLM File I/O

All 3 red team providers (Gemini, OpenAI, Claude Opus) independently flagged LLM-mediated read-then-write-all as the top risk. `capture-stats.sh` handles all mechanical work: YAML construction, atomic `>>` append, `<usage>` parsing, error handling. The orchestrator's responsibility shrinks to: (1) extract the `<usage>` line from the response/notification, (2) call the script with the right arguments.

This eliminates:
- O(N²) read-then-rewrite scaling for deepen-plan's 20+ agents
- LLM truncation/corruption risk on growing files
- Most inline instruction compliance risk (the script is deterministic)

**Why not a PostToolUse hook?** A hook would be fully deterministic and zero-context-cost. But PostToolUse fires when a tool call completes — for background agents (`run_in_background: true`), the tool call completes immediately at dispatch (returning "agent launched"), not when the agent finishes. Background completion notifications are async events, not tool call results. Since most dispatches are background, a hook would only capture foreground dispatches. The script approach works uniformly for both. [red-team--opus, see `.workflows/plan-research/per-agent-token-instrumentation/red-team--opus.md`]

**Why YAML, not JSONL?** The brainstorm rejected JSONL because LLMs produce malformed JSON. With bash doing capture, that concern is moot — bash can construct either format reliably. YAML was retained because the classify-stats skill (Step 9) is an LLM subagent that reads and rewrites entries to add classification fields. LLMs read and rewrite YAML more fluently than JSONL. Human readability of `cat .workflows/stats/*.yaml` is also better.

### Orchestrator-Owns-Capture

Stats are always captured by the orchestrator (main conversation context) from the Task/Agent response or completion notification. Subagents never write stats files directly. This is enforced by design:

1. Background agents cannot prompt for Write permissions (see `memory/project.md`: "Background agents get Write/Edit permission denied")
2. The orchestrator's cwd is the main repo (verified empirically in Step 2), so `.workflows/stats/` resolves correctly
3. The `<usage>` tag is in the response/notification received by the orchestrator, not available inside the subagent

### Background Task `<usage>` Capture

When a background Task/Agent completes, the orchestrator receives an automatic completion notification containing `<usage>`. The orchestrator extracts `<usage>` from the notification without calling TaskOutput. The notification content beyond `<usage>` is not processed, preserving the context-lean pattern.

Both Task and Agent dispatches produce identical `<usage>` format in completion notifications (validated 2026-03-09 with 3 Agent dispatches — see `memory/project.md`).

### Shared Reference File

Each command includes a ~4-line inline instruction pointing to `plugins/compound-workflows/resources/stats-capture-schema.md`. The reference file contains the full schema, field derivation rules, and capture-stats.sh usage. This follows the brainstorm's guidance: "If the instruction grows beyond 2-3 lines, extract to a separate reference file" (see brainstorm Decision 1).

**Conditional injection not needed:** The ~4-line inline instruction is static text with an "if stats_capture ≠ false" gate. The LLM reads and skips it when disabled — same pattern as other conditional gates throughout these commands (e.g., "if external research is needed..."). Conditional bash injection would add architecture complexity across 5 files to save ~20 tokens of context. [red-team--gemini, disagreed: gate pattern is well-established and 4 lines is trivial]

Single schema definition avoids contradictory palimpsest risk (see `docs/solutions/process-analysis/2026-03-08-deepen-plan-iteration-taxonomy.md`): inline instructions that grow iteratively across 5 files become inconsistent. One reference file is maintainable.

### Run Identity

Each command run generates a `run_id` (short UUID via `uuidgen | cut -c1-8`) at startup. All entries in that run share the same `run_id`. This disambiguates same-day same-stem reruns that land in the same file. The `run_id` is generated once, cached, and passed to every `capture-stats.sh` call. [red-team--openai: resolved CRITICAL contradiction between "one file per run" and same-day append semantics]

### classify-stats as Skill

`commands/compound/` is at the 8-command limit. classify-stats becomes `/compound-workflows:classify-stats`, following the overflow pattern used by `plugin-changes-qa` and `recover` (see brainstorm Decision 5, AGENTS.md).

### Post-Dispatch Validation

Each command includes a count check after the dispatch loop: YAML documents in stats file vs expected dispatch count. Mismatch triggers a warning that includes the names of missing agents (not just the count delta) to enable diagnosis. For commands with conditionals (plan.md, review.md, deepen-plan.md), the orchestrator tracks dispatched agent count dynamically. For deepen-plan, per-batch validation catches truncation early before files grow large.

### Interrupted Runs

Partial stats files are the natural result of command interruptions (Ctrl+C, compaction, crash). Post-dispatch validation never runs for interrupted commands. The classify-stats skill surfaces files with suspiciously low entry counts relative to command type as "possibly incomplete." No run header/footer mechanism needed — timestamp analysis and entry count thresholds are sufficient for v1.

### Out of Scope

- **Bash script dispatches** (plan.md/deepen-plan.md readiness check scripts): No `<usage>` tags, not agent dispatches
- **External model costs** (red team relay): Captures relay agent's Claude tokens only. External costs (Gemini/OpenAI) tracked by their respective billing.
- **`.workflows/work-stats/` migration**: The manually-collected dataset stays as-is. New automated stats go to `.workflows/stats/`. No migration needed.
- **Session JSONL log correlation for classify-stats**: Deferred to v2 (new bead). Stats + artifacts are sufficient for v1 classification. JSONL correlation adds marginal accuracy for edge cases but requires parsing undocumented internal directory structures. Test manually first before building into the plugin.
- **Programmatic YAML parsing**: Stats files are designed for LLM consumption first (`cat .workflows/stats/*.yaml`). Programmatic analysis (e.g., Python scripts) can use standard YAML multi-document parsers but is not a design requirement.

## Acceptance Criteria

- [x] All 5 orchestrator commands capture per-dispatch stats to `.workflows/stats/` YAML files
- [x] Stats capture is toggleable via `stats_capture: false` in `compound-workflows.local.md`
- [x] Missing `stats_capture` key defaults to enabled (no breakage for existing users)
- [x] Failed dispatches are captured with `status: failure/timeout` and null token fields
- [x] `<usage>` parse failures produce a visible warning (never silently skip)
- [x] Post-dispatch validation warns on missing entries (expected vs actual count)
- [x] Worktree-based work.md execution produces stats in the main repo's `.workflows/stats/`, not the worktree
- [x] Model resolution uses the 4-step priority chain (dispatch override > YAML > env var > parent)
- [x] ccusage snapshots are persisted by compact-prep to `.workflows/stats/`
- [x] `/compound-workflows:classify-stats` proposes complexity and output_type labels
- [x] Classification is batch-presented (table format, not one-by-one)
- [x] Setup migration adds `stats_capture` and `stats_classify` keys for existing users
- [x] Plugin QA passes with zero findings

## Work Execution Notes

**Parallel opportunities:** Steps 1 and 2 are independent (settings vs schema file). Steps 3-7 each touch a different command file and depend only on Step 2 (schema). Steps 8 and 9 are independent (compact-prep vs classify-stats skill). Step 10 depends on all others.

Suggested dispatch plan for `/compound:work`:
1. Steps 1 + 2 in parallel (separate files, no dependencies)
2. Steps 3-7 in parallel (each touches a different command file, all reference schema from Step 2)
3. Steps 8 + 9 in parallel (separate files)
4. Step 10 last (version bump + QA)

**Release split not needed:** Steps 8-9 touch entirely separate files (compact-prep SKILL.md, new classify-stats SKILL.md) with no overlap to Steps 1-7. They run in parallel with Steps 3-7 in the dispatch plan above. Splitting doubles the QA cycle (5 bash scripts + 3 LLM agents per release) for no risk reduction, since the steps don't interact. [red-team--opus, disagreed: no file overlap + QA is per-release not per-step]

**Large steps:** Step 5 (plan.md) and Step 7 (deepen-plan.md) are the largest — plan.md has 4 dispatch phases with conditional sub-dispatches, deepen-plan has batched agents. The work orchestrator should ensure subagents read the full command file and the schema file for context.

## Sources

- **Origin brainstorm:** [`docs/brainstorms/2026-03-09-per-agent-token-instrumentation-brainstorm.md`](docs/brainstorms/2026-03-09-per-agent-token-instrumentation-brainstorm.md) — All 9 key decisions carried forward: inline capture mechanism, YAML format, per-command-run files, schema, post-hoc classification, two settings toggles, all 5 commands, failed dispatch capture, xu2 data sufficiency.
- **Archived plan:** `docs/plans/archive/2026-03-09-feat-per-agent-token-instrumentation-plan.md` — Previous plan (stale, pre-v2.0-2.2). Architecture validated, per-command checklists updated.
- **Solution doc:** `docs/solutions/plugin-infrastructure/2026-03-09-task-completion-usage-persistence.md` — `<usage>` format definition, scope, first dataset.
- **Manual dataset:** `.workflows/work-stats/2026-03-09-quota-optimization-v2.0.md` — Schema baseline (8 dispatches, 245k tokens).
- **Research:** `.workflows/plan-research/per-agent-token-instrumentation/agents/` — Repo research (current dispatch patterns), learnings (institutional knowledge), SpecFlow (gap analysis).
