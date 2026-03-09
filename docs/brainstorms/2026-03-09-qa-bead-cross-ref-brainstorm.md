# QA Finding → Bead Cross-Reference

## What We're Building

Add a cross-reference phase to `plugin-changes-qa` that matches QA findings against open beads. Uses hybrid matching (deterministic text first, LLM for remainder). All bead operations require staged batch confirmation — no auto-creation. This changes plugin-changes-qa's identity from pure reporter to reporter+tracker.

### Scope

- **plugin-changes-qa SKILL.md** — new Phase 3.3 (cross-reference) after aggregation, before presentation
- **Hybrid matching** — deterministic text match on check-name/file/title first, LLM subagent for unmatched findings, uncertain matches escalated to user
- **Staged batch confirmation** — all proposed bead operations (create, update, add notes) presented as a batch, user confirms once before any bd commands execute
- **Two-pass subagent** — Pass 1: match findings to beads. Pass 2: coverage assessment on matched beads only.
- **Finding notes on beads** — add the finding as a note on matched beads for traceability
- **Severity-to-priority mapping** — CRITICAL→P1, SERIOUS→P2, MINOR→P3
- **Idempotency** — fingerprint (check-name + file + finding) + provenance token in created beads. Prevents duplicate beads and duplicate notes on re-runs.
- **Beads availability gating** — two-step: `bd version` (installed?) then `bd search "" --status open --json` (database accessible?). Warn once if unavailable.
- **Identity shift** — update all three "informational only" / "no mutation" rules in SKILL.md. QA becomes reporter+tracker.
- **Per-item status tracking** — track success/failure of each bd operation, report summary at end
- **Cap at 100 beads** — warn if more than 100 open beads, truncate to most recent

### Out of Scope

- PostToolUse hook changes (hook stays Tier 1 only, speed-optimized)
- Auto-closing beads when findings are resolved (separate concern)
- Changing the Tier 1/Tier 2 QA architecture

## Why This Approach

### Problem

After QA aggregates findings, the user manually cross-references against open beads by running `bd search` or `bd list`. This is tedious (both directions: "is this finding tracked?" and "did I miss creating a bead?") and error-prone (findings slip through when the user forgets to check, and rediscovered in future QA runs). The user has developed the pattern of asking "is everything connected to an open bead?" after every QA run — this should be automated.

### Solution: Hybrid Matching + Staged Confirmation

**Matching:** Two-step hybrid approach:
1. **Deterministic text match** — check-name, file path, and title keywords against bead titles/descriptions via `bd search`. Fast, free, provably correct for exact matches.
2. **LLM semantic match** — subagent handles unmatched findings, catching paraphrased connections. Includes an "uncertain" category for matches the LLM isn't confident about — these are escalated to the user for manual linking.

**Confirmation:** All proposed bead operations are presented as a staged batch. The user sees the full list of planned creates, updates, and note additions, then confirms once via AskUserQuestion before any bd commands execute. No auto-creation — even SERIOUS+ findings require explicit confirmation.

**Two-pass subagent:** Pass 1 matches findings to beads. Pass 2 assesses coverage on matched beads only and drafts proposed description updates. Splitting tasks improves accuracy by giving each pass a narrower focus.

This fits as Phase 3.3 in the existing skill, after aggregation (Phase 3.2) and before presentation (Phase 3.4).

### Why hybrid matching

All three red team providers flagged LLM-only matching as unreliable for exhaustive list-matching. Hybrid addresses this:
- Deterministic matching is provably correct and free for exact/near-exact matches (e.g., finding check-name "context-lean-grep" matches bead title "Fix 13 pre-existing SERIOUS context-lean-grep QA findings")
- LLM handles the hard cases (paraphrased beads, batch beads covering multiple findings)
- Uncertain matches get escalated rather than silently applied

### Rejected alternatives

- **LLM-only matching** — originally proposed but all three red team providers flagged reliability concerns. False negatives cause duplicate beads, false positives link to wrong beads. Hybrid reduces both risks.
- **Text-only matching** — fast and cheap but misses paraphrased beads. High false-negative rate defeats the purpose.
- **Hook-level cross-ref** — the PostToolUse hook is speed-optimized for Tier 1 scripts. Full cross-ref belongs in the comprehensive QA command.
- **Auto-creation without confirmation** — all three providers flagged the contradiction between "explicit user approval" and "auto-create." Staged batch confirmation resolves this.

## Key Decisions

### 1. Hybrid matching: text first, LLM for remainder, uncertain escalated

Deterministic text matching handles easy cases (free, provably correct). LLM subagent handles hard cases. Uncertain matches go to the user for manual linking. This addresses all three providers' concerns about LLM reliability while keeping the benefits of semantic matching.

**User rationale:** "Hybrid + uncertain" — best of both approaches plus safety net for ambiguous matches.

### 2. Staged batch confirmation — no auto-creation

All proposed bead operations (creates for SERIOUS+, creates for user-approved MINORs, coverage updates, note additions) are presented as a staged batch. User confirms once via AskUserQuestion before any bd commands run. No auto-creation.

**User rationale:** "Staged batch confirmation" — resolves the approval contradiction flagged by all three providers.

### 3. Coverage check via separate subagent pass

Pass 1: match findings to beads. Pass 2: for matched beads only, assess coverage and draft proposed description updates. Splitting into two passes gives each agent a narrower task, improving accuracy. Consistent with context-lean convention (focused agents).

**User rationale:** Fix the MINOR finding about subagent overload — split into two passes.

### 4. Idempotency via fingerprint + provenance token

Each finding gets a fingerprint (check-name + file + normalized description). Created beads include a provenance token (e.g., `qa-finding:context-lean-grep:work.md:185`). On subsequent runs:
- Deterministic matching finds the provenance token → skip
- LLM semantic matching catches beads without tokens → skip
- Double safety net prevents duplicate beads and duplicate notes

**User rationale:** "Both fingerprint and provenance token" — deterministic dedup plus semantic backup. Duplicates are theoretically prevented by semantic matching, but tokens are the safety net for LLM false negatives.

### 5. Identity shift: QA becomes reporter+tracker

plugin-changes-qa changes from pure reporter to reporter+tracker. All three "informational only" / "no mutation" rules in SKILL.md need updating. The tool can now create beads, update descriptions, and add notes — but only with explicit user confirmation via staged batch.

**User rationale:** "Acknowledge + update all rules" — the identity change is real and should be explicit, not hidden behind a single rule update.

### 6. Full QA only, not hook

Cross-ref runs during `/compound-workflows:plugin-changes-qa`, not the PostToolUse hook. Hook stays fast.

**User rationale:** Hook is speed-optimized. Cross-ref is a comprehensive analysis step.

### 7. Two-step beads availability check

Step 1: `bd version 2>/dev/null` (is bd installed?). Step 2: `bd search "" --status open --json` (is database accessible and producing JSON?). If either fails, warn once and skip cross-ref. This handles partial installation (bd installed but no .beads/ directory).

**Empirical finding:** `bd list --json` does NOT produce JSON — it outputs tree-formatted text regardless of the `--json` flag. `bd search "" --json` DOES produce proper JSON with full bead details (id, title, description, priority, status, timestamps). Use `bd search` not `bd list` for structured output.

### 8. Per-item status tracking for bd operations

Track success/failure of each bd command (create, update). Report "applied vs failed" summary at end. If a create fails, warn and continue with remaining items. No retry — user can re-run QA.

**User rationale:** "Per-item tracking" — know what succeeded and what didn't.

### 9. Cap at 100 beads

If `bd search` returns more than 100 open beads, warn the user and truncate to the 100 most recently updated. This prevents prompt-size issues and keeps the subagent focused. Projects with 200+ beads likely need backlog grooming, not larger matching windows.

## Integration Changes

### plugin-changes-qa SKILL.md

New Phase 3.3 after aggregation:

```
Phase 3.3: Beads Cross-Reference

1. Check beads availability (two-step):
   a. bd version 2>/dev/null → installed?
   b. bd search "" --status open --json → database accessible?
   If either fails: warn "Beads not configured — QA findings won't
   be cross-referenced." Skip to Phase 3.4.
   If >100 beads: warn and truncate to 100 most recent.

2. Deterministic text matching:
   For each finding, search bead titles/descriptions for:
   - Exact check-name match (e.g., "context-lean-grep")
   - File path match (e.g., "work.md")
   - Provenance token match (e.g., "qa-finding:context-lean-grep:work.md")
   Mark matched findings as "tracked."

3. Dispatch LLM subagent for unmatched findings (disk-persist):
   Pass 1 — Matching:
   - Input: unmatched findings + full beads JSON
   - Task: semantic match, classify as matched/untracked/uncertain
   - Output: .workflows/plugin-qa/bead-cross-ref-matches.md

4. Dispatch coverage subagent for matched beads (disk-persist):
   Pass 2 — Coverage:
   - Input: matched finding-bead pairs
   - Task: assess if bead description covers finding, draft updates
   - Output: .workflows/plugin-qa/bead-cross-ref-coverage.md

5. Read results. Present staged batch to user:

   "### Tracking Status

   **Already tracked (full coverage):**
   - [finding] → bead [id]: [title]

   **Already tracked (partial coverage — updates proposed):**
   - [finding] → bead [id]: [title]
     Proposed update: [description addition]

   **Uncertain matches — please confirm:**
   - [finding] → possibly bead [id]: [title]? [Link / Not related]

   **Untracked (will create beads):**
   - [SERIOUS] [finding] → new bead: [proposed title] (P2)
   - [MINOR] [finding] → Create bead? / Dismiss

   Confirm all actions?"

   Options:
   - Apply all (creates + updates + notes)
   - Review individually
   - Skip bead operations (just show findings)

6. On confirmation, execute bd commands with per-item tracking:
   - bd create with provenance token in description
   - bd update --notes for finding notes
   - bd update --description for coverage updates
   - Report: "N created, N updated, N failed"
```

### Rule updates in SKILL.md

Update all identity statements:
- Line 11: "Findings are informational. Bead tracking operations require explicit user confirmation."
- Line 209: "No codebase mutation. Bead creation/updates are presented for user approval before execution."
- Line 213: "NEVER modify the codebase. Bead operations are the only side effect, and require user confirmation."
- Line 216: "Bead creation and updates require explicit user approval via staged batch confirmation."

### Affected files

- `plugins/compound-workflows/skills/plugin-changes-qa/SKILL.md` — add Phase 3.3, update identity rules

## Resolved Questions

### 1. Should auto-creation bypass user approval?

No — all three red team providers flagged the contradiction between "explicit approval" and "auto-create." All bead operations use staged batch confirmation. The user sees everything planned and confirms once. (Red team finding: C1, all three providers.)

### 2. How to prevent duplicate beads on re-runs?

Fingerprint (check-name + file + finding) + provenance token stored in created beads. Deterministic matching finds tokens on re-runs. Semantic matching is the backup. Both layers prevent duplicates. (Red team finding: C2, OpenAI + Opus.)

### 3. Is the tool identity change acknowledged?

Yes — QA becomes reporter+tracker. All three "informational only" rules in SKILL.md are updated. This is an explicit architectural decision, not a hidden side effect. (Red team finding: C3, Opus.)

### 4. Is markdown output from subagent reliable enough?

Yes — the orchestrator is an LLM that reads markdown natively. Provenance tokens provide the structured data needed for idempotency. JSON output would be overengineering.

### 5. Does bd list --json produce JSON?

No — empirically tested, `bd list --json` produces tree-formatted text. `bd search "" --status open --json` produces proper JSON. Use `bd search` for structured output. (Red team finding: S3, Opus.)

## Red Team Resolution Summary

| # | Finding | Severity | Flagged By | Resolution |
|---|---------|----------|------------|------------|
| C1 | "Explicit approval" contradicts "auto-create" | CRITICAL | All three | **Valid — staged batch confirmation, no auto-create** (Decision 2) |
| C2 | No idempotency for repeated runs | CRITICAL | OpenAI, Opus | **Valid — fingerprint + provenance token** (Decision 4) |
| C3 | QA identity change not acknowledged | CRITICAL | Opus | **Valid — explicit identity shift, all rules updated** (Decision 5) |
| C4 | Brittle markdown-to-CLI parsing | CRITICAL | Gemini | **Disagree — orchestrator is an LLM, reads markdown natively** (Resolved Q4) |
| S1 | LLM matching reliability assumed | SERIOUS | All three | **Valid — switched to hybrid matching with uncertain category** (Decision 1) |
| S2 | Hybrid matching dismissed too quickly | SERIOUS | All three | **Valid — adopted hybrid** (Decision 1) |
| S3 | bd list --json doesn't produce JSON | SERIOUS | Opus | **Valid — empirically confirmed, use bd search instead** (Decision 7, Resolved Q5) |
| S4 | "10-50 beads" assumption fragile | SERIOUS | OpenAI, Opus | **Valid — cap at 100, warn if exceeded** (Decision 9) |
| S5 | No failure model for partial bd operations | SERIOUS | OpenAI | **Valid — per-item status tracking** (Decision 8) |
| M1 | Coverage check overloads subagent | MINOR | Opus | **Fixed — split into two subagent passes** (Decision 3) |
| M2 | Beads availability doesn't handle partial install | MINOR | Opus | **Fixed — two-step check: bd version then bd search** (Decision 7) |
| M3 | Hybrid dismissed too quickly | MINOR | Gemini | **Resolved by S2 — adopted hybrid** |
| M4 | Auto-create contradicts approval wording | MINOR | Opus | **Resolved by C1 — staged batch confirmation** |
| M5 | "No open questions" premature | MINOR | OpenAI, Opus | **Resolved — questions now in Resolved Questions section** |
| M6 | Unbounded scale assumptions | MINOR | OpenAI | **Resolved by S4 — cap at 100** |
