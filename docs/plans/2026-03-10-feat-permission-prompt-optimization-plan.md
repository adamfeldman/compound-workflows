---
title: "feat: Permission prompt optimization"
type: feat
status: active
date: 2026-03-10
origin: docs/brainstorms/2026-03-10-permission-prompt-optimization-brainstorm.md
---

# Permission Prompt Optimization

## Summary

Implement a layered permission system that reduces interactive permission prompts to near-zero for standard operations while preserving safety prompts for destructive actions. Three deliverables:

1. **PreToolUse hook script** (`.claude/hooks/auto-approve.sh`) — programmable auto-approval with path validation and audit logging. Primary mechanism.
2. **Committed baseline** (`.claude/settings.json`) — minimal static rules (Write/Edit .workflows/**) + hook registration. Ships with the plugin.
3. **Setup command enhancement** — new permission configuration step in `/compound:setup` with three profiles (Surgical/Conservative/Aggressive).

## Background

Analysis of session JSONL logs found ~500 of 2,637 Bash calls (~19%) trigger permission prompts. Subagents cannot inherit parent session permission grants, causing silent data loss when background agents are blocked on Write. Static wildcard rules (`Bash(bash:*)`, `Bash(rm:*)`) are sandbox escapes — all 3 red team providers flagged this. PreToolUse hooks are a documented, supported mechanism for permission automation in Claude Code. Deny rules are broken (GitHub #27040, #6699, #8961). (See brainstorm: `docs/brainstorms/2026-03-10-permission-prompt-optimization-brainstorm.md` for full analysis.)

Key decisions from brainstorm:
- Hooks as primary mechanism (not static rules) — path-scoped, auditable, no accretion
- Minimal committed baseline — only Write/Edit .workflows/** (supply chain risk minimization)
- Project-only scope — never global ~/.claude/settings.json
- Interpreters opt-in only (Aggressive profile) with explicit warnings
- Setup is idempotent — merge, not replace

## Implementation Constraints

**Orchestrator-only steps:** Steps 1 and 2 modify files in `.claude/` which is a protected directory — subagents cannot write there (platform security boundary, confirmed during v1.8.0). When executing via `/compound:work`, these steps MUST be assigned to the orchestrator context, not dispatched as subagent tasks. Step 3 modifies `plugins/compound-workflows/commands/setup.md` (subagent-safe). The setup command that Step 3 defines will write to `.claude/` at runtime, which works because the setup command runs in the orchestrator context (it's a slash command). [red-team--opus, see .workflows/plan-research/permission-prompt-optimization/red-team--opus.md]

**Hook restart required:** Hooks are loaded at Claude Code session startup. After modifying `.claude/settings.json` to register the PreToolUse hook, the user must restart their Claude Code session for the hook to take effect. The setup command must communicate this.

**Project root detection:** The hook input JSON includes a `cwd` field. Validate it by checking for a `.claude/` directory at that path (project root marker). If validation fails or `cwd` is missing, fall back to `git rev-parse --show-toplevel`. This guards against `cwd` reflecting a subagent's working directory after `cd` rather than the project root. [red-team--gemini, red-team--opus, see .workflows/plan-research/permission-prompt-optimization/red-team--opus.md]

### Step 1: Create PreToolUse Hook Script

**File:** `.claude/hooks/auto-approve.sh`

A bash script that receives tool call JSON on stdin and returns auto-approve decisions for known-safe operations. Models the same pattern as the existing `.claude/hooks/plugin-qa-check.sh` (PostToolUse).

**Hook input (stdin JSON):**

```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "ls -la .workflows/"
  }
}
```

**Hook output (auto-approve):**

```json
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}
```

**Hook output (fall-through — no decision):** Exit 0 with no stdout output.

**Additional hook input fields available:** `session_id`, `cwd` (project root — use this for path validation instead of `git rev-parse`), `permission_mode` (default/plan/acceptEdits/dontAsk/bypassPermissions), `tool_use_id`. When running in a subagent: `agent_id`, `agent_type`.

**Auto-approve logic by tool type:**

**Bash tool — metacharacter pre-check (runs on each segment after compound splitting):**
- If segment contains `>`, `>>`, or `2>` redirect operators, fall through (redirects can write to arbitrary files). [red-team--opus]
- If segment contains `$(` or backticks (`` ` ``), fall through (command substitution can execute arbitrary code inside any command, e.g., `echo $(rm -rf /)`). [review--security-sentinel H2]
- If segment contains `<<`, fall through (heredocs enable arbitrary code execution via interpreters, e.g., `bash << 'EOF'`). [review--security-sentinel M1]

**Bash tool — safe command prefixes (always approve, after pre-checks pass):**
- `ls`, `find`, `cat`, `head`, `tail`, `wc`, `grep`, `sort`, `uniq`, `cut`, `tr`
- `which`, `sleep`, `echo`, `printf`, `date`, `uuidgen`
- `cd`, `touch`, `realpath`, `dirname`, `basename`
- `diff`, `md5`, `shasum`, `read`
- `bd`, `ccusage`, `claude` (project tools)

**Prefix matching rule:** Match the first whitespace-delimited token of the command (or pipe/compound segment) exactly against the prefix list. Do not use string-startswith matching — `read` must not match `readlink`.

**Bash tool — git (with guardrails):**
- Approve `git` commands UNLESS command contains `push --force`, `push -f`, `reset --hard`, `clean -f`, `clean -fd`, `checkout -- .`, `restore .`, `restore --staged .`, `stash drop`, `branch -D`
- These dangerous patterns fall through to prompt

**Compound command pre-check (runs before prefix matching):**
- **Quote-aware tokenization:** Before splitting, track single-quote (`'`) and double-quote (`"`) state. Characters inside quoted regions are literal, not operators. Only split on `&&`, `||`, `;`, `|` that appear outside quotes. Example: `git commit -m "fix; update"` is a single command (`;` inside quotes), not two segments. Same approach applies to redirect detection below.
- Split into segments and validate EACH segment independently
- Each segment must match a safe prefix to be approved
- If ANY segment doesn't match a safe prefix, fall through for the entire command
- Example: `ls && rm foo` — `ls` is safe, `rm foo` needs path validation; entire command goes through rm path-scoping
- Example: `ls && curl example.com` — `curl` is not in any safe list; entire command falls through

**Path resolution algorithm (used by rm and bash/python3 scoping):**
- Extract `cwd` from hook input JSON — this is the project working directory
- Validate `cwd`: check that `$cwd/.claude/` directory exists (project root marker). If not, fall back to `git rev-parse --show-toplevel` for the project root
- Resolve each path to absolute using `realpath -m` (resolve without requiring existence): `resolved=$(realpath -m "$path" 2>/dev/null)` — if relative, resolves against shell cwd which matches `cwd`
- Check that resolved path starts with `$project_root/` prefix (string comparison after canonicalization)
- If `realpath` is unavailable, fall through for all path-sensitive commands (don't attempt custom string normalization — it's error-prone for traversal attacks)
- If `cwd` is missing from input, fall through (don't auto-approve path-sensitive commands)
- [red-team--gemini, red-team--openai, see .workflows/plan-research/permission-prompt-optimization/red-team--gemini.md]

**Bash tool — rm (path-scoped):**
- If any path argument contains glob characters (`*`, `?`, `[`, `{`), fall through unconditionally — `realpath -m` cannot resolve paths with globs. [review--security-sentinel H4]
- Extract all path arguments from the rm command (strip flags like -r, -f, -rf)
- Approve ONLY if every path argument passes the path resolution algorithm (stays within `$project_root`)
- Fall through if any path fails validation
- Special deny: always fall through for `rm -rf /`, `rm -rf ~`, `rm -rf $HOME`

**Bash tool — mkdir (path-scoped):**
- Same path resolution as rm — approve only if path arguments resolve within `cwd`
- `mkdir -p /tmp/staging` falls through (outside project)
- `mkdir -p .workflows/stats` approves (within project)
- [red-team--opus, see .workflows/plan-research/permission-prompt-optimization/red-team--opus.md]

**Bash tool — bash/python3 scripts (path-scoped):**
- Approve `bash <path>` or `python3 <path>` only if `<path>` passes the path resolution algorithm (stays within `cwd`)
- Fall through for paths outside project or no path argument

**Bash tool — variable assignments:**
- Commands starting with `[A-Z_]+=` (shell variable assignment pattern)
- Fall through if command contains `$(` or backticks (command substitution can execute arbitrary code inside assignments)
- If the command contains `&&`, `||`, `;`, or `|` after the assignment, the compound command pre-check applies — each subsequent segment must also be safe
- Pure assignments without continuation or substitution (`VAR=value`) are always safe
- [red-team--openai, red-team--opus, see .workflows/plan-research/permission-prompt-optimization/red-team--openai.md]

**Shell constructs — NOT auto-approved:**
- `if`, `[[`, `for`, `while`, `do`, `done`, `then`, `fi`, `else` — removed from safe prefix list. Claude Code's bash safety heuristics already trigger prompts for multi-line/control-flow commands (issue #30435), so auto-approving these gains nothing but adds bypass risk (e.g., `if true; then rm -rf /; fi`). [red-team--openai, red-team--opus, see .workflows/plan-research/permission-prompt-optimization/red-team--opus.md]

**Write/Edit tool — .workflows scoping:**
- Approve Write and Edit if `tool_input.file_path` matches `.workflows/**` (relative) or `*/.workflows/**` (absolute)
- Fall through for all other paths

**Everything else:** No output, exit 0 (falls through to normal prompting).

**Safety guardrails:**
- jq dependency check at script start (same pattern as plugin-qa-check.sh)
- If jq is missing, fall through silently (no auto-approve, no crash)
- If stdin JSON is malformed, fall through silently
- Use `cwd` field from hook input JSON for project root (provided by Claude Code — no subprocess needed). Fall back to `git rev-parse --show-toplevel` if `cwd` is missing.
- Log every approval to `.workflows/.hook-audit.log` (dotfile — easier to gitignore). Format: `ISO-8601-timestamp\ttool_name\tcommand_or_path` (tab-delimited, one line per approval). Example: `2026-03-10T17:45:23Z\tBash\tls -la .workflows/`
- Script must be `chmod +x`
- No sentinel file suppression — unlike the PostToolUse QA hook, auto-approval should always be active (including during `/compound:work`)
- `.workflows/` is already gitignored at directory level — no additional `.gitignore` entry needed for the audit log

**Acceptance criteria:**
- [x] Parses stdin JSON with jq (graceful fallback if jq missing)
- [x] All safe Bash prefixes auto-approved
- [x] Any command with redirect operators (`>`, `>>`, `2>`) falls through
- [x] Git destructive operations fall through to prompt
- [x] `rm` validates all path arguments within project directory
- [x] `bash`/`python3` validates script path is project-relative
- [x] Variable assignments (`VAR=...`) auto-approved
- [x] Write/Edit to .workflows/** auto-approved
- [x] Unrecognized tools/commands produce no output (fall through)
- [x] Audit log written for every approval
- [x] Script is executable

### Step 2: Update Committed Settings

**File:** `.claude/settings.json`

Merge the existing PostToolUse hook with new permissions and PreToolUse hook. The result ships with the plugin as the committed baseline.

**Target state:**

```json
{
  "permissions": {
    "allow": [
      "Write(//.workflows/**)",
      "Edit(//.workflows/**)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/auto-approve.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/plugin-qa-check.sh"
          }
        ]
      }
    ]
  }
}
```

**Notes:**
- Empty string matcher `""` matches all tool types (hook inspects internally and decides)
- If empty matcher doesn't work, fall back to explicit matchers for Bash, Write, Edit (3 entries pointing to same script)
- Permissions section is minimal — only what subagents need for .workflows output
- Existing PostToolUse hook preserved exactly as-is

**Acceptance criteria:**
- [x] permissions.allow has Write/Edit .workflows/**
- [x] PreToolUse hook registered
- [x] PostToolUse hook preserved unchanged
- [x] Valid JSON (no trailing commas, correct nesting)
- [x] Matcher behavior verified — hook fires for Bash, Write, Edit tool calls

**Post-change note:** Hooks load at session startup. After this step, the user must restart their Claude Code session for the PreToolUse hook to take effect. The setup command (Step 3) should warn about this.

### Step 3: Update Setup Command

**File:** `plugins/compound-workflows/commands/compound/setup.md`

Add a new step between the existing setup.md's directory creation step and config file writing step for permission configuration.

**New section: Configure Permissions** (inserted in setup.md between current "Step 6: Create Directories" and "Step 7: Write Config Files")

Present two profiles via AskUserQuestion with impact descriptions:

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
   ⚠ cat:*     — bypasses Read tool path restrictions
   ⚠ rm:*      — unscoped by static rule (hook provides path-scoping but static rule fires FIRST and is broader)
   Plus: gh, grep, find, claude, ccusage, head, tail, sed, cp, timeout, open
   Plus: mcp__pal__clink, mcp__pal__chat, mcp__pal__listmodels, WebSearch

   WARNING: Static allow rules are evaluated BEFORE the hook. When a static
   rule matches, the hook never fires — its pipe/compound/redirect/path-scoping
   checks are bypassed entirely. Choose this ONLY if you trust your LLM and
   want minimal friction. [red-team--openai, red-team--opus, review--code-simplicity]

Which profile? (1/2)
```

**Implementation logic:**
1. **Create hook script:** Write `.claude/hooks/auto-approve.sh` (the hook from Step 1) with a version comment on line 2: `# auto-approve v<plugin-version>`. Create `.claude/hooks/` directory if missing. Set executable permission. On re-run: compare the version comment in the installed hook vs the current plugin version. If installed is older, replace the script and report "Updated auto-approve.sh from vX to vY." If same version, skip (idempotent). [red-team--opus, see .workflows/plan-research/permission-prompt-optimization/red-team--opus.md]
2. **Register hook in settings.json:** Read existing `.claude/settings.json`. Merge PreToolUse hook entry and permissions.allow (Write/Edit .workflows/**). Preserve existing hooks. If already registered, skip. Write back.
3. **Add profile rules to settings.local.json:** Read existing `.claude/settings.local.json` (create if missing). Build rule set for chosen profile. Merge: add missing rules, skip already-present, never remove user-added. Write back.
4. **Report:** "Added N new rules, M already present. Hook installed at .claude/hooks/auto-approve.sh. **Restart Claude Code for hooks to take effect.**"
   4a. **jq dependency check:** Verify `jq` is available on PATH. If missing, append to the report: "jq not found — the hook requires jq for JSON parsing. Install jq (`brew install jq` / `apt install jq`) before restarting, or the hook will fall through silently (all prompts will appear as if the hook is not installed)."
5. **First-run migration:** if >20 exact-command Bash rules detected (auto-accumulated one-offs), offer to consolidate. An "exact-command" rule is one that does NOT contain `:*` or glob patterns — e.g., `Bash(git status)` is exact-command, `Bash(git:*)` is a pattern:
   "Found N exact-command rules that could be replaced by M clean patterns. Consolidate? (This replaces, not merges — your current rules will be backed up.)"

**Note:** Steps 1-2 create the hook and register it for the end user's project. The hook script is shipped as a template file at `plugins/compound-workflows/templates/auto-approve.sh`. The setup command copies this template to `.claude/hooks/auto-approve.sh` — no heredoc embedding or inline generation needed. This keeps the hook script as a standalone, testable file.

**Profile rule sets:**

Standard: no additional static rules (hook handles everything)

Permissive:
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
Bash(rm:*)
Bash(timeout:*)
Bash(open:*)
mcp__pal__clink
mcp__pal__chat
mcp__pal__listmodels
WebSearch
```

**Permission evaluation order:** Claude Code evaluates static allow rules BEFORE PreToolUse hooks. A matching static rule auto-approves without invoking the hook. The hook only runs for tool calls not matched by any static rule. This means Permissive profile rules REPLACE hook logic for matched commands, not supplement it. [review--architecture-strategist 5.2]

**Acceptance criteria:**
- [x] Two profile options (Standard / Permissive) presented with clear impact descriptions
- [x] WARNING labels on Permissive interpreter rules (bash, python3, cat, rm) explaining static rules bypass hook
- [x] Merge logic: reads existing, adds missing, skips duplicates
- [x] Never removes user-added rules
- [x] Reports what changed (N added, M already present)
- [x] First-run migration offer for >20 exact-command rules
- [x] Backup before migration (write old rules to `.claude/settings.local.json.bak`)
- [x] Idempotent — re-running same profile adds nothing
- [x] Profile upgrade — running Aggressive after Conservative adds only delta rules

### Step 4: Plugin Metadata & QA

- [x] Bump version in `plugins/compound-workflows/.claude-plugin/plugin.json`
- [x] Bump version in `.claude-plugin/marketplace.json`
- [x] Update `plugins/compound-workflows/CHANGELOG.md`
- [x] Verify README component counts
- [x] Run `/compound-workflows:plugin-changes-qa`
- [x] Fix any QA findings
- [x] Manual smoke test: run a Bash command that would normally prompt, verify hook auto-approves
- [x] **Subagent hook inheritance verification:** spawn a subagent that triggers a Bash call, verify the PreToolUse hook fires (check audit log for subagent entry). If hooks do NOT fire in subagents, add compensating static rules to the committed baseline for subagent needs (Write/Edit .workflows/**, Bash safe prefixes). [red-team--opus, see .workflows/plan-research/permission-prompt-optimization/red-team--opus.md]
- [x] **Adversarial test matrix:** test hook against known bypass payloads: pipe bypass (`echo evil | bash`), path traversal (`rm ../../etc/passwd`), compound obfuscation (`ls && rm -rf /`), quoted semicolons (`git commit -m "fix; rm -rf /"`), redirect bypass (`cat > /etc/passwd`), variable substitution (`VAR=$(rm -rf /)`), shell construct wrapping (`if true; then rm -rf /; fi`). All must fall through to prompt. [red-team--gemini, red-team--openai, see .workflows/plan-research/permission-prompt-optimization/red-team--gemini.md]

## Edge Cases

### Command Parsing

- **Compound commands** (`cmd1 && cmd2`): Handled by the compound command pre-check in Step 1 — split on `&&`, `||`, `;`, `|` and validate EACH segment independently against safe prefixes. If any segment doesn't match, the entire command falls through. `ls && rm foo` falls through because `rm` needs path validation. [red-team--gemini, red-team--openai, red-team--opus, see .workflows/plan-research/permission-prompt-optimization/red-team--opus.md]
- **Pipes** (`cmd | cmd2`): Included in compound command pre-check — each pipe segment is validated independently against safe prefixes. `grep foo | head` auto-approves (both safe). `echo evil | bash` falls through (`bash` without valid path arg is not auto-approvable). [red-team--gemini, red-team--openai, red-team--opus, see .workflows/plan-research/permission-prompt-optimization/red-team--gemini.md]
- **Bash safety heuristics (INDEPENDENT of hooks)**: Claude Code has built-in bash safety heuristics that fire independently of the permission system. These CANNOT be suppressed by PreToolUse hooks, static allow rules, or any mode except `--dangerously-skip-permissions`. Triggers include: `$()` command substitution, backtick substitution, multi-line scripts (for loops), heredocs with newlines, quote chars in comments. (GitHub issues #30435, #31373 — both OPEN as of 2026-03-10.) Impact: hooks reduce ~80% of prompts but cannot eliminate heuristic-triggered prompts. This is a known limitation, not a bug in our implementation.
  - **Plugin commands are affected:** The plugin's own commands (plan, work, brainstorm, deepen-plan) generate `$()` substitutions, `for` loops, heredocs, and multi-line scripts as part of normal operation. These will continue to trigger heuristic prompts even with the hook active. Follow-up work: audit plugin commands to minimize heuristic-triggering patterns where possible (e.g., replace `$()` with pipe chains, avoid inline `for` loops when simpler alternatives exist).
- **Heredocs** (`<< 'EOF'`): Treated as part of the command. The hook checks the command prefix before the heredoc. Safe if prefix is safe.
- **Redirect operators** (`>`, `>>`, `2>`): Handled by the redirect pre-check — any command with redirect operators falls through, regardless of prefix. This is conservative but safe; redirects can write to arbitrary files from any prefix.

### Path Validation (rm)

- **Relative paths**: Resolve using `realpath -m` which handles `..`, `.`, and multiple slashes correctly. Check resolved absolute path starts with `cwd/` prefix.
- **Glob patterns**: If any rm path contains glob characters (`*`, `?`, `[`, `{`), fall through unconditionally. `realpath -m` cannot resolve paths containing globs, and patterns like `rm .workflows/*/../../../etc/` would bypass validation.
- **Symlinks**: Not resolved — the hook checks the path string, not the target. A symlink within the project pointing outside is a theoretical risk but not worth the complexity of resolution.
- **Absolute paths**: Fall through (don't auto-approve) unless the absolute path starts with the project root.

### Hook Failure Modes

- **jq not installed**: Fall through silently (exit 0, no output). For PreToolUse, exit 0 with no output = no decision (falls through to normal prompting — same as if the hook didn't exist). Do NOT use exit 2 (that would block the tool call). Different from PostToolUse where exit 2 surfaces feedback.
- **Malformed stdin JSON**: jq returns error, script catches it and falls through (exit 0, no output).
- **Script error (set -e)**: Use `set -euo pipefail` but wrap jq calls in `|| true` patterns to prevent script crash on parse failure. Non-zero non-2 exit codes are non-blocking errors (logged in verbose mode, execution continues).
- **Hook script not found**: Claude Code logs an error and proceeds without the hook. User sees normal permission prompts (degraded, not broken).
- **Setup interrupted mid-write**: If settings.json is written but auto-approve.sh is not yet created, Claude Code will try to invoke a missing hook script. This logs an error but does not block operations (degraded, not broken). Setup should write the hook script before registering it in settings.json to minimize this window.
- **Performance**: Hook runs on every tool call. Must be fast (<100ms). jq parsing a small JSON blob is well within this budget. Audit log append is O(1).
- **stdout must be exclusive**: Hook stdout must contain ONLY the JSON decision. Shell profile output (from .bashrc/.zshrc) will break JSON parsing. Use `#!/bin/bash` (not `/bin/sh`) and avoid sourcing profiles.

### Hook Removal

Not shipping a `/compound:setup --remove-hook` in this version. If a user wants to disable the hook:
1. Remove the `PreToolUse` section from `.claude/settings.json`
2. Optionally delete `.claude/hooks/auto-approve.sh`
3. Restart Claude Code session

Document this in the setup summary output. A proper removal command is a future enhancement if demand exists.

### Audit Log Growth

`.workflows/.hook-audit.log` grows unbounded over time. Not adding rotation in this version — the file is small (one line per approval, ~100 bytes). At 2,637 Bash calls/session and ~80% auto-approved, that's ~2,100 entries/session ≈ 200KB. Manageable for months. If it becomes an issue, add `--rotate` flag to the hook or a cron job later.

### Setup Idempotency

- **Re-run same profile**: Zero rules added, zero removed. Report "0 added, N already present."
- **Profile upgrade** (Standard → Permissive): Add Permissive rules. Report "M added, N already present."
- **Profile downgrade** (Permissive → Standard): Do NOT remove Permissive rules — merge-only policy. Report "0 added, all present." The user must manually remove rules they don't want.
- **Concurrent settings.local.json edits**: Read → merge → write is not atomic. If another process modifies the file between read and write, changes could be lost. Acceptable for a setup command (not a hot path).
- **Missing settings.local.json**: Create it with the chosen profile's rules.
- **Malformed settings.local.json**: Warn the user and offer to back up and recreate.

## Dependencies

- **jq** — required for JSON parsing in the hook. Same dependency as the existing plugin-qa-check.sh hook. If not installed, the hook falls through silently (graceful degradation, not failure).

## Scope Boundaries

**In scope:**
- Hook script, committed settings, setup command permission step
- Bead 3k3 (absorbed — "ship .workflows permissions + setup command")

**Out of scope:**
- Developer settings.local.json cleanup (Component 3 from brainstorm) — already done manually
- Global `~/.claude/settings.json` rules
- Input modification hooks (v2.0.10 feature — future enhancement if needed)
- Hook-based denial rules (deny rules are broken; hooks could implement deny but not needed for this scope)

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-03-10-permission-prompt-optimization-brainstorm.md`
  - Carried forward: hooks as primary mechanism, minimal baseline, 3 profiles, interpreters opt-in, idempotent setup, all 3 CRITICAL + 7 SERIOUS + 9 MINOR findings resolved
- **Plan research:** `.workflows/plan-research/permission-prompt-optimization/agents/`
  - `repo-research.md` — settings.json structure, setup.md insertion point, orchestrator-only constraint, sentinel file consideration
  - `learnings.md` — prior solutions (PostToolUse hook pattern), .claude/ write restriction confirmed
  - `best-practices.md` — full hook input schema (tool_name, tool_input, cwd, permission_mode), matcher regex syntax, output format with hookEventName, exit code semantics, community patterns, 9 documented gotchas
  - `specflow.md` — 11 primary flows, 6 secondary flows, 4 failure/recovery flows; identified hook removal gap, audit log growth, setup interruption scenario
- **Existing hook pattern:** `.claude/hooks/plugin-qa-check.sh` — JSON parsing via jq, stdin reading, exit code conventions
- **Current setup command:** `plugins/compound-workflows/commands/compound/setup.md` — insertion point for new step
- **Red team research:** `.workflows/brainstorm-research/permission-prompt-audit/` — 3-provider findings, all resolved
- **Verified facts:** Subagent settings inheritance (empirically tested 2026-03-10), deny rules broken (GitHub #27040, #6699, #8961), hooks are a documented and supported mechanism for permission automation
- **Open upstream issues:** #30435 (bash safety heuristics, OPEN), #31373 ($() command substitution, OPEN), #29709 (Edit hook bypass via Bash, OPEN), #4669 (deny broken in early versions, closed as not-planned — exit 2 workaround recommended)
