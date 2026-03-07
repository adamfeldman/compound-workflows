---
title: "Smoke Test: compound-workflows v1.2.0"
type: task
status: active
date: 2026-02-26
---

# Smoke Test Plan: compound-workflows v1.2.0

## Prerequisites

- A test project directory (NOT the plugin repo itself)
- Claude Code CLI installed
- Optional: beads, PAL MCP, GitHub CLI (for full coverage)

## Setup

```bash
mkdir -p /tmp/test-compound-workflows && cd /tmp/test-compound-workflows
git init
```

Install the plugin from the local marketplace:
```bash
# From within a Claude session:
/install file:///Users/adamf/Dev/compound-workflows-marketplace
```

## Test 1: Plugin Registration

**What:** Verify all components are discovered by Claude Code.

- [ ] All 7 commands appear in `/` autocomplete:
  - `/compound:setup`
  - `/compound:brainstorm`
  - `/compound:plan`
  - `/compound:deepen-plan`
  - `/compound:work`
  - `/compound:review`
  - `/compound:compound`
- [ ] No stale `/compound-workflows:*` commands appear
- [ ] CLAUDE.md is loaded (ask "what agents are available?" — should list 22)

## Test 2: `/compound:setup`

**What:** The entry point. Detects environment and writes config.

- [ ] Detects presence/absence of beads
- [ ] Detects presence/absence of PAL MCP
- [ ] Detects presence/absence of GitHub CLI
- [ ] Detects if compound-engineering is also installed (should warn about conflict)
- [ ] Auto-detects stack (Python/TypeScript/general) based on project files
- [ ] Presents agent configuration appropriate to detected stack
- [ ] Creates `docs/`, `.workflows/` directories if missing
- [ ] Writes `compound-workflows.local.md` with correct schema
- [ ] Summary shows correct `/compound:*` command names (not `/compound-workflows:*`)

## Test 3: `/compound:brainstorm`

**What:** Collaborative dialogue flow with research agents.

- [ ] Accepts a feature description argument
- [ ] Dispatches `repo-research-analyst` agent (should resolve by name, or fall back to inline description)
- [ ] Dispatches `context-researcher` agent (haiku model)
- [ ] Creates `.workflows/brainstorm-research/<topic>/` directory
- [ ] Research agents write output files to disk
- [ ] Asks questions via AskUserQuestion (one at a time)
- [ ] Writes brainstorm doc to `docs/brainstorms/`
- [ ] Phase gates work — open questions must be resolved before proceeding
- [ ] Red team challenge offers PAL (if available) or Claude-only fallback
- [ ] Handoff offers `/compound:plan` (not `/compound-workflows:plan`)

## Test 4: `/compound:plan`

**What:** Transforms feature description into a plan with research agents.

- [ ] Detects recent brainstorm docs and offers to use as input
- [ ] Dispatches research agents: `repo-research-analyst`, `learnings-researcher`
- [ ] Conditional: dispatches `best-practices-researcher`, `framework-docs-researcher`
- [ ] Dispatches `spec-flow-analyzer` for completeness check
- [ ] Research outputs written to `.workflows/plan-research/<stem>/agents/`
- [ ] Writes plan to `docs/plans/YYYY-MM-DD-<type>-<name>-plan.md`
- [ ] Plan has correct YAML frontmatter (including `origin:` if from brainstorm)
- [ ] Handoff offers `/compound:deepen-plan` and `/compound:work`

## Test 5: `/compound:deepen-plan`

**What:** Enhances a plan with parallel research + review agents + red team.

- [ ] Finds the plan file (from recent plans or user-specified)
- [ ] Creates `.workflows/deepen-plan/<stem>/agents/run-<N>/` directory
- [ ] Writes `manifest.json` with agent roster
- [ ] Launches research agents in batches (background)
- [ ] Launches review agents (security-sentinel, architecture-strategist, code-simplicity-reviewer, performance-oracle)
- [ ] All agents write output files to disk (not returned in context)
- [ ] Synthesis agent reads all output files and updates the plan
- [ ] Red team uses 3-provider pattern (Gemini + GPT + Opus via PAL/Task)
- [ ] CRITICAL/SERIOUS findings surfaced via AskUserQuestion
- [ ] MINOR findings also surfaced (not silently skipped)
- [ ] `manifest.json` status progresses: parsing → discovered → agents_planned → synthesized
- [ ] Prior run data preserved if re-running

## Test 6: `/compound:work`

**What:** Execute a plan via subagent dispatch with beads/TodoWrite tracking.

- [ ] Reads the plan file
- [ ] Detects beads vs TodoWrite and adapts
- [ ] Creates issues/tasks for each plan step
- [ ] Dispatches subagents in foreground (sequential by default)
- [ ] Subagent prompt template includes all required fields
- [ ] Each subagent commits its work
- [ ] Orchestrator closes issues and checks off plan items
- [ ] Recovery after compaction works (checks bd/git state)
- [ ] Compound check at end suggests `/compound:compound` if appropriate

## Test 7: `/compound:review`

**What:** Multi-agent code review with disk-persisted findings.

- [ ] Creates `.workflows/review/` output directory
- [ ] Dispatches review agents based on `compound-workflows.local.md` config
- [ ] Agent outputs written to disk files
- [ ] Synthesis combines findings
- [ ] Handles projects without config (falls back to default agent set)

## Test 8: `/compound:compound`

**What:** Document a solved problem as institutional knowledge.

- [ ] Detects recent work context (git log, session activity)
- [ ] Offers analytical vs strategic mode
- [ ] Writes solution doc to `docs/solutions/`
- [ ] Uses `compound-docs` skill schema
- [ ] Dispatches `data-integrity-guardian`, `security-sentinel`, `performance-oracle` for review

## Test 9: Agent Resolution

**What:** Verify all 22 agents resolve by YAML `name:` field.

Test a sample across categories:

- [ ] `Task repo-research-analyst` — research agent resolves
- [ ] `Task context-researcher` — haiku model agent resolves
- [ ] `Task security-sentinel` — review agent resolves
- [ ] `Task typescript-reviewer` — renamed agent resolves (not kieran-*)
- [ ] `Task frontend-races-reviewer` — renamed agent resolves (not julik-*)
- [ ] `Task spec-flow-analyzer` — workflow agent resolves
- [ ] `Task bug-reproduction-validator` — standalone agent resolves
- [ ] Graceful fallback when agent not found (inline role description used instead)

## Test 10: Skill Loading

**What:** Verify skills load when referenced.

- [ ] `brainstorming` skill loads during `/compound:brainstorm`
- [ ] `document-review` skill loads when invoked
- [ ] `setup` skill has `disable-model-invocation: true` (not auto-loaded)
- [ ] `orchestrating-swarms` skill loads for multi-agent coordination
- [ ] `disk-persist-agents` skill loads when referenced
- [ ] `compound-docs` skill loads during `/compound:compound`

## Test 11: Graceful Degradation

**What:** Plugin works without optional dependencies.

- [ ] Without beads: `/compound:work` falls back to TodoWrite
- [ ] Without PAL MCP: `/compound:brainstorm` red team uses Claude-only fallback
- [ ] Without PAL MCP: `/compound:deepen-plan` red team uses single-model approach
- [ ] Without GitHub CLI: `/compound:setup` notes it's missing but doesn't fail
- [ ] Without compound-engineering: no warnings, no broken references

## Test 12: No Stale References

**What:** Verify the fork is clean.

```bash
cd <plugin-install-path>

# No old namespace
grep -r 'compound-workflows:' . | grep -v 'compound-workflows.local'
# Expected: 0 results

# No compound-engineering dependency
grep -r 'compound-engineering' . | grep -v NOTICE | grep -v FORK-MANIFEST | grep -v CHANGELOG | grep -v README
# Expected: 0 results (only attribution files)

# No personal names in agent prompts
grep -ri 'kieran\|julik' agents/
# Expected: 0 results

# No company-specific examples
grep -ri 'BriefSystem\|EmailProcessing\|Xiatech\|EveryInc\|Every Reader' agents/ skills/
# Expected: 0 results
```

## Priority Order

If time is limited, test in this order:
1. Test 1 (registration) — gates everything else
2. Test 2 (setup) — entry point for new users
3. Test 12 (stale refs) — automated, catches regressions
4. Test 9 (agent resolution) — core value prop
5. Test 3 (brainstorm) — most complex command
6. Tests 4-8 (remaining commands) — as time permits
