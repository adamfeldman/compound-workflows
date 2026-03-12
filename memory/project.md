# Project Context

## Overview
- Plugin: compound-workflows v3.1.2 (plugins/compound-workflows/)
- 26 agents, 29 skills, 8 commands (thin aliases)
- Workflow skills under `/do:*` (shorthand) or `/compound-workflows:do:*` (full). Legacy `/compound:*` aliases redirect during transition.
- Forked from Every's compound-engineering (February 2026), fully self-contained
- GitHub repo: adamfeldman/compound-workflows (public)
- 1 external user (as of 2026-03-09)

## Architecture Decisions
- **Namespace `/do:*`** — workflow skills migrated from commands to skills in v3.0.0. `/compound:*` thin aliases redirect for backwards compat (one version only).
- **Single work executor** — `/compound:work` IS the subagent architecture. Main context runs out of context and never finishes.
- **Config split** — `compound-workflows.md` (committed, project) + `compound-workflows.local.md` (gitignored, env). Red team prefs runtime-detected.
- **`.workflows/` committed in user projects** (research traceability), gitignored in this plugin source repo.
- **Deferring is OK** when user explicitly chooses it — "zero untriaged items" not "zero deferred items".
- **Knowledge Precedence** (AGENTS.md) — 6-tier hierarchy: live code > solutions > plans > brainstorms > memory > research artifacts. Agents trust higher-tier docs when sources conflict. Research artifacts are working subagent output, valuable for depth but not authoritative over reviewed decisions.

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
- **Most $() init patterns are fixable via init-values.sh** — a shared script that prints labeled values. The Bash tool input `bash init-values.sh brainstorm` contains no `$()` → no heuristic fires → auto-approves everywhere (no static rule or hook needed). The `$()` stays inside the .sh file. Bootstrap: try local path first, find fallback (also clean — no $()). Validated during 3l7 brainstorm. Supersedes prior split-call approach (split-calls also work but require model to track 3-5 values across calls).
- **Skills have same heuristic patterns as commands** — skill SKILL.md files contain model-interpreted bash with $() patterns. QA Check 5 must scan skills too, not just `$cmd_dir/*.md`.
- **Plugin update requires git pull FIRST (workaround)** — `claude plugin update` checks the local marketplace clone, not the GitHub remote, so it doesn't immediately pick up new releases. Workaround: (1) `git -C ~/.claude/plugins/marketplaces/compound-workflows-marketplace pull origin main`, (2) `claude plugin update compound-workflows@compound-workflows-marketplace`, (3) restart. Do NOT skip step 1. Do NOT manually copy to cache or remove+re-add the plugin.
- **Agent tool background completions include `<usage>`** — identical format to Task completion notifications (`total_tokens`, `tool_uses`, `duration_ms`). Validated 2026-03-09 with 3 dispatches (repo-research-analyst, context-researcher, code-simplicity-reviewer). Switching Task→Agent does not break `<usage>` capture.
- **Subagent settings inheritance verified** — subagents DO load `.claude/settings.json` from the project root. Empirically tested 2026-03-10: added a distinctive allow rule, spawned a subagent, confirmed it auto-approved. Write failures were transient permission denials, not systemic inheritance issues.
- **Deny rules in settings.json are BROKEN** — multiple GitHub issues (#27040, #6699, #8961) confirm deny rules are non-functional. PreToolUse hooks are the ONLY reliable way to block dangerous operations. Hook output format: `{"hookSpecificOutput": {"permissionDecision": "allow"}}`.
- **PreToolUse hooks are documented and supported** — hooks reference at code.claude.com/docs/en/hooks. Since v2.0.10, hooks can also modify tool inputs before execution. "Officially recommended" and "v2.0+" could not be verified as specific designations in docs — softened from prior entry.
- **PreToolUse hook input schema** — common fields: `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`. PreToolUse-specific: `tool_name`, `tool_input`, `tool_use_id`. Subagent context adds: `agent_id`, `agent_type`. Matcher is regex on `tool_name`; `""` or `"*"` or omitted = match all. Output: exit 0 + JSON `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}`. Exit 0 with no output = fall through. Exit 2 = blocking error (more reliable than JSON deny per issue #4669).
- **Bash safety heuristics: static rules suppress SOME, not all** — Static `Bash(X:*)` rules suppress "soft" heuristics: `{"` (verified: `bd:*` suppresses `{"`), redirects `>` (verified: `bd stats > /dev/null` auto-approved via `bd:*`). **Hard heuristics NOT suppressed by static rules:** `$()` command substitution (verified 2026-03-12: `git:*`, `bd:*`, `bd search:*` all failed to suppress $() — contradicts prior documentation), `<<` heredoc (verified 2026-03-11), `cp` with flags ("cp command with flags requires manual approval"). Fix for $(): avoid it entirely (Bash Generation Rules). Fix for heredocs: hide in script files. PreToolUse hooks CANNOT suppress any heuristic (fire AFTER heuristics). No "multi-line heuristic" exists. See: `docs/solutions/claude-code-internals/2026-03-10-static-rules-suppress-bash-heuristics.md`.
- **Static `Bash(VAR=:*)` rules don't reliably match** — added `Bash(PLAN_PATH=:*)` etc. to settings.local.json but commands starting with variable assignments still prompted. Confirmed during this session. Hook approach is the real fix.
- **No Claude Code setting to disable auto-memory per-project** — auto-memory (`~/.claude/projects/.../memory/`) is always active. System prompt instructs the LLM to write there. Workaround: redirect guard in MEMORY.md saying "DO NOT USE." LLM-enforced, not technically enforced — fragile. Upstream feature request needed.
- **Tier 1 QA zero-findings baseline** — all QA scripts must produce zero findings on a clean repo. Verified-correct patterns use `context-lean-exempt` markers to suppress known-good matches. Convention: mark exempt lines with `# context-lean-exempt: <reason>` so the grep skips them. If any script shows findings, they're either new bugs or missing exempt markers — never "pre-existing known-good." This ensures a fresh session always sees a clean baseline.
- **`bash -c` is unsafe as a static rule** — `Bash(bash -c:*)` auto-approves arbitrary inline code (universal bypass). No path-scoping possible because the argument is inline code, not a file path. Permissive profile only at best, never safe profile. Tested: `bash -c 'VAR=$(cmd); echo $VAR'` auto-approves via `Bash(bash:*)` but that's equally unsafe. The init-values.sh approach is superior: `bash script.sh` has no $() in tool input at all.
- **Zero $() in agent YAML files** — confirmed empirically. Agent prompts are loaded as system prompts for subagents, not as Bash tool input in the orchestrator. QA scan includes agents for future-proofing but currently 0 hits.
- **"cd with write operation" heuristic** — compound commands containing `cd` + write (`>`, `>>`, `mv`, `cp`) trigger "manual approval required to prevent path resolution bypass". Empirically verified 2026-03-12: `cd /path && mkdir -p .workflows && date +%s > .workflows/.work-in-progress` prompted. Fix: use absolute paths instead of cd-then-relative-write. No static rule suppresses this.
- **Relative paths in skills break in worktrees** — skill instructions using relative paths (e.g., `.workflows/tmp/commit-msg.txt`) cause models to prepend `cd /worktree/path &&` when executing in worktrees, triggering the cd+write heuristic. Also produces ugly `../../../` chains in Write tool calls, making session permission scoping ("allow all edits in tmp/") less useful. Fix: skills should use absolute paths computed from worktree path variables. Affects do-work sentinel setup (line 139) and commit message file (line 411).
- **"Quoted characters in flag names" heuristic: glob + redirect** — empirically verified 2026-03-11. Two confirmed trigger combinations: (1) glob (`*`) + redirect (`>`) in same command (e.g., `ls *.md 2>/dev/null`), (2) quoted dash string (`"---"`) + redirect in compound commands (e.g., `cmd 2>/dev/null; echo "---"`). `2>/dev/null` is the common enabler. Neither pattern triggers without the redirect. `--flag=value` alone is NOT a trigger. Fix: stop reflexively appending `2>/dev/null` to commands.
- **Ad-hoc model-generated bash is the remaining heuristic problem** — v2.5.0 fixed all plugin command/skill templates. The remaining 5-15 permission prompts per session come from bash the model generates in normal conversation (debugging, bead management, data analysis). No CLAUDE.md instructions exist to guide this. Brainstorm dndn addresses it.
- **Multi-word static rule prefixes work** — `Bash(for id:*)` exists in settings.local.json and matches commands starting with `for id`. Confirmed: multi-word matching is supported. `Bash(bash -c:*)` would also work syntactically.
- **`Bash(bd:*)` DOES match `bd <subcommand>`** — empirically verified 2026-03-12 (Claude Code 2.1.74): `bd stats > /dev/null` auto-approved via `bd:*` static rule (redirect bypassed hook, proving static rule matched). Prior claim that `bd:*` didn't match subcommands was wrong — the prompts were caused by $() being a hard heuristic, not by pattern mismatch. 13 planned per-subcommand rules dropped from permissive profile expansion plan.
- **`{"` in bd metadata does NOT trigger prompts** — `bd create --metadata '{"impact":...}'` does not trigger the "expansion obfuscation" heuristic in practice, despite containing `{"`. User confirmed never prompted for impact metadata. Contradicts theoretical expectation.
- **Cache tokens dominate Claude Code cost** — daily: 140M cache read vs 200k I/O tokens. Cache:I/O ratio ~710x. Effective Opus rate per I/O token (cache-inclusive): $493/M. Subagent ratio is lower (fresh context, ~50-100x estimated). Stats `tokens` field only captures I/O, not cache — per-agent cost requires the cache-inclusive rate. See `memory/cost-analysis.md`.
- **Task→Agent dispatch migration incomplete** — wgl (v2.1.0) only migrated deepen-plan + plan red-team. ~30 Task dispatches remain: brainstorm (8), review (7), plan (5), compound (8), work (2), plugin-changes-qa skill (5). Benefits: model from frontmatter, consistency, Agent tool features (worktree isolation). Not a capability or cost improvement — cleanup only. Tracked in bead 2kj.
- **`${CLAUDE_SKILL_DIR}` works in plugin skills, NOT in commands** — load-time string substitution, gives absolute path to skill directory. Empirically confirmed 2026-03-11: skill at `skills/do-test/SKILL.md` received `/Users/adamf/.claude/plugins/cache/.../2.6.1/skills/do-test`. Commands get literal `${CLAUDE_SKILL_DIR}` unsubstituted. `${CLAUDE_SESSION_ID}` works in both. Bash injection (`!`command``) works in neither.
- **`${CLAUDE_PLUGIN_ROOT}` is broken in markdown** — [GitHub #9354](https://github.com/anthropics/claude-code/issues/9354), open since Oct 2025, 20 comments, no Anthropic response. Only works in JSON configs (hooks.json, MCP). git-worktree and resolve-pr-parallel skills use it — those are broken in installed contexts.
- **`do:` namespace works in skill `name:` field** — `name: do:test` in `skills/do-test/SKILL.md` creates `/compound-workflows:do:test`. Short form `/do:test` works in autocomplete. Empirically confirmed 2026-03-11.
- **Upstream compound-engineering uses skills not commands** — `ce:brainstorm`, `ce:plan`, `ce:work`, `ce:review`, `ce:compound` are all skills. No scripts directory. No path resolution problem.
- **`$ARGUMENTS` / `#$ARGUMENTS` works in SKILL.md files** — substitution identical to commands. `#$ARGUMENTS` becomes `#<actual args>` — the `#` stays as literal text, not consumed. For clean output in skills, use `$ARGUMENTS` without the `#` prefix. Empirically confirmed 2026-03-12 during v3.0.0 prerequisite gate.
- **Squash-merge → `git branch -d` always warns "not fully merged"** — squash creates a new commit with different SHA than branch commits. Git can't tell the content was merged (only checks SHA reachability). Use `git branch -D` to force-delete. This is expected behavior, not an error.
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
- **v2.5.0** — Heuristic audit scope expansion (bead 3l7): init-values.sh (29 patterns), check-sentinel.sh (3 patterns), QA Check 5 expanded (skills+agents, backtick detection), 7 commands + 7 skills migrated. 51 $() patterns eliminated, 27 exempt markers removed, zero residuals. 5 subagent dispatches via worktree.

- **v2.6.1** — Permissionless bash generation (bead dndn) + heredoc hard heuristic fix: setup Step 8e injects Bash Generation Rules into project CLAUDE.md on opt-in, 8 avoidance patterns in resources/bash-generation-rules.md, complementary static rule suggestions. Heredoc fix: append-snapshot.sh replaces Read+Write approach, hard vs soft heuristic distinction in Permission Architecture. `<<` is unsuppressible by static rules.

- **v3.0.0** — Commands→skills migration: 8 workflow commands migrated from `commands/compound/` to `skills/do-*/` using `${CLAUDE_SKILL_DIR}` for path resolution. Namespace `compound:` → `do:`. Thin alias redirects for backwards compat. init-values.sh PLUGIN_ROOT validation. QA Check 2b (skill-to-skill validation). 5 existing skills updated to `${CLAUDE_SKILL_DIR}`. 41 files changed. Tier 1+2 QA clean.

- **v3.0.5** — Permissive profile expansion (bead u1fd): 11 new rules (git, ls, mkdir, md5, bd, if, for, [[, xargs, tee, WebFetch). Standard add-on gains ls + 4 safe git patterns (log, diff, status, branch). Step 0 verification: $() is hard heuristic, bd:* matches subcommands, cp with flags is hard. 13 planned bd subcommand rules dropped.

- **v3.0.6** — Write tool discipline (bead dj65): 10 violation fixes (2 heredoc, 4 echo-redirect, 4 unspecified-commit) across 7 skill files. New `write-tool-discipline.sh` QA script (Tier 1 count 8→9). `migrate-stats-keys.sh` for script delegation. Tier 1 scan scope expanded to `skills/*/workflows/*.md` in 4 scripts. Truncation-check workflow file type added.

- **v3.1.0** — Session-end capture + compact-prep batch refactor (bead ka3w): two-phase architecture (check→batch→execute), 5 config toggles, inverted multi-select batch prompt, per-step retry/skip/abort, compound state persistence for resume, version actions separated from batch.

- **v3.1.1** — Compact-prep performance fix (bead rdij): direct memory writes (no temp files), immediate ccusage snapshot in check phase. Eliminates ~15min overhead from deferred temp-file pattern.

- **v3.1.2** — Stats capture worktree path fix (bead j6ui): make STATS_FILE absolute via compute_repo_root() in init-values.sh. Fixes capture-stats.sh writing to nonexistent directory in worktrees.

## In-Progress Work

- **Work-step-executor: Sonnet subagents (bead xu2)** — P1. ~80% of work steps are mechanical after well-deepened plans. voo done — dataset now available. Next: `/do:brainstorm`.
- **Downgrade analytical agents to Sonnet (bead sze8)** — P1. Blocked by wtn. Candidates: semantic-checks, spec-flow-analyzer, plan-readiness-reviewer, minor-triage. Red-team-opus stays Opus.
- **Setup bash rules assumes CLAUDE.md (bead jgb8)** — P2 bug. Step 8e injects into CLAUDE.md but projects using AGENTS.md need detection or user prompt.
- **Research agents need web search (bead ixz4)** — P2. Brainstorm/plan research agents don't search GitHub issues or official docs for upstream constraints. Caused miss on CLAUDE_PLUGIN_ROOT #9354.
- **Red team model selection (bead aig)** — P3. Brainstorm complete. Next: `/compound:plan`.
- **Correction-capture skill (bead rhl)** — P2. Next: `/compound:brainstorm`.
- **Plugin-wide config toggles (bead 4a1o)** — P3. Created during ka3w plan. Extends ka3w's config toggle pattern to other commands (red team, readiness, etc.).
- **User input gates before automated work (bead 42s)** — P2. Brainstorm complete. Next: `/compound:plan`.
- **Fix usage-pipe race + work-in-progress scoping (bead 8one)** — P2 bug. Plan complete (`docs/plans/2026-03-12-fix-usage-pipe-isolation-plan.md`). Next: `/do:work`. Two shared static files have race conditions under concurrent sessions. Fix: eliminate .usage-pipe (named-field string arg 9), scope .work-in-progress per-session (.work-in-progress.d/$RUN_ID directory). 13+ files in one atomic commit.

## Critical Patterns
- **Plugin paths use `${CLAUDE_SKILL_DIR}`** — skills use `${CLAUDE_SKILL_DIR}/../../scripts/` for init-values.sh. init-values.sh validates PLUGIN_ROOT via `.claude-plugin/plugin.json` existence check. Commands don't get CLAUDE_SKILL_DIR (they're thin aliases).
- **version-check.sh context detection** — in source repo: 3-way (source vs installed vs release). In consumer project: 2-way (installed vs release only).
- **`.beads/PRIME.md`** overrides bd prime to remove conflicting memory instructions
- **Pre-existing dispatch migration debt** — Tier 2 QA (jak session) found: brainstorm.md still uses Task dispatch for red team (plan.md/deepen-plan.md migrated to Agent dispatch in v2.1.0). Also `repo-research-analyst` Dispatched By column in CLAUDE.md missing "brainstorm". Not blocking but should be cleaned up.
- **p14 fixed (4qc9, v3.0.2)** — capture-stats.sh now distinguishes "no `<usage>` data" (informational) from "usage data present but unparseable" (format warning). Prior: every non-Task `<usage>` format triggered misleading "format may have changed" warning.
- **Sonnet appropriateness = planning gate, not implementation step** — model-robustness verification belongs in specflow + readiness checks during `/compound:plan`, not as a post-implementation review. Captured in wtn.
- **`<usage>` block has no cache fields** — Agent/Task completion notifications only include total_tokens, tool_uses, duration_ms. No cache_read_tokens or cache_creation_tokens. Per-dispatch cache data requires session JSONL mining (bead 3zr) or upstream feature request.
- **User is on Max 20x** — $200/month subscription, regularly exhausts weekly quota. Token costs in ccusage are a proxy for quota consumption, not actual charges. Sonnet downgrades are a throughput issue (quota wall stops all work), not a cost optimization.

## Dependency Chain
- xu2 unblocked (voo done — dataset available). Depends on 8sd(done), wtn.
- **5b6 closed** — audit complete. Relay agents already Sonnet, analytical agents are Sonnet candidates, red-team-opus stays.
- **sze8 created** — P1. Downgrade analytical agents to Sonnet. Blocked by wtn.
- **jgb8 created** — P2 bug. Setup Step 8e assumes CLAUDE.md, doesn't work for AGENTS.md users.
- **dndn closed** — v2.6.1. Permissionless bash generation implemented.
- **8sd closed** — classify-stats validated on full dataset (44 entries, 7 files). Unblocks xu2 and 5b6.
- **2kj created** — P3. Migrate ~30 remaining Task dispatches to Agent dispatch across 5 commands + 1 skill. Consistency/cleanup, not capability. brainstorm.md (8), review.md (7), plan.md (5), compound.md (8), work.md (2), plugin-changes-qa (5).
- **7k6 created** — P3. Hook to inject current date into session context. MEMORY.md date goes stale on resumed sessions from prior days.
- h0g unblocked (removed aig dependency)
- **3k3 absorbed into permission-prompt-optimization** — plan fully triaged: 4 CRITICAL + 7 SERIOUS from red team resolved, re-check clean, security sentinel + architecture strategist + code simplicity reviewers ran. Plan ready for work. Key changes: pipes/`$()`/heredocs/globs added to pre-checks, realpath adopted, profiles collapsed 3→2 (Standard/Permissive), hook shipped as template file, quote-aware tokenization specified.
- **a4pj created** — P3. Setup should inject Knowledge Precedence into project CLAUDE.md. 30m estimate.
- **a6t created** — P2. Agent timeout/recovery rules in plan command. Don't skip agents that are actively working.
- **cn5 created** — P3. Make stats collection off by default.
- **jak created** — P3. Audit plugin commands for heuristic-triggering patterns ($(), for loops, heredocs).
- **jed created** — P3. Audit log rotation for .hook-audit.log.
- **2g4 created** — P2. Config option to auto-create beads for deferred plan items.
- **4v2 created** — P2. Plan command should ensure all implementation details are specified (underspecifications block autonomous work execution).
- **yod created** — P1. Add precision-preservation principle to consolidation agent prompts (plan-consolidator, synthesis). Subagents don't read memory.
- **go4 created** — P2. Document permission threat model / risk envelope. Reverse-engineer from implemented practice (settings.json, setup profiles, hook design, heuristic-exempt decisions).
- **j6ui created** — P2 bug. Stats capture fails in worktrees — STATS_FILE path is relative. 10m fix.
- voo(done), 22l(done), 0ob(done), dud(done), 1q3(done), 4gq(done), n2q(done), 3co(done), d2l(done), awx(done)
