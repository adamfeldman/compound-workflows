# Session-End Capture & compact-prep Batch Refactor

**Date:** 2026-03-12
**Bead:** ka3w
**Status:** Brainstormed

## What We're Building

Three changes shipped together as one compact-prep refactor:

1. **Batch refactor of compact-prep** — Replace the current 5+ sequential AskUserQuestion prompts with a check-then-act pattern. All checks run silently first, then the user sees one summary and approves/customizes actions in a single interaction.

2. **Abandon mode** — A `--abandon` flag on compact-prep (with `/abandon` as a thin alias) for sessions that won't be resumed. Skips queue-next-task (Step 8), adapts the summary, and is suggested via inline text when the LLM detects session-end language.

3. **Config toggles for optional steps** — Per-step config keys in `compound-workflows.local.md` to auto-skip steps that aren't always wanted (e.g., version check, cost summary). Absorbed from bead xzn. Steps toggled off via config don't appear in the batch prompt at all.

All three changes touch compact-prep SKILL.md. Shipping together avoids touching the file three times. *(Red team challenged bundling as convenience-not-design — acknowledged, but the batch refactor IS the larger change and the others are thin conditionals on top. Touching the file repeatedly would risk merge conflicts in prose.)*

## Why This Approach

**Batch refactor rationale:** The user expressed "I want to be hitting yes less often." Current compact-prep has up to 5 interactive prompts (commit pre-compound, compound check, commit post-compound, version update, queue task). Most of these are rubber-stamp approvals. Batching into one prompt respects user attention while preserving the ability to customize.

**Considered and rejected: auto-approve rubber-stamp steps.** Opus red team argued that if most prompts are "always yes," auto-executing them eliminates prompts entirely without batch complexity. Rejected because: the user wants visibility into what's happening before it runs. The batch shows a summary of what will happen; auto-approve is too invisible for session-end actions where you want a final "here's what I found" before walking away.

**Abandon mode rationale:** Currently there are two session-end paths: compact+resume (`/do:compact-prep` → `/compact`) and just close the terminal (lose everything). There's no clean "I'm done forever" path. `/abandon` fills this gap — it runs ~90% of compact-prep but skips resume-specific steps.

**Why not a separate skill:** Abandon mode is compact-prep minus step 8. A separate skill would duplicate most of the logic. Since skills are prose (not code), duplication means maintaining two copies that drift. A flag on compact-prep is DRY. *(Red team noted that DRY in prose is weaker than in code — conditional logic can confuse LLMs. Valid concern; the plan should keep the flag logic simple and test LLM adherence.)*

## Key Decisions

### Decision 1: ka3w and rhl are separate

**What:** Bead ka3w (session-end capture) and bead rhl (correction-capture) are separate skills with different triggers. ka3w fires at session end; rhl fires mid-session when the user corrects the model.

**Why:** Different triggers, different detection mechanisms, different UX. Combining them would conflate two distinct interaction patterns. They may share some downstream actions (memory writes) but the triggering logic is orthogonal.

### Decision 2: Check-then-act batch execution

**What:** compact-prep runs all checks silently in a first pass (memory scan, beads check, git status, compound assessment, version check, cost summary), then presents ONE consolidated prompt with all findings and recommended actions. User approves/customizes in a single interaction. Actions execute after approval.

**Why:** Reduces 5+ sequential prompts to 1. Memory writes are deferred until after approval — the check phase only IDENTIFIES what would change, doesn't write files. This makes the batch fully reversible until the user confirms. The execute phase has its own dependency ordering constraints (see Resolved Questions: step ordering).

**Batch prompt UX:** The prompt displays a summary of all findings, then a multi-select AskUserQuestion listing actions to **SKIP** (inverted selection). Default behavior (selecting nothing) = proceed with all recommended actions. This optimizes for the common case (approve all = zero selections). The "Other" option serves as the free-text escape hatch for custom instructions.

**Free-text parsing rules:** If the user selects "Other" and provides free text: treat it as override instructions applied on top of the skip selections. If the text is unambiguous (e.g., "commit with message 'fix typo'"), apply it. If ambiguous (e.g., "just do the important stuff"), ask a single clarifying follow-up before executing. Free text cannot add actions not in the recommended list — it can only modify how approved actions execute or provide additional context (e.g., commit message).

**Example batch prompt:**
```
Session end summary:
- Memory: 2 updates identified (patterns.md, project.md)
- Beads: 1 issue still in_progress (ka3w)
- Git: 3 uncommitted files
- Compound: worthy (solved non-obvious bash heuristic issue)
- Versions: all match
- Cost: today $4.23 (saved ~$1.20 via Sonnet)

Select actions to SKIP (leave empty to proceed with all):
☐ Skip memory updates
☐ Skip commit
☐ Skip compound
☐ Skip push
```

### Decision 3: Push prompt in both modes

**What:** Add a "Push to remote?" action to the batch prompt in both regular compact-prep and abandon mode.

**Why:** compact-prep currently commits but never pushes (original design omitted push because the session-close protocol hook already covered it; adding it here consolidates reminders into the batch rather than relying on a separate hook). Including push in the batch makes it visible and actionable without adding an extra prompt.

**Implementation requirement (from red team):** Gate push behind `git remote -v` check. If no remote configured, omit push from the action list entirely. Don't show a noisy option that can't succeed.

### Decision 4: Abandon mode is a flag, not a skill

**What:** `--abandon` flag on compact-prep. `/abandon` is a thin alias command (like the existing `/compound:*` → `/do:*` redirects). Abandon mode skips Step 8 (queue-next-task) and adapts the summary. Everything else runs identically to regular mode.

**Why:** Most logic is shared (~80%, exact overlap TBD in plan phase — abandon may need conditionals for beads handling, version check relevance, and cost summary beyond just skipping step 8). A separate skill would duplicate prose that drifts. The flag approach keeps one source of truth.

### Decision 5: Auto-detect routing via inline text suggestion

**What:** Add routing instructions to AGENTS.md so the LLM adds an inline text suggestion ("Tip: run /abandon to capture anything before closing.") when it detects session-end language.

**Why:** Low friction — easy to ignore if the user isn't actually done. No AskUserQuestion prompt (consistent with "fewer prompts" goal). The suggestion appears in the response text, not as a modal.

**Implementation requirement (from red team):** Add suppression — if the user says "stop suggesting /abandon" or ignores the tip twice in a session, stop suggesting for the remainder of the session. Addresses alarm fatigue risk.

**Detection phrases:** "done for today", "wrapping up", "that's all", "I'm done", "closing out", "ending the session", "abandoning", etc. Note: "I'm done" is ambiguous — can mean task-done vs session-done. The tip is low-cost enough that occasional false positives are acceptable, but suppression handles repeat offenses.

### Decision 6: Memory writes deferred until approval, via temp files

**What:** During the check phase, compact-prep scans the conversation and identifies what memory files would be updated. It writes proposed changes to temporary files (e.g., `.workflows/scratch/memory-pending/`) during the check phase — NOT to the actual memory locations. After the user approves, the temp files are copied to their final destinations.

**Why:** Makes the batch fully check-then-act. No irreversible side effects before the user sees the summary. Writing to temp files during check (rather than reconstructing from memory in the execute phase) prevents LLM drift — the exact content the user approved is what gets written. *(Red team improvement from Gemini: original design risked the LLM reconstructing memory updates differently in the execute phase.)*

### Decision 7: Per-step retry on failure

**What:** If any step fails during batch execution (e.g., compound fails, push fails), offer to retry the failed step before continuing to the next step.

**Why:** Batch execution is multi-step with dependencies. A single "halt and report" loses all progress. Per-step retry is resilient — the user can retry, skip the failed step, or abort the remaining batch. *(Red team finding from all three providers: original design had no failure semantics.)*

### Decision 8: PostToolUse hook on /compact — not feasible

**What (from Opus red team):** Investigate whether `/compact` triggers a tool call that hooks can intercept for a pre-compaction capture check.

**Resolution: not feasible.** `/compact` is a built-in Claude Code CLI command, not a tool call. The hook system (`PreToolUse`/`PostToolUse`) only fires on tool invocations (Bash, Read, Write, etc.). When the user types `/compact`, Claude Code handles it internally — no tool call is made, no hook fires. There is no way to intercept `/compact` with the current hook architecture.

**Remaining triggers are sufficient:** explicit `/abandon` invocation + inline text suggestion on session-end language detection. If Claude Code adds a `PreCommand` hook type in the future, this could be revisited.

### Decision 9: Config toggles for optional steps (absorbed from bead xzn)

**What:** Add config keys to `compound-workflows.local.md` for steps that aren't universally wanted. Steps toggled off via config are silently skipped — they don't appear in the check phase or the batch prompt.

**Candidates:**
- `compact_version_check: false` — skip version check (makes network calls, adds latency)
- `compact_cost_summary: false` — skip cost summary (requires ccusage, adds latency)
- Future: `compact_auto_commit: true` — auto-commit without appearing in batch (for users who want even fewer decisions)

**Why:** Absorbed from bead xzn. The batch refactor creates a natural extension point for per-step config: if a step is toggled off, it's simply omitted from the batch entirely. This is more granular than "auto-approve everything" (rejected S1) — users control which specific steps they never want to see.

**Default:** All optional steps enabled (current behavior). Users opt out via config. This ensures the batch prompt only shows steps the user cares about.

## Resolved Questions

**Q: How does "Customize" work in the batch prompt?**
A: Multi-select AskUserQuestion listing actions to SKIP (inverted selection). Selecting nothing = proceed with all. "Other" option for free-text instructions. One interaction for the common case.

**Q: Should the summary be skipped in abandon mode?**
A: No. Keep the summary in both modes. It serves as a final confirmation of what happened. Adapt wording for abandon context.

**Q: What about compact-prep step ordering with the batch?**
A: Check phase runs in any order (all are side-effect-free since memory writes go to temp files). Execute phase follows the correct dependency order: copy memory temp files → commit pre-compound → compound (if approved) → commit compound docs → push. The batch approval is for the DECISION; execution still respects ordering constraints.

## Red Team Resolution Summary

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| C1 | CRITICAL | AskUserQuestion doesn't support pre-checked items | **Fixed:** Inverted to "select actions to SKIP" — default (nothing selected) = proceed with all |
| C2 | CRITICAL | No failure/rollback semantics for batch execution | **Fixed:** Per-step retry — offer retry on each failed step (Decision 7) |
| S1 | SERIOUS | Auto-approve rubber-stamps simpler than batching | **Rejected:** User wants visibility before execution; batch shows what will happen |
| S2 | SERIOUS | PostToolUse hook on /compact not considered | **Resolved:** Not feasible — `/compact` is a built-in CLI command, not a hookable tool call (Decision 8) |
| S3 | SERIOUS | Push needs remote detection gating | **Fixed:** Gate behind `git remote -v` check (Decision 3) |
| S4 | SERIOUS | LLM drift when deferring memory writes | **Fixed:** Write to temp files during check phase (Decision 6) |
| S5 | SERIOUS | Session-end detection alarm fatigue | **Fixed:** Add suppression mechanism (Decision 5) |
| S6 | SERIOUS | DRY argument weak for prose skills | **Acknowledged:** Valid concern; plan should keep flag logic simple and test LLM adherence |
| S7 | SERIOUS | "Ship together" is convenience | **Acknowledged:** Primarily pragmatic; batch refactor is the larger change, abandon is thin conditional |
| S8 | SERIOUS | "No open questions" premature | **Fixed:** Reopened as deferred items (Decision 8, plus implementation requirements) |

**MINOR resolutions:**
- **Fixed (batch):** 2 fixable edits applied (execute-phase ordering reference in Decision 2, push exclusion rationale in Decision 3). Free-text parsing rules added to Decision 2.
- **Manual review outcomes:** Overlap claim updated to ~80% (item 3). Silent auto-capture rejected — curator-driven memory stays (item 4). Premature closure risk dismissed — sessions can be compacted later if needed (item 6). Config toggles absorbed from bead xzn (item 7, see Decision 9).
- **No action needed:** 6 items already resolved by CRITICAL/SERIOUS fixes or not actual issues.

## Implementation Notes

### Files to change

1. `plugins/compound-workflows/skills/do-compact-prep/SKILL.md` — major rewrite (batch refactor + abandon flag + config toggle support)
2. `plugins/compound-workflows/commands/compound/` — new thin alias for `/abandon` → `/do:compact-prep --abandon`
3. `AGENTS.md` — add auto-detect routing for session-end signals, add `/abandon` to routing table
4. `plugins/compound-workflows/skills/do-setup/SKILL.md` — add config toggle keys to setup flow
5. Plugin manifest updates (plugin.json, marketplace.json, CHANGELOG.md, README.md)

### Sequencing considerations

- Compound MUST run before compaction (needs full context) — the batch must make this clear
- Push happens last (after all commits)
- Memory temp files copied before commits (so memory updates are included in the commit)
- Version check is informational in the batch — user can choose to act on it or not
- Per-step retry available at each execution step

### Implementation requirements (from red team)

- Push gated behind `git remote -v` (no remote = omit push action)
- Memory writes via temp directory (`.workflows/scratch/memory-pending/`) during check phase
- Session-end detection suppression (stop suggesting after user dismisses or ignores twice)
- Flag logic in compact-prep kept simple — test LLM adherence to `--abandon` conditional
- `/compact` hook not feasible (built-in CLI command, not a tool call) — resolved
