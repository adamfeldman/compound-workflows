---
title: "Compound Workflows Cost vs Benefit — Adaptive Ceremony"
type: analysis
status: active
date: 2026-03-11
---

# Compound Workflows Cost vs Benefit — Adaptive Ceremony

## What We're Exploring

What benefit does the compound-workflows plugin provide vs. "just using Claude Code normally"? The plugin imposes a token and time cost through its multi-agent dispatch, quality gates, and structured ceremony (brainstorm → plan → deepen-plan → work → review). Is this overhead justified? When is it overkill? And as models get better and cheaper, which parts of the plugin are compensating for current model limitations vs. providing structurally durable value?

### Motivation (all four dimensions)

1. **Quota pressure (a):** User is on Max 20x ($200/month). Regularly exhausts weekly quota. The ceremony eats tokens — would simpler sessions stretch the quota further? (Increasing quota is an option for the cost dimension but doesn't address quality or knowledge compounding.)
2. **Quality ROI (b):** Do readiness checks, red team, deepen-plan rounds actually catch enough real issues to justify the overhead? User reports being "frustrated with the non-compound output" quality — suggesting the ceremony IS buying something.
3. **Knob settings (c):** When should you use full ceremony vs. skip brainstorm/skip red team/skip deepen-plan? Currently it's all-or-nothing.
4. **Generalizability (d):** Does this plugin make sense as a general tool, or is it only justified for specific use cases (quota-constrained, complex-workflow, solo developer)?

### The User's Key Insight

> "We have to skate where the puck is going. Models are getting better and cheaper."

This reframes the analysis fundamentally. Don't optimize for today's constraints — ask which parts of the plugin are future-proof and which are technical debt against improving models.

## Empirical Cost Data

### Per-Command Agent Dispatch Counts

| Command | Agents Dispatched | Token Range (I/O) | Wall-Clock (estimated) |
|---------|-------------------|-------------------|----------------------|
| brainstorm | ~6 (2 research + 3 red team + 1 triage) | ~257k standard, ~390k with extras | ~45 min |
| plan | ~10-14 (2-4 research + 1 specflow + 2-4 readiness + 3 red team + 1 triage + 1 consolidator) | ~484k measured | ~25-35 min |
| deepen-plan | ~15-27 (dynamic discovery of up to 19 research/review agents + synthesis + readiness + red team) | Not measured end-to-end | ~30-45 min |
| work | ~5-11 (1 per plan step + optional reviewer) | ~152k measured (3 steps) | ~30-120 min |
| review | ~7-10 (parallel specialized reviewers) | Not measured end-to-end | ~15-20 min |
| **Full cycle** | **~31-38 agents** | **~600k-1M+ I/O tokens** | **~100-200 min** |

Sources: `.workflows/stats/` YAML files (10 files, 44 classified entries), `memory/estimation-heuristics.md` (rough session observations — not precisely measured).

### Wall-Clock Data Quality Note

The per-phase wall-clock times (brainstorm ~45 min, plan ~25-35 min, etc.) are from `memory/estimation-heuristics.md`, which states: "These timings are rough estimates from session observation." The stats files have `duration_ms` per agent dispatch, but that captures only the subagent's execution time, not the orchestrator time between dispatches (reading outputs, triaging findings, user interaction). No reliable end-to-end wall-clock data exists for full command runs. Bead 3zr (session JSONL mining) would provide this.

### Measured Agent-Level Data

#### Brainstorm run (permissionless-bash-generation, 2026-03-11)

| Agent | Model | Tokens (I/O) | Duration |
|-------|-------|-------------|----------|
| repo-research-analyst | sonnet | 86,337 | 213s |
| context-researcher | sonnet | 90,127 | 148s |
| general-purpose (jsonl-analysis) | opus | 132,564 | 341s |
| red-team-relay (gemini) | sonnet | 18,821 | 122s |
| red-team-relay (openai) | sonnet | 16,793 | 93s |
| general-purpose (red-team-opus) | opus | 18,580 | 91s |
| general-purpose (minor-triage) | opus | 26,708 | 63s |
| **Total** | | **389,930** | ~1,071s (~18 min agent-only) |

Note: Includes an extra jsonl-analysis agent (132k tokens) specific to that task. Standard brainstorm without it: ~257k tokens.

#### Plan run (heuristic-audit-scope-expansion, 2026-03-11)

| Agent | Model | Tokens (I/O) | Duration |
|-------|-------|-------------|----------|
| learnings-researcher | sonnet | 36,393 | 110s |
| repo-research-analyst | sonnet | 61,785 | 189s |
| spec-flow-analyzer | opus | 53,461 | 243s |
| semantic-checks | opus | 54,212 | 133s |
| plan-readiness-reviewer | opus | 33,317 | 81s |
| semantic-checks (verify) | opus | 29,738 | 120s |
| general-purpose (red-team-opus) | opus | 56,452 | 136s |
| red-team-relay (openai) | sonnet | 16,846 | 150s |
| red-team-relay (gemini) | sonnet | 19,011 | 206s |
| general-purpose (minor-triage) | opus | 37,040 | — |
| plan-readiness-reviewer (recheck) | opus | 32,784 | — |
| semantic-checks (recheck) | opus | 53,368 | 170s |
| **Total** | | **484,407** | ~1,538s (~26 min agent-only) |

#### Work run (feat-permission-prompt-optimization, 2026-03-10)

| Step | Model | Tokens (I/O) | Duration |
|------|-------|-------------|----------|
| 8zy | opus | 57,633 | 285s |
| qnu | opus | 54,384 | 146s |
| igp | opus | 40,488 | 55s |
| **Total** | | **152,505** | ~486s (~8 min) |

### Token Economics

| Metric | Value | Source |
|--------|-------|--------|
| Daily API-equivalent cost | $100-210/day | ccusage snapshots (2026-03-10: $209.74, 2026-03-11: $147.15) |
| Opus effective rate (cache-inclusive) | $493/M I/O tokens | memory/cost-analysis.md |
| Sonnet effective rate (cache-inclusive) | $67/M I/O tokens | memory/cost-analysis.md |
| Opus:Sonnet cost ratio | 7.4x | memory/cost-analysis.md |
| Cache:I/O ratio (daily aggregate) | ~710x | 141.9M cache / 200k I/O |
| Orchestrator share of total Opus cost | estimated 50-70% | Inferred — not directly measured |
| Subagent share | estimated 30-50% | Inferred — not directly measured |
| Subagent cache:I/O ratio (estimated) | 50-100x | Lower than orchestrator — fresh contexts |
| Sonnet share of daily cost | ~2-7% | ccusage data |

**Key insight:** The orchestrator (the user's conversation context, re-sent on every tool call) dominates cost, not the subagent dispatches. All subagent model routing optimizations (dynamic routing, Sonnet tiers) can only affect the 30-50% subagent slice. The 50-70% orchestrator slice is untouchable by dispatch-level optimization.

### Per-Cycle Cost Estimates

| Component | Estimated Cost | Confidence |
|-----------|---------------|-----------|
| Opus subagents per cycle | $50-100 | Medium (from classification data) |
| Orchestrator overhead per cycle | $100-200+ | Low (inferred from gap analysis) |
| Full brainstorm→plan→work cycle | $150-300+ | Low-medium |
| Sonnet agents per cycle | $5-15 | High (research + relay, already on Sonnet) |

## External Research

### Multi-Agent vs Single-Agent (Google/MIT, 2025)

From "Towards a Science of Scaling Agent Systems" — 180 agent configurations evaluated:

- Multi-agent coordination yields **+81% gains on parallelizable tasks** (e.g., financial analysis)
- For **sequential reasoning tasks, every multi-agent variant degraded performance by 39-70%**
- "Capability saturation": once a single agent hits ~45% success rate, adding agents brings diminishing or negative returns as coordination costs eat gains
- Independent agents amplify errors 17.2x; centralized coordination contains to 4.4x
- The framework predicted optimal coordination strategy at 87% accuracy based on task properties (sequential dependencies + tool density)

**Implication for compound-workflows:** The plugin's parallel dispatch (review agents, research agents, red team) maps to the "parallelizable" category where multi-agent shines. But the sequential orchestrator flow (brainstorm → plan → work) is fundamentally sequential — the degradation finding applies here and is underweighted in the brainstorm's framing (red team, Opus, Gemini). The capability saturation finding (~45% threshold) also deserves more attention: if Opus already achieves >45% success rate on plan quality, additional readiness/re-check agents may be in the diminishing returns zone.

Sources: [Google Research Blog](https://research.google/blog/towards-a-science-of-scaling-agent-systems-when-and-why-agent-systems-work/), [arXiv](https://arxiv.org/abs/2512.08296)

### AI Developer Productivity (METR, 2025)

METR recruited 16 experienced developers working on familiar open-source repositories:

- Developers using AI tools took **19% longer** than without
- Developers **perceived** AI sped them up by 20% — opposite of reality
- Less than 44% of AI generations were accepted
- Time spent reviewing, testing, and modifying AI output outweighed time saved
- Key caveat: these were experienced developers on codebases they'd contributed to for 5+ years with 1,500+ commits — "there may not be much room for AI to help here"

**Implication:** AI-assisted development has inherent overhead from review/cleanup, regardless of ceremony level. However, METR compared AI vs no-AI, not "ceremony vs no-ceremony" — using this study to directly support the plugin's ceremony value is a stretch (red team, Opus). It provides context on baseline AI costs, not evidence for structured workflows specifically.

Sources: [METR Blog](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/), [arXiv](https://arxiv.org/abs/2507.09089)

### Claude Code Cost Benchmarks (2026)

From Claude Code docs and community analysis:

- Average cost: ~$6/developer/day, below $12 for 90% of users
- Agentic usage consumes **5-20x more tokens** than standard completions
- Agent teams (~7x more tokens than standard) because each teammate maintains its own context window
- Key optimization: delegating to subagents so verbose output stays in subagent context, only summary returns to main conversation — this IS the context-lean pattern
- 90% discount on cached tokens is "a game-changer for agentic workflows"
- Well-written CLAUDE.md saves "thousands of tokens" per session by avoiding rediscovery

**Implication:** The plugin's context-lean architecture follows the recommended pattern from Anthropic's own docs. The 5-20x token multiplier for agentic usage means the plugin's overhead is within the expected range for agentic workflows, not an outlier.

Sources: [Claude Code Docs - Manage Costs](https://code.claude.com/docs/en/costs), [32blog - 50% Token Reduction](https://32blog.com/en/claude-code/claude-code-token-cost-reduction-50-percent)

### Context Window Management (2025-2026)

From Anthropic's engineering blog and agentic patterns research:

- "Agentic systems will most likely fail without explicit context management"
- Serialized state management: save compressed history, task graph, tool outputs to external storage; on resume, reconstruct minimal necessary context
- Session splitting: distinct agent sessions for different development phases — exactly the subagent dispatch pattern
- Claude Sonnet 4.5 "maintained focus for more than 30 hours on complex, multi-step tasks" — but this doesn't eliminate context management needs for multi-agent orchestration
- Models exhibit "context anxiety" — proactively summarize progress near context limits, sometimes making premature decisions

**Implication:** The plugin's disk-persist pattern and session recovery via beads implement the recommended approach. But as context windows grow and models handle longer sessions better, the compaction resistance benefit diminishes.

Sources: [Anthropic Engineering Blog](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents), [Agentic Patterns](https://agentic-patterns.com/patterns/context-window-anxiety-management/)

### AI ROI at Organizational Level (2025-2026)

- AI investments returned **$3.70 per dollar invested** on average (top performers: $10.30)
- 62% of teams see at least 25% productivity gains
- But: "AI coding assistants increase developer output, but not company productivity" — organizational bottlenecks (review, QA, security, integration) must also be addressed
- 67% of organizations using agents report productivity gains (DigitalOcean 2026 survey, 1,100 developers/CTOs)
- Knowledge loss during employee turnover costs up to 213% of salary — institutional knowledge capture has measurable value
- Teams see 20-30% more deployments with AI tools — the gain is in smaller, faster iterations

**Implication:** These broad organizational surveys provide useful context on where AI ROI comes from (knowledge retention, review quality, iteration speed), though transferability from large-team enterprise settings to a single-user plugin is unvalidated. The plugin's `/compound:compound` and structured review align with the factors these studies identify, but the studies don't directly validate this plugin's specific design.

Sources: [Index.dev - AI ROI](https://www.index.dev/blog/ai-coding-assistants-roi-productivity), [VentureBeat - Agent ROI](https://venturebeat.com/orchestration/ai-agents-are-delivering-real-roi-heres-what-1-100-developers-and-ctos), [SitePoint - AI ROI Calculator](https://www.sitepoint.com/ai-coding-tools-cost-analysis-roi-calculator-2026/)

## The "Skating Where the Puck Is Going" Analysis

### What erodes as models improve

These plugin components exist primarily to compensate for current model limitations. As models get better and cheaper, their value diminishes:

| Component | Why It Exists Today | What Erodes It |
|-----------|-------------------|----------------|
| **Context-lean / disk-persist** | Context windows exhaust during long sessions | Larger context windows + better compaction |
| **Robustness Principles #1-5** | Sonnet skips steps, conflates scope | Better instruction-following in cheaper models |
| **Dynamic model routing** | Wide Opus/Sonnet quality gap | Gap narrows → just use the cheap model |
| **Permission heuristics / script encapsulation** | Claude Code's current heuristic inspector | Implementation-specific — could change any release |
| **Readiness checks / semantic-checks** | Plan-writing model creates inconsistencies | Better models make fewer inconsistencies |
| **710x cache overhead** | Current prompt caching architecture/pricing | Flat-rate models, better caching, or different pricing |
| **deepen-plan rounds 4+** | Earlier rounds' edits introduce new inconsistencies (Category 3 from iteration taxonomy) | Better models that edit without introducing contradictions |

### What persists regardless of model quality

These components address structural problems that don't go away with better models:

| Component | Why It Persists |
|-----------|----------------|
| **Multi-perspective red team (3 providers)** | Different models always have different training biases. Blind spot diversity is structural, not capability-dependent. |
| **Institutional knowledge capture (`/compound`)** | Knowledge loss is an organizational problem — people leave, context evaporates, the same problems get re-solved. No model improvement fixes this. |
| **Structured decomposition (brainstorm → plan → work)** | Helps *humans* reason about complex tasks. The user needs to understand and approve the approach before execution. This is a human interface, not a model limitation. |
| **Session recovery (beads + disk state)** | Sessions will always end and restart — compaction, quota exhaustion, crashes, context switches. Durable task state across sessions is a persistence problem, not a capability problem. |
| **Research traceability (.workflows/)** | Audit trails have value independent of model quality. "Why did we decide X?" needs a durable record regardless of how smart the model is. |

### Uncertain — could go either way

| Component | Depends On |
|-----------|-----------|
| **Subagent specialization (26 domain-specific agents)** | If a single model handles all review domains equally well with a generic prompt, specialized agents add overhead without benefit. But if domain prompts continue to improve output quality, they persist. |
| **Stats capture** | Useful for cost optimization while costs matter. If costs become negligible (flat-rate, unlimited usage), measurement overhead isn't worth it. |
| **QA hook enforcement** | Useful while models make structural errors (truncated files, broken YAML). Better models = fewer structural errors = less need for deterministic enforcement. |

### The Philosophical Implication

The plugin's **enduring value** is in knowledge management and human-facing structure:
- `/compound:compound` — institutional knowledge capture
- Brainstorm → plan → work — human reasoning scaffold
- Beads — persistent task tracking
- .workflows/ — research traceability

The plugin's **most expensive part** — the multi-agent dispatch machinery (26 agents, quality gates, readiness checks, re-checks) — is the part most likely to become unnecessary as models improve.

This suggests the plugin should evolve toward **lighter orchestration + heavier knowledge capture**, rather than heavier quality gates.

## Central Design Direction: Adaptive Ceremony

### The Proposal: `/compound:start`

A new routing command that assesses a task and decides how much ceremony to apply:

```
/compound:start <task description>
```

Instead of the user deciding whether to run brainstorm → plan → deepen → work (full ceremony) or just "do it" (no ceremony), the plugin evaluates the task and routes to the appropriate tier.

### Routing Model: Hybrid Tiers + Per-Gate Overrides

The router uses a two-layer approach: **tiers set a default bundle** of ceremony gates, then **triggers override individual gates** up or down based on task-specific signals.

#### Tiers (Default Bundles)

Tiers are sensible starting points, not rigid presets. Each tier defines which ceremony gates are on by default:

| Tier | Name | Default Gates | Typical Task |
|------|------|--------------|--------------|
| 0 | **Raw** | None. Model just does the task directly. | Trivial: single-file bug fix, typo, config change. |
| 1 | **Lite** | Quick inline plan → work | Well-understood: existing patterns, user is confident. |
| 2 | **Standard** | Brainstorm → plan → work | Medium: some novelty, moderate scope. |
| 3 | **Full** | Brainstorm + red team → plan + readiness + red team → deepen → work → review | High-risk: architectural, multi-domain, high uncertainty. |

Each gate (brainstorm, red team, readiness, deepen, review) is independently toggleable. Tiers just set the defaults.

#### Escalation Triggers (Add Ceremony)

Specific signals force a gate on, regardless of tier:

| # | Trigger | Gate Added | Detection |
|---|---------|-----------|-----------|
| E1 | Risk domain detected | +red team | Configurable list in `compound-workflows.md` (defaults: auth, payments, migration, security) |
| E2 | No prior knowledge (fuzzy, conservative) | +brainstorm | Broadened search: `docs/solutions/`, `memory/`, `.workflows/`, git log, codebase patterns. Biased toward "no match" when uncertain — better to over-ceremony than miss something |
| E3 | User expresses uncertainty (confirmed) | +deepen | Router asks user to confirm: "You seem uncertain — add deeper research?" |
| E4 | Cross-domain change detected | +readiness, +review | Mid-execution trigger — detected during plan/work when files span multiple domains. User confirms escalation |

#### De-escalation Triggers (Skip Ceremony)

Specific signals let a gate be skipped:

| # | Trigger | Gate Removed | Detection |
|---|---------|-------------|-----------|
| D1 | Prior knowledge exists | −brainstorm | High-confidence match across broadened search (solutions > memory > .workflows > git > codebase). Source quality weighted — compounded solution is strong signal, git commit message is weak |
| D2 | Single file/directory change | −multi-domain review | Scope assessment |
| D3 | User states high confidence (confirmed) | −brainstorm, −deepen | Router asks explicitly: "Run lighter? (y/n)" |
| D4 | Pattern-following change | −brainstorm, −deepen | Structural heuristic (similar files in target dir) + user confirms. Does NOT skip readiness — readiness validates the plan itself, not the novelty of the task |

#### Override Rules

- **Soft floor:** De-escalation cannot silently drop below the tier's default gates. Requires user confirmation: "This could run at Tier 1 instead — drop down? (y/n)"
- **Escalation is automatic** but always shown transparently (see Display below)
- **User can override any trigger** in either direction
- **New triggers emerge from feedback:** when the feedback loop shows repeated manual overrides in the same direction, that pattern becomes a candidate for a new trigger

#### Display: Summary + Detail

The router shows its decision in two layers:

**Summary line** (always shown):
```
Tier 2 (standard) + red team at plan (auth/) − deepen (prior solution exists)
```

**Detailed reasoning** (shown below summary):
```
  ↑ red team: plan touches plugins/compound-workflows/commands/ which imports auth middleware
  ↓ deepen: docs/solutions/auth-middleware-pattern.md matches this problem class
  → readiness: kept (default for Tier 2) — validates plan quality regardless of novelty
```

User confirms or overrides before execution proceeds.

#### Cold Start and Knowledge Gaps

The trigger system depends on accumulated project knowledge (`docs/solutions/`, `memory/`, `.workflows/`). For new users or sparse knowledge bases:

- **E2 (no prior knowledge):** When knowledge base is empty, everything escalates. This is the safe direction — new users get more ceremony, not less. As they compound solutions, the system naturally de-escalates.
- **D1 (prior knowledge exists):** Never fires with an empty knowledge base. No harm — other de-escalation paths still work (confidence, pattern-following, scope).
- **Compound nudge:** At task completion, if no matching prior knowledge was found during routing, the router suggests: "No prior solution exists for this problem class. Worth compounding? (y/n)" This creates a virtuous cycle: more compounding → better routing → less wasted ceremony → more capacity for compounding.

#### Configuration

Settings in `compound-workflows.md`:

```yaml
ceremony:
  # Coarse knob — shifts default tier assessment up or down
  bias: balanced  # conservative | balanced | aggressive

  # Gates that can never be skipped, regardless of tier or de-escalation triggers
  # User controls safety level — no hardcoded floors
  required_gates: [readiness]

  # Risk domains that trigger escalation (E1)
  # Overrides defaults — set your own list for your project
  risk_domains: [auth, payments, migration, security]

  # De-escalation triggers to disable entirely
  disabled_triggers: []
  # disabled_triggers: [D3]  # example: never skip brainstorm on confidence alone

  # Freeform rules — evaluated by the router alongside structured triggers
  # Use for project-specific judgment calls that don't fit the schema
  custom_rules: |
    - Any change to the plugin's commands/ directory should always get red team.
      These are 400-line prompt files where subtle wording changes can break behavior.
    - Skip brainstorm for CHANGELOG and README-only changes.
    - Tasks that only touch test files can drop to Tier 0.
    - If a task involves a new MCP tool, always run deepen-plan —
      MCP integration has surprised us before with edge cases.
```

**Design principles:**
- User is in charge — safety is configurable downward, no hardcoded floors
- Structured config for binary/enum decisions (bias, required gates, risk domains, disabled triggers)
- Prose rules for qualitative judgment calls that don't fit a schema
- If a prose rule conflicts with structured config, prose wins (user intent is more specific)
- Prose rule outcomes show in the detailed reasoning display

### What This Buys

1. **Quota efficiency (a):** Small tasks stop paying the 31-agent tax. A Tier 0 task costs ~0 extra tokens. A Tier 1 task costs maybe 50-100k tokens (one work subagent with a quick plan). Only Tier 3 pays the full ~600k-1M.

2. **Quality ROI (b):** The ceremony is applied proportionally. High-risk tasks get full quality gates. Trivial tasks skip ceremony entirely. Triggers catch edge cases the tier alone would miss (auth change at Tier 1 → escalate red team).

3. **Knob settings (c):** The user doesn't need to know the right knob — the routing command decides. But the user can override any decision, and the config lets them tune the system to their project.

4. **Generalizability (d):** New users describe the task, the plugin routes appropriately. The learning curve flattens. Config lets different projects (high-stakes enterprise vs solo side project) tune ceremony to their risk tolerance.

5. **Future-proofing:** As models improve, the routing thresholds shift. Today's Tier 2 becomes tomorrow's Tier 1. The tier boundaries and trigger sensitivities are the tunable knobs — the architecture doesn't change, only the calibration.

### The Future Vision

As models improve:
- Tier boundaries shift downward (more tasks qualify for lighter tiers)
- Quality gates thin out (readiness checks, deepen-plan rounds become unnecessary)
- The durable core remains: knowledge capture, human-facing structure, session recovery, research traceability
- Eventually the plugin becomes primarily a knowledge management tool with optional orchestration, rather than an orchestration tool with knowledge management bolted on

### Interaction with Existing Commands

`/compound:start` would be the new entry point, replacing the user's current decision of "which command do I run first?"

| Current User Decision | With `/compound:start` |
|----------------------|----------------------|
| "Is this worth brainstorming?" → `/compound:brainstorm` | Describe task → routing decides |
| "I know what to build" → `/compound:plan` | Describe task → routing skips brainstorm |
| "Just do this one thing" → raw Claude Code | Describe task → routing says "Tier 0, just do it" |
| "This is complex and risky" → full pipeline | Describe task → routing says "Tier 3, full ceremony" |

Existing commands remain available for direct invocation when the user wants to override routing.

## Counterfactual: "Just Using Claude Code Normally"

### What we know

- The user reports being **"frustrated with non-compound output"** — the quality difference is felt, even if not quantified
- METR study: experienced developers were 19% slower with AI tools on familiar codebases (mainly from review/cleanup overhead)
- No controlled comparison exists in this project: "workflow with ceremony" vs "ad-hoc iteration without ceremony" for equivalent tasks

### What "normal" looks like (estimated)

Without the plugin, a medium-complexity feature on Claude Code would involve:
- User describes the task
- Model reads files, proposes changes
- User reviews, requests corrections
- Iterate 3-10 times until satisfied
- No structured planning → model may go in wrong direction, requiring backtracking
- No red team → blind spots in the approach ship to implementation
- No institutional knowledge capture → same class of problem gets re-solved next time
- No session recovery → if context compacts mid-task, user manually re-orients

### The hidden costs of no ceremony

The following are hypothesized costs, not measured outcomes. Each would need empirical validation:

1. **Rework loops:** Without a plan, the model may build the wrong thing. Rework may cost more tokens than the planning ceremony would have. The deepen-plan iteration taxonomy found that rounds 1-3 catch genuine domain errors — these would likely become rework iterations in a no-ceremony workflow.

2. **Context exhaustion:** Long ad-hoc sessions accumulate context. Compaction mid-task may lose progress. The user would need to manually reconstruct state — or start over.

3. **Knowledge loss:** No `/compound:compound` means the same problem may get re-solved. The estimation-heuristics memory notes: "First occurrence: Research (30 min). Document: 5 min. Next occurrence: Quick lookup (2 min)."

4. **Review quality:** A single model reviewing its own work likely catches fewer issues than 7-10 specialized review agents + 3 external providers. The red team has documented cases of catching CRITICAL issues before implementation, though the marginal catch rate of ceremony over self-review is not quantified.

5. **The perception gap:** Per METR, developers think AI is making them faster even when it isn't. The structured ceremony may be more efficient than perceived "fast" ad-hoc iteration — but METR measured AI vs no-AI, not ceremony vs no-ceremony.

### The honest gap

We don't have hard data for the counterfactual. The above is reasoned but not measured. A controlled experiment (same-complexity task, one with ceremony, one without, measure tokens + time + quality) would be definitive but hasn't been done. The user's qualitative report ("frustrated with non-compound output") is the strongest evidence that the quality difference is real.

## Resolved Questions

1. **What should the routing model be?** → **Opus.** The routing assessment runs in the user's orchestrator context (already Opus). The routing decision is lightweight — no separate dispatch needed. The Opus orchestrator is already paying context cost; adding a routing assessment is nearly free.

2. **How does Tier 0 interact with plugin infrastructure?** → **Yes, by default.** The plugin exists to help track work and compound it overall. Even at Tier 0 (raw execution), beads tracking and `/compound:compound` remain available. The knowledge capture layer is always-on — it's the plugin's enduring value. Tier 0 means "skip ceremony," not "skip the plugin." Reason: institutional knowledge capture shouldn't depend on task complexity. A trivial bug fix can still surface a surprising root cause worth documenting.

3. **Should the tier boundaries be configurable?** → **Yes, extensively.** The `ceremony:` block in `compound-workflows.md` provides: `bias` (coarse knob for overall ceremony level), `required_gates` (user-defined untouchable gates — no hardcoded floors), `risk_domains` (configurable escalation triggers), `disabled_triggers` (turn off specific de-escalation), and `custom_rules` (freeform prose rules for project-specific judgment calls evaluated by the router alongside structured config). User is in charge — safety is configurable downward. See "Configuration" section above for full schema.

4. **How do we measure the right tier?** → **Three-layer feedback loop + post-hoc classifier.** Same pattern as `capture-stats.sh` → `classify-stats`, applied to routing decisions.

   **Layer 1 — Automatic logging.** Every `/compound:start` invocation logs to `.workflows/stats/` (reuses existing stats infrastructure): task description, assessed tier, routing signals used (scope, novelty, risk domain, user confidence, institutional knowledge hits), timestamp, `ceremony_bias` setting.

   **Layer 2 — Automatic outcome signals.** As the task progresses, outcome data is appended to the routing log entry:
   - Red team hit rate: count of CRITICAL + SERIOUS findings (0 = ceremony may have been excessive)
   - Rework ratio: re-dispatches / total dispatches during `/compound:work` (high = under-ceremony)
   - Readiness check pass/fail on first run (clean pass = ceremony may have been excessive)
   - User escalation: did the user manually invoke a higher-ceremony command mid-task? (signal of under-ceremony)
   - Ceremony skip rate: how many optional phases did the user skip when offered? (signal of over-ceremony)
   - Context exhaustion: did compaction hit during the task? (signal of under-ceremony — disk-persist would have helped)

   **Layer 3 — Post-task micro-survey.** At task completion (during `/compound:compact-prep` or at work Phase 4 Ship), one question: "Was this the right amount of process? (too much / about right / too little)". Captures user perception alongside objective signals.

   **Post-hoc classifier: `/compound-workflows:classify-routing`.** Runs over accumulated routing logs (same pattern as `/compound-workflows:classify-stats`). Labels each routing decision: `routing_accuracy: correct | under-ceremony | over-ceremony`. Uses Layer 2 signals (objective outcomes: rework ratio, red team hits, context exhaustion) as primary features; Layer 3 (user perception) as secondary weight. Objective outcomes are the ground truth for quality; user perception supplements but does not override — this separation prevents Goodhart drift where optimizing for user satisfaction diverges from actual outcome quality. Over time, patterns emerge (e.g., "tasks touching auth/ are consistently under-ceremonied at Tier 1") → feed back into routing threshold tuning.

   Reason for this design: reuses the existing stats capture + classify pipeline. No new infrastructure needed — just a new YAML schema for routing logs and a new classifier skill. The feedback loop is built into the workflow's natural touchpoints (start, work completion, compact-prep), not bolted on as a separate step.

5. **What's the migration path?** → **Coexist.** `/compound:start` guides which existing commands to run and with what phase settings. It's a router, not a replacement. Existing commands accept parameters that control which phases to run (e.g., skip red team, skip readiness). `/compound:start` sets those parameters based on the tier assessment. Direct invocation remains available for users who know what they want. Reason: the existing commands are well-tested and stable. A routing layer on top is lower risk than replacing them.

6. **Per-session vs per-task ceremony?** → **Per-task.** Each task gets its own tier assessment. Reason: task complexity varies within a session. Batching 3 small tasks as "all Tier 1" might under-serve a task that deserves Tier 2. Per-task routing is more granular and adapts to what's actually being done.

## Key Decisions

### Decision 1: The plugin's enduring value is in knowledge management, not orchestration

**Rationale:** The most expensive part of the plugin (multi-agent dispatch, quality gates) compensates for current model limitations and will erode as models improve. The structurally durable parts (compound, brainstorm-as-human-scaffold, beads, traceability) address organizational problems that persist regardless of model quality.

**Implication:** Future development should invest more in the knowledge layer and less in adding orchestration complexity.

### Decision 2: Adaptive ceremony is a promising direction, needs validation

**Rationale:** The current approach requires users to manually decide which commands and phases to run. Experienced users already do this informally — e.g., telling `/compound:plan` to skip red team or skip readiness checks via natural language. The proposal formalizes this existing pattern so plugin users don't need to know which steps are skippable. A routing layer that right-sizes the process matches Google/MIT's finding that the optimal strategy depends on task properties.

**Caveat (red team, OpenAI):** No controlled comparison of ceremony vs no-ceremony exists. The "hidden costs of no ceremony" section is reasoned but not measured. Before heavy investment in routing infrastructure, validate with lightweight experiments: track a few tasks done with minimal ceremony vs full ceremony and compare rework rates, token spend, and outcome quality.

**User context:** The user already steers commands to skip steps by simply asking (e.g., "run a quick version of plan, skip red team"). `/compound:start` formalizes this ad-hoc pattern into a structured routing decision that works for users who don't know which steps are skippable.

**Implication:** Build `/compound:start` as a lightweight entry point. Start minimal — the routing can be as simple as asking the user "quick or thorough?" and parameterizing existing commands accordingly. Avoid over-engineering the router before validating the tier model empirically.

### Decision 3: `/compound:start` is a router, not a replacement

**Rationale:** The existing commands (brainstorm, plan, work, review) are well-tested and stable. `/compound:start` coexists with them — it assesses the task, selects a tier, and invokes existing commands with appropriate phase settings (e.g., skip red team, skip readiness, skip deepen-plan). Users can always invoke commands directly to override routing.

**Implication:** Implementation is a new command that parameterizes existing commands, not a rewrite. The knowledge capture layer (beads, compound, traceability) is always-on regardless of tier — even Tier 0 tasks get tracked and can be compounded.

### Decision 4: The orchestrator is *likely* the real cost problem, not subagent dispatch count — CONTINGENT ON MEASUREMENT

**Rationale:** The orchestrator is estimated 50-70% of total Opus cost due to the 710x cache:I/O ratio from growing conversation context. Subagent dispatch savings are real but capped at 5-30% improvement. Shorter sessions and more aggressive compaction have larger impact than model selection for subagents.

**Caveat (red team, OpenAI + Opus):** The 50-70% estimate is inferred from aggregate daily ccusage data, not directly measured. Confidence is LOW. If the actual split is 30-40% orchestrator / 60-70% subagent, then subagent optimization becomes the dominant lever and the prioritization inverts. **Bead 3zr (session JSONL mining) is a prerequisite for validating this decision.** Do not make irreversible architectural commitments based on this estimate until per-command tracing confirms the split.

**Implication:** Adaptive ceremony addresses orchestrator cost indirectly (lighter tiers → shorter sessions → less accumulated context). However, the magnitude of orchestrator savings from shorter sessions has not been quantified — it is possible that lighter tiers do not materially reduce orchestrator context growth if the remaining tool calls still accumulate comparable context. If orchestrator cost is lower than estimated, the primary lever shifts to subagent count/model optimization — which adaptive ceremony also helps with (fewer agents at lower tiers).

## Red Team Resolution Summary

### CRITICAL — Resolved

1. **Orchestrator cost claim is inferred** (OpenAI, Opus) → **Valid.** Decision 4 updated with caveat: contingent on bead 3zr measurement. [red-team--openai, red-team--opus]

2. **No counterfactual evidence** (OpenAI) → **Valid.** Decision 2 downgraded from "right next evolution" to "promising direction, needs validation." Noted that the pattern already exists informally (user steers commands to skip steps). [red-team--openai]

### CRITICAL — Deferred to Planning

3. **Tier 0 is NOT free** (Gemini) → Tier 0 context bloat tradeoff is a real design question. At Tier 0 without context-lean subagents, verbose work lands in orchestrator context. Needs design resolution: does Tier 0 mean "no ceremony" or "minimal ceremony with a single work subagent"? [red-team--gemini]

4. **Sequential pipeline contradicts Google/MIT findings** (Gemini, Opus) → The plugin's sequential flow (brainstorm → plan → work) degrades performance per the Google/MIT study (-39-70% for sequential multi-agent). But within-phase parallelism (review agents, red team providers) is where multi-agent excels. The plan needs to address: is the phase-to-phase sequence necessary (human approval gates) or can phases overlap? [red-team--gemini, red-team--opus]

5. **Routing misclassification risk** (Gemini, OpenAI, Opus) → Under-ceremony is invisible and asymmetric. The feedback loop (Resolved Q4) has a structural bias — absent data from skipped checks cannot prove checks weren't needed. Needs design resolution: mandatory escalation triggers during execution (e.g., auth/migration touched → auto-bump tier)? Human confirmation gate before executing at a low tier? [red-team--gemini, red-team--openai, red-team--opus]

6. **Problem may be task count, not per-task cost** (Opus) → Valid concern but orthogonal to adaptive ceremony. Adaptive ceremony helps regardless: if the user does fewer tasks, each task costs less. If the user does many tasks, lightweight tiers prevent quota exhaustion. Both levers (task count + per-task cost) are complementary, not competing. Noted for planning. [red-team--opus]

### SERIOUS — Resolved

**Theme A — "Lighter orchestration" contradicts building orchestration routing** (OpenAI, Opus) → **Disagree.** We need a working system today. The philosophical tension is real — long-term the orchestration layer erodes as models improve, but the router serves today's needs. The router IS the bridge: it lets the orchestration thin out gracefully (tier boundaries shift as models improve) rather than requiring a binary rebuild. Investing in a router now is investing in the transition mechanism, not the eroding layer. [red-team--openai, red-team--opus]

**Theme B — Simpler alternatives unexplored: user routes manually, prune ceremony, preflight checklist** (Opus, OpenAI) → **Disagree.** The whole point of the plugin is to assist the user. "User just learns to route" is the status quo — it works for the plugin developer but fails for plugin users who don't know which steps are skippable. The plugin exists to encode that knowledge. Pruning ceremony (fewer agents, fewer re-checks) is a valid optimization that can happen independently of routing — it's not an alternative to routing, it's complementary. [red-team--opus, red-team--openai]

**Theme C — External studies misapplied: METR, Google/MIT** (Opus) → **Valid.** METR compared AI vs no-AI, not ceremony vs no-ceremony — using it to support ceremony's value is a stretch. Google/MIT sequential degradation finding is underweighted relative to the parallelism finding. Updated framing: these studies provide context on AI-assisted development costs, not direct evidence for or against this plugin's specific ceremony pattern. The brainstorm should present them as background, not supporting evidence.

**Theme D — Feedback loop is self-referential** (Opus) → **Acknowledged, proceed anyway.** The structural limitation is real — absent data from skipped checks cannot prove checks weren't needed. But we need to start somewhere. The feedback loop will have better signal for over-ceremony detection (Tier 3 with zero findings → should have been Tier 2) than under-ceremony detection. Supplement with post-ship quality monitoring: if bugs cluster in tasks that were routed to low tiers, that's a lagging but definitive signal. [red-team--opus]

**Theme E — n=1, model improvements not guaranteed** (Opus) → **Disagree on model improvements.** Model improvements are guaranteed for now — the trajectory is clear, pricing is dropping, capabilities are expanding. If this reverses, the plugin's ceremony becomes MORE valuable, not less. The adaptive ceremony design handles both scenarios: if models improve, tier boundaries shift down; if they plateau, tier boundaries stay where they are. n=1 is acknowledged — generalizability is a goal, not a validated claim. [red-team--opus]

**Theme F — Over-engineered ML feedback loop** (Gemini) → **Disagree.** The feedback loop (Resolved Q4) reuses existing stats capture infrastructure. It's not building an ML pipeline from scratch — it's adding a classification label to routing logs, same as classify-stats adds labels to dispatch logs. The complexity is proportional to the existing pattern. [red-team--gemini]

### MINOR — Resolved

8 MINOR findings triaged. 5 fixed in-document, 3 no action needed:

**Fixed:**
- External ROI claims reframed as context, not evidence (OpenAI)
- Hidden costs section changed from declarative to conditional (Opus)
- Decision 4 acknowledges unquantified orchestrator savings from lighter tiers (Opus)
- Classifier separates objective outcomes (primary) from user perception (secondary weight) to prevent Goodhart drift (OpenAI)
- "Buy more quota" acknowledged in motivation — addresses cost, not quality/knowledge (Opus)

**No action needed:**
- Async execution — incompatible with user-in-the-loop CLI interaction model (Gemini)
- CLAUDE.md-only alternative — addressed by Decision 1 (Opus)
- Complexity budget — addressed by Decision 2's "needs validation" + incremental approach (Opus)

See `.workflows/brainstorm-research/compound-workflows-cost-benefit/` for full red team files

## Sources

### Internal
- `memory/cost-analysis.md` — token economics, per-agent cost estimates, dynamic model routing decision
- `memory/estimation-heuristics.md` — per-phase timing data (rough estimates from session observation)
- `.workflows/stats/` — 10 YAML stats files with per-agent token/duration data (44 classified entries)
- `.workflows/stats/2026-03-11-ccusage-snapshot.yaml` — daily cost progression snapshots
- `docs/solutions/cost-modeling/2026-03-11-dynamic-model-routing-cost-analysis.md` — validated empirical analysis
- `docs/solutions/process-analysis/2026-03-08-deepen-plan-iteration-taxonomy.md` — ceremony cost evidence (rounds 1-3 valuable, 4+ diminishing)
- `docs/brainstorms/2026-03-09-workflow-quota-optimization-brainstorm.md` — original Sonnet tier decisions
- `docs/brainstorms/2026-03-09-per-agent-token-instrumentation-brainstorm.md` — measurement infrastructure
- `docs/brainstorms/2026-03-08-context-lean-enforcement-brainstorm.md` — context-lean pattern rationale

### External
- [Google/MIT — Scaling Agent Systems](https://research.google/blog/towards-a-science-of-scaling-agent-systems-when-and-why-agent-systems-work/) — multi-agent +81% parallelizable, -39-70% sequential
- [METR — AI Developer Productivity Study](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/) — experienced devs 19% slower with AI tools
- [Claude Code Docs — Manage Costs](https://code.claude.com/docs/en/costs) — agentic 5-20x more tokens, subagent delegation recommended
- [Anthropic — Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — context management strategies
- [VentureBeat — AI Agent ROI](https://venturebeat.com/orchestration/ai-agents-are-delivering-real-roi-heres-what-1-100-developers-and-ctos) — $3.70 per $1 invested
- [Index.dev — AI Coding ROI](https://www.index.dev/blog/ai-coding-assistants-roi-productivity) — 62% teams see 25%+ gains
- [SitePoint — AI Coding ROI Calculator](https://www.sitepoint.com/ai-coding-tools-cost-analysis-roi-calculator-2026/)
- [Compound Engineering — Every.to](https://every.to/guides/compound-engineering) — "each unit of work should make subsequent units easier"
