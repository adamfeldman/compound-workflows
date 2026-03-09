---
name: compound:plugin-changes-qa
description: Run structural and semantic QA checks on the compound-workflows plugin
user-invocable: true
---

# Plugin Changes QA

Run hybrid QA checks on the compound-workflows plugin: deterministic Tier 1 bash scripts for structural validation, followed by Tier 2 LLM agents for semantic analysis.

**Findings are informational only.** This command does not modify the codebase.

## Phase 1: Tier 1 (Deterministic Scripts)

Discover and run all bash scripts in the plugin-qa directory. These are fast, deterministic checks that validate structural properties.

### Step 1.1: Resolve Plugin Root

```bash
# Find the plugin root — look for plugins/compound-workflows relative to repo root
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PLUGIN_ROOT="$REPO_ROOT/plugins/compound-workflows"
echo "Plugin root: $PLUGIN_ROOT"
ls "$PLUGIN_ROOT/CLAUDE.md" 2>/dev/null && echo "VALID" || echo "NOT FOUND"
```

If the plugin root is not found, report the error and stop.

### Step 1.2: Discover and Run Scripts

```bash
ls plugins/compound-workflows/scripts/plugin-qa/*.sh
```

Run each `.sh` script via the Bash tool, passing the plugin root path as the first argument:

```bash
bash plugins/compound-workflows/scripts/plugin-qa/<script>.sh "$PLUGIN_ROOT"
```

**Error handling:**
- If a script exits 1 (script error): note the error, continue with remaining scripts
- If a script exits 0 with findings: collect the output (scripts always exit 0 for findings)
- Run all scripts regardless of individual failures

Collect all script outputs for Phase 3 aggregation.

## Phase 2: Tier 2 (Semantic Agents)

Dispatch three LLM agents in parallel for semantic analysis that bash scripts cannot perform. All agents use the disk-persist pattern.

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

Read ALL command files in: plugins/compound-workflows/commands/compound/

For each command file, verify:
1. **No large agent returns in orchestrator context** — every Task dispatch must include OUTPUT INSTRUCTIONS that direct the agent to write to disk and return only a 2-3 sentence summary
2. **MCP calls wrapped in subagents** — any mcp__pal__clink or mcp__pal__chat call must be inside a Task block, never called directly by the orchestrator
3. **OUTPUT INSTRUCTIONS present** — every Task dispatch (except trivial inline tasks) must have an === OUTPUT INSTRUCTIONS (MANDATORY) === block
4. **TaskOutput is banned** — no command should instruct the orchestrator to call TaskOutput; file-existence polling is the correct pattern
5. **Disk-persist pattern used** — agents write to .workflows/ directories, orchestrator reads from disk

For each violation found, report:
- File path
- Line number or section
- What the violation is
- Severity: CRITICAL (data flows through orchestrator), SERIOUS (missing instructions), MINOR (style/consistency)

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

Read the agent registry in: plugins/compound-workflows/CLAUDE.md
Read all agent definition files in: plugins/compound-workflows/agents/

Then read all command files in: plugins/compound-workflows/commands/compound/
And all skill files matching: plugins/compound-workflows/skills/*/SKILL.md

For each Task dispatch in commands and skills, verify:
1. **Agent name matches** — the Task dispatch references a valid agent from the registry
2. **Role description is accurate** — the inline role description in the Task dispatch matches the agent definition file's description
3. **Allowed-tools consistency** — if the agent definition specifies allowed tools, the Task dispatch does not ask the agent to use tools outside that set
4. **Model specification** — if the agent definition specifies a model override (e.g., haiku), verify it is respected in the dispatch
5. **Agent existence** — flag any Task dispatches referencing agents that do not have definition files

For each mismatch found, report:
- Command/skill file and the agent being dispatched
- What the mismatch is (expected vs actual)
- Severity: SERIOUS (wrong agent or missing definition), MINOR (description drift)

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

Read ALL command files in: plugins/compound-workflows/commands/compound/
Read the Command Conventions section in: plugins/compound-workflows/CLAUDE.md

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

### Step 3.2: Present Aggregated Summary

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

**No codebase mutation.** Findings are informational only. The user decides what to act on.

## Rules

- **NEVER modify the codebase.** This command only reports findings.
- **NEVER call TaskOutput.** Poll for file existence instead.
- **NEVER push to remote.** This is a local analysis command.
- **NEVER modify beads issues.** QA findings are presented to the user, not tracked automatically.
- Agent outputs go to `.workflows/plugin-qa/agents/`. Second runs overwrite prior results (always want latest).
- If a Tier 1 script fails with exit 1, report the error and continue with remaining scripts.
- If a Tier 2 agent times out, note it in the summary and present available results.
