---
title: Plugin Skill Discovery Requires Cache Directory, Not Dev Repo
date: 2026-03-12
category: plugin-infrastructure
tags: [plugin-system, skills, cache, discovery, reload-plugins, development-workflow, arguments-substitution]
severity: medium
status: resolved
origin_plan: docs/plans/2026-03-11-feat-plugin-script-path-resolution-plan.md
origin_brainstorm: docs/brainstorms/2026-03-11-plugin-script-path-resolution-brainstorm.md
---

# Plugin Skill Discovery Requires Cache Directory, Not Dev Repo

## Problem

Creating a new skill directory (`skills/args-test/SKILL.md`) in the development repo and running `/reload-plugins` does not make the skill discoverable. Invoking `/compound-workflows:args-test` returns "Unknown skill" despite valid YAML frontmatter with `name` and `description` fields.

## Root Cause

Claude Code's plugin loader reads skills from the **cache directory**, not the development repository. When a plugin is installed with `scope: "user"`, the authoritative source is:

```
~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/
```

The development repo is the source of truth for version control, but not for runtime discovery. `/reload-plugins` re-reads the cache, not the dev directory.

### Evidence

| Observation | What it proves |
|---|---|
| Skill created in dev repo → "Unknown skill" after `/reload-plugins` | Dev repo is not the runtime source |
| Cache `skills/` listed 20 original skills, not the new one | Cache was not updated by dev repo changes |
| Skill created in cache directory → visible after `/reload-plugins` | Cache is the authoritative loader path |
| `installed_plugins.json` shows `scope: "user"` with cache `installPath` | Plugin loader resolves via cache |

## Solution

For development testing of new skills, create them in the cache directory:

```
~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/skills/<new-skill>/SKILL.md
```

Then run `/reload-plugins`.

### Development Workflow for New Skills

1. Create the skill in the **dev repo** (for version control)
2. Copy to the **cache directory** (for runtime discovery)
3. Run `/reload-plugins`
4. Test the skill
5. Iterate in cache for fast feedback
6. Copy final version back to dev repo

### Longer-term: Symlink Dev Mode

Replace the cache directory with a symlink to the source repo:

```bash
ln -s "$(pwd)/plugins/compound-workflows" \
  "$HOME/.claude/plugins/cache/<marketplace>/<plugin>/<version>"
```

Eliminates the sync step entirely. Changes visible after `/reload-plugins`. Tradeoff: `claude plugin update` overwrites the symlink.

## Additional Findings

### `$ARGUMENTS` Substitution in SKILL.md

`$ARGUMENTS` is substituted at invocation time. Adjacent literal characters are preserved:

- SKILL.md contains: `"#$ARGUMENTS"`
- User runs: `/compound-workflows:args-test hello world`
- Agent receives: `"#hello world"`

The `#` stays as literal text — not consumed by substitution. For clean output, use `$ARGUMENTS` without `#`.

### `git branch -d` After Squash-Merge

`git branch -d` warns "not fully merged" after squash-merge because squash creates a new SHA unreachable from the branch tip. Use `git branch -D` (force delete) when you know the squash succeeded.

## Reuse Triggers

- Adding a new skill to the plugin during development
- Debugging "Unknown skill" for a skill that exists in the dev repo
- Setting up a development workflow for plugin iteration
- Investigating why `/reload-plugins` doesn't pick up changes

## Related

- `memory/project.md` — "Loaded skill staleness" and "Marketplace clone" entries
- `docs/solutions/plugin-infrastructure/2026-03-08-command-registration-limit-workaround.md` — cache mechanics
- `docs/brainstorms/2026-03-11-plugin-script-path-resolution-brainstorm.md` — `${CLAUDE_SKILL_DIR}` evidence
