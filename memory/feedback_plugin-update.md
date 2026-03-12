---
name: plugin-update-never-remove-reinstall
description: Never remove+reinstall the plugin to update it — use git pull on marketplace clone then claude plugin update
type: feedback
---

Never use `claude plugin remove` + `claude plugin install` to update the plugin. This is destructive and unnecessary.

**Why:** The correct update procedure is already documented in project memory (project.md line 40). Remove+install may lose configuration, break state, or cause other issues. The LLM should always check memory before improvising update procedures.

**How to apply:** When updating the installed plugin after a release:
1. `git -C ~/.claude/plugins/marketplaces/compound-workflows-marketplace pull origin main`
2. `claude plugin update compound-workflows@compound-workflows-marketplace`
3. Restart session

If step 2 says "already at latest", step 1 was likely skipped. Never skip step 1. Never fall back to remove+reinstall.
