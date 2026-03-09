#!/usr/bin/env bash
# name: version-sync
# description: Validate version consistency across plugin.json, marketplace.json, and CHANGELOG.md
#
# Usage: ./version-sync.sh [plugin-root-path]

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/lib.sh"

resolve_plugin_root "${1:-}"
init_findings

# --- Extract version from plugin.json ---

plugin_json="$PLUGIN_ROOT/.claude-plugin/plugin.json"
plugin_version=""
if [[ -f "$plugin_json" ]]; then
  plugin_version="$(grep -E '"version"' "$plugin_json" 2>/dev/null \
    | head -1 \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
fi

if [[ -z "$plugin_version" ]]; then
  add_finding "SERIOUS" "$plugin_json" "" "missing-version" \
    "Could not extract version from plugin.json"
fi

# --- Extract version from marketplace.json ---

# marketplace.json is at repo root, two levels up from plugin root
marketplace_json="$PLUGIN_ROOT/../../.claude-plugin/marketplace.json"
marketplace_version=""
if [[ -f "$marketplace_json" ]]; then
  # Extract the version from plugins[0].version — it's the version field
  # that appears after "plugins" and "name": "compound-workflows"
  # Use a simple approach: find lines with "version" inside the plugins array
  # The marketplace.json has a metadata.version (marketplace version) and
  # plugins[0].version (plugin version). We need the latter.
  # Strategy: extract all "version" lines, skip the first two (metadata block),
  # take the one inside plugins array.
  # Simpler: grep for version lines, the last one is inside the plugins array.
  marketplace_version="$(grep -E '"version"' "$marketplace_json" 2>/dev/null \
    | tail -1 \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
fi

if [[ -z "$marketplace_version" ]]; then
  add_finding "SERIOUS" "$marketplace_json" "" "missing-version" \
    "Could not extract plugin version from marketplace.json"
fi

# --- Compare plugin.json vs marketplace.json ---

if [[ -n "$plugin_version" ]] && [[ -n "$marketplace_version" ]]; then
  if [[ "$plugin_version" != "$marketplace_version" ]]; then
    add_finding "SERIOUS" "$marketplace_json" "" "version-mismatch" \
      "plugin.json=$plugin_version, marketplace.json=$marketplace_version"
  fi
fi

# --- Check CHANGELOG.md has a heading for current version ---

changelog="$PLUGIN_ROOT/CHANGELOG.md"
current_version="${plugin_version:-$marketplace_version}"

if [[ -n "$current_version" ]] && [[ -f "$changelog" ]]; then
  # Look for a heading containing the version (e.g., ## 1.11.0, ## v1.11.0, ## [1.11.0])
  if ! grep -qE "^##.*${current_version//./\\.}" "$changelog" 2>/dev/null; then
    add_finding "SERIOUS" "$changelog" "" "missing-changelog-entry" \
      "No heading found for version $current_version in CHANGELOG.md"
  fi
elif [[ -n "$current_version" ]] && [[ ! -f "$changelog" ]]; then
  add_finding "SERIOUS" "$changelog" "" "missing-file" \
    "CHANGELOG.md not found at $changelog"
fi

# --- Output ---
{
  emit_output "Version Sync Check"
  echo ""
  echo "## Versions Found"
  echo ""
  echo "- plugin.json: ${plugin_version:-"(not found)"}"
  echo "- marketplace.json: ${marketplace_version:-"(not found)"}"
  echo "- CHANGELOG entry: ${current_version:+"checked for $current_version"}"
}

exit 0
