---
title: "Fix unslugged .workflows/ paths across 4 skills"
type: fix
status: completed
date: 2026-03-12
bead: pj6k
---

# Fix unslugged .workflows/ paths across 4 skills

## Problem

Audit of all `.workflows/` write paths across skills found 4 skills writing to static filenames without unique stems. When these skills run more than once, the Write tool silently overwrites prior output — losing traceability and risking data loss.

## Audit Results

| Skill | Current Path | Slugged? | Needs Fix? |
|-------|-------------|----------|------------|
| do-brainstorm | `.workflows/brainstorm-research/<topic-stem>/` | Yes | No |
| do-plan | `.workflows/plan-research/<plan-stem>/` | Yes | No |
| do-deepen-plan | `.workflows/deepen-plan/<plan-stem>/run-<N>/` | Yes | No |
| do-review | `.workflows/code-review/<topic-stem>/` | Yes | No |
| do-compound | `.workflows/compound-research/<topic-stem>/` | Yes | No |
| do-work (commit/PR) | `.workflows/tmp/commit-msg-<RUN_ID>.txt` | Models drop RUN_ID + "tmp" confuses models into `/tmp/` | **Yes** |
| do-work (review) | `.workflows/work-review/code-simplicity.md` | No stem | **Yes** |
| plugin-changes-qa | `.workflows/plugin-qa/agents/*.md` | No stem | **Yes** |
| classify-stats | `.workflows/stats/classify-proposals.md` | No stem | **Yes** |
| resolve-pr-parallel | `.workflows/resolve-pr/PR_NUMBER/run-N/` | Yes | No |

## Root Cause

Two distinct issues:
1. **Confusing directory name:** `.workflows/tmp/` causes models to write to `/tmp/` instead (observed twice in practice). The word "tmp" triggers the model's default association with the system temp directory.
2. **Missing unique stems:** 3 skills write to fixed filenames with no RUN_ID, date, or bead stem — second runs silently overwrite first.

## Implementation Steps

### Step 0: Extend init-values.sh to emit RUN_ID and DATE for plugin-changes-qa and classify-stats

The `plugin-changes-qa|classify-stats` case in init-values.sh currently only emits REPO_ROOT and PLUGIN_ROOT. Both skills need RUN_ID and DATE for slugged output paths.

- [x] In `scripts/init-values.sh` line 224, extend the `plugin-changes-qa|classify-stats)` case to also compute and emit RUN_ID and DATE:
  ```
  plugin-changes-qa|classify-stats)
    REPO_ROOT_VAL="$(compute_repo_root)"
    DATE_VAL="$(compute_date)"
    RUN_ID_VAL="$(compute_run_id)"

    validate_plugin_root
    validate_date "$DATE_VAL"
    validate_run_id "$RUN_ID_VAL"

    echo "REPO_ROOT=$REPO_ROOT_VAL"
    echo "PLUGIN_ROOT=$PLUGIN_ROOT"
    echo "DATE=$DATE_VAL"
    echo "RUN_ID=$RUN_ID_VAL"
    ;;
  ```
- [x] Update the comment at line 14 to reflect the new outputs: `plugin-changes-qa, classify-stats -> REPO_ROOT, PLUGIN_ROOT, DATE, RUN_ID`

### Step 1: Rename `.workflows/tmp/` to `.workflows/scratch/` in do-work

- [x] In `skills/do-work/SKILL.md`, replace all 4 occurrences of `.workflows/tmp/` with `.workflows/scratch/`
  - Line 411: `commit-msg-<RUN_ID>.txt` path
  - Line 413: `git commit -F` path
  - Line 424: `pr-body-<RUN_ID>.txt` path
  - Line 426: `gh pr create --body-file` path

No changes to historical docs (brainstorms, plans) — they reference `.workflows/tmp/` as written at the time.

### Step 2: Add RUN_ID stem to do-work review path

- [x] In `skills/do-work/SKILL.md` line 388, update mkdir:
  - old: `mkdir -p .workflows/work-review/`
  - new: `mkdir -p .workflows/work-review/<RUN_ID>/`
- [x] In `skills/do-work/SKILL.md` line 396, change:
  - old: `Write your COMPLETE findings to: .workflows/work-review/code-simplicity.md`
  - new: `Write your COMPLETE findings to: .workflows/work-review/<RUN_ID>/code-simplicity.md`

The RUN_ID is already tracked by the do-work skill (initialized in Stats Setup). Both the mkdir and the subagent write instruction need the RUN_ID subdirectory.

### Step 3: Add date+RUN_ID stem to plugin-changes-qa paths

**Blanket replacement rule:** Replace ALL occurrences of `.workflows/plugin-qa/` with `.workflows/plugin-qa/<DATE>-<RUN_ID>/` — writes, reads, polls, mkdirs, and inline prose references. No reference should use the old unslugged base path.

Known references (22 occurrences across the skill — verify at implementation time):

- [x] **mkdir** (lines 57, 240, 297): `mkdir -p .workflows/plugin-qa/<DATE>-<RUN_ID>/agents/` etc.
- [x] **Agent write paths** (lines 99, 139, 177): context-lean-review.md, role-description-review.md, completeness-review.md
- [x] **Agent poll/ls** (lines 189, 206): `ls .workflows/plugin-qa/<DATE>-<RUN_ID>/agents/...`
- [x] **Beads JSON write** (line 246): `open-beads.json`
- [x] **Beads JSON reads** (lines 266, 311, 369): cross-ref steps reading open-beads.json
- [x] **Cross-ref write paths** (lines 322, 378, 453): bead-cross-ref-matches.md, bead-cross-ref-coverage.md, bead-cross-ref-batch.md
- [x] **Cross-ref poll/read** (lines 345, 350, 398, 405): `ls` and `Read` for cross-ref files
- [x] **Prose references** (lines 412, 413): inline mentions of cross-ref file paths
- [x] **Rules section** (line 645): Update from "Agent outputs go to `.workflows/plugin-qa/agents/`. Second runs overwrite prior results (always want latest)." to "Agent outputs go to `.workflows/plugin-qa/<DATE>-<RUN_ID>/agents/`. Each run writes to its own dated subdirectory; old run results are retained."

plugin-changes-qa already has init-values.sh integration but currently only parses REPO_ROOT and PLUGIN_ROOT. With Step 0, init-values.sh now also emits DATE and RUN_ID.

- [x] **Update parsing instruction** (line 19): change "track REPO_ROOT and PLUGIN_ROOT values" to "track REPO_ROOT, PLUGIN_ROOT, DATE, and RUN_ID values"

The skill then threads DATE and RUN_ID into all output paths.

### Step 4: Add DATE-RUN_ID stem to classify-stats proposal path

With Step 0, classify-stats now gets DATE and RUN_ID from init-values.sh. Use the same `<DATE>-<RUN_ID>` pattern as plugin-changes-qa for consistency.

Update ALL references to `classify-proposals.md` in the skill (not just the write path):

- [x] **Write path** (line 147): `classify-proposals.md` → `classify-proposals-<DATE>-<RUN_ID>.md`
- [x] **Poll/existence check** (line 158): `ls .workflows/stats/classify-proposals.md` → `ls .workflows/stats/classify-proposals-<DATE>-<RUN_ID>.md`
- [x] **Read path** (line 161): `Read .workflows/stats/classify-proposals.md` → `Read .workflows/stats/classify-proposals-<DATE>-<RUN_ID>.md`
- [x] **Cleanup** (line 222): `rm -f .workflows/stats/classify-proposals.md` → `rm -f .workflows/stats/classify-proposals-<DATE>-<RUN_ID>.md`

Also update the skill's init-values.sh parsing to track the new DATE and RUN_ID values (currently only parses REPO_ROOT and PLUGIN_ROOT).

### Step 5: Add Tier 1 QA check for unslugged paths

**New script vs existing:** This check is about path slugging, not context-lean violations. Create a new script `scripts/plugin-qa/unslugged-paths.sh` to keep concerns separated.

**What counts as a "write path":** Lines matching `Write.*\.workflows/` or `> \.workflows/` — instructions that tell a model or tool to write to a `.workflows/` path. Exclude `mkdir -p`, `ls`, `Read`, `rm -f`, bare `cat` without `>` (these are read/setup operations, not writes). Note: `cat > .workflows/...` IS a write and should be checked.

**What counts as "slugged":** The path contains at least one variable placeholder:
- Angle-bracket tokens: `<stem>`, `<RUN_ID>`, `<plan-stem>`, `<topic-stem>`, `<DATE>`, `<PR_NUMBER>`, `<N>`
- Shell variables: `$STATS_FILE`, `$SNAPSHOT_FILE`, `$RUN_ID` (any `$UPPER_CASE` identifier)

**Exempt paths** (intentionally static):
- `.workflows/.work-in-progress` — sentinel file

**Test cases** (expected behavior):
| Pattern | Result |
|---------|--------|
| `Write ... to: .workflows/brainstorm-research/<topic-stem>/repo-research.md` | PASS (has placeholder) |
| `Write ... to: .workflows/work-review/code-simplicity.md` | FAIL (no placeholder) |
| `Write ... to .workflows/plugin-qa/open-beads.json` | FAIL (no placeholder) |
| `Write "cleared" to .workflows/.work-in-progress` | PASS (exempt) |
| `Write ... to: .workflows/stats/classify-proposals-<DATE>-<RUN_ID>.md` | PASS (filename-embedded placeholder) |
| `$STATS_FILE` paths | PASS (shell variable) |

Implementation:
- [x] Create `scripts/plugin-qa/unslugged-paths.sh`
- [x] Update `scripts/plugin-qa/lib.sh` to include the new script in the runner (N/A — lib.sh is a function library, not a runner; scripts discovered dynamically)
- [x] Update `scripts/plugin-qa/file-counts.sh` expected script count (6 → 7) (N/A — file-counts.sh checks agent/skill/command counts, not script counts; prose counts updated in CLAUDE.md and AGENTS.md instead)
- [x] Update plugin CLAUDE.md QA table to list the new script
- [x] Update repo-root AGENTS.md QA scripts table (lines 40-46) to add the new script row
- [x] Verify: run against post-fix code confirms zero findings. Also fixed hardcoded `my-feature` in disk-persist-agents/SKILL.md template caught by the new check.

### Step 6: Version bump + CHANGELOG + QA

- [x] Update `plugins/compound-workflows/CHANGELOG.md`
- [x] Bump version in `plugins/compound-workflows/.claude-plugin/plugin.json` (PATCH) — 3.0.0 → 3.0.1
- [x] Bump version in `.claude-plugin/marketplace.json`
- [x] Run `/compound-workflows:plugin-changes-qa` — all 7 Tier 1 checks pass, 0 findings
- [x] Fix any QA findings — none needed

## Acceptance Criteria

- [x] No `.workflows/` write path in any skill uses a static filename without a unique stem
- [x] `.workflows/tmp/` renamed to `.workflows/scratch/` — no "tmp" confusion
- [x] Tier 1 QA catches future regressions (new unslugged paths fail QA)
- [x] All existing QA checks pass

## Open Questions

None — all design decisions resolved. Readiness review findings incorporated.

## Sources

- In-session audit (this conversation): full grep of all `Write.*\.workflows/` patterns across skills
- Bead pj6k: observed model writing to `/tmp/commit-msg-phase5.txt` and `.workflows/tmp/commit-msg-compound.txt` (missing RUN_ID)
