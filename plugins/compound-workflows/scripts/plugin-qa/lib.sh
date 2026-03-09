# Shared library for plugin-qa scripts
# Sourced (not executed directly) -- do NOT add a shebang or make executable
#
# Provides:
#   resolve_plugin_root  -- resolve plugin root from $1 or auto-detect from script location
#   init_findings        -- initialize finding counters and temp file
#   add_finding          -- append a structured finding
#   emit_output          -- write final structured markdown output

# --- Resolve plugin root ---
# Usage: resolve_plugin_root "$1"
# Sets: PLUGIN_ROOT (absolute path)
resolve_plugin_root() {
  local arg="${1:-}"
  if [[ -n "$arg" ]] && [[ -d "$arg" ]]; then
    PLUGIN_ROOT="$(cd "$arg" && pwd -P)"
  else
    # Auto-detect: this script is in scripts/plugin-qa/, so plugin root is ../../
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd -P)"
    PLUGIN_ROOT="$(cd "$script_dir/../.." && pwd -P)"
  fi

  if [[ ! -f "$PLUGIN_ROOT/CLAUDE.md" ]]; then
    echo "Error: could not find CLAUDE.md at plugin root: $PLUGIN_ROOT" >&2
    exit 1
  fi
}

# --- Initialize findings ---
# Sets: findings_file, finding_count
init_findings() {
  findings_file="$(mktemp)"
  finding_count=0
  trap 'rm -f "$findings_file"' EXIT
}

# --- Add a finding ---
# Usage: add_finding "severity" "file" "line" "pattern" "description"
# severity: CRITICAL, SERIOUS, MINOR, INFO
add_finding() {
  local severity="$1"
  local file="$2"
  local line="$3"
  local pattern="$4"
  local description="$5"

  # Make file path relative to plugin root for readability
  local rel_file
  rel_file="${file#"$PLUGIN_ROOT"/}"

  finding_count=$((finding_count + 1))
  {
    echo "- **[$severity]** \`$rel_file\`${line:+ (line $line)}: $pattern"
    echo "  $description"
    echo ""
  } >> "$findings_file"
}

# --- Emit structured output ---
# Usage: emit_output "Check Name"
emit_output() {
  local check_name="${1:-Plugin QA Check}"

  echo "# $check_name"
  echo ""
  echo "## Findings"
  echo ""
  if [[ "$finding_count" -eq 0 ]]; then
    echo "No findings."
  else
    echo "$finding_count finding(s):"
    echo ""
    cat "$findings_file"
  fi
  echo ""
  echo "## Summary"
  echo ""
  echo "- Plugin root: $PLUGIN_ROOT"
  echo "- Total findings: $finding_count"
}
