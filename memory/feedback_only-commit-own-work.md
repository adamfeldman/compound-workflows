---
name: Only commit your own session's work
description: Don't commit files modified in prior sessions — only commit what you changed in this session
type: feedback
---

Don't commit work that isn't yours. Only stage and commit files you created or modified in the current session.

**Why:** Prior-session changes may be intentionally uncommitted (work-in-progress, left for review, etc.). Bundling them into a compact-prep commit misattributes authorship and may commit incomplete work.

**How to apply:** During compact-prep Step 2, compare `git status` against what was actually touched this session. Only `git add` files from the current session. Leave other modified/untracked files alone.
