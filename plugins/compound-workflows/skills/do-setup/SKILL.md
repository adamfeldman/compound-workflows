---
name: do:setup
description: Set up compound-workflows for your project
disable-model-invocation: true
---

# Compound Workflows Setup

Set up compound-workflows for your project. Detects your environment, identifies your stack, configures review agents, and writes a local config file.

## Step 0: Prerequisites

```bash
# Must be a git repo — worktrees, diffs, and commits depend on it
git rev-parse --is-inside-work-tree 2>/dev/null && echo "GIT=true" || echo "GIT=false"
```

**If not a git repo:** Stop setup with a clear message:

> **This directory is not a git repository.** compound-workflows requires git (worktrees, diffs, commit tracking). Run `git init` first, then re-run `/do:setup`.

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

# Check for ccusage (token/cost tracking)
which ccusage 2>/dev/null && echo "CCUSAGE=available" || echo "CCUSAGE=not_available"
```

Record results for later use.

### Beads Initialization

If beads is installed but not initialized (`BEADS=available` and `BEADS_INIT=false`):

Use **AskUserQuestion**: "Beads is installed but not initialized in this project. Initialize now? (`bd init` sets up local task tracking.)"
- **Yes** — run `bd init` and record `BEADS_INIT=true`
- **Skip** — proceed with TodoWrite fallback

### CLI Activation (Gemini / Codex)

If Gemini CLI or Codex CLI are detected, they can be used for red team reviews via `clink` — giving each model direct file access in the repo. CLIs can independently read files referenced in prompts (verified: Gemini uses `read_file`, Codex uses `cat`). Without CLIs, red team falls back to PAL chat where file contents must be explicitly passed via `absolute_file_paths`.

**First-run setup:** These CLIs sandbox file access per project. If this is the first time using them in this repo, they need a one-time permission grant:

> **Gemini CLI and/or Codex CLI detected.** CLIs give red team reviewers direct access to your repo files — they can read plans, brainstorms, and source code independently. Each CLI needs one-time permission. Open a terminal in your project root and run:
> ```bash
> gemini    # accept file access when prompted, then exit
> codex     # accept file access when prompted, then exit
> ```
> Already done this? Skip ahead.

Use **AskUserQuestion**: "Have you activated Gemini/Codex CLI in this repo (or want to skip CLI-based red team)?"
- **Already activated** — record as available
- **Will do it now** — pause setup, let user activate, then continue
- **Skip** — use PAL chat instead (file contents must be passed explicitly, models cannot browse repo)

## Step 1.5: Plugin Version Check

```bash
bash ${CLAUDE_SKILL_DIR}/../../scripts/init-values.sh setup
```

Read the output. Track the values PLUGIN_ROOT and VERSION_CHECK for use in subsequent steps. If init-values.sh fails or any value is empty, warn the user and stop.

Then run the version check using the VERSION_CHECK value:

```bash
bash <VERSION_CHECK>
```

If VERSION_CHECK is empty or the script is not found, say "version-check.sh not found".

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

> **Note:** The current source version has no GitHub release yet. This won't affect your project setup — releases are tracked separately via `/do:compact-prep`.

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

If "Customize": list all available review and research agents. Use the PLUGIN_ROOT value from init-values.sh output:
```bash
ls "<PLUGIN_ROOT>/agents/review/" "<PLUGIN_ROOT>/agents/research/" 2>/dev/null
```
Let the user toggle agents on/off from the list.

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
    brainstorms/   Output from /do:brainstorm
    plans/         Output from /do:plan
    solutions/     Output from /do:compound (institutional knowledge)
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
  /do:brainstorm to explore, or /do:plan if you
  know what to build. Solutions feed future brainstorms.

Commands: type /do: to see all. The short form works:
  /do:brainstorm = /compound-workflows:do:brainstorm

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

Read `.gitignore` (if it exists). If `compound-workflows.local.md` is not already listed, use the **Edit tool** to append `compound-workflows.local.md` as a new line.

## Step 7: Configure Permissions

Set up a PreToolUse hook that auto-approves safe commands and configure permission profiles.

### 7a: Resolve Plugin Root

Use the PLUGIN_ROOT value from init-values.sh output (already tracked from Step 1.5):

```bash
HOOK_TEMPLATE="<PLUGIN_ROOT>/templates/auto-approve.sh"
echo "HOOK_TEMPLATE=$HOOK_TEMPLATE"
[[ -f "$HOOK_TEMPLATE" ]] && echo "TEMPLATE=found" || echo "TEMPLATE=missing"
```

**If template is missing:** Warn and skip the permission step:

> **Hook template not found.** The auto-approve.sh template is not available in this plugin version. Permission configuration skipped — you'll see standard permission prompts.

Proceed to Step 8 (Write Config Files).

### 7b: Install Hook Script

Create the hooks directory and install the auto-approve script:

```bash
mkdir -p .claude/hooks
```

**Version comparison (idempotent):**

Check if the installed hook exists, then read versions as split-calls:

```bash
[ -f .claude/hooks/auto-approve.sh ] && echo "HOOK_EXISTS=true" || echo "HOOK_EXISTS=false"
```

If the hook exists, run `sed -n '2s/^# auto-approve v//p' .claude/hooks/auto-approve.sh` and read the output as INSTALLED_VERSION.

Run `sed -n '2s/^# auto-approve v//p' <HOOK_TEMPLATE>` (using the HOOK_TEMPLATE path from above) and read the output as TEMPLATE_VERSION.

- **If no installed hook:** Copy the template and set executable:
  ```bash
  cp "$HOOK_TEMPLATE" .claude/hooks/auto-approve.sh
  chmod +x .claude/hooks/auto-approve.sh
  ```
  Record: `HOOK_STATUS=installed`

- **If installed version is older than template version:** Replace and report:
  ```bash
  cp "$HOOK_TEMPLATE" .claude/hooks/auto-approve.sh
  chmod +x .claude/hooks/auto-approve.sh
  ```
  Record: `HOOK_STATUS=updated` (from v$INSTALLED_VERSION to v$TEMPLATE_VERSION)

- **If versions match:** Skip (idempotent). Record: `HOOK_STATUS=current`

### 7c: Register Hook in settings.json

Read the existing `.claude/settings.json`:

```bash
cat .claude/settings.json 2>/dev/null || echo '{}'
```

Merge the following into the existing settings, preserving all existing hooks (especially PostToolUse):

1. Add `permissions.allow` entries if not already present:
   - `Write(//.workflows/**)`
   - `Edit(//.workflows/**)`

2. Add `PreToolUse` hook entry if not already registered:
   ```json
   {
     "matcher": "",
     "hooks": [
       {
         "type": "command",
         "command": "bash .claude/hooks/auto-approve.sh"
       }
     ]
   }
   ```

**Merge rules:**
- If `PreToolUse` array already contains an entry with `command` matching `auto-approve.sh`, skip (already registered)
- If `PostToolUse` hooks exist, preserve them exactly as-is
- If `permissions.allow` already contains the entries, skip duplicates
- Use `jq` for safe JSON manipulation. If `jq` is not available, write the JSON manually using the read values as a base

Write the merged result back to `.claude/settings.json`. Validate it is well-formed JSON.

Record: `SETTINGS_STATUS=updated` or `SETTINGS_STATUS=unchanged`

### 7d: Choose Permission Profile

Use **AskUserQuestion**:

```
Permission configuration:

1. Standard (recommended)
   Committed baseline + hook only. No additional static rules.
   The hook auto-approves safe commands (ls, git, grep, find, etc.)
   and path-scopes destructive operations. You'll still get prompted
   for uncommon operations and bash safety heuristic triggers.

2. Permissive (high impact)
   Adds interpreter access — reduces prompts to near-zero but:
   ⚠ bash:*    — allows arbitrary script execution (BYPASSES hook guardrails)
   ⚠ python3:* — allows arbitrary code execution (BYPASSES hook guardrails)
   ⚠ git:*     — allows all git operations including destructive (BYPASSES hook is_dangerous_git)
   ⚠ cat:*     — bypasses Read tool path restrictions
   Plus: gh, grep, find, claude, ccusage, head, tail, sed, cp, timeout, open,
         ls, mkdir, md5, bd, if, for, [[, xargs, tee, WebFetch
   Plus: mcp__pal__clink, mcp__pal__chat, mcp__pal__listmodels, WebSearch  <!-- context-lean-exempt: permission rule list -->

   WARNING: Static allow rules are evaluated BEFORE the hook. When a static
   rule matches, the hook never fires — its pipe/compound/redirect/path-scoping
   checks are bypassed entirely. Choose this ONLY if you trust your LLM and
   want minimal friction.

Which profile? (1/2)
```

Record the user's choice as `PROFILE=standard` or `PROFILE=permissive`.

### 7e: Apply Profile Rules to settings.local.json

Read the existing `.claude/settings.local.json`:

```bash
cat .claude/settings.local.json 2>/dev/null || echo '{}'
```

**Standard profile:** No additional static rules. The hook handles everything. Skip to reporting.

**Permissive profile rules to merge:**

```
Bash(gh:*)
Bash(grep:*)
Bash(find:*)
Bash(claude:*)
Bash(ccusage:*)
Bash(bash:*)
Bash(python3:*)
Bash(cat:*)
Bash(head:*)
Bash(tail:*)
Bash(sed:*)
Bash(cp:*)
Bash(timeout:*)
Bash(open:*)
Bash(git:*)
Bash(mkdir:*)
Bash(md5:*)
Bash(ls:*)
Bash(bd:*)
Bash(if:*)
Bash(for:*)
Bash([[:*)
Bash(xargs:*)
Bash(tee:*)
mcp__pal__clink  # context-lean-exempt: permission rule list
mcp__pal__chat  # context-lean-exempt: permission rule list
mcp__pal__listmodels
WebSearch
WebFetch(domain:*)
```

**Merge logic:**
- Read existing `permissions.allow` array from `settings.local.json`
- For each rule in the profile: add if not already present, skip if duplicate
- **Never remove** user-added rules that are not in the profile list
- Write back with `jq` (or manually if `jq` unavailable)

Count: `RULES_ADDED=N`, `RULES_ALREADY_PRESENT=M`

### 7f: First-Run Migration Check

Check for accumulated exact-command rules:

```bash
[ -f .claude/settings.local.json ] && echo "LOCAL_SETTINGS=true" || echo "LOCAL_SETTINGS=false"
```

If LOCAL_SETTINGS is true, run `jq -r '.permissions.allow[]? // empty' .claude/settings.local.json 2>/dev/null | grep -c -v '[:*?\[\{]' || echo '0'` and read the output as EXACT_COUNT.

**If >20 exact-command rules detected:**

Use **AskUserQuestion**:

```
Found N exact-command rules that could be replaced by M clean patterns.
Consolidate? (This replaces, not merges — your current rules will be
backed up to .claude/settings.local.json.bak.)
```

- **Yes** — Back up the current file, then replace exact-command rules with the profile's pattern rules:
  ```bash
  cp .claude/settings.local.json .claude/settings.local.json.bak
  ```
  Then rebuild the allow array: keep user glob/pattern rules, replace exact-command rules with the profile patterns.

- **No** — Leave as-is.

### 7g: jq Dependency Check

```bash
which jq 2>/dev/null && echo "JQ=available" || echo "JQ=missing"
```

Record `JQ_STATUS` for the report. If jq is missing, the hook will fall through silently on all commands (graceful degradation — all prompts appear as if the hook is not installed).

### 7h: Report

Build the permissions report line:

- "Hook installed at .claude/hooks/auto-approve.sh." (or "Hook updated from vX to vY." or "Hook already current.")
- "Profile: [Standard | Permissive]. Added N new rules, M already present."
- "**Restart Claude Code for hooks to take effect.**"
- If `JQ=missing`: "jq not found — the hook requires jq for JSON parsing. Install jq (`brew install jq` / `apt install jq`) before restarting."

### 7i: Install Session Worktree Hook

**CRITICAL: This step MUST run at orchestrator level. Do NOT delegate to a subagent.** Subagents cannot write to `.claude/` directory (platform-level security boundary — writes silently fail).

Install the session-worktree hook from the plugin template. This follows the same pattern as auto-approve.sh installation (Step 7b).

Use the PLUGIN_ROOT value from init-values.sh output:

```bash
WORKTREE_TEMPLATE="<PLUGIN_ROOT>/templates/session-worktree.sh"
[[ -f "$WORKTREE_TEMPLATE" ]] && echo "WORKTREE_TEMPLATE=found" || echo "WORKTREE_TEMPLATE=missing"
```

**If template is missing:** Skip silently — the template may not exist in older plugin versions.

**If template is found:**

Ensure the hooks directory exists:

```bash
mkdir -p .claude/hooks
```

**Version comparison (idempotent):**

```bash
[ -f .claude/hooks/session-worktree.sh ] && echo "WORKTREE_HOOK_EXISTS=true" || echo "WORKTREE_HOOK_EXISTS=false"
```

If the hook exists, run `sed -n '2s/^# session-worktree v//p' .claude/hooks/session-worktree.sh` and read the output as INSTALLED_WORKTREE_VERSION.

Run `sed -n '2s/^# session-worktree v//p' <WORKTREE_TEMPLATE>` and read the output as TEMPLATE_WORKTREE_VERSION.

- **If no installed hook:** Copy the template and set executable:
  ```bash
  cp "$WORKTREE_TEMPLATE" .claude/hooks/session-worktree.sh
  chmod +x .claude/hooks/session-worktree.sh
  ```
  Record: `WORKTREE_HOOK_STATUS=installed`

- **If installed version is older than template version:** Replace and report:
  ```bash
  cp "$WORKTREE_TEMPLATE" .claude/hooks/session-worktree.sh
  chmod +x .claude/hooks/session-worktree.sh
  ```
  Record: `WORKTREE_HOOK_STATUS=updated` (from v$INSTALLED_WORKTREE_VERSION to v$TEMPLATE_WORKTREE_VERSION)

- **If versions match:** Skip (idempotent). Record: `WORKTREE_HOOK_STATUS=current`

### 7j: Register SessionStart Hook in settings.json

**CRITICAL: This step MUST run at orchestrator level. Do NOT delegate to a subagent.** Subagents cannot write to `.claude/` directory.

Read the existing `.claude/settings.json`:

```bash
cat .claude/settings.json
```

Check if `SessionStart` hook array already contains an entry with `command` matching `session-worktree.sh`. If already registered, skip (idempotent).

If missing, merge the following `SessionStart` hook entry into the existing settings using the same `jq` merge pattern as Step 7c (PreToolUse registration):

```json
"SessionStart": [{
  "matcher": "",
  "hooks": [{"type": "command", "command": "bash .claude/hooks/session-worktree.sh"}]
}]
```

**Merge rules:**
- If `SessionStart` array already exists with other hooks, append this entry to the array (don't clobber existing SessionStart hooks)
- If `SessionStart` does not exist, create the array with this entry
- Preserve all existing hooks (PreToolUse, PostToolUse, etc.) exactly as-is
- Use `jq` for safe JSON manipulation

Write the merged result back to `.claude/settings.json`. Validate it is well-formed JSON.

Record: `SESSION_HOOK_STATUS=registered` or `SESSION_HOOK_STATUS=already_present`

### 7k: Verify .worktrees/ in .gitignore

**CRITICAL: This step MUST run at orchestrator level. Do NOT delegate to a subagent.** Subagents cannot reliably write to `.gitignore` in the project root.

Session worktrees live in `.worktrees/` (managed by bd). This directory should already be gitignored for bd-managed worktrees. Verify it is present:

```bash
grep -q '\.worktrees/' .gitignore && echo "WORKTREE_GITIGNORE=present" || echo "WORKTREE_GITIGNORE=missing"
```

If missing: append `.worktrees/` to `.gitignore` using the **Edit tool**. Silent addition, no user prompt.

### 7l: Install Pre-Commit Worktree Check Hook

Install a git-level pre-commit hook that blocks commits to the default branch when `session_worktree: true`. This is defense-in-depth alongside the AGENTS.md prose instruction — the prose tells the model to create a worktree, the git hook catches failures.

Use the PLUGIN_ROOT value from init-values.sh output:

```bash
PRECOMMIT_TEMPLATE="<PLUGIN_ROOT>/templates/pre-commit-worktree-check.sh"
[[ -f "$PRECOMMIT_TEMPLATE" ]] && echo "PRECOMMIT_TEMPLATE=found" || echo "PRECOMMIT_TEMPLATE=missing"
```

**If template is missing:** Skip silently — the template may not exist in older plugin versions. Record: `PRECOMMIT_HOOK_STATUS=skipped`.

**If template is found:**

Three scenarios for `.git/hooks/pre-commit`:

1. **No existing pre-commit hook** — copy the template and set executable:
   ```bash
   cp "$PRECOMMIT_TEMPLATE" .git/hooks/pre-commit
   chmod +x .git/hooks/pre-commit
   ```
   Record: `PRECOMMIT_HOOK_STATUS=installed`

2. **Existing pre-commit hook already contains the worktree check** — detect by grepping for the unique marker `session_worktree`:
   ```bash
   grep -q 'session_worktree' .git/hooks/pre-commit && echo "WORKTREE_CHECK=present" || echo "WORKTREE_CHECK=missing"
   ```
   If present, skip. Record: `PRECOMMIT_HOOK_STATUS=already_present`

3. **Existing pre-commit hook WITHOUT the worktree check** — append the check to the existing hook, separated by a comment marker:
   ```bash
   printf '\n# ── session-worktree pre-commit check (added by /do:setup) ──────────────\n' >> .git/hooks/pre-commit
   # Append the template content, skipping the shebang line (line 1) and set -e (already in existing hook)
   tail -n +3 "$PRECOMMIT_TEMPLATE" >> .git/hooks/pre-commit
   ```
   Record: `PRECOMMIT_HOOK_STATUS=appended`

**User escape hatch:** `git commit --no-verify` bypasses the hook for intentional main-branch commits.

## Step 8: Write Config Files

Write two config files — one shared (committed), one personal (gitignored).

### 8a: Project Config — `compound-workflows.md`

Shared project settings. **Should be committed** so team members share the same agent configuration.

```markdown
---
# Auto-generated by /do:setup
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

### 8b: Local Config — `compound-workflows.local.md`

Machine-specific environment settings. **Should be gitignored** — each developer's environment differs.

```markdown
---
# Auto-generated by /do:setup — machine-specific, gitignored
# Re-run setup to update
---

# Compound Workflows Local Config

tracker: [beads|todowrite]
gh_cli: [available|not available]
stats_capture: true
stats_classify: true
compact_version_check: false
compact_cost_summary: true
compact_auto_commit: false
compact_compound_check: true
compact_push: true
# Session worktree isolation (concurrent session safety)
# Set to false to disable worktree-per-session — sessions work directly on main
session_worktree: true
```

Fill in based on detected environment. Red team provider preferences are NOT stored — they're detected at runtime each session (CLI availability varies by machine and may change). Stats toggles default to `true` — capture and classification are enabled unless explicitly disabled.

### 8c: Routing Rules

Check if the project has an `AGENTS.md` or `CLAUDE.md` with a compound-workflows routing section:

```bash
# Check for existing routing rules
grep -q 'compound:brainstorm' AGENTS.md 2>/dev/null && echo "ROUTING_EXISTS=AGENTS.md" || \
grep -q 'compound:brainstorm' CLAUDE.md 2>/dev/null && echo "ROUTING_EXISTS=CLAUDE.md" || \
echo "ROUTING_EXISTS=none"
```

**If routing rules already exist:** Read the existing routing section and compare it against the canonical version below. If identical, skip. If different (missing routes, outdated wording, extra entries), show the user a diff summary of what would change and ask:

> Your routing rules differ from the current version. Want to update them? (yes / no / show diff)

On "yes", replace the existing routing section with the canonical version. On "no", leave as-is.

**If no routing rules found:** Append to `AGENTS.md` (create if needed).

**Canonical routing section:**

```markdown
## Routing

Do not use plan mode, ad-hoc research agents, or inline answers for tasks that have a compound command. Route through compound commands instead:

- **Exploring an idea** ("should we...", "what if...", "is there an opportunity to..."): `/do:brainstorm` — do not answer exploratory questions directly
- **Building a known feature or task**: `/do:plan` to design, then `/do:work` to execute — do not implement without a plan
- **Plan needs deeper research**: `/do:deepen-plan` before executing
- **Reviewing code changes**: `/do:review` — do not review inline
- **Solved a non-obvious problem**: `/do:compound` to capture institutional knowledge
- **Before `/compact`**: `/do:compact-prep` to preserve session context
- **Abandoning a session** ("done for today", "wrapping up for the day", "closing out", "ending the session"): `/do:abandon` — do not just close the terminal
- **Recovering a dead/exhausted session**: `/compound-workflows:recover`

### Session-End Detection

When you detect session-end language ("done for today", "wrapping up for the day", "closing out",
"ending the session", "abandoning"), add an inline text suggestion:

> Tip: run `/do:abandon` to capture session knowledge before closing.

**This is a suggestion, not a gate.** Do not ask, do not block, do not repeat if the user continues working.

**Suppression rules:**
- Suppress after the user dismisses it or ignores it twice in the same session (track in conversation context)
- Ambiguous phrases ("I'm done", "that's all") excluded from triggers — they fire on task completion, creating cry-wolf pattern
- If the user says "stop suggesting /abandon", stop immediately for the remainder of the session
```

#### Session Worktree Isolation Block (conditional)

**Gate:** Only add this block if `session_worktree` in `compound-workflows.local.md` is NOT `false`. If the key is missing (not yet configured), include the block (default is `true`).

**v1→v2 migration:** Check if the AGENTS.md contains `## Session Worktree Isolation`. If the heading exists, check whether any of the next 5 non-empty lines contain `EnterWorktree` (this distinguishes v1 blocks from v2 or user-written sections). If v1 detected:
1. Replace the entire section (from `## Session Worktree Isolation` up to but not including the next `##` heading) with the v2 canonical text below.
2. Note `v1→v2 updated` in the setup summary report (Step 9, Worktree line).

**Idempotent (v2):** If `## Session Worktree Isolation` exists but does NOT contain `EnterWorktree` in the next 5 non-empty lines, it is already v2 (or user-customized). Skip injection.

**Fresh install:** If `## Session Worktree Isolation` is not present at all, append the v2 block after the routing section (after the Session-End Detection suppression rules).

**v2 canonical text:**

```markdown
## Session Worktree Isolation

**At session start, before doing anything else, create a session worktree.**
Run `bd worktree create .worktrees/session-<name>` and `cd` into it.
Do not read files, run commands, or respond to the user first.

- Name the worktree after the task if known: `session-s7qj` or `session-fix-typo`
- User can say "stay on main" / "skip worktree" to opt out
- If you're already in a worktree (post-compact resume), skip — you're already isolated
- If `bd worktree create` fails, warn the user and proceed on main
- If the hook warns that bd is unavailable, skip worktree creation
- At session end, `/do:compact-prep` merges back to the default branch
- Any git operations before creating the worktree happen on the default branch
- Before committing, if session_worktree is enabled and you're NOT in a worktree,
  warn the user: "You're committing to main without worktree isolation. Continue?"

**Beads database (.beads/) is shared across all sessions.** Worktree isolation covers git state only. Bead operations are concurrency-safe at the SQL level (Dolt) but not coordination-safe at the business logic level.
```

### 8d: Migration Check

Before writing, check if either config file already exists:

```bash
cat compound-workflows.md 2>/dev/null
cat compound-workflows.local.md 2>/dev/null
```

If `compound-workflows.local.md` exists but lacks `stats_capture`, append both stats keys with `true` defaults:

```bash
bash ${CLAUDE_SKILL_DIR}/../../scripts/migrate-stats-keys.sh
```

Read the stdout for `STATS_KEYS_ADDED=true` status.

**Config key migration:** If `compound-workflows.local.md` exists, check for each of the 6 config keys below independently and append any that are missing with their defaults. Keys may be partially present (e.g., user added some manually). Handle each key independently:

**Migration procedure:** Read `compound-workflows.local.md` (create with `touch` if it does not exist). For each of the 6 config keys below, check whether the key is already present (`grep -q`). For any missing key, use the **Edit tool** to append it at the end of the file with its default value.

| Key | Default |
|-----|---------|
| `compact_version_check` | `false` |
| `compact_cost_summary` | `true` |
| `compact_auto_commit` | `false` |
| `compact_compound_check` | `true` |
| `compact_push` | `true` |
| `session_worktree` | `true` |

Handle each key independently — partial presence is expected during migration.

Defaults rationale: most keys default to `true` (enabled, preserves current behavior). Exceptions: `compact_version_check` defaults to `false` (only relevant to plugin developers, not regular users) and `compact_auto_commit` defaults to `false` (opt-in to auto-execute — stronger behavior change).

If an old-format `compound-workflows.local.md` exists (look for `review_agents:` in the local file, or `review_agents: compound-engineering`), inform the user:

> **Migration notice:** Found existing config with old schema. Project settings (stack, agents, depth) will move to `compound-workflows.md` (committed). Environment settings will stay in `compound-workflows.local.md` (gitignored).

Write both files with the new schema.

### 8e: Bash Prompt Reduction (Optional)

Claude Code's heuristic inspector flags `$()`, `$(())`, glob+redirect, and heredoc patterns in Bash tool input, causing permission prompts. The model naturally generates these patterns during conversation (debugging, data analysis, bead management). This step offers to inject rules that teach the model to avoid these patterns. <!-- heuristic-exempt: prose reference, not executable -->

Use **AskUserQuestion**:

```
Bash prompt reduction?

The plugin can add rules to your CLAUDE.md that teach the model to avoid
bash patterns triggering permission prompts (like $() substitution, <!-- heuristic-exempt -->
2>/dev/null + globs). This reduces prompts during normal conversation
without changing what's allowed — the rules are advisory ("SHOULD avoid").

1. Enable (recommended) — adds Bash Generation Rules to CLAUDE.md
2. Skip — no bash generation rules

Which? (1/2)
```

**If Skip:** Record `BASH_RULES=skipped`. Move on.

**If Enable:**

#### Check for Existing Rules

```bash
[ -f CLAUDE.md ] && echo "CLAUDE_MD=exists" || echo "CLAUDE_MD=missing"
```

If CLAUDE.md exists, check for existing rules:

```bash
grep -q 'Bash Generation Rules' CLAUDE.md && echo "RULES=exists" || echo "RULES=missing"
```

- **If rules already exist:** Say "Bash Generation Rules already present in CLAUDE.md — skipping." Record `BASH_RULES=already_present`. Move on.
- **If rules don't exist (or CLAUDE.md doesn't exist):** Append the following section to CLAUDE.md (create the file first if needed).

#### Bash Generation Rules Section

Read the template from `<PLUGIN_ROOT>/resources/bash-generation-rules.md` (using the PLUGIN_ROOT value from init-values.sh output). Append its content to the project's CLAUDE.md using the **Edit** or **Write** tool. If CLAUDE.md doesn't exist, create it with the template content.

Record `BASH_RULES=enabled`.

#### Suggest Complementary Static Rules

If the user chose Standard permission profile (Step 7d), additional static rules can suppress heuristic triggers for safe commands that the CLAUDE.md rules can't fully prevent (e.g., `which cmd 2>/dev/null && ...` where `which` is the first token):

Use **AskUserQuestion**:

```
The CLAUDE.md rules teach the model to avoid $() patterns, but some <!-- heuristic-exempt -->
commands still trigger heuristics when avoidance isn't possible.

These low-risk static rules suppress heuristics for safe commands:

  Bash(which:*)      — availability checks (which cmd && ...)
  Bash(echo:*)       — output and separators
  Bash(mkdir:*)      — directory creation chains
  Bash(ls:*)         — directory listings
  Bash(git log:*)    — read-only git history
  Bash(git diff:*)   — read-only git diffs
  Bash(git status:*) — read-only git status
  Bash(git branch:*) — read-only git branch listing

Add to settings.local.json? (yes/no)
These only suppress heuristics — the hook still checks safety.
```

**If yes:** Merge `Bash(which:*)`, `Bash(echo:*)`, `Bash(mkdir:*)`, `Bash(ls:*)`, `Bash(git log:*)`, `Bash(git diff:*)`, `Bash(git status:*)`, `Bash(git branch:*)` into `.claude/settings.local.json` using the same merge logic as Step 7e. Count additions.

**If no:** Move on.

If the user chose Permissive profile, skip this suggestion — the permissive rules already cover these commands via `Bash(bash:*)`.

## Step 9: Summary

Display the setup summary:

```
## Setup Complete

Environment:
  Task tracking:  [beads (compaction-safe) | TodoWrite (in-memory)] <!-- context-lean-exempt: display label -->
  Red team:       [Gemini CLI + Codex CLI | PAL MCP | Claude subagent fallback]
  GitHub CLI:     [available | not available]
  Cost tracking:  [ccusage available | not installed — npm install -g ccusage]

Stack & Review:
  Detected stack: [python | typescript | general]
  Review agents:  [agent list]
  Review depth:   [standard | comprehensive | minimal]

Directories:     [all present | N created]
Config:          compound-workflows.md (project, committed)
                 compound-workflows.local.md (environment, gitignored)
Permissions:     Hook: .claude/hooks/auto-approve.sh [installed | updated | current]
                 Profile: [Standard | Permissive] — [N added, M already present]
                 ⚠ Restart Claude Code for hooks to take effect.
                 [jq not found — install before restarting | jq available]
Bash rules:      [enabled — rules added to CLAUDE.md | already present | skipped]
                 [+ which, echo, mkdir static rules | Permissive covers these | declined]
Worktree:        Hook: .claude/hooks/session-worktree.sh [installed | updated | current | skipped]
                 SessionStart hook: [registered | already present]
                 AGENTS.md isolation block: [added | v1→v2 updated | already present | skipped]
                 Pre-commit hook: [installed | already present | appended to existing | skipped]
                 session_worktree: true (edit compound-workflows.local.md to disable)

Ready to go:
  /do:brainstorm  — explore an idea
  /do:plan        — create an implementation plan
  /do:work        — execute a plan
  /do:review      — review code changes

Tip: Edit the Workflow Instructions section in compound-workflows.md
     to add red team focus areas, domain constraints, or review emphasis.
     Run /do:setup anytime to reconfigure.
     Red team provider is chosen per-session based on available tools.

Known issue: Claude Code's AskUserQuestion dialog can obscure the last
     few lines of text above it. If you see truncated output, add this
     to ~/.claude/CLAUDE.md (ref: anthropics/claude-code#23862):
       "When using AskUserQuestion, always add 3-4 blank lines at the
        end of your text output before the tool call."
```
