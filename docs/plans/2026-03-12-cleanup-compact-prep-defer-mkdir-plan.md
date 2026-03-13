---
title: "cleanup: Defer compact-prep run directory creation to Step 3"
type: cleanup
status: completed
date: 2026-03-12
bead: bw9v
---

# Defer compact-prep run directory creation to Step 3

## Summary

The `mkdir -p .workflows/compact-prep/<run-id>/` runs unconditionally at init, but the directory is only needed for the compound pause-and-resume state file (Step 3). Most runs skip compound, so the directory is created for nothing. Move mkdir to Step 3.

## Implementation

**File:** `plugins/compound-workflows/skills/do-compact-prep/SKILL.md`

### Edit 1: Remove mkdir from init section

Remove the mkdir command and temp files paragraph from "Generate Run ID and Directory" (lines 48-54). Keep run ID generation. Rename section heading from "Generate Run ID and Directory" to "Generate Run ID".

### Edit 2: Add mkdir to Step 3

Add `mkdir -p .workflows/compact-prep/<run-id>/` to Step 3 (Run Compound), before writing the state file.

### Edit 3: Version bump + changelog

- Bump version 3.1.4 → 3.1.5 in plugin.json and marketplace.json
- Add CHANGELOG entry

### Edit 4: QA

- Run Tier 1 QA scripts (all 9)
