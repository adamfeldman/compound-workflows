# Setup Skill Deep Audit

## Summary

25 total references need changing in the setup SKILL.md. The plan's Phase 4a is ~85% complete but misses the command/skill schema conflict — the existing command and the skill write DIFFERENT schemas to the same config file.

## Reference Mappings (25 Total)

### File Path References (5)

| # | Line | Old | New |
|---|------|-----|-----|
| 1 | 3 | `compound-engineering.local.md` | `compound-workflows.local.md` |
| 2 | 9 | `compound-engineering.local.md` | `compound-workflows.local.md` |
| 3 | 13 | `compound-engineering.local.md` | `compound-workflows.local.md` |
| 4 | 137 | `compound-engineering.local.md` | `compound-workflows.local.md` |
| 5 | 159 | `compound-engineering.local.md` | `compound-workflows.local.md` |

### Command References (4)

| # | Line | Old | New |
|---|------|-----|-----|
| 6 | 9 | `/workflows:review` | `/compound-workflows:review` |
| 7 | 9 | `/workflows:work` | `/compound-workflows:work` |
| 8 | 148 | `/workflows:review` | `/compound-workflows:review` |
| 9 | 148 | `/workflows:work` | `/compound-workflows:work` |

### Agent Name Changes (8 across 6 locations)

| # | Line | Old | New |
|---|------|-----|-----|
| 10 | 58 | `kieran-rails-reviewer, dhh-rails-reviewer` (Rails section) | REMOVE entire line |
| 11 | 59 | `kieran-python-reviewer` | `python-reviewer` |
| 12 | 60 | `kieran-typescript-reviewer` | `typescript-reviewer` |
| 13 | 119 | Rails agents line | REMOVE entire line |
| 14 | 120 | `kieran-python-reviewer` | `python-reviewer` |
| 15 | 121 | `kieran-typescript-reviewer` | `typescript-reviewer` |
| 16-17 | various | Other kieran-*/julik-* refs if any | Check and update |

### Title/Description (2)

| # | Line | Old | New |
|---|------|-----|-----|
| 18 | 7 | "Compound Engineering Setup" | "Compound Workflows Setup" |
| 19 | 2 | `name: setup` | `name: setup` (unchanged) |

## Critical Finding: Command/Skill Schema Conflict

### Existing setup.md Command writes:
```yaml
# compound-workflows.local.md
tracker: beads/todowrite
red_team: gemini-2.5-pro / none
review_agents: list of agents
gh_cli: available/not available
```

### Setup SKILL.md writes:
```yaml
# compound-engineering.local.md (→ compound-workflows.local.md)
review_agents: per-stack agent lists
plan_review_agents: research agent lists
project_context: stack detection results
depth: standard/comprehensive/minimal
```

### The Problem
These are TWO DIFFERENT SCHEMAS targeting the SAME file. The plan's Phase 5c says the command should "load the setup skill for agent configuration knowledge" but doesn't address how to merge these schemas.

### Recommended Resolution
The rewritten setup command should produce a UNIFIED schema:
```yaml
# compound-workflows.local.md
## Environment
tracker: beads/todowrite
red_team: gemini-2.5-pro / none
gh_cli: available/not available

## Stack & Agents
stack: rails/python/typescript/general
review_agents: [merged agent lists from skill's stack detection]
plan_review_agents: [from skill]
depth: standard/comprehensive/minimal

## Project Context
[from skill's project context detection]
```

## Phase 4a Completeness

The plan's Phase 4a identifies:
1. ✓ Rename compound-engineering.local.md → compound-workflows.local.md
2. ✓ Update command references /workflows → /compound-workflows
3. ✓ Replace agent names
4. ✓ Remove Rails agents from defaults
5. ✓ Title update
6. ✓ Add conflict detection section (new content)
7. ✓ Carry over beads/PAL detection from existing setup.md

### Missing from Phase 4a:
- **Rails path simplification**: Since Rails agents are dropped, the entire Rails stack path in the skill becomes a simpler "general" path. The skill currently has Rails-specific agent lists — those need to be removed or merged into the general path, not just have agent names removed.
- **Schema merge strategy**: No guidance on unifying the command's environment detection output with the skill's agent configuration output.

## Phase 5c Assessment

Phase 5c (setup command rewrite) steps:
1. Load setup skill ✓
2. Detect environment (beads, PAL, GitHub CLI) ✓
3. Compound-engineering conflict detection ✓
4. Auto-detect stack ✓
5. Configure review agents ✓
6. Create missing directories ✓
7. Write compound-workflows.local.md ✓

**Gap**: Step 7 doesn't specify the merged schema format. The implementer will need to design the unified output format.

## Verdict

Phase 4a needs two additions:
1. Rails path handling strategy (simplify, don't just delete agent names)
2. Schema merge specification for the config file output

Phase 5c needs the merged schema template.
