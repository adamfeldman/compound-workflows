# Agent Port Gap Analysis: compound-workflows vs. compound-engineering

**Date:** 2025-02-25
**Scope:** All 7 command files in compound-workflows plugin, cross-referenced against all 29 agents in compound-engineering plugin.

---

## 1. Complete Agent Inventory in compound-engineering

### research/ (5 agents)
1. `repo-research-analyst` -- Repository structure and pattern discovery
2. `best-practices-researcher` -- External best practices, docs, community standards
3. `framework-docs-researcher` -- Official docs, version-specific constraints
4. `learnings-researcher` -- Searches docs/solutions/ for institutional knowledge
5. `git-history-analyzer` -- Git archaeology, code evolution tracing

### review/ (15 agents)
6. `kieran-typescript-reviewer` -- TypeScript type safety and patterns
7. `pattern-recognition-specialist` -- Design patterns, anti-patterns, naming
8. `architecture-strategist` -- Architectural impact and design integrity
9. `security-sentinel` -- Security audits, OWASP compliance
10. `performance-oracle` -- Performance bottlenecks and scalability
11. `code-simplicity-reviewer` -- YAGNI, unnecessary complexity
12. `agent-native-reviewer` -- Agent-native parity (user action = agent action)
13. `data-migration-expert` -- Migration safety, ID mappings, rollback
14. `deployment-verification-agent` -- Go/No-Go checklists, SQL verification
15. `kieran-rails-reviewer` -- Rails conventions and quality
16. `dhh-rails-reviewer` -- DHH philosophy, Rails convention enforcement
17. `julik-frontend-races-reviewer` -- Frontend race conditions, timing issues
18. `data-integrity-guardian` -- Database migration safety, privacy compliance
19. `schema-drift-detector` -- Unrelated schema.rb changes in PRs
20. `kieran-python-reviewer` -- Python patterns and type safety

### workflow/ (5 agents)
21. `spec-flow-analyzer` -- Spec completeness, edge cases, user flow gaps
22. `bug-reproduction-validator` -- Systematic bug reproduction and validation
23. `every-style-editor` -- Every editorial style guide compliance
24. `lint` -- Ruby/ERB linting (standardrb, erblint, brakeman)
25. `pr-comment-resolver` -- PR review comment resolution

### design/ (3 agents)
26. `design-implementation-reviewer` -- Figma vs. implementation comparison
27. `design-iterator` -- Iterative UI refinement cycles
28. `figma-design-sync` -- Pixel-perfect Figma-to-code sync

### docs/ (1 agent)
29. `ankane-readme-writer` -- Ankane-style README for Ruby gems

---

## 2. Agent References Found in Each Command

### 2.1 brainstorm.md

| Agent Reference | Dispatch Type | Inline Role Description? | compound-engineering Agent? |
|---|---|---|---|
| `repo-research-analyst` | Task (run_in_background) | YES: "You are a repository research analyst specializing in codebase pattern discovery and architectural analysis." | YES -- `research/repo-research-analyst.md` |
| `context-researcher` | Task (run_in_background) | YES: "You are a context researcher specializing in synthesizing project knowledge across documentation, solutions, brainstorms, plans, and institutional memory." | **PORTED** -- `agents/research/context-researcher.md` in compound-workflows |
| `general-purpose` | Task (run_in_background), fallback for PAL | YES: "You are a red team reviewer. Your job is to find flaws, not validate." | N/A -- generic subagent, not a named compound-engineering agent |

### 2.2 plan.md

| Agent Reference | Dispatch Type | Inline Role Description? | compound-engineering Agent? |
|---|---|---|---|
| `repo-research-analyst` | Task (run_in_background) | YES: "You are a repository research analyst specializing in codebase pattern discovery." | YES -- `research/repo-research-analyst.md` |
| `learnings-researcher` | Task (run_in_background) | YES: "You are an institutional knowledge researcher. Search docs/solutions/ for relevant past solutions." | YES -- `research/learnings-researcher.md` |
| `best-practices-researcher` | Task (run_in_background) | YES: "You are a best practices researcher specializing in external documentation and community standards." | YES -- `research/best-practices-researcher.md` |
| `framework-docs-researcher` | Task (run_in_background) | YES: "You are a framework documentation researcher specializing in official docs and version-specific constraints." | YES -- `research/framework-docs-researcher.md` |
| `spec-flow-analyzer` | Task (run_in_background) | YES: "You are a specification flow analyst specializing in completeness, edge cases, and user flow gaps." | YES -- `workflow/spec-flow-analyzer.md` |
| `general-purpose` | Task (synthesis agent) | Inline synthesis instructions | N/A -- generic subagent |

### 2.3 work.md

| Agent Reference | Dispatch Type | Inline Role Description? | compound-engineering Agent? |
|---|---|---|---|
| `code-simplicity-reviewer` | Task (run_in_background), optional | YES: "You are a code simplicity reviewer. Check for unnecessary complexity, YAGNI violations, and over-engineering." | YES -- `review/code-simplicity-reviewer.md` |

**Note:** work.md mentions "reviewer agents" generically and shows the code-simplicity-reviewer as an example. It says "Same pattern for other reviewers" but does not name specific additional agents.

### 2.4 work-agents.md

| Agent Reference | Dispatch Type | Inline Role Description? | compound-engineering Agent? |
|---|---|---|---|
| `general-purpose` | Task (foreground, per step) | Constructed from bd issue description | N/A -- generic subagent for step execution |
| `code-simplicity-reviewer` | Task (run_in_background), optional Phase 3 | YES: "You are a code simplicity reviewer. Check for unnecessary complexity, YAGNI violations, and over-engineering." | YES -- `review/code-simplicity-reviewer.md` |

### 2.5 review.md

| Agent Reference | Dispatch Type | Inline Role Description? | compound-engineering Agent? |
|---|---|---|---|
| `kieran-typescript-reviewer` | Task (run_in_background) | YES: "You are a TypeScript code reviewer focused on type safety, modern patterns, and maintainability." | YES -- `review/kieran-typescript-reviewer.md` |
| `pattern-recognition-specialist` | Task (run_in_background) | YES: "You are a pattern recognition specialist. Analyze for design patterns, anti-patterns, naming conventions, and duplication." | YES -- `review/pattern-recognition-specialist.md` |
| `architecture-strategist` | Task (run_in_background) | YES: "You are an architecture strategist. Review architectural impact, pattern compliance, and design integrity." | YES -- `review/architecture-strategist.md` |
| `security-sentinel` | Task (run_in_background) | YES: "You are a security auditor. Check for vulnerabilities, input validation, auth/authz issues, and OWASP compliance." | YES -- `review/security-sentinel.md` |
| `performance-oracle` | Task (run_in_background) | YES: "You are a performance analyst. Check for bottlenecks, algorithmic complexity, database queries, memory usage." | YES -- `review/performance-oracle.md` |
| `code-simplicity-reviewer` | Task (run_in_background) | YES: "You are a code simplicity reviewer. Check for unnecessary complexity, YAGNI violations, and over-engineering." | YES -- `review/code-simplicity-reviewer.md` |
| `agent-native-reviewer` | Task (run_in_background) | YES: "You are an agent-native reviewer. Verify any action a user can take, an agent can also take." | YES -- `review/agent-native-reviewer.md` |
| `data-migration-expert` | Task (run_in_background), conditional | YES: "You are a data migration expert. Validate migrations, backfills, and production data transformations." | YES -- `review/data-migration-expert.md` |
| `deployment-verification-agent` | Task (run_in_background), conditional | YES: "You are a deployment verification specialist. Produce Go/No-Go checklists with SQL verification queries and rollback procedures." | YES -- `review/deployment-verification-agent.md` |
| `kieran-rails-reviewer` | Task (run_in_background), conditional | YES: "You are a Rails code reviewer focused on Rails conventions, ActiveRecord patterns, and idiomatic Ruby." | YES -- `review/kieran-rails-reviewer.md` |
| `dhh-rails-reviewer` | Task (run_in_background), conditional | YES: "You are a Rails reviewer channeling DHH's philosophy: convention over configuration, minimal abstraction, Basecamp-style simplicity." | YES -- `review/dhh-rails-reviewer.md` |
| `julik-frontend-races-reviewer` | Task (run_in_background), conditional | YES: "You are a frontend concurrency reviewer. Check for race conditions, stale closures, unhandled promises, and UI state synchronization issues." | YES -- `review/julik-frontend-races-reviewer.md` |

### 2.6 compound.md

| Agent Reference | Dispatch Type | Inline Role Description? | compound-engineering Agent? |
|---|---|---|---|
| `general-purpose` | Task (run_in_background) -- Context Analyzer | YES: "You are a context analyzer specializing in problem classification and root cause identification." | N/A -- generic, role in prompt |
| (unnamed) Solution Extractor | Task (run_in_background) | Described by role, no agent name | N/A |
| (unnamed) Related Docs Finder | Task (run_in_background) | Described by role, no agent name | N/A |
| (unnamed) Prevention Strategist | Task (run_in_background) | Described by role, no agent name | N/A |
| (unnamed) Category Classifier | Task (run_in_background) | Described by role, no agent name | N/A |
| `performance-oracle` | Phase 3 reference, conditional | Name-only reference for performance_issue type | YES -- `review/performance-oracle.md` |
| `security-sentinel` | Phase 3 reference, conditional | Name-only reference for security_issue type | YES -- `review/security-sentinel.md` |
| `data-integrity-guardian` | Phase 3 reference, conditional | Name-only reference for database_issue type | YES -- `review/data-integrity-guardian.md` |

### 2.7 deepen-plan.md

| Agent Reference | Dispatch Type | Inline Role Description? | compound-engineering Agent? |
|---|---|---|---|
| (dynamic discovery) | Phase 2c discovery step | Discovers agents at runtime via filesystem search of compound-engineering agents | All review/*, research/*, design/*, docs/* agents |
| `general-purpose` | Task (synthesis agent) | Inline synthesis instructions | N/A |
| `general-purpose` | Task (red team fallback) | Inline red team instructions | N/A |

**Key detail from deepen-plan.md Phase 2c:**
```
For compound-engineering plugin:
- USE: agents/review/*, agents/research/*, agents/design/*, agents/docs/*
- SKIP: agents/workflow/*
```
This means deepen-plan dynamically discovers and dispatches ALL non-workflow compound-engineering agents at runtime.

---

## 3. Categorized Analysis

### Category A: Already Ported to compound-workflows Plugin

| Agent | Status |
|---|---|
| `context-researcher` | **PORTED** -- Full agent definition at `plugins/compound-workflows/agents/research/context-researcher.md`. This is the ONLY agent ported so far. |

### Category B: Referenced by Commands but NOT Ported (THE GAP)

These agents are referenced by name in command Task dispatches. The commands include inline role descriptions as fallback, so they "work" without the agent definitions, but lose all the detailed expertise, examples, methodology, and quality standards that the full agent definitions provide.

| # | Agent Name | Referenced By | Inline Fallback? | Importance |
|---|---|---|---|---|
| 1 | `repo-research-analyst` | brainstorm.md, plan.md | YES -- 1-sentence role | **CRITICAL** -- Core research agent for both brainstorm and plan. Full agent has structured research methodology (5 phases), output format, search strategies, quality assurance. Inline fallback loses all of this. |
| 2 | `learnings-researcher` | plan.md | YES -- 1-sentence role | **HIGH** -- Institutional knowledge surfacing. Full agent has a sophisticated 7-step grep-first filtering strategy, frontmatter schema reference, efficiency guidelines, critical-patterns.md integration. Inline fallback is a generic "search docs/solutions/" instruction. |
| 3 | `best-practices-researcher` | plan.md | YES -- 1-sentence role | **HIGH** -- External research. Full agent has 3-phase methodology (check skills first, deprecation check, then online), source attribution hierarchy. Inline fallback is just "research best practices for X". |
| 4 | `framework-docs-researcher` | plan.md | YES -- 1-sentence role | **HIGH** -- Framework documentation. Full agent has Context7 integration, deprecation/sunset checking, source code analysis via bundle show, version-specific docs. Inline fallback loses all methodology. |
| 5 | `spec-flow-analyzer` | plan.md | YES -- 1-sentence role | **HIGH** -- Completeness analysis. Full agent has 4-phase analysis (flow analysis, permutation discovery, gap identification, question formulation) with structured output. Inline fallback is a generic "analyze for completeness". |
| 6 | `code-simplicity-reviewer` | work.md, work-agents.md, review.md | YES -- 1-sentence role | **MEDIUM** -- Review agent. Full agent has structured output format, 6-point review methodology, YAGNI rigor. Used in 3 commands but always as an optional quality check, not a core flow step. |
| 7 | `kieran-typescript-reviewer` | review.md | YES -- 1-sentence role | **MEDIUM** -- Language-specific reviewer. Full agent has 10 review principles with concrete pass/fail examples. Only used in review.md. |
| 8 | `pattern-recognition-specialist` | review.md | YES -- 1-sentence role | **MEDIUM** -- Pattern analysis. Full agent has structured 6-step workflow and reporting format. Only used in review.md. |
| 9 | `architecture-strategist` | review.md | YES -- 1-sentence role | **MEDIUM** -- Architecture review. Full agent has SOLID principles check, coupling analysis, API contract verification. Only used in review.md. |
| 10 | `security-sentinel` | review.md, compound.md | YES -- 1-sentence role (review), name-only (compound) | **MEDIUM** -- Security auditing. Full agent has 6-section scanning protocol, OWASP checklist, Rails-specific checks. Used in review.md core flow and compound.md conditional enhancement. |
| 11 | `performance-oracle` | review.md, compound.md | YES -- 1-sentence role (review), name-only (compound) | **MEDIUM** -- Performance analysis. Full agent has 6-area framework (algorithmic, database, memory, caching, network, frontend), benchmarks. Same usage pattern as security-sentinel. |
| 12 | `agent-native-reviewer` | review.md | YES -- 1-sentence role | **MEDIUM** -- Agent-native parity. Full agent has 5-step review process, common anti-patterns library, mobile-specific checks. Only used in review.md. |
| 13 | `data-migration-expert` | review.md | YES -- 1-sentence role | **LOW** -- Conditional reviewer (only for PRs with DB migrations). Full agent has detailed checklist, SQL snippets, common bugs. |
| 14 | `deployment-verification-agent` | review.md | YES -- 1-sentence role | **LOW** -- Conditional reviewer (only for PRs with risky data changes). Full agent has Go/No-Go template, monitoring plan. |
| 15 | `kieran-rails-reviewer` | review.md | YES -- 1-sentence role | **LOW** -- Conditional reviewer (only for Rails PRs). Full agent has 9 review principles. |
| 16 | `dhh-rails-reviewer` | review.md | YES -- 1-sentence role | **LOW** -- Conditional reviewer (only for Rails PRs). Full agent has DHH philosophy and pattern recognition. |
| 17 | `julik-frontend-races-reviewer` | review.md | YES -- 1-sentence role | **LOW** -- Conditional reviewer (only for frontend PRs). Full agent has 10 sections on race conditions. |
| 18 | `data-integrity-guardian` | compound.md | Name-only reference | **LOW** -- Referenced only as a conditional Phase 3 enhancement in compound.md for database_issue type. |

### Category C: Available in compound-engineering but NOT Referenced

These agents exist in compound-engineering but are never referenced by any compound-workflows command.

| Agent | Category | Why Not Referenced |
|---|---|---|
| `git-history-analyzer` | research | Not used by any workflow command. Could be useful for plan or deepen-plan research phases. |
| `schema-drift-detector` | review | Not included in review.md's agent roster. Specialized Rails/ActiveRecord agent. |
| `kieran-python-reviewer` | review | Not included in review.md's agent roster. Language-specific. |
| `bug-reproduction-validator` | workflow | Workflow agent -- deepen-plan explicitly SKIPs workflow/* agents. Not used by other commands either. |
| `every-style-editor` | workflow | Workflow agent -- deepen-plan skips. Company-specific (Every brand). |
| `lint` | workflow | Workflow agent -- deepen-plan skips. Project-specific (Ruby/ERB). |
| `pr-comment-resolver` | workflow | Workflow agent -- deepen-plan skips. Could be relevant to review.md but isn't referenced. |
| `design-implementation-reviewer` | design | Not referenced by any command. Requires agent-browser + Figma MCP. |
| `design-iterator` | design | Not referenced by any command. Requires agent-browser. |
| `figma-design-sync` | design | Not referenced by any command. Requires Figma MCP + agent-browser. |
| `ankane-readme-writer` | docs | Not referenced by any command. Ruby gem-specific. |

**Note:** deepen-plan.md discovers agents/design/* and agents/docs/* dynamically at runtime (Phase 2c), so these ARE potentially used by deepen-plan even though they aren't explicitly named. However, they would only be discovered if compound-engineering is installed alongside compound-workflows.

---

## 4. The Impact of Not Porting

### How the fallback works today

When compound-workflows dispatches `Task repo-research-analyst`, Claude Code looks for:
1. An agent definition file named `repo-research-analyst.md` in any installed plugin's agents/ directory
2. If NOT found, it falls back to the inline role description in the Task prompt

The inline fallback approach means the commands **function** without the ported agents, but with severely degraded quality:

| What the full agent provides | What the inline fallback provides |
|---|---|
| Structured 5-phase research methodology | "You are a repository research analyst" (1 sentence) |
| Output format templates with sections | No format guidance |
| Search strategy documentation | No search guidance |
| Quality assurance checklist | No quality checks |
| Examples showing ideal usage | No examples |
| Tool usage patterns (Grep, Glob, ast-grep) | No tool guidance |
| Integration points with other agents | No integration awareness |
| Edge case handling | No edge case handling |

### Quantified gap

- **Total agents referenced across all commands:** 18 unique named agents
- **Already ported:** 1 (context-researcher)
- **Gap:** 17 agents referenced but not ported
- **Of those, CRITICAL/HIGH importance:** 5 (repo-research-analyst, learnings-researcher, best-practices-researcher, framework-docs-researcher, spec-flow-analyzer)
- **MEDIUM importance:** 7 (the core review agents used by review.md)
- **LOW importance:** 5 (conditional/specialized reviewers)

---

## 5. Priority Recommendation

### Tier 1 -- Port Immediately (CRITICAL/HIGH)

These are used in the core brainstorm + plan flow. Every user hits them.

1. **repo-research-analyst** -- Used by brainstorm.md AND plan.md
2. **learnings-researcher** -- Used by plan.md, sophisticated grep-first strategy
3. **best-practices-researcher** -- Used by plan.md, has deprecation checking
4. **framework-docs-researcher** -- Used by plan.md, has Context7 integration
5. **spec-flow-analyzer** -- Used by plan.md, has 4-phase analysis

### Tier 2 -- Port Next (MEDIUM)

These power the review command's full agent roster.

6. **code-simplicity-reviewer** -- Used in 3 commands
7. **kieran-typescript-reviewer** -- Standard reviewer
8. **pattern-recognition-specialist** -- Standard reviewer
9. **architecture-strategist** -- Standard reviewer
10. **security-sentinel** -- Standard reviewer + compound.md
11. **performance-oracle** -- Standard reviewer + compound.md
12. **agent-native-reviewer** -- Standard reviewer

### Tier 3 -- Port Later (LOW)

Conditional/specialized reviewers.

13. **data-integrity-guardian** -- compound.md conditional
14. **data-migration-expert** -- review.md conditional
15. **deployment-verification-agent** -- review.md conditional
16. **kieran-rails-reviewer** -- review.md conditional (Rails only)
17. **dhh-rails-reviewer** -- review.md conditional (Rails only)
18. **julik-frontend-races-reviewer** -- review.md conditional (frontend only)

### Not Referenced -- Consider for Future

- `git-history-analyzer` -- Could add value to plan or deepen-plan research
- `schema-drift-detector` -- Could add to review.md conditional roster
- `kieran-python-reviewer` -- Could add to review.md conditional roster
- Design agents (3) -- Require external tools (agent-browser, Figma MCP)
- Workflow agents (4) -- Company/project-specific, explicitly skipped by deepen-plan

---

## 6. Porting Considerations

### What porting means

Each agent definition file provides:
- YAML frontmatter (name, description, model)
- Examples block (usage scenarios)
- Full system prompt (methodology, output format, guidelines)

Porting means copying the agent .md file into `plugins/compound-workflows/agents/<category>/` so it ships with the plugin and is available without requiring compound-engineering to be separately installed.

### Model field concern

Several compound-engineering agents specify `model: haiku` (learnings-researcher) or `model: inherit`. The `model: haiku` setting is an optimization to use a cheaper model for simpler tasks. When porting, decide whether to keep these model preferences or standardize.

### Deduplication with compound-engineering

If a user has BOTH compound-workflows AND compound-engineering installed, there would be duplicate agent definitions. Claude Code's agent resolution order needs to be understood -- does the plugin's own agents/ take precedence? This should be tested.

### Generalization needed

Some agents contain company-specific references:
- `learnings-researcher` references "BriefSystem", "EmailProcessing" in examples
- `every-style-editor` is entirely company-specific
- `lint` is Ruby/ERB specific
- Examples in many agents reference Rails patterns

For a marketplace plugin, consider generalizing examples or making them framework-agnostic.
