# Source Inventory: compound-engineering Agents & Skills

Source plugin: `/Users/adamf/.claude/plugins/marketplaces/every-marketplace/plugins/compound-engineering/`

---

## Part 1: Agents (21 to port)

### Research Agents (5)

#### 1. repo-research-analyst.md
- **Lines:** 136
- **Model:** `inherit`
- **Company-specific content:** NONE
- **Cross-references:** None to other agents
- **Genericize effort:** NONE -- fully generic already

#### 2. learnings-researcher.md
- **Lines:** 265
- **Model:** `haiku`
- **Company-specific content:**
  - Line 37: `"BriefSystem", "EmailProcessing"` used as example module names in keyword extraction
  - Line 156: References `../../skills/compound-docs/references/yaml-schema.md` (relative path to compound-docs skill)
  - Lines 158-176: component values include `email_processing`, `brief_system` -- these are enum examples from compound-docs schema
  - Lines 261-263: Integration points reference `/workflows:plan`, `/deepen-plan`
- **Cross-references:** compound-docs skill (yaml-schema.md)
- **Genericize effort:** MEDIUM -- replace BriefSystem/EmailProcessing examples with generic ones; update skill path references to compound-workflows; update workflow references

#### 3. best-practices-researcher.md
- **Lines:** 127
- **Model:** `inherit`
- **Company-specific content:**
  - Line 39-41: Skill mapping references `dhh-rails-style`, `andrew-kane-gem-writer`, `dspy-ruby` (not being ported), `every-style-editor` (not being ported), `compound-docs`, `frontend-design`, `agent-native-architecture`, `create-agent-skills`, `gemini-imagegen`, `git-worktree`
- **Cross-references:** References many skills by name (skill discovery logic)
- **Genericize effort:** LOW -- remove references to skills NOT being ported (dhh-rails-style, andrew-kane-gem-writer, dspy-ruby, every-style-editor); keep references to skills that ARE being ported but update the discovery text

#### 4. framework-docs-researcher.md
- **Lines:** 107
- **Model:** `inherit`
- **Company-specific content:** NONE
- **Cross-references:** None
- **Genericize effort:** NONE -- fully generic

#### 5. git-history-analyzer.md
- **Lines:** 59
- **Model:** `inherit`
- **Company-specific content:**
  - Line 59: `compound-engineering pipeline artifacts created by /workflows:plan` -- references compound-engineering by name
- **Cross-references:** References `/workflows:plan`
- **Genericize effort:** LOW -- rename "compound-engineering" to "compound-workflows" in the one reference

### Review Agents (13)

#### 6. code-simplicity-reviewer.md
- **Lines:** 101
- **Model:** `inherit`
- **Company-specific content:**
  - Line 51: `compound-engineering pipeline artifacts created by /workflows:plan and used as living documents by /workflows:work` -- references compound-engineering by name
- **Cross-references:** References `/workflows:plan`, `/workflows:work`
- **Genericize effort:** LOW -- rename "compound-engineering" to "compound-workflows"

#### 7. kieran-typescript-reviewer.md (rename to: typescript-reviewer.md)
- **Lines:** 125
- **Model:** `inherit`
- **Company-specific content:**
  - Lines 11, 13, 21, 23, 32, 36: "Kieran" persona name used throughout (examples, commentary, main persona definition)
  - "You are Kieran, a super senior TypeScript developer" -- persona identity
- **Cross-references:** None
- **Genericize effort:** MEDIUM -- Remove "Kieran" persona name; rename file to `typescript-reviewer.md`; replace "Kieran" with generic phrasing like "the typescript-reviewer agent"; update persona to "You are a super senior TypeScript developer"

#### 8. kieran-python-reviewer.md (rename to: python-reviewer.md)
- **Lines:** 134
- **Model:** `inherit`
- **Company-specific content:**
  - Lines 11, 13, 21, 23, 32, 36: "Kieran" persona name used throughout (identical pattern to TS reviewer)
  - "You are Kieran, a super senior Python developer" -- persona identity
- **Cross-references:** None
- **Genericize effort:** MEDIUM -- same as typescript-reviewer: remove "Kieran", rename file, update persona

#### 9. pattern-recognition-specialist.md
- **Lines:** 73
- **Model:** `inherit`
- **Company-specific content:** NONE
- **Cross-references:** None
- **Genericize effort:** NONE -- fully generic

#### 10. architecture-strategist.md
- **Lines:** 68
- **Model:** `inherit`
- **Company-specific content:** NONE
- **Cross-references:** None
- **Genericize effort:** NONE -- fully generic

#### 11. security-sentinel.md
- **Lines:** 115
- **Model:** `inherit`
- **Company-specific content:** NONE
- **Cross-references:** None
- **Genericize effort:** NONE -- fully generic

#### 12. performance-oracle.md
- **Lines:** 138
- **Model:** `inherit`
- **Company-specific content:** NONE
- **Cross-references:** None
- **Genericize effort:** NONE -- fully generic

#### 13. agent-native-reviewer.md
- **Lines:** 262
- **Model:** `inherit`
- **Company-specific content:** NONE (uses "Every" only in generic phrasing like "Every UI action")
- **Cross-references:** None
- **Genericize effort:** NONE -- fully generic

#### 14. data-migration-expert.md
- **Lines:** 113
- **Model:** `inherit`
- **Company-specific content:** NONE
- **Cross-references:** None
- **Genericize effort:** NONE -- fully generic

#### 15. deployment-verification-agent.md
- **Lines:** 175
- **Model:** `inherit`
- **Company-specific content:** NONE
- **Cross-references:** Mentions `data-migration-expert` agent (line 172) -- this agent is also being ported
- **Genericize effort:** NONE -- fully generic

#### 16. julik-frontend-races-reviewer.md (rename to: frontend-races-reviewer.md)
- **Lines:** 222
- **Model:** `inherit`
- **Company-specific content:**
  - Lines 11, 13, 21, 26: "Julik" persona name used throughout
  - "You are Julik, a seasoned full-stack developer" -- persona identity
  - Line 215: Communication style references "Eastern-European and Dutch (directness)" -- tied to persona
- **Cross-references:** None
- **Genericize effort:** MEDIUM -- Remove "Julik" persona name; rename file to `frontend-races-reviewer.md`; update persona to "You are a seasoned full-stack developer"; keep the communication style guidance but remove cultural attribution

#### 17. data-integrity-guardian.md
- **Lines:** 86
- **Model:** `inherit`
- **Company-specific content:** NONE
- **Cross-references:** None
- **Genericize effort:** NONE -- fully generic

#### 18. schema-drift-detector.md
- **Lines:** 155
- **Model:** `inherit`
- **Company-specific content:** NONE (uses "Every" only in generic checklist: "Every new column")
- **Cross-references:** References `data-migration-expert` and `data-integrity-guardian` agents (line 150-153) -- both being ported
- **Genericize effort:** NONE -- fully generic

### Workflow Agents (3)

#### 19. spec-flow-analyzer.md
- **Lines:** 135
- **Model:** `inherit`
- **Company-specific content:** NONE
- **Cross-references:** None
- **Genericize effort:** NONE -- fully generic

#### 20. bug-reproduction-validator.md
- **Lines:** 83
- **Model:** `inherit`
- **Company-specific content:** NONE
- **Cross-references:** References `agent-browser` skill (line 37)
- **Genericize effort:** NONE -- fully generic (agent-browser skill is being ported)

#### 21. pr-comment-resolver.md
- **Lines:** 85
- **Model:** `inherit`
- **Company-specific content:** NONE
- **Cross-references:** None
- **Genericize effort:** NONE -- fully generic

---

## Agents Summary Table

| # | Agent | Lines | Model | Genericize | Rename? |
|---|-------|-------|-------|------------|---------|
| 1 | repo-research-analyst | 136 | inherit | NONE | No |
| 2 | learnings-researcher | 265 | haiku | MEDIUM | No |
| 3 | best-practices-researcher | 127 | inherit | LOW | No |
| 4 | framework-docs-researcher | 107 | inherit | NONE | No |
| 5 | git-history-analyzer | 59 | inherit | LOW | No |
| 6 | code-simplicity-reviewer | 101 | inherit | LOW | No |
| 7 | kieran-typescript-reviewer | 125 | inherit | MEDIUM | YES -> typescript-reviewer |
| 8 | kieran-python-reviewer | 134 | inherit | MEDIUM | YES -> python-reviewer |
| 9 | pattern-recognition-specialist | 73 | inherit | NONE | No |
| 10 | architecture-strategist | 68 | inherit | NONE | No |
| 11 | security-sentinel | 115 | inherit | NONE | No |
| 12 | performance-oracle | 138 | inherit | NONE | No |
| 13 | agent-native-reviewer | 262 | inherit | NONE | No |
| 14 | data-migration-expert | 113 | inherit | NONE | No |
| 15 | deployment-verification-agent | 175 | inherit | NONE | No |
| 16 | julik-frontend-races-reviewer | 222 | inherit | MEDIUM | YES -> frontend-races-reviewer |
| 17 | data-integrity-guardian | 86 | inherit | NONE | No |
| 18 | schema-drift-detector | 155 | inherit | NONE | No |
| 19 | spec-flow-analyzer | 135 | inherit | NONE | No |
| 20 | bug-reproduction-validator | 83 | inherit | NONE | No |
| 21 | pr-comment-resolver | 85 | inherit | NONE | No |

**Model breakdown:** 20 use `inherit`, 1 uses `haiku` (learnings-researcher)
**Genericize breakdown:** 13 NONE, 3 LOW, 5 MEDIUM, 0 HIGH
**Renames:** 3 agents need renaming (kieran-typescript -> typescript, kieran-python -> python, julik-frontend-races -> frontend-races)

---

## Part 2: Skills (14 to port)

### 1. brainstorming/
- **SKILL.md lines:** 191
- **Subdirectories:** NONE (SKILL.md only)
- **Company-specific content:** NONE
- **Cross-references:** References `/workflows:plan` (line 134, 143, 190)
- **Genericize effort:** LOW -- update workflow references from compound-engineering namespace to compound-workflows
- **Files to copy:** `SKILL.md`

### 2. document-review/
- **SKILL.md lines:** 88
- **Subdirectories:** NONE (SKILL.md only)
- **Company-specific content:** NONE
- **Cross-references:** References `/workflows:brainstorm`, `/workflows:plan` (line 39)
- **Genericize effort:** LOW -- update workflow references
- **Files to copy:** `SKILL.md`

### 3. file-todos/
- **SKILL.md lines:** 253
- **Subdirectories:** `assets/` (1 file)
- **Company-specific content:** NONE
- **Cross-references:** References `/workflows:review`, `/resolve_pr_parallel`, `/resolve_todo_parallel`, `/triage` (line 188-193)
- **Genericize effort:** LOW -- update workflow/command references
- **Files to copy:**
  - `SKILL.md`
  - `assets/todo-template.md`

### 4. git-worktree/
- **SKILL.md lines:** 300
- **Subdirectories:** `scripts/` (1 file)
- **Company-specific content:** NONE
- **Cross-references:** References `/workflows:review`, `/workflows:work` (lines 41-43, 208-231); uses `${CLAUDE_PLUGIN_ROOT}` path variable throughout
- **Genericize effort:** NONE -- uses `${CLAUDE_PLUGIN_ROOT}` which auto-resolves; fully generic
- **Files to copy:**
  - `SKILL.md`
  - `scripts/worktree-manager.sh`

### 5. compound-docs/
- **SKILL.md lines:** 511
- **Subdirectories:** `assets/` (2 files), `references/` (1 file), plus `schema.yaml` at root
- **Company-specific content:**
  - Line 141: `missing-include-BriefSystem-20251110.md` -- example filename
  - Line 142: `parameter-not-saving-state-EmailProcessing-20251110.md` -- example filename
  - Lines 158-170: Component enum values include `email_processing`, `brief_system` -- domain-specific
  - Lines 455-488: Full example scenario uses "Brief System", "BriefSystem", "email threads", "Brief model" -- Every-specific domain
  - References yaml-schema.md which contains `EmailProcessing` as example module (line 7 of that file)
- **Cross-references:** References `/compound` command, `skill-creator/scripts/init_skill.py`
- **Genericize effort:** MEDIUM -- replace BriefSystem/EmailProcessing examples with generic ones (e.g., "UserService", "PaymentProcessing"); update component enum examples; rewrite example scenario with generic domain
- **Files to copy:**
  - `SKILL.md`
  - `schema.yaml`
  - `assets/critical-pattern-template.md`
  - `assets/resolution-template.md`
  - `references/yaml-schema.md`

### 6. setup/
- **SKILL.md lines:** 169
- **Subdirectories:** NONE (SKILL.md only)
- **Company-specific content:**
  - Lines 3, 9, 13, 137, 159: `compound-engineering.local.md` -- config filename uses old plugin name
  - Line 8: `# Compound Engineering Setup` -- title uses old name
  - Line 58-61: References `kieran-rails-reviewer`, `dhh-rails-reviewer` (not being ported), `kieran-python-reviewer`, `kieran-typescript-reviewer` -- agent names that need updating
- **Cross-references:** References `/workflows:review`, `/workflows:work`; references multiple review agent names
- **Genericize effort:** HIGH -- rename `compound-engineering.local.md` to `compound-workflows.local.md`; update title to "Compound Workflows Setup"; replace `kieran-*` agent names with renamed versions (`typescript-reviewer`, `python-reviewer`); remove `dhh-rails-reviewer` / `kieran-rails-reviewer` references (not porting Rails-specific agents); update default agent lists
- **Files to copy:** `SKILL.md`

### 7. gemini-imagegen/
- **SKILL.md lines:** 237
- **Subdirectories:** `scripts/` (5 files), plus `requirements.txt`
- **Company-specific content:** NONE
- **Cross-references:** None
- **Genericize effort:** NONE -- fully generic
- **Files to copy:**
  - `SKILL.md`
  - `requirements.txt`
  - `scripts/compose_images.py`
  - `scripts/edit_image.py`
  - `scripts/gemini_images.py`
  - `scripts/generate_image.py`
  - `scripts/multi_turn_chat.py`

### 8. agent-browser/
- **SKILL.md lines:** 224
- **Subdirectories:** NONE (SKILL.md only)
- **Company-specific content:** NONE
- **Cross-references:** None
- **Genericize effort:** NONE -- fully generic
- **Files to copy:** `SKILL.md`

### 9. orchestrating-swarms/
- **SKILL.md lines:** ~1580 (large single file, 47,797 bytes)
- **Subdirectories:** NONE (SKILL.md only)
- **Company-specific content:**
  - Lines 315-355+: Extensive references to `compound-engineering:review:*`, `compound-engineering:research:*`, `compound-engineering:workflow:*`, `compound-engineering:design:*` agent type prefixes throughout examples
  - Line 335: References `compound-engineering:review:kieran-rails-reviewer` (not being ported)
  - Multiple instances of `compound-engineering` as plugin namespace in `subagent_type` strings
- **Cross-references:** References many agents by fully-qualified compound-engineering plugin paths
- **Genericize effort:** HIGH -- bulk find-replace `compound-engineering` -> `compound-workflows` in all subagent_type references; remove references to agents not being ported (kieran-rails-reviewer, figma-design-sync); update kieran-* references to new names; update all example code blocks
- **Files to copy:** `SKILL.md`

### 10. create-agent-skills/
- **SKILL.md lines:** 276
- **Subdirectories:** `references/` (13 files), `templates/` (2 files), `workflows/` (10 files)
- **Company-specific content:** NONE in SKILL.md; some reference files use "Every" in generic English sense only
- **Cross-references:** References official Claude Code docs (external URLs)
- **Genericize effort:** NONE -- fully generic
- **Files to copy:**
  - `SKILL.md`
  - `references/api-security.md`
  - `references/be-clear-and-direct.md`
  - `references/best-practices.md`
  - `references/common-patterns.md`
  - `references/core-principles.md`
  - `references/executable-code.md`
  - `references/iteration-and-testing.md`
  - `references/official-spec.md`
  - `references/recommended-structure.md`
  - `references/skill-structure.md`
  - `references/using-scripts.md`
  - `references/using-templates.md`
  - `references/workflows-and-validation.md`
  - `templates/router-skill.md`
  - `templates/simple-skill.md`
  - `workflows/add-reference.md`
  - `workflows/add-script.md`
  - `workflows/add-template.md`
  - `workflows/add-workflow.md`
  - `workflows/audit-skill.md`
  - `workflows/create-domain-expertise-skill.md`
  - `workflows/create-new-skill.md`
  - `workflows/get-guidance.md`
  - `workflows/upgrade-to-router.md`
  - `workflows/verify-skill.md`

### 11. agent-native-architecture/
- **SKILL.md lines:** 436
- **Subdirectories:** `references/` (14 files)
- **Company-specific content:**
  - In reference files only (not SKILL.md itself):
    - `references/files-universal-interface.md` line 99: "Reading assistant for the Every app"
    - `references/shared-workspace-architecture.md` lines 476-478: "Real-World Example: Every Reader"
    - `references/dynamic-context-injection.md` lines 268-270: "Real-World Example: Every Reader"
    - `references/action-parity-discipline.md` line 340: "Every Reader had a feed..."
    - `references/architecture-patterns.md` line 110: "Every Reader feedback bot"
    - `references/system-prompt-design.md` line 165: "Every's feedback collection assistant", "Every Reader iOS app"
- **Cross-references:** None to other plugin agents
- **Genericize effort:** MEDIUM -- The SKILL.md itself is generic; only reference files contain "Every Reader" app as case study examples. These could be left as-is (they are illustrative examples, not instructions) or genericized to "a reading app" / "BookReader app"
- **Files to copy:**
  - `SKILL.md`
  - `references/action-parity-discipline.md`
  - `references/agent-execution-patterns.md`
  - `references/agent-native-testing.md`
  - `references/architecture-patterns.md`
  - `references/dynamic-context-injection.md`
  - `references/files-universal-interface.md`
  - `references/from-primitives-to-domain-tools.md`
  - `references/mcp-tool-design.md`
  - `references/mobile-patterns.md`
  - `references/product-implications.md`
  - `references/refactoring-to-prompt-native.md`
  - `references/self-modification.md`
  - `references/shared-workspace-architecture.md`
  - `references/system-prompt-design.md`

### 12. resolve-pr-parallel/
- **SKILL.md lines:** 90
- **Subdirectories:** `scripts/` (2 files)
- **Company-specific content:**
  - `scripts/get-pr-comments` line 8: `EveryInc/cora` as example repo in usage string
- **Cross-references:** References `pr-comment-resolver` agent (being ported)
- **Genericize effort:** LOW -- change `EveryInc/cora` example to `owner/repo` in script
- **Files to copy:**
  - `SKILL.md`
  - `scripts/get-pr-comments`
  - `scripts/resolve-pr-thread`

### 13. skill-creator/
- **SKILL.md lines:** 211
- **Subdirectories:** `scripts/` (3 files)
- **Company-specific content:** NONE
- **Cross-references:** None
- **Genericize effort:** NONE -- fully generic
- **Files to copy:**
  - `SKILL.md`
  - `scripts/init_skill.py`
  - `scripts/package_skill.py`
  - `scripts/quick_validate.py`

### 14. frontend-design/
- **SKILL.md lines:** 43
- **Subdirectories:** NONE (SKILL.md only)
- **Company-specific content:** NONE
- **Cross-references:** None
- **Genericize effort:** NONE -- fully generic
- **Files to copy:** `SKILL.md`

---

## Skills Summary Table

| # | Skill | SKILL.md Lines | Subdirs | Total Files | Genericize |
|---|-------|---------------|---------|-------------|------------|
| 1 | brainstorming | 191 | -- | 1 | LOW |
| 2 | document-review | 88 | -- | 1 | LOW |
| 3 | file-todos | 253 | assets/ | 2 | LOW |
| 4 | git-worktree | 300 | scripts/ | 2 | NONE |
| 5 | compound-docs | 511 | assets/, references/ | 5 | MEDIUM |
| 6 | setup | 169 | -- | 1 | HIGH |
| 7 | gemini-imagegen | 237 | scripts/ | 7 | NONE |
| 8 | agent-browser | 224 | -- | 1 | NONE |
| 9 | orchestrating-swarms | ~1580 | -- | 1 | HIGH |
| 10 | create-agent-skills | 276 | references/, templates/, workflows/ | 26 | NONE |
| 11 | agent-native-architecture | 436 | references/ | 15 | MEDIUM |
| 12 | resolve-pr-parallel | 90 | scripts/ | 3 | LOW |
| 13 | skill-creator | 211 | scripts/ | 4 | NONE |
| 14 | frontend-design | 43 | -- | 1 | NONE |

**Total files to copy across all skills:** 70
**Genericize breakdown:** 6 NONE, 4 LOW, 2 MEDIUM, 2 HIGH

---

## Part 3: Complete File Manifest for Skills with Subdirectories

### compound-docs/ (5 files)
```
compound-docs/SKILL.md
compound-docs/schema.yaml
compound-docs/assets/critical-pattern-template.md
compound-docs/assets/resolution-template.md
compound-docs/references/yaml-schema.md
```

### create-agent-skills/ (26 files)
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

### agent-native-architecture/ (15 files)
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

### git-worktree/ (2 files)
```
git-worktree/SKILL.md
git-worktree/scripts/worktree-manager.sh
```

### resolve-pr-parallel/ (3 files)
```
resolve-pr-parallel/SKILL.md
resolve-pr-parallel/scripts/get-pr-comments
resolve-pr-parallel/scripts/resolve-pr-thread
```

### file-todos/ (2 files)
```
file-todos/SKILL.md
file-todos/assets/todo-template.md
```

### skill-creator/ (4 files)
```
skill-creator/SKILL.md
skill-creator/scripts/init_skill.py
skill-creator/scripts/package_skill.py
skill-creator/scripts/quick_validate.py
```

### gemini-imagegen/ (7 files)
```
gemini-imagegen/SKILL.md
gemini-imagegen/requirements.txt
gemini-imagegen/scripts/compose_images.py
gemini-imagegen/scripts/edit_image.py
gemini-imagegen/scripts/gemini_images.py
gemini-imagegen/scripts/generate_image.py
gemini-imagegen/scripts/multi_turn_chat.py
```

---

## Part 4: Genericization Work Summary

### HIGH priority (do first -- affects discoverability and naming)

1. **setup skill** -- rename `compound-engineering.local.md` to `compound-workflows.local.md`; update title; replace agent name references (kieran-* -> renamed, remove Rails-specific); update default agent lists
2. **orchestrating-swarms skill** -- bulk replace `compound-engineering:` prefix to `compound-workflows:` in ~30+ subagent_type strings; remove references to agents not being ported; update agent names

### MEDIUM priority (examples and personas)

3. **kieran-typescript-reviewer** -> **typescript-reviewer** -- remove Kieran persona; update filename and `name` field
4. **kieran-python-reviewer** -> **python-reviewer** -- remove Kieran persona; update filename and `name` field
5. **julik-frontend-races-reviewer** -> **frontend-races-reviewer** -- remove Julik persona; update filename and `name` field
6. **learnings-researcher** -- replace BriefSystem/EmailProcessing examples; update skill path refs
7. **compound-docs skill** -- replace BriefSystem/EmailProcessing examples in SKILL.md, schema.yaml, and yaml-schema.md
8. **agent-native-architecture skill** -- optionally genericize "Every Reader" case study examples in 6 reference files

### LOW priority (minor path/reference updates)

9. **best-practices-researcher** -- remove references to skills not being ported from discovery mapping
10. **git-history-analyzer** -- rename compound-engineering to compound-workflows in one line
11. **code-simplicity-reviewer** -- rename compound-engineering to compound-workflows in one line
12. **brainstorming skill** -- update workflow namespace references
13. **document-review skill** -- update workflow namespace references
14. **file-todos skill** -- update workflow/command references
15. **resolve-pr-parallel skill** -- change `EveryInc/cora` to `owner/repo` in script

### NO changes needed (13 agents + 6 skills = 19 files)

Agents: repo-research-analyst, framework-docs-researcher, pattern-recognition-specialist, architecture-strategist, security-sentinel, performance-oracle, agent-native-reviewer, data-migration-expert, deployment-verification-agent, data-integrity-guardian, schema-drift-detector, spec-flow-analyzer, bug-reproduction-validator, pr-comment-resolver

Skills: git-worktree, gemini-imagegen, agent-browser, create-agent-skills, skill-creator, frontend-design
