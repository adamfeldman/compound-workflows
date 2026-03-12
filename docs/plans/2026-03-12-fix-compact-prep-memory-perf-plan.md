---
title: "fix: Compact-prep performance — direct memory writes + immediate ccusage"
type: fix
status: completed
date: 2026-03-12
bead: ka3w
origin: docs/plans/2026-03-12-feat-session-end-capture-batch-refactor-plan.md
---

# Compact-prep Performance — Direct Memory Writes + Immediate ccusage

## Summary

Two performance fixes to compact-prep:

1. **Memory:** Remove temp-file-based memory handling and revert to direct writes. The deferred pattern (write to temp → show diffs → copy to production) adds ~15 minutes of overhead with no observed benefit. LLM drift was the theoretical concern but check and execute run in the same conversation context moments apart.

2. **ccusage:** Move snapshot persistence from Execute Step 6 to immediately after Check F. It's non-interactive background housekeeping — no reason to wait for batch approval.

## Acceptance Criteria

- [ ] Check A no longer writes temp files — just identifies updates with brief descriptions
- [ ] Batch prompt shows memory update descriptions (not abbreviated diffs)
- [ ] Execute Step 1 writes directly to `memory/` (no copy from temp)
- [ ] Initialization no longer creates `memory-pending/` subdirectory
- [ ] Run-ID directory still created (needed for state file in compound pause-and-resume)
- [ ] ccusage snapshot persisted immediately after Check F (not in execute phase)
- [ ] Execute Step 6 removed
- [ ] All Tier 1 QA scripts pass

## Implementation

### Step 1: Edit compact-prep SKILL.md

**File:** `plugins/compound-workflows/skills/do-compact-prep/SKILL.md`

Seven edits:

**1a. Initialization (line ~51):** Remove `memory-pending/` from mkdir:

```
# Before
mkdir -p .workflows/compact-prep/<run-id>/memory-pending/

# After
mkdir -p .workflows/compact-prep/<run-id>/
```

**1b. Check Phase header (line ~60):** Remove mention of temp directory writes being permitted:

```
# Before
The only writes permitted are to the temp directory `.workflows/compact-prep/<run-id>/memory-pending/`.

# After
Remove this sentence entirely.
```

**1c. Check A: Memory Scan (lines ~78-82):** Replace temp file writing with brief descriptions:

```
# Before (lines 78-82)
For each proposed update:
1. Create parent directories if needed (use `mkdir -p` for nested paths)
2. Use the **Write tool** to write the **complete new file content** to `.workflows/compact-prep/<run-id>/memory-pending/<path>` — mirror the target path structure (e.g., `memory/patterns.md` maps to `memory-pending/patterns.md`, `memory/sub/file.md` maps to `memory-pending/sub/file.md`). Do NOT write to `memory/` during check phase.

Record: number of updates identified, which files, and an **abbreviated diff per file** showing key additions/removals. These diffs appear in the batch prompt so the user can review the actual changes they're approving.

# After
Record: number of updates identified, which files, and a **1-2 sentence description per file** of what will be added or changed.
```

**1d. Execute Step 1 (lines ~277-283):** Replace temp-file copy with direct writes:

```
# Before
### Step 1: Copy Memory Temp Files

**Skip if:** user selected "Skip memory updates" OR no memory updates were identified.

Copy each file from `.workflows/compact-prep/<run-id>/memory-pending/<path>` to `memory/<path>` using the **Read tool** to read each temp file and the **Write tool** to write to the target path. Create parent directories as needed.

Tell the user what was updated (1-2 sentences per update, not a wall of text).

# After
### Step 1: Write Memory Updates

**Skip if:** user selected "Skip memory updates" OR no memory updates were identified.

Read existing memory files, apply the updates identified in Check A, and write directly to `memory/` using the **Read tool** and **Edit tool** (or **Write tool** for new files). Create parent directories as needed.

Tell the user what was updated (1-2 sentences per update, not a wall of text).
```

**1e. Check F: Cost Summary (line ~160):** After the cost summary check completes successfully, persist the snapshot immediately instead of deferring to Execute Step 6. Add at the end of Check F:

```
# Add after "If JSON parsing fails, note the raw summary output rather than erroring."

If cost data was successfully retrieved, persist the snapshot now:

\```bash
bash ${CLAUDE_SKILL_DIR}/../../scripts/append-snapshot.sh "<SNAPSHOT_FILE>" "<TIMESTAMP>" <total_cost> <input_tokens> <output_tokens> [additional_key=value pairs]
\```

This is non-interactive housekeeping — no user approval needed.
```

**1f. Execute Step 6 (lines ~342-354):** Remove entirely. The ccusage snapshot is now persisted in Check F.

**1g. Batch prompt summary example (line ~187-188):** Simplify memory detail line:

```
# Before
  - patterns.md: +2 lines (bash heuristic discovery), -0 lines
  - project.md: ~3 lines changed (ka3w status -> plan phase)

# After
  - patterns.md: add bash heuristic discovery
  - project.md: update ka3w status
```

### Step 2: Version bump + changelog

- [ ] Bump version to 3.1.1 in plugin.json and marketplace.json
- [ ] Add CHANGELOG entry: "Faster compact-prep — direct memory writes (no temp files), immediate ccusage snapshot"

### Step 3: QA

- [ ] Run Tier 1 QA scripts (all 9)

## Design Notes

### Why not keep diffs?

The abbreviated diffs were the most expensive part — the LLM had to compose complete file contents, then diff them against originals. The batch prompt descriptions ("add bash heuristic discovery") give the user enough context to decide whether to skip memory writes without the LLM doing all the work upfront.

### Drift risk assessment

The deferred write pattern (brainstorm Decision 6) was designed to prevent LLM drift between check and execute phases. In practice, both phases run in the same conversation context with only the batch prompt in between. No drift has been observed. The 15-minute overhead is a concrete cost; the drift prevention is a theoretical benefit.

## Sources

- **Parent plan:** `docs/plans/2026-03-12-feat-session-end-capture-batch-refactor-plan.md` — Decision 6 (deferred memory writes)
- **Origin brainstorm:** `docs/brainstorms/2026-03-12-session-end-capture-brainstorm.md` — Decision 6 rationale
