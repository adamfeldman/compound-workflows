---
name: Always run Tier 2 semantic QA
description: Always run Tier 2 semantic QA agents before merging plugin changes, not just Tier 1 scripts
type: feedback
---

Always run Tier 2 semantic QA agents (context-lean reviewer, role description reviewer, command completeness reviewer) before merging plugin changes. Don't skip them or make them optional.

**Why:** User expects full QA coverage on every change, not just structural scripts. Tier 2 catches semantic issues that Tier 1 can't.

**How to apply:** After all implementation work is done and Tier 1 scripts pass, dispatch all 3 Tier 2 agents before proceeding to merge/ship. This applies during `/compound:work` Phase 3 (Quality Check) and any manual QA runs.
