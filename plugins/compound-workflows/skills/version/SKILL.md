---
name: version
description: Check plugin version status — source vs installed vs release
---

# Version Check

Show the current plugin version status by comparing source, installed, and latest release versions.

## Step 1: Find and Run Script

```bash
# Find version-check.sh: local repo (dev) or installed plugin
VERSION_CHECK="plugins/compound-workflows/scripts/version-check.sh"
[[ -f "$VERSION_CHECK" ]] || VERSION_CHECK=$(find "$HOME/.claude/plugins" -name "version-check.sh" -path "*/compound-workflows/*" 2>/dev/null | head -1)
if [[ -n "$VERSION_CHECK" ]]; then
  bash "$VERSION_CHECK"
else
  echo "NOT FOUND"
fi
```

If version-check.sh is not found, tell the user: "version-check.sh not found. The compound-workflows plugin may not be installed or is an older version without version checking." Then stop.

## Step 3: Present Results

Present the script's output to the user. If the script reports any actionable items (STALE or UNRELEASED), highlight them clearly and show the exact commands to run.

## Rules

- **Do not modify any files.** This skill only reports version status.
- **Do not automatically run update or release commands.** Present the commands for the user to decide.
