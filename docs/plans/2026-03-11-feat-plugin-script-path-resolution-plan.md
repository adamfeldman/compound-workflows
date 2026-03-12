---
title: "feat: Plugin script path resolution — commands→skills migration"
type: feat
status: completed
date: 2026-03-11
origin: docs/brainstorms/2026-03-11-plugin-script-path-resolution-brainstorm.md
---

# Plugin Script Path Resolution — Commands→Skills Migration

Migrate 8 core workflow commands from `commands/compound/` to `skills/do-*/` directories, adopting `${CLAUDE_SKILL_DIR}` for reliable path resolution. Rename namespace from `compound:` to `do:`. Update all cross-references. Version bump to v3.0.0 (major — breaking namespace change).

## Background

Plugin path resolution grew organically and breaks in installed contexts. Commands use hardcoded repo-relative paths (`bash plugins/compound-workflows/scripts/init-values.sh`) with no fallback. `${CLAUDE_SKILL_DIR}` (Claude Code v2.1.69+) provides load-time absolute path substitution but only works in skills, not commands. Upstream compound-engineering already moved all workflows to skills.

**Origin brainstorm:** `docs/brainstorms/2026-03-11-plugin-script-path-resolution-brainstorm.md` — red-teamed by 3 providers, all CRITICAL/SERIOUS/MINOR findings resolved. Key carried-forward decisions: D1 (commands→skills), D2 (`${CLAUDE_SKILL_DIR}/../../scripts/` path pattern), D3 (`do:` namespace), D4 (only setup gets disable-model-invocation), D5 (update 5 existing skills), D6 (hyphenated directory names).

## Acceptance Criteria

- [ ] All 8 workflow commands exist as skills in `skills/do-*/SKILL.md`
- [ ] 7 of 8 skills use `${CLAUDE_SKILL_DIR}/../../scripts/init-values.sh` for path resolution (`do:compound` is exempt — no init-values.sh call)
- [ ] `do:setup` has `disable-model-invocation: true`; other 7 do not
- [ ] 5 existing skills (version, plugin-changes-qa, classify-stats, git-worktree, resolve-pr-parallel) use `${CLAUDE_SKILL_DIR}` instead of hardcoded paths or broken `${CLAUDE_PLUGIN_ROOT}`
- [ ] 8 thin alias command files in `commands/compound/` redirect to `/do:*` skills (Option B template)
- [ ] init-values.sh validates `.claude-plugin/plugin.json` exists at computed PLUGIN_ROOT
- [ ] All 6 agent files with `/compound:*` refs updated to `/do:*`
- [ ] All 8 skill files with `/compound:*` refs updated to `/do:*`; `recover` skill supports dual-namespace detection
- [ ] QA scripts updated: context-lean-grep.sh, truncation-check.sh, stale-references.sh (+ new Check 2b), file-counts.sh
- [ ] plugin-changes-qa Tier 2 agent prompts scan `skills/do-*/SKILL.md`
- [ ] CLAUDE.md, AGENTS.md, README.md, CHANGELOG.md updated
- [ ] plugin.json and marketplace.json bumped to 3.0.0
- [ ] `${CLAUDE_SKILL_DIR}/../../` depth assumption documented in plugin CLAUDE.md
- [ ] git-worktree stale `/workflows:*` references fixed
- [ ] All Tier 1 QA scripts pass with zero findings
- [ ] `$ARGUMENTS` substitution in skills verified empirically (prerequisite gate)

## Prerequisite: Verify `$ARGUMENTS` in Skills

Before any migration work, empirically verify that `$ARGUMENTS` / `#$ARGUMENTS` substitution works in SKILL.md files the same way it does in commands. The upstream compound-engineering plugin uses skills with arguments, and the brainstorm confirms skills get `$ARGUMENTS`, but this must be tested.

**Test:** Create a temporary `skills/args-test/SKILL.md` with:
```yaml
---
name: args-test
---
Report: arguments received = "#$ARGUMENTS"
```

Invoke `/compound-workflows:args-test hello world` and verify the model sees "hello world" substituted.

**If `$ARGUMENTS` does NOT work in skills:** Stop. The migration requires a different argument-passing mechanism. File a bead and revisit the brainstorm.

**If `$ARGUMENTS` works:** Delete test skill and proceed with Phase 1.

## Phase 1: init-values.sh Enhancement

Single targeted change — add `.claude-plugin/plugin.json` validation to PLUGIN_ROOT resolution. (See brainstorm RQ3.)

- [ ] After the existing PLUGIN_ROOT directory check (lines 35-38), add:
  ```bash
  if [[ ! -f "$PLUGIN_ROOT/.claude-plugin/plugin.json" ]]; then
    echo "Error: PLUGIN_ROOT validation failed — .claude-plugin/plugin.json not found at $PLUGIN_ROOT" >&2
    echo "  Resolved PLUGIN_ROOT: $PLUGIN_ROOT" >&2
    exit 1
  fi
  ```
- [ ] This check runs for ALL commands, including `version` (which currently skips `validate_plugin_root()` — this new check is in the main flow, not a function)

**No upward-walk fallback.** (See brainstorm C3 resolution + specflow Q9 analysis.) `${CLAUDE_SKILL_DIR}/../../scripts/init-values.sh` produces an absolute path, so `$0`-relative resolution inside init-values.sh always works. The existing `find` fallback handles the case where init-values.sh itself isn't found. The upward walk solves a case that can't occur.

**Out of scope:** No other changes to init-values.sh internal logic (brainstorm: "it works fine once found").

## Phase 2: Create 8 Workflow Skill Files

Create skill directories and SKILL.md files by migrating content from the 8 command files.

### Directory creation

```
skills/do-brainstorm/SKILL.md    ← from commands/compound/brainstorm.md (555 lines)
skills/do-plan/SKILL.md          ← from commands/compound/plan.md (941 lines)
skills/do-deepen-plan/SKILL.md   ← from commands/compound/deepen-plan.md (1296 lines)
skills/do-work/SKILL.md          ← from commands/compound/work.md (484 lines)
skills/do-review/SKILL.md        ← from commands/compound/review.md (212 lines)
skills/do-compound/SKILL.md      ← from commands/compound/compound.md (193 lines)
skills/do-compact-prep/SKILL.md  ← from commands/compound/compact-prep.md (179 lines)
skills/do-setup/SKILL.md         ← from commands/compound/setup.md (777 lines)
```

### Per-file migration checklist

For each command file → skill file:

- [ ] **YAML frontmatter:** Change `name: compound:<cmd>` to `name: do:<cmd>`. Carry forward the existing `description:` value from the source command file's frontmatter. For `do:setup` only, add `disable-model-invocation: true`.
- [ ] **Script path references:** Replace all `bash plugins/compound-workflows/scripts/init-values.sh <cmd>` with `bash ${CLAUDE_SKILL_DIR}/../../scripts/init-values.sh <cmd>`
- [ ] **Secondary script references:** Replace `bash $PLUGIN_ROOT/scripts/<script>` with `bash ${CLAUDE_SKILL_DIR}/../../scripts/<script>` where applicable (compact-prep uses `append-snapshot.sh`)
- [ ] **Internal cross-references:** Update any `/compound:*` references within the file to `/do:*`
- [ ] **`#$ARGUMENTS` usage:** Preserve as-is (skills support `$ARGUMENTS`)
- [ ] **Content:** Otherwise unchanged — same instructions, same phases, same agent dispatches

### Special cases

- **`do:compound`** — Has no init-values.sh call (uses inline `mkdir -p`). Migration is a pure move+rename with frontmatter change. No path resolution changes needed.
- **`do:setup`** — Gets `disable-model-invocation: true`. The existing `skills/setup/SKILL.md` (reference material) remains unchanged. Document the three-way relationship in CLAUDE.md: thin alias (`commands/compound/setup.md`) → workflow skill (`skills/do-setup/SKILL.md`) → reference skill (`skills/setup/SKILL.md`).
- **`do:compact-prep`** — References `$PLUGIN_ROOT/scripts/append-snapshot.sh` after init-values.sh runs. Replace with `${CLAUDE_SKILL_DIR}/../../scripts/append-snapshot.sh`.

## Phase 3: Update 5 Existing Skills

Update the 5 skills that currently reference scripts with hardcoded paths or broken `${CLAUDE_PLUGIN_ROOT}`.

### Pattern 1: Hardcoded path + find fallback → `${CLAUDE_SKILL_DIR}`

- [ ] **version/SKILL.md:** Replace the two-step `bash plugins/compound-workflows/scripts/init-values.sh version` + `find` fallback block with single line: `bash ${CLAUDE_SKILL_DIR}/../../scripts/init-values.sh version`
- [ ] **plugin-changes-qa/SKILL.md:** Same replacement, command: `plugin-changes-qa`. Also update Tier 2 agent prompts (see Phase 5).
- [ ] **classify-stats/SKILL.md:** Same replacement, command: `classify-stats`. Also remove the stale comment about overflow pattern.

### Pattern 2: Broken `${CLAUDE_PLUGIN_ROOT}` → `${CLAUDE_SKILL_DIR}`

- [ ] **git-worktree/SKILL.md:** Replace all `${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh` with `${CLAUDE_SKILL_DIR}/scripts/worktree-manager.sh` (~12 locations). Also fix stale `/workflows:review` and `/workflows:work` references → `/do:review` and `/do:work`.
- [ ] **resolve-pr-parallel/SKILL.md:** Replace all `${CLAUDE_PLUGIN_ROOT}/skills/resolve-pr-parallel/scripts/<script>` with `${CLAUDE_SKILL_DIR}/scripts/<script>` (4 locations).

## Phase 4: Create Thin Alias Command Files

Replace the 8 full command files in `commands/compound/` with thin alias redirects. Use the Option B structured template:

```yaml
---
name: compound:<cmd>
description: (deprecated) Use /do:<cmd> instead
---

> **Deprecated:** This command moved to `/do:<cmd>` in v3.0.0.

The user's original arguments: #$ARGUMENTS

Invoke the `/do:<cmd>` skill immediately with the arguments shown above. Do not ask for new input.

If the user explicitly asked for `/compound:<cmd>`, mention that it has been renamed to `/do:<cmd>`.
```

Note: `#$ARGUMENTS` is substituted by Claude Code at load time (same mechanism as in commands). The model sees the resolved arguments in the alias, then passes them when invoking the target skill.

Create for all 8: brainstorm, plan, deepen-plan, work, review, compound, compact-prep, setup.

**Alias removal timeline:** Aliases will be removed in the next minor or major version after v3.0.0. Document in CHANGELOG migration notes.

## Phase 5: Update QA Scripts

### Tier 1 scripts

- [ ] **context-lean-grep.sh:** Expand Checks 1-4 scan scope from `commands/compound/*.md` only → also scan `skills/do-*/SKILL.md`. Check 5 (`$()` patterns) already scans `skills/*/SKILL.md` — verify it catches `do-*` directories.
- [ ] **truncation-check.sh:** Add `skills/do-*/SKILL.md` check at 20-line threshold. Lower `commands/compound/*.md` threshold to 3 lines (thin aliases are ~8 lines, but allow headroom).
- [ ] **stale-references.sh:**
  - Update Check 2 to handle both `compound:` and `do:` namespace references
  - Add **Check 2b**: Validate `do:<name>` references against existing `skills/do-*/` directories. Implementation: build skill name index from directory names (`ls -d skills/do-*/` → extract `do-X` → normalize to `do:X`), scan all plugin `.md` files for `/do:<name>` patterns, flag references where `<name>` does not appear in the index. Follow the existing Check 2 pattern (batch grep + post-filter).
- [ ] **file-counts.sh:** Update expected counts in target docs: 26 agents, 28 skills, 8 commands. Verify the script's count extraction logic handles the new directory structure.

### Tier 2 agent prompts (in plugin-changes-qa/SKILL.md)

- [ ] **Agent A (context-lean reviewer):** Add `$PLUGIN_ROOT/skills/do-*/SKILL.md` to scan scope alongside `commands/compound/`
- [ ] **Agent B (role description reviewer):** Same — scan skill files for agent dispatch patterns
- [ ] **Agent C (command completeness reviewer):** Scan `skills/do-*/SKILL.md` for completeness conventions (AskUserQuestion, phase/step numbering, YAML frontmatter, argument handling). Thin aliases in `commands/compound/` should be checked for the alias template format only.

## Phase 6: Update Cross-References

### Agent files (6 files)

Update all `/compound:*` references to `/do:*` in:

- [ ] `agents/workflow/convergence-advisor.md`
- [ ] `agents/workflow/plan-consolidator.md`
- [ ] `agents/research/learnings-researcher.md`
- [ ] `agents/research/git-history-analyzer.md`
- [ ] `agents/workflow/plan-checks/semantic-checks.md`
- [ ] `agents/review/code-simplicity-reviewer.md`

These are batch find-and-replace operations. Each reference is instructional text telling agents which commands exist.

### Skill files (8 files)

- [ ] `skills/recover/SKILL.md` — **Dual-namespace detection.** Update to scan session logs for BOTH `compound:*` and `do:*` namespace patterns. Old sessions (pre-v3.0.0) will have `compound:*` in JSONL logs indefinitely. Add comments explaining the dual-namespace period. (~10 references to update.)
- [ ] `skills/document-review/SKILL.md` — Update `/compound:*` → `/do:*`
- [ ] `skills/setup/SKILL.md` — Update references (this is the reference skill, not the workflow skill)
- [ ] `skills/brainstorming/SKILL.md` — Update `/compound:*` → `/do:*`
- [ ] `skills/classify-stats/SKILL.md` — Update (in addition to Phase 3 path changes)
- [ ] `skills/plugin-changes-qa/SKILL.md` — Update (in addition to Phase 5 Tier 2 prompt changes)
- [ ] `skills/file-todos/SKILL.md` — Update `/compound:*` → `/do:*`
- [ ] `skills/orchestrating-swarms/SKILL.md` — Batch update ~19 references. This skill is beta/illustrative — references are examples, not functional. Straightforward find-and-replace.

## Phase 7: Documentation Updates

### Plugin CLAUDE.md

- [ ] **Directory structure:** Add `skills/do-*/` entries (8 new), note thin aliases in `commands/compound/`
- [ ] **Agent registry table:** Update "Dispatched By" column — `brainstorm` → `do:brainstorm`, `plan` → `do:plan`, etc.
- [ ] **Setup Command/Skill Split section:** Rewrite to explain three-way relationship: thin alias → workflow skill (`do-setup`) → reference skill (`setup`)
- [ ] **Config Files section:** Update command file references to skill file references
- [ ] **Command Conventions section:** Rename to "Skill/Command Conventions". Explain `do:` prefix for workflow skills, `compound:` aliases for backwards compat
- [ ] **Context-Lean Convention:** Update "commands dispatching agents" → "workflow skills dispatching agents"
- [ ] **New section: `${CLAUDE_SKILL_DIR}` Path Resolution:** Document the `${CLAUDE_SKILL_DIR}/../../` depth assumption — why it works (skills are 2 levels below plugin root per Agent Skills spec), what the depth represents, the `.claude-plugin/plugin.json` validation check, and what to do if it breaks (the existing `find` fallback in init-values.sh handles it)

### AGENTS.md (repo root)

- [ ] **Routing section:** Update `/compound:brainstorm` → `/do:brainstorm`, etc. Add note: "During v3.0.0 transition, `/compound:*` aliases redirect to `/do:*`. Aliases will be removed in a future version."

### README.md

- [ ] Update component counts: 26 agents, 28 skills, 8 commands (aliases)
- [ ] Update invocation examples to use `/do:*` namespace
- [ ] Add migration note for v3.0.0

### CHANGELOG.md

- [ ] v3.0.0 entry with sections:
  - **Breaking Changes:** Namespace rename `compound:` → `do:`. Commands moved to skills. Full invocation changes from `/compound:brainstorm` to `/do:brainstorm`.
  - **Features:** `${CLAUDE_SKILL_DIR}` path resolution (works in installed contexts), no 8-command limit, init-values.sh PLUGIN_ROOT validation, skill-to-skill reference validation (QA Check 2b)
  - **Migration Notes:** Thin aliases in `commands/compound/` redirect to `/do:*` skills for one version. Users should update muscle memory, docs, and any memory files referencing `/compound:*`. Aliases will be removed in the next version.

## Phase 8: Version Bump and Final Checks

- [ ] `plugins/compound-workflows/.claude-plugin/plugin.json` — version: `2.6.1` → `3.0.0`
- [ ] `.claude-plugin/marketplace.json` — version: `2.6.1` → `3.0.0`
- [ ] Run all 6 Tier 1 QA scripts — must pass with zero findings
- [ ] Spot-check: invoke `/do:brainstorm test-topic` in source repo context, verify init-values.sh resolves correctly
- [ ] Spot-check: invoke `/compound:brainstorm test-topic` (thin alias), verify redirect works

## Implementation Order

Phases are designed for sequential execution with natural verification points:

1. **Prerequisite** — `$ARGUMENTS` verification (blocker — stop if it fails)
2. **Phase 1** — init-values.sh enhancement (standalone, no dependencies)
3. **Phase 2** — Create 8 skill files (the core migration)
4. **Phase 3** — Update 5 existing skills (independent of Phase 2 content)
5. **Phase 4** — Create thin aliases (requires Phase 2 skills to exist for redirect targets)
6. **Phase 5** — QA script updates (requires Phase 2+4 to know the final file layout)
7. **Phase 6** — Cross-reference updates (batch work, can parallelize across files)
8. **Phase 7** — Documentation (needs final file layout and version)
9. **Phase 8** — Version bump and verification (last step)

**Parallelization opportunities:** Phases 2 and 3 touch separate files — can run in parallel. Phase 6 (cross-references) can run in parallel across agent files vs skill files. Phase 7 doc updates are independent of each other.

## File Change Summary

| Category | Files | Notes |
|----------|-------|-------|
| New skill directories | 8 | `skills/do-{brainstorm,plan,deepen-plan,work,review,compound,compact-prep,setup}/SKILL.md` |
| Replaced command files | 8 | `commands/compound/*.md` → thin aliases |
| Updated existing skills | 5 | version, plugin-changes-qa, classify-stats, git-worktree, resolve-pr-parallel |
| Updated agent files | 6 | Cross-reference `/compound:*` → `/do:*` |
| Updated skill files | 8 | Cross-reference `/compound:*` → `/do:*` (recover gets dual-namespace) |
| Updated QA scripts | 4 | context-lean-grep.sh, truncation-check.sh, stale-references.sh, file-counts.sh |
| Updated documentation | 4 | CLAUDE.md, AGENTS.md, README.md, CHANGELOG.md |
| Updated manifests | 2 | plugin.json, marketplace.json |
| Modified scripts | 1 | init-values.sh (PLUGIN_ROOT validation) |
| **Total files touched** | **~46** | |

## Open Questions

None — all questions resolved during planning. See specflow analysis at `.workflows/plan-research/plugin-script-path-resolution/agents/specflow.md` for full Q&A record.

## Risks

| Risk | Mitigation | Source |
|------|-----------|--------|
| `$ARGUMENTS` doesn't work in skills | Prerequisite gate — test before any migration work | Specflow Q1 |
| Model emits literal `${CLAUDE_SKILL_DIR}` in Bash calls | Empirically tested (model uses substituted path). Add E2E QA test in follow-up. | Red team M5 |
| Thin aliases unreliable (model doesn't follow redirect) | Accepted risk (brainstorm S3). Structured template (Option B) maximizes clarity. One version only. | Red team S3 |
| `../../` depth assumption breaks | `.claude-plugin/plugin.json` validation fails loudly. Existing `find` fallback in init-values.sh recovers. | Red team C3 |
| Stale `/compound:*` refs missed | Check 2b validates skill-to-skill refs. Full grep during Phase 6. | Specflow Gap 6 |

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-03-11-plugin-script-path-resolution-brainstorm.md` — Key decisions: D1-D6, RQ1-RQ3. Red team: 4 CRITICAL, 8 SERIOUS, 8 MINOR all resolved.
- **Research:** `.workflows/plan-research/plugin-script-path-resolution/agents/` — repo-research.md, learnings.md, specflow.md
- **Brainstorm red team:** `.workflows/brainstorm-research/plugin-script-path-resolution/red-team--{gemini,openai,opus}.md`
- **Related solutions:** `docs/solutions/plugin-infrastructure/2026-03-08-command-registration-limit-workaround.md`, `docs/solutions/claude-code-internals/2026-03-11-script-file-shell-substitution-bypass.md`
- **Upstream reference:** [EveryInc/compound-engineering-plugin](https://github.com/EveryInc/compound-engineering-plugin)
- **Upstream issues:** [#9354](https://github.com/anthropics/claude-code/issues/9354) (CLAUDE_PLUGIN_ROOT broken), [#11011](https://github.com/anthropics/claude-code/issues/11011) (skill relative paths)
