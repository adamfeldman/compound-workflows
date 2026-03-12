---
name: changelog-user-benefit
description: Changelog entries should communicate user benefit, not just list implementation changes
type: feedback
---

Changelog entries should lead with the user-facing benefit, not just describe what changed internally.

**Why:** The user noted that entries like "replace heredoc patterns" and "expand scan scope" don't communicate what the user gets. Better: "Fewer permission prompts during skill execution" or "Workflow files now covered by QA checks."

**How to apply:** When writing CHANGELOG.md entries, lead with the outcome (what improves for the user), then mention the mechanism in parentheses or a sub-bullet. Example: "Eliminate permission prompts from 7 skill files (replaced heredoc/echo patterns with Write tool)" instead of "Replace 10 heredoc/echo/commit patterns across 7 skill files."
