# Context Research: Porting Agents from compound-engineering to compound-workflows

## Search Context

- **Query**: Porting agents from compound-engineering plugin to compound-workflows, agent fallback strategies, and gaps in the initial port
- **Keywords**: compound-engineering, port, migration, fallback, agent, general-purpose, role description
- **Locations Searched**:
  - `plugins/compound-workflows/` (commands, agents, skills)
  - `.workflows/` (plans and brainstorms)
  - `docs/plans/` (planning documents)
  - `memory/` (project context)
- **Total Matches**: 18 files, primary sources identified
- **Date Searched**: 2026-02-25

---

## Results by Relevance

### 1. QA, Fix, and Publish compound-workflows Plugin Plan
- **Source**: `[PLAN]` — `/Users/adamf/Dev/compound-workflows-marketplace/plugins/compound-workflows/docs/plans/2026-02-25-plugin-qa-and-publish-plan.md`
- **Date**: 2026-02-25
- **Status**: Active (ready for execution)
- **Relevance**: Directly addresses QA gaps in the initial port and lists specific porting issues to verify
- **Key Finding**:
  - Porting was completed in a prior session (7 commands + context-researcher agent + disk-persist-agents skill)
  - QA step 1 explicitly lists 5 categories of gaps to verify during review:
    1. **Truncation** — Did ported files get cut off? Commands are 150-400 lines
    2. **Role descriptions on agent dispatches** — Some agents may lack fallback role descriptions
    3. **TodoWrite fallback completeness** — Detection block added but conditional guidance may be incomplete throughout `work.md` and `work-agents.md`
    4. **Example dates** — References to `2026-02-10`, `2026-02-20` should not say "current year is 2026"
    5. **Cross-references to skills** — Verify skill refs work by name (graceful fallback if absent)
- **Staleness Risk**: Low — dated today, reflects actual port status
- **Cross-References**: Links to `2026-02-25-plugin-packaging-plan.md`

### 2. Bundle aworkflows into a Shareable Plugin (Packaging Plan)
- **Source**: `[PLAN]` — `/Users/adamf/Dev/compound-workflows-marketplace/plugins/compound-workflows/docs/plans/2026-02-25-plugin-packaging-plan.md`
- **Date**: 2026-02-25
- **Status**: Completed (status: completed)
- **Relevance**: Documents the original porting strategy, decisions, and agent fallback architecture before execution
- **Key Findings**:
  - **Fallback strategy documented at decision level**:
    - Beads preferred but optional → TodoWrite fallback if `bd version` fails
    - PAL MCP optional → Claude `general-purpose` subagent fallback if PAL unavailable
    - compound-engineering optional → agents degrade to `general-purpose` with inline role descriptions for graceful fallback
  - **Agent dispatch pattern**: "task dispatches — add inline role description to each agent name so `general-purpose` fallback works"
  - **Specific modifications required during port**:
    - YAML `name:` field conversion: `aworkflows:X` → `compound-workflows:X`
    - Year references: "2026" → "the current year" (in brainstorm, plan, deepen-plan)
    - Internal cross-refs: `/aworkflows:plan` → `/compound-workflows:plan`
    - Agent references: Add inline role descriptions on all Task dispatches
    - PAL references: Add detection + fallback (try PAL `chat`; if unavailable, dispatch Claude `general-purpose` with same prompt)
    - Beads/TodoWrite: Add startup check for `bd version 2>/dev/null`
  - **Compound-engineering as peer dependency**: "Documented peer dependency. Agents referenced by name with inline role descriptions for graceful `general-purpose` fallback."
  - **Skills referenced by name**: brainstorm.md references `brainstorming` and `document-review` skills; review.md references `file-todos` and `git-worktree` skills (from compound-engineering, work if installed but don't break if absent)
- **Staleness Risk**: Low — strategy document from same session as execution
- **Critical Files to Check**: brainstorm.md, work.md, work-agents.md, deepen-plan.md, context-researcher.md

### 3. CLAUDE.md — Plugin Development Guidelines
- **Source**: `[RESOURCE]` — `/Users/adamf/Dev/compound-workflows-marketplace/plugins/compound-workflows/CLAUDE.md`
- **Date**: 2026-02-25 (created during packaging)
- **Status**: Validated (plugin dev instructions)
- **Relevance**: Codifies porting requirements and fallback strategy for future maintenance
- **Key Findings**:
  - **Fallback principle**: "Commands reference agents by name with inline role descriptions for graceful fallback"
  - **Runtime detection**: "Commands detect beads/PAL at runtime and adapt behavior"
  - **Testing requirement for porting**: "Verify graceful degradation without beads/PAL/compound-engineering"
  - **Versioning convention**: Breaking changes (2.0.0) include "command interfaces or directory conventions"
- **Staleness Risk**: Low — contemporaneous with port
- **Cross-References**: References testing requirements that align with QA plan

### 4. README.md — Feature Comparison & Dependencies
- **Source**: `[RESOURCE]` — `/Users/adamf/Dev/compound-workflows-marketplace/plugins/compound-workflows/README.md`
- **Date**: 2026-02-25
- **Status**: Validated (public documentation)
- **Relevance**: Defines what was ported and what fallback mechanisms exist
- **Key Findings**:
  - **Feature additions over compound-engineering**:
    - Disk-persisted agent outputs (`.workflows/`)
    - Beads preferred + TodoWrite fallback (from compound-engineering: TodoWrite only)
    - Multi-model red-team via PAL + Claude subagent fallback (from compound-engineering: none)
    - Subagent dispatch architecture in `work-agents` (no upstream equivalent)
    - Numbered multi-run directories for plan deepening
    - Broad context search (5 directories) vs. compound-engineering (solutions only)
  - **Dependency matrix**:
    | Tool | Required | What it enables |
    | --- | --- | --- |
    | beads (`bd`) | Recommended | Compaction-safe tracking; TodoWrite fallback w/o it |
    | PAL MCP | Optional | Multi-model red-team; Claude subagent fallback w/o it |
    | compound-engineering | Recommended | Specialized agents; general-purpose fallback w/o it |
    | GitHub CLI (`gh`) | Optional | PR creation in work/review |
  - Explicit instruction: "Run `/compound-workflows:setup` to see what's installed"
- **Staleness Risk**: Low — newly created
- **Cross-References**: Mentions `skills/disk-persist-agents/SKILL.md` pattern

### 5. brainstorm.md Command — Agent Dispatch with Fallback
- **Source**: `[PLAN]` — `/Users/adamf/Dev/compound-workflows-marketplace/plugins/compound-workflows/commands/compound-workflows/brainstorm.md`
- **Date**: 2026-02-25 (ported during this session)
- **Status**: Needs QA (part of Phase 1 review)
- **Relevance**: Most complex command; demonstrates fallback pattern for all commands
- **Key Findings**:
  - **Two parallel research agents with role descriptions**:
    ```
    Task repo-research-analyst (run_in_background: true): "
    You are a repository research analyst specializing in codebase pattern discovery and architectural analysis.
    ```
    ```
    Task context-researcher (run_in_background: true): "
    You are a context researcher specializing in synthesizing project knowledge across documentation...
    ```
  - Both agents have clear role descriptions enabling graceful fallback to `general-purpose`
  - **PAL fallback for red-team** (Phase 3.5):
    ```
    Task general-purpose (run_in_background: true): "
    You are a red team reviewer. Your job is to find flaws, not validate.
    ```
    This pattern detects if PAL is available and uses it; otherwise falls back to Claude `general-purpose`
  - **Cross-references to compound-engineering skills**: "Load the `brainstorming` skill for detailed techniques" and references to `document-review` skill
  - **Uses context-researcher agent** (custom, ported) for broad knowledge search
- **QA Checklist Items**:
  - [ ] Verify all agent dispatches have role descriptions
  - [ ] Verify PAL fallback block is complete and syntactically correct
  - [ ] Verify skill references work by name without breaking if absent
  - [ ] Verify year references use "current year" not hardcoded 2026
- **Staleness Risk**: Medium — port completed but not yet QA'd
- **Cross-References**: References `.workflows/brainstorm-research/<topic-stem>/` convention

### 6. work.md Command — Beads/TodoWrite Fallback
- **Source**: `[PLAN]` — `/Users/adamf/Dev/compound-workflows-marketplace/plugins/compound-workflows/commands/compound-workflows/work.md`
- **Date**: 2026-02-25 (ported)
- **Status**: Needs QA
- **Relevance**: Demonstrates beads/TodoWrite dual-path fallback pattern
- **Key Findings**:
  - **Task Tracking Detection block** (lines 17-27):
    ```bash
    if bd version 2>/dev/null; then
      echo "TRACKER=beads"
    else
      echo "TRACKER=todowrite"
    fi
    ```
  - **Fallback guidance**: Explains mapping of `bd` commands to TodoWrite equivalents:
    - `bd create` → `TodoWrite: add task`
    - `bd update` → `TodoWrite: mark`
    - `bd close` → `TodoWrite: mark completed`
    - `bd ready` → `TodoWrite: list pending`
  - **Critical note**: "With TodoWrite, recovery after compaction requires re-reading the plan file and checking git log to infer progress"
  - **Worktree handling**: Uses `bd worktree create` (beads) or `git checkout -b` (fallback)
- **QA Checklist Items**:
  - [ ] Verify TodoWrite fallback mapping appears THROUGHOUT work.md, not just in intro block
  - [ ] Check if beads issue creation (`bd create`) has full TodoWrite equivalent guidance
  - [ ] Verify worktree paths and cleanup instructions are clear for both paths
  - [ ] Verify date examples (`2026-02-10`) are illustrative, not prescriptive
- **Staleness Risk**: Medium — port complete but conditional guidance may be incomplete
- **Cross-References**: Shared pattern with `work-agents.md`

### 7. work-agents.md Command — Subagent Dispatch with Fallback
- **Source**: `[PLAN]` — `/Users/adamf/Dev/compound-workflows-marketplace/plugins/compound-workflows/commands/compound-workflows/work-agents.md`
- **Date**: 2026-02-25 (ported)
- **Status**: Needs QA
- **Relevance**: Demonstrates subagent dispatch pattern + beads fallback + role descriptions
- **Key Findings**:
  - **Identical beads/TodoWrite detection** to `work.md`
  - **Subagent dispatch pattern**: Orchestrator stays lean, each step gets a subagent with role description:
    ```
    Task [subagent-name] (run_in_background: true): "
    You are a [role description explaining specialization].
    ```
  - **Orchestrator-only context management**: "The main context acts as an orchestrator only — it never reads source files or writes code directly"
  - **Manifest file tracking**: Uses `.workflows/work-agents/<plan-stem>/manifest.json` to track subagent progress across runs
  - **Plan stem derivation**: Example shows how to extract topic from plan filename
- **QA Checklist Items**:
  - [ ] Verify each subagent dispatch has complete role description
  - [ ] Verify manifest.json structure is fully documented
  - [ ] Verify TodoWrite fallback guidance is complete throughout (not just intro)
  - [ ] Verify date examples are illustrative
  - [ ] Verify subagent prompt templates include instructions for writing findings to disk
- **Staleness Risk**: Medium — port complete but needs full QA
- **Cross-References**: Shared beads/TodoWrite pattern with `work.md`

### 8. deepen-plan.md Command — Multi-Run Fallback with Consensus
- **Source**: `[PLAN]` — `/Users/adamf/Dev/compound-workflows-marketplace/plugins/compound-workflows/commands/compound-workflows/deepen-plan.md`
- **Date**: 2026-02-25 (ported)
- **Status**: Needs QA
- **Relevance**: Most complex porting (PAL → consensus, multi-run manifests, agent discovery)
- **Key Findings**:
  - **Multi-run manifest pattern**: Retains all prior run outputs under `.workflows/deepen-plan/<plan-stem>/run-<N>-*`
    - Manifest tracks: `plan_path`, `plan_stem`, `origin_brainstorm`, `started_at`, `status`, `run`, `agents`
    - Status values: `"parsing"` → `"discovered"` → `"launched"` → `"synthesized"` → `"completed"`
  - **Agent discovery mechanism**: Dynamically discovers available skills, learnings, and agents:
    ```bash
    # Skills: ./.claude/skills/, ~/.claude/skills/, ~/.claude/plugins/cache/*/skills
    # Learnings: docs/solutions/
    # Agents: compound-engineering plugin agents, ./.claude/agents/, ~/.claude/agents/
    ```
  - **Fallback strategy for agents**: If compound-engineering agents not available, uses `general-purpose` with role description
  - **Consensus fallback**: Lines 210+ show fallback to `general-purpose` agent for synthesis if PAL unavailable
- **QA Checklist Items**:
  - [ ] Verify agent discovery loops handle missing compound-engineering gracefully
  - [ ] Verify consensus block uses `general-purpose` fallback with full context if PAL missing
  - [ ] Verify manifest.json read/write is atomic and handles interruption recovery
  - [ ] Verify prior run synthesis files are being read and used to focus new analysis
  - [ ] Verify skill/learning discovery paths are correct
- **Staleness Risk**: Medium — high complexity, needs thorough QA
- **Cross-References**: Depends on skill discovery from compound-engineering and local `.claude/` directories

### 9. context-researcher Agent — Custom Agent Port
- **Source**: `[MEMORY]` — `/Users/adamf/Dev/compound-workflows-marketplace/plugins/compound-workflows/agents/research/context-researcher.md`
- **Date**: 2026-02-25 (ported and generalized)
- **Status**: Needs QA on generalization
- **Relevance**: Only custom agent in port; used by brainstorm.md and context-search workflows
- **Key Findings**:
  - **Generalization requirement**: Originally specific to Adam's projects (Flooid, Intellect, StarRocks examples)
  - **Porting changes made**:
    - Removed project-specific references
    - Added directory existence checks
    - Kept `model: haiku` frontmatter
    - Retained search locations: `docs/solutions/`, `docs/brainstorms/`, `docs/plans/`, `memory/`, `Resources/`
  - **Inline role description**: "You are a context researcher specializing in synthesizing project knowledge across documentation, solutions, brainstorms, plans, and institutional memory"
  - **Output format**: Returns 2-3 sentence summary; writes full findings to `.workflows/brainstorm-research/<topic-stem>/context-research.md`
- **QA Checklist Items**:
  - [ ] Verify no project-specific examples remain (search for: Flooid, Intellect, StarRocks, Eric, etc.)
  - [ ] Verify directory existence checks work correctly
  - [ ] Verify search examples are generic and reusable
  - [ ] Verify frontmatter `model: haiku` is appropriate
- **Staleness Risk**: Low — generalization focused, specific task
- **Cross-References**: Used by brainstorm.md, can be invoked directly

### 10. disk-persist-agents Skill — Pattern Documentation
- **Source**: `[RESOURCE]` — `/Users/adamf/Dev/compound-workflows-marketplace/plugins/compound-workflows/skills/disk-persist-agents/SKILL.md`
- **Date**: 2026-02-25
- **Status**: Completed (skill documentation)
- **Relevance**: Documents the shared pattern all ported commands follow for disk persistence
- **Key Finding**: All 7 commands + custom agents follow this pattern:
  - Each agent writes complete findings to `.workflows/<workflow-type>/<topic-stem>/<agent-output>.md`
  - Agent returns only 2-3 sentence summary to keep context lean
  - Files are never deleted (retention policy)
  - Pattern includes output instruction block template
  - Batch dispatch with timeout handling
- **Staleness Risk**: Low — foundational documentation
- **Cross-References**: Referenced by README.md and embedded in all command flows

### 11. setup.md Command — Environment Detection
- **Source**: `[PLAN]` — `/Users/adamf/Dev/compound-workflows-marketplace/plugins/compound-workflows/commands/compound-workflows/setup.md`
- **Date**: 2026-02-25 (newly created)
- **Status**: Completed (part of initial port)
- **Relevance**: Implements fallback detection for beads, PAL, compound-engineering
- **Key Finding**: First command run detects environment and writes `compound-workflows.local.md` with detected capabilities
- **Staleness Risk**: Low — foundational
- **Cross-References**: Other commands read this config file at runtime

---

## Cross-References Between Documents

### Fallback Strategy Consistency Check

| Component | Decision Doc | Implementation Doc | Detection/Fallback |
|-----------|--------------|-------------------|-------------------|
| **Beads/TodoWrite** | packaging-plan.md | work.md, work-agents.md | `bd version 2>/dev/null` |
| **PAL/Claude subagent** | packaging-plan.md | brainstorm.md, deepen-plan.md | Try PAL; fallback to `general-purpose` |
| **compound-engineering agents** | packaging-plan.md | brainstorm.md, deepen-plan.md | Discover by path; use with role description or fallback to `general-purpose` |
| **compound-engineering skills** | packaging-plan.md | brainstorm.md, review.md | Reference by name; work if installed |

### Phase Gate Dependencies

- **brainstorm.md** → writes to `docs/brainstorms/` with Open Questions section
- **plan.md** → reads brainstorm, cross-checks with research agents, writes to `docs/plans/`
- **deepen-plan.md** → reads plan, discovers agents/skills, runs multi-agent review, retains all outputs
- **work.md** / **work-agents.md** → reads plan, detects beads/TodoWrite, executes with persistent tracking
- **review.md** → post-work review with disk-persisted findings
- **compound.md** → documents solution, feeds future brainstorms

All commands write outputs to `.workflows/` for traceability and recovery after compaction.

---

## Gaps Identified (From QA Plan)

### Gap 1: Truncation Risk
**Status**: Needs verification
- Files ported in prior session; no confirmation that all 150-400 line commands were completely copied
- **Verification method**: Compare line counts or manually spot-check line endings

### Gap 2: Role Descriptions on Agent Dispatches
**Status**: Partially verified
- brainstorm.md has clear role descriptions on both parallel agents ✓
- work.md, work-agents.md use inline role descriptions for subagents ✓
- deepen-plan.md agent discovery pattern needs verification
- **Risk**: Some agent Task blocks may lack the "You are a..." role description needed for `general-purpose` fallback

### Gap 3: TodoWrite Fallback Completeness
**Status**: Detected but not fully verified
- Fallback mapping documented in work.md and work-agents.md introduction blocks
- **Risk**: Body of both commands may reference `bd` commands without corresponding TodoWrite alternatives
- Example: `bd create --title="..."` is mentioned but subsequent `bd dep add` or `bd update` may not have guidance

### Gap 4: Hardcoded Year References
**Status**: Needs spot-check
- packaging-plan.md specifies: "2026" → "the current year" (in brainstorm, plan, deepen-plan)
- Example dates `2026-02-10`, `2026-02-20` are illustrative; should not say "current year is 2026"
- **Risk**: Low if conversion was systematic; medium if ad-hoc

### Gap 5: Cross-References to Compound-Engineering Skills
**Status**: Partially verified
- brainstorm.md references `brainstorming` and `document-review` skills
- review.md references `file-todos` and `git-worktree` skills
- **Verification needed**: Confirm these work when compound-engineering is installed AND degrade gracefully when absent

### Gap 6: Agent Name Resolution
**Status**: Needs verification
- All Task dispatches should reference agent names (not paths) with inline role descriptions
- **Risk**: If any agent reference looks like a path or lacks role description, it won't fall back to `general-purpose`

---

## Recommendations

### Immediate Actions (Before QA Review)

1. **Run full text search** across ported files for:
   - Truncation: Look for "..." or incomplete sentences at file endings
   - Agent role descriptions: Grep for `Task ` without corresponding "You are a" in the next line
   - Hardcoded years: Search for `2026` outside of example filenames/dates
   - Beads references without TodoWrite equivalents: `bd dep add`, `bd label`, etc.

2. **Verify fallback patterns**:
   - Test `/compound-workflows:setup` detection of beads, PAL, compound-engineering
   - Test brainstorm without PAL installed (should use Claude `general-purpose`)
   - Test work without beads (should use TodoWrite)
   - Test deepen-plan without compound-engineering agents (should use `general-purpose`)

3. **Cross-check against source files**:
   - Compare line counts: `wc -l ~/.claude/commands/aworkflows/*.md` vs. `wc -l plugins/compound-workflows/commands/*.md`
   - Spot-check complex sections (beads loops, PAL detection, manifest JSON)

### Trust Levels

- **High confidence**: Plans and decisions are clearly documented (packaging-plan.md, QA-plan.md)
- **Medium confidence**: Agent dispatches have role descriptions (verified spot-check on brainstorm.md)
- **Lower confidence**: TodoWrite fallback completeness and edge case handling in complex commands
- **Risk areas**: deepen-plan.md (most complex), work-agents.md (unique pattern), skill reference handling

### Follow-Up Investigation

1. Read the full body of work.md and work-agents.md to audit TodoWrite fallback coverage
2. Verify all compound-engineering skill references by name don't break if skills absent
3. Test context-researcher agent generalization (no project-specific examples leaking)
4. Run actual test installation and verify all 8 commands appear and function with various dependency combinations

---

## Validation Status Summary

| Document | Source Type | Validation | Last Updated | Trust |
|----------|-------------|-----------|--------------|-------|
| 2026-02-25-plugin-qa-and-publish-plan.md | [PLAN] | Active | 2026-02-25 | High — lists actual gaps |
| 2026-02-25-plugin-packaging-plan.md | [PLAN] | Completed | 2026-02-25 | High — strategy doc |
| CLAUDE.md | [RESOURCE] | Validated | 2026-02-25 | High — dev guidelines |
| README.md | [RESOURCE] | Validated | 2026-02-25 | High — public docs |
| brainstorm.md | [PLAN] | Needs QA | 2026-02-25 | Medium — verified some gaps |
| work.md | [PLAN] | Needs QA | 2026-02-25 | Medium — fallback logic needs full review |
| work-agents.md | [PLAN] | Needs QA | 2026-02-25 | Medium — complex subagent pattern |
| deepen-plan.md | [PLAN] | Needs QA | 2026-02-25 | Medium — most complex, highest risk |
| context-researcher.md | [RESOURCE] | Needs QA | 2026-02-25 | Medium — generalization needs verification |
| setup.md | [PLAN] | Completed | 2026-02-25 | High — simple detection logic |
| disk-persist-agents SKILL.md | [RESOURCE] | Completed | 2026-02-25 | High — pattern documentation |

