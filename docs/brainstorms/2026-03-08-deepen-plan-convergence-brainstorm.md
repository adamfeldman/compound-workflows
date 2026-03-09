# Deepen-Plan Convergence Guidance

**Date:** 2026-03-08
**Status:** Draft
**Scope:** After deepen-plan completes, help the user evaluate whether another run is advisable

## What We're Building

A convergence summary agent dispatched at the end of deepen-plan (after readiness checks, before Phase 6 report). It reads the current run's synthesis + readiness outputs and compares against prior runs to produce a convergence summary with both raw signals and a recommendation. The summary is written to disk and presented in Phase 6.

The next deepen-plan run reads the prior convergence summary as input, creating a feedback loop ("Last run recommended no further iteration — are you sure?").

## Why This Approach

- **The data already exists.** Synthesis summaries, readiness reports, manifests, and red team outputs are all retained across runs in `.workflows/`. The gap is that Phase 6 doesn't read prior run data or synthesize it into guidance.
- **Hybrid approach: script for structured metrics, LLM for qualitative classification.** Five of six signals (issue count trend, severity distribution, change magnitude, deferred items, readiness result) can be computed deterministically from structured data in readiness reports and manifests. Only the sixth — category mix (genuine design issues vs edit-induced inconsistencies) — requires LLM judgment. Readiness check types provide a partial proxy: stale-values and broken-references findings are inherently edit-induced; contradictions and underspecification are more likely genuine. The LLM classifies only synthesis and red team findings that don't map to a readiness check type. Classification criteria: a finding is "edit-induced" if it flags a value/reference/label that was correct in a prior run and broke due to a plan edit; it is "genuine" if it identifies a design flaw, missing requirement, or architectural risk independent of prior edits. When classification confidence is low, default to "genuine" (safer — avoids premature convergence).
- **Signal-based with soft round-count guardrails.** Signals are the primary driver, but the iteration taxonomy's round-count data (simple: 2-3, complex: 4-5) serves as a sanity check. If run count exceeds 5 and signals haven't triggered convergence, the recommendation should flag this: "Run count exceeds typical convergence range — consider whether remaining findings are genuine or systemic." These guardrails are soft (advisory, not blocking) and may be revised as empirical data accumulates with the new readiness system.
- **Context-lean.** Agent writes to disk, Phase 6 reads the file. No heavy analysis in the parent context.

## Key Decisions

1. **Hybrid: deterministic script + `convergence-advisor` agent.** A script computes structured metrics (issue counts, severity distribution, change magnitude, deferred items, readiness result) from readiness reports and manifests — no LLM needed. The convergence-advisor agent handles only the qualitative classification (category mix: genuine vs edit-induced) for synthesis and red team findings. Both write to `.workflows/deepen-plan/<stem>/run-<N>-convergence.md`.

2. **Six signals computed per run:**
   - Issue count trend — run N found fewer/more issues than run N-1
   - Severity distribution — count of CRITICAL/SERIOUS/MINOR, any CRITICAL remaining
   - Change magnitude — how many plan sections were modified this run
   - Deferred items — count/severity of items deferred to Open Questions, trend across runs
   - Readiness result — clean pass vs issues requiring consolidator fixes
   - Category mix — genuine design issues vs edit-induced inconsistencies (using readiness check types as proxy + LLM classification of synthesis/red team findings)

3. **Output includes both data and recommendation with explicit decision logic.** The convergence summary shows raw signal values (descriptive) plus a recommendation (prescriptive) derived from these rules:
   - **"Plan appears converged, ready for work"** — zero CRITICAL/SERIOUS genuine findings this run, issue count trending down or flat, readiness passed clean
   - **"Consolidate, then evaluate"** — findings exist but are predominantly edit-induced (category mix > 50% edit-induced), or readiness required consolidator fixes. Consolidation may resolve remaining issues without another full run.
   - **"Recommend another run"** — genuine CRITICAL/SERIOUS findings remain, or new design/architectural issues surfaced this run
   - **"Recommend another run after consolidation"** — both genuine issues and significant edit-induced churn exist. Consolidate first to reduce noise, then run again to address genuine issues.
   When signals conflict (e.g., issue count trending down but a new CRITICAL appeared), the presence of genuine CRITICALs overrides trend signals. User sees both raw data and recommendation, and decides.

4. **Written to disk, read by next run — but signals only, not prior recommendation.** The convergence summary at `run-<N>-convergence.md` is read by the next run, but the agent reads only the prior run's raw signal values (issue counts, severity distribution, category mix), not the prior recommendation. This prevents anchoring — the new run's recommendation is computed independently from fresh data. Phase 1 surfaces the prior run's signals as context ("Run 2 found 3 genuine issues, 5 edit-induced") but does not say "the prior run recommended X." The user sees prior signals; the agent computes a fresh recommendation.

5. **Failure modes.** If the convergence-advisor agent times out or fails, Phase 6 proceeds without a convergence section — the run is still valid, the user just doesn't get guidance. The script-computed metrics are independent and always available. If the prior convergence file is stale (plan was manually edited between sessions), the script detects this via plan file hash comparison against the hash in the prior readiness report; if mismatched, prior signals are flagged as "stale — plan modified since last run."

6. **Phase 6 reads and presents the convergence summary.** Phase 6's report includes a "Convergence" section with the signals and recommendation, presented before the "Deepen further" option. This gives the user context for that decision.

6. **Bounded reads to avoid context saturation.** The agent reads a limited set per run:
   - **Structured (script-parsed):** current + prior run readiness report Summary sections (machine-parseable severity counts), manifests (run number, agent count, status)
   - **LLM-classified:** current run's synthesis summary and the prior run's convergence summary only. Not individual red team files — the synthesis already consolidates red team findings. Not the full history — only current and immediately prior run.
   - **First run:** no prior data exists. The script computes what it can (severity distribution, readiness result); the agent classifies current-run findings only and notes "first run — trend data unavailable."

## Open Questions

None — resolved through red team triage (see Considered and Rejected below).

## Considered and Rejected

- **Run indexing/collision risk** (OpenAI, MINOR): Concurrent runs could mis-link comparisons. Acknowledged — run numbering is already sequential in the manifest; concurrent deepen-plan runs on the same plan aren't a real scenario.
- **Synthesis accretion makes cross-run comparison harder** (Opus, MINOR): Acknowledged — bounded reads (Decision 7) limit exposure to current + prior run only.
- **"Signal-based not threshold-based" is a false dichotomy** (Opus, MINOR): Addressed — soft round-count guardrails added as a hybrid.
- **"Context-lean" claim is misleading for agent's own context** (Gemini + Opus, MINOR): Addressed — bounded reads (Decision 7) cap the agent's input to current run synthesis + prior run convergence signals only.
- **Missing "consolidate then continue" recommendation state** (Opus, MINOR): Addressed — added as fourth recommendation bucket in Decision 3.

## Research

- Repo research: `.workflows/brainstorm-research/deepen-plan-convergence/repo-research.md`
- Context research: `.workflows/brainstorm-research/deepen-plan-convergence/context-research.md`
