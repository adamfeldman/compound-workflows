---
title: "feat: Plugin version visibility and release process improvements"
type: feat
status: active
date: 2026-03-09
origin: docs/brainstorms/2026-03-09-plugin-version-visibility-brainstorm.md
---

# Plugin Version Visibility

Implement 6 deliverables from the brainstorm to answer "am I stale?" and prevent forgotten releases.

## Background

v1.10.0 was merged and pushed but no GitHub release was created. `claude plugin update` didn't pick up changes. compact-prep Step 6 (release check) existed but wasn't running because the loaded plugin itself was stale. (See brainstorm: Why This Approach section.)

## Acceptance Criteria

- [ ] `version-check.sh` shows 3-way comparison (source vs installed vs release) with actionable advice
- [ ] `version-sync.sh` catches plugin.json/marketplace.json drift and missing CHANGELOG entries
- [ ] `/compound-workflows:version` skill wraps version-check.sh
- [ ] compact-prep Step 6 runs version-check.sh (replaces inline gh check)
- [ ] setup runs version-check.sh early to warn about stale plugins
- [ ] work.md Phase 4 reminds about releases after PR creation
- [ ] CLAUDE.md and AGENTS.md versioning checklists aligned to 4-file set
- [ ] AGENTS.md phantom `ref` field removed
- [ ] All QA checks pass (including the new version-sync.sh)

## Implementation

### Phase 1: New Scripts (3 new files, parallel-safe)

#### 1a. Create `scripts/plugin-qa/version-sync.sh`

QA script that validates version consistency across files. Sources lib.sh, uses standard findings pattern.

- [ ] Source lib.sh, resolve_plugin_root, init_findings
- [ ] Extract version from `plugin.json` (`"version": "X.Y.Z"`)
- [ ] Extract plugin version from `marketplace.json` (repo root's `.claude-plugin/marketplace.json`, the `plugins[0].version` field)
- [ ] Compare: if mismatch, add SERIOUS finding
- [ ] Extract current version, check CHANGELOG.md has a heading containing that version (e.g., `## 1.11.0` or `## v1.11.0`)
- [ ] If no matching CHANGELOG heading, add SERIOUS finding
- [ ] emit_output "Version Sync Check"
- [ ] Exit 0 (findings are informational)

This script auto-runs via the PostToolUse hook (hook iterates all `*.sh` in plugin-qa/).

Reference: `scripts/plugin-qa/file-counts.sh` for lib.sh usage pattern. `docs/solutions/qa-infrastructure/2026-03-08-bash-qa-script-patterns.md` for process substitution and regex patterns.

#### 1b. Create `scripts/version-check.sh`

Utility script for 3-way version comparison. **Not in plugin-qa/** — this script makes network calls to GitHub and should NOT auto-run on every commit hook. (The hook auto-discovers `plugin-qa/*.sh`; see `.claude/hooks/plugin-qa-check.sh` lines 79-83.)

- [ ] Accept optional `$1` for plugin root (default: auto-detect from script location at `scripts/`, so plugin root is `..`)
- [ ] **Source version**: Read from `$PLUGIN_ROOT/.claude-plugin/plugin.json`
- [ ] **Installed version**: Read from `~/.claude/plugins/marketplaces/compound-workflows-marketplace/plugins/compound-workflows/.claude-plugin/plugin.json`. If path doesn't exist, show "not installed"
- [ ] **Latest release**: Query `gh release list --json tagName,isLatest --jq '.[] | select(.isLatest) | .tagName'`. If `gh` unavailable or fails, show "unknown (gh CLI unavailable)"
- [ ] **Version normalization**: Strip leading `v` before all comparisons
- [ ] **Output format**: Always show all 3 versions. Append status labels (STALE, UNRELEASED) and "Actions needed:" with exact commands to run. See brainstorm output examples.
- [ ] **Exit code**: 0 = all match or informational only; 1 = staleness or unreleased version detected (allows callers to branch on result)

Does NOT source lib.sh (different output format — informational dashboard, not structured findings).

Reference: brainstorm section 1 for output format examples.

#### 1c. Create `skills/version/SKILL.md`

- [ ] YAML frontmatter: `name: version`, `description: Check plugin version status — source vs installed vs release`
- [ ] Instruction: Run `bash plugins/compound-workflows/scripts/version-check.sh` (resolve path from repo root)
- [ ] Present the script's output to the user
- [ ] No `disable-model-invocation` (needs LLM to run the script and present)

This is skill #19. Skill invocation: `/compound-workflows:version`.

### Phase 2: Proactive Integrations (3 existing files, parallel-safe)

#### 2a. Update `commands/compound/compact-prep.md` — Extend Step 6

Replace the current Step 6 (inline `gh release view` check) with a call to version-check.sh.

Current Step 6 (lines 78-90): inline bash that checks only release existence for the current version.

New Step 6:
- [ ] Run `bash plugins/compound-workflows/scripts/version-check.sh`
- [ ] If script shows any issues (STALE or UNRELEASED), present the script's output and use AskUserQuestion for each actionable item:
  - STALE → "Plugin is stale. Update now?" → Yes: run `claude plugin update compound-workflows@compound-workflows-marketplace`
  - UNRELEASED → "Version X.Y.Z has no release. Create one now?" → Yes: run tag + push + release commands
- [ ] If all versions match: "Versions OK." and move on
- [ ] Keep the step heading as "Step 6: Version Check" (rename from "Release Check" to reflect broader scope)

#### 2b. Update `commands/compound/setup.md` — Add version check step

Add a new step after Step 1 (Detect Environment) to warn about stale plugins early in project setup.

- [ ] Add "Step 1.5: Plugin Version Check" (between Step 1 and Step 2)
- [ ] Run `bash plugins/compound-workflows/scripts/version-check.sh`
- [ ] If STALE: warn user and suggest update command
- [ ] If UNRELEASED: note it but don't block setup (setup is about the project, not releases)
- [ ] If all match or script not found: move on silently

#### 2c. Update `commands/compound/work.md` — Post-merge reminder

Add a note in Phase 4 (Ship), after step 3 (Create PR), before step 4 (Update plan status).

- [ ] Add step 3.5 or a note block after PR creation: "After merge, run `/compound-workflows:version` or `/compound:compact-prep` to check for missing releases."
- [ ] Keep it lightweight — informational note, not an automated step. (User rationale: "work.md should NOT do releases automatically, that's not appropriate for a general purpose plugin.")

### Phase 3: Doc Alignment (2 files)

#### 3a. Update `plugins/compound-workflows/CLAUDE.md`

- [ ] Versioning section (lines 3-17): restructure the numbered list to include all 4 files explicitly:
  1. `.claude-plugin/plugin.json` — bump version
  2. `CHANGELOG.md` — document changes
  3. `README.md` — verify component counts and tables
  4. `.claude-plugin/marketplace.json` (repo root) — bump version
- [ ] Remove the buried sentence on line 17 ("Also update the marketplace.json...") since it's now in the list
- [ ] Directory structure: update `scripts/` section to show both `plugin-qa/` (5 scripts + lib.sh) and `version-check.sh`
- [ ] Update skill count if listed (currently 18 skill directories shown)

#### 3b. Update `AGENTS.md`

- [ ] Versioning section (lines 66-70): add `README.md` to the list:
  1. `plugin.json` — bump version
  2. `.claude-plugin/marketplace.json` — bump version
  3. `CHANGELOG.md` — document changes
  4. `README.md` — verify component counts
- [ ] Release Process step 4 (line 82): remove phantom `ref` reference. Change from "Bump version + ref in marketplace.json (ref pins the tag...)" to "Bump version in `.claude-plugin/marketplace.json`"
- [ ] QA section (line 37): update "Four bash scripts" → "Five bash scripts" (adding version-sync.sh)
- [ ] QA table: add version-sync.sh row
- [ ] Project structure: update script count in `scripts/plugin-qa/` line

### Phase 4: Version Bump and Counts (depends on all above)

This is a MINOR version bump (new skill + new scripts = new functionality).

- [ ] `plugins/compound-workflows/.claude-plugin/plugin.json`: bump 1.10.0 → 1.11.0
- [ ] `.claude-plugin/marketplace.json`: bump plugin version 1.10.0 → 1.11.0
- [ ] `plugins/compound-workflows/CHANGELOG.md`: add 1.11.0 entry documenting all 6 deliverables
- [ ] `plugins/compound-workflows/README.md`: update skill count 18 → 19, add version skill to skill list
- [ ] `plugins/compound-workflows/CLAUDE.md`: update script count references (4 → 5 in plugin-qa), add version skill to skills directory listing
- [ ] `AGENTS.md`: update script count in QA section (4 → 5)

## Parallel Dispatch Notes

- **Phase 1**: All 3 files are new and independent → dispatch in parallel
- **Phase 2**: All 3 files are different existing files → dispatch in parallel
- **Phase 3**: CLAUDE.md and AGENTS.md are independent → dispatch in parallel
- **Phase 4**: Must run after all other phases (needs final file list for accurate counts)

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-03-09-plugin-version-visibility-brainstorm.md` — 6 deliverables, all design decisions resolved, red team findings addressed
  - Key decisions carried forward: work.md should NOT automate releases; 3-way comparison validated; version-sync in own script (not file-counts.sh); both script and skill; proactive checks in compact-prep + setup
- **Solution doc (QA patterns):** `docs/solutions/qa-infrastructure/2026-03-08-bash-qa-script-patterns.md` — lib.sh patterns, process substitution, batch-then-filter
- **Solution doc (command limit):** `docs/solutions/plugin-infrastructure/2026-03-08-command-registration-limit-workaround.md` — 8-command limit, skill as overflow strategy
- **Research:** `.workflows/plan-research/plugin-version-visibility/agents/`
