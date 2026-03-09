---
title: Plugin Version Visibility and Release Process
date: 2026-03-09
status: active
---

# Plugin Version Visibility and Release Process

## What We're Building

Five complementary pieces to answer "am I stale?" and prevent forgotten releases:

### 1. Version Check Script (`scripts/plugin-qa/version-check.sh`)

Bash script that performs a 3-way version comparison:

- **Source version**: Read from `plugins/compound-workflows/.claude-plugin/plugin.json` in the working repo
- **Installed version**: Read from the marketplace clone's `plugin.json` at `~/.claude/plugins/marketplaces/compound-workflows-marketplace/plugins/compound-workflows/.claude-plugin/plugin.json`. This is the git clone that Claude Code loads the plugin from — when it's stale, the plugin is stale. (Investigated: confirmed this clone IS what Claude Code uses for local-path source plugins.)
- **Latest release**: Query latest GitHub release via `gh release list --json tagName,isLatest --jq '.[] | select(.isLatest) | .tagName'` (NOT `--limit 1`, which returns most recently created, not highest semver). Gracefully degrade to "unknown" if `gh` is unavailable or offline.

Output: always show all 3 versions with status and actionable advice for every issue found:

```
Source:     1.10.0
Installed:  1.9.1  ← STALE (loaded plugin is behind source)
Release:    v1.10.0

Actions needed:
  → Plugin is stale. Run: claude plugin update compound-workflows@compound-workflows-marketplace
```

```
Source:     1.11.0
Installed:  1.11.0
Release:    v1.10.0  ← UNRELEASED (source version has no matching release)

Actions needed:
  → Version 1.11.0 has no GitHub release. Run: git tag v1.11.0 && git push origin v1.11.0 && gh release create v1.11.0
```

```
Source:     1.10.0
Installed:  1.10.0
Release:    v1.10.0

All versions match. No action needed.
```

```
Source:     1.10.0
Installed:  1.9.1  ← STALE
Release:    v1.9.1  ← UNRELEASED (1.10.0 not released)

Actions needed:
  → Plugin is stale. Run: claude plugin update compound-workflows@compound-workflows-marketplace
  → Version 1.10.0 has no GitHub release. Run: git tag v1.10.0 && git push origin v1.10.0 && gh release create v1.10.0
```

Key principle: **always show impact and actionable fix**. Never just flag a problem — tell the user exactly what to run.

Edge case: if Installed > Release (committed but not released), label as `UNRELEASED` instead of `STALE`.

Version normalization: strip leading `v` before comparison (`v1.10.0` → `1.10.0`). All comparisons use bare semver.

Scope: this covers the single-maintainer workflow. Multi-user version visibility (notifying downstream plugin users of available updates) is out of scope.

### 2. Version Skill (`skills/version/SKILL.md`)

User-invocable as `/compound-workflows:version`. Convenience wrapper — runs `version-check.sh` and presents results. The script is the real tool; the skill is for discoverability when the user actively wonders "am I current?"

Note: this skill does NOT solve invisible staleness (if you don't know you're stale, you won't run it). That's handled by proactive checks in compact-prep and setup (see #3).

### 3. Proactive Version Checks (compact-prep + setup)

Integrate `version-check.sh` into:
- **compact-prep** (already has Step 6 release check — extend to also show installed vs source staleness)
- **setup** (runs early in new projects — good place to warn about stale plugins)

This solves the bootstrap problem: even if the skill is stale, compact-prep and setup will catch it because the bash script lives in the working repo, not in the loaded plugin.

### 4. Version-Sync QA Script (`scripts/plugin-qa/version-sync.sh`)

**New dedicated script** (not in file-counts.sh — all 3 red team models flagged the single-responsibility violation). Checks:
- `plugin.json` version == `marketplace.json` plugin version
- CHANGELOG.md has an entry matching the current plugin.json version

This runs on every QA invocation (Tier 1) and via the PostToolUse hook after commits.

### 5. Post-Merge Reminder (work.md Phase 4)

Add a note after PR creation in work.md Phase 4 (Ship): "After merge, run `/compound-workflows:version` or `/compound:compact-prep` to check for missing releases." Lightweight — doesn't automate releases, just reminds.

### 6. Doc Alignment (CLAUDE.md + AGENTS.md)

Align version checklists so both reference the complete 4-file set:
- `.claude-plugin/plugin.json` — bump version
- `.claude-plugin/marketplace.json` — bump version (repo root)
- `CHANGELOG.md` — document changes
- `README.md` — verify component counts and tables

CLAUDE.md already mentions marketplace.json on line 17 ("Also update the marketplace.json version at the repo root") but buries it as a separate sentence after the numbered list. AGENTS.md omits README.md. Align both to list all 4 explicitly in their numbered lists.

Also fix AGENTS.md line 82: "Bump version + ref in marketplace.json" — there is no `ref` field in marketplace.json. Remove the `ref` reference.

## Why This Approach

**Problem**: v1.10.0 was merged and pushed but no GitHub release was created. `claude plugin update` didn't pick up the changes. The user couldn't tell the plugin was stale until things didn't work as expected. compact-prep Step 6 (release check) existed but wasn't running because the *loaded plugin itself* was stale and didn't have that step.

**Root cause (refined after red team)**: Two layers:
1. **Why was the release forgotten?** The safety net (compact-prep Step 6) requires the safety net to already be working — chicken-and-egg. When the loaded plugin was stale, Step 6 didn't exist.
2. **Why was the plugin stale?** `claude plugin update` requires the marketplace clone to be current. The causal relationship between missing GitHub releases and the update failure needs further investigation — it may be that `git pull` alone would have worked regardless of releases.

The proposed solution addresses both visibility (can check staleness) and prevention (proactive checks in compact-prep/setup that work even with stale plugins, since the script lives in the working repo).

**Design rationale**:
- **Bash script as foundation** — reusable from skill, hooks, compact-prep, setup, and CLI. Not locked into the LLM context.
- **Skill as convenience layer** — `/compound-workflows:version` for ad-hoc "am I current?" checks. Not the primary defense against invisible staleness.
- **Proactive checks** — compact-prep and setup run the script automatically, solving the discoverability problem that a manual skill cannot.
- **Separate QA script** — version-sync.sh is its own concern, not shoehorned into file-counts.sh.
- **Doc alignment** — prevents the "which checklist do I follow?" confusion. Fix the AGENTS.md `ref` field error while we're at it.

## Key Decisions

1. **work.md should NOT do releases** — it's a general-purpose plugin. Release creation is the developer's decision, not an automated step. compact-prep Step 6 is the appropriate safety net. (User rationale: "i dont want work to do releases automatically, thats not appropriate for a general purpose plugin.")

2. **3-way comparison** — user wants to see source vs installed vs release, not just one comparison. Full picture of where things stand. "Installed" = marketplace clone state (confirmed via investigation).

3. **Both script and skill** — bash script is reusable from hooks/QA/compact-prep/setup; skill wraps it for user-facing UX. User chose "both" over either alone.

4. **Version-sync in its own script** — red team unanimously flagged file-counts.sh as wrong home. Separate `version-sync.sh` script. (Changed from original decision based on red team feedback.)

5. **Align both doc checklists** — CLAUDE.md and AGENTS.md serve complementary purposes (dev checklist vs release process) but both should reference the complete 4-file list. Fix AGENTS.md `ref` field error.

6. **Proactive checks in compact-prep + setup** — solves the bootstrap/discoverability problem that a manual skill cannot. The bash script lives in the working repo, so it works even when the loaded plugin is stale.

## Resolved Questions

**Q: How does `claude plugin update` work with local-path source?**
A: The marketplace cache at `~/.claude/plugins/marketplaces/<name>/` is a git clone. `claude plugin update` pulls latest from remote. The local path source (`"./plugins/compound-workflows"`) resolves within the clone. GitHub releases/tags are for versioning hygiene and visibility — the causal relationship to `claude plugin update` success needs further investigation.

**Q: Is compact-prep Step 6 sufficient as the only release gate?**
A: It's the right *place* for the check, but it failed because the loaded plugin was stale (didn't have Step 6). Proactive version checks from the working repo's script solve the bootstrap problem. The version skill is a convenience, not the safety net.

**Q: Is the "installed version" concept meaningful?**
A: Yes — investigated and confirmed. The marketplace clone at `~/.claude/plugins/marketplaces/compound-workflows-marketplace/` is a full git clone. Its `plugin.json` version reflects what Claude Code loads. When the clone is stale (hasn't been pulled), the version there is older than the source. This IS the staleness the user wants to detect.

**Q: Does CLAUDE.md already mention marketplace.json?**
A: Yes — line 17 says "Also update the marketplace.json version at the repo root." The brainstorm initially stated CLAUDE.md "omits" marketplace.json, which was factually wrong (caught by OpenAI red team). The real issue is that marketplace.json is buried as a separate sentence after the numbered list rather than included in the list itself.

## Red Team Resolution Summary

| Finding | Provider(s) | Resolution |
|---------|-------------|------------|
| Manual skill doesn't solve invisible staleness | Gemini, Opus, OpenAI | **Valid** — added proactive checks in compact-prep + setup |
| "Installed version" read mechanism unvalidated | Opus | **Investigated** — marketplace clone IS what Claude Code loads. 3-way comparison is valid with clear labels |
| Version-sync in file-counts.sh violates SRP | Opus, Gemini, OpenAI | **Valid** — changed to separate version-sync.sh |
| `gh release list --limit 1` is fragile | OpenAI | **Valid** — use `--json` with `isLatest` filter |
| AGENTS.md references nonexistent `ref` field | Opus | **Valid** — fix during doc alignment |
| No `gh` CLI fallback | Gemini, OpenAI | **Valid** — graceful degradation to "unknown" |
| CLAUDE.md factual claim wrong in brainstorm | OpenAI | **Valid** — corrected. CLAUDE.md does mention marketplace.json, just not in the numbered list |
| Root cause is symptoms not cause | Opus, OpenAI | **Valid** — refined root cause analysis to two layers |
| Skill adds context overhead | Opus | **Disagree** — context cost is trivial (~5 lines of script output). Context-lean principle targets heavy multi-page agent returns, not lightweight script wrappers |
| Version normalization needed | OpenAI | **Fixed** — added normalization rule (strip leading `v`) |
| Single-user scope not documented | Opus | **Fixed** — added scope note |
| Staleness window unaddressed | Opus | **Valid** — add post-merge reminder in work.md Phase 4 |
| marketplace.json version may be display-only | Opus | **Acknowledged** — still worth checking. Cosmetic drift causes confusion even if not functional |
| CI/pre-push gate as alternative | OpenAI | **Acknowledged** — no CI in this project. compact-prep + setup proactive checks serve the same purpose |
| SHA comparison as alternative to version | OpenAI | **Acknowledged** — version comparison is sufficient for current needs. SHA comparison adds complexity without clear benefit |

## Sources

- Research: `.workflows/brainstorm-research/plugin-version-visibility/`
- Red team: `.workflows/brainstorm-research/plugin-version-visibility/red-team--{gemini,openai,opus}.md`
- compact-prep Step 6: `plugins/compound-workflows/commands/compound/compact-prep.md` (lines 78-91)
- CLAUDE.md versioning: `plugins/compound-workflows/CLAUDE.md` (lines 1-18)
- AGENTS.md release process: `AGENTS.md` (lines 64-88)
- Solution doc (marketplace behavior): `docs/solutions/plugin-infrastructure/2026-03-08-command-registration-limit-workaround.md`
