#!/usr/bin/env bash
# name: convergence-signals
# description: "Compute 5 structured convergence metrics from readiness reports and manifests"
# type: mechanical
#
# Usage: ./convergence-signals.sh <stem-dir> <readiness-dir> <output-file>
#
# Arguments:
#   stem-dir      - .workflows/deepen-plan/<stem>/ — contains manifests and synthesis summaries
#   readiness-dir - .workflows/plan-research/<stem>/readiness/ — contains readiness reports
#   output-file   - path to write a debug copy of stdout output
#
# NOTE: Does NOT use lib.sh validate_inputs (incompatible interface).
# Outputs structured signal values to stdout AND writes to <output-file>.

set -euo pipefail

# --- Input validation ---
if [[ $# -ne 3 ]]; then
  echo "error: expected 3 arguments" >&2
  echo "Usage: $0 <stem-dir> <readiness-dir> <output-file>" >&2
  exit 1
fi

stem_dir="$1"
readiness_dir="$2"
output_file="$3"

if [[ ! -d "$stem_dir" ]]; then
  echo "error: stem directory not found: $stem_dir" >&2
  exit 1
fi

# readiness_dir may not exist on first run — handle gracefully
# output_file directory must exist
output_dir="$(dirname "$output_file")"
if [[ ! -d "$output_dir" ]]; then
  echo "error: output directory does not exist: $output_dir" >&2
  exit 1
fi

# --- Parse current run number from manifest ---
manifest_file="$stem_dir/manifest.json"
if [[ ! -f "$manifest_file" ]]; then
  echo "error: manifest.json not found in $stem_dir" >&2
  exit 1
fi

current_run="$(jq -r '.run // empty' "$manifest_file" 2>/dev/null)" || current_run=""
if [[ -z "$current_run" ]]; then
  echo "error: could not parse run number from manifest.json" >&2
  exit 1
fi

plan_path="$(jq -r '.plan_path // empty' "$manifest_file" 2>/dev/null)" || plan_path=""

# --- Locate current readiness report ---
# Convention: .workflows/plan-research/<stem>/readiness/run-<N>/report.md
current_report="$readiness_dir/run-${current_run}/report.md"

# --- Signal 1: Severity distribution ---
# Parse "By severity:" line from readiness report summary
severity_critical="unavailable"
severity_serious="unavailable"
severity_minor="unavailable"
total_findings="unavailable"

if [[ -f "$current_report" ]]; then
  severity_line="$(grep -i 'By severity:' "$current_report" 2>/dev/null | head -1)" || severity_line=""
  if [[ -n "$severity_line" ]]; then
    severity_critical="$(echo "$severity_line" | grep -oE '[0-9]+ CRITICAL' | grep -oE '[0-9]+' || echo "0")"
    severity_serious="$(echo "$severity_line" | grep -oE '[0-9]+ SERIOUS' | grep -oE '[0-9]+' || echo "0")"
    severity_minor="$(echo "$severity_line" | grep -oE '[0-9]+ MINOR' | grep -oE '[0-9]+' || echo "0")"
  fi

  # Parse total findings
  total_line="$(grep -i 'Total findings:' "$current_report" 2>/dev/null | head -1)" || total_line=""
  if [[ -n "$total_line" ]]; then
    total_findings="$(echo "$total_line" | grep -oE '[0-9]+' | head -1 || echo "0")"
  fi
fi

# --- Signal 2: Issue count trend (current vs prior) ---
prior_run=$((current_run - 1))
issue_trend="first-run"
prior_total="unavailable"

if [[ "$prior_run" -ge 1 ]]; then
  # Look for prior readiness report
  prior_report="$readiness_dir/run-${prior_run}/report.md"
  if [[ -f "$prior_report" ]]; then
    prior_total_line="$(grep -i 'Total findings:' "$prior_report" 2>/dev/null | head -1)" || prior_total_line=""
    if [[ -n "$prior_total_line" ]]; then
      prior_total="$(echo "$prior_total_line" | grep -oE '[0-9]+' | head -1 || echo "0")"
    fi

    if [[ "$total_findings" != "unavailable" ]] && [[ "$prior_total" != "unavailable" ]]; then
      if [[ "$total_findings" -lt "$prior_total" ]]; then
        issue_trend="decreasing"
      elif [[ "$total_findings" -gt "$prior_total" ]]; then
        issue_trend="increasing"
      else
        issue_trend="stable"
      fi
    else
      issue_trend="unavailable"
    fi
  else
    # Prior run exists but no readiness report — prior data unavailable
    issue_trend="unavailable"
  fi
fi

# --- Signal 3: Change magnitude ---
# Count distinct Location: values from current readiness report findings
change_magnitude="unavailable"

if [[ -f "$current_report" ]]; then
  location_count="$(grep -c '^\- \*\*Location:\*\*' "$current_report" 2>/dev/null)" || location_count="0"
  # Distinct locations (deduplicate)
  if [[ "$location_count" -gt 0 ]]; then
    change_magnitude="$(grep '^\- \*\*Location:\*\*' "$current_report" 2>/dev/null | sort -u | wc -l | tr -d ' ')" || change_magnitude="0"
  else
    change_magnitude="0"
  fi
fi

# --- Signal 4: Deferred items ---
# Count deferred items from current synthesis summary
deferred_count="unavailable"
synthesis_file="$stem_dir/run-${current_run}-synthesis.md"

if [[ -f "$synthesis_file" ]]; then
  # Look for "Deferred" disposition markers in the synthesis
  # Patterns: "deferred", "Deferred", disposition lines containing "deferred"
  deferred_count="$(grep -ci 'deferred' "$synthesis_file" 2>/dev/null)" || deferred_count="0"
fi

# Deferred trend (compare with prior synthesis)
deferred_trend="first-run"
if [[ "$prior_run" -ge 1 ]]; then
  prior_synthesis="$stem_dir/run-${prior_run}-synthesis.md"
  if [[ -f "$prior_synthesis" ]] && [[ "$deferred_count" != "unavailable" ]]; then
    prior_deferred="$(grep -ci 'deferred' "$prior_synthesis" 2>/dev/null)" || prior_deferred="0"
    if [[ "$deferred_count" -lt "$prior_deferred" ]]; then
      deferred_trend="decreasing"
    elif [[ "$deferred_count" -gt "$prior_deferred" ]]; then
      deferred_trend="increasing"
    else
      deferred_trend="stable"
    fi
  else
    deferred_trend="unavailable"
  fi
fi

# --- Signal 5: Readiness result ---
# passed = zero findings + complete, issues-found = findings exist, failed = check failures
readiness_result="unavailable"

if [[ -f "$current_report" ]]; then
  # Check Complete: field
  complete_line="$(grep -i '^\- \*\*Complete:\*\*' "$current_report" 2>/dev/null | head -1)" || complete_line=""
  is_complete="false"
  if echo "$complete_line" | grep -qi 'true' 2>/dev/null; then
    is_complete="true"
  fi

  if [[ "$total_findings" != "unavailable" ]]; then
    if [[ "$total_findings" -eq 0 ]] && [[ "$is_complete" = "true" ]]; then
      readiness_result="passed"
    elif [[ "$total_findings" -gt 0 ]]; then
      readiness_result="issues-found"
    else
      # Zero findings but not complete — check failures
      readiness_result="failed"
    fi
  else
    # Could not parse findings — check if report mentions failure
    if echo "$complete_line" | grep -qi 'false' 2>/dev/null; then
      readiness_result="failed"
    fi
  fi
fi

# --- Stale prior data detection ---
# Compare plan file hash against hash in prior readiness report's Plan hash: field
stale_prior="unavailable"

if [[ "$prior_run" -ge 1 ]] && [[ -n "$plan_path" ]] && [[ -f "$plan_path" ]]; then
  prior_report="$readiness_dir/run-${prior_run}/report.md"
  if [[ -f "$prior_report" ]]; then
    # Current plan hash
    current_hash="$(md5 -q "$plan_path" 2>/dev/null || md5sum "$plan_path" 2>/dev/null | cut -d' ' -f1)" || current_hash=""

    # Prior report's plan hash
    prior_hash_line="$(grep -i '^\- \*\*Plan hash:\*\*' "$prior_report" 2>/dev/null | head -1)" || prior_hash_line=""
    prior_hash=""
    if [[ -n "$prior_hash_line" ]]; then
      # Extract hash value (typically a 32-char hex string)
      prior_hash="$(echo "$prior_hash_line" | grep -oE '[0-9a-f]{32}' | head -1)" || prior_hash=""
    fi

    if [[ -n "$current_hash" ]] && [[ -n "$prior_hash" ]]; then
      if [[ "$current_hash" = "$prior_hash" ]]; then
        stale_prior="false"
      else
        stale_prior="true"
      fi
    fi
  fi
elif [[ "$prior_run" -lt 1 ]]; then
  stale_prior="not-applicable"
fi

# --- Soft round-count guardrail ---
round_warning=""
if [[ "$current_run" -gt 5 ]]; then
  round_warning="Run count exceeds typical convergence range -- consider whether remaining findings are genuine or systemic."
fi

# --- Output structured signals ---
# Both to stdout (for orchestrator capture) and to output file (debug artifact)
output_signals() {
  echo "## Convergence Signals"
  echo ""
  echo "- **Run:** $current_run"
  echo "- **Issue count trend:** Run $prior_run: ${prior_total} -> Run $current_run: ${total_findings} (${issue_trend})"
  echo "- **Severity distribution:** ${severity_critical} CRITICAL, ${severity_serious} SERIOUS, ${severity_minor} MINOR"
  echo "- **Change magnitude:** ${change_magnitude} sections with findings this run"
  echo "- **Deferred items:** ${deferred_count} (trend: ${deferred_trend})"
  echo "- **Readiness result:** ${readiness_result}"
  echo ""
  echo "## Supporting Data"
  echo ""
  echo "- **Stale prior data:** ${stale_prior}"
  if [[ -n "$round_warning" ]]; then
    echo "- **Round warning:** ${round_warning}"
  fi
  echo "- **Current manifest:** ${manifest_file}"
  echo "- **Current readiness report:** ${current_report}"
  if [[ "$prior_run" -ge 1 ]]; then
    echo "- **Prior readiness report:** ${readiness_dir}/run-${prior_run}/report.md"
  fi
  echo "- **Synthesis file:** ${synthesis_file}"
}

# Write to both stdout and output file
output_signals | tee "$output_file"

exit 0
