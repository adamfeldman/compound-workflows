---
title: Claude Code Per-Directory Command Registration Limit
date: 2026-03-08
category: plugin-infrastructure
tags: [plugin-system, commands, skills, registration, silent-failure, platform-limits]
severity: high
status: resolved
origin_plan: docs/plans/2026-03-08-feat-context-lean-enforcement-plan.md
related_solution: docs/solutions/qa-infrastructure/2026-03-08-bash-qa-script-patterns.md
commits: [bea15c5, 03ac41f, 18e5f81, 50a345b]
github_issues: ["anthropics/claude-code#20415", "anthropics/claude-code#13343", "anthropics/claude-code#14549", "anthropics/claude-code#22020", "anthropics/claude-code#11045"]
---

# Claude Code Per-Directory Command Registration Limit

## Problem

Plugin commands silently fail to register when a `commands/<namespace>/` subdirectory contains more than ~8 command files. Affected commands return "Unknown skill" when typed manually and do not appear in autocomplete. No error, no warning, no log entry.

## Root Cause

Claude Code's plugin loader imposes an undocumented per-directory cap (~8 items) on command registration. Commands beyond this limit are silently dropped. The limit is per-directory — `skills/` directories and local `.claude/commands/` are not subject to the same constraint.

### Evidence

| Observation | What it proves |
|---|---|
| System prompt consistently showed exactly 8/10 commands | Hard cutoff, not probabilistic |
| Same 2 commands always dropped (`plugin-changes-qa`, `recover`) | Deterministic, not random |
| Descriptions matched v1.7.0 text despite v1.8.2 installed | Loader stops after N items, keeps stale cached versions |
| Local `.claude/commands/` copies of dropped commands worked | Command content is valid; limit is on the loading path |
| Moving dropped commands to `skills/` worked | Limit is per-directory for `commands/`, not global |

## Solution

Move overflow commands from `commands/<namespace>/` to `skills/` directory. Skills register independently with a higher or uncapped budget.

```
# Before (broken — 10 commands, 2 silently dropped)
commands/compound/
├── brainstorm.md
├── ...8 more...
├── plugin-changes-qa.md  # DROPPED
└── recover.md             # DROPPED

# After (working — 8 commands + 2 skills)
commands/compound/          # 8 files (at limit)
skills/plugin-changes-qa/   # registers as /compound-workflows:plugin-changes-qa
skills/recover/             # registers as /compound-workflows:recover
```

### Trade-off

Invocation namespace changes from `/compound:name` to `/compound-workflows:name`. Acceptable because these commands are infrequently invoked and the longer prefix is a minor cost.

## Investigation Timeline (3 patches in one day)

| Version | Fix attempted | Result |
|---|---|---|
| **v1.8.1** | Remove `license`/`keywords` from plugin.json (per #20415) | No effect — defensive cleanup only |
| **v1.8.2** | Shorten all 28 descriptions by 63% (4577→1677 chars) | No effect — limit is count-based, not char-based |
| **v1.8.3** | Move 2 commands to skills | **Fixed** |

Additional fixes during the investigation:
- `SLASH_COMMAND_TOOL_CHAR_BUDGET=100000` env var — no effect
- Switched marketplace source from git-subdir to local path — no effect on registration, but good practice for development

## What Didn't Work

| Attempted Fix | Why it failed |
|---|---|
| `SLASH_COMMAND_TOOL_CHAR_BUDGET=100000` | Controls total char budget for system prompt skill section, not per-directory count |
| Shortening descriptions (63% reduction) | Good practice for char budget, but the limit is per-directory count |
| Removing unknown plugin.json fields | Fields don't actually break registration despite issue #20415 |
| Switching marketplace source to local path | Affects how marketplace delivers plugin, not how loader registers commands |
| Uninstall + reinstall plugin | Cache updated correctly; the limit persists regardless of install method |

## Architectural Guideline

For Claude Code plugins:
- **Max 7 commands per `commands/` subdirectory** (leaves 1 slot as buffer)
- **Default to `skills/` for most slash commands** — skills support `disable-model-invocation: true` and can hold supporting files
- **Reserve `commands/` for primary workflows** that benefit from the shorter namespace

## Reuse Triggers

Re-read this when:
- Adding a command to a directory with 7+ files
- Debugging "Unknown skill" errors for commands that exist on disk
- Setting up a new Claude Code marketplace plugin
- `claude plugin update` doesn't pick up new versions (marketplace clone needs manual `git pull`)
- Planning plugin architecture (commands vs skills)

## Marketplace Clone Behavior

The marketplace cache at `~/.claude/plugins/marketplaces/<name>/` is a full git clone. Key behaviors:
- `claude plugin update` may not `git pull` the latest — manual `git pull` in the clone directory may be needed
- Local path source (`"./plugins/..."`) is more reliable than git-subdir with ref tags
- Upstream (EveryInc/compound-engineering-plugin) uses local path source as the standard convention

## Assumptions That Could Invalidate

- Anthropic could raise or remove the per-directory limit
- The exact limit (~8) may vary across Claude Code versions
- If Claude Code changes skill registration mechanics, the workaround may need revisiting
