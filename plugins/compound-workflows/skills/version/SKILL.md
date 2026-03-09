---
name: version
description: Check plugin version status — source vs installed vs release
---

# Version Check

Show the current plugin version status by comparing source, installed, and latest release versions.

## Step 1: Resolve Plugin Root

```bash
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
echo "Repo root: $REPO_ROOT"
ls "$REPO_ROOT/plugins/compound-workflows/scripts/version-check.sh" 2>/dev/null && echo "FOUND" || echo "NOT FOUND"
```

If version-check.sh is not found, tell the user: "version-check.sh not found at `plugins/compound-workflows/scripts/version-check.sh`. The compound-workflows plugin may not be installed or is an older version without version checking." Then stop.

## Step 2: Run Version Check

```bash
bash plugins/compound-workflows/scripts/version-check.sh
```

## Step 3: Present Results

Present the script's output to the user. If the script reports any actionable items (STALE or UNRELEASED), highlight them clearly and show the exact commands to run.

## Rules

- **Do not modify any files.** This skill only reports version status.
- **Do not automatically run update or release commands.** Present the commands for the user to decide.
