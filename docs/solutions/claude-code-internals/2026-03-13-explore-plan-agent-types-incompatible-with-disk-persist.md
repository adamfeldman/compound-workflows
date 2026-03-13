---
date: 2026-03-13
category: claude-code-internals
tags: [agent-types, explore-agent, plan-agent, disk-persist-pattern, write-tool, platform-constraints, subagent-architecture, context-lean]
fragility: MEDIUM — Explore/Plan tool restrictions are undocumented but stable; could change in any Claude Code release
verification_cadence: after Claude Code updates that mention agent types
reuse_triggers:
  - considering switching subagents from general-purpose to Explore or Plan
  - evaluating new Claude Code built-in agent types for plugin use
  - debugging subagent failures where Write tool calls are rejected
  - reviewing disk-persist architecture assumptions
  - cost audits of plugin token usage
---

# Explore and Plan Agent Types Are Incompatible with the Disk-Persist Pattern

## Finding

Claude Code's built-in `Explore` and `Plan` agent types lack the Write tool. The compound-workflows plugin's disk-persist pattern requires every subagent to Write findings to `.workflows/` files. This makes Explore/Plan incompatible with the plugin's architecture — not as an oversight, but as a structural consequence of the context-lean design.

## Built-In Agent Types

Claude Code provides 4 built-in agent types:

| Type | Purpose | Key Tool Restrictions |
|------|---------|----------------------|
| `general-purpose` | Multi-step tasks, research, code search | None — full tool access |
| `Explore` | Fast codebase exploration | No Agent, Edit, Write, NotebookEdit |
| `Plan` | Architecture and design | No Agent, Edit, Write, NotebookEdit |
| `statusline-setup` | Status line config | Only Read, Edit |

Explore is described as "fast" — likely uses a smaller/cheaper model (possibly Haiku).

## Why This Matters

The plugin dispatches ~27 subagents, all as `general-purpose`. An audit found 17+ are functionally read-only (they don't edit source code or spawn sub-agents). At first glance, these seem like natural Explore candidates. But "read-only with respect to source code" is not the same as "doesn't need Write."

Every agent in the plugin follows the disk-persist pattern:

```
Write your COMPLETE findings to: .workflows/<command>/<run>/agents/<name>.md
Return ONLY a 2-3 sentence summary.
```

This pattern requires the Write tool. Without it, agents would need to either:
1. Return full results in the response — defeating disk-persist (orchestrator context bloat)
2. Use Bash `cat >` to write — violating Claude Code conventions and triggering permission prompts

## Alternatives Evaluated

| Alternative | Verdict | Reason |
|-------------|---------|--------|
| Return results in response | Rejected | Defeats disk-persist. Orchestrator would bloat with 1000+ token outputs per agent, triggering compaction in multi-agent workflows. |
| Use Bash `cat >` to write | Rejected | Violates conventions, triggers permission heuristics (redirect `>` combined with content), fragile for multi-line markdown. |
| Stay with `general-purpose` | Accepted | Correct choice given the architectural constraint. |

## Why the Incompatibility Runs Deep

Six reinforcing design decisions make this structural, not incidental:

1. **Disk-persist requires Write** — `disk-persist-agents/SKILL.md` mandates the Write tool for OUTPUT INSTRUCTIONS
2. **Context-lean is zero-exceptions** — `plugins/compound-workflows/CLAUDE.md` allows no carve-outs
3. **QA enforces OUTPUT INSTRUCTIONS** — `context-lean-grep.sh` auto-catches dispatches missing the block
4. **Agent discovery uses named agents** — native-agent-discovery chose `compound-workflows:review:*` patterns over built-in types
5. **Model optimization uses frontmatter** — cost control happens via `model` field in agent YAML, not agent type switching
6. **Research quality requires Sonnet** — `decision_keep-research-agents-on-sonnet.md` argues against Haiku, which is Explore's likely default

## When to Revisit

| Trigger | What Changed |
|---------|-------------|
| Claude Code grants Write to Explore/Plan | Core incompatibility removed |
| New built-in type that is cheap + has Write | Cost benefit without architectural conflict |
| Plugin adds non-disk-persist agents | Those specific agents could use Explore |
| Plugin abandons disk-persist | All agents become Explore/Plan candidates |
| New persistence mechanism (e.g., structured output API) | May bypass Write tool requirement |

## Related Documents

| Document | Relevance |
|----------|-----------|
| `plugins/compound-workflows/skills/disk-persist-agents/SKILL.md` | Defines Write-dependent OUTPUT INSTRUCTIONS pattern |
| `plugins/compound-workflows/CLAUDE.md` | Context-lean zero-exceptions policy |
| `docs/brainstorms/2026-03-08-context-lean-enforcement-brainstorm.md` | Origin of "context-lean" principle |
| `docs/plans/2026-03-08-feat-context-lean-enforcement-plan.md` | QA enforcement infrastructure |
| `plugins/compound-workflows/skills/orchestrating-swarms/SKILL.md` | Documents Explore/Plan types; marked beta |
| `docs/brainstorms/2026-03-09-native-agent-discovery-brainstorm.md` | Named agents over built-in types |
| `docs/brainstorms/2026-03-09-workflow-quota-optimization-brainstorm.md` | Model routing via frontmatter |
| `memory/decision_keep-research-agents-on-sonnet.md` | Quality argument against Haiku |

## Investigation Origin

Triggered by noticing the plugin documents Explore agents in its `orchestrating-swarms` teaching skill but never uses them internally. The inconsistency between teaching and practice was a reasonable signal for investigation, but the exclusion is justified by the disk-persist constraint.
