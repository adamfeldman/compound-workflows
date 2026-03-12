---
name: do:abandon
description: Capture session knowledge before abandoning — runs compact-prep in abandon mode
argument-hint: ""
---

# /abandon — Capture session knowledge before closing

> This is a thin wrapper around `/do:compact-prep --abandon`.

Invoke `/do:compact-prep --abandon` immediately with any user arguments appended.

Abandon mode runs the full compact-prep checklist (memory, beads, git, compound, versions, cost)
but skips queuing a post-compaction task — the session won't be resumed.

## When to use

Use `/do:abandon` when the user is ending their session and does not plan to resume from this
context. Common triggers: "done for today", "wrapping up", "closing out", "ending the session".

The AGENTS.md routing table and session-end detection will suggest this command automatically
when session-end language is detected.

## Implementation

Do not add any logic beyond this delegation. All behavior lives in `/do:compact-prep`.
