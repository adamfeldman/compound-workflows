# Red Team Critique: Port Gaps Brainstorm

**Reviewer:** Claude Opus 4.6 (red team role)
**Date:** 2026-02-25
**Document reviewed:** `docs/brainstorms/2026-02-25-port-gaps-compound-engineering-brainstorm.md`
**Methodology:** Adversarial review against the actual codebase state, command files, research outputs, and stated assumptions.

---

## 1. Unexamined Assumptions

### 1a. "Users install ONE plugin and get everything" assumes agent resolution works correctly with forked agents

**Severity: SERIOUS**

The brainstorm states:

> "A complete fork of compound-engineering's agents and skills into the compound-workflows plugin, making it fully self-contained. Users install ONE plugin and get everything."

This assumes that Claude Code's agent resolution mechanism will correctly resolve forked agent names within the plugin's `agents/` directory when dispatched by commands. However, the existing commands dispatch agents using bare names like `Task repo-research-analyst` -- the brainstorm never verifies that Claude Code's `Task` dispatch resolves agent definitions from the same plugin's `agents/` directory. If agent resolution is global (across all plugins) rather than scoped to the dispatching plugin, the fork creates a different problem than it solves: now TWO plugins could define `repo-research-analyst` and the resolution order becomes the unpredictability the brainstorm claims to eliminate.

The brainstorm acknowledges this tangentially in the "Coexistence" row -- "Document 'don't install both'" -- but treats it as a documentation problem rather than a technical one. What if users already have compound-engineering installed and add compound-workflows? The brainstorm assumes they'll read the docs and uninstall one.

### 1b. "Examples kept as-is" assumes marketplace users will tolerate company-specific examples

**Severity: MINOR**

The brainstorm states:

> "Company-specific examples in agent prompts (e.g., 'BriefSystem', 'EmailProcessing' in learnings-researcher) are illustrative, not prescriptive. Faster to port, and users understand examples aren't literal requirements."

This is an assumption about marketplace user behavior. Developers installing a marketplace plugin are in a different context than internal team members who share context about "BriefSystem." Generic marketplace users encountering "BriefSystem" as an example will either (a) be mildly confused, (b) think the plugin is poorly generalized, or (c) not notice. Probably (c) for most, but it signals "internal tool hastily published" to discerning users. The brainstorm dismisses this too quickly by saying "Faster to port" -- which is a schedule argument, not a quality argument.

### 1c. spec-flow-analyzer is missing from the scope inventory

**Severity: SERIOUS**

The brainstorm lists 21 new agents to port across Research (6), Review (13), and Workflow (2). However, `spec-flow-analyzer` -- which the repo-research document categorizes as CRITICAL/HIGH and which `plan.md` dispatches directly -- does not appear anywhere in the brainstorm's scope inventory. The research output at `.workflows/brainstorm-research/port-gaps-compound-engineering/repo-research.md` lists it at position 21 (`workflow/spec-flow-analyzer`) and it appears as a Tier 1 priority (line 233: "spec-flow-analyzer -- Used by plan.md, has 4-phase analysis"). Yet the brainstorm's enumerated 21-agent list skips it entirely.

This is not a dropped agent -- it does not appear in the "Dropped (not porting)" section either. It is simply missing from the scope, which means the plan derived from this brainstorm will also miss it, and `plan.md` will continue dispatching a non-existent agent with only a 1-sentence inline fallback.

### 1d. The brainstorm assumes 21 agents is the complete gap

**Severity: MINOR**

The brainstorm titles itself "Port Gaps" but the gap analysis only counts agents referenced by commands or deemed useful. It does not account for agents that `deepen-plan.md` discovers dynamically at runtime (Phase 2c: `find ~/.claude/plugins/cache -path "*/agents/*.md"`). After the fork, `deepen-plan.md` still contains this filesystem discovery logic that searches compound-engineering's cache directory. If compound-engineering is not installed, this discovery returns nothing -- but the brainstorm's scope section does not mention updating `deepen-plan.md`'s discovery logic to also search compound-workflows' own agents directory. The "Commands: 7 existing, need updates" section only mentions updating agent references and removing Rails reviewer references, not fixing the dynamic discovery mechanism.

---

## 2. Missing Alternatives

### 2a. Wrapper/delegation pattern not considered

**Severity: SERIOUS**

The brainstorm presents "Fork over dependency" as the only serious alternative to the current state. It does not consider a middle path: a **thin wrapper that re-exports agents**.

Instead of copying 21 multi-page agent definitions (with ongoing maintenance burden), compound-workflows could define lightweight proxy agents that include the compound-engineering agent definition by reference:

```yaml
---
name: repo-research-analyst
description: "Proxy: loads full definition from compound-engineering if available"
---
# If compound-engineering is installed, this agent is superseded by its richer definition.
# This file provides the baseline methodology when compound-engineering is absent.
[condensed version of methodology]
```

This preserves the "one plugin" experience while reducing maintenance surface. The brainstorm never evaluates this tradeoff -- it jumps straight from "dependency is bad" to "full fork."

### 2b. No consideration of selective forking

**Severity: MINOR**

The brainstorm forks ALL 21 agents plus 14 skills. The repo-research document clearly tiered agents by priority: Tier 1 (5 CRITICAL/HIGH), Tier 2 (7 MEDIUM), Tier 3 (5 LOW plus 2 unreferenced). The brainstorm could have proposed forking only Tier 1 agents (the 5 that every user hits) and keeping compound-engineering as an optional dependency for the review-specific agents (Tier 2-3). This would reduce the fork surface by ~75% while covering the critical path. The brainstorm does not evaluate this partial-fork approach.

### 2c. No consideration of upstream contribution

**Severity: MINOR**

The brainstorm does not consider whether the naming collision problem could be solved upstream. If compound-engineering changed its command prefix (or compound-workflows changed its), the coexistence problem disappears. The brainstorm treats the naming collision as immutable rather than exploring whether a conversation with the upstream maintainer could solve it more cleanly than a fork.

---

## 3. Weak Arguments

### 3a. "Fork over dependency" argument conflates two problems

**Severity: SERIOUS**

The brainstorm states:

> "compound-engineering ships overlapping commands (`/workflows:brainstorm`, `/workflows:review`, `/workflows:compound`, `/deepen-plan`). Requiring it means users see both sets in the slash command picker with no clear way to distinguish."

This is actually two separate problems:
1. **Command namespace collision** -- both plugins register similar slash commands
2. **Agent quality degradation** -- without compound-engineering's agent definitions, inline fallbacks are weak

The brainstorm uses problem #1 (namespace collision) to justify a solution for problem #2 (fork all agents). But forking agents does NOT solve the namespace collision -- only dropping compound-engineering as a dependency does. And dropping compound-engineering as a dependency does NOT require forking agents -- it only requires accepting the inline fallback quality or finding another way to ship agent definitions.

By conflating these, the brainstorm avoids justifying the fork on its own merits (maintenance burden, divergence risk, update lag) and instead hides behind the namespace collision argument.

### 3b. "Depersonalized names" rationale is thin

**Severity: MINOR**

The brainstorm states:

> "Three agents carried contributor names (kieran-*, julik-*) that don't serve the marketplace audience. Renamed to descriptive names."

The rationale is stated as fact without evidence. Many successful open source projects use contributor names in tooling (e.g., "DHH-style" is a well-known pattern in Rails). The brainstorm renames `kieran-typescript-reviewer` to `typescript-reviewer` but does not consider that the rename creates a name collision risk: if compound-engineering also has a `typescript-reviewer` alias or if another plugin ships one, the generic name collides more easily than the specific one. The brainstorm's own concern about naming collisions between plugins would apply here too.

### 3c. "Version: 1.1.0 (MINOR)" may understate the change

**Severity: MINOR**

The brainstorm states:

> "Version: 1.1.0 (MINOR -- adding agents/skills)"

The brainstorm also states that this change removes compound-engineering as a dependency ("Remove compound-engineering as optional dependency -- plugin is now self-contained") and replaces the setup command content. The README currently lists compound-engineering as "Recommended" in the dependency table. Removing a recommended dependency and replacing a command's implementation (setup) could arguably be considered a breaking change for users who configured their workflow around the compound-engineering dependency. If a user's `compound-workflows.local.md` says `review_agents: compound-engineering`, and after the update the plugin ignores compound-engineering's agents, that user's workflow changes without a major version bump.

---

## 4. Hidden Risks

### 4a. Maintenance divergence from upstream

**Severity: CRITICAL**

This is the single biggest risk the brainstorm fails to address. Forking 21 agents and 14 skills creates a **permanent maintenance burden**. When compound-engineering improves `security-sentinel` with new OWASP checks, or updates `framework-docs-researcher` with new Context7 integration patterns, compound-workflows' fork will not receive those improvements.

The brainstorm has no plan for:
- How to track upstream changes to forked agents
- Whether to periodically re-sync with compound-engineering
- Who maintains 35+ forked definitions going forward
- How to handle the case where compound-engineering fixes a bug in an agent that compound-workflows has also forked

This is not mentioned in Key Decisions, Resolved Questions, or anywhere else. For a project that currently has 1 agent and 1 skill, jumping to 22 agents and 15 skills is a 22x increase in maintenance surface with zero plan for sustaining it.

### 4b. Skill dependencies and asset bundling are not addressed

**Severity: SERIOUS**

The brainstorm lists 14 new skills, several of which have complex directory structures:

> - `compound-docs/` (SKILL.md + assets/ + schema.yaml)
> - `create-agent-skills/` (SKILL.md + references/ + templates/ + workflows/)
> - `agent-native-architecture/` (SKILL.md + 12 reference docs)

The brainstorm does not address:
- How large is this content? (12 reference docs for agent-native-architecture alone)
- Do any skills depend on external tools that aren't listed? (e.g., `agent-browser` skill -- does it require a browser automation tool?)
- Do any skills reference compound-engineering paths that would need updating?
- What is the total size impact on the plugin package?

The scope lists these skills as "Utility" without evaluating whether they're truly useful to the general marketplace audience or whether they're internal tools that happened to live alongside the workflow.

### 4c. "Don't install both" is unenforceable

**Severity: SERIOUS**

The brainstorm states:

> "Document that compound-workflows supersedes compound-engineering. Install one or the other. Agent resolution with duplicates would be unpredictable."

This is documentation-only enforcement of a technical constraint. Claude Code's plugin system likely does not prevent installing both. If a user installs compound-workflows and later installs compound-engineering (perhaps for its Rails agents which were dropped), they enter the "unpredictable" state the brainstorm warns about. There is no technical mechanism proposed to detect this situation, warn the user, or degrade gracefully.

The setup command currently detects compound-engineering and displays it in the status table. After this change, the setup command would need to detect compound-engineering and WARN against it -- but the brainstorm's command update scope only says "Remove compound-engineering as optional dependency" without specifying that setup.md should add a conflict warning.

### 4d. Review.md still references Rails agents after the port

**Severity: SERIOUS**

The brainstorm states:

> "review.md: Remove Rails reviewer references (dhh-rails-reviewer, kieran-rails-reviewer)."

But looking at the actual `review.md` content (lines 67-68), the Rails reviewers are dispatched **conditionally**:

> "If PR has Rails code: `Task kieran-rails-reviewer` (...), `Task dhh-rails-reviewer` (...)"

The brainstorm drops these agents ("Dropped: dhh-rails-reviewer (Rails-specific), kieran-rails-reviewer (Rails-specific)") but does not consider: what happens when a Rails developer uses compound-workflows and runs `/compound-workflows:review` on a PR with Rails code? The conditional block fires, dispatches agents that don't exist, and falls back to generic. The brainstorm treats this as acceptable ("dropped") but never asks whether Rails users are part of the marketplace audience. Given that compound-engineering originated as a Rails-centric tool, dropping Rails support without a migration path could alienate the existing user base.

### 4e. No testing strategy for 35+ new components

**Severity: SERIOUS**

The brainstorm proposes adding 21 agents and 14 skills but includes no testing plan. How will you verify that:
- All 21 agents resolve correctly when dispatched by commands?
- The 3 renamed agents are correctly referenced everywhere?
- Skills with complex directory structures (compound-docs, create-agent-skills, agent-native-architecture) work correctly?
- The setup command correctly detects the new self-contained state?
- Commands that previously referenced compound-engineering agents now resolve them locally?

The CLAUDE.md testing section says "Test each modified command end-to-end" but with 7 commands, 21 new agents, and 14 new skills, end-to-end testing is a significant effort that the brainstorm does not scope.

---

## 5. Contradictions

### 5a. "Fork" vs. "Mirror compound-engineering structure"

**Severity: MINOR**

The brainstorm says:

> "Agent organization: Mirror compound-engineering structure (research/, review/, workflow/)"

But also says:

> "Fork agents/skills, no dependency"

If you're forking to become independent, why mirror the upstream's directory structure? This creates an implicit coupling: when compound-engineering reorganizes its agents, compound-workflows' mirrored structure becomes a false signal about compatibility. This is a minor tension, not a blocker, but it reveals that the brainstorm wants independence while still borrowing organizational decisions.

### 5b. "Dropped" agents vs. "review.md" conditional dispatch

**Severity: SERIOUS**

The brainstorm lists `dhh-rails-reviewer` and `kieran-rails-reviewer` under "Dropped (not porting)" but does not list them under the review.md changes to be made. It says:

> "review.md: Remove Rails reviewer references (dhh-rails-reviewer, kieran-rails-reviewer)."

This means the brainstorm plans to remove the conditional Rails review from `review.md` entirely. But `review.md` line 67-68 also conditionally dispatches `julik-frontend-races-reviewer` for frontend code. The brainstorm RENAMES this agent to `frontend-races-reviewer` and plans to PORT it -- but the review.md command still references the old name. The brainstorm says "Update 3 renamed agent refs (typescript-reviewer, python-reviewer, frontend-races-reviewer)" but does not specify that `review.md` currently says `kieran-typescript-reviewer` (line 55) not just the agent definition name. This is a consistency gap between the scope description and the actual work required.

### 5c. "22 total with existing context-researcher" vs. actual count

**Severity: MINOR**

The brainstorm states:

> "Agents: 21 new (22 total with existing context-researcher)"

But the enumerated list shows 21 agents numbered 1-21, with `context-researcher` at position 1 marked "already ported." That is 20 new agents + 1 existing = 21 total, not 22. Unless the brainstorm is counting an unlisted agent, the arithmetic is off by one.

Wait -- reviewing more carefully: the brainstorm says "21 new" and lists items 2-21 as new (20 items), plus item 1 as existing. So "21 new" does not match the list, which shows 20 new items. Either the count is wrong or an agent is missing from the enumeration.

Cross-referencing with section 1c above: `spec-flow-analyzer` is missing from the list. If it were included, the count would be 21 new + 1 existing = 22 total, matching the header. This confirms that `spec-flow-analyzer` was accidentally omitted from the enumerated list.

---

## Summary of Findings by Severity

### CRITICAL (1)
1. **4a. Maintenance divergence** -- No plan for tracking upstream changes to 35+ forked components. This is unsustainable.

### SERIOUS (7)
2. **1a. Agent resolution assumptions** -- Untested assumption that plugin-scoped agent resolution works as expected.
3. **1c. spec-flow-analyzer omission** -- A Tier 1 agent used by plan.md is missing from the scope entirely.
4. **2a. Wrapper pattern not considered** -- Middle-ground alternative would reduce fork surface while preserving the user experience.
5. **3a. Conflated problems** -- Namespace collision and agent quality are separate problems getting a single solution.
6. **4b. Skill dependencies** -- Complex skills with assets and reference docs not evaluated for size, dependencies, or audience fit.
7. **4c. "Don't install both" unenforceable** -- Documentation-only enforcement of a technical constraint.
8. **4d. Rails removal impact** -- Dropping Rails support without considering the existing Rails user base or migration path.
9. **4e. No testing strategy** -- 35+ new components with no testing plan.
10. **5b. Rename inconsistency** -- review.md references old names that need updating, but the scope description is imprecise about what exactly needs changing.

### MINOR (6)
11. **1b. Company-specific examples** -- "Faster to port" is a schedule argument, not a quality argument.
12. **1d. deepen-plan discovery logic** -- Dynamic agent discovery still searches compound-engineering's paths.
13. **2b. Selective forking** -- Partial fork not evaluated.
14. **2c. Upstream contribution** -- Solving the namespace collision upstream not considered.
15. **3b. Depersonalized names** -- Thin rationale; generic names may collide more easily.
16. **3c. Version 1.1.0** -- May understate the scope of change for users relying on compound-engineering dependency.
17. **5a. Fork but mirror** -- Minor tension between independence and mirrored structure.
18. **5c. Agent count arithmetic** -- 21 new does not match enumerated list (20 new), likely due to spec-flow-analyzer omission.
