#!/usr/bin/env bash
# name: stale-values
# description: "Detect same label appearing with different numeric values across the plan"
# type: mechanical
# verify_only: true
#
# Usage: ./stale-values.sh <plan-file-path> <output-file-path>

set -euo pipefail
source "$(dirname "$0")/lib.sh"

validate_inputs "$@"
start_time="$(date +%s)"

# --- Detection logic ---
findings=""
finding_count=0
critical_count=0
serious_count=0
minor_count=0

# Check if plan has a ## Constants section
has_constants=false
if grep -q '^## Constants' "$plan_file" 2>/dev/null; then
  has_constants=true
fi

if [[ "$has_constants" = true ]]; then
  # Mode (a): Verify references match defined constants
  # Extract constants from the ## Constants section
  in_constants=false
  constants_labels=()
  constants_values=()
  while IFS= read -r line; do
    if [[ "$line" =~ ^"## Constants" ]]; then
      in_constants=true
      continue
    fi
    if [[ "$in_constants" = true ]] && [[ "$line" =~ ^"## " ]] && [[ ! "$line" =~ ^"## Constants" ]]; then
      break
    fi
    if [[ "$in_constants" = true ]]; then
      # Match patterns like: label: 42, label = 42, `label`: 42, - label: 42
      if echo "$line" | grep -Eq '[`_a-zA-Z][-_a-zA-Z0-9]*[`]?[[:space:]]*[:=][[:space:]]*[0-9]+'; then
        label="$(echo "$line" | sed -E 's/^[[:space:]]*[-*]*[[:space:]]*[`]?([_a-zA-Z][-_a-zA-Z0-9]*)[`]?[[:space:]]*[:=].*/\1/')"
        value="$(echo "$line" | sed -E 's/.*[:=][[:space:]]*([0-9]+).*/\1/')"
        if [[ -n "$label" ]] && [[ -n "$value" ]]; then
          constants_labels+=("$label")
          constants_values+=("$value")
        fi
      fi
    fi
  done < "$plan_file"

  # Check each constant label for mismatched values elsewhere in the plan
  idx=0
  while [[ "$idx" -lt "${#constants_labels[@]}" ]]; do
    label="${constants_labels[$idx]}"
    expected="${constants_values[$idx]}"
    line_num=0
    in_constants_section=false
    in_fence=false
    while IFS= read -r line; do
      line_num=$((line_num + 1))
      # Track code fences
      if [[ "$line" =~ ^'```' ]]; then
        if [[ "$in_fence" = true ]]; then
          in_fence=false
        else
          in_fence=true
        fi
        continue
      fi
      if [[ "$in_fence" = true ]]; then
        continue
      fi
      if [[ "$line" =~ ^"## Constants" ]]; then
        in_constants_section=true
        continue
      fi
      if [[ "$in_constants_section" = true ]] && [[ "$line" =~ ^"## " ]] && [[ ! "$line" =~ ^"## Constants" ]]; then
        in_constants_section=false
      fi
      # Skip the constants section itself
      if [[ "$in_constants_section" = true ]]; then
        continue
      fi
      # Look for the label with a number
      if echo "$line" | grep -Fq "$label"; then
        # Extract numbers near the label
        numbers="$(echo "$line" | grep -oE '[0-9]+' || true)"
        while IFS= read -r num; do
          [[ -z "$num" ]] && continue
          if [[ "$num" != "$expected" ]]; then
            # Only flag if the number could plausibly be the same constant
            # (same order of magnitude: both 1-3 digits, both 4+ digits, etc.)
            expected_len="${#expected}"
            num_len="${#num}"
            if [[ "$num_len" -ge $((expected_len - 1)) ]] && [[ "$num_len" -le $((expected_len + 1)) ]]; then
              section="$(get_section_heading "$plan_file" "$line_num")"
              findings="${findings}
### [SERIOUS] Constant mismatch: $label
- **Check:** stale-values
- **Location:** $section
- **Description:** Label \`$label\` defined as $expected in Constants but appears near value $num
- **Values:** Expected=$expected, Found=$num
- **Suggested fix:** Update to match the Constants-defined value of $expected
"
              finding_count=$((finding_count + 1))
              serious_count=$((serious_count + 1))
            fi
          fi
        done <<< "$numbers"
      fi
    done < "$plan_file"
    idx=$((idx + 1))
  done

else
  # Mode (b): Find identical labels with different numeric values
  # Extract label-value pairs: patterns like label_name: 42, label-name = 100, `max_retries`: 3
  # We use a temp file to store label/value/line associations (bash 3.2 compatible - no associative arrays)
  label_data_file="$(mktemp)"
  trap 'rm -f "$label_data_file"' EXIT

  line_num=0
  in_fence=false
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    # Track code fences to skip code block content
    if [[ "$line" =~ ^'```' ]]; then
      if [[ "$in_fence" = true ]]; then
        in_fence=false
      else
        in_fence=true
      fi
      continue
    fi
    # Skip content inside code fences, markdown headings, and empty lines
    if [[ "$in_fence" = true ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
      continue
    fi
    # Extract label-number pairs: word_chars followed by : or = then a number
    # Pattern: `label` or label followed by :, =, or space then number
    matches="$(echo "$line" | grep -oE '[`]?[_a-zA-Z][_a-zA-Z0-9]*[-_a-zA-Z0-9]*[`]?[[:space:]]*[:=][[:space:]]*[0-9]+' || true)"
    if [[ -n "$matches" ]]; then
      while IFS= read -r match; do
        label="$(echo "$match" | sed -E 's/^[`]?([_a-zA-Z][-_a-zA-Z0-9]*)[`]?[[:space:]]*[:=].*/\1/')"
        value="$(echo "$match" | sed -E 's/.*[:=][[:space:]]*([0-9]+).*/\1/')"
        if [[ -n "$label" ]] && [[ -n "$value" ]]; then
          echo "${label}	${value}	${line_num}" >> "$label_data_file"
        fi
      done <<< "$matches"
    fi
  done < "$plan_file"

  # Find labels that appear with different values
  if [[ -s "$label_data_file" ]]; then
    # Get unique labels
    unique_labels="$(cut -f1 "$label_data_file" | sort -u)"
    while IFS= read -r label; do
      [[ -z "$label" ]] && continue
      # Get all distinct values for this label
      values="$(grep -F "	" "$label_data_file" | awk -F'\t' -v lbl="$label" '$1 == lbl { print $2 }' | sort -u)"
      value_count="$(echo "$values" | wc -l | tr -d ' ')"
      if [[ "$value_count" -gt 1 ]]; then
        # Found a mismatch - collect locations
        first_value=""
        locations_detail=""
        while IFS= read -r entry; do
          entry_label="$(echo "$entry" | cut -f1)"
          entry_value="$(echo "$entry" | cut -f2)"
          entry_line="$(echo "$entry" | cut -f3)"
          if [[ "$entry_label" = "$label" ]]; then
            section="$(get_section_heading "$plan_file" "$entry_line")"
            locations_detail="${locations_detail}  - Value $entry_value at $section
"
            if [[ -z "$first_value" ]]; then
              first_value="$entry_value"
            fi
          fi
        done < "$label_data_file"

        all_values="$(echo "$values" | tr '\n' ', ' | sed 's/,$//')"
        # First occurrence gets priority - report at first mismatch location
        first_section="$(grep -F "	" "$label_data_file" | awk -F'\t' -v lbl="$label" '$1 == lbl { print $3; exit }')"
        section="$(get_section_heading "$plan_file" "$first_section")"

        findings="${findings}
### [SERIOUS] Inconsistent values for: $label
- **Check:** stale-values
- **Location:** $section
- **Description:** Label \`$label\` appears with ${value_count} different numeric values
- **Values:** $all_values
- **Suggested fix:** Ensure all references to \`$label\` use the same value, or add a Constants section to define the canonical value
"
        finding_count=$((finding_count + 1))
        serious_count=$((serious_count + 1))
      fi
    done <<< "$unique_labels"
  fi
fi

# --- Output generation ---
end_time="$(date +%s)"
elapsed=$((end_time - start_time))

{
  echo "status: success"
  echo ""
  if [[ "$finding_count" -eq 0 ]]; then
    echo "## Findings"
    echo ""
    echo "No applicable patterns found."
    echo ""
  else
    # Output cap: 150-200 lines. Preserve CRITICAL/SERIOUS, truncate MINOR.
    echo "## Findings"
    echo "$findings"
  fi
  echo "## Summary"
  echo "- Total findings: $finding_count"
  echo "- By severity: $critical_count CRITICAL, $serious_count SERIOUS, $minor_count MINOR"
  echo "- Check completed in: ${elapsed} seconds"
} > "$tmp_file"

truncate_output

mv "$tmp_file" "$output_file"
exit 0
