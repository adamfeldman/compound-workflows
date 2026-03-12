---
title: "fix: Write tool discipline — replace heredoc/echo/commit patterns in LLM-interpreted files"
type: fix
status: active
date: 2026-03-12
bead: dj65
---

# Write Tool Discipline — Replace Shell Patterns in LLM-Interpreted Files

## Problem

LLM-interpreted `.md` files in the compound-workflows plugin contain shell patterns that trigger Claude Code permission prompts:

- **Heredoc (`<< 'EOF'`)** — hard heuristic, fires even with matching `Bash(cat:*)` static rules
- **Echo redirect (`echo >> file`)** — triggers permission prompts in compound command contexts
- **Unspecified commit methods** — models default to `git commit -m "$(cat <<'EOF'...)"` which triggers heredoc/`$()` heuristics

These prompts interrupt every invocation of the affected skills. The `<<` heredoc is empirically confirmed as a "hard" heuristic that no static rule can suppress (see `docs/solutions/claude-code-internals/2026-03-10-static-rules-suppress-bash-heuristics.md`).

## Scope

Full re-audit of `plugins/compound-workflows/` for all three pattern classes in LLM-interpreted `.md` files. Plus:
- New QA script (`write-tool-discipline.sh`) to prevent recurrence
- Expand `skills/*/workflows/*.md` scan scope across **all** existing Tier 1 QA scripts (blind spot discovered during audit)
- One atomic commit

### Out of Scope

- `.sh` scripts — shell files legitimately use heredocs and redirects
- `skills/*/references/*.md` — reference material, not model-executed
- `skills/*/assets/*.md` and `skills/*/templates/*.md` — content/data templates, not executable instructions (follow-up if violations found)
- `resources/*.md` — contains shell pattern examples (e.g., bash-generation-rules.md) but these are reference material injected into CLAUDE.md, not directly executed by skills. Not in scan scope.
- Docs, README, CHANGELOG content (not executed)

## Violation Inventory

Full re-audit results. Lines should be verified against current code at implementation time.

### Heredoc Patterns (CRITICAL — guaranteed permission prompt)

| # | File | Line(s) | Pattern | Fix |
|---|------|---------|---------|-----|
| 1 | `skills/compound-docs/SKILL.md` | ~223 | `cat >> docs/solutions/patterns/common-solutions.md << 'EOF'` | Write/Edit tool with two-step existence check |
| 2 | `skills/create-agent-skills/workflows/create-new-skill.md` | ~159 | `cat > ~/.claude/commands/{skill-name}.md << 'EOF'` | Write tool with literal `$ARGUMENTS` preserved |

### Echo Redirect Patterns (HIGH — reliable permission prompt trigger)

| # | File | Line(s) | Pattern | Fix |
|---|------|---------|---------|-----|
| 3 | `skills/do-setup/SKILL.md` | ~321 | `echo 'compound-workflows.local.md' >> .gitignore` | Read .gitignore, check if present, Edit tool to append if missing |
| 4 | `skills/do-setup/SKILL.md` | ~662-663 | `echo 'stats_capture: true' >> compound-workflows.local.md` (×2, inside if block) | Script delegation: `migrate-stats-keys.sh` |
| 5 | `skills/compound-docs/SKILL.md` | ~211 | `echo "- See also: [$FILENAME]($REAL_FILE)" >> [similar-doc.md]` | Edit tool to append cross-reference line |
| 6 | `skills/setup/SKILL.md` | ~158-159 | `echo 'stats_capture: true' >> compound-workflows.local.md` (×2, inside if block) | Script delegation: same `migrate-stats-keys.sh` |

**Note on #6:** `setup/SKILL.md` has `disable-model-invocation: true` (reference skill, not directly executed). Fix anyway: (a) QA script will flag it, (b) it was the fork source for `do-setup`, (c) prevents re-activation surprises.

### Unspecified Commit Method Patterns (HIGH — models generate heredoc/`$()` spontaneously)

| # | File | Line(s) | Pattern | Fix |
|---|------|---------|---------|-----|
| 7 | `skills/do-compact-prep/SKILL.md` | ~46 | `**Yes** — commit (ask for message or suggest one)` | Expand with Write tool + `git commit -F` pattern, preserve collaborative UX |
| 8 | `skills/do-compact-prep/SKILL.md` | ~74 | `**Yes** — commit` | Same expansion |
| 9 | `skills/do-work/SKILL.md` | ~L279 (subagent template) | `Stage and commit your changes with the commit message suggested in the task description` | Expand with Write tool + `git commit -F` pattern (confirmed underspecified — subagent context has same heuristic constraints) |
| 10 | `skills/resolve-pr-parallel/SKILL.md` | ~119 | `Commit changes with a clear message referencing the PR feedback` | Expand instruction with Write tool + `git commit -F` pattern |

**Note on resolve-pr-parallel line ~154:** This is a success criterion ("Changes committed and pushed"), not an instruction. Leave as-is — success criteria describe end state, not method.

**Note on #9 (do-work):** The bead flagged this but the re-audit didn't. Verify current code — may have been fixed in a prior session. If already specifying `git commit -F`, mark as no-op.

## Implementation Steps

### Step 1: Create `migrate-stats-keys.sh`

Create `plugins/compound-workflows/scripts/migrate-stats-keys.sh` following the `append-snapshot.sh` pattern.

**Inputs:** None. Path hardcoded as `compound-workflows.local.md` relative to CWD (consistent with Step 2 callsites which pass no arguments).

**Logic:**
1. Check if file exists; if not, exit 0 (nothing to migrate)
2. Check if `stats_capture` key is present; if yes, exit 0 (already migrated)
3. Append `stats_capture: true` and `stats_classify: true` to the file
4. Echo `STATS_KEYS_ADDED=true` to stdout (preserves status output for downstream logic)

**Why script delegation:** The `if/echo/fi` block contains conditional logic, file appends, and stdout status output. Moving to a script keeps all heuristic-triggering patterns out of the Bash tool input. Consistent with `append-snapshot.sh` and `capture-stats.sh` precedent.

- [ ] Create `plugins/compound-workflows/scripts/migrate-stats-keys.sh`
- [ ] Make executable (`chmod +x`)

### Step 2: Fix All Violations (10 sites)

Apply fixes in any order (independent sites in different files/sections). For each fix, verify behavioral equivalence with the original pattern.

**Heredoc fixes:**

- [ ] **#1 compound-docs/SKILL.md ~L223:** Replace `cat >> file << 'EOF'` block with two-step logic: "If `docs/solutions/patterns/common-solutions.md` exists, use the Edit tool to append the pattern block. If it does not exist, use the Write tool to create it." Preserve the template content verbatim (placeholder brackets, heading levels, blank lines).
- [ ] **#2 create-agent-skills/workflows/create-new-skill.md ~L159:** Replace `cat > file << 'EOF'` with: "Use the Write tool to create `~/.claude/commands/{skill-name}.md` with the following content (note: `$ARGUMENTS` is a Claude Code variable — include it literally, do not expand):" followed by the same content block.

**Echo redirect fixes:**

- [ ] **#3 do-setup/SKILL.md ~L321:** Replace `echo '...' >> .gitignore` with: "Read `.gitignore` (if it exists). If `compound-workflows.local.md` is not already listed, use the Edit tool to append `compound-workflows.local.md` as a new line."
- [ ] **#4 do-setup/SKILL.md ~L662-663:** Replace the entire `if/echo/fi` bash block with: `bash ${CLAUDE_SKILL_DIR}/../../scripts/migrate-stats-keys.sh`. Read the stdout for `STATS_KEYS_ADDED=true` status. (Use SKILL_DIR-relative path per plugin convention.)
- [ ] **#5 compound-docs/SKILL.md ~L211:** Replace `echo "- See also: ..." >> file` with: "Use the Edit tool to append `- See also: [$FILENAME]($REAL_FILE)` to the target document."
- [ ] **#6 setup/SKILL.md ~L158-159:** Replace the `if/echo/fi` bash block with same `migrate-stats-keys.sh` call as #4 (using `${CLAUDE_SKILL_DIR}/../../scripts/migrate-stats-keys.sh`).

**Unspecified commit method fixes:**

- [ ] **#7 do-compact-prep/SKILL.md ~L46:** Expand "commit (ask for message or suggest one)" to: "Ask the user for a commit message or suggest one. Use the Write tool to write the agreed message to `.workflows/scratch/commit-msg-<RUN_ID>.txt`, then run `git commit -F .workflows/scratch/commit-msg-<RUN_ID>.txt`."
- [ ] **#8 do-compact-prep/SKILL.md ~L74:** Same expansion as #7.
- [ ] **#9 do-work/SKILL.md ~L279 (subagent template):** Expand "Stage and commit your changes with the commit message suggested in the task description" with Write tool + `git commit -F` pattern. Use unique filename: `.workflows/scratch/commit-msg-<TASK_ID>.txt` (subagents have task IDs, not RUN_IDs). This is inside a Task subagent dispatch template. **Assumption:** subagents operate in their own Bash tool context with the same heuristic constraints as the orchestrator — this is assumed based on orchestrator behavior but has not been empirically verified for subagent contexts. Fix is good practice regardless. Note: the Phase 4 orchestrator commit (~L415) is already properly specified.
- [ ] **Pre-implementation verification for #9:** Before fixing, empirically test whether a Task subagent inherits static allow rules from `.claude/settings.json`. If `Bash(git:*)` is inherited, the subagent's `git commit -m` would auto-approve (making the fix good practice but not strictly necessary). If NOT inherited, the fix is critical. Document the result.
- [ ] **#10 resolve-pr-parallel/SKILL.md ~L119:** Expand "Commit changes with a clear message" to include Write tool + `git commit -F` method.

### Step 3: Create `write-tool-discipline.sh` QA Script

Create `plugins/compound-workflows/scripts/plugin-qa/write-tool-discipline.sh` following the `no-shell-atomicity.sh` structural pattern.

**Detection patterns:**

| Pattern | Regex | What it catches |
|---------|-------|-----------------|
| Heredoc | `<<-?\s*['"]?[A-Za-z_]+['"]?` | `<< 'EOF'`, `<< YAML_EOF`, `<<EOF`, `<<-EOF`, `<< eof` (case-insensitive, includes indent-stripping form) |
| Echo redirect | `echo\s+.*>>` | `echo '...' >> file`, `echo "..." >> file` |
| Inline commit flag | `git commit\s+.*-m\s` | `git commit -m "..."` (not `-F`) |

**Limitation (documented in script header):** The `git commit -m` regex catches explicit inline flags but NOT underspecified prose like "commit your changes." Prose patterns are a Tier 2 (semantic review) concern — accept this limitation per specflow Q6 analysis.

**Scan scope:**
```
commands/compound/*.md
skills/*/SKILL.md
skills/*/workflows/*.md    # NEW — covers create-new-skill.md
agents/**/*.md              # excluding */references/*
```

**Exemption markers:** Recognize both `write-tool-exempt` (primary) and `heuristic-exempt` (inherited from broader heuristic category). Consistent with existing per-script markers.

**Script structure:**
```bash
source lib.sh
resolve_plugin_root "${1:-}"
init_findings
# Collect scan_files array (commands, skills, skill workflows, agents minus references)
# Pattern 1: heredoc
# Pattern 2: echo redirect
# Pattern 3: git commit -m
emit_output "Write Tool Discipline Check"
```

**Self-detection note:** Script contains detection patterns as regex strings. Not a live risk since `scripts/` is not in scan scope. Document in header comment.

- [ ] Create `write-tool-discipline.sh`
- [ ] Make executable
- [ ] Verify it returns 0 findings on fixed codebase

### Step 4: Expand Scan Scope in All Tier 1 QA Scripts

Add `skills/*/workflows/*.md` to the scan scope of all existing Tier 1 scripts that scan LLM-interpreted `.md` files. Currently, 10 workflow files exist in `skills/create-agent-skills/workflows/` — these are LLM-interpreted but invisible to Tier 1 QA.

Scripts to update (verify each has a scan file collection step):

- [ ] `context-lean-grep.sh` — has the narrowest scope (only `do-*/SKILL.md`), most critical to expand
- [ ] `no-shell-atomicity.sh`
- [ ] `unslugged-paths.sh`
- [ ] `truncation-check.sh` — requires workflow-specific thresholds (see sub-step below)

**Note:** `stale-references.sh` already uses recursive `grep -rnE --include="*.md"` across `$PLUGIN_ROOT/skills` — it already covers `skills/*/workflows/*.md`. No expansion needed.

**Sub-step: Add workflow file type to truncation-check.sh.** Workflow files differ from SKILL.md files: they may lack YAML frontmatter and range from 70-600+ lines. Define workflow-specific rules:
- No frontmatter requirement (or optional)
- Higher minimum line threshold (e.g., 20-50 lines — calibrate against current workflow file sizes)
- Appropriate max-line cap if applicable
- [ ] Read current workflow file sizes to calibrate thresholds
- [ ] Add `workflow` file type rules to truncation-check.sh
- [ ] Verify expanded truncation-check passes on all existing workflow files

Scripts that do NOT need the expansion:
- `version-sync.sh` — checks version strings in plugin.json/marketplace.json/CHANGELOG.md, does not scan .md content. **Skip.**
- `capture-stats-format.sh` — tests capture-stats.sh with mock input, does not scan .md content. **Skip.**

Scripts to verify at implementation time:
- `file-counts.sh` — counts files by type. If it counts workflow `.md` files, add the glob; if it only counts SKILL.md files, skip. **Verify and decide.**

For each script, add the glob pattern to the scan file collection step. Run each script individually after modification to confirm no new findings from the expanded scope (or fix any legitimate findings discovered).

- [ ] Verify which scripts need expansion
- [ ] Add `skills/*/workflows/*.md` glob to each
- [ ] Run each modified script to check for new findings
- [ ] Fix any legitimate new findings (scope expansion may surface violations beyond write-tool patterns)

### Step 5: Update Plugin Infrastructure

- [ ] Verify `write-tool-discipline.sh` is discovered by plugin-changes-qa (check if it auto-discovers `scripts/plugin-qa/*.sh` or has a static list — register only if static)
- [ ] Verify `file-counts.sh` expectations — check if it tracks QA script counts; update only if it does
- [ ] Update CLAUDE.md Tier 1 scripts table (add write-tool-discipline.sh row)
- [ ] Update AGENTS.md Tier 1 scripts table (if it lists QA scripts)
- [ ] Verify README.md component counts still accurate
- [ ] Update plugin.json + marketplace.json version (PATCH bump)
- [ ] Update CHANGELOG.md

### Step 6: Run Full QA

- [ ] Run `/compound-workflows:plugin-changes-qa` (both Tier 1 + Tier 2)
- [ ] Fix any findings
- [ ] Commit atomically: all fixes + new script + scope expansion + infrastructure updates

## Acceptance Criteria

- [ ] No `<< 'EOF'` or `<< 'YAML_EOF'` heredoc patterns in LLM-interpreted .md files (commands, skills, skill workflows, agents minus references)
- [ ] No `echo >>` file modification patterns in LLM-interpreted .md files
- [ ] All commit instructions in skills specify Write tool + `git commit -F` method
- [ ] `write-tool-discipline.sh` exists and returns 0 findings
- [ ] All applicable Tier 1 QA scripts scan `skills/*/workflows/*.md` (except stale-references.sh which already recurses)
- [ ] All existing QA scripts pass (including expanded scope)
- [ ] `migrate-stats-keys.sh` exists and preserves conditional + status output behavior

## Design Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Conditional echo blocks (2b, 2d) | Script delegation (`migrate-stats-keys.sh`) | Consistent with append-snapshot.sh precedent; keeps all heuristic-triggering patterns in .sh files where inspector doesn't see them; cleaner than hybrid bash+tool-instructions |
| Scan scope expansion | All applicable Tier 1 scripts | Eliminates blind spot now rather than deferring (overrides specflow recommendation to create follow-up bead); `stale-references.sh` already recurses (skip); `context-lean-grep.sh` added (narrowest scope); `truncation-check.sh` needs workflow-specific thresholds |
| Commit message file paths | Unique slugged paths (`<RUN_ID>` or `<TASK_ID>`) | Avoids unslugged-path policy violations and prevents overwrite collisions in parallel subagent contexts [red-team--gemini, red-team--openai] |
| migrate-stats-keys.sh invocation | `${CLAUDE_SKILL_DIR}/../../scripts/` (SKILL_DIR-relative) | Consistent with all other script references in skill files; avoids CWD-dependent silent failure [red-team--opus] |
| Heredoc regex | Case-insensitive, includes `<<-` form | Catches lowercase, mixed-case, and indent-stripping heredoc variants [red-team--openai, red-team--opus] |
| Subagent heuristic assumption | Assumed same as orchestrator; verify empirically before fix #9 | Fix is good practice regardless, but verification determines criticality [red-team--opus] |
| QA exemption markers | `write-tool-exempt` + `heuristic-exempt` | Each script has domain-specific marker; also recognize parent category marker for consistency |
| `git commit -m` detection limitation | Accept — Tier 1 catches explicit flags; prose is Tier 2 | Broad prose detection is too false-positive-prone for a deterministic script |
| setup/SKILL.md (disabled reference skill) | Fix anyway | QA script flags it; fork source for do-setup; prevents re-activation surprises |
| compact-prep commit UX | Preserve collaborative "ask or suggest" + specify method | Keeps the user-friendly interaction while preventing permission prompts |
| One atomic commit | Yes | All changes are interdependent (fixes + QA script that validates them + infrastructure that registers the script) |

## Open Questions

1. **file-counts.sh scope:** Does `file-counts.sh` count workflow `.md` files? If yes, add the `skills/*/workflows/*.md` glob. If it only counts `SKILL.md` files, skip. Verify at implementation time. [red-team--openai, red-team--opus, see .workflows/plan-research/write-tool-discipline/red-team--openai.md]

## Sources

- **Research files:** `.workflows/plan-research/write-tool-discipline/agents/` (repo-research.md, learnings.md, specflow.md)
- **Institutional knowledge:** `docs/solutions/claude-code-internals/2026-03-10-static-rules-suppress-bash-heuristics.md` (heredoc hard heuristic proof)
- **Institutional knowledge:** `docs/solutions/claude-code-internals/2026-03-11-script-file-shell-substitution-bypass.md` (script delegation pattern)
- **Prior fixes:** Bead ywug (v2.5.1/v2.6.1 compact-prep heredoc → append-snapshot.sh), Bead 3l7 (v2.5.0 $() elimination)
- **QA pattern:** `plugins/compound-workflows/scripts/plugin-qa/no-shell-atomicity.sh` (structural template for new script)
