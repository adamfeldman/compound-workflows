# Bead Estimation Heuristics

When creating beads, estimate total remaining workflow time in minutes using `--estimate N`.

## Per-Phase Timings (empirical, 2026-03-10)

| Phase | Duration | Notes |
|-------|----------|-------|
| Brainstorm | ~45 min | With red team (~5-6 min for 3 providers) |
| Plan | ~25-35 min | Research + write + readiness checks |
| Deepen-plan | ~30-45 min | Agent swarm (~15-25 min) + synthesis + red team + convergence |
| Work | ~30-120 min | Varies hugely by scope. Single command file: ~30-60 min. Multi-file/multi-command: ~60-120 min |
| Work (jak data) | ~10 min | 8 dispatches: 6 parallel (19-67s each, wall ~67s) + step 7 (341s) + step 8 (48s). Well-specified plan with exact old/new text → fast execution. |
| Review | ~15-20 min | Multi-agent parallel review |

## Estimation Formula

Sum remaining phases based on the bead's "Next" step:

- **Next: Brainstorm** → brainstorm + plan + work = ~100-200 min
- **Next: Plan** → plan + work = ~55-155 min
- **Next: Deepen-plan** → deepen + work = ~60-165 min
- **Next: Work** → work only = ~30-120 min
- **Next: Research/audit** → ~30-60 min (no build phase)
- **Bug fix** → ~30-60 min (usually straight to work)

## Adjustment Factors

- **Multi-command scope** (touches brainstorm + plan + deepen-plan): +50%
- **Well-scoped, single-file change**: use lower bound
- **Needs deepen-plan?** Add ~30-45 min. Skip if: brainstorm was thorough, plan is simple, red team in plan covers validation needs
- **Has dependencies**: estimate only this bead's work, not the dependency chain

## Early Cost Savings Analysis (2026-03-10)

From ccusage daily data for a session that ran brainstorm + red team + triage:

| Model | Cost | Tokens |
|-------|------|--------|
| Opus 4.6 | $14.49 | 21M |
| Sonnet 4.6 | $1.99 | 2.2M |
| **Total** | **$16.48** | **23.2M** |

Sonnet is ~5x cheaper than Opus per token. If those 2.2M Sonnet tokens had run on Opus: ~$10. **Savings: ~$8 (~33%) by running research agents and red-team-relay on Sonnet.**

This is from the v2.0.0 workflow quota optimization (bead 22l) which moved 5 research agents + red-team-relay to `model: sonnet`. The savings are real but this is a single day's aggregate — can't break down by agent or phase without voo (per-agent instrumentation). Bead 5b6 will audit for additional cheaper-model opportunities beyond the 6 agents already on Sonnet.

**Projection:** If more dispatches can safely use Sonnet/Haiku (e.g., MINOR triage subagents, readiness check agents, specflow analyzer), the 33% savings could grow to 40-50%. Needs empirical validation from voo data.

## Data Source

These timings are rough estimates from session observation. Bead 3zr will mine JSONL session logs for empirical data. Update this file when better data is available.
