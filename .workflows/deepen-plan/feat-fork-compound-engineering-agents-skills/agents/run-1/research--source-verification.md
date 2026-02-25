# Source Verification: compound-engineering 2.35.2

**Date:** 2026-02-25
**Source path:** `~/.claude/plugins/cache/every-marketplace/compound-engineering/2.35.2/`
**Inventory:** `.workflows/plan-research/fork-compound-engineering-agents-skills/agents/source-inventory.md`
**Method:** Each file read via Read tool; line counts taken from final line number returned by Read.

---

## Part 1: Agent Verification (21 agents)

### Line Count Comparison

All 21 agent files exist at the 2.35.2 path. Line counts were verified by reading each file to its final line number.

| # | Agent | Inventory Lines | Actual Lines | Match? |
|---|-------|----------------|--------------|--------|
| 1 | repo-research-analyst | 136 | 136 | MATCH |
| 2 | learnings-researcher | 265 | 265 | MATCH |
| 3 | best-practices-researcher | 127 | 127 | MATCH |
| 4 | framework-docs-researcher | 107 | 107 | MATCH |
| 5 | git-history-analyzer | 59 | 59 | MATCH |
| 6 | code-simplicity-reviewer | 101 | 101 | MATCH |
| 7 | kieran-typescript-reviewer | 125 | 125 | MATCH |
| 8 | kieran-python-reviewer | 134 | 134 | MATCH |
| 9 | pattern-recognition-specialist | 73 | 73 | MATCH |
| 10 | architecture-strategist | 68 | 68 | MATCH |
| 11 | security-sentinel | 115 | 115 | MATCH |
| 12 | performance-oracle | 138 | 138 | MATCH |
| 13 | agent-native-reviewer | 262 | 262 | MATCH |
| 14 | data-migration-expert | 113 | 113 | MATCH |
| 15 | deployment-verification-agent | 175 | 175 | MATCH |
| 16 | julik-frontend-races-reviewer | 222 | 222 | MATCH |
| 17 | data-integrity-guardian | 86 | 86 | MATCH |
| 18 | schema-drift-detector | 155 | 155 | MATCH |
| 19 | spec-flow-analyzer | 135 | 135 | MATCH |
| 20 | bug-reproduction-validator | 83 | 83 | MATCH |
| 21 | pr-comment-resolver | 85 | 85 | MATCH |

**Result: All 21 agents verified. 21/21 line counts match exactly.**

### Agent File Paths (all confirmed to exist)

```
agents/research/repo-research-analyst.md
agents/research/learnings-researcher.md
agents/research/best-practices-researcher.md
agents/research/framework-docs-researcher.md
agents/research/git-history-analyzer.md
agents/review/code-simplicity-reviewer.md
agents/review/kieran-typescript-reviewer.md
agents/review/kieran-python-reviewer.md
agents/review/pattern-recognition-specialist.md
agents/review/architecture-strategist.md
agents/review/security-sentinel.md
agents/review/performance-oracle.md
agents/review/agent-native-reviewer.md
agents/review/data-migration-expert.md
agents/review/deployment-verification-agent.md
agents/review/julik-frontend-races-reviewer.md
agents/review/data-integrity-guardian.md
agents/review/schema-drift-detector.md
agents/workflow/spec-flow-analyzer.md
agents/workflow/bug-reproduction-validator.md
agents/workflow/pr-comment-resolver.md
```

---

## Part 2: Skill Verification (14 skills)

### SKILL.md Line Count Comparison

| # | Skill | Inventory Lines | Actual Lines | Match? |
|---|-------|----------------|--------------|--------|
| 1 | brainstorming | 191 | 191 | MATCH |
| 2 | document-review | 88 | 88 | MATCH |
| 3 | file-todos | 253 | 253 | MATCH |
| 4 | git-worktree | 300 | 303 | **DISCREPANCY (+3 lines)** |
| 5 | compound-docs | 511 | 511 | MATCH |
| 6 | setup | 169 | 169 | MATCH |
| 7 | gemini-imagegen | 237 | 237 | MATCH |
| 8 | agent-browser | 224 | 224 | MATCH |
| 9 | orchestrating-swarms | ~1580 | 1580 | MATCH (inventory used ~ approximation) |
| 10 | create-agent-skills | 276 | 276 | MATCH |
| 11 | agent-native-architecture | 436 | 436 | MATCH |
| 12 | resolve-pr-parallel | 90 | 90 | MATCH |
| 13 | skill-creator | 211 | 211 | MATCH |
| 14 | frontend-design | 43 | 43 | MATCH |

**Result: 13/14 SKILL.md line counts match. 1 minor discrepancy (git-worktree: 303 vs 300).**

### Complete Skill Directory Listings

#### 1. brainstorming/ (1 file)
```
brainstorming/SKILL.md
```
Matches inventory: 1 file expected, 1 file found. MATCH.

#### 2. document-review/ (1 file)
```
document-review/SKILL.md
```
Matches inventory: 1 file expected, 1 file found. MATCH.

#### 3. file-todos/ (2 files)
```
file-todos/SKILL.md
file-todos/assets/todo-template.md  (156 lines)
```
Matches inventory: 2 files expected, 2 files found. MATCH.

#### 4. git-worktree/ (2 files)
```
git-worktree/SKILL.md
git-worktree/scripts/worktree-manager.sh  (338 lines)
```
Matches inventory: 2 files expected, 2 files found. MATCH.

#### 5. compound-docs/ (5 files)
```
compound-docs/SKILL.md
compound-docs/schema.yaml  (177 lines)
compound-docs/assets/critical-pattern-template.md  (35 lines)
compound-docs/assets/resolution-template.md  (94 lines)
compound-docs/references/yaml-schema.md  (66 lines)
```
Matches inventory: 5 files expected, 5 files found. MATCH.

#### 6. setup/ (1 file)
```
setup/SKILL.md
```
Matches inventory: 1 file expected, 1 file found. MATCH.

#### 7. gemini-imagegen/ (7 files)
```
gemini-imagegen/SKILL.md
gemini-imagegen/requirements.txt  (2 lines)
gemini-imagegen/scripts/compose_images.py
gemini-imagegen/scripts/edit_image.py
gemini-imagegen/scripts/generate_image.py
gemini-imagegen/scripts/gemini_images.py
gemini-imagegen/scripts/multi_turn_chat.py
```
Matches inventory: 7 files expected, 7 files found. MATCH.

#### 8. agent-browser/ (1 file)
```
agent-browser/SKILL.md
```
Matches inventory: 1 file expected, 1 file found. MATCH.

#### 9. orchestrating-swarms/ (1 file)
```
orchestrating-swarms/SKILL.md
```
Matches inventory: 1 file expected, 1 file found. MATCH.

#### 10. create-agent-skills/ (26 files)
```
create-agent-skills/SKILL.md
create-agent-skills/references/api-security.md
create-agent-skills/references/be-clear-and-direct.md
create-agent-skills/references/best-practices.md
create-agent-skills/references/common-patterns.md
create-agent-skills/references/core-principles.md
create-agent-skills/references/executable-code.md
create-agent-skills/references/iteration-and-testing.md
create-agent-skills/references/official-spec.md
create-agent-skills/references/recommended-structure.md
create-agent-skills/references/skill-structure.md
create-agent-skills/references/using-scripts.md
create-agent-skills/references/using-templates.md
create-agent-skills/references/workflows-and-validation.md
create-agent-skills/templates/router-skill.md
create-agent-skills/templates/simple-skill.md
create-agent-skills/workflows/add-reference.md
create-agent-skills/workflows/add-script.md
create-agent-skills/workflows/add-template.md
create-agent-skills/workflows/add-workflow.md
create-agent-skills/workflows/audit-skill.md
create-agent-skills/workflows/create-domain-expertise-skill.md
create-agent-skills/workflows/create-new-skill.md
create-agent-skills/workflows/get-guidance.md
create-agent-skills/workflows/upgrade-to-router.md
create-agent-skills/workflows/verify-skill.md
```
Matches inventory: 26 files expected, 26 files found. MATCH.

#### 11. agent-native-architecture/ (15 files)
```
agent-native-architecture/SKILL.md
agent-native-architecture/references/action-parity-discipline.md
agent-native-architecture/references/agent-execution-patterns.md
agent-native-architecture/references/agent-native-testing.md
agent-native-architecture/references/architecture-patterns.md
agent-native-architecture/references/dynamic-context-injection.md
agent-native-architecture/references/files-universal-interface.md
agent-native-architecture/references/from-primitives-to-domain-tools.md
agent-native-architecture/references/mcp-tool-design.md
agent-native-architecture/references/mobile-patterns.md
agent-native-architecture/references/product-implications.md
agent-native-architecture/references/refactoring-to-prompt-native.md
agent-native-architecture/references/self-modification.md
agent-native-architecture/references/shared-workspace-architecture.md
agent-native-architecture/references/system-prompt-design.md
```
Matches inventory: 15 files expected, 15 files found. MATCH.

#### 12. resolve-pr-parallel/ (3 files)
```
resolve-pr-parallel/SKILL.md
resolve-pr-parallel/scripts/get-pr-comments
resolve-pr-parallel/scripts/resolve-pr-thread
```
Matches inventory: 3 files expected, 3 files found. MATCH.

#### 13. skill-creator/ (4 files)
```
skill-creator/SKILL.md
skill-creator/scripts/init_skill.py
skill-creator/scripts/package_skill.py
skill-creator/scripts/quick_validate.py
```
Matches inventory: 4 files expected, 4 files found. MATCH.

#### 14. frontend-design/ (1 file)
```
frontend-design/SKILL.md
```
Matches inventory: 1 file expected, 1 file found. MATCH.

**Skill file count total: 70 files expected, 70 files found. MATCH.**

---

## Part 3: NEW Files in 2.35.2 NOT in the Fork Plan

### Agents NOT Being Ported (8 agents found in source, not in the 21-agent list)

| Agent | Category | Path | Reason for Exclusion |
|-------|----------|------|---------------------|
| `dhh-rails-reviewer.md` | review | `agents/review/dhh-rails-reviewer.md` | Rails-specific, not ported |
| `kieran-rails-reviewer.md` | review | `agents/review/kieran-rails-reviewer.md` | Rails-specific, not ported |
| `design-implementation-reviewer.md` | design | `agents/design/design-implementation-reviewer.md` | Design category not ported |
| `design-iterator.md` | design | `agents/design/design-iterator.md` | Design category not ported |
| `figma-design-sync.md` | design | `agents/design/figma-design-sync.md` | Design category not ported |
| `ankane-readme-writer.md` | docs | `agents/docs/ankane-readme-writer.md` | Docs category not ported |
| `every-style-editor.md` | workflow | `agents/workflow/every-style-editor.md` | Company-specific, not ported |
| `lint.md` | workflow | `agents/workflow/lint.md` | **Not mentioned in plan** |

**Total agents in 2.35.2 source: 29 agents**
- 21 being ported (per plan)
- 8 excluded (7 documented in plan/brainstorm + 1 undocumented)

**DISCREPANCY: `lint.md` is a workflow agent in 2.35.2 that was not mentioned in the source inventory or the plan.** It was not flagged as excluded or considered for porting. This is a low-risk omission -- lint is likely project-specific -- but should be consciously acknowledged in the plan.

### Skills NOT Being Ported (5 skills found in source, not in the 14-skill list)

| Skill | Path | Files | Reason for Exclusion |
|-------|------|-------|---------------------|
| `dhh-rails-style` | `skills/dhh-rails-style/` | 7 files (SKILL.md + 6 references) | Rails-specific, not ported |
| `dspy-ruby` | `skills/dspy-ruby/` | 8 files (SKILL.md + 3 assets + 4 references) | Ruby-specific, not ported |
| `andrew-kane-gem-writer` | `skills/andrew-kane-gem-writer/` | 6 files (SKILL.md + 5 references) | Ruby-specific, not ported |
| `every-style-editor` | `skills/every-style-editor/` | 2 files (SKILL.md + 1 reference) | Company-specific, not ported |
| `rclone` | `skills/rclone/` | 2 files (SKILL.md + 1 script) | **Not mentioned in plan** |

**Total skills in 2.35.2 source: 19 skills (96 files)**
- 14 being ported (per plan, 70 files)
- 5 excluded (4 documented + 1 undocumented)

**DISCREPANCY: `rclone` skill is in 2.35.2 but was not mentioned in the source inventory or the plan.** Contains SKILL.md + scripts/check_setup.sh (2 files). Should be consciously acknowledged in the plan.

### Full Source File Counts

| Category | Total in 2.35.2 | Being Ported | Excluded |
|----------|-----------------|--------------|----------|
| agents/ | 29 | 21 | 8 |
| skills/ (directories) | 19 | 14 | 5 |
| skills/ (total files) | 96 | 70 | 26 |

---

## Part 4: Discrepancy Summary

### Line Count Discrepancies

| Item | Inventory | Actual | Delta | Severity |
|------|-----------|--------|-------|----------|
| git-worktree/SKILL.md | 300 | 303 | +3 | LOW |

All other files (20 agents + 13 skills) match exactly.

### Files Not Accounted for in Plan

| Item | Type | Risk |
|------|------|------|
| `agents/workflow/lint.md` | Agent | LOW -- likely project-specific lint agent. Should be reviewed to confirm it is not a useful generic utility. |
| `skills/rclone/` | Skill (2 files) | LOW -- rclone is a file sync tool. May not be relevant for compound-workflows. Should be reviewed once. |

### Confirmed Exclusions (documented in plan/brainstorm, verified present in source)

**Agents (7 documented exclusions):**
- `dhh-rails-reviewer.md` -- Rails-specific
- `kieran-rails-reviewer.md` -- Rails-specific
- `design-implementation-reviewer.md` -- Design category
- `design-iterator.md` -- Design category
- `figma-design-sync.md` -- Design category
- `ankane-readme-writer.md` -- Docs category
- `every-style-editor.md` -- Company-specific (Every)

**Skills (4 documented exclusions):**
- `dhh-rails-style/` -- Rails-specific
- `dspy-ruby/` -- Ruby-specific
- `andrew-kane-gem-writer/` -- Ruby-specific
- `every-style-editor/` -- Company-specific (Every)

---

## Part 5: Content Spot Checks

### Agent Model Fields Verified

| Agent | Expected Model | Actual Model | Match? |
|-------|---------------|--------------|--------|
| learnings-researcher | haiku | haiku | MATCH |
| repo-research-analyst | inherit | inherit | MATCH |
| kieran-typescript-reviewer | inherit | inherit | MATCH |
| agent-native-reviewer | inherit | inherit | MATCH |
| performance-oracle | inherit | inherit | MATCH |

**Confirmed: 20 agents use `inherit`, 1 uses `haiku` (learnings-researcher). Matches inventory.**

### Agent Persona Content Verified

- **kieran-typescript-reviewer.md line 36:** "You are Kieran, a super senior TypeScript developer" -- CONFIRMED present, needs removal per plan
- **kieran-python-reviewer.md line 36:** "You are Kieran, a super senior Python developer" -- CONFIRMED present, needs removal per plan
- **julik-frontend-races-reviewer.md line 26:** "You are Julik, a seasoned full-stack developer" -- CONFIRMED present, needs removal per plan
- **julik-frontend-races-reviewer.md line 215:** "Eastern-European and Dutch (directness)" -- CONFIRMED present, needs genericization per plan

### Company-Specific Content Verified

- **git-history-analyzer.md line 59:** "compound-engineering pipeline artifacts created by /workflows:plan" -- CONFIRMED
- **code-simplicity-reviewer.md line 51:** "compound-engineering pipeline artifacts created by /workflows:plan and used as living documents by /workflows:work" -- CONFIRMED
- **learnings-researcher.md line 37:** "BriefSystem", "EmailProcessing" -- CONFIRMED
- **learnings-researcher.md line 156:** relative path `../../skills/compound-docs/references/yaml-schema.md` -- CONFIRMED
- **learnings-researcher.md lines 167-168:** "email_processing", "brief_system" component values -- CONFIRMED
- **compound-docs/schema.yaml lines 48-49:** "email_processing", "brief_system" -- CONFIRMED
- **compound-docs/references/yaml-schema.md line 7:** "EmailProcessing" -- CONFIRMED
- **setup/SKILL.md line 3:** "compound-engineering.local.md" -- CONFIRMED
- **setup/SKILL.md line 58:** References "kieran-rails-reviewer, dhh-rails-reviewer" -- CONFIRMED
- **pr-comment-resolver.md:** No company-specific content found -- CONFIRMED generic

### pr-comment-resolver.md Extra Field

The pr-comment-resolver.md has a `color: blue` field in its frontmatter (line 4) that is not mentioned in the inventory. This is cosmetic and has no impact on the fork.

---

## Part 6: Overall Verification Verdict

### Summary

| Check | Result |
|-------|--------|
| All 21 agents exist at source path | PASS |
| All 21 agent line counts match inventory | PASS (21/21 exact match) |
| All 14 skills exist at source path | PASS |
| All 14 SKILL.md line counts match inventory | PASS (13 exact, 1 off by +3) |
| All 70 skill files exist | PASS (70/70 confirmed) |
| Skill subdirectory file counts match | PASS (all 14 skills match) |
| No undocumented files in ported set | PASS |
| Excluded agents accounted for | MOSTLY -- `lint.md` not mentioned |
| Excluded skills accounted for | MOSTLY -- `rclone/` not mentioned |
| Company-specific content matches inventory | PASS (all documented references confirmed) |
| Model fields match inventory | PASS |

### Actionable Items

1. **LOW -- git-worktree SKILL.md has 303 lines vs 300 in inventory.** The 3-line difference is immaterial for the fork (the file is being copied without modification). Update inventory if desired for accuracy.

2. **LOW -- `agents/workflow/lint.md` exists in 2.35.2 but is unmentioned in the plan.** Read the file to determine if it is a generic utility worth porting or a project-specific tool to exclude. If excluded, document the exclusion in the plan.

3. **LOW -- `skills/rclone/` exists in 2.35.2 but is unmentioned in the plan.** Contains SKILL.md + scripts/check_setup.sh (2 files). Review to determine if it is worth porting. If excluded, document the exclusion in the plan.

### Confidence Level

**HIGH.** The source inventory is accurate. All 21 agents and 70 skill files are present and verified at the 2.35.2 cache path. Line counts match within tolerance. Company-specific content is located exactly where the inventory says it is. The only gaps are 2 items not mentioned in the plan (lint.md agent, rclone skill), both low-risk omissions that should be documented as conscious exclusions.

### Prior Version Note

This file supersedes an earlier verification run that reported off-by-one line counts across all agents. The earlier run likely used `wc -l` which does not count the final line if it lacks a trailing newline. This verification used the Read tool's line numbering, which counts all lines including the final one, and found exact matches with the inventory for all 21 agents.
