# Command Design Patterns

## Rationale Capture
All commands (brainstorm, plan, deepen-plan) must record the user's stated reasoning when they make decisions, not just the decision itself. User rationale evaporates with conversation context.

## Zero Untriaged Items
Principle across brainstorm, plan, deepen-plan: every finding/question must be explicitly resolved, deferred by user, or removed before handoff. Nothing silently applied, nothing accidentally skipped. Deferring is OK when user explicitly chooses it.

## Consolidated Triage (deepen-plan)
Synthesis findings AND red team findings go through the same triage flow. Summary first, then CRITICAL/SERIOUS individually, MINOR as batch.

## Work-Readiness Guidance
plan.md and deepen-plan.md handoffs assess step sizing for subagent dispatch. work.md Phase 1.1 checks plan structure (single-file builds, large steps, shared reference data) and flags concerns.

## Red Team Dispatch
- Three providers run independently in parallel — no provider reads another's critique (prevents anchoring)
- `clink` (Gemini CLI / Codex CLI) gives models direct file access — richer analysis
- `pal chat` lets you specify exact model. Preferred when user wants a specific model
- Provider method is a per-session runtime choice, not a stored preference
- CLIs need one-time per-repo file access permission

## QA Process
- AGENTS.md has 4 reusable parallel QA checks covering all 9 commands + stale refs + CLAUDE.md consistency
- Run after ANY change to commands, agents, or skills

## Release Process
1. Bump version in: plugin.json, marketplace.json, CHANGELOG.md, README.md, CLAUDE.md, AGENTS.md
2. Commit and push to main
3. Tag: `git tag -a v<version> -m "description"`
4. Push tag: `git push origin v<version>`
5. Update marketplace.json `ref` field to new tag
6. Commit and push the marketplace.json ref bump
- marketplace.json uses `git-subdir` source with explicit `ref` — users get the pinned version, not HEAD
- GitHub releases are NOT needed — Claude Code plugins install via git clone, not release artifacts

## Skill Visibility
- `user-invocable: false` hides skills from command palette
- `disable-model-invocation: true` prevents Claude auto-triggering but still shows in palette
- Reference-only skills need both flags if they shouldn't be invocable by anyone

## Beads in Worktrees
- `bd init` must run in main repo first, worktrees share the .beads database
- `bd create` priority range is 0-4 (P0-P4), not arbitrary numbers
- Pre-commit hook shim: use `bd hooks run pre-commit` (not `bd hook pre-commit`)

## /recover Command (v1.6.0)
- Dead sessions only (not post-compaction — that's compact-prep's job)
- Head 5 + tail 30 JSONL parsing, 50KB budget, 2KB per entry cap
- Writes recovery manifest to .workflows/recover/<session-id>/
- Outputs exact command string for replay (commands can't invoke other commands)
- Includes memory extraction step (fills compact-prep gap)
- No --flags — use AskUserQuestion for configurability
