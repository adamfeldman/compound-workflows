# Red Team Critique — Claude Opus 4.6

**Date:** 2026-02-25
**Model:** claude-opus-4.6
**Run:** 1
**Focus:** New findings not covered by Gemini 2.5 Pro or GPT-5.2

---

## CRITICAL

### O1. The plan silently breaks the brainstorm.md and plan.md commands by not updating their agent dispatch prompts

The plan focuses on updating `review.md`, `deepen-plan.md`, `setup.md`, `compound.md`, and `plan.md` (Phase 5a-5c). However, examining the actual command files reveals that `plan.md` dispatches agents using inline role descriptions with `Task repo-research-analyst`, `Task learnings-researcher`, `Task best-practices-researcher`, `Task framework-docs-researcher`, and `Task spec-flow-analyzer` (lines 73-191 of plan.md). Phase 5a only updates a single line in plan.md (line 63: genericize example names). It does NOT update the inline role descriptions in the Task dispatch blocks.

After the fork, these agents will resolve to the bundled agent .md files instead of the inline fallbacks. The 1-sentence inline descriptions currently serve as the COMPLETE prompt. Once Claude resolves `Task learnings-researcher` to the full 265-line agent definition, the inline description becomes the Task instruction (what to research), not the agent identity. This is actually the desired behavior — but the plan never verifies that the inline descriptions work correctly AS TASK INSTRUCTIONS when the full agent definitions are loaded. The smoke tests in Phase 7g test `plan`, `review`, and `setup`, but do not test that agent Task dispatches with inline descriptions PLUS loaded agent definitions produce coherent output rather than confused instructions.

**Reference:** Phase 5a (plan.md changes), plan.md lines 73-191, Phase 7g

### O2. The brainstorm command is completely absent from Phase 5

The brainstorm command (`brainstorm.md`) is not listed anywhere in Phase 5, yet the brainstorm document says "All commands: Remove compound-engineering as optional dependency — plugin is now self-contained. Genericize any company-specific examples encountered during updates." The Scope Summary lists "5 of 7" (later "5 of 6") commands to update, and Phase 5 covers plan.md, compound.md, review.md, deepen-plan.md, and setup.md. brainstorm.md is silently excluded.

If brainstorm.md contains any references to compound-engineering agents, inline fallback descriptions, or company-specific examples, they will survive the fork unmodified. Neither Gemini nor GPT-5.2 noticed this missing command. The Phase 7b grep would catch `compound-engineering` string literals, but would NOT catch stale inline role descriptions that should be updated to reference the richer bundled agents.

**Reference:** Phase 5, Scope Summary, brainstorm origin document "Commands: 7 existing, need updates"

### O3. The plan assumes Claude's Task dispatch resolves agent names via filesystem discovery, but never specifies or validates the resolution mechanism

The entire fork premise is: "bundled agent .md files replace 1-sentence inline fallbacks." But how does `Task security-sentinel (run_in_background: true): "You are..."` actually resolve to `agents/review/security-sentinel.md`? GPT-5.2 raised a related concern (A1) about dev-mode paths, but the deeper issue is: the plan never establishes what the actual agent resolution rules ARE.

Possible resolution behaviors: (a) Claude matches the Task agent name against YAML `name:` fields in agent files; (b) Claude matches against filenames; (c) Claude matches against directory-qualified paths like `review/security-sentinel`; (d) Claude requires the plugin prefix like `compound-workflows:review:security-sentinel`. The plan references all four formats in different places without establishing which one Claude Code actually uses. The orchestrating-swarms transformation (Phase 4b) assumes format (d). The review.md command (Phase 5a) uses bare names like `Task kieran-typescript-reviewer`. The deepen-plan discovery logic assumes format (a) or (b).

If the resolution mechanism is format (d) — plugin-qualified — then every Task dispatch in every command needs the `compound-workflows:` prefix, and the plan only addresses this in orchestrating-swarms. If it is format (a) — YAML name field — then the Phase 7c check on renamed agents is critical but insufficient (only checks 3 agents, not all 22).

**Reference:** Phase 4b, Phase 5a, Phase 7c, all command files

---

## SERIOUS

### O4. The work-agents.md merge (Phase 0) destroys a carefully designed architecture without specifying what replaces it

Gemini flagged the content merge as unspecified (their #1), but missed the deeper issue: work-agents.md is not a duplicate of work.md — it is an ALTERNATIVE ARCHITECTURE. Examining the actual files: work.md is a direct-execution model (main context writes code), while work-agents.md is a subagent-dispatch model (orchestrator dispatches, subagents code). They share the same beads/worktree infrastructure but have fundamentally different execution philosophies.

The plan says "merge work-agents.md into work.md" with a target of ~380 lines (down from 318+390=708). That is a 46% reduction. This is not a merge — it is a redesign that picks one architecture and discards the other, or creates a hybrid. The plan treats this as "housekeeping" (Phase 0, before the fork even begins) when it is actually the most consequential architectural decision in the entire plan. It determines whether the primary work command uses direct execution or subagent dispatch.

**Reference:** Phase 0, work.md, work-agents.md

### O5. The plan creates 9 "utility" skills that no command references or invokes

Of the 14 new skills, only 5 are referenced by commands (brainstorming, document-review, file-todos, git-worktree, compound-docs). The remaining 9 (setup, gemini-imagegen, agent-browser, orchestrating-swarms, create-agent-skills, agent-native-architecture, resolve-pr-parallel, skill-creator, frontend-design) are ported as "utility" skills with no concrete invocation path from any command.

The setup skill is referenced by the setup command (Phase 5c), but the other 8 are truly orphaned — they exist in the plugin directory but no command loads, references, or dispatches them. Skills are passive (loaded when Claude decides they are relevant to the user's query, or when a command explicitly references them). Without a command reference, these 8 skills rely entirely on Claude's autonomous skill discovery, which is undocumented and non-deterministic.

The plan spends significant effort on two of these orphaned skills: orchestrating-swarms (Phase 4b, 30-60 minutes of manual review) and agent-native-architecture (Phase 3c, 15 files, 6 needing edits). This is substantial work for files with no guaranteed invocation path.

**Reference:** Phase 1c, Phase 3c, Phase 4b, brainstorm "Skills: 14 new"

### O6. The genericization table has a naming collision: `api-rate-limiting` appears as the replacement for TWO different original terms

The Canonical Genericization Table specifies: `intellect-v6-pricing -> api-rate-limiting`. Phase 5a specifies: `cash-manager-reporting -> api-rate-limiting` (plan.md line 63). GPT-5.2 caught the first-hop inconsistency (C3: plan.md line 63 says `intellect-v6-pricing -> user-auth-flow` while the table says `api-rate-limiting`). But the deeper issue is that even within the table, `api-rate-limiting` is used as a replacement value AND `cash-management / cash-manager -> user-dashboard` is a separate replacement. The plan.md line 63 reference to `cash-manager-reporting -> api-rate-limiting` creates a third variant.

There are actually three different original terms (`intellect-v6-pricing`, `cash-manager-reporting`, `cash-management`) being mapped to overlapping replacement values across different files, and the table, Phase 5a, and the brainstorm disagree on which maps to which. This is not just a typo — it means the implementer cannot know which replacement to apply where without re-auditing each occurrence.

**Reference:** Canonical Genericization Table, Phase 5a, plan.md line 63

### O7. The existing setup command actively recommends installing compound-engineering — this is not just a "text swap"

The current setup.md (Phase 2, line 49) displays compound-engineering as an enhancement to install: "compound-engineering: [Installed/Not found] — Specialized review/research agents." The "Install missing enhancements" path (line 85-88) provides explicit installation instructions: `claude /install compound-engineering`. Phase 5c says "rewrite" the setup command, but the plan never explicitly calls out that the current setup command is an ADVERTISEMENT for compound-engineering.

If any implementation shortcut is taken (partial rewrite, copy-paste from old content), the setup command could end up both warning about compound-engineering conflict (new behavior) AND recommending its installation (old behavior). Phase 7b would catch the string `compound-engineering` in the rewritten file, but only if the implementer remembers that the old setup content should be completely replaced, not patched.

**Reference:** Phase 5c, current setup.md lines 49-88

### O8. Phase 7d cross-reference verification assumes a static agent roster, but deepen-plan uses dynamic discovery

Phase 7d says "Every agent name dispatched by commands has a matching .md file in agents/." This works for commands with hardcoded agent names (review.md, plan.md, compound.md). But deepen-plan.md (Phase 5b) uses DYNAMIC discovery — it finds agents at runtime via `find` commands. The cross-reference verification cannot validate a dynamic roster against static files because the roster is determined at runtime based on what plugins are installed.

This means deepen-plan could discover and dispatch agents that do not exist in compound-workflows (from other plugins), or could fail to discover compound-workflows agents if the directory structure does not match the filter rules. Phase 7d's static check gives false confidence about deepen-plan's runtime behavior.

**Reference:** Phase 7d, Phase 5b

### O9. The plan never addresses what happens to compound-workflows.local.md files that already exist from v1.0.0 setup

Users who ran `/compound-workflows:setup` with v1.0.0 have a `compound-workflows.local.md` file with the old schema: `{tracker, red_team, review_agents: compound-engineering|general-purpose, gh_cli}`. When they upgrade to v1.1.0 and re-run setup, the new unified schema writes different keys. But what if they DON'T re-run setup? Commands that read `compound-workflows.local.md` will encounter the old schema. The `review_agents: compound-engineering` value is now meaningless (the plugin bundles its own agents).

The plan specifies no migration path for existing config files. Phase 5c Step 7 says "replace any compound-engineering references with bundled or equivalent" in the local config, but this is part of the setup command's write logic — it only applies when setup runs. A user who upgrades the plugin without re-running setup gets a stale config that references a non-existent dependency.

**Reference:** Phase 5c, Phase 4 findings (unified schema), current setup.md Phase 4

---

## MINOR

### O10. The plan counts agents inconsistently: brainstorm says 22 new (23 total), plan says 21 new (22 total)

The brainstorm "Scope" section lists "22 new (23 total with existing context-researcher)" while the plan's "Scope Summary" says "Agents (new): 21" and Phase 6e says "21 new agents -> 22 total." The brainstorm lists agents 1-22 in its numbered list, with #1 being context-researcher (existing). That gives 21 new, consistent with the plan. But the brainstorm header says "22 new" which is wrong by its own numbering. This is a source-of-truth error that could propagate into CHANGELOG and README if someone uses the brainstorm as reference.

**Reference:** Brainstorm scope section, Plan scope summary, Phase 6e

### O11. No plan for handling the `model:` field in forked agent YAML frontmatter

The brainstorm's Key Decisions table says "Model fields: Keep haiku/inherit as-is — Preserves cost optimization." But the plan never addresses this as an implementation step. Several compound-engineering agents likely have `model: haiku` or similar fields in their YAML frontmatter. These fields are being carried over silently in the "zero-change" copies. If compound-workflows users have different model configurations or if the `haiku` model alias changes behavior, these inherited model fields could cause unexpected cost or quality differences. The plan should at minimum document which agents have non-default model fields so implementers and users know what they are getting.

**Reference:** Brainstorm Key Decisions, Phase 1b (zero-change agents)

### O12. The FORK-MANIFEST.yaml (Phase 6f) has no specified schema

Phase 6f says "tracking per-file: source path in compound-engineering, source version (2.35.2), modification status (unmodified / renamed / genericized / rewritten)." But no YAML schema is provided. For 91 files, this is a non-trivial document. Without a schema, the implementer will invent one, and it may not support the future sync process it is designed to enable. Gemini called this "architecture on credit" (their #4), but specifically the missing schema means even the credit is unstructured.

**Reference:** Phase 6f

### O13. Phase 7g smoke tests require a "test project" but the plan provides no test fixture or setup instructions

Phase 7g says "Run /compound-workflows:setup in a test project" and "Run /compound-workflows:plan with a simple feature." These require a real project environment with a git repo, possibly a package.json or similar, and the plugin installed in development mode. The plan provides no instructions for creating this test environment, no test fixture, and no definition of what "a test project" means. Each implementer will improvise differently, making the smoke tests non-reproducible.

**Reference:** Phase 7g
