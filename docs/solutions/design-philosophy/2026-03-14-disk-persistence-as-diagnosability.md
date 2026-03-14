---
title: "Disk Persistence Reframes from Technical Constraint to Diagnosability Guarantee"
date: 2026-03-14
category: design-philosophy
tags:
  - traceability
  - self-diagnosis
  - disk-persistence
  - workflow-archaeology
confidence: high
actionability: high
trigger: "README review — 'Research traceability | Retained across sessions' undersold actual value"
---

# AI Mistakes Become Diagnosable

## The Insight

Most AI tools are black boxes. When the output is wrong, you shrug and re-prompt. compound-workflows is different: every workflow phase writes its full reasoning to `.workflows/`, so when things go wrong the agent can trace its own reasoning back through the artifacts to find where things diverged.

The user asks "where did things go wrong with this plan?" and the agent reads through `.workflows/`, cross-references brainstorm research against red team challenges against plan decisions, and identifies the gap. The agent does the archaeology — not the user.

## Three Layers

1. **Disk persistence enables traceability** — brainstorm research, red team challenges, plan analysis, deepen-plan findings all persist to `.workflows/`. This creates a complete reasoning chain on disk.

2. **The agent can self-diagnose** — with persisted artifacts, the agent itself reads `.workflows/` and traces where reasoning diverged from reality. This is machine-readable self-inspection, not just human-readable logging.

3. **This justifies the architecture** — disk persistence, committing `.workflows/` in user projects, and context-lean design all serve this principle. Context-lean isn't just about fitting in the context window — it's about making every reasoning step independently inspectable.

## Reframing Existing Decisions

| Decision | Previous justification | Reframed justification |
|----------|----------------------|----------------------|
| Disk persistence to `.workflows/` | Keep context small | Make reasoning traceable and self-inspectable |
| Committing `.workflows/` in user repos | Preserve artifacts across sessions | Enable cross-session diagnosis of reasoning failures |
| Context-lean subagent design | Avoid context overflow | Force each reasoning step to produce a standalone, inspectable artifact |

## Why "Diagnosable" Over Alternatives

| Term | Why rejected |
|------|-------------|
| "Traceability" | Too mechanical — focuses on the mechanism, not the value |
| "Audit trail" | Implies human inspection — misses the key insight that the *agent* does the diagnosis |
| "Self-debugging pipeline" | Viable but "diagnosable" is more precise — describes the property, not the mechanism |

"AI mistakes become diagnosable" describes the user-facing outcome in plain language.

## Evidence: The Principle in Practice

### s7qj — Tracing Where a Plan Missed Infrastructure Concerns

The worktree-per-session isolation plan went through 8 review iterations and still missed that adding a new skill requires `/do:setup` changes. The post-mortem traced exactly which review layer missed what and why, because all review artifacts were on disk:

- Gemini flagged hook installation in its red team review (traceable in `.workflows/`)
- The orchestrator dismissed it (traceable in conversation + synthesis)
- The user pushed back (traceable in conversation)

Every review layer's blind spot was identified by examining the persisted artifacts.

### Deepen-Plan Iteration Taxonomy — Diagnosing Convergence Failures

By analyzing `.workflows/deepen-plan/` synthesis outputs from 12 deepen-plan runs (~112 agents), the investigation traced exactly why plans weren't converging: rounds 1-3 were genuine domain errors, rounds 4+ were edit-induced inconsistencies. Category 3 (edit-induced) was identified as the dominant driver by examining which findings in late rounds referenced changes made in earlier rounds.

Without disk persistence, classifying 112 agents' findings into 5 categories would have been impossible — the findings would have been lost to context compaction.

## The Diagnosability Test

Before any architectural decision, ask:

> **If this workflow produces a wrong answer next week, can the agent trace back through disk artifacts to find where reasoning diverged?**

If the answer is "no" or "only partially," the change creates a diagnosability gap.

## What Would Weaken the Principle

| Weakness | Early Warning |
|----------|---------------|
| `.workflows/` files become too large to read | Monitor agent output sizes. Current: 50-500 lines. Alert if >1000 |
| Context-lean summaries lose the reasoning chain | After a bad outcome, attempt a trace. If the orchestrator can't connect phases without reading disk files, summaries are too thin |
| Agents stop writing "why" and only write "what" | Periodically sample outputs for evidence citations |
| Cross-reference rot (paths change) | Same mechanism as edit-induced inconsistencies from the iteration taxonomy |

## What Would Strengthen the Principle

| Enhancement | Effect |
|-------------|--------|
| Explicit provenance links between phases | Each phase's output includes "Sources" listing exact `.workflows/` files that informed it |
| A `/do:trace` command | Automates the archaeology: given a bad outcome, walks backward through `.workflows/` |
| Manifest files per workflow run | Lists all artifacts, creation order, and which fed into which |
| Structured decision markers in agent output | `[DECISION]` tags make divergence points findable without reading entire files |

## Structural Durability

The cost-benefit brainstorm (2026-03-11) classifies research traceability as **structurally durable** — persisting regardless of model quality:

> "Research traceability (.workflows/) — Audit trails have value independent of model quality. 'Why did we decide X?' needs a durable record regardless of how smart the model is."

Diagnosability is an organizational need (accountability, learning), not a model limitation (compensating for mistakes). Even if models become much better, the ability to trace reasoning remains valuable.

## Where This Principle Is Declared

- **Plugin CLAUDE.md**: Design Philosophy section (first section, before Versioning)
- **Plugin README.md**: Feature table row + expanded traceability bullet under Disk-Persisted Agents
- **Root README.md**: Traceability as differentiator

## Related Documents

- `plugins/compound-workflows/skills/disk-persist-agents/SKILL.md` — the technical mechanism
- `docs/solutions/process-analysis/2026-03-08-deepen-plan-iteration-taxonomy.md` — diagnosability in practice
- `docs/solutions/process-analysis/2026-03-14-plan-vs-deepen-role-separation.md` — s7qj post-mortem
- `docs/brainstorms/2026-03-11-compound-workflows-cost-benefit-brainstorm.md` — structural durability classification
- `docs/brainstorms/2026-03-08-finding-resolution-provenance-brainstorm.md` — provenance gap-fill
