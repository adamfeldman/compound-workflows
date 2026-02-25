# Deepen-Plan Synthesis: Run 1

**Date:** 2026-02-25
**Run:** 1
**Agents:** 9 (6 research, 3 review)
**Plan:** `docs/plans/2026-02-25-feat-fork-compound-engineering-agents-skills-plan.md`

---

## Agent Roster

| Agent | Type | Key Focus | Relevant Findings |
|-------|------|-----------|-------------------|
| research--command-analysis | Research | Per-command cross-reference of agents, skills, examples | 3 gaps found |
| research--genericization-audit | Research | Verify all 12 replacement patterns against source | 1 minor finding (hardcoded year) |
| research--orchestrating-swarms-audit | Research | Per-instance audit of 1580-line orchestrating-swarms | 26 references mapped (20 namespace, 3 rename, 3 removal) |
| research--setup-skill-audit | Research | Setup skill reference mapping + command/skill schema conflict | 1 critical finding (schema merge) |
| research--source-verification | Research | Verify all 91 source files exist with correct counts | All verified; off-by-one counting methodology noted |
| research--version-diff | Research | Compare source across versions 2.31.1 vs 2.35.2 | No drift; setup skill is only new file |
| review--architecture-strategist | Review | Architecture, coupling, commit strategy, discovery logic | 6 serious risks, 2 medium risks |
| review--code-simplicity-reviewer | Review | Overengineering, YAGNI, unnecessary complexity | 7 simplification recommendations |
| review--security-sentinel | Review | Licensing, scripts, credentials, supply chain | 2 HIGH, 3 MEDIUM, 3 LOW findings |

---

## Top Findings by Severity

### Critical / HIGH

1. **NOTICE file lacks full MIT license text** (security-sentinel) -- MIT requires "this permission notice shall be included," not just a summary attribution. The plan's NOTICE content does not include the full MIT permission text. Must be fixed before Phase 1.

2. **No security review of executable scripts before redistribution** (security-sentinel) -- 11 executable scripts across 6 skills (gemini-imagegen, git-worktree, skill-creator, resolve-pr-parallel, create-agent-skills) are copied as "zero-change" with no content review. These run with user shell permissions. Gemini-imagegen includes requirements.txt with supply chain risk.

3. **Setup command/skill write different schemas to same config file** (research--setup-skill-audit) -- The existing setup.md command writes {tracker, red_team, review_agents, gh_cli} while the setup SKILL.md writes {review_agents, plan_review_agents, project_context, depth}. Phase 5c says command "loads skill for knowledge" but does not specify merged schema format. Implementer has no guidance on unifying these.

4. **No structured upstream sync mechanism** (review--architecture-strategist) -- Plan promises "regular upstream merge" but defines no FORK-MANIFEST, no version tracking per file, no modification status tracking. Without this, future syncs are ad-hoc and error-prone.

### Serious / MEDIUM

5. **Deepen-plan discovery filter replacement underspecified** (research--command-analysis, review--architecture-strategist) -- Phase 5b says "replace with generic filter" but does not specify the exact replacement logic. The generic filter also risks sweeping in agents from other plugins (architecture-strategist).

6. **Phase 7b grep sweep misses script file types** (security-sentinel) -- The primary `compound-engineering` reference check uses `--include="*.md" --include="*.yaml" --include="*.json"`, missing .sh, .py, and extensionless scripts.

7. **No credential pattern scan** (security-sentinel) -- Phase 7b checks company-specific terms but not API keys, tokens, secrets (sk-, ghp_, api_key patterns).

8. **No copyright header preservation check for modified files** (security-sentinel) -- cp -p preserves zero-change files, but Phase 2-3 modifications could inadvertently alter copyright headers.

9. **Rails path simplification not addressed** (research--setup-skill-audit) -- Since Rails agents are dropped, the setup skill's Rails-specific stack path needs to become a simpler general path, not just have agent names deleted.

10. **Supply chain risk from ongoing fork divergence** (security-sentinel) -- No fork base version recorded in machine-readable format, no sync cadence defined, no mechanism to detect upstream security patches.

### Low / Minor

11. **NOTICE file appears in both Phase 1d and Phase 6a** (review--architecture-strategist, review--code-simplicity-reviewer) -- Forward reference creates confusion about when NOTICE is created.

12. **Hardcoded year in git-history-analyzer.md** (research--genericization-audit) -- Line 22: "The current year is 2026" matches the Phase 7f check pattern.

13. **review.md output file path should be definitive** (research--command-analysis) -- Plan says "kieran-typescript.md -> typescript.md (if referenced)" with uncertain phrasing. Should be definitive.

14. **Off-by-one line counts in source inventory** (research--source-verification) -- Source inventory counts are consistently 1 higher than wc -l. Counting methodology difference, not content issue.

15. **No systematic scan for relative path references** (security-sentinel) -- Only one `../../` reference identified (learnings-researcher.md). No grep for other relative paths across 91 files.

16. **compound-docs skill name may confuse** (review--architecture-strategist) -- "compound" in the name collides with the plugin namespace "compound-workflows."

---

## Contradictions Between Agents

### 1. Setup command/skill split: Keep vs. Eliminate

- **architecture-strategist**: "JUSTIFIED but NOVEL" -- the split follows Separation of Concerns. Recommends documenting the pattern in CLAUDE.md.
- **code-simplicity-reviewer**: "YAGNI violation" -- the split is premature. Recommends folding the skill into the command and shipping one artifact.
- **Resolution**: These are architectural philosophy differences, not factual contradictions. The plan should acknowledge both views and make an explicit decision. The setup-skill-audit's finding (schema merge gap) adds weight to the simplicity argument -- if the schema merge is complex enough to warrant specification, maybe a single artifact is simpler.

### 2. Genericization scope: Full table vs. Half table

- **Plan + 5 research agents**: Full 12-pattern genericization table is comprehensive and all terms are confirmed in source.
- **code-simplicity-reviewer**: Cut to ~6 patterns (personas + real company/repo names only). Example names like "BriefSystem" and "cash-management" are arbitrary and replacing them provides zero functional improvement.
- **Resolution**: Factual disagreement on whether example names are worth genericizing. The brainstorm's red team previously decided to genericize all company-specific content. The simplicity argument is valid but contradicts an already-ratified decision.

### 3. Phase 7 verification scope: Comprehensive vs. Proportionate

- **Plan + research agents**: 30+ verification checks across 7 sub-phases.
- **code-simplicity-reviewer**: "Verification theater" -- collapse to ~8 meaningful checks. Remove Phase 7e (redundant with diff) and Phase 7f (scope creep from v1.0.0 QA).
- **Resolution**: Both have merit. The plan is for a ~96-file fork where individual check cost is low. But the simplicity reviewer is right that Phase 7e is redundant if Phase 1e's byte-identical diff passes.

### 4. Commit count: 5 vs. 4

- **architecture-strategist**: 5 commits well-scoped; considers splitting Commit 2 into LOW and MEDIUM.
- **code-simplicity-reviewer**: Collapse to 4 by merging Commit 3 (2 files) into Commit 2.
- **Resolution**: Opposite directions. Architecture-strategist wants more granularity (6 commits), simplicity reviewer wants less (4). The plan's current 5 is a reasonable middle ground.

---

## Sections With Most Feedback

| Plan Section | Agents Contributing | Finding Count |
|-------------|-------------------|---------------|
| Phase 5b (deepen-plan discovery) | command-analysis, architecture-strategist | 3 findings |
| Phase 5c (setup command rewrite) | setup-skill-audit, architecture-strategist, code-simplicity-reviewer | 4 findings |
| Phase 4a (setup skill) | setup-skill-audit, architecture-strategist, code-simplicity-reviewer | 3 findings |
| Phase 7b (grep sweep) | security-sentinel | 3 findings |
| Phase 6a (NOTICE file) | security-sentinel, architecture-strategist, code-simplicity-reviewer | 3 findings |
| Phase 4b (orchestrating-swarms) | orchestrating-swarms-audit | Detailed 26-item manifest (confirming plan, no gaps) |
| Commit Strategy | architecture-strategist, code-simplicity-reviewer | 2 contradictory recommendations |

## Agents With Nothing New

- **research--version-diff**: Confirmed no version drift across compound-engineering versions. Useful validation but no new findings requiring plan changes.
- **research--source-verification**: Confirmed all 91 source files exist. Only finding was off-by-one line counting methodology.

Both provided valuable confirmation that the plan's assumptions are correct, even if they did not surface new issues.

---

## Summary Statistics

- **Total unique findings**: 16
- **Critical/HIGH**: 4
- **Serious/MEDIUM**: 6
- **Low/Minor**: 6
- **Contradictions**: 4 (all philosophy-level, no factual contradictions)
- **Plan sections with zero findings**: Phase 1 (copy), Phase 2 (LOW edits), Phase 3 (MEDIUM edits except NOTICE overlap), Phase 6b-6e (docs/config)
