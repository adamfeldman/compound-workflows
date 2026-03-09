---
name: compound:setup
description: Set up compound-workflows for your project
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

## Step 1.5: Plugin Version Check

```bash
bash plugins/compound-workflows/scripts/version-check.sh
```

Interpret the output:

- **If script not found:** Skip silently — the script may not exist in older plugin versions.
- **If output contains STALE:** Warn the user:

> **Your compound-workflows plugin is out of date.** The installed version is behind the source. Run:
> ```
> claude plugin update compound-workflows@compound-workflows-marketplace
> ```
> Then restart your session to pick up the new version.

Use **AskUserQuestion**: "Plugin is stale. Update now, or continue setup with the current version?"
- **Update now** — run the update command, then advise restarting the session
- **Continue** — proceed with setup using the current version

- **If output contains UNRELEASED:** Note it but do not block setup:

> **Note:** The current source version has no GitHub release yet. This won't affect your project setup — releases are tracked separately via `/compound:compact-prep`.

- **If all versions match:** Move on silently.

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

Present this overview using a code block for clean terminal formatting:

```
Your project structure:

  docs/
    brainstorms/   Output from /compound:brainstorm
    plans/         Output from /compound:plan
    solutions/     Output from /compound:compound (institutional knowledge)
    decisions/     Decision records (choices between alternatives)

  resources/       External reference material you bring in (API docs,
                   specs, research papers). Organize by topic or flat.
                   The context-researcher searches this recursively.

  memory/          Stable project facts that persist across sessions.

  .workflows/      Agent outputs persisted to disk. Agents write here
                   instead of into your conversation, so context stays
                   lean. Recommend committing for traceability.

Workflow cycle:

  brainstorm → plan → [deepen-plan] → work → review → compound

  Each step produces docs that feed the next. Start with
  /compound:brainstorm to explore, or /compound:plan if you
  know what to build. Solutions feed future brainstorms.

Commands: type /compound: to see all. The short form works:
  /compound:brainstorm = /compound-workflows:compound:brainstorm

Customization: after setup, edit the "Workflow Instructions"
  section in compound-workflows.md to add red team focus areas,
  domain constraints, or review emphasis specific to this project.
```

Then ask:

Use **AskUserQuestion**: "Any questions about the structure, or ready to continue?"
- **Continue** — proceed to Step 7
- **Questions** — answer, then proceed

### .gitignore Check

Check `.gitignore` for issues:

```bash
# Check what's gitignored that shouldn't be
GITIGNORE_ISSUES=""
for d in .workflows resources memory; do
  if grep -q "^$d" .gitignore 2>/dev/null || grep -q "^/$d" .gitignore 2>/dev/null; then
    GITIGNORE_ISSUES="$GITIGNORE_ISSUES $d"
  fi
done

# Check what's NOT gitignored that should be
if ! grep -q 'compound-workflows.local.md' .gitignore 2>/dev/null; then
  echo "MISSING_GITIGNORE=compound-workflows.local.md"
fi

echo "GITIGNORE_ISSUES=$GITIGNORE_ISSUES"
```

**If any directories are gitignored**, explain and offer to fix:

Use **AskUserQuestion**: "These directories are in .gitignore but should be committed for traceability: [list]. Remove them from .gitignore?"
- **Yes** — remove the matching lines from `.gitignore`
- **Keep gitignored** — leave as-is (agent outputs won't be tracked)

**If `compound-workflows.local.md` is not in `.gitignore`**, add it silently — it contains machine-specific config that shouldn't be committed:

```bash
echo 'compound-workflows.local.md' >> .gitignore
```

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

## Plan Readiness

# Which checks to skip (comma-separated, or "none" to run all 8)
# Mechanical: stale-values, broken-references, audit-trail-bloat
# Semantic: contradictions, unresolved-disputes, underspecification, accretion, external-verification
plan_readiness_skip_checks: (none)

# How many days before a brainstorm/plan link is considered stale
plan_readiness_provenance_expiry_days: 30

# Source policy for verification: conservative (require doc links),
# moderate (allow commit refs), permissive (trust inline assertions)
plan_readiness_verification_source_policy: conservative

## Workflow Instructions
[Optional. Add instructions that apply to compound-workflows commands specifically.
Examples:
- Red team focus: "Always check for HIPAA compliance and multi-tenant data leakage"
- Domain context: "This is a financial app — brainstorms should consider regulatory constraints"
- Review emphasis: "Performance is critical — flag any N+1 queries or unbounded loops"
General project instructions belong in CLAUDE.md or AGENTS.md, not here.]
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
  Task tracking:  [beads (compaction-safe) | TodoWrite (in-memory)] <!-- context-lean-exempt: display label -->
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

Tip: Edit the Workflow Instructions section in compound-workflows.md
     to add red team focus areas, domain constraints, or review emphasis.
     Run /compound:setup anytime to reconfigure.
     Red team provider is chosen per-session based on available tools.
```
