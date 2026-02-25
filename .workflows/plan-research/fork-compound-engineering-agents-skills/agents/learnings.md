# Learnings Research: Forking compound-engineering Agents & Skills

## Search Context

- **Query**: Plugin porting strategies, agent/skill file format requirements, Claude Code plugin structure conventions, previous issues encountered with the compound-workflows port
- **Keywords**: compound-engineering, port, fork, agent, skill, fallback, plugin structure, naming, role description, YAML frontmatter
- **Locations Searched**: docs/solutions/, docs/brainstorms/, docs/plans/, memory/, .workflows/brainstorm-research/port-gaps-compound-engineering/
- **Total Matches**: 11 files across 4 locations (docs/brainstorms: 1, docs/plans: 2, .workflows/brainstorm-research: 5, plugin root: 3)
- **Date Searched**: 2026-02-25

---

## Summary of Findings

The project has extensive prior analysis covering the exact scope of this fork. A brainstorm, three red-team critiques, a repo-level gap analysis, a context research document, and two planning documents collectively provide a detailed blueprint for the agent/skill fork. Below are the key learnings organized by topic.

---

## 1. Agent File Format Requirements

**Source**: `plugins/compound-workflows/agents/research/context-researcher.md` (the only currently ported agent)

The established format for agent definition files in this plugin:

```yaml
---
name: <agent-name>
description: "<1-2 sentence description of what the agent does and when to invoke it>"
model: haiku          # Optional. Use for cost optimization on simpler tasks.
---

<examples>
<example>
Context: <situation description>
user: "<user message>"
assistant: "<agent response>"
<commentary>Why this example matters</commentary>
</example>
</examples>

# Full system prompt follows:
## Role definition
## Methodology (numbered steps/phases)
## Output format (markdown template)
## Efficiency guidelines (DO/DON'T lists)
## Integration points with other agents
```

### Key Format Conventions
- **YAML frontmatter**: `name`, `description`, and optionally `model` fields
- **Examples block**: XML-style `<examples>/<example>` with `Context`, `user`, `assistant`, and `<commentary>` tags
- **System prompt**: Structured with clear sections, methodology phases, output templates
- **Model field**: `haiku` for cost-optimized agents, `inherit` to use the parent's model, or omitted for default
- **File naming**: `<agent-name>.md` matching the `name:` field in frontmatter, placed in category subdirectory (`research/`, `review/`, `workflow/`)

---

## 2. Skill File Format Requirements

**Source**: `plugins/compound-workflows/skills/disk-persist-agents/SKILL.md` (the only currently existing skill)

The established format for skill files:

```yaml
---
name: <skill-name>
description: <description of the pattern/capability>
---

# Skill Title

## The Problem
## The Solution
## Pattern/Template (with code blocks)
## Directory Convention
## Examples
## Anti-Patterns
```

### Key Skill Conventions
- **File name**: Must be `SKILL.md` inside a directory named after the skill
- **Directory structure**: `skills/<skill-name>/SKILL.md`, with optional subdirectories for assets (`assets/`, `references/`, `templates/`, `workflows/`)
- **Content**: Pattern documentation, not executable code. Teaches Claude how to apply a reusable pattern.
- **Skills referenced by name**: Commands reference skills by name (e.g., "Load the `brainstorming` skill"); they work if installed but must not break if absent.

---

## 3. Plugin Structure Conventions

**Source**: `plugins/compound-workflows/CLAUDE.md`, `docs/plans/2026-02-25-plugin-packaging-plan.md`

### Directory Layout
```
plugins/compound-workflows/
  agents/
    research/           # Research and knowledge agents
    review/             # Code review and quality agents
    workflow/           # Process and workflow agents
  commands/
    compound-workflows/ # All slash commands (namespaced)
  skills/
    <skill-name>/
      SKILL.md          # Main skill file
      assets/           # Optional supporting files
  .claude-plugin/
    plugin.json         # Plugin manifest
  CLAUDE.md             # Development guidelines
  README.md             # User documentation
  CHANGELOG.md          # Version history
  LICENSE               # MIT
  NOTICE                # Attribution (required for forks)
```

### Naming Conventions
- Commands use `compound-workflows:` prefix in YAML `name:` field
- Agent files named with lowercase-hyphenated descriptive names
- Three agents being renamed from contributor names: `kieran-typescript-reviewer` -> `typescript-reviewer`, `kieran-python-reviewer` -> `python-reviewer`, `julik-frontend-races-reviewer` -> `frontend-races-reviewer`
- Topic stems: lowercase, hyphens, 3-6 words max

### Versioning Rules (from CLAUDE.md)
- **MAJOR** (2.0.0): Breaking changes to command interfaces or directory conventions
- **MINOR** (1.1.0): New commands, agents, or skills
- **PATCH** (1.0.1): Bug fixes, doc updates, prompt improvements
- This fork is versioned as **1.1.0** (adding agents/skills, plugin was never published so no users to break)

---

## 4. Plugin Porting Strategy (Established Pattern)

**Sources**: `docs/plans/2026-02-25-plugin-packaging-plan.md`, `docs/brainstorms/2026-02-25-port-gaps-compound-engineering-brainstorm.md`

### What "Porting" Means for This Project
1. Copy the agent `.md` file from compound-engineering into `plugins/compound-workflows/agents/<category>/`
2. Genericize company-specific examples (e.g., "BriefSystem" -> "AuthService", "EmailProcessing" -> "PaymentProcessor")
3. Keep `model: haiku` or `model: inherit` fields as-is (preserves cost optimization)
4. Ensure inline role descriptions exist on all Task dispatches in commands (for `general-purpose` fallback)
5. Update command files to reference new names for the 3 renamed agents
6. Remove references to dropped agents (Rails reviewers, company-specific agents)

### The Fallback Architecture (Critical Pattern)
Commands dispatch agents with inline role descriptions so that if the full agent definition is unavailable, Claude's `general-purpose` subagent can still execute with a reasonable (if degraded) role description:

```
Task repo-research-analyst (run_in_background: true): "
You are a repository research analyst specializing in codebase pattern discovery.
[... rest of prompt ...]
"
```

When the full `repo-research-analyst.md` agent exists, it gets the rich multi-page methodology. When it does not exist, the 1-sentence inline description provides basic guidance. This fork eliminates the fallback scenario for all 22 ported agents.

### Three Fallback Tiers (All Must Work)
| Component | With Enhancement | Without Enhancement |
|-----------|-----------------|-------------------|
| Agents | Full multi-page agent definitions from this plugin | Inline 1-sentence role descriptions (general-purpose fallback) |
| Beads (`bd`) | Compaction-safe task tracking | TodoWrite fallback (loses state on compaction) |
| PAL MCP | Cross-model red-team challenges | Claude subagent fallback (same prompt, less model diversity) |

---

## 5. Previous Issues Encountered (QA Findings from v1.0.0 Port)

**Source**: `docs/plans/2026-02-25-plugin-qa-and-publish-plan.md`, `.workflows/brainstorm-research/port-gaps-compound-engineering/context-research.md`

### Issue 1: Truncation Risk
- Files ported in a prior session may have been cut off. Commands are 150-400 lines each.
- **Mitigation**: Compare line counts against source files. Spot-check file endings.

### Issue 2: Incomplete Role Descriptions
- Some Task dispatch blocks may lack the "You are a..." inline role description needed for general-purpose fallback.
- **Mitigation**: Grep for `Task ` patterns and verify each has an accompanying role description.

### Issue 3: TodoWrite Fallback Incompleteness
- The beads/TodoWrite detection block was added at the top of work.md and work-agents.md, but the body of those commands may still reference `bd` commands without corresponding TodoWrite alternatives.
- **Mitigation**: Audit entire body of work.md and work-agents.md for every `bd` command reference and ensure TodoWrite equivalents are documented alongside.

### Issue 4: Hardcoded Year References
- Some files may still contain "2026" as a literal year instead of "the current year."
- **Mitigation**: Grep for `2026` in all ported files; verify only illustrative dates remain (e.g., example filenames like `2026-02-10-my-plan.md` are fine, but "the current year is 2026" is not).

### Issue 5: Skill Cross-References
- Commands reference compound-engineering skills by name (`brainstorming`, `document-review`, `file-todos`, `git-worktree`). These must work when skills exist AND degrade gracefully when absent.
- **Mitigation**: After this fork ports those skills locally, cross-references will resolve within the plugin. Verify no hard failures if a skill is somehow missing.

### Issue 6: deepen-plan Discovery Paths
- `deepen-plan.md` searches compound-engineering's cache path for agents. After the fork, it must ALSO search compound-workflows' own `agents/` directory.
- **Mitigation**: Update Phase 2c discovery logic in deepen-plan.md to include the plugin's own agent directory.

---

## 6. Red Team Findings (Resolved and Unresolved)

**Sources**: `.workflows/brainstorm-research/port-gaps-compound-engineering/red-team-gemini.md`, `red-team-gpt5.md`, `red-team-opus.md`

### Addressed in Brainstorm (Will Be Implemented)
| Finding | Resolution |
|---------|-----------|
| Fork drift / no sync strategy (all 3 models) | LLM-assisted periodic merge from upstream; will contribute back |
| Licensing/attribution (GPT-5.2) | NOTICE file + README credit for MIT (c) Kieran Klaassen |
| spec-flow-analyzer missing from scope (Opus) | Added to Workflow agents list |
| Company-specific examples bias LLM outputs (all 3) | Genericize all examples during port |
| "Don't install both" unenforceable (all 3) | Setup command will detect compound-engineering and warn |
| deepen-plan discovery searches wrong paths (Opus) | Added to command update scope |
| Figma drop rationale inconsistent (GPT-5.2) | Corrected: real blocker is Figma MCP, not agent-browser |
| "One plugin, full power" overstates (GPT-5.2) | Clarified: all prompts present, external deps need separate setup |

### Considered and Rejected (With Rationale)
| Finding | Why Rejected |
|---------|-------------|
| Should be 2.0.0 not 1.1.0 (GPT-5.2) | Plugin was never published. No users, no scripts, no references to break. |
| Namespace aliasing instead of fork (Gemini, GPT-5.2) | Claude Code plugins don't support command aliasing or renaming upstream commands. Fork is the only mechanism. |
| Thin wrapper / proxy agents (Opus) | Adds complexity without reducing maintenance. Full fork is simpler. |
| Selective fork (Tier 1 only) (Opus) | User explicitly chose all agents. Partial fork would leave /review degraded. |
| Generic names may collide more easily (Opus) | Acceptable risk. "typescript-reviewer" is descriptive. Collision with another plugin is edge case. |
| Model field "haiku" may not resolve for all providers (Gemini) | Claude Code's model field is Claude-ecosystem specific. "haiku" resolves to Claude Haiku. |
| No testing strategy (Opus) | Valid but out of scope for brainstorm. Testing will be in the implementation plan. |

---

## 7. Complete Scope Inventory

**Source**: `docs/brainstorms/2026-02-25-port-gaps-compound-engineering-brainstorm.md`

### Agents to Port: 22 new (23 total with existing context-researcher)

**Research (5 new, 6 total):**
1. `context-researcher` -- ALREADY PORTED
2. `repo-research-analyst` -- used by brainstorm, plan (CRITICAL)
3. `learnings-researcher` -- used by plan (HIGH)
4. `best-practices-researcher` -- used by plan (HIGH)
5. `framework-docs-researcher` -- used by plan (HIGH)
6. `git-history-analyzer` -- utility, useful for deepen-plan

**Review (13 new):**
7. `code-simplicity-reviewer` -- used by work, work-agents, review (MEDIUM)
8. `typescript-reviewer` -- renamed from kieran-typescript-reviewer (MEDIUM)
9. `python-reviewer` -- renamed from kieran-python-reviewer (MEDIUM)
10. `pattern-recognition-specialist` -- review (MEDIUM)
11. `architecture-strategist` -- review (MEDIUM)
12. `security-sentinel` -- review, compound (MEDIUM)
13. `performance-oracle` -- review, compound (MEDIUM)
14. `agent-native-reviewer` -- review (MEDIUM)
15. `data-migration-expert` -- review conditional (LOW)
16. `deployment-verification-agent` -- review conditional (LOW)
17. `frontend-races-reviewer` -- renamed from julik-frontend-races-reviewer (LOW)
18. `data-integrity-guardian` -- compound conditional (LOW)
19. `schema-drift-detector` -- utility, not currently referenced

**Workflow (3 new):**
20. `spec-flow-analyzer` -- used by plan (HIGH)
21. `bug-reproduction-validator` -- standalone utility
22. `pr-comment-resolver` -- standalone utility

### Skills to Port: 14 new (15 total with existing disk-persist-agents)

**Referenced by commands (5):**
1. `brainstorming` -- brainstorm.md
2. `document-review` -- brainstorm.md
3. `file-todos` -- review.md
4. `git-worktree` -- review.md
5. `compound-docs` -- compound.md (templates + YAML schema)

**Utility (9):**
6. `setup` -- replaces existing setup command; adds stack detection + agent config
7. `gemini-imagegen` -- Gemini API image generation
8. `agent-browser` -- browser automation
9. `orchestrating-swarms` -- multi-agent coordination patterns
10. `create-agent-skills` -- guide for creating new agents/skills
11. `agent-native-architecture` -- architecture patterns (12 reference docs)
12. `resolve-pr-parallel` -- parallel PR comment resolution
13. `skill-creator` -- skill creation and iteration
14. `frontend-design` -- distinctive frontend interfaces, anti-AI-slop guide

### Commands to Update: 7 existing
- **review.md**: Remove Rails reviewer references, update 3 renamed agent refs
- **setup.md**: Replace with skill approach, add conflict detection
- **deepen-plan.md**: Update agent discovery to search own agents/ directory
- **All commands**: Remove compound-engineering as optional dependency, genericize examples

### Agents Deliberately Dropped (not porting)
- `dhh-rails-reviewer` (Rails-specific)
- `kieran-rails-reviewer` (Rails-specific)
- `every-style-editor` (Every brand-specific)
- `lint` (Ruby/ERB-specific)
- `ankane-readme-writer` (Ruby gem-specific)
- 3 design/Figma agents (require Figma MCP)

---

## 8. Key Implementation Risks

### Risk 1: Agent Resolution with Duplicate Plugins
If a user has both compound-workflows and compound-engineering installed, there will be duplicate agent definitions. The brainstorm's solution is for `setup` to detect compound-engineering and warn. This is documentation-level enforcement, not technical enforcement.

### Risk 2: Maintenance Divergence from Upstream
Forking 22 agents + 14 skills creates a 36-component maintenance surface. The plan calls for "LLM-assisted periodic merge" from upstream compound-engineering, but no cadence or process is specified.

### Risk 3: Complex Skills with Assets
Several skills have multi-file structures: `compound-docs/` (SKILL.md + assets/ + schema.yaml), `create-agent-skills/` (SKILL.md + references/ + templates/ + workflows/), `agent-native-architecture/` (SKILL.md + 12 reference docs). Total size and dependency audit needed.

### Risk 4: Example Genericization Quality
All three red-team models flagged that company-specific examples (e.g., "BriefSystem", "EmailProcessing") bias LLM outputs through few-shot anchoring. The quality of replacement examples directly impacts agent effectiveness for marketplace users.

### Risk 5: Renamed Agents Need Command Updates
Three agents are being renamed. Every command file that references the old names must be updated: `kieran-typescript-reviewer` -> `typescript-reviewer`, `kieran-python-reviewer` -> `python-reviewer`, `julik-frontend-races-reviewer` -> `frontend-races-reviewer`. Missing any reference creates a silent fallback to general-purpose.

---

## 9. Disk Persistence Pattern (Applies to All Agents)

**Source**: `plugins/compound-workflows/skills/disk-persist-agents/SKILL.md`

Every agent dispatched by commands must include the output instruction block:

```
=== OUTPUT INSTRUCTIONS (MANDATORY) ===
Write your COMPLETE findings to: <path>
After writing the file, return ONLY a 2-3 sentence summary.
```

Directory convention: `.workflows/<workflow-type>/<topic-stem>/agents/<agent-output>.md`

This pattern is already used by all 7 existing commands and the context-researcher agent. New agents must follow the same convention when dispatched by commands.

---

## 10. Cross-Reference Map

| Document | Location | Relevance |
|----------|----------|-----------|
| Port Gaps Brainstorm | `docs/brainstorms/2026-02-25-port-gaps-compound-engineering-brainstorm.md` | Complete scope, decisions, directory structure |
| Context Research | `.workflows/brainstorm-research/port-gaps-compound-engineering/context-research.md` | Fallback strategy analysis, gap inventory, QA checklist |
| Repo Research | `.workflows/brainstorm-research/port-gaps-compound-engineering/repo-research.md` | Full 29-agent inventory, per-command agent reference map, priority tiers |
| Red Team - Gemini | `.workflows/brainstorm-research/port-gaps-compound-engineering/red-team-gemini.md` | Fork drift, model aliases, example bias |
| Red Team - GPT-5.2 | `.workflows/brainstorm-research/port-gaps-compound-engineering/red-team-gpt5.md` | Versioning, licensing, namespace alternatives |
| Red Team - Opus | `.workflows/brainstorm-research/port-gaps-compound-engineering/red-team-opus.md` | Agent resolution, spec-flow-analyzer omission, wrapper alternatives, testing gap |
| Plugin Packaging Plan | `plugins/compound-workflows/docs/plans/2026-02-25-plugin-packaging-plan.md` | Original porting decisions, fallback architecture, verification steps |
| QA and Publish Plan | `plugins/compound-workflows/docs/plans/2026-02-25-plugin-qa-and-publish-plan.md` | Known QA gaps from v1.0.0 port |
| CLAUDE.md | `plugins/compound-workflows/CLAUDE.md` | Development conventions, versioning rules, testing requirements |
| context-researcher.md | `plugins/compound-workflows/agents/research/context-researcher.md` | Reference agent format (the only ported agent) |
| disk-persist-agents SKILL.md | `plugins/compound-workflows/skills/disk-persist-agents/SKILL.md` | Reference skill format, persistence patterns |
