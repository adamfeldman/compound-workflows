---
title: "Bundle aworkflows into a Shareable Plugin"
type: feat
status: completed
date: 2026-02-25
---

# Plan: Bundle aworkflows into a Shareable Plugin

## Context

Adam's `/aworkflows:*` commands are enhanced versions of compound-engineering's workflow commands, currently living as loose files in `~/.claude/commands/aworkflows/` and `~/.claude/agents/`. They add substantial value over the upstream: disk-persisted agent outputs, beads integration, PAL-based red-team challenges, subagent dispatch architecture, context-researcher agent, and rigorous phase gates. To share these with others, they need to be packaged as a proper Claude Code plugin.

## Inventory

**7 commands** (`~/.claude/commands/aworkflows/`):
- `brainstorm.md` — Collaborative dialogue + PAL red-team + context-researcher
- `plan.md` — Disk-persisted research agents + brainstorm cross-check + specflow
- `work.md` — Beads-tracked execution + worktree integration
- `work-agents.md` — Subagent dispatch architecture for large plans (no upstream equivalent)
- `review.md` — Multi-agent code review with disk-persisted outputs
- `compound.md` — Solution documentation with analytical/strategic mode
- `deepen-plan.md` — Multi-run plan enhancement with red-team + consensus

**1 custom agent** (`~/.claude/agents/context-researcher.md`):
- Broad knowledge base search across 5 directories, tagged by source type and validation status

## Decisions (Confirmed)

- **Plugin name:** `compound-workflows` → commands register as `/compound-workflows:brainstorm`, etc.
- **Distribution:** Own marketplace repo with standard `marketplace.json` wrapper
- **Beads:** Preferred but optional. Work/work-agents detect `bd` at startup; if missing, fall back to TodoWrite for task tracking. Beads path retains compaction-safe persistence; TodoWrite path is functional but loses state on compaction.
- **compound-engineering:** Documented peer dependency. Agents referenced by name with inline role descriptions for graceful `general-purpose` fallback.
- **PAL MCP:** Optional with Claude subagent fallback. Red-team steps detect PAL availability at runtime. If PAL is available, use it (different model = different blind spots). If not, fall back to a Claude subagent running the same red-team prompt — still valuable, just less diverse training data.

## Plugin Structure

```
compound-workflows-marketplace/          # Git repo root = marketplace
├── .claude-plugin/
│   └── marketplace.json                 # Lists the plugin
├── plugins/
│   └── compound-workflows/              # The actual plugin
│       ├── .claude-plugin/
│       │   └── plugin.json
│       ├── agents/
│       │   └── research/
│       │       └── context-researcher.md
│       ├── commands/
│       │   └── compound-workflows/
│       │       ├── brainstorm.md
│       │       ├── plan.md
│       │       ├── work.md
│       │       ├── work-agents.md
│       │       ├── review.md
│       │       ├── compound.md
│       │       ├── deepen-plan.md
│       │       └── setup.md             # Environment detection + enhancement recommendations
│       ├── skills/
│       │   └── disk-persist-agents/
│       │       └── SKILL.md
│       ├── CLAUDE.md
│       ├── README.md
│       ├── CHANGELOG.md
│       └── LICENSE
```

## Implementation Steps

### Phase 0: Scaffold (`~/Dev/compound-workflows-marketplace/`)
- [x] Create full directory tree
- [x] Write `marketplace.json` (root)
- [x] Write `plugin.json`: name, version 1.0.0, description, author (Adam Feldman), keywords
- [x] Write `LICENSE` (MIT)
- [x] `git init`

### Phase 0.5: Create setup command

**Target:** `plugins/compound-workflows/commands/compound-workflows/setup.md`

`/compound-workflows:setup` — runs on first use or on demand. Detects environment and tells the user what's available vs. what they could add:

1. **Detect installed enhancements:**
   - `bd version 2>/dev/null` → beads available?
   - Check if PAL MCP tools are registered (try listing models or similar)
   - Check if compound-engineering plugin is installed (check for known agents/skills)

2. **Present status table** showing what's detected and what each enhancement unlocks:

   | Enhancement | Status | What it adds |
   |-------------|--------|-------------|
   | **beads** (`bd`) | Installed / Not found | Compaction-safe task tracking in work/work-agents. Without it: TodoWrite fallback (loses state on compaction) |
   | **PAL MCP** | Connected / Not found | Cross-model red-team challenges in brainstorm/deepen-plan. Without it: Claude subagent fallback (still works, less model diversity) |
   | **compound-engineering** | Installed / Not found | Specialized review/research agents. Without it: general-purpose fallback (still works, less specialized) |

3. **For missing enhancements**, show install instructions
4. **Confirm directory conventions** — check if `docs/brainstorms/`, `docs/plans/`, `docs/solutions/` exist. If not, offer to create them.
5. **Write `compound-workflows.local.md`** with detected capabilities so commands can read it at runtime.

### Phase 1: Port 7 commands

**Source:** `~/.claude/commands/aworkflows/*.md`
**Target:** `plugins/compound-workflows/commands/compound-workflows/`

Per-file changes:
1. YAML `name:` — `aworkflows:X` → `compound-workflows:X`
2. Hardcoded "2026" → "the current year" (brainstorm, plan, deepen-plan)
3. Internal cross-refs — `/aworkflows:plan` → `/compound-workflows:plan` (all files)
4. Task dispatches — add inline role description to each agent name so `general-purpose` fallback works
5. PAL references — add detection + fallback: try PAL `chat` for red-team; if PAL unavailable, dispatch a Claude `general-purpose` subagent with the same red-team prompt
6. Beads/TodoWrite detection — add startup check: `bd version 2>/dev/null`. If beads available, use beads. If not, fall back to TodoWrite.

### Phase 2: Port context-researcher agent

**Source:** `~/.claude/agents/context-researcher.md`
**Target:** `plugins/compound-workflows/agents/research/context-researcher.md`

Changes:
- Generalize `memory/` and `Resources/` — keep them in the search list but add existence check guidance
- Remove project-specific examples → generic examples
- Keep `model: haiku` frontmatter

### Phase 3: Create disk-persist-agents skill

**Target:** `plugins/compound-workflows/skills/disk-persist-agents/SKILL.md`

Content: Extract the repeated pattern from all 7 commands into a single skill doc:
- The "OUTPUT INSTRUCTIONS (MANDATORY)" boilerplate template
- `.workflows/<workflow-type>/<topic-stem>/` directory convention
- File monitoring pattern (`ls` polling, not `TaskOutput`)
- Retention policy (never delete research outputs)
- Batch dispatch and timeout handling patterns

### Phase 4: Documentation

- [x] **README.md** — Installation, what this adds over compound-engineering, dependency table, directory conventions, quick start
- [x] **CLAUDE.md** — Plugin dev instructions (versioning, structure, testing)
- [x] **CHANGELOG.md** — v1.0.0 with full feature list

### Phase 5: Git + distribute
- [x] Commit all files
- [ ] Create GitHub repo, push
- [ ] Test: install from another project with `claude /install`

## Source Files (Critical Paths)

| Source | Purpose |
|--------|---------|
| `~/.claude/commands/aworkflows/brainstorm.md` | Most complex command — PAL integration, context-researcher, red-team |
| `~/.claude/commands/aworkflows/work-agents.md` | Unique to this plugin — subagent dispatch architecture |
| `~/.claude/commands/aworkflows/deepen-plan.md` | Multi-run + red-team + consensus — most modification needed |
| `~/.claude/agents/context-researcher.md` | The only custom agent to port |
| `~/.claude/plugins/marketplaces/every-marketplace/plugins/compound-engineering/.claude-plugin/plugin.json` | Format reference for plugin.json |
| `~/.claude/plugins/marketplaces/beads-marketplace/.claude-plugin/marketplace.json` | Format reference for marketplace.json |

## Verification

1. Install in a test project and verify all 8 commands appear in slash command list
2. Run `/compound-workflows:setup` — verify it detects beads/PAL/compound-engineering status correctly and shows install guidance for missing items
3. Run `/compound-workflows:brainstorm test feature` — verify dialogue flow, research agents write to `.workflows/`
4. Run `/compound-workflows:plan` from the brainstorm — verify disk persistence and cross-references work
5. Test without compound-engineering installed — verify agents degrade to `general-purpose` with adequate role context
6. Test without PAL — verify red-team falls back to Claude subagent and produces critique
7. Test `work` without beads — verify it detects missing `bd` and falls back to TodoWrite cleanly
