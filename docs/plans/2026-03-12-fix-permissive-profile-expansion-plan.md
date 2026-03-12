---
title: "fix: expand permissive profile with missing safe rules"
type: fix
status: draft
date: 2026-03-12
---

# Fix: Expand Permissive Profile with Missing Safe Rules

## Context

Audit of a real user's `settings.local.json` against the permissive profile in `do:setup` revealed 18 missing rules that are safe and commonly needed. The permissive profile should reduce prompts to near-zero for trusted environments, but gaps force users to accumulate ad-hoc rules.

Also discovered: `Bash(bd:*)` does not match `bd <subcommand>` in practice — explicit subcommand rules are required. Root cause unknown (likely Claude Code glob matching behavior). This means bd users need per-subcommand rules.

Already completed: removed `rm:*` from permissive (zvux, committed in 3.0.2).

## Rules to Add

### General (10)

| Rule | Rationale |
|------|-----------|
| `Bash(git:*)` | Fundamental — used constantly, hook handles for standard but permissive users expect it |
| `Bash(mkdir:*)` | Basic, safe — model generates bare `mkdir -p` without `bash` prefix. Currently standard-only add-on but belongs in permissive |
| `Bash(md5:*)` | Used regularly for hash checks in plugin workflows |
| `Bash(ls:*)` | Basic, safe — avoids prompts on `ls` with flags |
| `Bash(bd:*)` | Beads is a core plugin tool — kept even though subcommand rules are also needed |
| `Bash(if:*)` | Shell control flow — common in model-generated bash, triggers heuristics with `$()` inside |
| `Bash(for:*)` | Shell control flow — used for iterating over beads results, file lists, etc. |
| `Bash([[:*)` | Shell control flow — conditional checks |
| `Bash(xargs:*)` | Pipeline tool — safe, used in data processing |
| `Bash(tee:*)` | Pipeline tool — safe, used for logging output |
| `WebFetch(domain:*)` | Research agents and defuddle skill fetch URLs — broad but consistent with permissive trust model |

### Beads Subcommands (13)

`Bash(bd:*)` doesn't cover `bd <subcommand>` in practice. All common subcommands need explicit rules:

| Rule | Used by |
|------|---------|
| `Bash(bd show:*)` | All workflows — inspect issues |
| `Bash(bd list:*)` | All workflows — enumerate issues |
| `Bash(bd create:*)` | do:work — create issues from plan steps |
| `Bash(bd update:*)` | do:work — claim issues, update status |
| `Bash(bd close:*)` | do:work — mark issues complete |
| `Bash(bd search:*)` | Ad-hoc — find issues by keyword |
| `Bash(bd ready:*)` | do:work — find unblocked issues |
| `Bash(bd blocked:*)` | Ad-hoc — check blocked issues |
| `Bash(bd dep:*)` | do:work — manage dependencies |
| `Bash(bd worktree:*)` | do:work — create/remove worktrees |
| `Bash(bd stats:*)` | Ad-hoc — project health |
| `Bash(bd doctor:*)` | Ad-hoc — diagnostics |
| `Bash(bd dolt:*)` | Session end — push/pull beads |

### Not Adding (personal preference, not universal)

| Rule | Why excluded |
|------|-------------|
| `Read(//Users/adamf/.claude/**)` | User-specific path |
| `mcp__pal__thinkdeep` | Not all users have PAL |
| `mcp__pal__analyze` | Not all users have PAL |

## Implementation

- [ ] **Step 1:** Add 24 rules to permissive profile rule list in `skills/do-setup/SKILL.md` (line ~460)
- [ ] **Step 2:** Update permissive summary line (line ~435) to mention git, ls, mkdir, md5, bd, shell constructs, WebFetch
- [ ] **Step 3:** Update CHANGELOG.md under current unreleased version
- [ ] **Step 4:** Add `ls` and `git` to standard profile add-on (line ~718 area) alongside existing `which`, `echo`, `mkdir`
- [ ] **Step 5:** Run QA — this touches a skill file

## Resolved Questions

- **Standard profile add-on gets `ls` and `git` too.** Yes — these are basic and safe. Standard add-on becomes: `which`, `echo`, `mkdir`, `ls`, `git`.
- **Conditional bd rules deferred.** Setup adds bd rules unconditionally for now. Bead ptxp tracks adding `bd version` detection to conditionally include them.
