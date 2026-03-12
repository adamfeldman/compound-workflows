---
name: commit-scratch-path
description: Write commit message files to .workflows/scratch/, never /tmp
type: feedback
---

Write commit message scratch files to `.workflows/scratch/commit-msg-<RUN_ID>.txt`, not `/tmp`.

**Why:** The project has an established convention for scratch files in `.workflows/scratch/`. Writing to `/tmp` puts files outside the project directory, produces ugly relative paths in the UI (`../../../../../tmp/...`), and ignores an existing pattern that was explicitly documented in the codebase. The user caught this after the convention was literally surfaced in research during the same session.

**How to apply:** Whenever creating a temporary file for `git commit -F` or `gh pr create --body-file`, use `.workflows/scratch/<purpose>-<RUN_ID>.txt`. Ensure `mkdir -p .workflows/scratch` first.
