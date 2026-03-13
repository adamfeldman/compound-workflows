---
title: "Fix: Compact-prep commit message uses shared static path"
type: fix
status: completed
date: 2026-03-12
origin_bead: je54
related_beads: [8one]
---

# Fix: Compact-prep commit message uses shared static path

## Problem

`do-compact-prep/SKILL.md` writes commit messages to `.workflows/scratch/commit-msg-compact-prep.txt` — a shared static path that overwrites on repeat runs and races under concurrent sessions. Same class of bug as 8one (usage-pipe, work-in-progress).

The skill already creates a run-scoped directory at `.workflows/compact-prep/<run-id>/` but doesn't use it for commit messages.

`unslugged-paths.sh` (QA) has a blanket exemption for `.workflows/scratch/*` that masked this.

## Steps

- [ ] **Step 1: Update commit message paths in `do-compact-prep/SKILL.md`**
  - Line 290-291: `.workflows/scratch/commit-msg-compact-prep.txt` → `.workflows/compact-prep/<run-id>/commit-msg.txt` (4 string replacements)
  - Line 312: `.workflows/scratch/commit-msg-compact-prep-compound.txt` → `.workflows/compact-prep/<run-id>/commit-msg-compound.txt` (2 string replacements)

- [ ] **Step 2: Remove `.workflows/scratch/*` blanket exemption from `unslugged-paths.sh`**
  - Line 84: remove `.workflows/scratch/*` from the case pattern
  - All other scratch users (do-work, resolve-pr-parallel) are already slugged by ID — removing the exemption won't cause false positives

- [ ] **Step 3: Version bump, changelog, QA**

## Acceptance Criteria

1. Compact-prep writes commit messages under `.workflows/compact-prep/<run-id>/`
2. `unslugged-paths.sh` no longer exempts `.workflows/scratch/*`
3. QA passes with zero findings

## Sources

- Bead je54: compact-prep commit message uses shared static path
- Bead 8one (closed): same class of bug with usage-pipe and work-in-progress
- `unslugged-paths.sh` line 84: blanket exemption that masked the issue
