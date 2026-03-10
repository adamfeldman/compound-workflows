---
title: "Per-Agent Token Instrumentation"
type: feature
category: plugin-infrastructure
date: 2026-03-09
bead: voo
related_beads: [xu2, 22l]
status: brainstorm-complete
---

# Per-Agent Token Instrumentation

## What We're Building

Automatic per-dispatch stats collection across all 5 orchestrator commands (work, brainstorm, plan, deepen-plan, review). Task completion notifications already return `<usage>total_tokens, tool_uses, duration_ms</usage>` — this feature persists those stats to centralized YAML files and provides a standalone classification skill. ccusage snapshots are also persisted for delta math (session cost approximation and orchestrator overhead visibility).

## Why This Approach

Task completion stats are more actionable than ccusage for optimization decisions. ccusage answers "how much did I spend today?" — per-dispatch stats answer "which agent cost what and was it worth it?" The data is already flowing through every orchestrator command; it's just being discarded. Persisting it builds the dataset that xu2 (work-step-executor Sonnet routing) needs to make informed model-tiering decisions.

First dataset was manually collected during v2.0.0 work execution: 8 subagents, 245k tokens, 121 tool uses, 626s. This feature automates that collection.

## Key Decisions

### 1. Capture Mechanism — Inline Instructions

Short inline instruction in each orchestrator command telling the orchestrator to extract `<usage>` stats after each Task completion and append to the YAML stats file. If the instruction grows beyond 2-3 lines, extract to a separate reference file.

**Rationale:** CLAUDE.md conventions aren't reliably followed for procedural steps. Inline is most reliable because it's right in the prompt being executed. A separate file read is the fallback if complexity grows.

### 2. Storage Format — Multi-Document YAML

One YAML file per command run, with one document per dispatch separated by `---`. LLMs write YAML fluently (unlike JSON, which is prone to syntax errors). Append-friendly via `---` separator. Classification rewrites the file to add `complexity` fields — acceptable since per-command-run files are small.

```yaml
---
command: work
bead: 22l
stem: quota-optimization-v2.0
agent: general-purpose
step: "1"
model: opus
tokens: 20121
tools: 13
duration_ms: 43364
timestamp: 2026-03-09T14:23:00Z
status: success
---
command: work
bead: 22l
stem: quota-optimization-v2.0
agent: general-purpose
step: "3"
model: opus
tokens: 44641
tools: 19
duration_ms: 83000
timestamp: 2026-03-09T14:25:00Z
status: success
```

**Rationale:** JSONL was initially chosen but rejected after red team review — LLMs produce malformed JSON, and "append-only" conflicted with classification requiring in-place updates. YAML is natural for LLMs, machine-parseable (multi-document YAML is standard), and small files make rewrites safe.

### 3. Storage Location — Centralized, Per-Command-Run Files

Single directory: `.workflows/stats/`

One file per command run, named `<date>-<command>-<stem>.yaml`:
```
.workflows/stats/2026-03-09-work-quota-optimization.yaml
.workflows/stats/2026-03-09-brainstorm-voo.yaml
.workflows/stats/2026-03-09-deepen-plan-quota-optimization.yaml
```

A session running multiple commands produces multiple files. No coordination needed between commands — each run is self-contained.

ccusage snapshots are also written here by compact-prep:
```yaml
---
type: ccusage-snapshot
timestamp: 2026-03-09T18:30:00Z
total_cost_usd: 212.71
input_tokens: 1234567
output_tokens: 456789
```

Delta between consecutive snapshots approximates session cost. Gap between ccusage delta and sum of per-dispatch stats reveals orchestrator overhead.

**Rationale:** Per-command-run files eliminate session coordination complexity (no shared file path between commands, no collision on same-day same-topic runs). Cross-run analysis via `cat .workflows/stats/*.yaml`. Centralized (not scattered across per-command subdirs) because the goal is a unified dataset.

### 4. Schema

```yaml
---
command: work
bead: 22l
stem: quota-optimization-v2.0
agent: general-purpose
step: "1"
model: opus
tokens: 20121
tools: 13
duration_ms: 43364
timestamp: 2026-03-09T14:23:00Z
status: success
complexity: mechanical
```

Fields:
- `command` — which orchestrator (work, brainstorm, plan, deepen-plan, review)
- `bead` — bead ID, nullable (not all runs have one)
- `stem` — `.workflows/` subdirectory stem, links back to source artifacts
- `agent` — dispatched agent name
- `step` — universal, always populated. Step number for work, agent name for others.
- `model` — what model ran
- `tokens`, `tools`, `duration_ms` — raw stats from `<usage>` tag
- `timestamp` — when dispatch completed
- `status` — dispatch outcome (success/failure/timeout), captured inline by orchestrator at capture time
- `complexity` — added post-hoc by classifier (rote/mechanical/analytical/judgment), null until classified
- `output_type` — added post-hoc by classifier (code-edit/research/review/relay/synthesis), null until classified

### 5. Complexity Classification — Decoupled from Compact-Prep

Classification is a standalone skill (`/compound:classify-stats`), not tied to compact-prep. Run it whenever — after a session, after a week, after a batch of sessions.

The classifier is a dispatched subagent that reads three input layers:
1. **YAML stats** — tokens, tools, duration, agent name, status
2. **Artifacts** — `.workflows/` outputs via stem field
3. **Session log** — Claude Code internal JSONL log for conversation context (orchestrator retries, user feedback, actual flow)

It updates the YAML file in place — entries with classification fields are classified, entries without are unclassified. Per-command-run files are small, so rewriting is safe. The classifier proposes classifications, the user confirms or overrides.

The classifier adds two dimensions:
- **Complexity** (4-tier): `rote` (trivial, almost no reasoning — Haiku candidate) / `mechanical` (structured edits with clear specs — Sonnet candidate) / `analytical` (research, synthesis, comparison — Sonnet) / `judgment` (tradeoffs, architecture, prose — Opus)
- **Output type**: `code-edit` / `research` / `review` / `relay` / `synthesis`

Both are derivable post-hoc from stats + artifacts + agent metadata. No extra capture burden on the orchestrator. Output type is largely predictable from agent name + command, but the classifier confirms from actual artifacts.

**Rationale:** All three input layers persist on disk. There's no reason to tie classification to compact-prep — it doesn't need live conversation context because the session JSONL log IS the conversation context, available anytime. Decoupling saves time during compact-prep (already a multi-step process) and lets the user classify on their own schedule.

### 6. Settings — Two Independent Toggles

In `compound-workflows.local.md` (gitignored config):
```
stats_capture: true    # default on — collect raw stats during command execution
stats_classify: true   # default on — classify-stats proposes complexity labels
```

Both default to on. Capture can be disabled if stats aren't wanted. Classification can be disabled to collect raw stats without labeling.

Missing keys = enabled (no breakage for existing users). Re-running `/compound:setup` adds any new config keys — setup is idempotent for config migration.

### 7. Scope — All 5 Commands from Day One

All orchestrator commands instrumented simultaneously:
- **work** — step number as `step` field, bd context for `bead` field
- **brainstorm** — agent name as `step` field
- **plan** — agent name as `step` field
- **deepen-plan** — agent name as `step` field (stats go to centralized YAML only, not the manifest)
- **review** — agent name as `step` field

### 8. Failed Dispatches — Still Captured

Failed Task dispatches still cost tokens. Stats are captured regardless of success/failure with `status: failure` or `status: timeout`. The orchestrator knows dispatch outcome at capture time; reconstructing it post-hoc from artifacts is unreliable. If `<usage>` tags are absent on failure, the entry is still written with `tokens: null` to preserve the failure record.

### 9. "Enough Data" for xu2

After a few sessions running different commands, the dataset should have enough patterns across agent types to inform model-tiering decisions. Exact thresholds are xu2's brainstorm concern, not voo's.

## Open Questions

Resolved for brainstorm scope. Execution risks to address during planning:
- `<usage>` parse failure handling — warn on format changes so user can file a bug (don't silently skip)
- Per-command capture timing differences — each command has different dispatch patterns (foreground vs background, batched vs individual)
- Classifier session-log correlation design — mapping stats entries to relevant sections of potentially large session logs
- Inline capture reliability — LLMs may skip secondary procedural tasks; detection/validation of missing entries
- Sample size thresholds for xu2 decisions — deferred to xu2's brainstorm

## Resolved Questions

1. **Classify at dispatch time or post-hoc?** Post-hoc via standalone skill. The orchestrator doesn't classify; a separate classifier subagent does, reading stats + artifacts + session logs. User clarified "classify at dispatch time" was about model selection (xu2's concern), not complexity labeling.

2. **Does classification need conversation context?** Not live context — the Claude Code session JSONL log persists conversation context to disk. The classifier reads it from there, so it doesn't need to run during the session.

3. **Should classification live in compact-prep?** No. Decoupled to a standalone skill. All inputs persist on disk; no reason to tie it to compact-prep's synchronous flow. Saves user time.

4. **Per-command stats or centralized?** Centralized. Deepen-plan manifest doesn't need stats — it tracks run status, not cost/complexity. The YAML stats directory is the single source of truth.

5. **File rotation?** Per-command-run. Each command execution creates its own file. No session coordination needed. Cross-run analysis via `cat .workflows/stats/*.yaml`.

6. **What about ccusage?** Keep it but persist snapshots to the stats directory. Delta between consecutive snapshots approximates session cost. Gap between ccusage delta and sum of per-dispatch stats reveals orchestrator overhead — the blind spot per-dispatch stats can't cover.

## Red Team Resolution Summary

Three-provider red team review (Gemini, OpenAI, Claude Opus).

| Finding | Severity | Provider(s) | Resolution |
|---------|----------|-------------|------------|
| Append-only vs in-place contradiction | CRITICAL | Gemini, OpenAI | **Fixed:** Changed from JSONL to multi-document YAML. Small per-command-run files make rewrites safe. |
| LLM JSON corruption risk | CRITICAL | Gemini | **Fixed:** YAML replaces JSON — LLMs write YAML fluently. |
| `<usage>` tag is undocumented API | CRITICAL | Opus | **Acknowledged:** Real risk, acceptable for optimization data. Warn on parse failure so user can file a bug — don't silently skip. |
| Session boundary/file coordination | SERIOUS | Gemini, Opus | **Fixed:** One file per command run, not per session. No coordination needed. |
| Session log dependency is brittle | SERIOUS | All three | **Kept:** Three-layer classifier (stats + artifacts + session logs). Session logs add classification value worth the complexity. |
| Concurrent write collisions | SERIOUS | OpenAI | **Resolved:** Orchestrator processes completions sequentially even for background tasks. |
| "All 5 from day one" masks complexity | SERIOUS | Opus | **Acknowledged:** Per-command capture timing varies. Planning concern, not brainstorm scope change. |
| Inline instruction reliability | SERIOUS | Opus, Gemini | **Acknowledged:** Real risk. Plan should address validation/detection of missing entries. |
| Privacy risk from session log ingestion | SERIOUS | OpenAI | **Dismissed:** Single-user local tool. Session logs already on user's machine. |
| **Fixed (batch):** 2 MINOR fixes applied. | MINOR | Various | Added `status` field to schema. Replaced "Open Questions: None" with risk register. |
| **Acknowledged (batch):** 5 MINOR findings accepted. | MINOR | Various | Step field overloading (keep single field, `command` disambiguates), ternary expanded to 4-tier + output_type dimension, instrumentation cost negligible, settings migration via idempotent setup re-run, sample thresholds deferred to xu2. |
| **No action (batch):** 2 MINOR findings. | MINOR | Gemini, OpenAI | Programmatic capture and SQLite alternatives — already addressed by format change. |
