---
title: "Native Agent Discovery for deepen-plan"
type: feat
status: active
date: 2026-03-09
origin: docs/brainstorms/2026-03-09-native-agent-discovery-brainstorm.md
bead: wgl
related_beads: [voo]
---

# Native Agent Discovery for deepen-plan

## Overview

Replace deepen-plan's Phase 2 filesystem-based agent and skill discovery with Claude Code's native subagent_type registry. The current approach uses `find ~/.claude/plugins/cache` to crawl the filesystem, read YAML frontmatter, and build agent/skill rosters — this is fragile (sandbox restrictions break `find` silently), generates bash approval cascades before useful work begins, and reconstructs information already available natively.

Key decisions from [brainstorm](docs/brainstorms/2026-03-09-native-agent-discovery-brainstorm.md):
- Dynamic discovery (D) primary with hardcoded fallback (A) and invariant check (see brainstorm Decision 1)
- Agent descriptions via manifest.json from system prompt context (see brainstorm Decision 2)
- Stack-based filtering unchanged — applied after discovery (see brainstorm Decision 3)
- Agent tool dispatch for `model` parameter override (see brainstorm Decision 4)
- Skills discovery also migrates away from filesystem (see brainstorm Decision 5)
- Ships before voo; voo updates afterward for all 5 commands (see brainstorm Decision 6)

## Implementation Steps

### Step 1: Rewrite Phase 2 as a Single Coherent Block

**Critical implementation note:** Rewrite Steps 2a-2e as a single coherent unit — do NOT patch individual lines. Each incremental edit to a plan file introduces ~0.5-1.0 new inconsistencies; after 3-4 patches, most findings become edit-induced, not genuine design bugs (see `docs/solutions/process-analysis/2026-03-08-deepen-plan-iteration-taxonomy.md`). Write the entire new Phase 2 in one pass.

**File:** `plugins/compound-workflows/commands/compound/deepen-plan.md`

#### Step 1a: Agent Discovery (replaces current Steps 2c-2d)

Replace filesystem-based agent discovery with subagent_type registry reading. This is the core change.

**Current (remove):** Steps 2c and 2d — the `find ~/.claude/plugins/cache -path "*/agents/*.md"` commands, `find .claude/agents`, `find ~/.claude/agents`, YAML frontmatter reading, and the agent filtering/logging logic.

**New (replace with):**

- [ ] Replace Step 2c with the following instruction prose for the command prompt:
  > "Read the list of available subagent_types from your system prompt. For each entry whose subagent_type contains `:review:` or `:research:` in its path, extract: the agent name (last colon-delimited segment, e.g., `security-sentinel` from `compound-workflows:review:security-sentinel`) and the description (from the subagent_type listing). Skip entries containing `:workflow:`, `:design:`, or `:docs:` in their path. Build the agent roster from these filtered entries."
- [ ] The instruction must be explicit about what to look for — LLMs do not automatically enumerate subagent_types unless prompted (specflow Gap 2)
- [ ] For each discovered agent, extract: name (last segment after `:`) and description (from system prompt)
- [ ] Write discoveries into manifest.json `agents` array with format:
  ```json
  {
    "name": "security-sentinel",
    "subagent_type": "compound-workflows:review:security-sentinel",
    "description": "Security auditor focused on vulnerabilities and OWASP compliance",
    "type": "review",
    "source": "dynamic",
    "model": "inherit",
    "file": "agents/run-<N>/review--security-sentinel.md",
    "status": "pending"
  }
  ```
- [ ] Add `subagent_type` field to manifest entries (new — needed for Agent tool dispatch in Phase 3)

**Invariant check (hardcoded fallback):**

- [ ] After dynamic discovery, verify that the roster includes at minimum: `security-sentinel` and `architecture-strategist`
- [ ] If any invariant agent is missing, merge with a hardcoded fallback list of compound-workflows core agents:
  ```
  compound-workflows:review:security-sentinel
  compound-workflows:review:architecture-strategist
  compound-workflows:review:code-simplicity-reviewer
  compound-workflows:review:performance-oracle
  compound-workflows:review:pattern-recognition-specialist
  compound-workflows:review:typescript-reviewer
  compound-workflows:review:python-reviewer
  compound-workflows:review:frontend-races-reviewer
  compound-workflows:review:data-integrity-guardian
  compound-workflows:review:data-migration-expert
  compound-workflows:review:agent-native-reviewer
  compound-workflows:review:deployment-verification-agent
  compound-workflows:review:schema-drift-detector
  compound-workflows:research:best-practices-researcher
  compound-workflows:research:repo-research-analyst
  compound-workflows:research:context-researcher
  compound-workflows:research:framework-docs-researcher
  compound-workflows:research:learnings-researcher
  compound-workflows:research:git-history-analyzer
  ```
- [ ] For fallback agents, set description from hardcoded defaults (sourced from current CLAUDE.md Agent Registry descriptions)
- [ ] Log to user: "Dynamic discovery found N agents. Invariant check: [passed / merged M agents from fallback]."

**User-defined agent support:**

- [ ] Also include subagent_types that do NOT have a `compound-workflows:` prefix but match `*:review:*` or `*:research:*` patterns — these are user-defined agents (e.g., from `.claude/agents/review/go-reviewer.md`)
- [ ] User-defined agents are NOT in the invariant check — their absence is expected
- [ ] Discovery guardrails: compound-workflows agents take priority in name conflicts. The 30-agent cap from filesystem discovery is removed — realistic count (19 compound-workflows + a few user-defined) is well under any practical limit, and LLMs count unreliably (specflow Gap 3). If agent sprawl becomes a concern, add a cap in a future version with manifest-level counting.
- [ ] Deduplication: if a user-defined agent has the same name as a compound-workflows agent (e.g., user creates their own `security-sentinel`), keep only the compound-workflows version. The user-defined one is silently dropped with a note in the user-facing discovery report.

**Invariant check matching logic:**

- [ ] Match on agent name portion only (last segment after `:`), not full subagent_type string. E.g., check for `security-sentinel` in the roster regardless of prefix (`compound-workflows:review:security-sentinel` or `compound:review:security-sentinel`)
- [ ] Merge semantics: add-missing-only (union). If dynamic discovery found 12 agents but missed security-sentinel, add only security-sentinel from the fallback list. Preserve all dynamically-discovered agents including user-defined ones. Never replace the entire roster.
- [ ] If both invariant agents are missing AND the total roster is < 5, treat as total failure — replace with the full fallback list (19 agents)

**File path derivation from subagent_type:**

- [ ] Convert subagent_type to output file path: extract category (second segment) and name (third segment), format as `<category>--<name>.md`. E.g., `compound-workflows:review:security-sentinel` → `review--security-sentinel.md`
- [ ] For user-defined agents without the standard 3-segment format, use `review--<full-name>.md` (assume review category for `*:review:*` matched agents)

#### Step 1b: Skills Discovery (replaces current Step 2a)

Replace filesystem-based skills discovery with system prompt reading.

**Current (remove):** Step 2a — the `find ~/.claude/plugins/cache -type d -name "skills"` command and the SKILL.md reading loop for plugin-installed skills.

**New (replace with):**

- [ ] Replace Step 2a with the following instruction prose:
  > "Read the list of available skills from your system prompt. Skills appear in a separate section from subagent_types — they are listed with names and descriptions (e.g., 'compound-workflows:brainstorming', 'compound-workflows:disk-persist-agents'). For each skill, check if its name or description overlaps with the plan's technologies or domain areas. Include matched skills in the manifest."
- [ ] Skills are NOT subagent_types — they appear in a different system prompt section (the available skills list, not the subagent_type registry). The filter pattern is name/description keyword matching, not `:review:`/`:research:` pattern matching.
- [ ] For matched skills, add manifest entries with type `"skill"` and fields: `name`, `description`, `type: "skill"`, `file: "agents/run-<N>/skill--<name>.md"`, `status: "pending"`. No `subagent_type` field for skills (they are dispatched differently).
- [ ] Retain `ls .claude/skills/` and `ls ~/.claude/skills/` for project-local skills — these search the project/user directory (not plugin cache) and don't hit sandbox issues
- [ ] Remove only the `find ~/.claude/plugins/cache -type d -name "skills"` line

**Note:** Learnings discovery (Step 2b: `find docs/solutions/ -name "*.md"`) stays as-is — it searches the project directory, not the plugin cache, and doesn't hit sandbox issues (see brainstorm Decision 5).

#### Step 1b2: Phase 5 (Recovery) Backward Compatibility

Add a conditional dispatch check in the Phase 5 recovery flow:

- [ ] When reading a manifest entry for re-dispatch: if the entry has a `subagent_type` field, dispatch via Agent tool using that value. If not (pre-migration manifest), dispatch via Task using the `name` field with inline role description (old syntax). This ensures runs started before the migration can still be recovered.

#### Step 1c: Stack Filtering (Step 2e unchanged)

Stack-based relevance assessment stays exactly as-is. The filtering logic is applied after discovery — it works regardless of whether agents were discovered via filesystem or subagent_type registry. No changes needed (see brainstorm Decision 3).

#### Step 1d: Manifest Schema Update

The manifest.json agent entry format gains new fields to support subagent_type dispatch.

- [ ] Add `subagent_type` field (string, e.g., `"compound-workflows:review:security-sentinel"`) — needed for Agent tool dispatch
- [ ] Add `source` field: `"dynamic"` for D-discovered, `"fallback"` for A-merged, `"user-defined"` for non-compound-workflows agents — replaces `source_plugin` which was filesystem-specific
- [ ] Add `model` field: the model to pass to Agent dispatch (e.g., `"sonnet"`, `"inherit"`, `"opus"`)
- [ ] Keep existing fields: `name`, `description`, `type`, `file`, `status`
- [ ] Remove `source_plugin` field — replaced by `source` (no longer relevant when discovery isn't filesystem-based)

### Step 2: Update All Task Dispatches to Agent Tool

Change every `Task` dispatch in deepen-plan.md to `Agent` with `subagent_type` parameter. This is done as part of the Phase 2 rewrite (Step 1) for discovery-related dispatches, plus separate passes for other phases.

**File:** `plugins/compound-workflows/commands/compound/deepen-plan.md`

#### Phase 3 dispatches (review/research agents):

- [ ] Change dispatch syntax from `Task [agent-name]` to `Agent(subagent_type: "<value from manifest>", ...)`:
  ```
  Agent(subagent_type: "compound-workflows:review:security-sentinel", model: "inherit", run_in_background: true, prompt: "
  You are a security auditor focused on vulnerabilities and OWASP compliance...
  === OUTPUT INSTRUCTIONS (MANDATORY) ===
  ...")
  ```
- [ ] For research agents with `model: sonnet` in frontmatter: pass `model: "sonnet"` explicitly in the Agent dispatch
- [ ] For review agents with `model: inherit` in frontmatter: omit the `model` parameter — let the Agent tool use the agent's frontmatter setting (consistent with brainstorm Decision 4: model override is opt-in for cost optimization, not forced)
- [ ] Inline role descriptions MUST still be included in the prompt — they give context even with `subagent_type` routing

#### Phase 4 dispatches (synthesis, MINOR triage):

- [ ] Change `Task general-purpose` synthesis dispatch to `Agent(subagent_type: "general-purpose", prompt: "...")`
- [ ] Change `Task general-purpose` MINOR triage dispatch similarly

#### Phase 4.5 dispatches (red team):

- [ ] Change `Task red-team-relay (run_in_background: true)` to `Agent(subagent_type: "compound-workflows:workflow:red-team-relay", model: "sonnet", run_in_background: true, prompt: "...")`
- [ ] Change `Task general-purpose (run_in_background: true)` (Opus red team) to `Agent(subagent_type: "general-purpose", run_in_background: true, prompt: "...")`
- [ ] Keep all other red team logic unchanged (runtime detection, 3-provider parallel, MCP wrapper pattern preserved — both clink AND chat fallback paths stay wrapped)

#### Phase 5.75/6 dispatches (readiness):

- [ ] Change `Task convergence-advisor` to `Agent(subagent_type: "compound-workflows:workflow:convergence-advisor", ...)`
- [ ] Change `Task plan-readiness-reviewer` to `Agent(subagent_type: "compound-workflows:workflow:plan-readiness-reviewer", ...)`
- [ ] Change `Task plan-consolidator` to `Agent(subagent_type: "compound-workflows:workflow:plan-consolidator", ...)`
- [ ] Change semantic checks dispatch to use Agent tool
- [ ] Keep foreground vs background dispatch decisions unchanged — only the tool syntax changes

**Context-lean convention preserved:** Agent dispatches include OUTPUT INSTRUCTIONS blocks identical to current Task dispatches. The context-lean pattern is tool-agnostic. `context-lean-grep.sh` must be updated if it checks for `Task` keyword specifically — verify during QA (Step 4).

**Monitoring unchanged:** Agent background completions include `<usage>` with identical format to Task completions (validated — see brainstorm Q1). Polling for file existence remains the same.

### Step 3: Prefix and Syntax Validation (Implementation-Time)

- [ ] Validate both the prefix format AND the dispatch syntax before writing the Phase 2 rewrite:
  1. Dispatch a trivial Agent call to confirm the syntax works: `Agent(subagent_type: "compound-workflows:review:code-simplicity-reviewer", model: "haiku", run_in_background: true, prompt: "Return 'ok'")`
  2. If `compound-workflows:` fails, try `compound:` prefix
  3. Confirm `run_in_background: true` produces an async completion notification (not a blocking call)
  4. Confirm `<usage>` appears in the completion notification
- [ ] If the prefix must change, do a find-and-replace across the entire Phase 2 rewrite block (including the hardcoded fallback list in Step 1a)
- [ ] Add a defensive note in the command text: "Use `compound-workflows:` prefix for subagent_type. If dispatch fails with unknown subagent_type, try `compound:` prefix."
- [ ] Confirm that Agent tool error handling matches Task: 3-minute timeout, `status: "timeout"` or `status: "failed"` manifest values. If Agent has different failure modes, document them in the Phase 3 error handling section.

### Step 4: Version Bump + QA

- [ ] Bump version in `plugins/compound-workflows/.claude-plugin/plugin.json` (PATCH — internal refactor, no new features)
- [ ] Bump version in `.claude-plugin/marketplace.json`
- [ ] Update `plugins/compound-workflows/CHANGELOG.md` with changes
- [ ] Run `/compound-workflows:plugin-changes-qa` — all Tier 1 + Tier 2 checks
- [ ] Fix any findings — watch specifically for:
  - `stale-references.sh`: will flag old `Task` dispatch references if any were missed
  - `context-lean-grep.sh`: verify it handles `Agent(subagent_type:` syntax for OUTPUT INSTRUCTIONS checks (may need grep pattern update in the script if it only matches `Task`)
  - Tier 2 role description reviewer: verify agent names in Agent dispatches still match

## Design Decisions

### Dynamic Discovery as LLM Self-Reading

The command instructs the LLM to read its own available subagent_types from the system prompt. This is unconventional but mitigated:
- **Invariant check** catches partial omissions (core agents always present)
- **Hardcoded fallback** catches total parsing failure (empty roster → full fallback list)
- **User-defined agents** are additive — their absence is harmless

The alternative (hardcoded-only, Approach A) would work but loses user-defined agent extensibility. User rationale: "I want D so users can add their own review agents for other programming langs." (see brainstorm Decision 1, Q10)

### Agent Tool vs Task Tool

Both support `subagent_type`. Agent is chosen because it has a `model` parameter for dispatch-time model override — validated empirically (dispatched with `model: "haiku"`, completed in 995ms vs 13s at opus). This enables cost optimization without editing agent YAML frontmatter.

The migration is scoped to deepen-plan only. Other commands (review, brainstorm, plan, work) keep Task dispatch. voo (bead voo) will standardize Agent dispatch across all 5 commands. (see brainstorm Decision 4, Q3)

### Skills Discovery Simplification

Skills discovery migrates to reading from the system prompt's available skills list, supplemented by local `ls .claude/skills/` (project-local skills). The fragile `find ~/.claude/plugins/cache -type d -name "skills"` path is removed.

Learnings discovery (`find docs/solutions/`) stays filesystem-based — it searches the project directory, not the plugin cache (see brainstorm Decision 5).

### All Phases Migrate to Agent Dispatch

The brainstorm Q8 said "Phases 4, 4.5 stay on Task" based on the assumption that `general-purpose` and `red-team-relay` are not subagent_type dispatches. This was partially incorrect — both are valid subagent_types (`general-purpose` is the default agent type in the system prompt; `red-team-relay` is a named agent with `model: sonnet`). Migrating all phases avoids mixed dispatch patterns in one command and simplifies the mental model for implementers and future maintainers. User rationale: "why wouldn't we migrate all?" — consistency across the command outweighs the brainstorm's scope limitation.

### Scope: deepen-plan Only

Only deepen-plan is modified. It's the only command that does filesystem discovery — review, brainstorm, and plan all hardcode their agent names. This limits blast radius. voo standardizes the Agent dispatch pattern across all 5 commands later, which also adds stats instrumentation. (see brainstorm Q3, Decision 6)

### Phase 2 as Single Rewrite

Repo research surfaced a key institutional learning: each incremental edit to a command file introduces ~0.5-1.0 new inconsistencies (see `docs/solutions/process-analysis/2026-03-08-deepen-plan-iteration-taxonomy.md`). Deepen-plan's Phase 2 is ~80 lines of tightly coupled discovery logic. Patching individual lines will create a palimpsest of layered corrections. Instead, write the entire new Phase 2 (Steps 2a-2e) as a single coherent block, replacing the old block wholesale.

### context-lean-grep.sh Compatibility

The QA script `context-lean-grep.sh` checks for OUTPUT INSTRUCTIONS on Task dispatches. If it regex-matches on `Task` keyword specifically, it will miss Agent dispatches and produce false negatives (no findings when OUTPUT INSTRUCTIONS are actually missing). Verify the grep pattern during QA — may need updating to match both `Task` and `Agent` dispatch syntax.

### Backward Compatibility with Pre-Migration Manifests

Phase 5 (Recovery) reads manifest.json to resume interrupted runs. Pre-migration manifests won't have `subagent_type` or `source` fields. The rewrite should include a backward compatibility check: if a manifest entry lacks `subagent_type`, treat the `name` field as the agent identifier and dispatch via `Task` (old syntax). This ensures runs started before the migration can still be recovered after the plugin updates. (surfaced by specflow Gap 19)

### Skills Matching Quality

Current skills discovery reads full SKILL.md content for domain matching. After migration, the LLM sees only skill names and short descriptions from the system prompt — less information for relevance matching. This is an acceptable tradeoff: skills were rarely matched in practice (repo research shows manifest entries are almost exclusively review/research agents), and the description is sufficient for domain-level filtering. Local skills (`ls .claude/skills/`) still trigger SKILL.md reading for detailed matching. (surfaced by specflow Gap 23)

### Version as PATCH

This is an internal refactor of deepen-plan's discovery mechanism. No new commands, agents, or skills. No breaking changes to user-facing interfaces. The output (agent roster, manifest, dispatched agents) is functionally identical — only the discovery path changes.

## Acceptance Criteria

- [ ] deepen-plan Phase 2 agent discovery uses subagent_type registry (no `find ~/.claude/plugins/cache -path "*/agents/*.md"`)
- [ ] deepen-plan Phase 2 skills discovery uses system prompt (no `find ~/.claude/plugins/cache -type d -name "skills"`)
- [ ] Invariant check verifies security-sentinel and architecture-strategist are always present
- [ ] Hardcoded fallback activates when invariant agents are missing
- [ ] User-defined agents (non-compound-workflows subagent_types matching `*:review:*` or `*:research:*`) are included in discovery
- [ ] Phase 3 uses Agent tool dispatch with `subagent_type` and `model` parameters
- [ ] Manifest.json entries include `subagent_type`, `description`, `source`, and `model` fields
- [ ] Red team and readiness dispatches also use Agent tool
- [ ] Stack-based filtering (Step 2e) works identically to before
- [ ] No `find` commands touch `~/.claude/plugins/cache` anywhere in deepen-plan.md
- [ ] Plugin QA passes with zero findings

## Out of Scope

- **Other commands** (review, brainstorm, plan, work) — they don't do filesystem discovery and keep Task dispatch. voo standardizes later.
- **Learnings discovery** (Step 2b: `find docs/solutions/`) — searches project directory, not plugin cache
- **Agent YAML frontmatter reading** — descriptions come from system prompt or hardcoded defaults now
- **Third-party plugin trust gating** — deferred; current cap of 30 agents and compound-workflows priority provide basic protection

## Sources

- **Origin brainstorm:** [`docs/brainstorms/2026-03-09-native-agent-discovery-brainstorm.md`](docs/brainstorms/2026-03-09-native-agent-discovery-brainstorm.md) — 6 decisions carried forward: D+A discovery with invariant check, manifest descriptions, stack filtering, Agent dispatch, skills migration, voo sequencing
- **Current implementation:** `plugins/compound-workflows/commands/compound/deepen-plan.md` — Phase 2 (Steps 2a-2e) is the change target
- **Comparison pattern:** `plugins/compound-workflows/commands/compound/review.md` — hardcoded Task dispatch roster
- **Related plan:** `docs/plans/2026-03-09-feat-per-agent-token-instrumentation-plan.md` (bead voo) — needs updating after wgl ships to adopt Agent dispatch across all 5 commands
- **Agent registry:** `plugins/compound-workflows/CLAUDE.md` — 26 agents with categories, dispatch info, model config
- **Brainstorm red team findings:** `.workflows/brainstorm-research/native-agent-discovery/red-team--{gemini,openai,opus}.md`
- **Institutional learnings:** `docs/solutions/process-analysis/2026-03-08-deepen-plan-iteration-taxonomy.md` — palimpsest risk, single-pass rewrite pattern
- **Plan research:** `.workflows/plan-research/native-agent-discovery/agents/` — repo-research.md (dispatch patterns, manifest schema), learnings.md (8 implementation recommendations), specflow.md (24 gaps identified, key gaps incorporated)
