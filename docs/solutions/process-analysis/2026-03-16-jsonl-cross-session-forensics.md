---
title: "JSONL Cross-Session Forensics"
date: 2026-03-16
category: process-analysis
tags: [jsonl-forensics, cross-session-debugging, empirical-verification, debugging-methodology]
confidence: high
actionability: high
origin_brainstorm: docs/brainstorms/2026-03-15-session-worktree-start-flow-brainstorm.md
related:
  - docs/solutions/process-analysis/2026-03-13-session-log-analysis-methodology.md
  - docs/solutions/process-analysis/2026-03-14-inherited-assumption-blind-spots.md
  - docs/solutions/design-philosophy/2026-03-14-disk-persistence-as-diagnosability.md
reuse_triggers:
  - Session encounters state it didn't create (missing worktree, unexpected branch, file changes)
  - Bug reproduces only "sometimes" or "on resume"
  - Two sessions share mutable state (worktrees, .beads/, git index)
  - Red team or LLM claims specific OS/tool behavior — needs empirical verification
  - User reports "something deleted my work" or "my changes disappeared"
---

# JSONL Cross-Session Forensics

## The Problem

A session worktree (`session-fbbb`) was deleted while the owning session was active, causing uncommitted edits to be lost. `git reflog` showed the branch existed but couldn't identify what removed it. Multiple hypotheses (Agent tool isolation, bd auto-cleanup, random ID collision) were plausible but wrong.

## Technique 1: JSONL Forensic Timeline Reconstruction

Claude Code session logs at `~/.claude/projects/<project-path>/<session-id>.jsonl` contain every tool call with full arguments. Each session has its own file.

**Methodology:**
1. **Locate session files:** `ls ~/.claude/projects/<path>/*.jsonl`
2. **Search for the destructive action:** `grep -l "session-fbbb" *.jsonl` to find which session touched the resource
3. **Extract specific commands:** `grep -n "bd worktree remove" <session>.jsonl` to find the exact tool call
4. **Cross-reference timestamps:** JSONL entries have timestamps. `git reflog --date=iso` has timestamps. Interleave to prove ordering.
5. **Cite by line number:** JSONL is append-only — line numbers are stable references.

**How this solved the bug:** The prior session's JSONL (2232c062) had no `bd worktree create session-fbbb` (proving THIS session created it) but DID have `bd worktree remove .worktrees/session-fbbb --force` at line 11334 during `/do:abandon`. Timestamp cross-referencing proved the deletion happened while the owning session was active.

**Systematic elimination:** Each alternative hypothesis generates a testable prediction about what should/shouldn't appear in the logs. Absence of evidence (no `bd worktree create` in the prior session) is evidence of absence when the logs are known-complete.

## Technique 2: Empirical Falsification of LLM Claims

Red team round 2 (Opus, running as o3-pro fallback) claimed `git status`/`git log` update directory mtime, making mtime unreliable for worktree freshness detection.

**The 30-second test:**
```bash
stat -f '%m %Sm' .worktrees/test-probe    # Record mtime
sleep 3
git -C .worktrees/test-probe status        # Run the claimed operation
stat -f '%m %Sm' .worktrees/test-probe    # Check mtime — unchanged
```

**Result:** mtime unchanged across `git status`, `git log`, and `git branch`. The claim was false. The proposed fix (commit timestamps) had a worse bug — new worktrees inherit base branch age, appearing days stale immediately.

**The principle:** Red team claims about undocumented system behavior should be empirically tested BEFORE implementation. A 30-second test saved adopting a broken alternative. LLM consensus on factual claims is unreliable — shared training data produces shared hallucinations.

## When to Apply

| Trigger | Technique |
|---------|-----------|
| Something deleted/modified by unknown session | JSONL forensics — search all session files for the resource name |
| Bug only reproduces with concurrent sessions | JSONL timeline reconstruction across multiple session files |
| Red team claims specific OS/filesystem behavior | 30-second empirical test: observe state, run command, observe state |
| Proposed fix relies on undocumented tool behavior | Test the claim before designing around it |
| Need to prove (not guess) causation | JSONL line-number citations + git reflog timestamps |

## Invalidating Assumptions

| Assumption | What breaks it |
|------------|---------------|
| JSONL format stability | Claude Code version change alters log structure |
| One JSONL per session | Shared/rotated logs would complicate cross-session attribution |
| Tool call arguments fully logged | Truncation would reduce forensic resolution |
| mtime not updated by git reads | Different filesystems (NFS, FUSE) or future git versions |
| Local test matches all environments | macOS APFS behavior may differ from Linux ext4 |

## Connection to Existing Knowledge

- **Session log analysis methodology** (2026-03-13) — established JSONL as an analytics data source. This solution extends it to individual bug investigation.
- **Inherited assumption blind spots** (2026-03-14) — the mtime claim was an inherited assumption from a red team provider that propagated unchecked. This solution provides the enforcement mechanism: test before adopting.
- **Disk persistence as diagnosability** (2026-03-14) — "AI mistakes become diagnosable." JSONL forensics is the concrete mechanism that makes cross-session bugs diagnosable.
- **`/compound-workflows:recover` skill** — existing productized use of JSONL forensics for session recovery. This solution covers the debugging use case.
