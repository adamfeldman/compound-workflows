# Red Team Critique — GPT-5.2

**Date:** 2026-02-25
**Model:** gpt-5.2
**Run:** 1
**Focus:** New findings not covered by Gemini 2.5 Pro

---

## CRITICAL

### A1. Discovery logic assumes Claude runtime resolves agents the way the plan imagines
Phase 5b's "find agents" shell logic + generic filter rules assume this maps cleanly to how Claude actually resolves/loads plugin agents at runtime, across cache installs, development mode, and multiple plugins/versions. Plan mentions "verify find catches agents in development mode" but never specifies dev-mode paths or a deterministic detection method. Could silently revert to "1-sentence inline" fallback.

**Reference:** Phase 5b, Phase 7g

### A4. "Command reads skill for knowledge" is non-deterministic at runtime
Phase 5c says "load the setup skill for stack detection knowledge" but this depends on model behavior ("read the skill and follow it"). Two runs could write different schemas/lists because the "load skill" step isn't operationally specified — no exact sections to parse, no precedence rules, no conflict handling.

**Reference:** Phase 5c, Phase 6d

### M1. No deterministic agent name cross-reference validation
Agent names appear in command Task dispatches, orchestrating-swarms references, setup default lists, and CLAUDE registry table. Phase 7d is phrased as a checklist, not a concrete procedure. Missing: a one-liner pipeline that extracts all referenced identifiers and compares against frontmatter `name:` and filenames.

**Reference:** Phase 7d, Phase 5a, Phase 4b

---

## SERIOUS

### A2. Workflow agents shipped but designed to be undiscoverable
The plan forks 3 workflow agents (Phase 1b) but the discovery filter (Phase 5b) skips `workflow/` directories. These agents are "shipped but undiscoverable." If any command or skill later expects them, the plan bakes in silent failure.

**Reference:** Phase 5b, Phase 1b

### R1. Generic plugin agent discovery will become noisy at scale
Beyond Gemini's "too permissive" — the new risk is **non-deterministic rosters** (order depends on filesystem traversal), **prompt bloat** (more candidates = context exhaustion), and **incompatible agent behavior** from other plugins. No stable ordering, cap, prioritization, or allowlist.

**Reference:** Phase 5b

### R2. Setup schema consumers undefined
The unified schema in compound-workflows.local.md is richer but the plan never lists who reads it, how strict parsing is, or backwards compatibility from existing files. Configuration drift likely.

**Reference:** Phase 4 findings, Phase 5c

### M2. plugin.json may not register forked agents/skills
Phase 6b only updates version/keywords/description. Plan assumes filesystem-based discovery, but plugin.json may control packaging. Never verified: new directories included in distribution, commands list correct after merge, NOTICE/FORK-MANIFEST in package.

**Reference:** Phase 6b, Phase 0

### M3. No clean-install packaging test
Phase 7g does runtime smoke tests but not a packaging test — install the built plugin fresh in a clean environment. Given heavy reliance on cache paths.

**Reference:** Phase 7g

### D1. Two different source-of-truth paths
Sources section lists `~/.claude/plugins/marketplaces/every-marketplace/plugins/compound-engineering/` but synthesis uses `~/.claude/plugins/cache/every-marketplace/compound-engineering/2.35.2/`. Not interchangeable — one is marketplace, other is versioned cache.

**Reference:** Sources section

### C1. Command count internally inconsistent
Phase 0d verification excerpt shows confusion about whether there are 6 or 7 commands. Undermines count-based verification elsewhere.

**Reference:** Phase 0d

### C3. Genericization table contradicts Phase 5a
Table: `intellect-v6-pricing → api-rate-limiting`. Phase 5a: `intellect-v6-pricing → user-auth-flow`. Direct inconsistency in "exact replacements for consistency."

**Reference:** Canonical Genericization Table vs Phase 5a

---

## MINOR

### R3. Script runtime deps unaddressed
cp -p preserves executable bits but doesn't check shebangs, line endings, shell strict-mode, or runtime deps (python packages, gh, jq, curl).

**Reference:** Phase 1c, Phase 7a

### O2. Phase 7f mixes fork correctness with v1.0.0 QA
Different objectives in same checklist = checklist sprawl, attention dilution.

**Reference:** Phase 7f

### M4. No regression plan for renamed output filenames
Users with downstream tooling expecting `kieran-typescript.md` will break. Currently unplanned.

**Reference:** Phase 5a
