---
name: deepen-plan-for-big-changes
description: /do:deepen-plan should be treated as non-optional for plans that add new plugin components or touch multiple integration points
type: feedback
---

Deepen-plan is not optional for big changes — treat it as a required step when the plan adds new files to the plugin (skills, scripts, commands) or modifies multiple existing integration points.

**Why:** During the worktree-session-isolation plan (bead s7qj), `/do:plan` researched the problem domain (git worktrees, concurrency) but missed that adding a new skill and config key requires `/do:setup` changes. The gap survived specflow analysis (user flow focused), two readiness check rounds, and a 3-provider red team — only caught because Gemini flagged hook installation and the user pushed back on the triage.

**Root cause:** Plan researches the **problem space** ("what do I need to know about worktrees?"). Deepen researches the **plan itself** ("given this plan adds new files, what plugin infrastructure needs updating?"). These are fundamentally different — plan creates, deepen audits. Without deepen, integration gaps with existing plugin machinery (setup, QA, versioning, component counts) slip through.

**How to apply:** When the plan's Files Changed table includes new plugin files (skills/, scripts/, agents/) or the plan touches 3+ existing skills, recommend deepen-plan even if readiness checks pass clean. The decision tree should weight this — "big change without deepen" is a risk signal comparable to "no brainstorm + 4+ steps."
