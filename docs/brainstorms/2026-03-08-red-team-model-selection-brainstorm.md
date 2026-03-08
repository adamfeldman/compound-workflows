# Red Team Model Selection

## What We're Building

Replace ad-hoc hardcoded model selection in red team dispatch with a precedence chain that supports user overrides and dynamic discovery. Extract the duplicated red team logic from `brainstorm.md` and `deepen-plan.md` into a shared skill.

### Scope

- New `red-team-dispatch` skill defining the model selection precedence chain, dispatch patterns, and provider templates
- `## Red Team Preferences` free-form section in both config files (`compound-workflows.md` and `compound-workflows.local.md`)
- `listmodels` call as the default discovery mechanism when no preferences are specified
- Both `brainstorm.md` and `deepen-plan.md` updated to reference the skill instead of inlining the red team logic
- QA rule updated to allow model preferences in config while keeping dispatch method as runtime-detected
- Hardcoded model examples kept in the skill as calibration guidance

### Out of Scope

- Changing the three-provider architecture (Gemini, OpenAI, Claude Opus)
- Changing Claude Opus dispatch (stays as Task subagent, not PAL)
- Adding new providers
- Mid-session model switching (detected once per session)
- Structured/validated config keys — preferences are free-form, LLM-interpreted

## Why This Approach

### Problem

Red team model names are hardcoded as inline examples in two command files (`brainstorm.md` and `deepen-plan.md`). When models change, both files must be updated manually. There is no dynamic discovery (`listmodels` is never called), no user override mechanism, and no single source of truth. The "NOT" exclusions (e.g., `NOT gemini-2.5-pro`) lack documented rationale and will accumulate as models evolve.

### Solution: Precedence Chain + Shared Skill

**Precedence chain for model selection:**

1. **Local config** (`compound-workflows.local.md` `## Red Team Preferences`) — personal preference, overrides everything. Gitignored, per-machine.
2. **Project config** (`compound-workflows.md` `## Red Team Preferences`) — team standard. Committed, shared.
3. **AGENTS.md** — free-form project conventions that may mention model preferences.
4. **`listmodels` default** — call PAL's `listmodels` tool, select highest-end model per provider, using hardcoded examples in the skill as calibration for what "highest-end" means.

**Rationale:** Local overrides project because an individual may have different CLI availability or cost constraints. Project overrides AGENTS.md because structured config (even free-form) is more intentional than conventions prose. `listmodels` is the fallback because it reflects what's actually available, not what was available when the command was written.

**Skill extraction:** Both `brainstorm.md` and `deepen-plan.md` have duplicated model selection logic. Extracting the *knowledge* (precedence chain, selection criteria, calibration examples) to a `red-team-dispatch` skill creates a single source of truth. Commands keep their dispatch *execution* steps inline (runtime detection, clink/chat calls, Task subagent, output writing) but reference the skill for which models to select. The red team prompts differ between commands (brainstorm: design review; deepen-plan: architecture risks) and stay in the commands.

### Why free-form, not structured keys

The config already uses free-form `## Workflow Instructions` for domain-specific overrides. A `## Red Team Preferences` section follows the same pattern. Free-form is:
- Flexible — users can specify models, exclusions, cost constraints, or provider preferences in natural language
- Future-proof — new providers or dispatch methods don't require config schema changes
- Consistent — matches the existing Workflow Instructions pattern

Example content:
```
## Red Team Preferences
Use gemini-3.1-pro-preview for Gemini.
Use gpt-5.4-pro for OpenAI.
Always use Opus via subagent for Claude.
```

Or more nuanced:
```
## Red Team Preferences
Prefer cost-optimized models for brainstorm red team.
Use highest-end models for deepen-plan red team.
Never use gemini-2.5-pro — produces shallow analysis.
```

### Why a skill, not an agent

The skill defines the *knowledge* — precedence chain, selection logic, dispatch templates, provider patterns. Commands orchestrate execution. This keeps commands in control of their own flow (brainstorm and deepen-plan have different pre/post red team steps) while deduplicating the shared dispatch logic.

An agent would fully encapsulate execution, but that's heavier than needed. The dispatch logic is a pattern to follow, not a standalone task.

## Key Decisions

### 1. Precedence: Local > Project > AGENTS.md > listmodels

Local config wins because an individual may have different CLI availability, cost constraints, or model access. Project config wins over AGENTS.md because it's more intentional. `listmodels` is the universal fallback.

**User rationale:** "Don't we have both local and project config?" — both layers matter. Local for personal prefs, project for team standards.

### 2. Update QA rule to allow model preferences in config

The current QA rule ("no red team in stored config") was about dispatch *method* (clink vs pal chat), not model *preferences*. The rule changes to: "no red team dispatch method in stored config" — dispatch method stays runtime-detected, model preferences are allowed.

**User rationale:** Config should store preferences (which models to use), not volatile state (which CLIs are installed).

### 3. Extract to skill, not agent

Skill = shared reference knowledge. Commands stay in control of their flow and just follow the skill's patterns.

**User rationale:** Skill deduplicates the knowledge without changing how commands work.

### 4. Free-form section, not structured keys

`## Red Team Preferences` as a free-form section in config files, consistent with existing `## Workflow Instructions` pattern. LLM interprets the content.

**User rationale:** Selected free-form over flat keys (`red_team_gemini:`) and comma-separated (`red_team_models:`). More flexible, matches existing patterns.

### 5. Keep hardcoded examples as secondary reference, select by capability

"Highest-end" is defined by capability: highest reasoning ability. The skill defines this criterion explicitly. Examples like `gemini-3.1-pro-preview` and `gpt-5.4-pro` are kept as secondary illustration of what highest-end looks like today, but the primary selector is the capability description from `listmodels` output (e.g., "Maximum performance variant... for the hardest problems").

**User rationale:** "Capability-based means highest reasoning, unless you think more is needed. Keep the examples too." Examples will go stale but the capability criterion won't — `listmodels` descriptions contain clear capability signals.

### 6. Always call `listmodels` to validate before dispatch

Call `listmodels` at the start of every red team dispatch, regardless of preference source. Use the output to:
- **Validate** that user-specified model names exist in the catalog
- **Select** the highest-reasoning model per provider when no preference is specified
- **Fall back** to the best available model if a specified model isn't found

This resolves the contradiction between "skip listmodels for exact names" and "fall back to listmodels on failure." There is no skip — `listmodels` always runs. The result stays in conversation context for the session (acceptable: it's a single tool call result, not a large file).

### 7. Precedence is guidance, not strict level-by-level lookup

The precedence chain (local > project > AGENTS.md > listmodels) is priority guidance for the LLM, not a mechanical level-by-level lookup. The LLM interprets all available config holistically — free-form text doesn't have strict boundaries between "levels." If local config says "prefer cost-optimized" and project config says "use gpt-5.4-pro," the LLM resolves the tension using the stated priority order as guidance.

**User rationale:** Free-form config and strict precedence are in tension. Reframing as "guidance" acknowledges that the LLM interprets holistically while preserving the intended priority order.

### 8. Skill has knowledge only; dispatch steps stay inline in commands

The skill defines the precedence chain, selection criteria, calibration examples, and provider patterns. The concrete step-by-step dispatch logic (runtime detection, clink/chat calls, Task subagent creation, output writing) stays inline in `brainstorm.md` and `deepen-plan.md`. This prevents execution degradation from the LLM summarizing or skipping procedural steps when reading a referenced skill.

**User rationale:** Split knowledge (skill) from execution (commands). Commands keep their dispatch steps but reference the skill for model selection logic.

## Integration Changes

### New skill: `skills/red-team-dispatch/SKILL.md`

Knowledge-only skill (`disable-model-invocation: true`). Defines:
- Model selection precedence chain as guidance (local > project > AGENTS.md > listmodels)
- "Highest-end" selection criterion: highest reasoning ability (not cost, not context size)
- `listmodels` integration: always call to validate and discover; select by capability description
- Calibration examples with rationale (current model recommendations with "NOT" exclusions and documented reasons)
- Per-provider notes (Gemini: clink preferred for file access; OpenAI: clink preferred; Claude: always Task subagent, never PAL)

Does NOT define (stays inline in commands):
- Concrete dispatch steps (runtime detection, clink/chat calls, Task subagent creation)
- Output writing patterns
- Red team review prompts (differ per command)

### Config changes

**`compound-workflows.md`** — add optional `## Red Team Preferences` section (empty by default, setup mentions it exists)

**`compound-workflows.local.md`** — add optional `## Red Team Preferences` section (for personal overrides)

**Setup** — mention the section exists during config creation. Don't prompt for model preferences (most users won't need to override).

### Command changes

**`brainstorm.md`** Phase 3.5 — replace hardcoded model names with: "Follow the `red-team-dispatch` skill for model selection. Call `listmodels` to validate." Keep dispatch execution steps inline (runtime detection, clink/chat, Task subagent, output writing). Keep brainstorm-specific red team prompt and triage steps.

**`deepen-plan.md`** Phase 4.5 — same pattern. Keep deepen-plan-specific red team prompt (architecture risks, not design review).

### QA changes

**AGENTS.md** QA Check 3 — change "No red team in stored config?" to "No red team dispatch *method* in stored config? (model preferences OK)"

**AGENTS.md** QA Check 4 — change "Red team dispatch is runtime detection, not stored config" to "Red team dispatch *method* is runtime detection. Model preferences may be in config."

### Plugin CLAUDE.md changes

Update config documentation to mention the new `## Red Team Preferences` section and its relationship to runtime detection.

### Versioning

This adds a new skill (15 → 16 skills). Version bump required. Counts in plugin.json, marketplace.json, README, CLAUDE.md, AGENTS.md all need updating. Note: the memory skill integration plan already targets v1.7.0. This feature may ship in the same release or a subsequent one — coordinate version bumps.

## Resolved Questions

### 1. Does this conflict with the "runtime not stored" principle?

No — the principle was about dispatch *method* (clink vs pal chat), which depends on volatile CLI availability. Model *preferences* are stable across sessions and appropriate for config. The QA rule is updated to reflect this distinction.

### 2. Should `listmodels` validate user-specified models?

Yes — `listmodels` is always called, even when user preferences specify exact model names. The output validates that the chosen model exists. If not found, the LLM falls back to the best available model from the catalog. This avoids "hope-based" error recovery from failed dispatch calls. (Red team finding: all three providers flagged the original "no pre-validation" stance as unreliable.)

### 3. Should the skill have `disable-model-invocation: true`?

Yes — the skill is reference material for commands, not something Claude should auto-load and act on. Users don't invoke it directly.

### 4. What about the "NOT" exclusions — should we document rationale?

Yes — the skill should document why specific models are excluded alongside the exclusion. Current exclusions (`NOT gemini-2.5-pro`, `NOT gpt-5.4`, `NOT gpt-5.2-pro`) lack rationale in MEMORY.md. The skill captures this once so it doesn't evaporate again.

## Empirical: `listmodels` Output

Called `mcp__pal__listmodels` during brainstorm to validate the fallback path. Key findings:

- **Output is well-structured**: per-provider sections, model names, context sizes, capability descriptions, aliases
- **Capability descriptions contain clear signals**: "Maximum performance variant... for the hardest problems" (gpt-5.4-pro), "Latest Gemini with 2x reasoning improvement" (gemini-3.1-pro-preview), "Cost-efficient" (gpt-5.1-codex-mini), "Fastest, cheapest" (gpt-5-nano)
- **Capability-based selection is viable**: the LLM can identify highest-reasoning models from descriptions without relying on naming conventions
- **Current highest-end per provider**: Gemini → `gemini-3.1-pro-preview`, OpenAI → `gpt-5.4-pro`
- **2 providers configured** (Gemini, OpenAI); others available but not keyed (Azure, Grok, OpenRouter, Custom)

This validates the design: `listmodels` output is rich enough for LLM-driven model selection by capability.

## Red Team Resolution Summary

Three providers (Gemini, OpenAI via Codex, Claude Opus) reviewed this brainstorm. Findings and resolutions:

| # | Finding | Severity | Flagged By | Resolution |
|---|---------|----------|------------|------------|
| C1 | No pre-validation; "natural" error handling unreliable | CRITICAL | Gemini, OpenAI | **Valid — always call `listmodels` to validate before dispatch** (Decision 6) |
| S1 | Calibration examples won't survive naming changes | SERIOUS | All three | **Valid — select by capability (highest reasoning), keep examples as secondary** (Decision 5) |
| S2 | AGENTS.md precedence level underspecified | SERIOUS | Opus, OpenAI | **Kept as-is** — AGENTS.md is guidance, not strict lookup. User: "LLM interprets holistically" |
| S3 | Contradiction between free-form and strict precedence | SERIOUS | Opus | **Valid — reframed as guidance, not strict level-by-level lookup** (Decision 7) |
| S4 | Skill extraction risks execution degradation | SERIOUS | Gemini | **Valid — split: knowledge in skill, dispatch steps stay inline** (Decision 8) |
| S5 | `listmodels` untested | SERIOUS | Opus | **Valid — called and validated during brainstorm** (see Empirical section) |
| M1 | Environment variables not considered | MINOR | Gemini | Acknowledged — env vars bypass LLM but don't match existing config patterns. Not adopting. |
| M2 | AGENTS.md trust boundary risk | MINOR | OpenAI | Acknowledged — mitigated by precedence guidance; config overrides AGENTS.md. |
| M3 | Stale listmodels cache | MINOR | OpenAI | Acknowledged — session-level retention in context is acceptable for a single tool call. |
| M4 | Skill may not reduce command size | MINOR | Opus | Acknowledged — true, but the win is single source of truth for model selection knowledge, not size reduction. |
| M5 | Precedence chain conflict handling | MINOR | Opus | Acknowledged — free-form nature makes this inherently LLM-interpreted. Guidance framing handles this. |
| M6 | Session caching mechanism undefined | MINOR | Opus | Acknowledged — context retention for one tool call result is acceptable and doesn't violate context-lean. |
| M7 | review.md not addressed | MINOR | Opus | Acknowledged — review.md has no red team dispatch today. Skill is available if it gains it later. |
| M8 | Free-form vs structured tension | MINOR | Opus | Resolved by guidance framing (Decision 7). |
| M9 | Skill context burden | MINOR | Opus | Mitigated by keeping skill as knowledge-only (small) and dispatch steps inline. |
