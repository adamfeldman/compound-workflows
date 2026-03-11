---
name: version
description: Check plugin version status — source vs installed vs release
---

# Version Check

Show the current plugin version status by comparing source, installed, and latest release versions.

## Step 1: Find and Run Script

Run `bash plugins/compound-workflows/scripts/init-values.sh version`. Read the VERSION_CHECK value from output. If the script is not found (not in source repo), run `find ~/.claude/plugins -name "init-values.sh" -path "*/compound-workflows/*" | head -1` to find it, then run `bash <found-path> version`.

Then run the version check script:

```bash
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
