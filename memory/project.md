# Project Context

## Overview
- Plugin: compound-workflows v2.1.0 (plugins/compound-workflows/)
- 26 agents, 19 skills, 8 commands
- Commands under `/compound:*`, skills under `/compound-workflows:*`
- Forked from Every's compound-engineering (February 2026), fully self-contained
- GitHub repo: adamfeldman/compound-workflows (public)
- 1 external user (as of 2026-03-09)

## Architecture Decisions
- **Namespace `/compound:*`** — shorter to type. Exception: `plugin-changes-qa` and `recover` are skills under `/compound-workflows:*` due to per-directory command limit (~8).
- **Single work executor** — `/compound:work` IS the subagent architecture. Main context runs out of context and never finishes.
- **Config split** — `compound-workflows.md` (committed, project) + `compound-workflows.local.md` (gitignored, env). Red team prefs runtime-detected.
- **`.workflows/` committed in user projects** (research traceability), gitignored in this plugin source repo.
- **Deferring is OK** when user explicitly chooses it — "zero untriaged items" not "zero deferred items".

## Critical Discoveries
- **Nested Task dispatch does NOT work** — subagents cannot spawn further subagents. Use flat dispatch.
- **Claude Code hooks cannot trigger slash commands** — use PostToolUse on Bash instead. Sentinel `.workflows/.work-in-progress` suppresses during `/compound:work`.
- **Subagents cannot write to `.claude/` directory** — orchestrator must handle protected paths.
- **Claude Code per-directory command limit** — ~8 commands per `commands/` subdirectory. Overflow goes to `skills/`.
- **Marketplace clone** — cache at `~/.claude/plugins/marketplaces/<name>/` is a full git clone. Use `claude plugin update compound-workflows@compound-workflows-marketplace`.
- **`bd list --json` does NOT produce JSON** — use `bd search "" --status open --json` instead.
- **`bd search` default limit is 50** — pass `--limit N` for more.
- **`bd update --append-notes`** — appends (not overwrites). Use instead of `--notes`.
- **bd worktree create uses path as-is** — pass `.worktrees/<name>` explicitly.
- **Loaded skill staleness** — skills loaded at conversation start from cached plugin version. Mid-session updates don't refresh loaded skills. Also affects new agents — created mid-session won't appear in `subagent_type` list.
- **Agent tool HAS `model` parameter** — `model: enum["sonnet", "opus", "haiku"]` overrides agent frontmatter at dispatch time. Validated 2026-03-09: dispatched code-simplicity-reviewer with `model: "haiku"`, completed in 995ms (vs 13s at opus). Previous memory entry ("has no model parameter") was outdated — parameter was added in a Claude Code update. Named agents still respect `model` field in frontmatter when no dispatch override (proven: haiku and sonnet both work).
- **`CLAUDE_CODE_SUBAGENT_MODEL` env var** — only affects agents WITHOUT explicit `model:` field. Does NOT override explicit `model: sonnet` or `model: haiku`. Agents with `model: inherit` or no model field are affected. Discovered during readiness semantic checks (contradicted multiple red team providers who claimed it "overrides all").
- **worktree-manager.sh uses `cleanup` not `remove`** — `bash worktree-manager.sh cleanup` to remove completed worktrees (interactive y/n).
- **Worktree blocks `gh pr merge`** — use `gh api repos/.../pulls/N/merge -X PUT -f merge_method=squash` instead.
- **`claude plugin update` unreliable** — command exits 0 silently but doesn't always pull latest. Fallback: `git -C ~/.claude/plugins/marketplaces/<name> pull origin main` then `/reload-plugins`.
- **Agent tool background completions include `<usage>`** — identical format to Task completion notifications (`total_tokens`, `tool_uses`, `duration_ms`). Validated 2026-03-09 with 3 dispatches (repo-research-analyst, context-researcher, code-simplicity-reviewer). Switching Task→Agent does not break `<usage>` capture.
- **Background agents get Write/Edit permission denied** — agents launched with `run_in_background: true` cannot prompt for interactive permission approval. If `.claude/settings.local.json` doesn't pre-allow the Write/Edit paths, agents silently fail to write output files. Fix: add `Write(//.workflows/**)` and `Edit(//.workflows/**)` to project settings. Captured as bead 3k3 to add to `/compound:setup`. User: "in general i want to be hitting 'yes' less often."
- **`find` on `~/.claude/plugins/cache` hits sandbox restrictions** — `find -path "*/agents/*.md"` and `find -type f` return empty silently due to sandbox. `ls` and `find` without type/path filters work. Affects deepen-plan Phase 2 agent/skill discovery. Root cause of bash approval cascades.

## Session Log Format
- Path: `~/.claude/projects/<path-with-dashes>/<session-id>.jsonl`
- Entry types: progress, assistant, user, file-history-snapshot, queue-operation, system, custom-title, last-prompt

## Completed Work
- **v1.7.0** — Plan readiness agents (PR #1)
- **v1.8.0** — Context-lean enforcement + QA enhancement (PR #2)
- **v1.9.0** — Finding resolution provenance (PR #3)
- **v1.9.1** — Plan deepen recommendation (PR #5)
- **v1.10.0** — Three-category MINOR triage (PR #6)
- **v1.11.0** — Plugin version visibility (PR #7): version-check.sh, version-sync.sh, /compound-workflows:version skill, compact-prep/setup/work.md integrations, doc alignment
- **v1.12.0** — QA bead cross-ref (PR #8)
- **v1.12.1** — Bug fixes: stale /compound:recover refs, compact-prep $ARGUMENTS syntax, work.md sequential-as-safer bias, context-lean-grep false positives (13 SERIOUS → 0)
- **v1.9.0** — Deepen-plan convergence guidance (PR #4): convergence-signals.sh, convergence-advisor.md, Phase 5.75/6/1 in deepen-plan.md

- **v1.12.2** — Dynamic plugin script path resolution via `find` (version-check.sh, plugin-qa)
- **v1.13.0** — Setup routing rules (AGENTS.md), conditional compact-prep release check
- **v1.13.1** — All remaining hardcoded plugin paths fixed (plan.md, deepen-plan.md, work.md, setup.md, plugin-changes-qa)
- **v1.13.2** — version-check.sh consumer project bug, QA agent noise reduction (awx), roadmap table in root README
- **v2.0.0** — Workflow quota optimization (bead 22l): 5 research agents → sonnet, red-team-relay agent, stack-based dynamic agent selection, ccusage tracking, convergence advisor named dispatch
- **v2.1.0** — Native agent discovery (bead wgl): deepen-plan Phase 2 filesystem discovery → subagent_type registry, Agent dispatch migration across all phases, deterministic post-discovery validation pipeline, user-defined agent support, QA scripts detect Agent dispatch syntax

## In-Progress Work
- **Per-agent token instrumentation (bead voo)** — P1. Plan complete at `docs/plans/2026-03-09-feat-per-agent-token-instrumentation-plan.md`. 10 implementation steps: settings, stats-capture reference file, 5 command instrumentations (work→brainstorm→plan→review→deepen-plan), compact-prep ccusage snapshot, classify-stats skill (`/compound-workflows:classify-stats` — command dir at capacity). Stop-gate between Steps 3-4 (verify background `<usage>` before instrumenting background commands). Readiness checks: 6 auto-fixes applied (underspecification), verify clean. **voo plan needs update:** incorporate Agent dispatch migration from native-agent-discovery brainstorm (all 5 commands switch Task→Agent for `model` override + standardization). Next: `/compound:deepen-plan`.
- **Work-step-executor: Sonnet subagents (bead xu2)** — P2. ~80% of work steps are mechanical after well-deepened plans. Depends on voo (need dataset first). Next: `/compound:brainstorm`.
- **Red team model selection (bead aig)** — P1, brainstorm complete. Next: `/compound:plan`.
- **Correction-capture skill (bead rhl)** — P2. Next: `/compound:brainstorm`.
- **Red team + readiness in plan (bead nn3)** — P1. Brainstorm complete at `docs/brainstorms/2026-03-10-plan-red-team-readiness-brainstorm.md`. 14 key decisions, red-teamed by 3 providers, all findings resolved. Key: Phase 6.8 (optional red team, 7-dimension prompt), Phase 6.9 (full readiness re-check if edits applied, not verify-only), decision tree routes to work when red team clean (CRITICAL/SERIOUS both trigger deepen-plan routing). Deepen-plan keeps its own independent red team. Target: v2.2.0 (MINOR bump). Next: `/compound:plan`.
- **Compact-prep version check config toggle (bead xzn)** — P2. Add config toggle for version check, disabled by default.
- **Check upstream compound-engineering (bead odn)** — P3. Review EveryInc/compound-engineering-plugin for changes since fork.

## Critical Patterns
- **Plugin paths must use `find` fallback** — all script/file references in commands/skills need dynamic resolution: try local path, then `find "$HOME/.claude/plugins" ...`. Affects any new command referencing plugin scripts.
- **version-check.sh context detection** — in source repo: 3-way (source vs installed vs release). In consumer project: 2-way (installed vs release only).
- **`.beads/PRIME.md`** overrides bd prime to remove conflicting memory instructions

## Dependency Chain
- xu2 → voo (work-step-executor needs per-agent stats dataset)
- aig → h0g (aig now unblocked)
- 22l(done), 0ob(done), dud(done), 1q3(done), 4gq(done), n2q(done), 3co(done), d2l(done), awx(done)
