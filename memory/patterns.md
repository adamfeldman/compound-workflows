# Command Design Patterns

## Rationale Capture
All commands (brainstorm, plan, deepen-plan) must record the user's stated reasoning when they make decisions, not just the decision itself. User rationale evaporates with conversation context.

## Zero Untriaged Items
Principle across brainstorm, plan, deepen-plan: every finding/question must be explicitly resolved, deferred by user, or removed before handoff. Nothing silently applied, nothing accidentally skipped. Deferring is OK when user explicitly chooses it.

## Consolidated Triage (deepen-plan)
Synthesis findings AND red team findings go through the same triage flow. Summary first, then CRITICAL/SERIOUS individually, MINOR as batch.

## Work-Readiness Guidance
plan.md and deepen-plan.md handoffs assess step sizing for subagent dispatch. work.md Phase 1.1 checks plan structure (single-file builds, large steps, shared reference data) and flags concerns.

## Context-Lean Principle
- Canonical term: "context-lean" (not "disk-persisted" or "context-safe")
- All commands dispatching agents MUST include OUTPUT INSTRUCTIONS blocks
- TaskOutput is banned — poll file existence instead
- MCP tool responses must be wrapped in subagents (empirically confirmed: Task subagents DO inherit MCP tool access)
- Swarms skill is beta/unreviewed — broader review tracked for when swarms go GA

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
