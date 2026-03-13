---
name: Keep research agents on Sonnet, not Haiku
description: Decision to keep the 5 research agents + relay on Sonnet rather than downgrading to Haiku — quality tradeoff not worth the modest savings
type: project
---

**Decision (2026-03-13):** Do not move research agents back to Haiku. Keep them on Sonnet.

**Why:** The v2.0.0 change (bead 22l) *promoted* context-researcher and learnings-researcher from Haiku to Sonnet because Haiku summaries were "too thin." Moving back reverses the quality fix. The 5 research agents + relay are already the cheapest dispatches — savings from Haiku would be ~$1-2/cycle, negligible against the orchestrator cost elephant (50-70% of total spend).

**Risk of Haiku:** Research agents feed into plans and brainstorms. Thin summaries → worse upstream documents → more iterations → more Opus tokens spent fixing gaps. Context-researcher and learnings-researcher surface institutional knowledge — if they miss nuance, the compounding benefit of docs/solutions/ degrades.

**How to apply:** If quota pressure resurfaces, the higher-leverage moves are: (1) reducing orchestrator context size, (2) being more selective about which review agents fire during deepen-plan, (3) Tier 1/2 dynamic routing for analytical agents (beads xu2, sze8). Not downgrading research agents.

See `memory/cost-analysis.md` for full token economics.
