# Project Context

## Overview
- Plugin: compound-workflows v2.4.1 (plugins/compound-workflows/)
- 26 agents, 20 skills, 8 commands
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
- **`bd search --json` field names** — `estimated_minutes` (not `estimate`), `dependency_count` (not `dependencies`), `issue_type` (not `type`). Empty string query `""` fails; use `"a"` or any non-empty query with `--status open` to list all.
- **What's Next table rendering** — `bd search "a" --status open --json --limit 100`, pipe to python3 via heredoc (`<< 'PYEOF'`), filter out in_progress/P4/blocked (`dependency_count > 0`), compute `eff = impact_score / (estimated_minutes / 60)`, sort by eff descending.
- **`bd update --append-notes`** — appends (not overwrites). Use instead of `--notes`.
- **bd worktree create uses path as-is** — pass `.worktrees/<name>` explicitly.
- **Loaded skill staleness** — skills loaded at conversation start from cached plugin version. Mid-session updates don't refresh loaded skills. Also affects new agents — created mid-session won't appear in `subagent_type` list.
- **Agent tool HAS `model` parameter** — `model: enum["sonnet", "opus", "haiku"]` overrides agent frontmatter at dispatch time. Validated 2026-03-09: dispatched code-simplicity-reviewer with `model: "haiku"`, completed in 995ms (vs 13s at opus). Previous memory entry ("has no model parameter") was outdated — parameter was added in a Claude Code update. Named agents still respect `model` field in frontmatter when no dispatch override (proven: haiku and sonnet both work).
- **`CLAUDE_CODE_SUBAGENT_MODEL` env var** — only affects agents WITHOUT explicit `model:` field. Does NOT override explicit `model: sonnet` or `model: haiku`. Agents with `model: inherit` or no model field are affected. Discovered during readiness semantic checks (contradicted multiple red team providers who claimed it "overrides all").
- **worktree-manager.sh uses `cleanup` not `remove`** — `bash worktree-manager.sh cleanup` to remove completed worktrees (interactive y/n).
- **Worktree blocks `gh pr merge`** — use `gh api repos/.../pulls/N/merge -X PUT -f merge_method=squash` instead.
- **clink CLIs read repo files independently** — Gemini uses `read_file` tool, Codex uses `cat`. Verified: both browse beyond the brainstorm file passed via `absolute_file_paths` — they reference CLAUDE.md, README.md, command files, directory structure. 100% of red team dispatches used clink, never PAL chat. PAL chat would need `absolute_file_paths` explicitly; CLIs don't.
- **`VAR=$((...))` also triggers heuristic** — arithmetic expansion `$((...))` triggers the SAME permission prompt heuristic as command substitution `$()`. Empirically verified 2026-03-11: `TEST_VAL=$((2 + 3))` prompted. No distinction between `$()` and `$(())`. QA Check 5 regex must catch both.
- **Most $() init patterns are fixable** — `PLUGIN_ROOT=$(find ...)` → glob loop, `RUN_ID=$(uuidgen ...)` → standalone cmd + model reads output, `STATS_FILE="...$(date ...)"` → split date call. Bash vars don't persist between Bash tool calls anyway — model already tracks values mentally. Split adds 0 cognitive load but eliminates the prompt.
- **Skills have same heuristic patterns as commands** — skill SKILL.md files contain model-interpreted bash with $() patterns. QA Check 5 must scan skills too, not just `$cmd_dir/*.md`.
- **`claude plugin update` unreliable** — command exits 0 silently but doesn't always pull latest. Fallback: `git -C ~/.claude/plugins/marketplaces/<name> pull origin main` then `/reload-plugins`.
- **Agent tool background completions include `<usage>`** — identical format to Task completion notifications (`total_tokens`, `tool_uses`, `duration_ms`). Validated 2026-03-09 with 3 dispatches (repo-research-analyst, context-researcher, code-simplicity-reviewer). Switching Task→Agent does not break `<usage>` capture.
- **Subagent settings inheritance verified** — subagents DO load `.claude/settings.json` from the project root. Empirically tested 2026-03-10: added a distinctive allow rule, spawned a subagent, confirmed it auto-approved. Write failures were transient permission denials, not systemic inheritance issues.
- **Deny rules in settings.json are BROKEN** — multiple GitHub issues (#27040, #6699, #8961) confirm deny rules are non-functional. PreToolUse hooks are the ONLY reliable way to block dangerous operations. Hook output format: `{"hookSpecificOutput": {"permissionDecision": "allow"}}`.
- **PreToolUse hooks are documented and supported** — hooks reference at code.claude.com/docs/en/hooks. Since v2.0.10, hooks can also modify tool inputs before execution. "Officially recommended" and "v2.0+" could not be verified as specific designations in docs — softened from prior entry.
- **PreToolUse hook input schema** — common fields: `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`. PreToolUse-specific: `tool_name`, `tool_input`, `tool_use_id`. Subagent context adds: `agent_id`, `agent_type`. Matcher is regex on `tool_name`; `""` or `"*"` or omitted = match all. Output: exit 0 + JSON `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}`. Exit 0 with no output = fall through. Exit 2 = blocking error (more reliable than JSON deny per issue #4669).
- **Bash safety heuristics: static rules suppress, hooks don't** — `$()`, backticks, `{"`, heredocs trigger Claude Code's built-in heuristics. Static `Bash(X:*)` rules suppress them (fire BEFORE heuristics — verified: `bd:*` suppresses `{"`, `git:*` suppresses `$()`). PreToolUse hooks CANNOT suppress them (fire AFTER heuristics). `--dangerously-skip-permissions` suppresses everything. No "multi-line heuristic" exists — multi-line blocks without `$()` auto-approve. GitHub #30435, #31373 (both OPEN 2026-03-10). See: `docs/solutions/claude-code-internals/2026-03-10-static-rules-suppress-bash-heuristics.md`.
- **Static `Bash(VAR=:*)` rules don't reliably match** — added `Bash(PLAN_PATH=:*)` etc. to settings.local.json but commands starting with variable assignments still prompted. Confirmed during this session. Hook approach is the real fix.
- **No Claude Code setting to disable auto-memory per-project** — auto-memory (`~/.claude/projects/.../memory/`) is always active. System prompt instructs the LLM to write there. Workaround: redirect guard in MEMORY.md saying "DO NOT USE." LLM-enforced, not technically enforced — fragile. Upstream feature request needed.
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
- **v2.2.0** — Red team + readiness re-check in plan (bead nn3): Phase 6.8 (3-provider red team with Yes/Skip gate, 7-dimension prompt, MINOR triage), Phase 6.9 (conditional full readiness re-check via SHA-256 hash), 7-rule decision tree, deepen-plan 7th dimension, brainstorm 6th dimension
- **v2.3.0** — Per-agent token instrumentation (bead voo): capture-stats.sh, stats-capture-schema.md, all 5 commands instrumented, compact-prep ccusage snapshot, /compound-workflows:classify-stats skill, stats_capture + stats_classify settings. 10 steps via /compound:work (4 parallel batches). QA clean after TaskOutput ban phrasing fix.
- **v2.4.1** — Plugin heuristic audit (bead jak): validate-stats.sh replaces 9 inline ENTRY_COUNT blocks, 2 P5 subshell fixes, sentinel redesign (Write tool clear vs rm), QA Check 5 (var-dollar-paren-heuristic), 27 heuristic-exempt markers. 10 steps via /compound:work (6 parallel in batch 1).

## In-Progress Work
- **Heuristic audit scope expansion (bead 3l7)** — P1. jak v2.4.1 missed skills (11 $() patterns) and accepted fixable command init patterns (27 marked exempt). Most are eliminable via split commands, glob loops, model-side arithmetic. Principles 8+9 added to CLAUDE.md. Next: `/compound:brainstorm 3l7`.
- **Work-step-executor: Sonnet subagents (bead xu2)** — P1. ~80% of work steps are mechanical after well-deepened plans. voo done — dataset now available. Next: `/compound:brainstorm`.
- **Red team model selection (bead aig)** — P3 (lowered: clink handles model selection, not urgent). Brainstorm complete. Accumulated notes: Opus model bug, ad-hoc red team skill idea, cost configurability, CLI file access verified. Next: `/compound:plan`.
- **Correction-capture skill (bead rhl)** — P2. Next: `/compound:brainstorm`.
- **Config toggles for optional compact-prep steps (bead xzn)** — P2. Version check + daily cost summary both optional.
- **User input gates before automated work (bead 42s)** — P2. Brainstorm complete. Key finding: the bug is execution sequencing (Step 3c runs before 3d), not display order. Scope narrowed to 3 commands (brainstorm, plan, deepen-plan — review.md has no triage flow). Next: `/compound:plan`.
- **Cheaper-model dispatch audit (bead 5b6)** — P2. voo done — dataset now available. Next: `/compound:brainstorm`.

## Critical Patterns
- **Plugin paths must use `find` fallback** — all script/file references in commands/skills need dynamic resolution: try local path, then `find "$HOME/.claude/plugins" ...`. Affects any new command referencing plugin scripts.
- **version-check.sh context detection** — in source repo: 3-way (source vs installed vs release). In consumer project: 2-way (installed vs release only).
- **`.beads/PRIME.md`** overrides bd prime to remove conflicting memory instructions

## Dependency Chain
- xu2 unblocked (voo done — dataset available)
- 5b6 unblocked (voo done — dataset available)
- h0g unblocked (removed aig dependency)
- **3k3 absorbed into permission-prompt-optimization** — plan fully triaged: 4 CRITICAL + 7 SERIOUS from red team resolved, re-check clean, security sentinel + architecture strategist + code simplicity reviewers ran. Plan ready for work. Key changes: pipes/`$()`/heredocs/globs added to pre-checks, realpath adopted, profiles collapsed 3→2 (Standard/Permissive), hook shipped as template file, quote-aware tokenization specified.
- **a6t created** — P2. Agent timeout/recovery rules in plan command. Don't skip agents that are actively working.
- **cn5 created** — P3. Make stats collection off by default.
- **jak created** — P3. Audit plugin commands for heuristic-triggering patterns ($(), for loops, heredocs).
- **jed created** — P3. Audit log rotation for .hook-audit.log.
- **2g4 created** — P2. Config option to auto-create beads for deferred plan items.
- **4v2 created** — P2. Plan command should ensure all implementation details are specified (underspecifications block autonomous work execution).
- voo(done), 22l(done), 0ob(done), dud(done), 1q3(done), 4gq(done), n2q(done), 3co(done), d2l(done), awx(done)
