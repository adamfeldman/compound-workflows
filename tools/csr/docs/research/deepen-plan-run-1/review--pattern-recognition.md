# Pattern Recognition Review: Claude Session Resume Plan

**Reviewed plan:** `/Users/adamf/Work/Strategy/docs/plans/2026-02-23-feat-claude-session-resume-tmux-plan.md`
**Date:** 2026-02-23
**Agent:** pattern-recognition-specialist

---

## 1. Shell Convention Consistency

### Comparison Target: `/Users/adamf/Work/Strategy/scripts/bq_cost_measurement.sh`

**Matches:**

| Convention | bq_cost_measurement.sh | Plan |
|---|---|---|
| Shebang | `#!/bin/bash` | `#!/bin/bash` |
| Strict mode | `set -uo pipefail` | `set -uo pipefail` |
| `printf` over `echo` | Yes | Yes |
| Named local variables | `local name="$1"` | `local resolved` |
| Error messages to stderr | `echo "ERROR: ..."` | Plan says "to stderr" |
| `jq` dependency | Not used (uses python3) | `/opt/homebrew/bin/jq` |

**Deviations and Issues:**

1. **Missing `set -e` (errexit) -- consistent, but intentional in both.** `bq_cost_measurement.sh` omits `errexit` deliberately because it handles errors in the `run_query()` function with explicit `$?` checks. The plan's `cs` tool similarly needs to handle failures gracefully (missing directories, no sessions found), so omitting `errexit` is correct. No issue here.

2. **No header comment block.** `bq_cost_measurement.sh` starts with a descriptive block:
   ```bash
   # BQ Cost Measurement Script for Intellect Pricing Model
   #
   # Runs representative queries against the Insights dev BQ dataset...
   #
   # Usage:
   #   export BQ_PROJECT=product-insights-041121
   #   bash bq_cost_measurement.sh
   ```
   The plan does not specify a header comment or usage block in the `cs` script. Since `cs help` is a subcommand, inline usage documentation is less necessary, but a header comment describing what the tool does and its dependencies would match the existing pattern.

   **Severity: Low.** Add a header comment block for consistency.

3. **Error output convention mismatch.** `bq_cost_measurement.sh` uses bare `echo "ERROR: ..."` to stdout (not stderr). The plan says "Clear error messages to stderr." The plan is actually *better* practice than the existing script. But this means the plan will establish a new pattern rather than following the existing one. Not a problem -- just noting the divergence is intentional improvement.

4. **No timestamped run IDs.** `bq_cost_measurement.sh` creates `RUN_ID="bqcost_$(date +%Y%m%d_%H%M%S)"` for traceability. The `cs` tool does not need run IDs (it is stateless), so this is a non-issue. Just noting the pattern exists.

5. **No environment variable configuration pattern.** `bq_cost_measurement.sh` uses `PROJECT="${BQ_PROJECT:-}"` for configuration. The `cs` tool hardcodes `~/.claude/projects/` as the session directory. If this path ever changes, there is no `CS_PROJECTS_DIR` environment variable to override it. The plan could benefit from:
   ```bash
   CLAUDE_PROJECTS="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
   ```
   **Severity: Low.** Personal tool, unlikely to need override. But it is a deviation from the env-var configuration pattern.

---

## 2. Hook JSON Parsing Pattern Consistency

### Comparison Target: `/Users/adamf/.claude/statusline-command.sh`

**statusline-command.sh pattern:**
```bash
input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
model=$(echo "$input" | jq -r '.model.display_name // empty')
```

**Plan's hook pattern (from line 123-129):**
```bash
INPUT=$(cat)
DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // "unknown"' | xargs basename)
MSG=$(printf '%s' "$INPUT" | jq -r '.message // "needs attention"')
```

**Matches:**

| Convention | statusline-command.sh | Plan hooks |
|---|---|---|
| Read stdin once | `input=$(cat)` | `INPUT=$(cat)` |
| Parse with jq | `echo "$input" \| jq -r '...'` | `printf '%s' "$INPUT" \| jq -r '...'` |
| Default handling | `.field // empty` | `.field // "default"` |

**Deviations and Issues:**

1. **Variable naming convention inconsistency.** `statusline-command.sh` uses lowercase (`input`, `cwd`, `model`). The plan uses UPPERCASE (`INPUT`, `DIR`, `MSG`). In shell scripting, UPPERCASE is conventionally reserved for environment variables and exported constants. Local script variables should be lowercase per both POSIX convention and the existing pattern.

   **Severity: Medium.** Inconsistent with the only other hook script in the ecosystem. Change `INPUT`, `DIR`, `MSG` to `input`, `dir`, `msg`.

2. **`printf '%s'` vs `echo` for piping.** `statusline-command.sh` uses `echo "$input" | jq`. The plan uses `printf '%s' "$INPUT" | jq`. The plan's approach is technically more correct (`echo` can interpret escape sequences on some platforms), which matches the plan's own stated convention of "printf over echo." However, this creates an inconsistency with the existing hook script. For new code, `printf '%s'` is the right choice, but it means two hook scripts in `~/.claude/` will use different idioms for the same operation.

   **Severity: Low.** The plan's choice is better; consider updating `statusline-command.sh` to match eventually, but do not block on this.

3. **JSON field path difference: `.workspace.current_dir` vs `.cwd`.** This is NOT an inconsistency -- it reflects the different JSON schemas for different hook types. The `statusLine` hook receives a different JSON structure than `Notification`/`PostToolUseFailure` hooks. The plan correctly uses `.cwd` for notification hooks per the official hooks documentation, while `statusline-command.sh` correctly uses `.workspace.current_dir` for the status line hook.

   **Severity: None.** Different hook types, different schemas. Both are correct.

4. **Missing `basename` in statusline-command.sh.** The statusline script extracts `current_dir=$(basename "$cwd")` as a separate step. The plan inlines this into the jq pipeline: `jq -r '.cwd // "unknown"' | xargs basename`. The `xargs basename` approach is fragile -- if `jq` outputs nothing or an empty string, `xargs basename` gets no argument and may error. The statusline script's two-step approach is more defensive.

   **Severity: Low.** Replace `| xargs basename` with a separate `dir=$(basename "$dir")` step for consistency and robustness.

---

## 3. Settings.json Compatibility

### Comparison Target: `/Users/adamf/.claude/settings.json`

**Existing structure:**
```json
{
  "env": { ... },
  "hooks": {
    "PreCompact": [{ "matcher": "", "hooks": [{ "type": "command", "command": "bd prime" }] }],
    "SessionStart": [{ "matcher": "", "hooks": [{ "type": "command", "command": "bd prime" }] }]
  },
  "statusLine": { ... },
  "enabledPlugins": { ... }
}
```

**Plan's additions (lines 134-151):**
```json
{
  "Notification": [{
    "matcher": "permission_prompt|idle_prompt",
    "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/notify-attention.sh", "timeout": 5000 }]
  }],
  "PostToolUseFailure": [{
    "matcher": "",
    "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/notify-error.sh", "timeout": 5000 }]
  }]
}
```

**Compatibility Assessment:**

1. **Structure is correct.** The plan follows the exact same `"HookType": [{ "matcher": "...", "hooks": [{ "type": "command", "command": "..." }] }]` pattern used by the existing `PreCompact` and `SessionStart` entries. The merge is additive -- new keys in the `hooks` object alongside existing ones.

2. **Hook command path convention inconsistency.** Existing statusline uses an absolute path: `"bash /Users/adamf/.claude/statusline-command.sh"`. The plan uses a tilde path: `"bash ~/.claude/hooks/notify-attention.sh"`. Tilde expansion depends on the shell that executes the command. Claude Code runs hook commands via a shell, so `~` should expand correctly. However, the existing pattern uses an absolute path. For consistency and robustness:

   **Severity: Medium.** Use `"bash /Users/adamf/.claude/hooks/notify-attention.sh"` to match the statusline pattern. Or, if portability across machines matters more, use `$HOME` expansion. But do not mix tilde paths and absolute paths in the same config file.

3. **Timeout is specified in the plan but not in existing hooks.** The existing `PreCompact` and `SessionStart` hooks do not set `timeout`. The plan specifies `"timeout": 5000` on the new hooks. This is good practice (the specflow analysis identified that notification hooks should have short timeouts), but it creates an asymmetry in the config. The existing hooks using default timeout (60s per the docs) is fine for `bd prime`, which is a fast command.

   **Severity: None.** Different hooks have different timeout needs. The asymmetry is justified.

4. **Missing `"async": true` on notification hooks.** The specflow analysis (Gap 21) identified that notification hooks should be async since they are fire-and-forget. The plan does not specify `"async": true`. This means notification sounds will block Claude until `osascript` completes. For a personal tool where `osascript` is typically fast (<100ms), this is low risk, but the specflow analysis's recommendation is sound.

   **Severity: Low.** Consider adding `"async": true` to both notification hook entries. Not a pattern violation, but a missed optimization identified by the project's own research.

5. **Plan correctly preserves existing hooks.** The plan explicitly states "Add hooks to existing ~/.claude/settings.json alongside SessionStart and PreCompact (preserve those)." The JSON additions are new keys that will not overwrite existing entries. Implementation needs to use a JSON merge (e.g., `jq` deep merge), not a file overwrite.

---

## 4. CLI Subcommand Pattern vs. Beads (`bd`)

### Comparison Target: `bd` CLI (beads)

**beads subcommand pattern** (from repo-research.md):
```
bd list       bd create     bd show <id>
bd update     bd close      bd sync
bd ready      bd prime      bd onboard
bd worktree create/info/remove
bd dep add
bd config get/set
```

**Plan's subcommand pattern:**
```
cs list [project_dir]
cs restore [name]
cs help
cs (no args -> help)
```

**Pattern Comparison:**

| Aspect | `bd` (beads) | `cs` (plan) | Assessment |
|---|---|---|---|
| Verb-first subcommands | Yes (`list`, `create`, `show`) | Yes (`list`, `restore`, `help`) | Match |
| Positional arguments | `bd show <id>` | `cs restore <name>` | Match |
| No-args behavior | Shows help/usage | Shows help/usage | Match |
| `--json` output mode | Supported | Explicitly cut from v1 | Noted, acceptable for v1 |
| Help subcommand | Implicit (no args) | Explicit `cs help` | Minor divergence |
| Nested subcommands | `bd worktree create` | None | Not needed |

**Deviations and Issues:**

1. **No `--help` flag.** `bd` (as a Go CLI, likely using cobra/urfave) supports `--help` on all subcommands. The plan specifies `cs help` as a subcommand but does not mention `cs --help` or `cs list --help`. Shell scripts typically handle `--help` via a case statement. This is a minor UX inconsistency.

   **Severity: Low.** Add `--help` / `-h` flag handling alongside the `help` subcommand.

2. **No version subcommand.** The specflow analysis (Gap 25) flagged this. `bd` has versioning built in. For a personal shell script, a hardcoded `VERSION="1.0.0"` at the top with `cs version` / `cs --version` is trivial to add and useful for debugging.

   **Severity: Low.** Add `cs version` for parity.

3. **Interactive mode in `cs restore`.** The plan says "No args: show interactive list, let user pick one or type `all`." Neither `bd` nor any other existing tool in this ecosystem uses interactive selection from shell. `bd` is entirely non-interactive (all arguments are positional or flags). Introducing interactive mode (reading from stdin, presenting a numbered list) adds complexity and diverges from the established non-interactive pattern.

   **Severity: Medium.** The interactive restore conflicts with the non-interactive CLI pattern established by `bd`. Consider making `cs restore` without arguments restore ALL named sessions (with a count confirmation), and `cs restore <name>` restore a specific one. Or require a name argument and error if none given. The interactive picker adds ~20 lines of shell code for a feature that will rarely be used (the user knows their session names).

4. **Argument parsing is ad-hoc.** `bq_cost_measurement.sh` uses environment variables, not subcommands. `bd` uses a proper CLI framework (Go). The plan's `cs` uses positional case-matching (`case "$1" in list|restore|help`), which is standard for simple shell scripts. This is fine for two subcommands but will not scale if `cs` grows. Not a problem for v1.

   **Severity: None.** Appropriate for scope.

---

## 5. Naming Convention Analysis

**File and directory naming:**

| Item | Plan's Name | Convention Check |
|---|---|---|
| CLI tool | `cs` | Two-letter name matches Unix convention (ls, cp, mv). Could conflict with `cs` in some systems (C# compiler on some distros). Acceptable for a personal tool on macOS |
| Hook directory | `~/.claude/hooks/` | New directory. No existing `hooks/` dir in `~/.claude/`. The compound-engineering plugin has hooks at a different level. Name is intuitive |
| Hook scripts | `notify-attention.sh`, `notify-error.sh` | Follows `verb-noun.sh` pattern. Consistent hyphen-separated naming. Matches `statusline-command.sh` style |

**Variable naming in plan code samples:**

| Item | Plan's Convention | Established Convention | Issue? |
|---|---|---|---|
| Hook stdin variable | `INPUT` (uppercase) | `input` (lowercase in statusline-command.sh) | Yes -- see Section 2.1 |
| Extracted fields | `DIR`, `MSG` (uppercase) | `cwd`, `model` (lowercase in statusline-command.sh) | Yes -- see Section 2.1 |
| Function names | `encode_path()`, `sanitize_tmux_name()` | `run_query()` in bq_cost_measurement.sh | Match (snake_case) |

**Naming inconsistency across the plan:**

1. **The plan title says "feat:" but frontmatter says `type: feat`.** This matches the plan filename convention `docs/plans/YYYY-MM-DD-<short-description>.md`. No issue.

2. **"cs" vs "claude sessions".** The plan explains `cs` stands for "claude sessions" in the repo-research, but the plan itself never states this. The `cs help` output should include this expansion for discoverability.

   **Severity: Low.** Document in the script's help output.

---

## 6. Anti-Patterns Identified

### 6.1 Shell Injection in tmux Commands

**Location:** Plan line 51
```bash
tmux new-window -n "<sanitized-name>" "claude --resume '<name>'"
```

The plan's `sanitize_tmux_name()` function (lines 113-117) sanitizes the tmux window name but the `claude --resume '<name>'` portion uses the **unsanitized** session name wrapped in single quotes. If a session name contains a single quote (e.g., `Adam's debug session`), this breaks:
```bash
tmux new-window -n "Adams_debug_session" "claude --resume 'Adam's debug session'"
```

The single quote in `Adam's` terminates the quoting early, producing a syntax error or partial command.

**Severity: High.** The specflow analysis (Gap 3 / Q1) flagged this as a shell injection risk. The plan addresses window name sanitization but not the `claude --resume` argument quoting. Fix: use `printf '%q'` for shell-safe quoting of the session name, or replace single quotes with escaped single quotes in the resume command.

### 6.2 `xargs basename` Fragility

**Location:** Plan line 126
```bash
DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // "unknown"' | xargs basename)
```

If `jq` outputs an empty string or whitespace, `xargs` will invoke `basename` with no arguments, producing an error. If `.cwd` contains spaces, `xargs` splits on whitespace and runs `basename` multiple times.

**Severity: Medium.** Replace with:
```bash
cwd=$(printf '%s' "$input" | jq -r '.cwd // "unknown"')
dir=$(basename "$cwd")
```

### 6.3 No Defensive Check for `~/.claude/projects/` Existence

**Location:** Plan Section "Implementation Details" -- path encoding

The `encode_path()` function encodes the path, but the plan does not show a check for whether `~/.claude/projects/<encoded>/` actually exists before scanning. If the directory does not exist, `grep` will error.

**Severity: Medium.** The plan's "Edge Cases Addressed" section (line 161) mentions "Format changes: Defensive checks," but no actual code is shown. Implementation should include:
```bash
projects_dir="$HOME/.claude/projects/$(encode_path "$dir")"
if [[ ! -d "$projects_dir" ]]; then
  printf 'No sessions found for %s\n' "$dir" >&2
  exit 0
fi
```

### 6.4 `osascript` Command Injection via Notification Text

**Location:** Plan line 128
```bash
osascript -e "display notification \"$DIR: $MSG\" with title \"Claude\" sound name \"Submarine\""
```

If `$DIR` or `$MSG` contain double quotes or backslashes, the AppleScript string breaks. If `$MSG` contains `\" with title \"pwned\" sound name \"` it could inject arbitrary AppleScript parameters. While the JSON input comes from Claude Code (trusted), defensive quoting is good practice.

**Severity: Low.** Sanitize `$DIR` and `$MSG` by stripping or escaping double quotes before embedding in the AppleScript string.

---

## 7. Architectural Boundary Review

### 7.1 Separation of Concerns

The plan cleanly separates three concerns:
1. **Session discovery** (`cs list`) -- reads JSONL, outputs text
2. **Session restoration** (`cs restore`) -- orchestrates tmux
3. **Notifications** (hook scripts) -- fire-and-forget macOS alerts

These are in separate files (`~/.local/bin/cs` for 1-2, separate scripts in `~/.claude/hooks/` for 3). The notification hooks have no dependency on `cs` and vice versa. This is good separation.

### 7.2 File Location Boundaries

| Component | Location | Boundary |
|---|---|---|
| CLI tool | `~/.local/bin/cs` | User-global, on PATH |
| Hook scripts | `~/.claude/hooks/` | Claude Code ecosystem |
| Hook config | `~/.claude/settings.json` | Claude Code config |
| Session data | `~/.claude/projects/` | Claude Code internal (read-only) |

The plan correctly treats session data as read-only. No component writes to another component's space. The only shared state is the `settings.json` file, which is modified once during installation.

### 7.3 Missing Boundary: Hook Scripts Should Not Depend on `cs`

The plan keeps hooks and `cs` independent -- good. But there is no explicit statement that hook scripts must be self-contained (no sourcing of shared libraries, no dependency on `cs` being installed). This boundary should be stated explicitly in implementation to prevent future coupling.

---

## 8. Plan vs. Research Alignment

The plan at `/Users/adamf/Work/Strategy/docs/plans/2026-02-23-feat-claude-session-resume-tmux-plan.md` incorporates most of the specflow analysis findings from `/Users/adamf/Work/Strategy/.workflows/plan-research/claude-session-resume/agents/specflow.md`. Specifically:

**Incorporated from specflow:**
- Extracted hooks into script files (specflow recommendation 2) -- plan uses `~/.claude/hooks/*.sh`
- Added matcher to Notification hook (specflow recommendation 3) -- plan uses `"permission_prompt|idle_prompt"`
- Defined error messages (specflow recommendation 4) -- plan lines 46, 54
- Made hooks async-capable with timeouts (specflow recommendation 6) -- plan specifies `timeout: 5000`
- Added `cs help` subcommand (specflow recommendation 8) -- plan line 57
- Cut `--layout` explicitly (specflow recommendation 9) -- plan line 165
- Addressed duplicate session names (specflow Q2) -- plan line 155
- Addressed no-sessions case (specflow Q6) -- plan line 159

**NOT incorporated from specflow (gaps that remain):**
- **Stop hook removed entirely.** The specflow flagged the Stop vs. SessionEnd confusion (specflow "Architecture Observations" section). The plan resolved this by cutting the Stop hook completely, keeping only Notification and PostToolUseFailure. This is the right call -- Stop fires every turn, which would be extremely noisy.
- **`stop_hook_active` check (specflow Q3)** -- Moot since Stop hook was cut.
- **`is_interrupt` check on PostToolUseFailure** -- The plan (line 70) says "Skip if `is_interrupt` is true" but the hook code sample (lines 122-129) does not show this check. Implementation must include it.
- **Shell injection quoting (specflow Q1)** -- The plan added `sanitize_tmux_name()` for window names but the `claude --resume` argument still has the single-quote injection issue (see Section 6.1).
- **`cs version` subcommand (specflow Gap 25)** -- Not added.
- **Defensive format change detection (specflow recommendation 10)** -- Mentioned in edge cases but no code shown.
- **Async hooks (specflow Q4)** -- Plan specifies timeout but not `"async": true"`. May be intentionally omitted.

---

## 9. Summary of Findings by Severity

### High Severity (fix before implementation)
1. **Shell injection in `claude --resume '<name>'`** -- Session names with single quotes break the command. Use `printf '%q'` or proper escaping. (Section 6.1)

### Medium Severity (fix during implementation)
2. **Variable naming: UPPERCASE in hook scripts** -- Change `INPUT`, `DIR`, `MSG` to lowercase `input`, `dir`, `msg` to match `statusline-command.sh` convention. (Section 2.1)
3. **Hook command paths use `~` instead of absolute paths** -- Use `/Users/adamf/.claude/hooks/...` to match `statusline-command.sh` reference in existing settings. (Section 3.2)
4. **`xargs basename` fragility** -- Replace with two-step extraction for robustness. (Section 6.2)
5. **Interactive `cs restore` diverges from non-interactive CLI pattern** -- Consider requiring a name argument or making "restore all" the default no-arg behavior, rather than introducing interactive selection. (Section 4.3)
6. **Missing `is_interrupt` check in hook code sample** -- Plan text mentions it (line 70) but the code sample does not implement it. (Section 8)
7. **No directory existence check before scanning** -- Add a guard for `~/.claude/projects/<encoded>/` existence. (Section 6.3)

### Low Severity (nice to have)
8. **No header comment block** -- Add a header comment to `cs` for consistency with `bq_cost_measurement.sh`. (Section 1.2)
9. **No `cs version` subcommand** -- Trivial to add, useful for debugging. (Section 4.2)
10. **No `--help` flag** -- Add alongside `help` subcommand. (Section 4.1)
11. **`cs` full name not documented in help output** -- Expand to "cs (claude sessions)" in help text. (Section 5.2)
12. **`osascript` string injection** -- Sanitize notification text before embedding in AppleScript. (Section 6.4)
13. **Consider `"async": true` on notification hooks** -- Fire-and-forget pattern does not need synchronous execution. (Section 3.4)
14. **No configurable projects directory** -- Consider `CLAUDE_PROJECTS_DIR` env var for override. (Section 1.5)

---

## 10. Files Referenced

| File | Role in Analysis |
|---|---|
| `/Users/adamf/Work/Strategy/docs/plans/2026-02-23-feat-claude-session-resume-tmux-plan.md` | The plan under review |
| `/Users/adamf/Work/Strategy/scripts/bq_cost_measurement.sh` | Shell convention baseline |
| `/Users/adamf/.claude/statusline-command.sh` | Hook JSON parsing pattern baseline |
| `/Users/adamf/.claude/settings.json` | Settings config format baseline |
| `/Users/adamf/Work/Strategy/.workflows/plan-research/claude-session-resume/agents/repo-research.md` | Research context (beads CLI patterns, session data format) |
| `/Users/adamf/Work/Strategy/.workflows/plan-research/claude-session-resume/agents/specflow.md` | Gap analysis context (25 gaps, 12 questions) |
| `/Users/adamf/Work/Strategy/.workflows/plan-research/claude-session-resume/agents/learnings.md` | Institutional learnings context |
| `/Users/adamf/.claude/projects/-Users-adamf-Work-Strategy/*.jsonl` | Real session data for format verification |
