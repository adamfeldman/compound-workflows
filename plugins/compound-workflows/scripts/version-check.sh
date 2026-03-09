#!/usr/bin/env bash
# name: version-check
# description: 3-way version comparison — source vs installed vs latest release
#
# Usage: ./version-check.sh [plugin-root-path]
#
# Does NOT source lib.sh — output format is an informational dashboard,
# not structured QA findings.
#
# Exit codes:
#   0 = all versions match or informational only
#   1 = staleness or unreleased version detected

set -euo pipefail

# --- Resolve plugin root ---
if [[ -n "${1:-}" ]]; then
  PLUGIN_ROOT="$1"
else
  PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
fi

# --- Helper: strip leading v from version string ---
normalize_version() {
  local v="$1"
  echo "${v#v}"
}

# --- 1. Source version (from working repo) ---
source_plugin_json="$PLUGIN_ROOT/.claude-plugin/plugin.json"
if [[ -f "$source_plugin_json" ]]; then
  source_version_raw="$(grep -oE '"version"\s*:\s*"[^"]+"' "$source_plugin_json" | head -1 | grep -oE '"[^"]+"\s*$' | tr -d '"' | xargs)"
  source_version="$(normalize_version "$source_version_raw")"
else
  echo "ERROR: Source plugin.json not found at $source_plugin_json"
  exit 1
fi

# --- 2. Installed version (from marketplace clone) ---
installed_plugin_json="$HOME/.claude/plugins/marketplaces/compound-workflows-marketplace/plugins/compound-workflows/.claude-plugin/plugin.json"
if [[ -f "$installed_plugin_json" ]]; then
  installed_version_raw="$(grep -oE '"version"\s*:\s*"[^"]+"' "$installed_plugin_json" | head -1 | grep -oE '"[^"]+"\s*$' | tr -d '"' | xargs)"
  installed_version="$(normalize_version "$installed_version_raw")"
else
  installed_version="not installed"
fi

# --- 3. Latest release (from GitHub via gh CLI) ---
if command -v gh &>/dev/null; then
  release_tag="$(gh release list --repo adamfeldman/compound-workflows --json tagName,isLatest --jq '.[] | select(.isLatest) | .tagName' 2>/dev/null || true)"
  if [[ -n "$release_tag" ]]; then
    release_version_raw="$release_tag"
    release_version="$(normalize_version "$release_version_raw")"
  else
    release_version="unknown (no releases found)"
    release_version_raw=""
  fi
else
  release_version="unknown (gh CLI unavailable)"
  release_version_raw=""
fi

# --- Determine status labels and actions ---
actions=()
exit_code=0

# Check installed vs source
installed_label=""
if [[ "$installed_version" == "not installed" ]]; then
  installed_label="  <- NOT INSTALLED"
  actions+=("Plugin is not installed. Run: claude plugin update compound-workflows@compound-workflows-marketplace")
  exit_code=1
elif [[ "$installed_version" != "$source_version" ]]; then
  installed_label="  <- STALE (loaded plugin is behind source)"
  actions+=("Plugin is stale. Run: claude plugin update compound-workflows@compound-workflows-marketplace")
  exit_code=1
fi

# Check release vs source
release_label=""
if [[ "$release_version" != unknown* ]]; then
  if [[ "$release_version" != "$source_version" ]]; then
    release_label="  <- UNRELEASED (source version has no matching release)"
    actions+=("Version $source_version has no GitHub release. Run: git tag v$source_version && git push origin v$source_version && gh release create v$source_version")
    exit_code=1
  fi
fi

# --- Output ---
echo "Source:     $source_version"
echo "Installed:  $installed_version$installed_label"
if [[ -n "$release_version_raw" ]]; then
  echo "Release:    $release_version_raw$release_label"
else
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
