---
title: Context-Lean Enforcement + QA Enhancement
type: feat
status: active
date: 2026-03-08
origin: docs/brainstorms/2026-03-08-context-lean-enforcement-brainstorm.md
---

# Context-Lean Enforcement + QA Enhancement

## Summary

Four deliverables in a single plan:

1. **Fix 3 context-lean violations** — MCP red team wrapping in brainstorm.md + deepen-plan.md, disk-persist in resolve-pr-parallel
2. **Create `/compound:plugin-changes-qa` command** — hybrid QA: Tier 1 bash scripts for structural checks + Tier 2 LLM agents for semantic analysis
3. **Add hook-based enforcement** — PostToolUse hook that runs Tier 1 scripts after git commits touching plugin files
4. **Swarms interim guardrail** — beta warning banner + bead for broader review at GA

Target version: **1.8.0** (new command + significant enhancements = MINOR bump).

## Key Decisions Carried Forward

All decisions from the brainstorm (see brainstorm: `docs/brainstorms/2026-03-08-context-lean-enforcement-brainstorm.md`):

1. **MCP calls wrapped in Task subagents** — empirically validated. Subagents inherit MCP tool access. Write exact unedited response to disk before summarizing.
2. **resolve-pr-parallel gets disk-persist** — real (small) violation, not just consistency.
3. **orchestrating-swarms deferred to GA** — beta warning banner only. Broader review tracked in bead.
4. **"Context-lean" is the canonical term** — centralized note in CLAUDE.md, not 22 agent file edits.
5. **Command named `/compound:plugin-changes-qa`** — descriptive of what it validates.
6. **Hybrid QA architecture** — bash scripts for structural, LLM agents for semantic.
7. **Hook-based enforcement** — PostToolUse on Bash (Option B from planning session). Hook runs Tier 1 scripts after commits, surfaces findings as feedback. Cannot trigger slash commands directly (Claude Code limitation). Sentinel file `.workflows/.work-in-progress` suppresses hook during `/compound:work`.

**Planning session decision:** The command **automates** the existing 4 AGENTS.md checks. AGENTS.md is updated to document what the command does internally and reference the command for execution. (User: "automate them")

## Phase 1: Fix Context-Lean Violations + Swarms Banner

All steps touch different files — **execute in parallel**.

### Step 1.1: Wrap MCP Red Team in brainstorm.md

**File:** `plugins/compound-workflows/commands/compound/brainstorm.md`
**Section:** Phase 3.5 (lines ~115-219)

**What changes:**
- [ ] Provider 1 (Gemini) `mcp__pal__clink`/`mcp__pal__chat` calls → wrapped in `Task general-purpose (run_in_background: true)` subagent
- [ ] Provider 2 (OpenAI) `mcp__pal__clink`/`mcp__pal__chat` calls → wrapped in same pattern
- [ ] Provider 3 (Opus) → **unchanged** (already compliant)
- [ ] Execution note (line ~219) → update from "Gemini and OpenAI as parallel MCP calls, Opus as a background Task" to "all three as background Tasks"

**What stays unchanged:**
- Runtime detection (`which gemini`, `which codex`) stays in orchestrator
- AskUserQuestion for provider preference stays in orchestrator
- The red team prompt text stays identical
- Output file paths stay identical (`.workflows/brainstorm-research/<topic-stem>/red-team--gemini.md`, etc.)

**Transformation pattern** — convert each provider from:

```
*If Gemini CLI is available* — use `clink` (direct file access, richer analysis):

mcp__pal__clink:
  cli_name: gemini
  role: codereviewer
  prompt: "..."
  absolute_file_paths: [...]

After receiving the response (from either method), write it to: <output-path>
```

To:

```
*If Gemini CLI is available* — use `clink` via subagent:

Task general-purpose (run_in_background: true): "
You are a red team dispatch agent. Call the Gemini model for a red team review and persist the result to disk.

Call this MCP tool:

mcp__pal__clink:
  cli_name: gemini
  role: codereviewer
  prompt: "<same prompt text as before>"
  absolute_file_paths: [<same files as before>]

=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write the EXACT, UNEDITED response from the MCP tool call to: <output-path>
Do not edit, summarize, or reformat the response in the file. The file should contain exactly what the MCP tool returned.
After writing the file, return ONLY a 2-3 sentence summary of the key findings.
"
```

Apply the same transformation to the `pal chat` fallback variant (replace `mcp__pal__clink` with `mcp__pal__chat` and its parameters). Apply to both Gemini and OpenAI providers.

**Reference:** The existing Opus provider (Provider 3, line ~198-217) is the gold standard — it already uses this exact Task subagent + OUTPUT INSTRUCTIONS pattern. Match its structure.

### Step 1.2: Wrap MCP Red Team in deepen-plan.md

**File:** `plugins/compound-workflows/commands/compound/deepen-plan.md`
**Section:** Phase 4.5 (lines ~335-464)

**Same transformation as Step 1.1** but preserve deepen-plan-specific differences:
- [ ] Different prompt text (reviews "a software implementation plan" not a brainstorm)
- [ ] Passes TWO files to `absolute_file_paths` (plan path + synthesis summary), not one
- [ ] Different output paths (`.workflows/deepen-plan-research/<plan-stem>/`)
- [ ] Update execution note (line ~463) same as Step 1.1

### Step 1.3: Add Disk-Persist to resolve-pr-parallel

**File:** `plugins/compound-workflows/skills/resolve-pr-parallel/SKILL.md`
**Section:** Step 3 (lines ~48-55)

- [ ] Add `mkdir -p .workflows/resolve-pr/<pr-number>/agents/` before agent dispatch
- [ ] Add OUTPUT INSTRUCTIONS to each `Task pr-comment-resolver` dispatch:
  ```
  === OUTPUT INSTRUCTIONS (MANDATORY) ===
  Write your complete Comment Resolution Report to: .workflows/resolve-pr/<pr-number>/agents/comment-<N>.md
  After writing the file, return ONLY a 2-3 sentence summary.
  ```
- [ ] Update the synthesis step to read resolution reports from disk instead of from agent return values

### Step 1.4: Add Swarms Beta Warning Banner

**File:** `plugins/compound-workflows/skills/orchestrating-swarms/SKILL.md`

- [ ] Add warning banner immediately after `# Claude Code Swarm Orchestration` header (line 8), before the `---` separator:

```markdown
> **Beta / Unreviewed:** This skill is beta. The patterns shown do not include disk-persist
> for teammate outputs. Do not copy these patterns without adding OUTPUT INSTRUCTIONS per
> the disk-persist-agents skill. A broader context-lean review is tracked for when swarms go GA.
```

### Step 1.5: Create Bead for Swarms Broader Review

- [ ] Run: `bd create --title="Broader context-lean review of orchestrating-swarms skill" --description="When swarms go GA, do a full context-lean compliance review of the orchestrating-swarms skill. The skill is 1500+ lines and currently lacks disk-persist for teammate outputs. Deferred per brainstorm decision: user said to review when swarms are GA." --type=task --priority=4`

## Phase 2: QA Infrastructure

### Step 2.1: Create Tier 1 Bash Scripts

**Location:** `plugins/compound-workflows/scripts/plugin-qa/`

Create 4 scripts. All follow the same conventions:
- Shebang: `#!/usr/bin/env bash`
- Exit 0 always (even if findings). Exit 1 only for script errors.
- Output format: structured markdown with `## Findings` section
- Accept plugin root path as `$1` argument (default: auto-detect from script location)
- macOS compatible (no `realpath`, use `cd "$(dirname "$0")" && pwd -P`)

**a. `stale-references.sh`**
- [ ] Grep all `.md` files under commands/, agents/, skills/ for:
  - `aworkflows:` or `aworkflows/` (old namespace)
  - References to commands/skills/agents that don't exist (cross-reference against actual files)
- [ ] Output: file path, line number, matched pattern for each finding

**b. `file-counts.sh`**
- [ ] Count `.md` files in `agents/` (recursive, excluding non-agent files)
- [ ] Count directories in `skills/` (each skill is a directory with SKILL.md)
- [ ] Count `.md` files in `commands/compound/`
- [ ] Read declared counts from CLAUDE.md, plugin.json, marketplace.json, README.md
- [ ] Compare actual vs declared; report mismatches

**c. `truncation-check.sh`**
- [ ] Verify each command file has YAML frontmatter (`---` delimiters)
- [ ] Verify each command file is > 20 lines (catch truncated files)
- [ ] Verify each agent file has YAML frontmatter
- [ ] Report files that appear incomplete

**d. `context-lean-grep.sh`**
- [ ] Grep command files for Pattern B violations: `After receiving the response` followed by `write it to` (indicates MCP response transiting orchestrator)
- [ ] Grep for `TaskOutput` calls (banned)
- [ ] Grep command files for `Task` dispatches that lack `OUTPUT INSTRUCTIONS` (check within 20 lines after each `Task` line)
- [ ] Report: file, line, pattern name, severity

- [ ] `chmod +x` all scripts after creation

### Step 2.2: Create `/compound:plugin-changes-qa` Command

**File:** `plugins/compound-workflows/commands/compound/plugin-changes-qa.md`

Depends on: Step 2.1 (scripts must exist at known paths)

**Frontmatter:**
```yaml
---
name: plugin-changes-qa
description: Run structural and semantic QA checks on the compound-workflows plugin
user-invocable: true
---
```

**Command structure:**
- [ ] **Phase 1: Tier 1 (deterministic scripts)**
  - Discover all `.sh` files in `plugins/compound-workflows/scripts/plugin-qa/`
  - Run each script via Bash tool, passing plugin root path
  - Collect all outputs
  - If any script exits 1: report script error, continue with remaining scripts
- [ ] **Phase 2: Tier 2 (semantic agents)** — dispatch with disk-persist pattern
  - Create output directory: `mkdir -p .workflows/plugin-qa/agents/`
  - **Agent A: context-lean-reviewer** — Read all command files, verify orchestrator context is minimized (no large agent returns, MCP wrapped in subagents, OUTPUT INSTRUCTIONS present). Write to `.workflows/plugin-qa/agents/context-lean-review.md`
  - **Agent B: role-description-reviewer** — Compare agent dispatches in commands against agent file definitions. Check that role descriptions, allowed-tools, and model specifications match. Write to `.workflows/plugin-qa/agents/role-description-review.md`
  - **Agent C: command-completeness-reviewer** — Verify commands use AskUserQuestion (not raw questions), have proper phase/step numbering, include all required sections. Write to `.workflows/plugin-qa/agents/completeness-review.md`
  - All three agents dispatched in parallel with `run_in_background: true`
  - Monitor completion via `ls .workflows/plugin-qa/agents/`
- [ ] **Phase 3: Aggregation**
  - Read all Tier 1 script outputs and Tier 2 agent files
  - Present aggregated summary to user: N findings by severity, grouped by check
  - If zero findings: "All checks passed."
  - No codebase mutation — findings are informational only

### Step 2.3: Create Hook Configuration + Script

Depends on: Step 2.1 (hook script runs Tier 1 scripts)

**Hook script:** `.claude/hooks/plugin-qa-check.sh`

- [ ] Check if the Bash command was `git commit` (match against `$tool_input.command`)
  - If not a git commit: exit 0 immediately (fast path)
- [ ] Check sentinel file: if `.workflows/.work-in-progress` exists, exit 0 (suppress during `/compound:work`)
- [ ] Check if committed files include plugin dirs:
  ```bash
  git diff --name-only HEAD~1 HEAD | grep -qE '^plugins/compound-workflows/(commands|agents|skills)/'
  ```
  - If no plugin files changed: exit 0
- [ ] Run all Tier 1 scripts from `plugins/compound-workflows/scripts/plugin-qa/`
- [ ] If findings exist: exit 2 with findings in stderr + message "Run `/compound:plugin-changes-qa` for full QA (includes semantic checks)"
- [ ] If clean: exit 0
- [ ] `chmod +x` after creation

**Hook configuration:** `.claude/settings.json`

- [ ] Create/update `.claude/settings.json` with:
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/plugin-qa-check.sh",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

**Note:** If `.claude/settings.json` already exists with other content (e.g., permissions), merge the hooks key — do not overwrite.

## Phase 3: Documentation Updates

All steps touch different files — **execute in parallel**.

### Step 3.1: Update CLAUDE.md

**File:** `plugins/compound-workflows/CLAUDE.md`

- [ ] Add **Context-Lean Convention** section (after "Command Conventions", before "Testing Changes"):
  - Define "context-lean" as the canonical principle
  - Rule: all commands dispatching agents MUST include OUTPUT INSTRUCTIONS blocks
  - Rule: TaskOutput is banned — poll file existence instead
  - Rule: MCP tool responses must be wrapped in subagents
  - Reference: `skills/disk-persist-agents/SKILL.md` for the canonical pattern
  - Exception: MCP responses may transit orchestrator context when the orchestrator needs to make routing/triage decisions. Document the rationale inline.
- [ ] Add note to Agent Registry section (after the agent table):
  "All agents expect callers to include OUTPUT INSTRUCTIONS per the `disk-persist-agents` skill. See Context-Lean Convention below."
- [ ] Update command count from 9 to 10 (if referenced in CLAUDE.md)

### Step 3.2: Update README.md

**File:** `plugins/compound-workflows/README.md`

- [ ] In "Key Concept: Disk-Persisted Agents" section (~line 89): add "context-lean" as the named principle
- [ ] Ensure "context-lean" appears as a defined term, not just descriptive phrases
- [ ] Update command count from 9 to 10 if referenced

### Step 3.3: Update AGENTS.md

**File:** `AGENTS.md`

- [ ] Replace the 4 manual QA check prompts with documentation of what `/compound:plugin-changes-qa` automates:
  - **Tier 1 (scripts):** stale references, file counts, truncation, context-lean patterns
  - **Tier 2 (agents):** context-lean architecture, role descriptions, command completeness
- [ ] Add: "Run `/compound:plugin-changes-qa` to execute all checks. The hook in `.claude/settings.json` auto-triggers Tier 1 checks after commits touching plugin files."
- [ ] Update command count if referenced
- [ ] **Coordination note:** If the plan-readiness agents plan (bead `h0g`) has already modified AGENTS.md, adapt Check numbering accordingly

## Phase 4: Version Bump

Depends on: all prior phases complete.

### Step 4.1: Bump Version to 1.8.0

- [ ] `plugins/compound-workflows/.claude-plugin/plugin.json`:
  - `"version"`: `"1.7.0"` → `"1.8.0"`
  - `"description"`: update command count from "9 commands" to "10 commands"
- [ ] `.claude-plugin/marketplace.json`:
  - `"version"`: `"1.7.0"` → `"1.8.0"`
  - `"ref"`: `"v1.7.0"` → `"v1.8.0"`
  - Update command count in description
- [ ] `plugins/compound-workflows/CHANGELOG.md`: add 1.8.0 entry:
  - Fixed: MCP red team responses wrapped in subagents (brainstorm.md, deepen-plan.md)
  - Fixed: resolve-pr-parallel now uses disk-persist pattern
  - Added: `/compound:plugin-changes-qa` command (hybrid Tier 1 scripts + Tier 2 agents)
  - Added: PostToolUse hook for automated Tier 1 QA on plugin file commits
  - Added: Context-Lean Convention section in CLAUDE.md
  - Changed: AGENTS.md QA checks replaced with automated command reference
  - Changed: orchestrating-swarms skill marked as beta with warning banner

## Phase 5: Validation

### Step 5.1: Run QA Command

- [ ] Run `/compound:plugin-changes-qa` on the updated codebase
- [ ] Verify zero findings from Tier 1 scripts
- [ ] Review Tier 2 agent findings — address any legitimate issues

### Step 5.2: Manual Spot-Check

- [ ] Verify brainstorm.md Phase 3.5 red team dispatch uses three background Tasks (no direct MCP calls)
- [ ] Verify deepen-plan.md Phase 4.5 matches the same pattern
- [ ] Verify the hook script runs correctly: `echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}' | .claude/hooks/plugin-qa-check.sh`

## Work-Readiness Assessment

- **Steps 1.1 and 1.2 are the largest** (~100 lines of prompt text edited per file). The transformation pattern is provided above — subagents should use Edit tool (find-replace), not rewrite entire files.
- **Steps 1.1-1.4 are fully parallel** (different files, no dependencies).
- **Phase 2 has a dependency:** Step 2.1 (scripts) before Steps 2.2+2.3. Steps 2.2 and 2.3 can be parallel after 2.1.
- **Phase 3 is fully parallel** (different files).
- **Phase 4 must be last** (version bump after all changes).
- **Sentinel file:** `/compound:work` should create `.workflows/.work-in-progress` at start and remove at end to suppress the hook during execution.

## Acceptance Criteria

- [ ] No direct MCP calls in orchestrator context (brainstorm.md, deepen-plan.md)
- [ ] resolve-pr-parallel dispatches agents with OUTPUT INSTRUCTIONS
- [ ] orchestrating-swarms has beta warning banner
- [ ] Bead exists for swarms broader review at GA
- [ ] `/compound:plugin-changes-qa` command exists with Tier 1 scripts + Tier 2 agents
- [ ] 4 Tier 1 bash scripts in `scripts/plugin-qa/`, all executable
- [ ] PostToolUse hook fires on commits touching plugin files
- [ ] Hook skips when `.workflows/.work-in-progress` sentinel exists
- [ ] CLAUDE.md has Context-Lean Convention section + agent registry note
- [ ] "context-lean" is the canonical term in CLAUDE.md, README.md, AGENTS.md
- [ ] Version 1.8.0 across plugin.json, marketplace.json, CHANGELOG.md
- [ ] AGENTS.md references `/compound:plugin-changes-qa` for automated QA

## Failure Modes

(From brainstorm — see brainstorm: `docs/brainstorms/2026-03-08-context-lean-enforcement-brainstorm.md`, Failure Modes section)

1. **MCP wrapping adds latency** — All three providers launch in parallel; wall-clock = max(latencies). Acceptable overhead.
2. **Tier 2 false positives** — Reports include confidence + evidence. User makes final call.
3. **Legitimate in-context MCP** — Documented exception for routing/triage decisions.
4. **Hook on irrelevant changes** — Tier 1 scripts are fast (~1-2s). Only Tier 2 (manual command) adds LLM cost.
5. **Hook during /compound:work** — Sentinel file suppresses. If sentinel is missing, Tier 1 scripts run but are non-blocking (exit 2 surfaces findings, doesn't prevent work).

## Scope Boundaries

**In scope:** Everything listed above.

**Out of scope (per brainstorm):**
- Agent definition files (22 files) — centralized note in CLAUDE.md instead
- orchestrating-swarms beyond the warning banner — deferred to GA
- "context-safe" terminology in command file subtitles (e.g., deepen-plan.md "Context-Safe Edition") — lower priority, higher blast radius, separate task
- Smoke testing — separate concern (`docs/plans/2026-02-26-smoke-test-plan.md`)

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-03-08-context-lean-enforcement-brainstorm.md` — 7 key decisions, all resolved red team findings, failure modes
- **Repo research:** `.workflows/plan-research/context-lean-enforcement/agents/repo-research.md`
- **Learnings:** `.workflows/plan-research/context-lean-enforcement/agents/learnings.md`
- **SpecFlow analysis:** `.workflows/plan-research/context-lean-enforcement/agents/specflow.md`
- **Brainstorm research:** `.workflows/brainstorm-research/context-lean-enforcement/` (repo research, context research, 3 red team critiques)
- **Existing QA:** `AGENTS.md` (4 parallel checks, to be automated)
- **Canonical pattern:** `plugins/compound-workflows/skills/disk-persist-agents/SKILL.md`
- **Hook API:** Claude Code hooks documentation (PostToolUse event, command type, exit code semantics)
