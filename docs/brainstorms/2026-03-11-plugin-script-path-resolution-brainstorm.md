---
date: 2026-03-11
topic: plugin-script-path-resolution
status: draft
participants: [adam, claude]
origin_bead: jgb8
related_beads: [ixz4]
---

# Plugin Script Path Resolution

## What We're Building

A reliable path resolution architecture for plugin scripts that works from any CWD — not just the source repo. This involves migrating the 8 core workflow commands from `commands/compound/` to `skills/` directories, leveraging `${CLAUDE_SKILL_DIR}` (Claude Code v2.1.69+), and renaming the namespace from `compound:` to `do:`.

## Why This Approach

### The Problem

Plugin path resolution was never designed — it grew organically:

1. **Commands** use `bash plugins/compound-workflows/scripts/init-values.sh` — a hardcoded path relative to the source repo CWD. Works for the developer, breaks for any installed user.
2. **3 skills** (version, plugin-changes-qa, classify-stats) use the same hardcoded path with a `find ~/.claude/plugins` fallback — the only files that handle the installed case.
3. **2 skills** (git-worktree, resolve-pr-parallel) use `${CLAUDE_PLUGIN_ROOT}` — which doesn't work in markdown content (upstream bug, see below).
4. **8 commands** have no fallback at all.

The bug surfaced when a hook triggered the version skill from an installed context. The model tried to construct a relative path from the cached skill location, miscounted directory levels (3 `..` instead of 2), and failed.

### Upstream Reality

- **`${CLAUDE_PLUGIN_ROOT}` is broken in markdown** — [GitHub #9354](https://github.com/anthropics/claude-code/issues/9354), open since Oct 2025, 20 comments, no Anthropic response or timeline. Only works in JSON configs (hooks, MCP servers), not in command or skill markdown.
- **`${CLAUDE_SKILL_DIR}` works in skills** — shipped in v2.1.69 (March 5, 2026). Load-time string substitution, always-correct absolute path. **Empirically confirmed** in this session.
- **`${CLAUDE_SKILL_DIR}` does NOT work in commands** — **empirically confirmed** in this session. The literal string passes through unsubstituted.
- **Bash injection (`!`command``)** does not work in plugin skills — **empirically confirmed**.
- **`${CLAUDE_SESSION_ID}`** works in both skills and commands.
- Related issues: [#24529](https://github.com/anthropics/claude-code/issues/24529) (hook executor doesn't export env var), [#11011](https://github.com/anthropics/claude-code/issues/11011) (skill scripts fail on first execution with relative paths), [#12541](https://github.com/anthropics/claude-code/issues/12541) (feature request for built-in env vars).

### Why Commands → Skills

The [upstream compound-engineering plugin](https://github.com/EveryInc/compound-engineering-plugin) already moved all core workflows (`ce:brainstorm`, `ce:plan`, `ce:work`, `ce:review`, `ce:compound`) to skills. They have no `scripts/` directory and no path resolution problem.

Our plugin differs — we have shared scripts (`init-values.sh`, `capture-stats.sh`, `validate-stats.sh`, etc.) that exist to avoid `$()` permission prompt heuristics. These scripts are important. But by making the workflows skills instead of commands, `${CLAUDE_SKILL_DIR}` becomes available for resolving paths to these shared scripts.

**Empirical evidence table:**

| Mechanism | Skills | Commands |
|-----------|--------|----------|
| `${CLAUDE_SKILL_DIR}` | **Substituted** (absolute path) | **NOT substituted** (literal string) |
| `${CLAUDE_SESSION_ID}` | Substituted | Substituted |
| `!`command`` injection | Does NOT work | Not tested (likely same) |
| `find` fallback | Works (model interprets instruction) | Works (model interprets instruction) |

## Key Decisions

### D1: Migrate commands to skills

Move all 8 commands from `commands/compound/` to `skills/do-*/SKILL.md` directories.

**Rationale:** `${CLAUDE_SKILL_DIR}` is the only upstream-supported, load-time path resolution mechanism that works in markdown content. It's only available in skills, not commands. Upstream already made this move. This also removes the 8-command-per-directory limit we're currently hitting.

### D2: Use `${CLAUDE_SKILL_DIR}/../../scripts/` with upward-walk fallback

Skills at `skills/do-brainstorm/SKILL.md` are 2 directory levels below the plugin root. `${CLAUDE_SKILL_DIR}/../../scripts/init-values.sh` resolves to `<plugin-root>/scripts/init-values.sh` at load time.

**Fast path:** `../../` from skill dir (works when depth is standard).
**Fallback:** If `plugin.json` not found at the expected depth, init-values.sh walks upward from its invocation path until it finds `.claude-plugin/plugin.json`. This handles cases where the directory depth changes.

**Rationale:** Red team (all three providers) flagged the hardcoded depth as fragile. The upward-walk fallback provides recovery without sacrificing the fast path's simplicity.

### D3: Rename namespace from `compound:` to `do:`

Skills get `name: do:brainstorm`, `name: do:plan`, etc. Full invocation: `/compound-workflows:do:brainstorm`. Short form: `/do:brainstorm`.

**Rationale:** `do:` reads as natural English ("do brainstorm", "do plan", "do work"). Shorter than `compound:` (2 chars vs 8). Upstream uses `ce:` — `do:` differentiates while being more intuitive. This is a breaking change, bundled with the structural migration to make it one transition.

### D4: Setup gets `disable-model-invocation: true`, all others stay model-invocable

Only `do:setup` gets `disable-model-invocation: true` (writes config files, side effects). All other workflow skills remain model-invocable for conversational triggering ("brainstorm X" → model invokes skill).

**Rationale:** Red team flagged accidental invocation risk for heavyweight workflows. Setup is the only skill with irreversible side effects (config writes). Others benefit from conversational invocation. Upstream doesn't disable any of theirs.

### D5: Migrate existing skills to `${CLAUDE_SKILL_DIR}`

The 5 existing skills that reference scripts also get updated:
- **version, plugin-changes-qa, classify-stats:** Replace `bash plugins/compound-workflows/scripts/init-values.sh` + `find` fallback with `bash ${CLAUDE_SKILL_DIR}/../../scripts/init-values.sh`
- **git-worktree:** Replace broken `${CLAUDE_PLUGIN_ROOT}` with `${CLAUDE_SKILL_DIR}/scripts/worktree-manager.sh`
- **resolve-pr-parallel:** Replace broken `${CLAUDE_PLUGIN_ROOT}` with `${CLAUDE_SKILL_DIR}/scripts/<script>`

### D6: Directory naming convention

Skill directories use hyphenated names matching the colon-separated skill name: `do-brainstorm/` for `name: do:brainstorm`, `do-compact-prep/` for `name: do:compact-prep`. Matches upstream convention (`ce-work/` for `name: ce:work`).

## Resolved Questions

### RQ1: Namespace verification

Does `name: do:brainstorm` in `skills/do-brainstorm/SKILL.md` produce the expected `/compound-workflows:do:brainstorm` invocation path?

**Yes — empirically confirmed.** Created `skills/do-test/SKILL.md` with `name: do:test`. Autocomplete showed `/do:test` with the colon preserved. Full path: `/compound-workflows:do:test`. The `name:` field controls the namespace, the directory name (`do-test`) is just the folder.

### RQ2: Backwards compatibility

**Decision: Thin aliases for one version.** Keep `commands/compound/` with one-liner files that tell the model to invoke the corresponding `/do:*` skill. Remove the aliases in the following version. This gives users one release cycle to update muscle memory and any docs/memory that reference `/compound:*`.

### RQ3: `${CLAUDE_SKILL_DIR}/../../` depth assumption

**Decision: Validate + document.** Add a validation check in init-values.sh: after computing PLUGIN_ROOT from the path, verify it contains `.claude-plugin/plugin.json`. Fail loudly if not — this catches cases where the directory depth assumption breaks. Also document the assumption in CLAUDE.md so future contributors know the constraint.

**Rationale for not just accepting the risk:** The depth is defined by the Agent Skills spec, so it's unlikely to change. But init-values.sh already validates PLUGIN_ROOT is a directory — adding one more check (plugin.json exists) is trivial and provides a clear error instead of silent misbehavior.

## Scope

### In scope

- Migrate 8 commands → 8 skills (`do:*` namespace)
- Keep thin command aliases in `commands/compound/` for one version (backwards compat)
- Update 5 existing skills to use `${CLAUDE_SKILL_DIR}`
- Add PLUGIN_ROOT validation in init-values.sh (check for `.claude-plugin/plugin.json`)
- Document `${CLAUDE_SKILL_DIR}/../../` depth assumption in CLAUDE.md
- Update plugin.json, marketplace.json, CLAUDE.md, QA scripts
- Version bump (major — v3.0.0, breaking namespace change)
- CHANGELOG documentation

### Out of scope

- Eliminating shared scripts (they serve the `$()` avoidance purpose)
- Changes to init-values.sh internal logic (it works fine once found)
- Upstream Claude Code fixes (we can't control their timeline)
- Converting utility/reference skills to use `do:` prefix (only core workflows get it)

## Red Team Resolution Summary

Red team challenge completed 2026-03-11. Three providers (Gemini, OpenAI, Claude Opus). 4 CRITICAL, 8 SERIOUS, 8 MINOR findings across all three. Deduplicated to unique findings below.

### CRITICAL — Resolved

**C1: `find` fallback is the obvious simpler fix, never evaluated** (all three providers)
**Valid — noted, disagree on conclusion.** The `find` fallback solves the immediate path resolution bug, but the migration solves multiple additional problems: 8-command limit, upstream architecture alignment, supporting files in skill directories, `${CLAUDE_SKILL_DIR}` as upstream-supported mechanism. The migration is worth the cost. User's reasoning: "I have a real user now" and the migration future-proofs the architecture.

**C2: Migration may be over-engineering / architectural abuse** (Opus, Gemini)
**Valid concern — accepted the tradeoff.** The original bug IS a prompt clarity issue. But the underlying architecture (commands can't resolve their own paths) is real. The `find` fallback is a workaround for a missing platform feature. The migration aligns with upstream and gives us `${CLAUDE_SKILL_DIR}` as a load-time guarantee.

**C3: `../../` depth assumption fragile** (all three)
**Valid — updated design.** Changed to: `../../` as fast path, upward walk (to `plugin.json`) as fallback in init-values.sh. Best of both: fast when depth is correct, recoverable when it's not.

**C4: Semver contradiction** (OpenAI)
**Valid — fixed.** Breaking namespace change = major version bump. v3.0.0, not minor.

### SERIOUS — Resolved

**S1: `do:` namespace collision risk** (Gemini)
**Disagree — keeping `do:`.** Plugin namespacing (`compound-workflows:do:*`) already provides uniqueness. Collision only matters for the short form `/do:*`, which is project-local. Acceptable risk.

**S2: Accidental model invocation of heavyweight workflows** (Opus, Gemini, OpenAI)
**Partially valid — added `disable-model-invocation: true` on `setup` only.** Setup writes config files and has side effects that shouldn't be auto-triggered. Other workflows (brainstorm, plan, work, review) benefit from conversational invocation ("brainstorm X" → model invokes skill). Upstream doesn't disable theirs.

**S3: Thin aliases are non-deterministic** (Gemini, Opus)
**Valid concern — accepted the risk.** The model generally follows simple "invoke /do:X" instructions. One version of imperfect aliases is better than a clean break with no transition period for users.

**S4: "Empirically confirmed" is weak evidence** (Opus, OpenAI)
**Valid — adding QA test.** Will add a reproducible test to the plugin-qa suite that verifies `${CLAUDE_SKILL_DIR}` substitution works in installed context.

### MINOR — Pending triage

8 MINOR findings from all three providers. Triage deferred to next session (context compaction needed). Files on disk:
- `.workflows/brainstorm-research/plugin-script-path-resolution/red-team--gemini.md`
- `.workflows/brainstorm-research/plugin-script-path-resolution/red-team--openai.md`
- `.workflows/brainstorm-research/plugin-script-path-resolution/red-team--opus.md`

## Related

- Bead jgb8: Setup assumes CLAUDE.md (original bug that led to this brainstorm)
- Bead ixz4: Research agents should web-search upstream constraints (filed during this brainstorm)
- [GitHub #9354](https://github.com/anthropics/claude-code/issues/9354): Canonical CLAUDE_PLUGIN_ROOT issue
- [GitHub #11011](https://github.com/anthropics/claude-code/issues/11011): Skill scripts fail with relative paths
- [Upstream plugin](https://github.com/EveryInc/compound-engineering-plugin): Reference architecture
