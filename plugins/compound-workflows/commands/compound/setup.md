---
name: compound:setup
description: "Set up compound-workflows plugin for your project"
---

# Compound Workflows Setup

Set up compound-workflows for your project. Detects your environment, identifies your stack, configures review agents, and writes a local config file.

## Step 1: Detect Environment

Run all detection checks:

```bash
# Check for beads
which bd 2>/dev/null && echo "BEADS=available" || echo "BEADS=not_available"

# Check for GitHub CLI
which gh 2>/dev/null && echo "GH=available" || echo "GH=not_available"

# Check for PAL MCP
if [ -f ~/.claude/settings.json ] && grep -q "pal" ~/.claude/settings.json 2>/dev/null; then
  echo "PAL=available"
else
  echo "PAL=not_available"
fi
```

Record results for later use.

## Step 2: Compound-Engineering Conflict Detection

```bash
ls ~/.claude/plugins/cache/*/compound-engineering 2>/dev/null
```

**If compound-engineering is found:** Warn the user:

> **Warning: compound-engineering detected.** compound-workflows supersedes it and bundles its own agents and skills. Having both installed may cause duplicate agent dispatches during reviews and plan deepening. **Recommendation:** Uninstall compound-engineering to avoid duplicate agents.

Use **AskUserQuestion** to confirm whether the user wants to continue setup or uninstall first.

## Step 3: Auto-Detect Stack

Detect the project's primary technology stack:

```bash
# Python detection
PYTHON=false
if [ -f requirements.txt ] || [ -f pyproject.toml ] || [ -f setup.py ]; then
  PYTHON=true
fi
if [ -d src ] && ls src/*.py 2>/dev/null | head -1 > /dev/null; then
  PYTHON=true
fi

# TypeScript detection
TYPESCRIPT=false
if [ -f tsconfig.json ]; then
  TYPESCRIPT=true
fi
if [ -f package.json ] && grep -q '"typescript"' package.json 2>/dev/null; then
  TYPESCRIPT=true
fi

echo "PYTHON=$PYTHON"
echo "TYPESCRIPT=$TYPESCRIPT"
```

**Stack assignment:**

- If Python indicators found: `stack: python`
- If TypeScript indicators found: `stack: typescript`
- If both found: use **AskUserQuestion** to let user choose primary stack
- If neither found: `stack: general`

## Step 4: Configure Review Agents

Based on detected stack, set default review agent roster:

**Python stack:**
- `python-reviewer` — Python code reviewer focused on idioms, type hints, and best practices
- `security-sentinel` — Security auditor for vulnerabilities and OWASP compliance
- `code-simplicity-reviewer` — Checks for unnecessary complexity and over-engineering
- `performance-oracle` — Performance analysis for bottlenecks and algorithmic issues

**TypeScript stack:**
- `typescript-reviewer` — TypeScript code reviewer focused on type safety and modern patterns
- `security-sentinel` — Security auditor for vulnerabilities and OWASP compliance
- `code-simplicity-reviewer` — Checks for unnecessary complexity and over-engineering
- `performance-oracle` — Performance analysis for bottlenecks and algorithmic issues

**General stack:**
- `security-sentinel` — Security auditor for vulnerabilities and OWASP compliance
- `code-simplicity-reviewer` — Checks for unnecessary complexity and over-engineering
- `architecture-strategist` — Reviews architectural impact and design integrity
- `performance-oracle` — Performance analysis for bottlenecks and algorithmic issues

## Step 5: User Customization

Use **AskUserQuestion** to let the user configure depth and agents:

```
question: "Review configuration ready. Choose review depth and customize agents."
header: "Review Configuration"
```

**Depth options:**
- **standard** — Default agent set runs on every review (recommended)
- **comprehensive** — All available review and research agents run (thorough but slower)
- **minimal** — Only security-sentinel and one stack reviewer (fast, lightweight)

**Agent customization:**

Present the default agent list for the detected stack and ask:

```
question: "Default review agents for [stack]: [agent list]. Add or remove any?"
header: "Agent Selection"
options:
  - label: "Use defaults"
    description: "Proceed with the recommended agent set"
  - label: "Customize"
    description: "Add or remove specific agents from the roster"
```

If "Customize": list all available agents from `plugins/compound-workflows/agents/review/` and `plugins/compound-workflows/agents/research/` and let the user toggle.

## Step 6: Create Directories

```bash
mkdir -p docs/brainstorms/ docs/plans/ docs/solutions/ .workflows/
```

Report which directories were created vs. already existed.

### .workflows/ and .gitignore

Recommend **committing `.workflows/`** to the repo. It contains disk-persisted agent outputs (research, reviews, red team critiques) that provide full traceability for how decisions were made. Without it, the reasoning behind plans and brainstorms is lost.

If `.workflows/` is in `.gitignore`, inform the user:

> **Note:** `.workflows/` is currently gitignored. We recommend tracking it — agent research outputs provide traceability for how plans and decisions were reached. Remove `.workflows/` from `.gitignore` to preserve this history.

## Step 7: Write Local Config

Write `compound-workflows.local.md` to the project root using the unified schema:

```markdown
---
# Auto-generated by /compound:setup
# Re-run setup to update
---

# Compound Workflows Configuration

## Environment
tracker: [beads|todowrite]
red_team: [gemini-2.5-pro|none]
gh_cli: [available|not available]

## Stack & Agents
stack: [python|typescript|general]
review_agents: [comma-separated list of configured review agents]
plan_review_agents: [comma-separated list of research agents for plan deepening]
depth: [standard|comprehensive|minimal]

## Project Context
[Add project-specific instructions here. These notes are available to all workflow commands.]
```

Fill in the actual detected values. Set `tracker` based on beads availability, `red_team` based on PAL availability, and `gh_cli` based on GitHub CLI detection.

For `plan_review_agents`, use the research agents available in the plugin: `repo-research-analyst`, `best-practices-researcher`, `framework-docs-researcher`.

### Step 7b: Migration Check

Before writing, check if `compound-workflows.local.md` already exists:

```bash
cat compound-workflows.local.md 2>/dev/null
```

If the file exists and contains the old schema format (look for `review_agents: compound-engineering` or `review_agents: general-purpose`), inform the user:

> **Migration notice:** Found existing `compound-workflows.local.md` with old schema format (`review_agents: compound-engineering|general-purpose`). This will be replaced with the new unified schema that uses explicit agent names and stack detection.

Overwrite with the new schema.

## Step 8: Summary

Display the setup summary:

```
## Setup Complete

Environment:
  Task tracking:  [beads (compaction-safe) | TodoWrite (in-memory)]
  Red team:       [PAL MCP with gemini-2.5-pro | Claude subagent fallback]
  GitHub CLI:     [available | not available]

Stack & Review:
  Detected stack: [python | typescript | general]
  Review agents:  [agent list]
  Review depth:   [standard | comprehensive | minimal]

Directories:     [all present | N created]
Config:          compound-workflows.local.md

Ready to go:
  /compound:brainstorm  — explore an idea
  /compound:plan        — create an implementation plan
  /compound:work        — execute a plan
  /compound:review      — review code changes

Tip: Edit compound-workflows.local.md to add project-specific context.
     Run /compound:setup anytime to reconfigure.
```
