# Architecture Strategist Review: Fork compound-engineering Agents & Skills Plan

**Reviewed:** `docs/plans/2026-02-25-feat-fork-compound-engineering-agents-skills-plan.md`
**Origin:** `docs/brainstorms/2026-02-25-port-gaps-compound-engineering-brainstorm.md`
**Date:** 2026-02-25
**Agent:** architecture-strategist (methodology per `~/.claude/plugins/cache/every-marketplace/compound-engineering/2.35.2/agents/review/architecture-strategist.md`)

---

## 1. Architecture Overview

The compound-workflows plugin (v1.0.0) currently ships 8 commands, 1 agent, and 1 skill. It was designed to work alongside compound-engineering, falling back to 1-sentence inline role descriptions when specialized agents are unavailable. The plan proposes forking 21 agents and 14 skills from compound-engineering to make the plugin self-contained at v1.1.0 (~96 files touched across 5 commits).

The existing architecture follows a clear layered pattern:
- **Commands** (`commands/compound-workflows/*.md`) are user-facing entry points that orchestrate agents
- **Agents** (`agents/`) provide domain-specific expertise dispatched via `Task`
- **Skills** (`skills/`) provide reference material and utility patterns
- **Disk persistence** (`.workflows/`) is the context-safety mechanism

The fork introduces a second concern: the plugin must now maintain its own copy of upstream assets while preserving the existing orchestration patterns.

---

## 2. Fork Architecture Assessment

### 2a. "Copy + Modify" Approach: SOUND with caveats

**Strengths:**
- The phased approach (copy unmodified first, then modify) creates a clean audit trail. Commit 1 is byte-verifiable against source, making it trivial to confirm nothing was accidentally changed.
- Fork-over-dependency is the correct call given the Claude Code plugin architecture. There is no aliasing or namespace forwarding mechanism. The brainstorm's red team confirmed this across three models.
- The NOTICE file with MIT attribution is legally correct and placed early (Phase 1d).

**Risks:**

1. **SERIOUS: No upstream sync mechanism is defined beyond prose.** The plan says "will regularly merge improvements from upstream" and the brainstorm mentions "LLM-assisted periodic merge," but neither document specifies:
   - How to detect upstream changes (no tracking of the source version forked from)
   - What file-level metadata tracks which files are unmodified copies vs. locally modified
   - How to merge upstream changes into locally-modified files without regression

   **Recommendation:** Add a `FORK-MANIFEST.yaml` or similar file that records, per file: (a) source path in compound-engineering, (b) source version/commit hash, (c) modification status (unmodified / renamed / genericized / rewritten). This becomes the sync lookup table. Without it, "LLM-assisted periodic merge" has no structured input and will be error-prone.

2. **MINOR: The plan creates a NOTICE file in Phase 1d but Phase 6a also says "Create NOTICE file."** These are the same file. Phase 6a should say "Verify NOTICE file content" rather than "Create" to avoid confusion during execution. The plan even notes "(see Phase 6a for content)" in Phase 1d, creating a forward reference that could cause the executor to skip or double-create.

### 2b. Coupling Analysis

The fork introduces a new coupling pattern: **commands reference agents by Task dispatch name**. This is an implicit contract -- if an agent file is renamed, the command silently falls back to an inline description. The plan handles this well for the 3 renamed agents (updating dispatch names in review.md), but:

**SERIOUS: No centralized agent registry exists.** The mapping between command dispatch names and agent files is spread across 8 command files. Phase 7d's cross-reference verification is manual. For 22 agents, this is manageable. At scale, this is fragile.

**Recommendation:** Consider adding an agent manifest (even just a comment block or table in CLAUDE.md) that lists all agent names and which commands dispatch them. This serves as a single-source-of-truth for Phase 7d verification and future maintenance.

---

## 3. Directory Organization Assessment

### 3a. Structure: SCALES WELL

The proposed structure mirrors compound-engineering's `research/`, `review/`, `workflow/` categorization. This is a sound choice:
- Categories map to dispatch patterns (research agents run first in plan/deepen-plan, review agents run in review, workflow agents are utilities)
- The hierarchy is flat within categories (no nested subdirectories for agents)
- Skills use their own subdirectories for multi-file bundles, which is appropriate

### 3b. Naming Conflicts: TWO ISSUES

1. **SERIOUS: The `setup` skill and `setup` command create an ambiguous dual-artifact.** Both `skills/setup/SKILL.md` and `commands/compound-workflows/setup.md` exist for the same feature. The plan addresses this in Phase 5c ("both will exist"), but the relationship is unusual within the plugin architecture. No other feature has this pattern. The skill has `disable-model-invocation: true`, meaning it is reference-only material that the command reads. This is a valid pattern, but it needs documentation because it breaks the convention that skills and commands are independent.

2. **MINOR: `compound-docs` skill name may confuse.** The skill is about documenting compound knowledge (solution capture), not about the compound-workflows plugin's own documentation. This name was inherited from compound-engineering where it made more sense. Consider whether this causes confusion in the compound-workflows context, where "compound" is the plugin namespace.

### 3c. Missing Category

The brainstorm lists agents in a `docs/` category (from compound-engineering's `agents/docs/*`), which the plan explicitly drops. However, the deepen-plan discovery logic in the current code (lines 104-106) references `agents/docs/*` in the USE list. The plan's Phase 5b correctly removes this, but it is worth confirming no other command references the `docs/` agent category.

---

## 4. Commit Strategy Assessment

### 4a. Five-Commit Structure: WELL-SCOPED

The commit boundaries are logically clean:

| Commit | Content | Dependency | Verdict |
|--------|---------|------------|---------|
| 1 | Pure copy + NOTICE | None | Clean isolation. Byte-verifiable. |
| 2 | Rename + genericize | Depends on Commit 1 files existing | Sound. All content mods in one commit. |
| 3 | HIGH-effort mods (setup skill, orchestrating-swarms) | Depends on agent names finalized in Commit 2 | Sound. Isolates risk. |
| 4 | Command updates | Depends on all agent names and skill structure finalized | Sound ordering. |
| 5 | Docs + config | Depends on final counts | Sound. Last commit, easy to amend if counts shift. |

### 4b. Ordering Risks: ONE CONCERN

**SERIOUS: Commit 2 bundles Phase 2 (LOW-effort) and Phase 3 (MEDIUM-effort) into a single commit, but these have different risk profiles.** Phase 3 includes persona removal and example genericization, which are judgment calls (e.g., replacing "Eastern-European and Dutch directness" with "Direct and precise"). If any genericization decision needs to be reverted, the entire commit must be unpicked, including the simple Phase 2 string replacements.

**Recommendation:** Consider splitting Commit 2 into two: one for LOW-effort mechanical changes (Phase 2), one for MEDIUM-effort editorial changes (Phase 3). This keeps the "judgment call" changes isolated. However, this is a minor concern -- the plan's canonical genericization table already constrains the replacement space, reducing the risk of needing to revert individual decisions.

### 4c. Context Exhaustion Handling: GOOD

The plan explicitly addresses context exhaustion with the `work-agents` dispatch strategy (one subagent per commit's worth of work). The manifest-based recovery pattern from the existing deepen-plan command is well-suited to this. The plan's Phase 1 verification step after every commit provides a checkpoint that enables resumption.

---

## 5. Dependency Management Assessment

### 5a. compound-engineering to compound-workflows Transition: THOROUGH

The plan handles the namespace transition systematically:
- The canonical genericization table provides exact replacement strings
- Phase 7b's grep sweep catches missed references
- The orchestrating-swarms file gets special treatment (per-instance review, not bulk replace) -- this is the correct call for a 1580-line file with three categories of references

### 5b. TWO GAPS in Dependency Management

1. **SERIOUS: The existing `setup.md` command still recommends installing compound-engineering.** Lines 86-89 of the current `setup.md` show: `"claude /install compound-engineering"`. After the fork, the setup command should detect compound-engineering as a CONFLICT, not recommend it. The plan addresses this in Phase 5c, but the risk is that a partially-completed port (e.g., Commits 1-3 done, Commit 4 not yet) leaves users in a state where setup still recommends the conflicting plugin.

   **Recommendation:** Phase 5c (Commit 4) should be treated as a blocking dependency for any pre-release testing. The plan's Phase 7g smoke tests cover this, but explicitly flag that Commits 1-3 should NOT be published independently.

2. **MEDIUM: The `compound-workflows.local.md` config file written by setup still has `review_agents: [compound-engineering|general-purpose]` as a possible value.** After the fork, this should be `review_agents: [bundled|general-purpose]` or similar, since the agents are no longer from compound-engineering. The plan's Phase 5c describes rewriting setup.md but does not explicitly call out updating the config file's vocabulary.

   **Recommendation:** Add a line item to Phase 5c: update the `compound-workflows.local.md` template to replace "compound-engineering" with "bundled" (or similar) in the `review_agents` field.

### 5c. Dropped Agent References: WELL-HANDLED

The plan correctly identifies all places where dropped agents (Rails reviewers, Figma agents, design agents) are referenced and specifies their removal. The grep sweep in Phase 7b covers the common patterns (`kieran-rails`, `dhh-rails`, etc.).

---

## 6. Discovery Logic Assessment (Phase 5b)

### 6a. Current State

The existing `deepen-plan.md` (lines 98-107) has a three-step discovery:
1. Find ALL plugin agents via `find ~/.claude/plugins/cache -path "*/agents/*.md"`
2. Find local/global agents
3. Apply a compound-engineering-specific filter (USE: review/research/design/docs, SKIP: workflow)

### 6b. Proposed Generic Filter: SOUND with ONE RISK

The plan proposes replacing the compound-engineering-specific filter with a generic one:
- USE: agents in `review/` and `research/` subdirectories
- SKIP: agents in `workflow/` subdirectories

**Strengths:**
- This is plugin-agnostic -- it works for any plugin that follows the `research/review/workflow` convention
- It correctly drops `design/` and `docs/` categories (not ported)
- It handles the case where compound-workflows' agents are in the cache AND the source directory

**Risk:**

**SERIOUS: The generic filter assumes all plugins follow the same directory convention.** If a user has another plugin with an `agents/review/` directory, those agents will be swept into deepen-plan's roster. This is actually a *feature* for extensibility, but it means deepen-plan could dispatch agents it knows nothing about.

The current compound-engineering-specific filter is narrow and predictable. The generic filter is broad and depends on convention.

**Recommendation:** The generic filter is the correct architectural direction -- it follows the Open/Closed principle (new plugins can add agents without modifying deepen-plan). However, add a safeguard: when dispatching discovered agents, include a `description:` field from the agent's YAML frontmatter in the manifest. This gives the user visibility into what was discovered and enables filtering in future iterations. The plan's Step 2d already captures agent name and type in the manifest, but adding the description field would make the roster self-documenting.

### 6c. Development Mode Coverage

The plan notes: "Verify the `find` command on line 98 also catches agents in development mode (source dir, not just cache)." This is an important detail. The current `find` only searches `~/.claude/plugins/cache`, which is the installed location. During development, agents live in the source tree (`plugins/compound-workflows/agents/`).

**Recommendation:** Ensure the discovery logic includes a check for agents in the current project's plugin source directory (if it exists). This is likely already handled by the `find .claude/agents` step, but verify that `plugins/*/agents/` is also covered.

---

## 7. Setup Command/Skill Split Assessment

### 7a. The Dual-Artifact Pattern: JUSTIFIED but NOVEL

The plan proposes:
- **Command** (`setup.md`): Interactive entry point handling UX flow, environment detection, config writing
- **Skill** (`setup/SKILL.md`): Reference material with `disable-model-invocation: true` providing stack detection logic, agent lists, depth options

**Justification assessment:**

This pattern is justified for two reasons:
1. The setup skill from compound-engineering contains substantial domain knowledge (stack detection heuristics, per-stack agent configurations, depth options) that is useful as reference material even outside the interactive setup flow
2. The command needs to be thin (handle user interaction) while the knowledge base is large -- splitting them follows Separation of Concerns

**However:**

**MEDIUM: This is the only command in the plugin that reads a skill for configuration knowledge.** Every other command is self-contained or dispatches agents directly. This breaks the established pattern where commands and skills are independent artifacts.

**Recommendation:** Document this pattern explicitly in CLAUDE.md. Something like: "The setup command reads the setup skill for configuration knowledge. This is a deliberate split: the command handles the interactive flow, the skill provides the domain knowledge. Other commands should not adopt this pattern without justification."

### 7b. Overengineering Risk: LOW

The alternative would be a single large `setup.md` that contains both the interaction flow and the configuration knowledge. At the current size of the setup skill (~200-300 lines of stack detection + agent configuration), this would make setup.md unwieldy. The split is pragmatic.

However, if the setup skill grows significantly (adding more stacks, more agent configurations), it could become a maintenance burden -- changes to agent lists would need to be reflected in both the skill and the commands that dispatch those agents.

### 7c. Conflict Detection: WELL-DESIGNED

The setup command's compound-engineering conflict detection (`ls ~/.claude/plugins/cache/*/compound-engineering 2>/dev/null`) is the right approach:
- It checks the actual installed location, not a version file
- It warns rather than blocks (user might have legitimate reasons to keep both)
- It runs early in the setup flow (Step 2) before any configuration is written

---

## 8. Risk Analysis Summary

### Critical Risks (address before execution)

None. The plan is thorough enough that no single failure would be unrecoverable.

### Serious Risks (address during execution)

| # | Risk | Location | Recommendation |
|---|------|----------|----------------|
| S1 | No structured upstream sync mechanism | Plan-wide | Add FORK-MANIFEST.yaml tracking source version, modification status per file |
| S2 | No centralized agent registry | Plan-wide | Add agent manifest to CLAUDE.md mapping dispatch names to files |
| S3 | Commit 2 bundles LOW and MEDIUM risk changes | Commit Strategy | Consider splitting into two commits (minor concern if canonical table is followed) |
| S4 | Intermediate commits leave setup recommending compound-engineering | Phase 5c | Flag that pre-Commit-4 states should not be tested as "release candidates" |
| S5 | Generic discovery filter sweeps in unknown plugin agents | Phase 5b | Add agent description to discovery manifest for visibility |
| S6 | `compound-workflows.local.md` still references compound-engineering vocabulary | Phase 5c | Update config template vocabulary |

### Medium Risks

| # | Risk | Location | Recommendation |
|---|------|----------|----------------|
| M1 | Setup command/skill split is a novel pattern | Phase 4a/5c | Document in CLAUDE.md |
| M2 | `compound-docs` skill name ambiguity | Directory Organization | Consider renaming or add a description line in skill frontmatter |

### Minor Risks

| # | Risk | Location | Recommendation |
|---|------|----------|----------------|
| m1 | NOTICE file created in Phase 1d, re-described in Phase 6a | Phases 1d/6a | Clarify Phase 6a as "verify content" not "create" |
| m2 | Development-mode agent discovery | Phase 5b | Verify plugins/*/agents/ is covered by find commands |

---

## 9. Compliance Check

### SOLID Principles

| Principle | Status | Notes |
|-----------|--------|-------|
| Single Responsibility | UPHELD | Commands orchestrate, agents analyze, skills provide knowledge |
| Open/Closed | UPHELD (with caveats) | Generic discovery filter follows O/C. But agent dispatch names in commands are hardcoded -- adding a new agent requires editing the command |
| Liskov Substitution | N/A | No inheritance hierarchy |
| Interface Segregation | UPHELD | Agents have focused responsibilities. Skills are independent bundles |
| Dependency Inversion | PARTIALLY VIOLATED | Commands depend directly on agent file names (concrete implementations). The inline role descriptions serve as a "fallback interface," which is good, but the coupling to specific agent names remains |

### Architectural Patterns

- **Disk persistence pattern**: Consistently applied across all commands. The fork preserves this.
- **Context-safe orchestration**: Commands stay lean, agents write to disk. The fork adds more agents but does not change the pattern.
- **Graceful degradation**: Inline role descriptions serve as fallback when agents are missing. The fork makes this less likely to trigger (agents are now bundled) but preserves the mechanism.

---

## 10. Recommendations (Prioritized)

### Must-Do (before execution begins)

1. **Add FORK-MANIFEST.yaml** tracking per-file source path, source version, and modification status. Without this, the promised "upstream sync" will be ad-hoc and error-prone.

2. **Update Phase 5c** to include `compound-workflows.local.md` vocabulary changes (`compound-engineering` -> `bundled`).

3. **Clarify Phase 1d/6a overlap** to prevent executor confusion on the NOTICE file.

### Should-Do (during execution)

4. **Add agent description to deepen-plan discovery manifest** (Step 2d) for self-documenting agent rosters.

5. **Document the setup command/skill split pattern** in CLAUDE.md as an explicit architectural decision.

6. **Add an agent registry table** to CLAUDE.md listing all 22 agents, their categories, and which commands dispatch them.

### Consider (post-v1.1.0)

7. **Evaluate splitting Commit 2** if the genericization decisions prove contentious during review.

8. **Rename `compound-docs`** to something less ambiguous (e.g., `knowledge-docs` or `solution-docs`) if user feedback indicates confusion.

---

## 11. Overall Assessment

**Verdict: PROCEED.** The plan is architecturally sound, well-structured, and addresses the key risks identified during brainstorm red-teaming. The five-commit strategy provides clean isolation between copy, modify, and integrate phases. The main architectural gap is the lack of a structured upstream sync mechanism -- the FORK-MANIFEST recommendation should be adopted before execution to avoid accumulating undocumented drift. The discovery logic rewrite is the right architectural direction (generic over specific), and the setup command/skill split is justified but should be documented as a deliberate pattern exception.

The plan reflects careful analysis: the per-instance review approach for orchestrating-swarms, the canonical genericization table, and the comprehensive Phase 7 verification all indicate mature architectural thinking. The ~96-file scope is large but the phased approach with per-commit verification makes it manageable.
