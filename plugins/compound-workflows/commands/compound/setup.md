---
name: compound:setup
description: "Set up compound-workflows plugin for your project"
---

# Compound Workflows Setup

Set up compound-workflows for your project. Detects your environment, identifies your stack, configures review agents, and writes a local config file.

## Step 0: Prerequisites

```bash
# Must be a git repo — worktrees, diffs, and commits depend on it
git rev-parse --is-inside-work-tree 2>/dev/null && echo "GIT=true" || echo "GIT=false"
```

**If not a git repo:** Stop setup with a clear message:

> **This directory is not a git repository.** compound-workflows requires git (worktrees, diffs, commit tracking). Run `git init` first, then re-run `/compound:setup`.

## Step 1: Detect Environment

Run all detection checks:

```bash
# Check for beads
which bd 2>/dev/null && echo "BEADS=available" || echo "BEADS=not_available"

# Check if beads is initialized in this project
[ -d .beads ] && echo "BEADS_INIT=true" || echo "BEADS_INIT=false"

# Check for GitHub CLI
which gh 2>/dev/null && echo "GH=available" || echo "GH=not_available"

# Check for PAL MCP
if [ -f ~/.claude/settings.json ] && grep -q "pal" ~/.claude/settings.json 2>/dev/null; then
  echo "PAL=available"
else
  echo "PAL=not_available"
fi

# Check for Gemini CLI
which gemini 2>/dev/null && echo "GEMINI_CLI=available" || echo "GEMINI_CLI=not_available"

# Check for Codex CLI (OpenAI)
which codex 2>/dev/null && echo "CODEX_CLI=available" || echo "CODEX_CLI=not_available"
```

Record results for later use.

### Beads Initialization

If beads is installed but not initialized (`BEADS=available` and `BEADS_INIT=false`):

Use **AskUserQuestion**: "Beads is installed but not initialized in this project. Initialize now? (`bd init` sets up local task tracking.)"
- **Yes** — run `bd init` and record `BEADS_INIT=true`
- **Skip** — proceed with TodoWrite fallback

### CLI Activation (Gemini / Codex)

If Gemini CLI or Codex CLI are detected, they can be used for red team reviews via `clink` — giving each model direct file access in the repo (richer analysis than API-only calls).

**First-run setup:** These CLIs sandbox file access per project. If this is the first time using them in this repo, they need a one-time permission grant:

> **Gemini CLI and/or Codex CLI detected.** To use them for red team reviews, each CLI needs one-time permission to read files in this project. Open a terminal in your project root and run:
> ```bash
> gemini    # accept file access when prompted, then exit
> codex     # accept file access when prompted, then exit
> ```
> Already done this? Skip ahead.

Use **AskUserQuestion**: "Have you activated Gemini/Codex CLI in this repo (or want to skip CLI-based red team)?"
- **Already activated** — record as available
- **Will do it now** — pause setup, let user activate, then continue
- **Skip** — use PAL API calls instead (or Claude-only fallback)

## Step 2: Compound-Engineering Conflict Detection

```bash
ls ~/.claude/plugins/cache/*/compound-engineering 2>/dev/null
```

**If compound-engineering is found:** Warn the user:

> **Warning: compound-engineering detected.** compound-workflows supersedes it and bundles its own agents and skills. Having both installed may cause duplicate agent dispatches during reviews and plan deepening.

Use **AskUserQuestion**: "compound-engineering is installed alongside compound-workflows. Uninstall it to avoid duplicate agents?"
- **Yes** — run `/plugin uninstall compound-engineering`, then continue setup
- **Continue anyway** — proceed with both installed (not recommended)

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

Check and create all required directories. Report status for each one:

```bash
for d in docs/brainstorms docs/plans docs/solutions docs/decisions resources memory .workflows; do
  if [ -d "$d" ]; then
    echo "$d: exists"
  else
    mkdir -p "$d"
    echo "$d: created"
  fi
done
```

### Project Structure Walkthrough

After creating directories, explain the folder structure to the user:

Use **AskUserQuestion**:

```
question: "Here's how compound-workflows organizes your project:"
header: "Project Structure"
```

Present this overview:

> **`docs/`** — Everything your team produces through the workflow:
> - `brainstorms/` — Output from `/compound:brainstorm`. Exploratory thinking, evaluated alternatives, design decisions.
> - `plans/` — Output from `/compound:plan`. Implementation plans with research-backed steps.
> - `solutions/` — Output from `/compound:compound`. Verified fixes and proven patterns — your team's institutional knowledge.
> - `decisions/` — Decision records. When a brainstorm's main output is a choice between alternatives rather than a design to implement.
>
> **`resources/`** — External reference material you bring into the project. API docs, specs, research papers, architecture references — anything that gives Claude context. Organize however you like: folders by topic, or files at the root. The context-researcher searches this recursively.
>
> **`memory/`** — Stable project facts that persist across sessions. Project context, glossary, key decisions. Updated over time as the project evolves.
>
> **`.workflows/`** — Disk-persisted agent outputs (research, reviews, red team critiques). Agents write here instead of returning results into your conversation, so context stays lean and you can run 15+ agents without exhaustion. These files persist across sessions and compactions — commit them for full traceability of how decisions were made.
>
> **Workflow:** `brainstorm → plan → [deepen-plan] → work → review → compound`
>
> Each step produces documents that feed the next. Start with `/compound:brainstorm` to explore an idea, or `/compound:plan` if you already know what to build. Solutions from `/compound:compound` feed future brainstorms.
>
> **Commands:** Type `/compound:` to see all available commands. The short form (e.g. `/compound:brainstorm`) works the same as the full form (`/compound-workflows:compound:brainstorm`).

Then ask:

Use **AskUserQuestion**: "Any questions about the structure, or ready to continue?"
- **Continue** — proceed to Step 7
- **Questions** — answer, then proceed

### .workflows/ and .gitignore

If `.workflows/` is in `.gitignore`, inform the user:

> **Note:** `.workflows/` is currently gitignored. We recommend committing it — agent research outputs provide traceability for how plans and decisions were reached. Remove `.workflows/` from `.gitignore` to preserve this history.

## Step 7: Write Config Files

Write two config files — one shared (committed), one personal (gitignored).

### 7a: Project Config — `compound-workflows.md`

Shared project settings. **Should be committed** so team members share the same agent configuration.

```markdown
---
# Auto-generated by /compound:setup
# Re-run setup to update
---

# Compound Workflows Configuration

## Stack & Agents
stack: [python|typescript|general]
review_agents: [comma-separated list of configured review agents]
plan_review_agents: [comma-separated list of research agents for plan deepening]
depth: [standard|comprehensive|minimal]

## Project Context
[Add project-specific instructions here. These notes are available to all workflow commands.]
```

For `plan_review_agents`, use the research agents available in the plugin: `repo-research-analyst`, `best-practices-researcher`, `framework-docs-researcher`.

### 7b: Local Config — `compound-workflows.local.md`

Machine-specific environment settings. **Should be gitignored** — each developer's environment differs.

```markdown
---
# Auto-generated by /compound:setup — machine-specific, gitignored
# Re-run setup to update
---

# Compound Workflows Local Config

tracker: [beads|todowrite]
gh_cli: [available|not available]
```

Fill in based on detected environment. Red team provider preferences are NOT stored — they're detected at runtime each session (CLI availability varies by machine and may change).

If `compound-workflows.local.md` is not in `.gitignore`, add it:

```bash
if ! grep -q 'compound-workflows.local.md' .gitignore 2>/dev/null; then
  echo 'compound-workflows.local.md' >> .gitignore
fi
```

### 7c: Migration Check

Before writing, check if either config file already exists:

```bash
cat compound-workflows.md 2>/dev/null
cat compound-workflows.local.md 2>/dev/null
```

If an old-format `compound-workflows.local.md` exists (look for `review_agents:` in the local file, or `review_agents: compound-engineering`), inform the user:

> **Migration notice:** Found existing config with old schema. Project settings (stack, agents, depth) will move to `compound-workflows.md` (committed). Environment settings will stay in `compound-workflows.local.md` (gitignored).

Write both files with the new schema.

## Step 8: Summary

Display the setup summary:

```
## Setup Complete

Environment:
  Task tracking:  [beads (compaction-safe) | TodoWrite (in-memory)]
  Red team:       [Gemini CLI + Codex CLI | PAL MCP | Claude subagent fallback]
  GitHub CLI:     [available | not available]

Stack & Review:
  Detected stack: [python | typescript | general]
  Review agents:  [agent list]
  Review depth:   [standard | comprehensive | minimal]

Directories:     [all present | N created]
Config:          compound-workflows.md (project, committed)
                 compound-workflows.local.md (environment, gitignored)

Ready to go:
  /compound:brainstorm  — explore an idea
  /compound:plan        — create an implementation plan
  /compound:work        — execute a plan
  /compound:review      — review code changes

Tip: Edit compound-workflows.md to add project-specific context.
     Run /compound:setup anytime to reconfigure.
     Red team provider is chosen per-session based on available tools.
```
