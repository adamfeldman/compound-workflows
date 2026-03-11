---
title: "feat: Heuristic audit scope expansion — eliminate $() patterns across full plugin"
type: feat
status: active
date: 2026-03-11
origin: docs/brainstorms/2026-03-11-heuristic-audit-scope-expansion-brainstorm.md
bead: 3l7
---

# Heuristic Audit Scope Expansion

## Summary

Eliminate `$()` shell substitution patterns that trigger permission prompts across the full compound-workflows plugin — commands, skills, and QA tooling. Extends the completed jak v2.4.1 audit (which covered commands only and accepted init-block patterns as exempt) to the full plugin scope.

**Three workstreams:**

1. **Create init-values.sh** — shared script that prints labeled init values. Commands call `bash init-values.sh <cmd> [<stem>]` → no `$()` in Bash tool input → auto-approves universally.
2. **Eliminate remaining patterns** — split-calls, script delegation, direct rewrites, and model-side tracking for P5 complex patterns.
3. **Expand QA Check 5** — broader regex, skills + agents scan scope, backtick detection.

**Scope:** 51 `$()` patterns across 14 files (7 commands, 7 skills), including 3 prose instruction rewrites. All patterns eliminated — zero residuals. Net: 27 exempt markers reduced to 0. (See brainstorm D1: comprehensive fixes, not targeted.)

## Canonical Pattern Inventory

Every `$()` pattern in the plugin, its planned fix, and technique. Patterns grouped by technique.

### init-values.sh candidates (25 listed, 29 after reclassification — patterns 31-33 moved here from split-call, pattern 48 cross-listed)

Common init values shared across commands — replaced by single `bash init-values.sh <cmd> [<stem>]` call.

| # | File | Line | Pattern | Status |
|---|------|------|---------|--------|
| 1 | brainstorm.md | L43 | `PLUGIN_ROOT=$(find ...)` | exempt |
| 2 | brainstorm.md | L44 | `RUN_ID=$(uuidgen \| cut -c1-8)` | exempt |
| 3 | brainstorm.md | L45 | `STATS_FILE="...$(date ...)..."` | exempt |
| 4 | review.md | L42 | `RUN_ID=$(uuidgen ...)` | exempt |
| 5 | review.md | L50 | `PLUGIN_ROOT=$(find ...)` | exempt |
| 6 | plan.md | L100 | `PLUGIN_ROOT=$(find ...)` | exempt |
| 7 | plan.md | L109 | `RUN_ID=$(uuidgen ...)` | exempt |
| 8 | work.md | L63 | `RUN_ID=$(uuidgen ...)` | exempt |
| 9 | work.md | L71 | `PLUGIN_ROOT=$(find ...)` | exempt |
| 10 | work.md | L115 | `WORKTREE_MGR=$(find ...)` | exempt |
| 11 | work.md | L460 | `WORKTREE_MGR=$(find ...)` | exempt |
| 12 | deepen-plan.md | L44 | `PLUGIN_ROOT=$(find ...)` | exempt |
| 13 | deepen-plan.md | L45 | `RUN_ID=$(uuidgen ...)` | exempt |
| 14 | deepen-plan.md | L46 | `STATS_FILE="...$(date ...)..."` | exempt |
| 15 | compact-prep.md | L85 | `VERSION_CHECK=$(find ...)` | exempt |
| 16 | compact-prep.md | L140 | `SNAPSHOT_FILE="...$(date ...)..."` | exempt |
| 17 | compact-prep.md | L141 | `TIMESTAMP="$(date ...)"` | exempt |
| 18 | setup.md | L85 | `VERSION_CHECK=$(find ...)` | exempt |
| 19 | setup.md | L211 | `PLUGIN_ROOT=$(find ...)` | exempt |
| 20 | setup.md | L326 | `PLUGIN_ROOT=$(find ...)` | exempt |
| 21 | plugin-changes-qa/SKILL.md | L21 | `REPO_ROOT="$(git rev-parse ...)"` | non-exempt |
| 22 | plugin-changes-qa/SKILL.md | L24 | `PLUGIN_ROOT=$(find ...)` | non-exempt |
| 23 | classify-stats/SKILL.md | L63 | `REPO_ROOT="$(git rev-parse ...)"` | non-exempt |
| 24 | classify-stats/SKILL.md | L66 | `PLUGIN_ROOT=$(find ...)` | non-exempt |
| 25 | version/SKILL.md | L15 | `VERSION_CHECK=$(find ...)` | non-exempt |

### Command restructure / split-call (15 listed, 12 after reclassification — patterns 31-33 moved to init-values.sh)

Remove `VAR=$(cmd)` wrapper — model calls command directly, reads output, tracks value.

**Split-call auto-approval verification:** Commands without `$()`, backticks, `{"`, or heredocs in tool input auto-approve by default — static rules only suppress heuristic triggers, not enable approval. Each split-call target confirmed trigger-free:

| First token | Example command | Heuristic triggers | Auto-approves? |
|-------------|----------------|-------------------|----------------|
| `shasum` | `shasum -a 256 <path>` | None | Yes |
| `sed` | `sed -n '2s/^# auto-approve v//p' <path>` | None | Yes |
| `jq` | `jq -r '.permissions.allow[]' <path> \| grep -c ...` | None (pipe is not a trigger) | Yes |
| `git` | `git branch --show-current` | None | Yes |
| `ls` | `ls -d .workflows/resolve-pr/...` | None | Yes |
| `cat` | `cat .workflows/.work-in-progress` | None | Yes |

[red-team--opus: split-call auto-approval concern addressed with explicit verification table. Auto-approval depends on absence of heuristic triggers, not presence of static rules. See .workflows/plan-research/heuristic-audit-scope-expansion/red-team--opus.md]

| # | File | Line | Pattern | Status | Notes |
|---|------|------|---------|--------|-------|
| 26 | plan.md | L398 | `PLAN_HASH_BEFORE=$(shasum ...)` | exempt | `shasum -a 256 <path>` — no $() |
| 27 | plan.md | L803 | `PLAN_HASH_AFTER=$(shasum ...)` | exempt | same |
| 28 | setup.md | L353 | `INSTALLED_VERSION=$(sed ...)` | exempt | `sed -n '...' <path>` — no $() |
| 29 | setup.md | L357 | `TEMPLATE_VERSION=$(sed ...)` | exempt | same |
| 30 | setup.md | L497 | `EXACT_COUNT=$(jq ... \| grep ...)` | exempt | pipe chain, no $() |
| 31 | work.md | L88 | `current_branch=$(git branch ...)` | non-exempt | **Moved to init-values.sh** — branch detection absorbed into `work` subcommand [red-team--gemini] |
| 32 | work.md | L89 | `default_branch=$(git symbolic-ref ...)` | non-exempt | same — absorbed into init-values.sh |
| 33 | work.md | L91 | `default_branch=$(git rev-parse ...)` | non-exempt | same — absorbed into init-values.sh |
| 34 | work.md | L456 | `cd $(git worktree list ...)` | non-exempt | split: git worktree list, then cd |
| 35 | resolve-pr-parallel/SKILL.md | L54 | `existing=$(ls ...)` | non-exempt | `ls -d ... \| wc -l` — no $() |
| 36 | git-worktree/SKILL.md | L244 | `cd $(git rev-parse ...)` | non-exempt | split: git rev-parse, then cd |
| 37 | git-worktree/SKILL.md | L267 | `cd $(git rev-parse ...)` | non-exempt | same |
| 38 | file-todos/SKILL.md | L209 | `echo "...: $(ls ... \| wc ...)"` | non-exempt | split: count first, then echo |
| 39 | work.md | L412 | `git commit -m "$(cat <<'EOF'"` | non-exempt | Write msg to file, `git commit -F <file>` |
| 40 | work.md | L427 | `gh pr create --body "$(cat <<'EOF'"` | non-exempt | Write body to file, `gh pr create --body-file <file>` |

### Script delegation (3 patterns)

Multi-line blocks with complex logic → new `check-sentinel.sh` script.

| # | File | Line | Pattern | Status | Notes |
|---|------|------|---------|--------|-------|
| 41 | work.md | L336 | `sentinel_content=$(cat ...)` | non-exempt | 3-line sentinel check block |
| 42 | work.md | L338 | `sentinel_age=$(( $(date ...) - ... ))` | non-exempt | nested $() inside $(()) |
| 43 | work.md | L340 | `echo "...($(( ... ))h old)..."` | non-exempt | diagnostic output |

### Model-side tracking (3 patterns)

Model counts/computes instead of shell — no Bash tool call needed.

| # | File | Line | Pattern | Status | Notes |
|---|------|------|---------|--------|-------|
| 44 | deepen-plan.md | L241 | `AGENT_COUNT=$(echo ... \| jq ...)` | exempt | model tracks dispatch count |
| 45 | deepen-plan.md | L251 | `echo "...$(echo ... \| jq ...)"` | non-exempt | same — use tracked count |
| 46 | resolve-pr-parallel/SKILL.md | L55 | `run_num=$((existing + 1))` | non-exempt | model-side arithmetic |

### Direct rewrite (1 pattern)

Pure parameter expansion — no shell substitution needed.

| # | File | Line | Pattern | Status | Notes |
|---|------|------|---------|--------|-------|
| 47 | recover/SKILL.md | L23 | `SESSION_DIR="...$(echo "$(pwd)" \| tr ...)"` | non-exempt | `${PWD//\//-}` — pure bash |

### init-values.sh (ccusage date argument) (1 pattern)

init-values.sh provides DATE_COMPACT — model uses it directly.

| # | File | Line | Pattern | Status | Notes |
|---|------|------|---------|--------|-------|
| 48 | compact-prep.md | L109 | `ccusage ... --since $(date +%Y%m%d)` | exempt | use DATE_COMPACT from init-values.sh |

Disagree with red team S8 (Opus): inventory completeness concern. Zero backtick substitution patterns exist currently (empirically validated during brainstorm). QA Check 5 expansion (Step 2) adds backtick detection as ongoing safety net. "Indirect generation" (model spontaneously generating `$()`) is inherently unbounded — the prose rewrites (#49-51) cover known cases; QA catches regressions. [red-team--opus, see .workflows/plan-research/heuristic-audit-scope-expansion/red-team--opus.md]

### Prose instruction rewrites (3 patterns)

Backtick-enclosed instructions that cause model to generate `$()` in Bash tool input — rewrite prose to reference init-values.sh output values.

| # | File | Line | Pattern | Status | Notes |
|---|------|------|---------|--------|-------|
| 49 | review.md | L56 | `` `STATS_FILE="...$(date ...)..."` `` | prose | rewrite to "use STATS_FILE from init-values.sh" |
| 50 | plan.md | L114 | `` `STATS_FILE="...$(date ...)..."` `` | prose | same |
| 51 | work.md | L77 | `` `STATS_FILE="...$(date ...)..."` `` | prose | same |

### Summary

| Technique | Patterns | % |
|-----------|----------|---|
| init-values.sh | 29 | 57% |
| Split-call (command restructure) | 12 | 24% |
| Script delegation | 3 | 6% |
| Model-side tracking | 3 | 6% |
| Direct rewrite | 1 | 2% |
| Prose edit | 3 | 6% |
| **Total** | **51** | 100%* |

*Percentages rounded.

**Net exempt marker change:** 27 current → 0. All markers eliminated. No residuals — `/compound:setup` writes Bash rules to `settings.local.json`: Standard profile adds none, Permissive adds `gh`, `bash`, `cat`, etc. but NOT `git`. Neither profile covers both heredoc patterns (`git commit` + `gh pr create`). Patterns formerly considered "static-rule-covered" are migrated to Write tool + `-F`/`--body-file` pattern instead.

## init-values.sh Interface Contract

(See brainstorm D2 and resolved Q1/Q3 for rationale.)

### Arguments

```
bash init-values.sh <command-name> [<stem>]
```

- `<command-name>`: one of `brainstorm`, `plan`, `deepen-plan`, `review`, `work`, `compact-prep`, `setup`, `plugin-changes-qa`, `classify-stats`, `version`
- `<stem>`: optional topic/plan stem for STATS_FILE construction. Required for commands with stats capture. **Sanitized on input:** the script slugifies the stem (`tr -cs 'a-z0-9-' '-' | sed 's/^-//;s/-$//'`) to enforce `[a-z0-9-]` only — strips `/`, spaces, `..`, and shell-significant chars. This is defense-in-depth: model-side derivation already sanitizes, but the script enforces it as a guardrail. [red-team--openai, see .workflows/plan-research/heuristic-audit-scope-expansion/red-team--openai.md]

### Output Format

One `KEY=VALUE` pair per line. Keys are uppercase. No quoting. Model parses by matching line prefix (e.g., "the line starting with `PLUGIN_ROOT=`").

Example output for `bash init-values.sh brainstorm my-topic`:

```
PLUGIN_ROOT=plugins/compound-workflows
RUN_ID=A1B2C3D4
DATE=2026-03-11
STATS_FILE=.workflows/stats/2026-03-11-brainstorm-my-topic.yaml
```

Example for `bash init-values.sh compact-prep`:

```
PLUGIN_ROOT=plugins/compound-workflows
VERSION_CHECK=plugins/compound-workflows/scripts/version-check.sh
DATE=2026-03-11
DATE_COMPACT=20260311
TIMESTAMP=2026-03-11T12:34:56Z
SNAPSHOT_FILE=.workflows/stats/2026-03-11-ccusage-snapshot.yaml
```

Example for `bash init-values.sh work` (no stem — script auto-detects from branch):

```
PLUGIN_ROOT=plugins/compound-workflows
RUN_ID=E5F6G7H8
DATE=2026-03-11
STEM=my-feature
STATS_FILE=.workflows/stats/2026-03-11-work-my-feature.yaml
WORKTREE_MGR=plugins/compound-workflows/skills/git-worktree/scripts/worktree-manager.sh
```

For `work`, the stem argument is optional. If omitted, init-values.sh auto-detects by running `git branch --show-current` internally; if empty (detached HEAD), falls back to `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'`; if that also fails, `git rev-parse --verify origin/main >/dev/null 2>&1 && echo main || echo master`. The branch name is slugified and output as `STEM=<value>`. This eliminates the 3-step model-side fallback chain — all branch detection logic lives in the script. [red-team--gemini, see .workflows/plan-research/heuristic-audit-scope-expansion/red-team--gemini.md]

### Per-Command Output

| Command | Values |
|---------|--------|
| brainstorm, plan, deepen-plan, review | PLUGIN_ROOT, RUN_ID, DATE, STATS_FILE |
| work | PLUGIN_ROOT, RUN_ID, DATE, STEM, STATS_FILE, WORKTREE_MGR (STEM auto-detected from branch if not passed) |
| compact-prep | PLUGIN_ROOT, VERSION_CHECK, DATE, DATE_COMPACT, TIMESTAMP, SNAPSHOT_FILE |
| setup | PLUGIN_ROOT, VERSION_CHECK |
| plugin-changes-qa, classify-stats | REPO_ROOT, PLUGIN_ROOT |
| version | VERSION_CHECK |

### Bootstrap

Two-phase path resolution (see brainstorm C1 resolution):

1. Try local path: `bash plugins/compound-workflows/scripts/init-values.sh <cmd> [<stem>]`
2. If local path doesn't exist (installed plugin): `find ~/.claude/plugins -name "init-values.sh" -path "*/compound-workflows/*" | head -1` — also no `$()` in tool input. (Disagree with red team S7: `find | head -1` is a pre-existing pattern, not introduced by this plan. Claude Code installs one plugin version per name — multiple versions don't coexist. [red-team--openai])

Model tries the local path first. If it fails (exit code non-zero or "not found"), model runs the find fallback and uses the discovered path.

### Skill Bootstrap

Skills loaded from `~/.claude/plugins/` cannot use the local path `plugins/compound-workflows/scripts/init-values.sh`. Skills use the same two-phase resolution as commands but with different paths:

Skills use the same local-path-first + find fallback as commands. Claude Code's Bash tool executes in the project root (repo root), not the skill file's directory — so relative paths like `../../scripts/init-values.sh` resolve incorrectly.

1. Try local path: `bash plugins/compound-workflows/scripts/init-values.sh <skill-name>`
2. Fallback: `find ~/.claude/plugins -name "init-values.sh" -path "*/compound-workflows/*" | head -1`, then `bash <found-path> <skill-name>`

Skill instructions should say: "Run `bash plugins/compound-workflows/scripts/init-values.sh <skill-name>`. If the script is not found (not in source repo), run the find fallback."

[red-team--opus: relative path approach replaced — cwd is repo root, not skill directory. See .workflows/plan-research/heuristic-audit-scope-expansion/red-team--opus.md]

### Error Handling

- init-values.sh prints errors to stderr and exits non-zero on failure.
- Command instructions include: "If init-values.sh fails or any value is empty, warn the user and stop — do not proceed with empty variables."
- No fallback to inline `$()` — that defeats the purpose.
- **Re-run for long sessions:** init-values.sh is idempotent and cheap. If a command runs many steps after init and values are needed late in the session, the instruction may say "re-run init-values.sh to refresh values" rather than relying on model memory across 50+ tool calls. This is not a regression — current inline `VAR=$(...)` also requires model tracking (shell variables don't persist across separate Bash tool calls). [red-team--opus, see .workflows/plan-research/heuristic-audit-scope-expansion/red-team--opus.md]

### Why This Works

`bash init-values.sh brainstorm my-topic` contains NO `$()` in the Bash tool input. The `$()` stays inside the script file, invisible to Claude Code's heuristic inspection. Auto-approves universally without static rules, hooks, or setup. (See `docs/solutions/claude-code-internals/2026-03-11-script-file-shell-substitution-bypass.md`.)

Disagree with red team C4 (OpenAI CRITICAL, Gemini MINOR): "security model bypass by design." This is standard practice — `bash script.sh` is the intended auto-approve pattern; the heuristic targets dangerous user-composed commands, not all shell execution. The fragility risk (Claude Code could inspect script contents in future) is documented in brainstorm Q10. A formal threat model / risk envelope for the permissions architecture is tracked separately (bead go4) — broader than this plan's scope. [red-team--openai, red-team--gemini, see .workflows/plan-research/heuristic-audit-scope-expansion/red-team--openai.md]

## Implementation Steps

### Step 1: Create init-values.sh and check-sentinel.sh

**Files created:**
- [ ] `plugins/compound-workflows/scripts/init-values.sh`
- [ ] `plugins/compound-workflows/scripts/check-sentinel.sh`

**init-values.sh implementation:**
- Case statement keyed by `$1` (command name)
- PLUGIN_ROOT: `PLUGIN_ROOT=$(cd "$(dirname "$0")/.." && pwd)` (scripts/ is one level below plugin root), with find fallback if dirname fails
- REPO_ROOT: `$(git rev-parse --show-toplevel 2>/dev/null || pwd)`
- RUN_ID: `$(uuidgen | cut -c1-8)`
- DATE: `$(date +%Y-%m-%d)`, DATE_COMPACT: `$(date +%Y%m%d)`, TIMESTAMP: `$(date -u +%Y-%m-%dT%H:%M:%SZ)` (ISO-8601 UTC)
- STATS_FILE: `".workflows/stats/${DATE}-${CMD}-${STEM}.yaml"` (requires stem arg)
- SNAPSHOT_FILE: `".workflows/stats/${DATE}-ccusage-snapshot.yaml"` (compact-prep only, no stem)
- VERSION_CHECK: derived from `$PLUGIN_ROOT/scripts/version-check.sh` with find fallback
- WORKTREE_MGR: derived from `$PLUGIN_ROOT/skills/git-worktree/scripts/worktree-manager.sh`
- Exit non-zero with stderr message if PLUGIN_ROOT is empty

**check-sentinel.sh implementation:** *(Disagree with red team Opus finding 4: Opus suggested split-call + model-side arithmetic as a lighter alternative. User: the whole point is to reduce work by the model — a dedicated script offloads age computation to deterministic bash, which is the plan's design philosophy. The maintenance surface (one small script) is acceptable.)*
- Reads `.workflows/.work-in-progress`, computes age vs current time, prints result
- Staleness threshold: 14400 seconds (4 hours) — matches current work.md L339 logic (`if [ "$sentinel_age" -ge 14400 ]`)
- Replaces work.md L336-340 (sentinel_content + sentinel_age + echo diagnostic)
- Usage: `bash check-sentinel.sh` → prints `STALE:<hours>` or `ACTIVE` or `NOT_FOUND` or `CLEARED` (if content is non-numeric/already cleared)
- The sentinel file contains a Unix timestamp written by work.md at session start

**Verification:**
- [ ] `bash plugins/compound-workflows/scripts/init-values.sh brainstorm test-stem` outputs valid KEY=VALUE pairs
- [ ] `bash plugins/compound-workflows/scripts/init-values.sh compact-prep` outputs VERSION_CHECK, DATE_COMPACT, etc.
- [ ] `bash plugins/compound-workflows/scripts/init-values.sh work test-stem` outputs WORKTREE_MGR
- [ ] Script auto-approves without any static rule (no `$()` in tool input)
- [ ] check-sentinel.sh outputs correct status
- [ ] **Script hardening:** Both scripts include `#!/usr/bin/env bash` shebang, pass `shellcheck` with zero warnings, and are NOT marked executable (invoked via `bash script.sh`, not `./script.sh` — consistent with existing plugin scripts). Add negative tests: init-values.sh with invalid subcommand exits non-zero, check-sentinel.sh with missing sentinel file prints `NOT_FOUND`. [red-team--openai, see .workflows/plan-research/heuristic-audit-scope-expansion/red-team--openai.md]
- [ ] **Output format validation:** init-values.sh self-validates its own output before printing — DATE matches `^[0-9]{4}-[0-9]{2}-[0-9]{2}$`, RUN_ID is exactly 8 hex chars, PLUGIN_ROOT is a non-empty directory path that exists, STATS_FILE ends in `.yaml`. On validation failure, print error to stderr and exit non-zero. This catches silent corruption (e.g., BSD vs GNU date format differences, uuidgen case differences) before values propagate to 10+ consumers. [red-team--opus, see .workflows/plan-research/heuristic-audit-scope-expansion/red-team--opus.md]

### Step 2: Expand QA Check 5

**File modified:** `plugins/compound-workflows/scripts/plugin-qa/context-lean-grep.sh` (lines 170-192)

Changes:
- [ ] **Regex expansion:** Change from `^\s*[A-Z_]+=.*\$\(` to `\$\(` matching any position on any line. This catches lowercase vars, non-assignment patterns, `$(())` arithmetic, and `cd $(...)` patterns.
- [ ] **Scope expansion:** Add scan loops for `$plugin_root/skills/*/SKILL.md` and `$plugin_root/agents/**/*.md`
- [ ] **Path exclusion:** Skip files matching `*/references/*` (illustrative code in reference docs)
- [ ] **Suppress markers:** Skip lines containing `heuristic-exempt` or `context-lean-exempt` (existing behavior, verify it still works)
- [ ] **Backtick detection:** Add secondary regex targeting backtick *substitution* in assignment context: `` [A-Za-z_]+=`[^`]+` `` (variable assignment using backtick substitution). This avoids false positives from Markdown inline code formatting. Apply globally (no code-fence scoping) — the narrowed assignment-context regex is specific enough that prose false positives are unlikely. Any rare false positive gets `# heuristic-exempt`. This is a best-effort secondary check — the primary `\$\(` regex catches the vast majority of patterns.

**False positive rationale (red team C2):** The `\$\(` regex scans only instruction files (`commands/*.md`, `skills/*/SKILL.md`, `agents/**/*.md`) — not all markdown. Every `$()` in an instruction file is model-executed (these are prompts, not documentation). Empirically validated: 25 real hits, zero false positives. Agents confirmed zero `$()` currently. Path exclusion (`*/references/*`) handles illustrative code. Any future false positives are handled by the existing `# heuristic-exempt` marker mechanism. Bash code fence scoping was considered but rejected — instruction-file `$()` in prose is equally valid (prose instructs the model to generate `$()` in Bash tool input). [red-team--gemini, red-team--openai, red-team--opus, see .workflows/plan-research/heuristic-audit-scope-expansion/red-team--gemini.md]
- [ ] **Finding message update:** Change from "VAR=$() pattern" to "$() pattern" (broader scope)

**Expected baseline after expansion (before migration):** ~48 findings across commands and skills (matching the canonical inventory minus prose patterns which aren't in code blocks). This serves as the TODO list for Steps 3-4.

### Step 3: Migrate command files

For each command file, replace the init block with `bash init-values.sh <cmd> [<stem>]` and handle P5 patterns.

**Instruction pattern for all migrated commands:**

Replace the current init block (3-5 `VAR=$(...)` lines) with:

```bash
bash plugins/compound-workflows/scripts/init-values.sh <cmd> <stem>
```

Then add: "Read the output. Track the values PLUGIN_ROOT, RUN_ID, DATE, STATS_FILE (and others per command) for use in subsequent steps. If init-values.sh fails or any value is empty, warn the user and stop."

Remove `# heuristic-exempt` markers from all replaced lines. Remove the prose `STATS_FILE="...$(date ...)..."` backtick instructions and replace with "Use the STATS_FILE value from init-values.sh output."

#### 3a: brainstorm.md
- [ ] Replace L43-45 init block (3 exempt patterns → init-values.sh)
- [ ] Remove 3 `# heuristic-exempt` markers

#### 3b: plan.md
- [ ] Replace L100, L109 init block (2 exempt patterns → init-values.sh)
- [ ] Rewrite L114 prose instruction (STATS_FILE)
- [ ] Rewrite L398 PLAN_HASH_BEFORE: instruction says "call `shasum -a 256 <path>` and read the hash from the output" (split-call, no $())
- [ ] Rewrite L803 PLAN_HASH_AFTER: same pattern
- [ ] Remove 4 `# heuristic-exempt` markers

#### 3c: review.md
- [ ] Replace L42, L50 init block (2 exempt patterns → init-values.sh)
- [ ] Rewrite L56 prose instruction (STATS_FILE)
- [ ] Remove 2 `# heuristic-exempt` markers

#### 3d: work.md
- [ ] Replace L63, L71 init block (2 exempt patterns → init-values.sh, includes WORKTREE_MGR)
- [ ] Remove L115, L460 WORKTREE_MGR find (covered by init-values.sh work output)
- [ ] Rewrite L77 prose instruction (STATS_FILE)
- [ ] Rewrite L88-91 branch detection: remove entirely — init-values.sh `work` subcommand auto-detects branch and outputs `STEM=<value>`. Instruction says: "Call `bash init-values.sh work` (no stem argument). Read the STEM value from the output. The script handles branch detection internally." This eliminates 3 split-call patterns (#31-33). [red-team--gemini]
- [ ] Rewrite L336-340 sentinel check: replace with `bash check-sentinel.sh` — model reads output (`STALE:<hours>`, `ACTIVE`, `NOT_FOUND`, or `CLEARED`), acts accordingly
- [ ] Rewrite L456 worktree cd as split-call: "Run `git worktree list --porcelain | head -1 | sed 's/worktree //'` and read the output as the worktree root path. Then run `cd <path>`."
- [ ] Rewrite L412 git commit heredoc: use Write tool to write commit message to `.workflows/tmp/commit-msg-<RUN_ID>.txt` (model uses tracked RUN_ID value — Write tool creates `.workflows/tmp/` automatically), then `git commit -F .workflows/tmp/commit-msg-<RUN_ID>.txt`. No cleanup needed — file is tiny, gitignored, and RUN_ID ensures no collision across parallel sessions. (No `$()` in tool input — `git` first token, no heredoc substitution.) [red-team--gemini, see .workflows/plan-research/heuristic-audit-scope-expansion/red-team--gemini.md]
- [ ] Rewrite L427 gh pr create heredoc: use Write tool to write PR body to `.workflows/tmp/pr-body-<RUN_ID>.txt`, then `gh pr create --body-file .workflows/tmp/pr-body-<RUN_ID>.txt`. Same pattern — RUN_ID-namespaced, no cleanup. [red-team--gemini]
- [ ] Remove 4 `# heuristic-exempt` markers

#### 3e: deepen-plan.md
- [ ] Replace L44-46 init block (3 exempt patterns → init-values.sh)
- [ ] Rewrite L241 AGENT_COUNT: model tracks dispatch count directly — remove the jq call. Instruction says "track the agent dispatch count as you go; use that count here." (model-side tracking, no Bash call)
- [ ] Rewrite L251 echo with AGENT_COUNT: same — use model-tracked count
- [ ] Remove 4 `# heuristic-exempt` markers

#### 3f: compact-prep.md
- [ ] Replace L85, L140-141 init block (3 exempt patterns → init-values.sh compact-prep)
- [ ] Rewrite L109 ccusage date arg: "use DATE_COMPACT from init-values.sh output: `ccusage daily --json --breakdown --since <DATE_COMPACT> --offline 2>/dev/null`" (no $() in tool input)
- [ ] Remove 4 `# heuristic-exempt` markers

#### 3g: setup.md
- [ ] Replace L85, L211, L326 init patterns (3 exempt → init-values.sh setup)
- [ ] Rewrite L353-357 version extraction as split-call. Replacement instruction: "Run `sed -n '2s/^# auto-approve v//p' .claude/hooks/auto-approve.sh` and read the output as INSTALLED_VERSION. Run `sed -n '2s/^# auto-approve v//p' <HOOK_TEMPLATE path>` and read the output as TEMPLATE_VERSION." (No `$()` — `sed` first token.)
- [ ] Rewrite L497 exact count as split-call. Replacement instruction: "Run `jq -r '.permissions.allow[]? // empty' .claude/settings.local.json 2>/dev/null | grep -c -v '[:*?\[\{]' || echo '0'` and read the output as EXACT_COUNT." (No `$()` — `jq` first token.)
- [ ] Remove 6 `# heuristic-exempt` markers

### Step 4: Migrate skill files

#### 4a: plugin-changes-qa/SKILL.md
- [ ] Replace L21, L24 init block → init-values.sh plugin-changes-qa (outputs REPO_ROOT, PLUGIN_ROOT)
- [ ] 2 patterns eliminated

#### 4b: classify-stats/SKILL.md
- [ ] Replace L63, L66 init block → init-values.sh classify-stats
- [ ] 2 patterns eliminated

#### 4c: version/SKILL.md
- [ ] Replace L15 VERSION_CHECK find → init-values.sh version
- [ ] 1 pattern eliminated

#### 4d: recover/SKILL.md
- [ ] Rewrite L23: `SESSION_DIR="$HOME/.claude/projects/${PWD//\//-}"` (pure parameter expansion, no $())
- [ ] 1 pattern eliminated (direct rewrite)

#### 4e: resolve-pr-parallel/SKILL.md
- [ ] Rewrite L54 as split-call. PR_NUMBER is a model-tracked variable from earlier in the skill flow. Replacement instruction: "Using the PR number from the earlier step, run `ls -d .workflows/resolve-pr/<PR_NUMBER>/agents/run-* 2>/dev/null | wc -l | tr -d ' '` and read the output as the existing run count."
- [ ] Rewrite L55: model-side arithmetic — "add 1 to the count from the previous call"
- [ ] 2 patterns eliminated

#### 4f: git-worktree/SKILL.md
- [ ] Rewrite L244, L267: split-call — "call `git rev-parse --show-toplevel`, read the path, then `cd <path>`"
- [ ] 2 patterns eliminated

#### 4g: file-todos/SKILL.md
- [ ] Rewrite L209 as split-call. Replacement instruction: "Run `ls -1 todos/*-<status>-*.md 2>/dev/null | wc -l` and read the count. Then use the count in the status output." (No `$()` — `ls` first token.)
- [ ] 1 pattern eliminated

### Step 5: Verify + version bump

- [ ] Run expanded QA Check 5 — **target: zero findings**
- [ ] Verify zero `# heuristic-exempt` markers remain (all patterns migrated, no residuals)
- [ ] Verify init-values.sh auto-approves by running: `bash plugins/compound-workflows/scripts/init-values.sh brainstorm test` — should produce output with no permission prompt
- [ ] Run full Tier 1 QA (`bash plugins/compound-workflows/scripts/plugin-qa/*.sh` via `/compound-workflows:plugin-changes-qa`)
- [ ] Update file counts in CLAUDE.md (scripts section — add init-values.sh, check-sentinel.sh)
- [ ] Update CHANGELOG.md
- [ ] Bump version in plugin.json + marketplace.json
- [ ] Update README.md if script count changed

## Parallelization Notes

For `/compound:work` dispatch:

- **Steps 1 and 2 have no dependency on each other** — they touch different files (scripts vs QA). They CAN run in parallel, but the recommended grouping below bundles them into one agent for simplicity. [Clarified per red-team--openai finding 6, see .workflows/plan-research/heuristic-audit-scope-expansion/red-team--openai.md]
- **Steps 3a-3g can run in parallel** — each touches a different command file. However, all depend on Step 1 (init-values.sh must exist). Recommended: run 2-3 command files per agent dispatch to avoid file collision.
- **Steps 4a-4g can run in parallel** — same logic as Step 3. Depend on Step 1.
- **Step 5 must run after all others** — validation pass

**Recommended dispatch grouping:**
1. **Batch 1 — Agent A: Steps 1 + 2** (foundation — scripts + QA expansion)
2. **GATE: Verify Agent A complete** before dispatching Batch 2. The work executor must confirm init-values.sh exists and produces valid output (`bash plugins/compound-workflows/scripts/init-values.sh brainstorm test-stem` returns KEY=VALUE pairs) before any migration agents start. Without this gate, migration agents reference a script that doesn't exist yet. [red-team--opus, see .workflows/plan-research/heuristic-audit-scope-expansion/red-team--opus.md]
3. **Batch 2 — Agents B + C + D in parallel:**
   - Agent B: Steps 3a + 3b + 3c (brainstorm, plan, review — simpler commands)
   - Agent C: Steps 3d + 3e + 3f + 3g (work, deepen-plan, compact-prep, setup — complex commands)
   - Agent D: Steps 4a-4g (all skills — smaller, uniform changes)
4. **Batch 3 — Agent E: Step 5** (verification — depends on B, C, D)

## Acceptance Criteria

1. QA Check 5 reports zero findings across commands, skills, and agents
2. `init-values.sh` exists at `scripts/init-values.sh` and auto-approves in both source repo and installed plugin contexts
3. All 7 command files use `init-values.sh` for init values (no inline `VAR=$(...)` for PLUGIN_ROOT, RUN_ID, DATE, STATS_FILE)
4. All 7 skill files have `$()` patterns eliminated
5. Net exempt marker count: 0 (all patterns migrated)
6. `check-sentinel.sh` replaces inline sentinel logic in work.md
7. QA Check 5 scans commands + skills + agents with expanded regex
8. CHANGELOG and version bump reflect all changes
9. Full Tier 1 + Tier 2 QA passes with zero findings

## Open Questions

### Resolved

**Q2 (from brainstorm): Script inventory** — Resolved during planning. Two new scripts needed: `init-values.sh` (shared init, replaces 26 patterns across 12 files) and `check-sentinel.sh` (sentinel stale detection, replaces 3-line block in work.md). All other P5 patterns use split-calls (15 patterns) or model-side tracking (3 patterns) — no additional scripts required.

**Backtick detection specifics (from specflow G8)** — Backtick shell substitution (`` `cmd` ``) in Markdown files is overloaded with inline code formatting. Use a simple heuristic regex that flags backtick pairs with command-like content. Accept that some edge cases may need `# heuristic-exempt`. This is a secondary detection mechanism — the primary `\$\(` regex catches the vast majority of patterns.

**QA expansion sequencing (from specflow G9)** — Expand QA first (Step 2), then migrate patterns (Steps 3-4). QA findings serve as the TODO list. During `/compound:work`, the `.work-in-progress` sentinel suppresses PostToolUse hook QA, so intermediate findings don't interrupt work.

**deepen-plan jq pattern (from specflow G6)** — Model-side tracking chosen over pipe-through-script (specflow option d). Rationale: the model already tracks the dispatch count as it runs the pipeline, making the jq query redundant. The `AGENT_COUNT=$(echo "$VALIDATED" | jq ...)` pattern is replaced by the model using its own tracked count — no Bash call needed. Pipe-through-script would have worked (no `$()` in tool input) but adds unnecessary complexity when the model already has the value. (See brainstorm D2: model-side tracking is one of the elimination techniques.)

**Static rule verification for residuals (from specflow G7/Q3)** — Resolved by eliminating residuals entirely. `/compound:setup` writes Bash rules to `settings.local.json` (not `settings.json`): Standard profile adds zero rules, Permissive profile adds `Bash(gh:*)`, `Bash(bash:*)`, `Bash(cat:*)`, etc. but NOT `Bash(git:*)`. Therefore: `git commit -m "$(cat <<'EOF'"` prompts for ALL users (no profile covers it). `gh pr create --body "$(cat <<'EOF'"` prompts for Standard users (only Permissive has `Bash(gh:*)`). Fix: migrate both — use Write tool for message/body content, then `git commit -F <file>` / `gh pr create --body-file <file>`. Zero residuals.

**Skill bootstrap (from specflow G4)** — Resolved by adding a "Skill Bootstrap" subsection to the init-values.sh Interface Contract. Skills use the same local-path-first + find fallback as commands (`bash plugins/compound-workflows/scripts/init-values.sh <skill-name>`). Relative paths like `../../scripts/init-values.sh` don't work because Claude Code's Bash tool executes in the project root, not the skill directory.

## Red Team MINOR Triage

**Fixed (batch):** 1 MINOR red team fix applied (stale skill bootstrap reference in Open Questions Resolved). [see .workflows/plan-research/heuristic-audit-scope-expansion/minor-triage-redteam.md]

**Valid (individual):** 3 MINOR red team findings addressed:
- check-sentinel.sh overengineering concern — Disagree: the whole point is to reduce work by the model; dedicated script offloads computation to deterministic bash. [red-team--opus, see .workflows/plan-research/heuristic-audit-scope-expansion/red-team--opus.md]
- Missing script hardening steps — Valid: added shellcheck, shebang, and negative test requirements to Step 1 verification. [red-team--openai, see .workflows/plan-research/heuristic-audit-scope-expansion/red-team--openai.md]
- Sequencing description ambiguity — Valid: clarified parallelization notes phrasing. [red-team--openai, see .workflows/plan-research/heuristic-audit-scope-expansion/red-team--openai.md]

**Acknowledged (batch):** 4 MINOR red team findings, no action needed. [see .workflows/plan-research/heuristic-audit-scope-expansion/minor-triage-redteam.md]

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-03-11-heuristic-audit-scope-expansion-brainstorm.md` — Key decisions carried forward: full scope (brainstorm D1), three techniques (brainstorm D2), eliminate prompts + document residuals (brainstorm D3, updated during planning: zero residuals), QA expansion (brainstorm D4).
- **Script-file bypass solution:** `docs/solutions/claude-code-internals/2026-03-11-script-file-shell-substitution-bypass.md` — Grounds init-values.sh approach: `$()` inside scripts is invisible to heuristic.
- **Static rules solution:** `docs/solutions/claude-code-internals/2026-03-10-static-rules-suppress-bash-heuristics.md` — Explains why VAR=$() can't be fixed with settings rules.
- **QA script patterns:** `docs/solutions/qa-infrastructure/2026-03-08-bash-qa-script-patterns.md` — Process substitution and path-filter patterns for Check 5 expansion.
- **Research files:** `.workflows/plan-research/heuristic-audit-scope-expansion/agents/` (repo-research.md, learnings.md, specflow.md)
