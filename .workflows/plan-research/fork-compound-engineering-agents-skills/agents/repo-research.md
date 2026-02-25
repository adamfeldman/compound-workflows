# Repo Research: Fork compound-engineering Agents & Skills

## Current Plugin State

- **Plugin version:** 1.0.0 (`.claude-plugin/plugin.json`)
- **Components:** 8 commands, 1 agent (`context-researcher`), 1 skill (`disk-persist-agents`)
- **All commands namespaced:** `compound-workflows:*`

---

## Command-by-Command Analysis

---

### 1. brainstorm.md (198 lines)

**File:** `/Users/adamf/Dev/compound-workflows-marketplace/plugins/compound-workflows/commands/compound-workflows/brainstorm.md`

#### Agent Dispatches (Task calls)

| Agent Name Used | Inline Role Description | Output File |
|-----------------|------------------------|-------------|
| `repo-research-analyst` | "You are a repository research analyst specializing in codebase pattern discovery and architectural analysis." | `.workflows/brainstorm-research/<topic-stem>/repo-research.md` |
| `context-researcher` | "You are a context researcher specializing in synthesizing project knowledge across documentation, solutions, brainstorms, plans, and institutional memory." | `.workflows/brainstorm-research/<topic-stem>/context-research.md` |
| `general-purpose` (red team fallback) | "You are a red team reviewer. Your job is to find flaws, not validate." | `.workflows/brainstorm-research/<topic-stem>/red-team-critique.md` |

#### Skill References

- Line 13: `Load the brainstorming skill for detailed techniques.` (refers to a `brainstorming` skill -- NOT part of this plugin)

#### PAL MCP References

- Lines 116-134: `mcp__pal__chat` with `model: gemini-2.5-pro` for red team (primary path)
- Lines 136-158: Claude subagent fallback using `Task general-purpose` if PAL unavailable

#### References to compound-engineering

- **NONE.** This command has zero references to compound-engineering.

#### Company-Specific Examples or Names

- **NONE.** Examples are generic (e.g., "claude-code-cursor-dual-tool").

#### Text That Needs to Change for Fork

- **Nothing.** This command is already fully generic. No changes required for the fork plan.

---

### 2. plan.md (278 lines)

**File:** `/Users/adamf/Dev/compound-workflows-marketplace/plugins/compound-workflows/commands/compound-workflows/plan.md`

#### Agent Dispatches (Task calls)

| Agent Name Used | Inline Role Description | Output File |
|-----------------|------------------------|-------------|
| `repo-research-analyst` | "You are a repository research analyst specializing in codebase pattern discovery." | `.workflows/plan-research/<plan-stem>/agents/repo-research.md` |
| `learnings-researcher` | "You are an institutional knowledge researcher. Search docs/solutions/ for relevant past solutions." | `.workflows/plan-research/<plan-stem>/agents/learnings.md` |
| `best-practices-researcher` | "You are a best practices researcher specializing in external documentation and community standards." | `.workflows/plan-research/<plan-stem>/agents/best-practices.md` |
| `framework-docs-researcher` | "You are a framework documentation researcher specializing in official docs and version-specific constraints." | `.workflows/plan-research/<plan-stem>/agents/framework-docs.md` |
| `spec-flow-analyzer` | "You are a specification flow analyst specializing in completeness, edge cases, and user flow gaps." | `.workflows/plan-research/<plan-stem>/agents/specflow.md` |

#### Skill References

- **NONE.**

#### References to compound-engineering

- **NONE.**

#### Company-Specific Examples or Names

- Line 63: Plan stem examples: `intellect-v6-pricing` or `cash-manager-reporting` -- **THESE ARE COMPANY-SPECIFIC** (Intellect is likely a product name, cash-manager is likely a product name)

#### Text That Needs to Change for Fork

| Line(s) | Current Text | Reason |
|----------|-------------|--------|
| 63 | `intellect-v6-pricing` or `cash-manager-reporting` | Company-specific product names used as examples |

**Replacement needed:** Use generic examples like `user-auth-flow` or `api-rate-limiting`.

---

### 3. work.md (318 lines)

**File:** `/Users/adamf/Dev/compound-workflows-marketplace/plugins/compound-workflows/commands/compound-workflows/work.md`

#### Agent Dispatches (Task calls)

| Agent Name Used | Inline Role Description | Output File |
|-----------------|------------------------|-------------|
| `code-simplicity-reviewer` | "You are a code simplicity reviewer. Check for unnecessary complexity, YAGNI violations, and over-engineering." | `.workflows/work-review/agents/code-simplicity.md` |

#### Skill References

- **NONE.**

#### References to compound-engineering

- **NONE.**

#### Company-Specific Examples or Names

- **NONE.** Examples use generic patterns (`feat(scope): description`).

#### Text That Needs to Change for Fork

- **Nothing.** This command is already fully generic. No changes required.

---

### 4. compound.md (141 lines)

**File:** `/Users/adamf/Dev/compound-workflows-marketplace/plugins/compound-workflows/commands/compound-workflows/compound.md`

#### Agent Dispatches (Task calls)

| Agent Name Used | Inline Role Description | Output File |
|-----------------|------------------------|-------------|
| `general-purpose` (Context Analyzer) | "You are a context analyzer specializing in problem classification and root cause identification." | `.workflows/compound-research/<topic-stem>/agents/context.md` |

Note: Agents 2-5 (Solution Extractor, Related Docs Finder, Prevention Strategist, Category Classifier) are described but their Task dispatch syntax is abbreviated as "writes to" references without full inline prompts.

#### Skill References

- **NONE.**

#### Phase 3 References to Specialized Agents (by name only, not dispatched)

- `performance-oracle` (for performance_issue)
- `security-sentinel` (for security_issue)
- `data-integrity-guardian` (for database_issue)

These are referenced as **optional Phase 3 enhancement agents** -- they would come from compound-engineering if installed.

#### References to compound-engineering

- **NONE explicitly**, but the Phase 3 agent names (`performance-oracle`, `security-sentinel`, `data-integrity-guardian`) are compound-engineering agent names.

#### Company-Specific Examples or Names

- Line 40: Topic stem examples: `bq-cost-measurement` or `upstream-fork-management` -- `bq-cost-measurement` is **mildly company-specific** (BigQuery cost measurement could be generic but suggests specific internal usage)
- Line 126: Reuse trigger example: `"before any Xiatech meeting"` -- **COMPANY-SPECIFIC** (Xiatech is a specific company name)

#### Text That Needs to Change for Fork

| Line(s) | Current Text | Reason |
|----------|-------------|--------|
| 40 | `bq-cost-measurement` or `upstream-fork-management` | Mildly company-specific examples |
| 126 | `"before any Xiatech meeting"` | Company-specific name |

**Replacements needed:**
- Line 40: Use generic examples like `redis-cache-invalidation` or `api-versioning-strategy`
- Line 126: Use generic example like `"before any vendor evaluation meeting"`

---

### 5. deepen-plan.md (446 lines)

**File:** `/Users/adamf/Dev/compound-workflows-marketplace/plugins/compound-workflows/commands/compound-workflows/deepen-plan.md`

#### Agent Dispatches (Task calls)

| Agent Name Used | Inline Role Description | Output File |
|-----------------|------------------------|-------------|
| `general-purpose` (Synthesis Agent) | "You are synthesizing findings from multiple review and research agents into plan enhancements." | `.workflows/deepen-plan/<plan-stem>/run-<N>-synthesis.md` + enhanced plan |
| `general-purpose` (Red Team fallback) | "You are a red team reviewer for a software implementation plan. Your job is to find flaws, not validate." | `.workflows/deepen-plan/<plan-stem>/agents/run-<N>/red-team--critique.md` |
| `general-purpose` (Consensus fallback) | "You are evaluating a disputed recommendation from a software plan." | `.workflows/deepen-plan/<plan-stem>/agents/run-<N>/red-team--consensus-<topic>.md` |

Note: Research agents and review agents are described generically -- the actual agent names come from runtime discovery (Phase 2).

#### Skill References

- **NONE** directly, but Phase 2 (Step 2a) discovers skills dynamically from `.claude/skills/`, `~/.claude/skills/`, and plugin caches.

#### PAL MCP References

- Lines 297-319: `mcp__pal__chat` with `model: gemini-2.5-pro` for red team (primary path)
- Lines 358-365: `mcp__pal__consensus` with `gemini-2.5-pro` and `gpt-5.2` for disputed points (primary path)
- Lines 321-347, 370-388: Claude subagent fallbacks for both

#### References to compound-engineering

- **Line 105-107 (CRITICAL):**
  ```
  For compound-engineering plugin:
  - USE: `agents/review/*`, `agents/research/*`, `agents/design/*`, `agents/docs/*`
  - SKIP: `agents/workflow/*`
  ```
  This explicitly references compound-engineering by name and describes which agent directories to use/skip.

#### Company-Specific Examples or Names

- Line 27: Plan stem example: `feat-cash-management-reporting-app` -- **COMPANY-SPECIFIC** (cash-management is likely a product)

#### Text That Needs to Change for Fork

| Line(s) | Current Text | Reason |
|----------|-------------|--------|
| 27 | `feat-cash-management-reporting-app` | Company-specific product name |
| 105-107 | "For compound-engineering plugin: USE agents/review/*, agents/research/*, agents/design/*, agents/docs/* SKIP agents/workflow/*" | Direct reference to compound-engineering plugin by name |

**Replacements needed:**
- Line 27: Use generic example like `feat-user-dashboard-redesign`
- Lines 105-107: This is the **key fork point**. Once compound-workflows bundles its own agents, this reference changes to refer to the plugin's own bundled agents instead of compound-engineering.

---

### 6. work-agents.md (390 lines)

**File:** `/Users/adamf/Dev/compound-workflows-marketplace/plugins/compound-workflows/commands/compound-workflows/work-agents.md`

#### Agent Dispatches (Task calls)

| Agent Name Used | Inline Role Description | Output File |
|-----------------|------------------------|-------------|
| `general-purpose` (Subagent template) | "You are executing one step of a larger work plan. Your job is to implement ONLY the tasks described below, commit your work, and return a summary." | N/A (commits code, returns summary) |
| `code-simplicity-reviewer` | "You are a code simplicity reviewer. Check for unnecessary complexity, YAGNI violations, and over-engineering." | `.workflows/work-agents-review/code-simplicity.md` |

#### Skill References

- **NONE.**

#### References to compound-engineering

- **NONE.**

#### Company-Specific Examples or Names

- **NONE.** Examples use generic patterns (`FooService`, `bar_service.rb`).

#### Text That Needs to Change for Fork

- **Nothing.** This command is already fully generic. No changes required.

---

### 7. review.md (162 lines)

**File:** `/Users/adamf/Dev/compound-workflows-marketplace/plugins/compound-workflows/commands/compound-workflows/review.md`

#### Agent Dispatches (Task calls)

| Agent Name Used | Inline Role Description | Output File |
|-----------------|------------------------|-------------|
| `kieran-typescript-reviewer` | "You are a TypeScript code reviewer focused on type safety, modern patterns, and maintainability." | `.workflows/code-review/<topic-stem>/agents/kieran-typescript.md` |
| `pattern-recognition-specialist` | "You are a pattern recognition specialist. Analyze for design patterns, anti-patterns, naming conventions, and duplication." | `.workflows/code-review/<topic-stem>/agents/pattern-recognition.md` |
| `architecture-strategist` | "You are an architecture strategist. Review architectural impact, pattern compliance, and design integrity." | `.workflows/code-review/<topic-stem>/agents/architecture.md` |
| `security-sentinel` | "You are a security auditor. Check for vulnerabilities, input validation, auth/authz issues, and OWASP compliance." | `.workflows/code-review/<topic-stem>/agents/security.md` |
| `performance-oracle` | "You are a performance analyst. Check for bottlenecks, algorithmic complexity, database queries, memory usage." | `.workflows/code-review/<topic-stem>/agents/performance.md` |
| `code-simplicity-reviewer` | "You are a code simplicity reviewer. Check for unnecessary complexity, YAGNI violations, and over-engineering." | `.workflows/code-review/<topic-stem>/agents/simplicity.md` |
| `agent-native-reviewer` | "You are an agent-native reviewer. Verify any action a user can take, an agent can also take." | `.workflows/code-review/<topic-stem>/agents/agent-native.md` |

**Conditional agents:**

| Agent Name Used | Condition | Inline Role Description |
|-----------------|-----------|------------------------|
| `data-migration-expert` | DB migrations in PR | "You are a data migration expert. Validate migrations, backfills, and production data transformations." |
| `deployment-verification-agent` | DB migrations in PR | "You are a deployment verification specialist. Produce Go/No-Go checklists with SQL verification queries and rollback procedures." |
| `kieran-rails-reviewer` | Rails code in PR | "You are a Rails code reviewer focused on Rails conventions, ActiveRecord patterns, and idiomatic Ruby." |
| `dhh-rails-reviewer` | Rails code in PR | "You are a Rails reviewer channeling DHH's philosophy: convention over configuration, minimal abstraction, Basecamp-style simplicity." |
| `julik-frontend-races-reviewer` | Frontend code in PR | "You are a frontend concurrency reviewer. Check for race conditions, stale closures, unhandled promises, and UI state synchronization issues." |

#### Skill References

- Line 24: `skill: git-worktree` (refers to a skill NOT part of this plugin)
- Line 106: "Use the file-todos skill" (refers to a `file-todos` skill NOT part of this plugin)

#### References to compound-engineering

- **NONE explicitly**, but agent names like `kieran-typescript-reviewer`, `kieran-rails-reviewer`, `dhh-rails-reviewer`, `julik-frontend-races-reviewer` are **compound-engineering persona names** (Kieran = Kieran Klaassen, DHH = David Heinemeier Hansson, Julik = Julik Tarkhanov). These are personality-based names from compound-engineering's agent roster.

#### Company-Specific Examples or Names

- Line 30: Topic stem example: `feat-cash-management-ui` -- **COMPANY-SPECIFIC** (cash-management product)

#### Text That Needs to Change for Fork

| Line(s) | Current Text | Reason |
|----------|-------------|--------|
| 30 | `feat-cash-management-ui` | Company-specific product name |
| 55 | `kieran-typescript-reviewer` | compound-engineering persona name |
| 57 | `architecture-strategist` | compound-engineering agent name |
| 58 | `security-sentinel` | compound-engineering agent name |
| 59 | `performance-oracle` | compound-engineering agent name |
| 61 | `agent-native-reviewer` | compound-engineering agent name |
| 66-67 | `data-migration-expert`, `deployment-verification-agent` | compound-engineering agent names |
| 67 | `kieran-rails-reviewer`, `dhh-rails-reviewer` | compound-engineering persona names |
| 68 | `julik-frontend-races-reviewer` | compound-engineering persona name |
| 24 | `skill: git-worktree` | External skill reference |
| 106 | "Use the file-todos skill" | External skill reference |

**Key decision:** These agent names are used purely as Task dispatch names with inline role descriptions. They are NOT file references -- they're just semantic names for Claude Code's `Task` tool. The **inline role descriptions** are the actual prompts. The agent names could be changed to anything.

**However:** If compound-engineering is installed, Claude Code may route `Task kieran-typescript-reviewer` to compound-engineering's actual agent file (which has a richer prompt). The current names create **intentional coupling** to compound-engineering's agent roster for users who have it installed.

---

### 8. setup.md (192 lines)

**File:** `/Users/adamf/Dev/compound-workflows-marketplace/plugins/compound-workflows/commands/compound-workflows/setup.md`

#### Agent Dispatches (Task calls)

- **NONE.** Setup has no Task dispatches.

#### Skill References

- **NONE.**

#### References to compound-engineering

- **Line 23:** `ls ~/.claude/plugins/cache/*/compound-engineering/*/agents/review/security-sentinel.md 2>/dev/null && echo "CE=installed" || echo "CE=missing"` -- Direct filesystem detection of compound-engineering plugin
- **Line 49:** `| **compound-engineering** | [Installed/Not found] | Specialized review/research agents (security-sentinel, performance-oracle, etc.) with rich domain prompts. Without it: general-purpose fallback (still works, less specialized) |`
- **Lines 86-89:** Installation instructions for compound-engineering: `claude /install compound-engineering`
- **Lines 148-149:** Config output: `review_agents: [compound-engineering|general-purpose]` and `- **Review agents:** [compound-engineering (specialized) | general-purpose (fallback)]`

#### Company-Specific Examples or Names

- **NONE.**

#### Text That Needs to Change for Fork

| Line(s) | Current Text | Reason |
|----------|-------------|--------|
| 23 | `ls ~/.claude/plugins/cache/*/compound-engineering/*/agents/review/security-sentinel.md` | Direct compound-engineering detection |
| 49 | `compound-engineering` in status table | Plugin name reference |
| 86-89 | `claude /install compound-engineering` | Installation instructions |
| 148-149 | `compound-engineering` in config output | Plugin name reference |

**This is the command being entirely replaced** per the fork plan. The new setup.md will detect compound-workflows' own bundled agents instead of checking for compound-engineering.

---

## Cross-Cutting Analysis

### All Agent Names Referenced Across Commands

**Agents dispatched via `Task` tool (with inline role descriptions):**

| Agent Name | Used In | Origin |
|------------|---------|--------|
| `repo-research-analyst` | brainstorm, plan | Generic (invented by compound-workflows) |
| `context-researcher` | brainstorm | Matches bundled agent file |
| `learnings-researcher` | plan | Generic |
| `best-practices-researcher` | plan | Generic |
| `framework-docs-researcher` | plan | Generic |
| `spec-flow-analyzer` | plan | Generic |
| `general-purpose` | brainstorm, compound, deepen-plan, work-agents | Claude Code default |
| `code-simplicity-reviewer` | work, work-agents, review | compound-engineering name |
| `kieran-typescript-reviewer` | review | compound-engineering persona |
| `pattern-recognition-specialist` | review | compound-engineering name |
| `architecture-strategist` | review | compound-engineering name |
| `security-sentinel` | review | compound-engineering name |
| `performance-oracle` | review | compound-engineering name |
| `agent-native-reviewer` | review | compound-engineering name |
| `data-migration-expert` | review (conditional) | compound-engineering name |
| `deployment-verification-agent` | review (conditional) | compound-engineering name |
| `kieran-rails-reviewer` | review (conditional) | compound-engineering name |
| `dhh-rails-reviewer` | review (conditional) | compound-engineering name |
| `julik-frontend-races-reviewer` | review (conditional) | compound-engineering name |

**Agents referenced by name only (not dispatched):**

| Agent Name | Used In | Context |
|------------|---------|---------|
| `performance-oracle` | compound (Phase 3) | Optional enhancement |
| `security-sentinel` | compound (Phase 3) | Optional enhancement |
| `data-integrity-guardian` | compound (Phase 3) | Optional enhancement |

### All Skill References Across Commands

| Skill Name | Used In | Part of This Plugin? |
|------------|---------|---------------------|
| `brainstorming` | brainstorm (line 13) | NO |
| `document-review` | brainstorm (line 181) | NO |
| `git-worktree` | review (line 24) | NO |
| `file-todos` | review (line 106) | NO |
| `agent-browser` + `imgup` | work (line 253) | NO |
| `disk-persist-agents` | (bundled skill) | YES |

### All References to compound-engineering

| File | Line(s) | Type of Reference |
|------|---------|-------------------|
| deepen-plan.md | 105-107 | Explicit plugin name + directory structure |
| setup.md | 23 | Filesystem detection path |
| setup.md | 49 | Status table entry |
| setup.md | 86-89 | Installation instructions |
| setup.md | 148-149 | Config output values |
| plugin.json | 14 | Keyword: `"compound-engineering"` |
| README.md | 3, 7-17, 63, 97-101 | Description, comparison table, dependency, acknowledgments |
| CHANGELOG.md | 25 | Acknowledgment |
| CLAUDE.md | 44 | Testing instructions mention compound-engineering |

### All Company-Specific Examples

| File | Line | Text | Issue |
|------|------|------|-------|
| plan.md | 63 | `intellect-v6-pricing` | Product name |
| plan.md | 63 | `cash-manager-reporting` | Product name |
| compound.md | 40 | `bq-cost-measurement` | Mildly specific |
| compound.md | 126 | `"before any Xiatech meeting"` | Company name |
| deepen-plan.md | 27 | `feat-cash-management-reporting-app` | Product name |
| review.md | 30 | `feat-cash-management-ui` | Product name |

---

## Current Bundled Agent: context-researcher.md

**File:** `/Users/adamf/Dev/compound-workflows-marketplace/plugins/compound-workflows/agents/research/context-researcher.md`

**Format reference for porting agents:**

```yaml
---
name: context-researcher
description: "..."
model: haiku
---
```

- Uses `<examples>` block with `<example>`, `<commentary>` tags
- Has detailed search strategy (5 steps)
- Has output format template
- Has efficiency guidelines (DO/DON'T)
- Has integration points section
- **173 lines total**
- Contains NO company-specific references (examples use generic terms like "analytics module", "ClickHouse", "CTO")

---

## Line Counts per Command File

| Command File | Lines |
|-------------|-------|
| brainstorm.md | 198 |
| plan.md | 278 |
| work.md | 318 |
| compound.md | 141 |
| deepen-plan.md | 446 |
| work-agents.md | 390 |
| review.md | 162 |
| setup.md | 192 |
| **Total** | **2,125** |

---

## Summary of Changes Required for Fork

### Commands Requiring NO Changes (already generic)
- **brainstorm.md** -- Zero company-specific or compound-engineering references
- **work.md** -- Zero company-specific or compound-engineering references
- **work-agents.md** -- Zero company-specific or compound-engineering references

### Commands Requiring Minor Changes (example text only)
- **plan.md** -- Replace 2 company-specific example stems (line 63)
- **compound.md** -- Replace 2 company-specific examples (lines 40, 126)
- **review.md** -- Replace 1 company-specific example stem (line 30)

### Commands Requiring Significant Changes
- **deepen-plan.md** -- Replace 1 example stem (line 27) + rewrite compound-engineering agent discovery (lines 105-107) to reference bundled agents
- **setup.md** -- Being entirely replaced. Current version detects compound-engineering as external dependency; new version detects bundled agents

### Non-Command Files Requiring Updates
- **plugin.json** -- Remove `compound-engineering` keyword, bump version
- **README.md** -- Update component counts, dependency table, remove compound-engineering as recommended dependency
- **CHANGELOG.md** -- Add new version entry
- **CLAUDE.md** -- Update testing instructions

### Key Architectural Decision

The review.md command uses **12 different agent names** from compound-engineering's roster (kieran-typescript-reviewer, security-sentinel, etc.). These names serve dual purposes:
1. **Semantic labels** for the `Task` tool (any name works)
2. **Coupling hooks** to compound-engineering's agent files (if installed, richer prompts activate)

The fork must decide: **rename the agents to generic names** (breaking compound-engineering coupling) or **keep the names** (preserving optional enrichment when compound-engineering is also installed). The inline role descriptions make these agents functional regardless.
