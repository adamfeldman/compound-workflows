# Specification Flow Analysis: Fork compound-engineering Agents & Skills

## Scope Analyzed

Feature: Fork 22 agents and 14 skills from compound-engineering into compound-workflows. Genericize examples, rename 3 agents, update 7 commands, add NOTICE file, update setup with conflict detection, fix deepen-plan discovery logic.

Claimed totals: 91 files to copy, 36 needing modifications.

Sources reviewed: repo-research.md (command-by-command analysis), source-inventory.md (per-file inventory), learnings.md (institutional knowledge), brainstorm (scope and decisions), plus live examination of deepen-plan.md, setup.md, review.md, compound.md, plan.md, plugin.json, README.md, CHANGELOG.md, CLAUDE.md, and the source compound-engineering agent/skill directories.

---

## 1. Missing Steps and Dependencies Between Phases

### 1A. No Phase for Agent Directory Structure Creation

The brainstorm shows the target directory layout (`agents/review/`, `agents/workflow/`) but no step explicitly creates these directories before copying files into them. The current plugin only has `agents/research/`. The plan needs an explicit step to:

```bash
mkdir -p plugins/compound-workflows/agents/review
mkdir -p plugins/compound-workflows/agents/workflow
```

**Risk:** If copying is scripted and the directories do not exist, copies fail silently or noisily depending on the tool used.

### 1B. No Step to Verify the Existing context-researcher.md Is Untouched

The inventory lists context-researcher as "already ported" but never checks whether it needs updates for consistency with the newly ported agents. If the 22 new agents use slightly different output format conventions, examples, or integration points than context-researcher, the inconsistency will be visible to users. A reconciliation step is missing.

### 1C. Plugin.json Update Depends on Final File Counts

The spec says to update plugin.json description (currently "8 commands, 1 agent, 1 skill") to reflect the new counts. But the description string depends on the final count of agents (23) and skills (15). This update MUST happen after all copies and modifications are verified -- not during the copy phase. The dependency is implicit, not documented.

### 1D. README.md Dependency Table Rewrite Depends on Setup Command Changes

README.md line 63 currently lists compound-engineering as "Recommended." This must change to remove compound-engineering entirely from the dependency table. But the replacement text depends on what the new setup.md/setup skill detects. The setup command rewrite and the README update are coupled -- the README should reflect whatever the setup command actually checks for.

### 1E. No Step for CHANGELOG.md Entry Assembly

The CHANGELOG must list all 22 new agents by name and all 14 new skills. This is a mechanical but error-prone step. If written before all files are verified, it may list agents that were not actually copied or miss ones that were. The CHANGELOG entry should be generated AFTER verification, not during the copy phase.

### 1F. Setup Skill vs. Setup Command Relationship Is Ambiguous

The brainstorm says "setup skill replaces the setup command's content." But these are different plugin mechanisms:
- A **command** lives in `commands/compound-workflows/setup.md` and is invoked via `/compound-workflows:setup`
- A **skill** lives in `skills/setup/SKILL.md` and is loaded contextually

The spec seems to mean the setup *command* should be rewritten to incorporate what the setup *skill* teaches. But the source compound-engineering has a setup **skill** (in `skills/setup/SKILL.md`) that configures `compound-engineering.local.md`. The plan ports this skill AND rewrites the command. The interaction between the two is not specified:
- Does the command call the skill?
- Does the command duplicate the skill's logic?
- Is the skill only used when the command is not explicitly invoked?

**This is a gap.** The plan should specify whether both the command and skill exist, and how they interact.

### 1G. No Phase for Removing Dead Agent References from compound.md

The compound.md command (lines 99-101) references `performance-oracle`, `security-sentinel`, and `data-integrity-guardian` as Phase 3 enhancement agents. After the fork, these agents will be bundled. The current spec only mentions compound.md needs example genericization (lines 40, 126), but does NOT mention that the Phase 3 references should now point to the bundled agents rather than relying on compound-engineering being installed. This is a semantic change that needs explicit handling.

---

## 2. Edge Cases in the Copy/Rename/Genericize Workflow

### 2A. Agent Name Collisions if Both Plugins Installed

If a user ignores the setup warning and installs both compound-workflows and compound-engineering, Claude Code will see TWO definitions for agents like `security-sentinel`, `performance-oracle`, etc. The spec acknowledges this ("agent resolution with duplicates would be unpredictable") and plans to warn via setup. But the edge case of WHICH agent wins is undefined. Claude Code's agent resolution order (plugin cache path, alphabetical, most-recently-installed) determines behavior. This is not documented in the spec and cannot be controlled by the plugin author.

**Mitigation recommendation:** Document the specific behavior observed in testing. If compound-engineering's definition "wins," the fork's richer/modified prompts are never used. If compound-workflows wins, compound-engineering users lose their customized prompts. Either way, there is a user-facing regression that the warning alone does not prevent.

### 2B. Three Renamed Agents Create Forward-Compatibility Risk

The renames (`kieran-typescript-reviewer` -> `typescript-reviewer`, etc.) mean that any user who has compound-engineering AND later installs compound-workflows will have BOTH the old-named and new-named agents available. Commands will dispatch to the new names, but the old names still exist in compound-engineering. A user who manually references `kieran-typescript-reviewer` in their own commands will get compound-engineering's version. This is not a bug, but it is a confusing state.

### 2C. Skill Cross-Reference Chain Breaks

The learnings-researcher agent (source-inventory.md line 23) references `../../skills/compound-docs/references/yaml-schema.md` via a relative path. After porting to compound-workflows, this relative path will point to a DIFFERENT location. The relative path resolution depends on where Claude Code resolves the agent file from. If the agent is at `plugins/compound-workflows/agents/research/learnings-researcher.md`, then `../../skills/compound-docs/references/yaml-schema.md` resolves to `plugins/compound-workflows/skills/compound-docs/references/yaml-schema.md` -- which IS the correct location after the port. But this depends on the agent being read from the plugin directory, not from a cache path. Verify that the relative path resolution works in the installed (cached) plugin layout, not just the development layout.

### 2D. Bulk Find-Replace in orchestrating-swarms May Over-Match

The orchestrating-swarms skill needs `compound-engineering` replaced with `compound-workflows` throughout. But a naive find-replace could hit:
- Prose that says "compound-engineering plugin" (should become "compound-workflows plugin")
- subagent_type strings like `compound-engineering:review:kieran-rails-reviewer` (this agent is NOT being ported -- the reference should be REMOVED, not renamed)
- General explanatory text about the compound-engineering ecosystem

**Each replacement must be evaluated in context.** The spec says "bulk find-replace" but some instances need deletion (references to dropped agents), some need renaming (references to ported agents), and some need rewording (explanatory prose). This is not a single-operation task.

### 2E. The "Every Reader" Case Study in agent-native-architecture

Six reference files contain "Every Reader" as a case study. The spec (source-inventory.md line 357) says these "could be left as-is (they are illustrative examples, not instructions) or genericized." This is an unresolved decision. If left as-is, marketplace users see a case study about a specific company's product. If genericized, six files need edits. The brainstorm marks this as MEDIUM priority but does not make a final decision. The implementation plan needs a concrete yes/no.

### 2F. Script File Permissions

Skills like git-worktree (`scripts/worktree-manager.sh`), resolve-pr-parallel (`scripts/get-pr-comments`, `scripts/resolve-pr-thread`), gemini-imagegen (5 Python scripts), and skill-creator (3 Python scripts) contain executable scripts. When copying these files, the executable permission bit (`chmod +x`) must be preserved. A naive file copy (e.g., via `cp` without `-p`, or via file-write operations in an editor) may strip permissions. The spec does not mention permission preservation.

### 2G. Python Requirements.txt Dependency

The gemini-imagegen skill has a `requirements.txt` file. The spec copies it but does not mention whether these Python dependencies conflict with anything in the user's environment, or whether the skill's SKILL.md documents the installation step. This is an external dependency that "full power" users need to set up -- it should be flagged in the setup command or README.

---

## 3. Testing Gaps

### 3A. No Automated Verification Strategy

The spec mentions 91 files to copy and 36 needing modifications. There is NO automated verification described. Manual testing of 91 files is error-prone. The plan needs:

**File count verification:**
```bash
# After copy, count agents
find plugins/compound-workflows/agents -name "*.md" -type f | wc -l
# Expected: 23 (22 new + 1 existing)

# Count skills (including subdirectory files)
find plugins/compound-workflows/skills -type f | wc -l
# Expected: 70 new + 1 existing SKILL.md = 71
```

**Modification verification:**
```bash
# Grep for any remaining compound-engineering references
grep -r "compound-engineering" plugins/compound-workflows/ --include="*.md" --include="*.yaml" --include="*.json"
# Expected: ZERO matches (except possibly NOTICE file attribution text)

# Grep for any remaining persona names
grep -r "Kieran\|kieran-typescript\|kieran-python\|kieran-rails\|julik-" plugins/compound-workflows/ --include="*.md"
# Expected: ZERO matches (except NOTICE file)

# Grep for company-specific examples
grep -r "BriefSystem\|EmailProcessing\|Xiatech\|EveryInc\|Every Reader\|cash-management\|intellect-v6" plugins/compound-workflows/ --include="*.md"
# Expected: ZERO matches

# Grep for dropped agent references
grep -r "dhh-rails-reviewer\|kieran-rails-reviewer\|every-style-editor\|lint\|ankane-readme-writer\|figma-design-sync" plugins/compound-workflows/ --include="*.md"
# Expected: ZERO matches
```

### 3B. No Functional Smoke Test Plan

After the mechanical copy/modify, there is no plan to verify that commands actually WORK:
- Does `/compound-workflows:plan` successfully dispatch `repo-research-analyst` to the bundled agent file (not general-purpose fallback)?
- Does `/compound-workflows:review` correctly launch `typescript-reviewer` (new name) instead of `kieran-typescript-reviewer` (old name)?
- Does `/compound-workflows:deepen-plan` discover agents from the plugin's own `agents/` directory?
- Does `/compound-workflows:setup` detect compound-engineering and produce a warning?
- Do skills with scripts (git-worktree, gemini-imagegen, resolve-pr-parallel) execute their scripts from the correct paths?

**Minimum functional smoke tests needed:**
1. Run `setup` in a clean project -- verify it detects bundled agents (not compound-engineering dependency)
2. Run `plan` with a simple feature description -- verify research agents are dispatched to bundled agent files
3. Run `review` on a test PR -- verify agent names in output match new names
4. Run `deepen-plan` -- verify Phase 2c discovers agents from the plugin's own directory
5. Manually verify `setup` produces a warning when compound-engineering is also installed

### 3C. No Diff Verification Against Source

For the 55 files that need NO changes (13 agents + 6 skills), there is no step to verify byte-for-byte identity with the source. After copying, run:

```bash
diff <source-file> <destination-file>
```

on every "no changes needed" file. If any diff exists, it indicates an unintended modification or truncation (which was flagged as a known risk from the v1.0.0 port in learnings.md Issue 1).

### 3D. No Line Count Verification

Learnings.md Issue 1 flags truncation risk. The source-inventory.md carefully records line counts for every file (e.g., repo-research-analyst: 136 lines, learnings-researcher: 265 lines). After copy, verify:

```bash
wc -l plugins/compound-workflows/agents/research/repo-research-analyst.md
# Expected: ~136 (may differ slightly if genericized)
```

For unmodified files, line counts must match exactly. For modified files, line counts should be close to the original (genericization typically changes content, not length).

### 3E. No YAML Frontmatter Validation

Every agent file must have valid YAML frontmatter with at minimum `name` and `description`. After the 3 renames, the frontmatter `name:` field must match the new filename:
- `typescript-reviewer.md` must have `name: typescript-reviewer` (not `name: kieran-typescript-reviewer`)
- `python-reviewer.md` must have `name: python-reviewer`
- `frontend-races-reviewer.md` must have `name: frontend-races-reviewer`

Every skill file must have `name` and `description` in frontmatter. The setup skill specifically has `disable-model-invocation: true` in its source -- this must be preserved.

---

## 4. Ordering Risks

### 4A. Critical Path: Copy Before Modify

All 91 files must be copied BEFORE any modifications begin. If you modify a file in the source (compound-engineering) directory instead of the destination (compound-workflows), you corrupt the upstream. The workflow should be:

1. Copy all 91 files to destination
2. Verify all 91 copies exist (file count check)
3. THEN begin modifications on the destination copies

Never modify in-place in the source directory.

### 4B. Rename Before Command Update

The 3 agent renames (kieran-typescript -> typescript, etc.) must happen before command files are updated to reference the new names. If commands reference `typescript-reviewer` but the file is still named `kieran-typescript-reviewer.md`, the Task dispatch will fall back to general-purpose silently.

**Ordering:**
1. Copy `kieran-typescript-reviewer.md` to destination
2. Rename destination file to `typescript-reviewer.md`
3. Update frontmatter `name:` field
4. THEN update review.md and any other commands referencing the new name

### 4C. Skills Before Commands That Reference Them

Commands like brainstorm.md reference skills (`brainstorming`, `document-review`). These skills should be copied before the commands are verified, so that verification can confirm the skill references resolve correctly.

### 4D. Agent Copy Before deepen-plan Discovery Update

The deepen-plan.md command (Phase 2c, lines 98-106) currently searches:
```bash
find ~/.claude/plugins/cache -path "*/agents/*.md" 2>/dev/null
find .claude/agents -name "*.md" 2>/dev/null
find ~/.claude/agents -name "*.md" 2>/dev/null
```

Plus a compound-engineering-specific filter (lines 104-106). After the fork, the discovery must also search the plugin's own agents directory. But the exact path depends on where Claude Code installs the plugin at runtime.

**Key question:** Does `find ~/.claude/plugins/cache -path "*/agents/*.md"` already catch compound-workflows' agents when the plugin is installed? If so, the compound-engineering-specific filter on lines 104-106 just needs to be updated to be plugin-agnostic. If not, an additional search path is needed.

This update must happen AFTER agents are copied (so you can test discovery), but the design must be settled BEFORE implementation (so you know what search paths to add).

### 4E. NOTICE File Before Any Publication

The NOTICE file (MIT attribution for compound-engineering / Kieran Klaassen) must exist before the plugin is published to any marketplace. It should be created early in the process, not as a cleanup step. Create it alongside the first file copy.

### 4F. Setup Command Rewrite Depends on All Other Changes Being Complete

The setup command/skill needs to detect bundled agents, warn about compound-engineering conflicts, and report accurate component counts. It should be the LAST command rewritten, after all agents, skills, and other commands are finalized. Otherwise it may reference components that do not yet exist or report incorrect counts.

---

## 5. What Could Go Wrong During Execution

### 5A. Context Exhaustion During the Port Itself

Copying and modifying 91 files in a single Claude session will exhaust context. The 14 skills alone contain files totaling thousands of lines (orchestrating-swarms alone is ~1580 lines, create-agent-skills has 26 files). An agent-assisted port will need compaction recovery, which means the port must be designed as a resumable workflow:
- Track which files have been copied (manifest)
- Track which files have been modified (checklist)
- Allow resumption after compaction

Without this, a compaction mid-port could lose track of which files were already processed, leading to double-modifications or missed files.

### 5B. Git Diff Noise Makes Review Impossible

Adding 91 files and modifying 36 produces a massive diff. If done as a single commit, the PR will be unreviewable. If split into commits, the intermediate states may have broken references (e.g., commands reference agents not yet copied).

**Recommended commit strategy:**
1. Commit 1: Copy all 91 files unmodified (pure copy, easy to verify against source)
2. Commit 2: Rename 3 agent files + update their frontmatter
3. Commit 3: Genericize examples across all modified files
4. Commit 4: Update commands (review.md, deepen-plan.md, etc.)
5. Commit 5: Rewrite setup command, add NOTICE, update plugin.json/README/CHANGELOG/CLAUDE.md

Each commit is independently verifiable and the diff is focused.

### 5C. Inconsistent Genericization

Six different people genericizing examples would produce six different replacement terms. Even a single person may use "AuthService" in one file and "UserService" in another for the same concept. The spec should define a canonical replacement table:

| Original | Replacement |
|----------|-------------|
| BriefSystem | AuthService |
| EmailProcessing | PaymentProcessor |
| cash-management | user-dashboard |
| intellect-v6-pricing | api-rate-limiting |
| Xiatech | Acme Corp |
| EveryInc/cora | owner/repo |
| Every Reader | BookReader (or just "a reading app") |
| feat-cash-management-ui | feat-user-dashboard-redesign |
| feat-cash-management-reporting-app | feat-user-dashboard-redesign |
| bq-cost-measurement | redis-cache-invalidation |

Without a canonical table, genericization will be inconsistent across the 36 files.

### 5D. The orchestrating-swarms Skill Is a Minefield

At ~1580 lines, this is the largest single file. It contains extensive references to `compound-engineering:review:*`, `compound-engineering:research:*`, etc. in `subagent_type` strings embedded in code examples, mermaid diagrams, and prose. Some of these reference agents being ported (update namespace), some reference agents being DROPPED (must be removed or replaced with alternatives), and some may reference agent categories like `design/*` which is being partially dropped (Figma agents dropped, no design agents ported). A careful manual review of every instance is required. Estimate 30-60 minutes for this single file.

### 5E. deepen-plan Discovery Logic Is More Complex Than Described

Looking at the actual deepen-plan.md (lines 98-106), the discovery logic does:
1. `find ~/.claude/plugins/cache -path "*/agents/*.md"` -- finds ALL agents from ALL plugins
2. `find .claude/agents -name "*.md"` -- finds project-local agents
3. `find ~/.claude/agents -name "*.md"` -- finds user-global agents
4. Then applies a compound-engineering-specific filter

After the fork, this logic needs to:
- Find agents from compound-workflows (they will be at `~/.claude/plugins/cache/*/compound-workflows/*/agents/...`)
- Still find agents from other plugins (not just compound-engineering)
- Apply appropriate filtering (USE review/research/design/docs, SKIP workflow)
- Handle the case where the plugin is in development mode (source directory, not cache)

The fix is NOT just "replace compound-engineering with compound-workflows" in lines 104-106. The entire filter block needs to be generalized to work with ANY plugin that provides agents in the expected directory structure, OR it needs to specifically enumerate compound-workflows' agent paths.

### 5F. The setup Skill Has a `disable-model-invocation: true` Field

The source compound-engineering setup skill has `disable-model-invocation: true` in its frontmatter. This means the skill is used as reference material, not as an agent that gets invoked. If the setup command is being rewritten to use the setup skill, it must `Read` the skill file for guidance -- it cannot dispatch the skill as a Task. This subtle distinction affects how the command/skill interaction works.

### 5G. File Count Discrepancy

The spec claims 91 files to copy. Let me verify:
- Agents: 21 files (22 new minus the 1 already existing context-researcher; but the inventory lists 21 agent .md files, not 22)
- Skills: 70 files (per source-inventory.md)
- Total: 91

This adds up. But the source-inventory counts 21 agents to port (Part 1) and says "Total files to copy across all skills: 70" (Part 2). 21 + 70 = 91. Correct.

However, the 36 files needing modifications includes:
- Agents: 8 need genericizing (3 LOW, 5 MEDIUM per source-inventory summary)
- Skills: 8 need genericizing (4 LOW, 2 MEDIUM, 2 HIGH per source-inventory summary)
- Commands: 7 commands to update
- Meta-files: 4 (plugin.json, README.md, CHANGELOG.md, CLAUDE.md)
- New file: 1 (NOTICE)
- Total: 8 + 8 + 7 + 4 + 1 = 28

That is 28, not 36. Either the spec includes additional files not enumerated (perhaps some of the 70 skill sub-files need modifications within their skills), or the count is wrong. Looking more carefully: the compound-docs skill has 5 files, at least 3 of which need genericizing (SKILL.md, schema.yaml, yaml-schema.md). The agent-native-architecture skill has 15 files, 6 of which contain "Every Reader." That could add 9 more modified files to the count:
- compound-docs: +2 (schema.yaml, yaml-schema.md beyond SKILL.md)
- agent-native-architecture: +6 (reference files)
- resolve-pr-parallel: +1 (get-pr-comments script)
- 28 + 9 = 37

Close to 36. The discrepancy is small but should be reconciled before execution. An exact manifest of "these 36 files need modification" should be produced.

### 5H. CLAUDE.md Testing Section Becomes Stale

The current CLAUDE.md (line 45) says "Verify graceful degradation without beads/PAL/compound-engineering." After the fork, compound-engineering is no longer a dependency. The testing instructions need to be rewritten to say "Verify bundled agents are discovered correctly" instead. This is listed in the repo-research findings (line 471) but could easily be forgotten since CLAUDE.md is a development guide, not a user-facing file.

---

## 6. Additional Observations

### 6A. The "22 agents" Count Needs Clarification

The brainstorm lists 22 "new" agents (items 2-22 plus spec-flow-analyzer at 20, but numbering goes to 22). The source inventory lists 21 agents to port (Part 1 header says "21 to port"). The brainstorm says "22 new (23 total with existing context-researcher)." The source inventory table has 21 rows. The discrepancy: the brainstorm counts git-history-analyzer (#6) which the source inventory also lists (#5), so both should have the same count.

Recount from brainstorm: items 2 through 22 = 21 new agents (context-researcher is #1 and already exists). But the brainstorm header says "22 new." Either the brainstorm miscounts, or there is a 22nd agent not listed. Verify against the source to resolve.

Actually, looking more carefully at the brainstorm: it lists numbers 2-22, which is 21 items. But the header says "22 new (23 total)." This is an off-by-one error in the brainstorm. It should say "21 new (22 total)" OR there is a missing 22nd agent not enumerated.

The source-inventory says "21 to port" with 21 rows. The brainstorm's "22" appears to be wrong. The correct count is **21 new agents, 22 total including context-researcher**.

### 6B. The spec-flow-analyzer Discovery in plan.md

The plan.md command dispatches `spec-flow-analyzer` (line 62 of repo-research.md). This agent is currently in compound-engineering's `agents/workflow/` directory. After the fork, it will be in compound-workflows' `agents/workflow/`. The plan.md command dispatches it by name with an inline role description -- it does NOT reference a file path. So the name-based dispatch should resolve to the bundled agent after the fork. No file path change needed in plan.md for this agent. But verify this assumption in testing.

### 6C. No Rollback Plan

If the fork is partially executed and something goes wrong (e.g., context exhaustion mid-port, incorrect modifications discovered after committing), there is no documented rollback. The commit strategy in 5B provides natural rollback points (revert individual commits), but the spec should explicitly note: "If the port fails partway through, `git checkout .` reverts all uncommitted changes. If committed, `git revert` individual commits in reverse order."

---

## Summary of Findings by Severity

### CRITICAL (Plan will fail or produce wrong outcome if not addressed)

1. **deepen-plan discovery logic is more complex than "replace name"** (5E) -- The filter in lines 104-106 needs redesign, not just a string replacement. Without this, deepen-plan will not find bundled agents.
2. **No automated verification strategy** (3A) -- 91 files with 36 modifications and no automated checks means errors will ship.
3. **Context exhaustion during port** (5A) -- The port itself needs to be a resumable workflow with a manifest, or it will fail mid-execution.
4. **orchestrating-swarms requires per-instance review** (5D) -- Bulk find-replace will produce incorrect results for dropped agents.

### SERIOUS (Significant risk that should be addressed before implementation)

5. **Agent count discrepancy: 21 vs. 22** (6A) -- Off-by-one in the brainstorm. Resolve before starting.
6. **File modification count: 28 vs. 36** (5G) -- The claimed 36 is close but not reconciled. Produce an exact manifest.
7. **No canonical genericization table** (5C) -- Inconsistent replacements will degrade agent quality.
8. **Setup command/skill interaction undefined** (1F) -- Two mechanisms that both configure the same thing, unclear which takes precedence.
9. **No functional smoke test plan** (3B) -- Mechanical correctness does not guarantee functional correctness.
10. **Script file permissions** (2F) -- Silent breakage for git-worktree, resolve-pr-parallel, gemini-imagegen, skill-creator.
11. **Commit strategy needed** (5B) -- A single-commit 91-file change is unreviewable.

### MINOR (Worth noting for awareness)

12. **NOTICE file timing** (4E) -- Create early, not as cleanup.
13. **"Every Reader" decision pending** (2E) -- Make the call before implementation.
14. **Skill cross-reference path resolution** (2C) -- Verify in installed/cached layout.
15. **Python requirements.txt dependency** (2G) -- Document in README or setup.
16. **CLAUDE.md testing section** (5H) -- Update during meta-file phase.
17. **No rollback plan** (6C) -- Document git-based recovery steps.

---

## Recommended Phase Ordering

```
Phase 0: Preparation
  - Resolve count discrepancies (21 vs 22 agents, 28 vs 36 modifications)
  - Produce exact file manifest with source -> destination mapping
  - Define canonical genericization replacement table
  - Decide on "Every Reader" -- genericize or leave as-is
  - Clarify setup command vs. setup skill interaction
  - Design the deepen-plan discovery logic update

Phase 1: Copy (Single Commit)
  - Create directory structure (agents/review/, agents/workflow/)
  - Copy all 91 files preserving permissions (cp -p)
  - Create NOTICE file
  - Verify: file count, byte-identical for unmodified files

Phase 2: Rename (Single Commit)
  - Rename 3 agent files
  - Update YAML frontmatter name: fields
  - Update persona text within the 3 files
  - Verify: no "Kieran" or "Julik" references in renamed files

Phase 3: Genericize (Single Commit)
  - Apply canonical replacement table to all files
  - Handle orchestrating-swarms manually (per-instance review)
  - Handle agent-native-architecture reference files (if decision is to genericize)
  - Verify: grep for all company-specific terms returns zero

Phase 4: Command Updates (Single Commit)
  - Update review.md (remove Rails refs, update renamed agent refs)
  - Update deepen-plan.md (rewrite discovery logic)
  - Update compound.md (genericize examples)
  - Update plan.md (genericize examples)
  - Update setup.md (rewrite with conflict detection)
  - Verify: grep for "compound-engineering" returns zero (except NOTICE)

Phase 5: Meta-Files (Single Commit)
  - Update plugin.json (version, description, keywords)
  - Update README.md (dependency table, counts, attribution)
  - Update CHANGELOG.md (add v1.1.0 entry)
  - Update CLAUDE.md (directory structure, testing instructions)
  - Verify: all counts match reality

Phase 6: Functional Verification
  - Run smoke tests (3B list above)
  - Run automated grep checks (3A list above)
  - Verify line counts for unmodified files (3D)
  - Validate YAML frontmatter on all agent/skill files (3E)
```
