---
title: "Fork compound-engineering Agents & Skills into compound-workflows"
type: feat
status: active
date: 2026-02-25
origin: docs/brainstorms/2026-02-25-port-gaps-compound-engineering-brainstorm.md
---

# Plan: Fork compound-engineering Agents & Skills

## Context

The compound-workflows plugin (v1.0.0) ships 7 commands, 1 agent, and 1 skill. It references 18 named agents and 5 skills from compound-engineering, but doesn't bundle them — falling back to 1-sentence inline role descriptions. This plan forks 21 agents and 14 skills from compound-engineering, making the plugin fully self-contained at v1.1.0.

**Origin brainstorm:** `docs/brainstorms/2026-02-25-port-gaps-compound-engineering-brainstorm.md` — Key decisions carried forward: fork (not depend), depersonalize 3 agents, genericize examples, add NOTICE attribution, setup warns on conflict, 1.1.0 versioning.

## Scope Summary

| Category | Count | Files | Effort |
|----------|-------|-------|--------|
| Agents (new) | 21 | 21 .md files | 14 zero-change, 3 LOW, 4 MEDIUM, 0 HIGH |
| Skills (new) | 14 | 70 files (SKILL.md + assets/refs/scripts) | 6 zero-change, 4 LOW, 2 MEDIUM, 2 HIGH |
| Commands (update) | 7 of 7 | 7 .md files | 3 minor text, 1 discovery rewrite, 1 full replace, 2 red team methodology |
| Docs/config (update) | 5 | plugin.json, README, CLAUDE, CHANGELOG, new NOTICE | All updated |
| **Total** | — | **~96 files touched** | — |

### Deepen-Plan Findings (Run 1)

**Recommendations:**
- After the work-agents merge (Phase 0), the command count becomes 6 not 7. "5 of 7" becomes "5 of 6" — update accordingly. [research--command-analysis]
- Source inventory line counts are consistently 1 higher than `wc -l` due to trailing newline counting. Phase 7e should use `wc -l` consistently throughout. [research--source-verification]
- All 91 source files verified present at `~/.claude/plugins/cache/every-marketplace/compound-engineering/2.35.2/`. No missing files. [research--source-verification]
- All files identical between versions 2.31.1 and 2.35.2 except `skills/setup/SKILL.md` (new in 2.35.2). Safe to use 2.35.2 as source. [research--version-diff]

## Commit Strategy

Each phase produces one focused, reviewable commit:

1. **Commit 0** (Phase 0): Merge work-agents.md into work.md — housekeeping before fork
2. **Commit 1** (Phase 1): Copy all 91 files unmodified + create NOTICE — pure copy, verifiable against source
3. **Commit 2** (Phase 2-3): Rename 3 agents + genericize examples — all content modifications
4. **Commit 3** (Phase 4): HIGH-effort modifications — setup skill + orchestrating-swarms
5. **Commit 4** (Phase 5): Update commands — references, discovery logic, setup replacement
6. **Commit 5** (Phase 6): Docs and config — plugin.json, README, CHANGELOG, CLAUDE.md

### Deepen-Plan Findings (Run 1)

**Contradictions noted:**
- architecture-strategist recommends splitting Commit 2 into LOW and MEDIUM changes for safer revert. code-simplicity-reviewer recommends merging Commit 3 into Commit 2 for fewer commits. These are opposite directions; current 5-commit structure (plus new Commit 0) is a reasonable middle ground.

**Recommendations:**
- Do NOT publish intermediate states (Commits 1-3) as releases. Until Commit 4 (Phase 5) lands, the setup command still recommends installing compound-engineering as a dependency, creating a conflict. [review--architecture-strategist]

## Canonical Genericization Table

Use these exact replacements for consistency across all files:

| Original | Replacement | Where Found |
|----------|-------------|-------------|
| BriefSystem | AuthService | learnings-researcher, compound-docs |
| EmailProcessing | PaymentProcessor | learnings-researcher, compound-docs |
| email_processing | payment_processing | learnings-researcher, compound-docs schema |
| brief_system | auth_service | learnings-researcher, compound-docs schema |
| cash-management / cash-manager | user-dashboard | plan, compound, deepen-plan, review |
| intellect-v6-pricing | api-rate-limiting | plan |
| Xiatech | Acme Corp | compound |
| EveryInc/cora | owner/repo | resolve-pr-parallel script |
| Every Reader | BookReader | agent-native-architecture references (6 files) |
| bq-cost-measurement | redis-cache-invalidation | compound |
| Kieran (persona) | Remove entirely | typescript-reviewer, python-reviewer |
| Julik (persona) | Remove entirely | frontend-races-reviewer |

### Deepen-Plan Findings (Run 1)

**Verification:**
- All 12 replacement patterns confirmed present in source files. No undiscovered company-specific terms found. Table is 95% complete. [research--genericization-audit]
- "Every Reader" confirmed in 5 (not 6) agent-native-architecture reference files: action-parity-discipline.md, system-prompt-design.md, shared-workspace-architecture.md, dynamic-context-injection.md, architecture-patterns.md. [research--genericization-audit]

**Contradiction noted:**
- code-simplicity-reviewer argues the table should be cut to ~6 patterns (personas + real company/repo names only), since example names like "BriefSystem" and "cash-management" are arbitrary and provide zero functional improvement when replaced. The brainstorm red team previously ratified full genericization. Decision: **keep the full table** as ratified, since the cost is low and completeness aids verification.

**Additional finding:**
- `agents/research/git-history-analyzer.md` line 22 contains "The current year is 2026" — matches the Phase 7f check pattern. Flag for review during Phase 2a when this file is already being edited. [research--genericization-audit]

---

## Phase 0: Pre-Fork Housekeeping

Merge `work-agents.md` into `work.md` before starting the fork, since this affects file counts, references, and the context exhaustion strategy.

### 0a. Replace work.md with work-agents.md (subagent architecture wins)

This is NOT a content merge — work-agents.md is the evolved version of work.md. The subagent dispatch architecture supersedes the direct-execution model entirely. work-agents.md already includes all shared infrastructure (beads, worktree, recovery, quality check, ship phase).

- [ ] Delete `commands/compound-workflows/work.md` (direct-execution model, superseded)
- [ ] Rename `commands/compound-workflows/work-agents.md` to `commands/compound-workflows/work.md`
- [ ] Update YAML frontmatter: `name: compound-workflows:work-agents` → `name: compound-workflows:work`, `description:` update to remove "subagent" qualifier (it's now the only mode)
- [ ] Remove lines 12-19: "How This Differs from `/compound-workflows:work`" comparison table (no longer relevant)
- [ ] Remove line 9: "The main context acts as an **orchestrator only**" phrasing that positions this as an alternative (it's now the default)
- [ ] Update line 288: `.workflows/work-agents-review/` → `.workflows/work-review/`
- [ ] Expected result: ~370-380 lines (390 minus ~15 lines of comparison/positioning content)

### 0b. Update references

- [ ] Update `CLAUDE.md` if it mentions both `work` and `work-agents` as separate commands
- [ ] Update `README.md` command table (7 commands becomes 6)
- [ ] Update `plugin.json` commands array if work-agents is listed separately
- [ ] Update `CHANGELOG.md` if needed to note the merge

### 0c. Update plan references

- [ ] Context exhaustion strategy (below) now reads `/compound-workflows:work` not `/aworkflows:work-agents`
- [ ] Phase 7f line count verification: work ~380 lines (was work 318 + work-agents 390, now single work ~380)
- [ ] Scope summary "5 of 7" becomes "5 of 6" (6 total commands after merge)

### 0d. Phase 0 verification

- [ ] `ls commands/compound-workflows/` shows 7 .md files (brainstorm, plan, work, compound, deepen-plan, review, setup). Pre-merge was 8 (work + work-agents); post-merge is 7.
- [ ] `grep -r "work-agents" plugins/compound-workflows/` returns zero results
- [ ] The merged work.md functions correctly: `/compound-workflows:work` dispatches as expected

**Phase 0 total: 2-4 files updated, 1 file deleted. -> Commit 0.**

---

## Phase 1: Copy Zero-Change Files

Copy files that need no modification from compound-engineering into compound-workflows.

### Prerequisite: Verify source exists

- [ ] `ls ~/.claude/plugins/cache/every-marketplace/compound-engineering/2.35.2/` — if this path does not exist, STOP. The user must install compound-engineering first (`claude /install compound-engineering`) or locate the source at an alternative path. Do not proceed with missing source files.

### 1a. Verify agent resolution mechanism (PREREQUISITE)

Before copying any files, determine how Claude Code resolves `Task <agent-name>` to an agent .md file. This determines how agent names must be formatted throughout all commands.

- [ ] Test empirically: install a test agent with a known `name:` field and filename, then dispatch `Task <name>` from a command. Verify which field Claude matches against (YAML `name:`, filename, directory-qualified path, or plugin-qualified path like `compound-workflows:review:agent-name`).
- [ ] Document the resolution format in CLAUDE.md for the plugin
- [ ] If resolution requires plugin-qualified names (`compound-workflows:category:agent-name`): every Task dispatch in every command needs updating — escalate scope of Phase 5
- [ ] If resolution uses YAML `name:` field: Phase 7c must validate ALL 22 agents' `name:` fields (not just the 3 renamed ones)
- [ ] If resolution uses filenames: no additional work needed beyond ensuring filenames match expectations

**This is blocking.** The entire fork depends on agents resolving correctly. Do not proceed past Phase 1 without confirming the mechanism.

### 1b. Create directory structure

- [ ] Create `plugins/compound-workflows/agents/review/`
- [ ] Create `plugins/compound-workflows/agents/workflow/`
- [ ] Create skill directories for all 14 new skills (with subdirs where needed)

### 1b. Copy 14 zero-change agents

Direct copy using `cp -p` to preserve file permissions. No modifications:

- [ ] `agents/research/repo-research-analyst.md` (136 lines)
- [ ] `agents/research/framework-docs-researcher.md` (107 lines)
- [ ] `agents/review/pattern-recognition-specialist.md` (73 lines)
- [ ] `agents/review/architecture-strategist.md` (68 lines)
- [ ] `agents/review/security-sentinel.md` (115 lines)
- [ ] `agents/review/performance-oracle.md` (138 lines)
- [ ] `agents/review/agent-native-reviewer.md` (262 lines)
- [ ] `agents/review/data-migration-expert.md` (113 lines)
- [ ] `agents/review/deployment-verification-agent.md` (175 lines)
- [ ] `agents/review/data-integrity-guardian.md` (86 lines)
- [ ] `agents/review/schema-drift-detector.md` (155 lines)
- [ ] `agents/workflow/spec-flow-analyzer.md` (135 lines)
- [ ] `agents/workflow/bug-reproduction-validator.md` (83 lines)
- [ ] `agents/workflow/pr-comment-resolver.md` (85 lines)

### 1c. Copy 6 zero-change skills (with all subdirectories)

Use `cp -rp` for directories to preserve permissions on scripts:

- [ ] `skills/git-worktree/` — SKILL.md + scripts/worktree-manager.sh (2 files)
- [ ] `skills/gemini-imagegen/` — SKILL.md + requirements.txt + 5 scripts (7 files)
- [ ] `skills/agent-browser/` — SKILL.md (1 file)
- [ ] `skills/create-agent-skills/` — SKILL.md + 13 references + 2 templates + 10 workflows (26 files)
- [ ] `skills/skill-creator/` — SKILL.md + 3 scripts (4 files)
- [ ] `skills/frontend-design/` — SKILL.md (1 file)

### 1d. Security review of executable scripts (BEFORE copying)

Review all executable scripts being forked. These run with the user's full shell permissions. Do not copy blindly.

- [ ] Review and document each script's purpose, system resource access, and external service calls:
  - `git-worktree/scripts/worktree-manager.sh` (shell — git operations)
  - `gemini-imagegen/scripts/compose_images.py` (Python — Gemini API)
  - `gemini-imagegen/scripts/edit_image.py` (Python — Gemini API)
  - `gemini-imagegen/scripts/generate_image.py` (Python — Gemini API)
  - `gemini-imagegen/scripts/gemini_images.py` (Python — Gemini API)
  - `gemini-imagegen/scripts/multi_turn_chat.py` (Python — Gemini API)
  - `gemini-imagegen/requirements.txt` (supply chain — check pinned versions)
  - `skill-creator/scripts/init_skill.py` (Python — filesystem)
  - `skill-creator/scripts/package_skill.py` (Python — filesystem)
  - `skill-creator/scripts/quick_validate.py` (Python — filesystem)
  - `resolve-pr-parallel/scripts/get-pr-comments` (shell — GitHub API)
  - `resolve-pr-parallel/scripts/resolve-pr-thread` (shell — GitHub API)
- [ ] Verify no hardcoded credentials, API keys, or tokens in any script
- [ ] Verify no unexpected network calls, file deletions, or privilege escalation
- [ ] Check runtime dependencies: verify shebangs point to standard interpreters (`/usr/bin/env python3`, `/usr/bin/env bash`), `requirements.txt` has pinned versions (not open ranges), and note any external tool deps (gh, jq, curl) that users must have installed
- [ ] If any script is flagged: document the concern and decide whether to port, modify, or exclude it

### 1e. Create NOTICE file

- [ ] Create `plugins/compound-workflows/NOTICE` with the full MIT license text from compound-engineering (not just a summary attribution). Content:

  ```
  This plugin includes agents and skills originally from compound-engineering.
  Forked from compound-engineering v2.35.2.

  compound-engineering
  Copyright (c) 2025 Kieran Klaassen

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.

  https://github.com/kieranklaassen/compound-engineering
  ```

### 1f. Phase 1 verification

- [ ] Count agent files: `find plugins/compound-workflows/agents -name "*.md" -type f | wc -l` -> expect 15 (14 new + 1 existing)
- [ ] Count all skill files: `find plugins/compound-workflows/skills -type f | wc -l` -> expect 42 (41 new + 1 existing)
- [ ] Diff zero-change files against source to confirm byte-identical copies
- [ ] Verify NOTICE file exists and contains full MIT license text

**Phase 1 total: 56 files (55 copied + 1 NOTICE created), 0 modifications. -> Commit 1.**

### Deepen-Plan Findings (Run 1)

**Critical:**
- The NOTICE file MUST include the full MIT license text, not just a summary attribution. MIT requires "this permission notice shall be included in all copies or substantial portions of the Software." 91 copied files constitute "substantial portions." [review--security-sentinel]

**Recommendations:**
- Script security review is now a concrete task (Phase 1d). [review--security-sentinel → promoted to task]
- Preserve any copyright, license, or attribution comments at the top of files during all subsequent modification phases. Do not modify or remove these during genericization. [review--security-sentinel]
- Fork base version (v2.35.2) is recorded in the NOTICE file (Phase 1e). [review--security-sentinel]

---

## Phase 2: Copy and Modify LOW-Effort Files

Files needing single-line or small text changes.

### 2a. LOW-effort agents (3)

- [ ] `agents/research/best-practices-researcher.md` — Remove references to dropped skills (dhh-rails-style, andrew-kane-gem-writer, dspy-ruby, every-style-editor) from skill discovery mapping
- [ ] `agents/research/git-history-analyzer.md` — Replace "compound-engineering" with "compound-workflows" (1 line)
- [ ] `agents/review/code-simplicity-reviewer.md` — Replace "compound-engineering" with "compound-workflows" (1 line)

### 2b. LOW-effort skills (4)

- [ ] `skills/brainstorming/SKILL.md` — Update `/workflows:plan` references to `/compound-workflows:plan`
- [ ] `skills/document-review/SKILL.md` — Update `/workflows:brainstorm`, `/workflows:plan` references
- [ ] `skills/file-todos/` — Update command references in SKILL.md; copy assets/todo-template.md (2 files)
- [ ] `skills/resolve-pr-parallel/` — Change `EveryInc/cora` to `owner/repo` in scripts/get-pr-comments; copy SKILL.md + 2 scripts (3 files)

**Phase 2 total: 12 files, 7 need small edits.**

### Deepen-Plan Findings (Run 1)

**Recommendations:**
- When editing git-history-analyzer.md in Phase 2a, also review line 22 ("The current year is 2026") — this is a hardcoded year that matches the Phase 7f check pattern. Consider removing or making it dynamic. [research--genericization-audit]
- For resolve-pr-parallel: verify get-pr-comments script does not contain other EveryInc/org-specific references beyond the one identified. The Phase 7b grep for "EveryInc" covers this if it runs against ALL file types (not just .md). [review--security-sentinel]

---

## Phase 3: Copy and Modify MEDIUM-Effort Files

Files needing persona removal, example genericization, or path updates.

### 3a. Rename and depersonalize 3 agents

For each: copy file with new name, update YAML `name:` field, remove persona name from prompt and examples.

- [ ] `kieran-typescript-reviewer.md` -> `agents/review/typescript-reviewer.md`
  - Replace "You are Kieran, a super senior TypeScript developer" -> "You are a super senior TypeScript developer"
  - Replace "Kieran" throughout examples and commentary
  - Update `name:` in frontmatter to `typescript-reviewer`

- [ ] `kieran-python-reviewer.md` -> `agents/review/python-reviewer.md`
  - Same pattern as typescript: remove "Kieran" persona, update name field

- [ ] `julik-frontend-races-reviewer.md` -> `agents/review/frontend-races-reviewer.md`
  - Replace "You are Julik, a seasoned full-stack developer" -> "You are a seasoned full-stack developer"
  - Remove "Julik" throughout; remove cultural attribution from communication style ("Eastern-European and Dutch (directness)" -> "Direct and precise")
  - Update `name:` in frontmatter to `frontend-races-reviewer`

### 3b. Genericize example content in 2 agents

- [ ] `agents/research/learnings-researcher.md` (265 lines)
  - Replace "BriefSystem" -> "AuthService", "EmailProcessing" -> "PaymentProcessor" in examples
  - Replace `email_processing`, `brief_system` enum values with generic equivalents
  - Update relative path `../../skills/compound-docs/references/yaml-schema.md` to point to compound-workflows' own path
  - Update `/workflows:plan`, `/deepen-plan` references to compound-workflows namespace

### 3c. Genericize example content in 2 skills

- [ ] `skills/compound-docs/` (5 files)
  - SKILL.md: Replace BriefSystem/EmailProcessing examples throughout (~lines 141, 142, 158-170, 455-488)
  - schema.yaml: Update component enum examples
  - references/yaml-schema.md: Replace EmailProcessing module example
  - Copy assets/ (critical-pattern-template.md, resolution-template.md) — no changes needed

- [ ] `skills/agent-native-architecture/` (15 files)
  - SKILL.md: no changes needed (fully generic)
  - 6 reference files: Replace "Every Reader" case study with generic "BookReader app" or similar
  - 8 reference files: no changes needed

**Phase 3 total: 25 files, 7 need substantive edits.**

---

## Phase 4: HIGH-Effort Modifications

### 4a. Setup skill — full namespace update

- [ ] Copy `skills/setup/SKILL.md` and apply:
  - Rename `compound-engineering.local.md` -> `compound-workflows.local.md` throughout
  - Update title: "Compound Engineering Setup" -> "Compound Workflows Setup"
  - Replace agent names: `kieran-rails-reviewer` -> REMOVE, `dhh-rails-reviewer` -> REMOVE, `kieran-python-reviewer` -> `python-reviewer`, `kieran-typescript-reviewer` -> `typescript-reviewer`
  - Update default agent lists to exclude dropped Rails agents
  - Update `/workflows:review` -> `/compound-workflows:review` etc.
  - Add compound-engineering conflict detection section (new content — see brainstorm)
  - Add beads/PAL detection sections (carry over from existing setup.md command)

### 4b. Orchestrating-swarms skill — per-instance review (NOT bulk replace)

- [ ] Copy `skills/orchestrating-swarms/SKILL.md` (~1580 lines) and apply:
  - **WARNING:** This file requires per-instance manual review, not blind bulk replace. Each `compound-engineering:` reference falls into one of three categories:
    - **Namespace update** (most): `compound-engineering:review:security-sentinel` -> `compound-workflows:review:security-sentinel`
    - **Agent rename**: `compound-engineering:review:kieran-typescript-reviewer` -> `compound-workflows:review:typescript-reviewer`
    - **Removal needed**: References to dropped agents (`kieran-rails-reviewer`, `figma-design-sync`, `dhh-rails-reviewer`, design category agents) must be removed, not renamed
  - Also update `compound-engineering:design:*` references — remove entirely (design agents not ported)
  - Update prose text: "compound-engineering plugin" -> "compound-workflows plugin"
  - Estimate: 30-60 minutes for careful review of this single file

**Phase 4 total: 2 files, both need substantial edits. -> Commit 3.**

### Deepen-Plan Findings (Run 1)

**Critical — Setup skill schema merge (Phase 4a + 5c):**

The existing setup.md command and the setup SKILL.md write DIFFERENT schemas to the same config file (`compound-workflows.local.md`). The command writes `{tracker, red_team, review_agents, gh_cli}`. The skill writes `{review_agents, plan_review_agents, project_context, depth}`. Phase 5c says the command should "load the setup skill for configuration knowledge" but does not specify how to merge these schemas. [research--setup-skill-audit]

**Unified schema specification** (use this when writing the setup command in Phase 5c):

```yaml
# compound-workflows.local.md

## Environment
tracker: beads/todowrite
red_team: gemini-2.5-pro / none
gh_cli: available/not available

## Stack & Agents
stack: python/typescript/general
review_agents: [merged agent list from skill's stack detection]
plan_review_agents: [from skill's research agent lists]
depth: standard/comprehensive/minimal

## Project Context
[from skill's project context detection]
```

**Additional Phase 4a gaps:**
- Since Rails agents are dropped entirely, the setup skill's Rails-specific stack path should be simplified to the "general" path. Do not just delete agent names from the Rails path — remove or merge the entire Rails code path. [research--setup-skill-audit]

**Orchestrating-swarms transformation manifest** (use during Phase 4b execution):

26 total references confirmed: 20 namespace updates, 3 agent renames, 3 removals. [research--orchestrating-swarms-audit]

Recommended execution order:
1. Bulk namespace replace: `compound-engineering:` -> `compound-workflows:` (catches 20 of 26)
2. Handle 3 renames manually: lines 363 (julik-frontend-races-reviewer -> frontend-races-reviewer), 364 (kieran-python-reviewer -> python-reviewer), 366 (kieran-typescript-reviewer -> typescript-reviewer)
3. Remove 3 blocks: lines 333-338 (kieran-rails-reviewer example), line 362 (dhh-rails-reviewer line), lines 403-409 (Design Agents section with figma-design-sync)
4. Final grep to verify zero remaining `compound-engineering` references

---

## Phase 5: Update Existing Commands

**All 7 commands are touched in Phase 5** (was "5 of 7" before deepen-plan run 1):
- 5a: plan.md, compound.md, review.md (minor text swaps)
- 5b: deepen-plan.md (discovery logic rewrite)
- 5c: setup.md (full rewrite)
- 5d: deepen-plan.md, brainstorm.md (red team methodology update)
- 5e: brainstorm.md (verification of agent dispatch compatibility)

### 5a. Minor text swaps (3 commands)

- [ ] `commands/compound-workflows/plan.md` line 63: Replace `intellect-v6-pricing` -> `api-rate-limiting`, `cash-manager-reporting` -> `user-dashboard-reporting` (aligned with Canonical Genericization Table — `cash-manager` maps to `user-dashboard`, `intellect-v6-pricing` maps to `api-rate-limiting`)

- [ ] `commands/compound-workflows/compound.md`:
  - Line 40: Replace `bq-cost-measurement` -> `redis-cache-invalidation`, `upstream-fork-management` -> `api-versioning-strategy`
  - Line 126: Replace `"before any Xiatech meeting"` -> `"before any vendor evaluation meeting"`

- [ ] `commands/compound-workflows/review.md`:
  - Line 30: Replace `feat-cash-management-ui` -> `feat-user-dashboard-redesign`
  - Line 55: Replace `kieran-typescript-reviewer` -> `typescript-reviewer` (Task dispatch name)
  - Line 68: Replace `julik-frontend-races-reviewer` -> `frontend-races-reviewer` (Task dispatch name)
  - Lines 67: REMOVE `kieran-rails-reviewer` and `dhh-rails-reviewer` conditional dispatch blocks entirely
  - Update output file path: `kieran-typescript.md` -> `typescript.md` (this IS referenced — make the change definitively)

### 5b. Discovery logic rewrite (1 command)

- [ ] `commands/compound-workflows/deepen-plan.md`:
  - Line 27: Replace `feat-cash-management-reporting-app` -> `feat-user-dashboard-redesign`
  - Lines 98-107: **Redesign** the agent discovery block (not just string replace). The current logic:
    1. `find ~/.claude/plugins/cache -path "*/agents/*.md"` — finds ALL plugin agents
    2. `find .claude/agents` / `find ~/.claude/agents` — finds local/global agents
    3. Applies a compound-engineering-specific filter (lines 104-106)
  - After the fork, compound-workflows' agents will be at `~/.claude/plugins/cache/*/compound-workflows/*/agents/...` and the generic find on line 98 already catches them. The fix:
    - **Remove** the compound-engineering-specific filter block (lines 104-106)
    - **Replace** with a generic filter that works for ANY plugin's agents:
      ```
      For discovered plugin agents:
      - USE: agents in review/ and research/ subdirectories
      - SKIP: agents in workflow/ subdirectories (utility agents, not review/research)
      - SKIP: agents not in a recognized subdirectory (prevents sweeping in unknown agents)
      ```
    - Remove `agents/design/*` and `agents/docs/*` from USE list (those categories not ported)
    - **Note:** `workflow/` agents (spec-flow-analyzer, bug-reproduction-validator, pr-comment-resolver) are intentionally excluded from dynamic discovery. They are utility agents dispatched by name from specific commands (e.g., plan.md dispatches spec-flow-analyzer directly). They do not belong in deepen-plan's review/research roster.
    - Verify the `find` command on line 98 also catches agents in development mode (source dir, not just cache). Check that `plugins/*/agents/` is also covered.
    - When building the agent manifest (Step 2d), include each agent's `description:` from YAML frontmatter for self-documenting rosters
    - **Discovery guardrails** to prevent prompt bloat at scale: (a) compound-workflows agents take priority over third-party plugin agents with the same name; (b) cap total discovered agents at 30 to prevent context exhaustion; (c) log discovered agents and their source plugin for debugging

### 5c. Setup command rewrite (1 command)

Both the setup **command** and setup **skill** will exist:
- **Command** (`commands/compound-workflows/setup.md`): The interactive entry point users invoke via `/compound-workflows:setup`. Handles the UX flow (AskUserQuestion), environment detection, and config writing.
- **Skill** (`skills/setup/SKILL.md`): Reference material with `disable-model-invocation: true`. Provides the "what to configure" knowledge — stack detection logic, agent lists, depth options.

**How the command uses the skill:** The command does NOT "load the skill and interpret it" at runtime (that would be non-deterministic). Instead, the command is written at fork time by a human/agent who has READ the skill and hardcoded the relevant knowledge directly into the command prompt. The skill is the source-of-truth for what stacks, agents, and options exist; the command is the operationalized version with concrete steps. If the skill is updated later, the command must be manually synced.

- [ ] `commands/compound-workflows/setup.md` — **FULL REPLACEMENT** (do NOT patch the old content). The current setup.md actively recommends installing compound-engineering as an enhancement and provides `claude /install compound-engineering` instructions. The entire file must be replaced, not edited. Start from scratch with this structure:
  - Step 1: Detect environment (beads, PAL MCP, GitHub CLI)
  - Step 2: **Compound-engineering conflict detection**: `ls ~/.claude/plugins/cache/*/compound-engineering 2>/dev/null` — if found, warn user and recommend uninstalling
  - Step 3: Auto-detect stack using hardcoded detection rules (derived from setup skill: Python/TypeScript/general — Rails path removed):
    - Python: check for `requirements.txt`, `pyproject.toml`, `setup.py`, `*.py` in src/
    - TypeScript: check for `tsconfig.json`, `package.json` with typescript dep
    - General: fallback if neither detected
  - Step 4: Configure review agents using hardcoded per-stack defaults (derived from setup skill):
    - Python stack: `python-reviewer`, `security-sentinel`, `code-simplicity-reviewer`, `performance-oracle`
    - TypeScript stack: `typescript-reviewer`, `security-sentinel`, `code-simplicity-reviewer`, `performance-oracle`
    - General: `security-sentinel`, `code-simplicity-reviewer`, `architecture-strategist`, `performance-oracle`
  - Step 5: AskUserQuestion for depth (standard/comprehensive/minimal) and any agent additions/removals
  - Step 6: Create missing directories (docs/brainstorms/, docs/plans/, docs/solutions/)
  - Step 7: Write `compound-workflows.local.md` using the **unified schema** (see Phase 4 findings above)
  - Step 7b: **Migration for existing v1.0.0 configs**: Before writing, check if `compound-workflows.local.md` already exists with the old schema (`review_agents: compound-engineering|general-purpose`). If found, inform the user: "Existing config detected from v1.0.0. Re-running setup to update schema." Overwrite with the new unified schema. This handles users who upgrade without re-running setup.
  - Step 8: Update vocabulary: replace any "compound-engineering" references with "bundled" or equivalent

**Schema consumers** (document in CLAUDE.md, Phase 6d): The following commands read `compound-workflows.local.md`:
- `review.md` reads: `review_agents`, `red_team`, `gh_cli`
- `plan.md` reads: `plan_review_agents`, `depth`
- `deepen-plan.md` reads: `red_team`
- `work.md` reads: `tracker`
- `setup.md` writes all keys
If the schema changes, these consumers must be updated.

### 5d. Update red team methodology (2 commands)

Both `deepen-plan.md` and `brainstorm.md` have red team phases that challenge plans/brainstorms with non-Claude models. Update both to use a consistent multi-model red team pattern:

- [ ] `commands/compound-workflows/deepen-plan.md` Phase 4.5 — Replace the current single-model PAL chat with:
  ```
  Red team with ALL THREE model providers in parallel:
  1. PAL chat (Gemini — latest highest-end model) — non-Claude perspective
  2. PAL chat (OpenAI — latest highest-end model) — non-Claude perspective
  3. Task subagent (Claude Opus — latest version) — Claude perspective, reads local files directly

  Do NOT use PAL for Claude — use a Task subagent instead (direct file access, no token relay overhead).
  Always run all 3. Do not skip providers or fall back to fewer models.
  ```
  - Remove the specific `gemini-2.5-pro` model pin — use `gemini-2.5-pro` as the current recommendation but phrase as "latest highest-end Gemini model"
  - Remove the optional PAL `consensus` step — the 3-model parallel approach replaces it
  - Each red team reviewer writes findings to a separate file: `red-team--gemini.md`, `red-team--openai.md`, `red-team--opus.md`
  - The later red teams receive prior red teams' critiques to avoid duplication

- [ ] `commands/compound-workflows/brainstorm.md` red team phase — Apply the same 3-provider pattern:
  - Replace any single-model or 2-model red team instruction with the 3-provider parallel pattern above
  - Ensure the brainstorm red team also writes findings to disk (`.workflows/brainstorm-research/*/red-team--*.md`)

- [ ] **Both commands** — Update severity surfacing to include MINOR findings:
  - Current behavior: only CRITICAL and SERIOUS items are presented to the user via AskUserQuestion. MINOR items are silently noted for awareness.
  - New behavior: After all CRITICAL and SERIOUS items are resolved, present MINOR items as a batch: "N MINOR findings remain. Review individually or batch-accept?" If the user chooses batch-accept, note all as "acknowledged" in the resolution summary. If the user chooses to review, present each via AskUserQuestion.
  - In `deepen-plan.md`: update Phase 4.5 Step 3 (line ~395) — change "For each CRITICAL or SERIOUS item" to include a follow-up MINOR batch step
  - In `brainstorm.md`: update Phase 3.5 Step 2 (line ~164) — same pattern

### 5e. Verify brainstorm.md agent dispatch compatibility (1 command)

brainstorm.md has zero `compound-engineering` references and zero company-specific examples, but it dispatches agents (`repo-research-analyst`, `context-researcher`, `general-purpose`) that will now resolve to bundled agent files instead of relying on inline fallback descriptions. Verify this works correctly.

- [ ] `commands/compound-workflows/brainstorm.md`:
  - Verify all Task dispatch agent names match bundled agent filenames / YAML `name:` fields (per resolution mechanism established in Phase 1a)
  - Verify inline role descriptions in Task prompts work as task instructions (not identity) when full agent definitions are loaded alongside them
  - If the agent resolution mechanism (Phase 1a) requires format changes to Task dispatch names, apply them here
  - No genericization or text swaps needed — this is a compatibility check only

### Deepen-Plan Findings (Run 1)

**Critical — Discovery filter specification (Phase 5b):**

The plan said "replace with generic filter" but did not specify the exact logic. The filter must:
1. Accept agents in `review/` and `research/` subdirectories from ANY plugin
2. Reject agents in `workflow/` subdirectories (utility agents)
3. Reject agents not in a recognized subdirectory to prevent sweeping in unknown agents from other plugins
4. Include agent `description:` from YAML frontmatter in the manifest for visibility

This generic filter is the correct architectural direction (Open/Closed principle — new plugins can add agents without modifying deepen-plan). [review--architecture-strategist, research--command-analysis]

**Recommendations:**
- review.md output file path `kieran-typescript.md` -> `typescript.md` IS referenced and should be changed definitively, not conditionally. [research--command-analysis]
- Phase 5c Step 3: Rails stack path should be removed from the detection options since Rails agents are dropped. The choices become Python/TypeScript/general. [research--setup-skill-audit]
- Phase 5c Step 6 must produce the unified schema specified in the Phase 4 findings. The implementer should NOT design this during execution — use the schema template above. [research--setup-skill-audit]
- Verify deepen-plan.md line ~27 `feat-cash-management-reporting-app` is also genericized (this was listed in Phase 5b line items but could be missed since it's separate from the discovery logic rewrite). [research--command-analysis]

**Contradiction noted:**
- code-simplicity-reviewer argues the setup command/skill split is a YAGNI violation and recommends folding the skill into the command. architecture-strategist says the split is "justified but novel" and recommends documenting it in CLAUDE.md. Decision: **keep the split** as planned since the skill is being forked from compound-engineering regardless, but document the pattern in CLAUDE.md (Phase 6d).

---

## Phase 6: Documentation and Config Updates

### 6a. Verify NOTICE file

- [ ] Verify `plugins/compound-workflows/NOTICE` contains full MIT license text (created in Phase 1d — do NOT re-create; only verify content is complete)

### 6b. Update plugin.json

- [ ] Bump version: `1.0.0` -> `1.1.0`
- [ ] Remove `compound-engineering` from keywords array
- [ ] Update description if needed to reflect self-contained nature
- [ ] **Verify directory registration**: Check if plugin.json has `agents`, `skills`, or `files` fields that control packaging/distribution. If so, ensure new `agents/review/`, `agents/research/`, `agents/workflow/`, and all 14 skill directories are registered. Also verify the `commands` array reflects the post-merge state (6 commands, no `work-agents`). Verify NOTICE and FORK-MANIFEST.yaml are included in the package.

### 6c. Update README.md

- [ ] Update component counts (1 agent -> 22 agents, 1 skill -> 15 skills)
- [ ] Update command count (7 -> 6 after work-agents merge)
- [ ] Update dependency table: remove compound-engineering as "Recommended", note it's superseded
- [ ] Add "Based on compound-engineering" attribution section
- [ ] Add "Do not install alongside compound-engineering" warning
- [ ] Note: Do NOT document an upstream sync process that does not yet exist. A simple "Forked from compound-engineering (MIT)" attribution is sufficient for v1.1.0.

### 6d. Update CLAUDE.md

- [ ] Update directory structure to show review/ and workflow/ agent categories
- [ ] Update testing instructions to remove compound-engineering references
- [ ] Update component counts
- [ ] Document the setup command/skill split pattern: "The setup command reads the setup skill for configuration knowledge. This is a deliberate split: the command handles the interactive flow, the skill provides the domain knowledge."
- [ ] Add agent registry table listing all 22 agents with columns: name, category, dispatched by (commands), model (if non-default — e.g., `haiku` for cost-optimized agents, `inherit` for default). This documents which agents run on smaller models for cost control so users can override if desired.

### 6e. Update CHANGELOG.md

- [ ] Add v1.1.0 entry (write AFTER Phase 7 verification confirms all counts):
  - 21 new agents (5 research, 13 review, 3 workflow) -> 22 total with existing context-researcher
  - 14 new skills (5 command-referenced + 9 utility) -> 15 total with existing disk-persist-agents
  - 3 agents renamed/depersonalized (typescript-reviewer, python-reviewer, frontend-races-reviewer)
  - 5 commands updated (example genericization, discovery logic rewrite, setup rewrite)
  - work-agents.md merged into work.md (6 commands total, down from 7)
  - NOTICE file added (full MIT license text, attribution to Kieran Klaassen / compound-engineering)
  - Plugin is now fully self-contained — compound-engineering no longer needed

### 6f. Create FORK-MANIFEST.yaml

- [ ] Create `plugins/compound-workflows/FORK-MANIFEST.yaml` tracking per-file: source path in compound-engineering, source version (2.35.2), modification status (unmodified / renamed / genericized / rewritten). This enables structured upstream sync if needed in the future. Use this schema:

  ```yaml
  # FORK-MANIFEST.yaml
  source_plugin: compound-engineering
  source_version: "2.35.2"
  fork_date: "2026-02-25"

  files:
    - local_path: agents/review/security-sentinel.md
      source_path: agents/review/security-sentinel.md
      status: unmodified  # unmodified | renamed | genericized | rewritten
      notes: null
    - local_path: agents/review/typescript-reviewer.md
      source_path: agents/review/kieran-typescript-reviewer.md
      status: renamed
      notes: "Persona removed, name: field updated"
    - local_path: skills/compound-docs/SKILL.md
      source_path: skills/compound-docs/SKILL.md
      status: genericized
      notes: "BriefSystem->AuthService, EmailProcessing->PaymentProcessor"
    # ... one entry per forked file (91 total)
  ```

**Phase 6 total: 6 files updated/created. -> Commit 5.**

### Deepen-Plan Findings (Run 1)

**Recommendations:**
- The original Phase 6a said "Create NOTICE file" but the NOTICE is already created in Phase 1d. Changed to "Verify NOTICE file" to avoid confusion. [review--architecture-strategist, review--code-simplicity-reviewer]
- Add FORK-MANIFEST.yaml (new Phase 6f) to track per-file source path, version, and modification status. Without this, future upstream sync will be ad-hoc. [review--architecture-strategist]
- Do NOT document a sync cadence or process that does not exist yet. Keep attribution simple for v1.1.0. [review--code-simplicity-reviewer]
- Add an agent registry table to CLAUDE.md listing all 22 agents, their categories, and which commands dispatch them. This serves as a centralized cross-reference for Phase 7d verification and future maintenance. [review--architecture-strategist]

---

## Phase 7: Verification

### 7a. File count verification

- [ ] Count agent files: `find plugins/compound-workflows/agents -name "*.md" -type f | wc -l` -> expect 22 (21 new + 1 existing)
- [ ] Count skill files: `find plugins/compound-workflows/skills -type f | wc -l` -> expect 71 (70 new + 1 existing)
- [ ] Verify NOTICE file exists and contains full MIT license text
- [ ] Verify FORK-MANIFEST.yaml exists
- [ ] Verify script files retained executable permissions: `ls -la plugins/compound-workflows/skills/git-worktree/scripts/`, `ls -la plugins/compound-workflows/skills/gemini-imagegen/scripts/`
- [ ] Enumerate all executable files: `find plugins/compound-workflows/skills -type f -perm +111` — confirm list matches expectations (~11 scripts)

### 7b. Content verification (automated grep sweep)

Run all of these — each should return zero results unless noted:

- [ ] `grep -r "compound-engineering" plugins/compound-workflows/` — allowed ONLY in NOTICE attribution and FORK-MANIFEST.yaml source paths. **Note: search ALL file types, not just .md/.yaml/.json.**
- [ ] `grep -r "kieran-" plugins/compound-workflows/` — zero results
- [ ] `grep -r "julik-" plugins/compound-workflows/` — zero results
- [ ] `grep -r "BriefSystem" plugins/compound-workflows/` — zero results
- [ ] `grep -r "EmailProcessing" plugins/compound-workflows/` — zero results
- [ ] `grep -r "Xiatech" plugins/compound-workflows/` — zero results
- [ ] `grep -r "cash-management\|cash-manager" plugins/compound-workflows/` — zero results
- [ ] `grep -r "intellect-v6" plugins/compound-workflows/` — zero results
- [ ] `grep -r "Every Reader" plugins/compound-workflows/` — zero results
- [ ] `grep -r "dhh-rails\|kieran-rails" plugins/compound-workflows/` — zero results
- [ ] `grep -r "EveryInc" plugins/compound-workflows/` — zero results
- [ ] `grep -r "work-agents" plugins/compound-workflows/` — zero results (post-merge cleanup)
- [ ] **Credential scan**: `grep -rEi "(api[_-]?key|api[_-]?secret|bearer |token['\"]?\s*[:=]|sk-[a-zA-Z0-9]{20,}|ghp_|gho_|github_pat_)" plugins/compound-workflows/ --include="*.sh" --include="*.py" --include="*.yaml"` — zero results
- [ ] **Relative path scan**: `grep -rn "\.\./\.\." plugins/compound-workflows/agents/ plugins/compound-workflows/skills/` — verify each match resolves correctly in new directory structure
- [ ] **Copyright header check**: `grep -r "Copyright\|copyright\|(c)" plugins/compound-workflows/ --include="*.sh" --include="*.py"` — confirm headers survived modifications

### 7c. YAML frontmatter validation

- [ ] Verify 3 renamed agents have correct `name:` field matching filename:
  - `typescript-reviewer.md` has `name: typescript-reviewer`
  - `python-reviewer.md` has `name: python-reviewer`
  - `frontend-races-reviewer.md` has `name: frontend-races-reviewer`
- [ ] Verify setup skill preserves `disable-model-invocation: true` in frontmatter
- [ ] Verify merged work.md has `name: work` (not `work-agents`)
- [ ] **Model field audit**: Enumerate all agents with a non-default `model:` field in YAML frontmatter (e.g., `model: haiku`). These are intentional cost optimizations from compound-engineering — agents where the task is well-scoped enough for a smaller model. Document each in the CLAUDE.md agent registry table (Phase 6d) with a "Model" column so users can see which agents run on haiku vs. inheriting the default, and override if desired.

### 7d. Cross-reference verification

- [ ] Every agent name dispatched by commands has a matching .md file in agents/
- [ ] Every skill referenced in commands has a matching SKILL.md in skills/
- [ ] deepen-plan.md discovery logic finds agents from compound-workflows' directory (not compound-engineering)
- [ ] setup.md references setup skill and detects compound-engineering conflict
- [ ] review.md has zero references to dropped agents (Rails reviewers)
- [ ] Output file paths in review.md match renamed agents (typescript.md not kieran-typescript.md)
- [ ] Cross-check against agent registry table in CLAUDE.md (if created in Phase 6d)

### 7e. ~~Line count verification (truncation check)~~ REMOVED — redundant

Phase 1e already verifies byte-identical diffs on zero-change files, which is strictly stronger than line count comparison. For modified files, line counts are meaningless (genericization changes content). Removed to reduce checklist noise.

### 7f. v1.0.0 QA issues (address alongside fork verification)

These are pre-existing QA issues from v1.0.0 that should be verified during the fork since we're touching these files anyway. They are separate from fork correctness but low-cost to check.

- [ ] Verify no command files were truncated (expected: brainstorm 198, plan 278, work ~380, compound 141, deepen-plan 446, review 162, setup 192)
- [ ] Verify all Task dispatches in commands have inline role descriptions ("You are a...")
- [ ] Verify TodoWrite fallback guidance is complete in work.md body (not just intro block)
- [ ] Verify no hardcoded "the current year is 2026" (illustrative dates in examples are fine — but git-history-analyzer.md line 22 needs review)
- [ ] Verify skill cross-references now resolve locally (brainstorming, document-review, file-todos, git-worktree, compound-docs all ported)

### 7g. Functional smoke tests

**Test project definition**: Create a git repo with a `package.json` (triggers TypeScript stack detection) or `pyproject.toml` (triggers Python). No prior `compound-workflows.local.md`. Install the plugin in development mode (`claude /install /path/to/plugins/compound-workflows`).

- [ ] Run `/compound-workflows:setup` in a test project — verify it detects bundled agents, not compound-engineering dependency
- [ ] Run `/compound-workflows:plan` with a simple feature — verify research agents dispatch to bundled agent files (check output for agent methodology, not just 1-sentence inline)
- [ ] Verify `/compound-workflows:review` uses `typescript-reviewer` not `kieran-typescript-reviewer`
- [ ] Verify `/compound-workflows:setup` produces a warning when compound-engineering is also installed
- [ ] **Negative-path test**: In a project with Ruby/Rails files, verify `/compound-workflows:review` does NOT attempt to dispatch `kieran-rails-reviewer` or `dhh-rails-reviewer`. Should fall through to the general agent roster gracefully.
- [ ] **Clean-install packaging test**: Install the plugin fresh via `claude /install <path>` in a clean environment (no prior compound-workflows or compound-engineering). Verify: agents/ and skills/ directories are present in the cache, `/compound-workflows:setup` completes successfully, agent discovery in deepen-plan finds bundled agents.
- [ ] **Renamed output filename test**: Verify review.md produces `typescript.md` (not `kieran-typescript.md`), `python.md` (not `kieran-python.md`), and `frontend-races.md` (not `julik-frontend-races.md`) as output filenames.

### Deepen-Plan Findings (Run 1)

**Recommendations:**
- Phase 7b first grep now searches ALL file types (removed `--include` filter) per security-sentinel finding. The original filter missed .sh, .py, and extensionless scripts. [review--security-sentinel]
- Added credential pattern scan, relative path scan, and copyright header check to Phase 7b. [review--security-sentinel]
- Added executable file enumeration to Phase 7a. [review--security-sentinel]
- Added `work-agents` grep to Phase 7b for post-merge cleanup verification.
- Phase 7f line counts updated: work ~380 (merged), work-agents removed from list.
- Phase 7c: added work.md frontmatter name check.

**Noted but not adopted:**
- code-simplicity-reviewer recommends collapsing Phase 7 to ~8 checks and removing Phase 7e (redundant with diff) and 7f (scope creep). Decision: **keep 7e and 7f** since the cost is low and they catch real issues (truncation, QA regressions). However, Phase 7e is indeed redundant for zero-change files if Phase 1e's byte-identical diff passes — the executor may skip 7e for zero-change files.

---

## Execution Order

```
Phase 0 (work-agents merge)     -> Commit 0: housekeeping before fork
         |
Phase 1 (copy all + NOTICE)     -> Commit 1: pure copy, verifiable against source
         |
Phase 2-3 (rename + genericize) -> Commit 2: all content modifications
         |
Phase 4 (HIGH-effort mods)      -> Commit 3: setup skill + orchestrating-swarms
         |
Phase 5 (update commands)       -> Commit 4: depends on agent names being finalized
         |
Phase 6 (docs/config)           -> Commit 5: depends on final counts from verification
         |
Phase 7 (verification)          -> Run after each commit; full sweep after Commit 5
```

**Context exhaustion strategy:** This port touches ~96 files. If executing via Claude, use `/compound-workflows:work` to dispatch each phase as a separate subagent. Each subagent handles one commit's worth of work. The manifest at `.workflows/work/` tracks progress across compactions.

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| Missing a file in complex skill dirs | Phase 7a file count verification against source inventory |
| Stale compound-engineering reference | Phase 7b automated grep sweep (all file types) |
| Renamed agent not updated in commands | Phase 7d cross-reference check + agent registry in CLAUDE.md |
| Fork diverges from upstream | FORK-MANIFEST.yaml tracks per-file source version and modification status |
| Users install both plugins | Setup command detects + warns on conflict |
| Context exhaustion during port | Multi-commit strategy; use work for subagent dispatch |
| Inconsistent genericization | Canonical replacement table (above) |
| Script permissions lost | `cp -p` / `cp -rp` preserves permissions; Phase 7a enumerates executables |
| orchestrating-swarms over-match | Per-instance manual review with 26-item transformation manifest |
| Leaked credentials in copied scripts | Phase 7b credential pattern scan |
| MIT license non-compliance | Full MIT license text in NOTICE file (not summary) |
| Renamed output filenames break downstream | CHANGELOG documents renames; Phase 7g tests new filenames |
| Stale v1.0.0 config after upgrade | Phase 5c Step 7b detects old schema and prompts re-setup |
| Setup schema conflict between command and skill | Unified schema template specified in Phase 4 findings |
| Intermediate commits break setup | Do NOT publish pre-Commit-4 states as releases |

## Sources

- **Origin brainstorm:** `docs/brainstorms/2026-02-25-port-gaps-compound-engineering-brainstorm.md` — fork decision, agent/skill selection, genericization strategy, red team resolutions
- **Repo research:** `.workflows/plan-research/fork-compound-engineering-agents-skills/agents/repo-research.md` — per-command change analysis
- **Source inventory:** `.workflows/plan-research/fork-compound-engineering-agents-skills/agents/source-inventory.md` — per-file effort estimates, complete file manifest
- **Learnings:** `.workflows/plan-research/fork-compound-engineering-agents-skills/agents/learnings.md` — format conventions, QA issues from v1.0.0
- **Red team critiques:** `.workflows/brainstorm-research/port-gaps-compound-engineering/red-team-*.md`
- **Specflow analysis:** `.workflows/plan-research/fork-compound-engineering-agents-skills/agents/specflow.md` — ordering risks, testing gaps, edge cases
- **compound-engineering source:** `~/.claude/plugins/cache/every-marketplace/compound-engineering/2.35.2/` (version-pinned cache path — use this for all copy operations, not the marketplace path)
- **Deepen-plan run 1:** `.workflows/deepen-plan/feat-fork-compound-engineering-agents-skills/run-1-synthesis.md` — 9-agent review (6 research + 3 review), 16 findings, 4 contradictions resolved
- **Red team critiques (run 1):** `.workflows/deepen-plan/feat-fork-compound-engineering-agents-skills/agents/run-1/red-team--critique.md` (Gemini), `red-team--gpt5.md` (GPT-5.2), `red-team--opus.md` (Opus)

---

## Red Team Resolution Summary (Run 1)

### CRITICAL — Resolved via user review (5 findings)

| ID | Finding | Resolution | Plan change |
|----|---------|------------|-------------|
| O3/A1 | Agent resolution mechanism unspecified | **Valid** | Added Phase 1a prerequisite — empirically test resolution before proceeding |
| G1/O4 | Phase 0 merge is architecture redesign | **Valid** | Rewrote Phase 0a — work-agents.md replaces work.md (not a merge) |
| O2 | brainstorm.md absent from Phase 5 | **Valid** | Added Phase 5e — verify brainstorm agent dispatch compatibility |
| G2 | Script security review is recommendation, not task | **Valid** | Promoted to Phase 1d — concrete checklist with review criteria |
| A4 | Setup skill loading non-deterministic | **Valid** | Rewrote Phase 5c — hardcode knowledge at fork time, not runtime loading |

### SERIOUS — Resolved via batch judgment (17 findings)

| # | ID | Finding | Judgment | Plan change |
|---|-----|---------|----------|-------------|
| 1 | A2 | Workflow agents shipped but undiscoverable | **Intentional** — utility agents dispatched by name, not discovered | Added note to Phase 5b filter |
| 2 | O5 | 8 orphaned utility skills | **Acceptable** — Claude auto-discovers skills by description match | Clarified in Phase 6e CHANGELOG entry |
| 3 | C3/O6 | Genericization table contradicts Phase 5a | **Fix** — Phase 5a mismatched the table | Fixed Phase 5a to use `api-rate-limiting` and `user-dashboard-reporting` per table |
| 4 | O7 | Setup advertises compound-engineering install | **Valid** — easy to miss during partial rewrite | Added FULL REPLACEMENT callout to Phase 5c |
| 5 | O9 | No migration for v1.0.0 config files | **Valid** | Added Phase 5c Step 7b — detect old schema, prompt re-setup |
| 6 | D1 | Two different source-of-truth paths | **Fix** — standardize on cache path | Fixed Sources section to use `2.35.2` cache path |
| 7 | G4/O12 | FORK-MANIFEST has no schema | **Valid** | Added example YAML schema to Phase 6f |
| 8 | G5 | No negative-path testing for removed functionality | **Valid** | Added Rails negative-path smoke test to Phase 7g |
| 9 | M3 | No clean-install packaging test | **Valid** | Added clean-install test to Phase 7g |
| 10 | M2 | plugin.json may not register new dirs | **Valid** | Added directory verification step to Phase 6b |
| 11 | G6 | Setup split sidesteps core debate | **Already resolved** | Documented in Phase 5c deepen-plan findings; split kept |
| 12 | C1 | Command count internally inconsistent | **Already fixed** | Phase 0d corrected to 7 commands post-merge |
| 13 | R1 | Discovery noisy at scale | **Valid** | Added guardrails to Phase 5b: priority, cap at 30, logging |
| 14 | R2 | Schema consumers undefined | **Valid** | Added consumer map to Phase 5c (review, plan, deepen-plan, work, setup) |
| 15 | R3 | Script runtime deps unaddressed | **Valid** | Added shebang/version/dep checks to Phase 1d |
| 16 | O2-GPT | Phase 7f mixes objectives | **Acceptable** — low cost, keep together | Added explanatory note to Phase 7f header |
| 17 | M4 | No regression plan for renamed output filenames | **Valid** | Added to Phase 7g smoke tests + Risk Mitigation table |

### MINOR — Resolved (5 findings)

| # | ID | Finding | Judgment | Plan change |
|---|-----|---------|----------|-------------|
| 1 | G7 | No prerequisite check for source cache path | **Valid** | Added `ls` check at top of Phase 1 — stop if source missing |
| 2 | G8 | Phase 7e redundant with Phase 1e diff | **Valid** | Removed Phase 7e — byte-identical diff is strictly stronger |
| 3 | O10 | Brainstorm header says "22 new" (should be 21) | **Valid** | Fixed brainstorm doc to "21 new (22 total)" |
| 4 | O11 | `model:` fields silently carried over | **Valid** | Added model field audit to Phase 7c; document in CLAUDE.md agent registry with "Model" column for cost transparency |
| 5 | O13 | Smoke tests lack test fixture definition | **Valid** | Added test project definition to Phase 7g header |
