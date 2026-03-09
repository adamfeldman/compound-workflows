#!/usr/bin/env bash
# name: version-check
# description: Version comparison — source (if in dev repo) vs installed vs latest release
#
# Usage: ./version-check.sh [plugin-root-path]
#
# When run from the source repo (plugins/compound-workflows/ exists at git root):
#   3-way comparison: source vs installed vs release
# When run from a consumer project:
#   2-way comparison: installed vs release (source is N/A)
#
# Does NOT source lib.sh — output format is an informational dashboard,
# not structured QA findings.
#
# Exit codes:
#   0 = all versions match or informational only
#   1 = staleness or unreleased version detected

set -euo pipefail

# --- Helper: strip leading v from version string ---
normalize_version() {
  local v="$1"
  echo "${v#v}"
}

# --- Helper: extract version from plugin.json ---
read_version() {
  local json_path="$1"
  grep -oE '"version"\s*:\s*"[^"]+"' "$json_path" | head -1 | grep -oE '"[^"]+"\s*$' | tr -d '"' | xargs
}

# --- Detect context: source repo or consumer project ---
git_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
source_plugin_json="$git_root/plugins/compound-workflows/.claude-plugin/plugin.json"

if [[ -f "$source_plugin_json" ]]; then
  # In source repo — read source version from working copy
  in_source_repo=true
  source_version="$(normalize_version "$(read_version "$source_plugin_json")")"
else
  # Consumer project — no source version
  in_source_repo=false
  source_version=""
fi

# --- Installed version (from marketplace clone) ---
installed_plugin_json="$HOME/.claude/plugins/marketplaces/compound-workflows-marketplace/plugins/compound-workflows/.claude-plugin/plugin.json"
if [[ -f "$installed_plugin_json" ]]; then
  installed_version="$(normalize_version "$(read_version "$installed_plugin_json")")"
else
  installed_version="not installed"
fi

# --- Latest release (from GitHub via gh CLI) ---
if command -v gh &>/dev/null; then
  release_tag="$(gh release list --repo adamfeldman/compound-workflows --json tagName,isLatest --jq '.[] | select(.isLatest) | .tagName' 2>/dev/null || true)"
  if [[ -n "$release_tag" ]]; then
    release_version="$(normalize_version "$release_tag")"
  else
    release_version="unknown (no releases found)"
  fi
else
  release_version="unknown (gh CLI unavailable)"
fi

# --- Determine status labels and actions ---
actions=()
exit_code=0

if [[ "$in_source_repo" == true ]]; then
  # Source repo: compare source vs installed, source vs release
  installed_label=""
  if [[ "$installed_version" == "not installed" ]]; then
    installed_label="  <- NOT INSTALLED"
    actions+=("Plugin is not installed. Run: claude plugin update compound-workflows@compound-workflows-marketplace")
    exit_code=1
  elif [[ "$installed_version" != "$source_version" ]]; then
    installed_label="  <- STALE (installed is behind source)"
    actions+=("Plugin is stale. Run: claude plugin update compound-workflows@compound-workflows-marketplace")
    exit_code=1
  fi

  release_label=""
  if [[ "$release_version" != unknown* ]]; then
    if [[ "$release_version" != "$source_version" ]]; then
      release_label="  <- UNRELEASED (source has no matching release)"
      actions+=("Version $source_version has no GitHub release. Run: git tag v$source_version && git push origin v$source_version && gh release create v$source_version")
      exit_code=1
    fi
  fi

  echo "Source:     $source_version"
  echo "Installed:  $installed_version$installed_label"
  echo "Release:    ${release_version}${release_label:-}"
else
  # Consumer project: compare installed vs release only
  installed_label=""
  if [[ "$installed_version" == "not installed" ]]; then
    installed_label="  <- NOT INSTALLED"
    actions+=("Plugin is not installed. Run: claude plugin update compound-workflows@compound-workflows-marketplace")
    exit_code=1
  elif [[ "$release_version" != unknown* ]] && [[ "$installed_version" != "$release_version" ]]; then
    installed_label="  <- STALE (behind latest release)"
    actions+=("Plugin is stale. Run: claude plugin update compound-workflows@compound-workflows-marketplace")
    exit_code=1
  fi

  echo "Installed:  $installed_version$installed_label"
  echo "Release:    $release_version"
fi

echo ""

if [[ ${#actions[@]} -eq 0 ]]; then
  echo "All versions match. No action needed."
else
  echo "Actions needed:"
  for action in "${actions[@]}"; do
    echo "  -> $action"
  done
fi

exit "$exit_code"
