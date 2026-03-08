#!/usr/bin/env bash
# name: audit-trail-bloat
# description: "Detect annotation bloat exceeding 30% of plan content"
# type: mechanical
# verify_only: true
#
# Usage: ./audit-trail-bloat.sh <plan-file-path> <output-file-path>

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

total_lines=0
annotation_lines=0
spec_lines=0
annotation_sections=""
in_annotation=false
annotation_start_line=0
current_annotation_heading=""
annotation_section_count=0

# Patterns that indicate annotation/review sections:
# - "Run N Review Findings", "Run N Findings"
# - "Review Findings", "Deepen Findings"
# - "Audit Trail", "Change Log", "Review Log"
# - Sections starting with "Run [0-9]"

while IFS= read -r line; do
  total_lines=$((total_lines + 1))

  # Check if this line is a heading that starts an annotation section
  if [[ "$line" =~ ^#{1,6}[[:space:]] ]]; then
    # End previous annotation section if active
    if [[ "$in_annotation" = true ]]; then
      in_annotation=false
    fi

    # Check if this heading starts an annotation section
    is_annotation_heading=false
    if echo "$line" | grep -qEi 'Run [0-9]+ (Review )?Findings'; then
      is_annotation_heading=true
    elif echo "$line" | grep -qEi 'Run [0-9]+ '; then
      is_annotation_heading=true
    elif echo "$line" | grep -qEi '(Audit Trail|Change ?Log|Review Log|Revision History)'; then
      is_annotation_heading=true
    elif echo "$line" | grep -qEi '^#{1,6} (Review|Deepen|Synthesis) Findings'; then
      is_annotation_heading=true
    fi

    if [[ "$is_annotation_heading" = true ]]; then
      in_annotation=true
      annotation_start_line="$total_lines"
      current_annotation_heading="$line"
      annotation_section_count=$((annotation_section_count + 1))
      annotation_sections="${annotation_sections}
  - $line (line $total_lines)"
    fi
  fi

  if [[ "$in_annotation" = true ]]; then
    annotation_lines=$((annotation_lines + 1))
  else
    spec_lines=$((spec_lines + 1))
  fi
done < "$plan_file"

# --- Calculate ratios and generate findings ---

if [[ "$total_lines" -eq 0 ]]; then
  annotation_pct=0
else
  # Integer arithmetic: multiply by 100 first to get percentage
  annotation_pct=$((annotation_lines * 100 / total_lines))
fi

# Finding 1: Annotation bloat exceeding 30%
if [[ "$annotation_pct" -gt 30 ]]; then
  severity="SERIOUS"
  if [[ "$annotation_pct" -gt 50 ]]; then
    severity="CRITICAL"
    critical_count=$((critical_count + 1))
  else
    serious_count=$((serious_count + 1))
  fi
  findings="${findings}
### [$severity] Annotation bloat detected
- **Check:** audit-trail-bloat
- **Location:** (multiple annotation sections)
- **Description:** Annotation/review sections comprise ${annotation_pct}% of plan content (threshold: 30%)
- **Values:** Total lines=$total_lines, Spec lines=$spec_lines, Annotation lines=$annotation_lines, Ratio=${annotation_pct}%
- **Suggested fix:** Run plan-consolidator to integrate review findings into the spec and remove resolved annotations
"
  finding_count=$((finding_count + 1))
fi

# Finding 2: Individual annotation sections that are very large
if [[ "$annotation_section_count" -gt 0 ]]; then
  # Re-scan to get per-section line counts
  in_annotation=false
  section_line_count=0
  section_heading=""
  line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))

    if [[ "$line" =~ ^#{1,6}[[:space:]] ]]; then
      # Report previous annotation section if it was large
      if [[ "$in_annotation" = true ]] && [[ "$section_line_count" -gt 30 ]]; then
        findings="${findings}
### [MINOR] Large annotation section: ${section_line_count} lines
- **Check:** audit-trail-bloat
- **Location:** $section_heading
- **Description:** Annotation section has $section_line_count lines, consuming review context budget
- **Values:** Section lines=$section_line_count
- **Suggested fix:** Consolidate findings from this section into the relevant spec sections and remove
"
        finding_count=$((finding_count + 1))
        minor_count=$((minor_count + 1))
      fi

      in_annotation=false
      section_line_count=0

      # Check if new annotation section
      is_annotation_heading=false
      if echo "$line" | grep -qEi 'Run [0-9]+ (Review )?Findings'; then
        is_annotation_heading=true
      elif echo "$line" | grep -qEi 'Run [0-9]+ '; then
        is_annotation_heading=true
      elif echo "$line" | grep -qEi '(Audit Trail|Change ?Log|Review Log|Revision History)'; then
        is_annotation_heading=true
      elif echo "$line" | grep -qEi '^#{1,6} (Review|Deepen|Synthesis) Findings'; then
        is_annotation_heading=true
      fi

      if [[ "$is_annotation_heading" = true ]]; then
        in_annotation=true
        section_heading="$line"
      fi
    fi

    if [[ "$in_annotation" = true ]]; then
      section_line_count=$((section_line_count + 1))
    fi
  done < "$plan_file"

  # Handle last section
  if [[ "$in_annotation" = true ]] && [[ "$section_line_count" -gt 30 ]]; then
    findings="${findings}
### [MINOR] Large annotation section: ${section_line_count} lines
- **Check:** audit-trail-bloat
- **Location:** $section_heading
- **Description:** Annotation section has $section_line_count lines, consuming review context budget
- **Values:** Section lines=$section_line_count
- **Suggested fix:** Consolidate findings from this section into the relevant spec sections and remove
"
    finding_count=$((finding_count + 1))
    minor_count=$((minor_count + 1))
  fi
fi

# Finding 3: Check for contradiction indicators within annotations
# Look for annotations that say "changed", "updated", "was X now Y", "no longer"
# within annotation sections, then check if the referenced text matches
if [[ "$annotation_section_count" -gt 0 ]]; then
  in_annotation=false
  line_num=0
  contradiction_count=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))

    if [[ "$line" =~ ^#{1,6}[[:space:]] ]]; then
      is_annotation_heading=false
      if echo "$line" | grep -qEi 'Run [0-9]+ (Review )?Findings'; then
        is_annotation_heading=true
      elif echo "$line" | grep -qEi 'Run [0-9]+ '; then
        is_annotation_heading=true
      elif echo "$line" | grep -qEi '(Audit Trail|Change ?Log|Review Log|Revision History)'; then
        is_annotation_heading=true
      elif echo "$line" | grep -qEi '^#{1,6} (Review|Deepen|Synthesis) Findings'; then
        is_annotation_heading=true
      fi
      in_annotation="$is_annotation_heading"
    fi

    if [[ "$in_annotation" = true ]]; then
      # Look for stale annotation markers
      if echo "$line" | grep -qEi '(was previously|no longer|changed from|replaced by|deprecated|removed|obsolete)'; then
        contradiction_count=$((contradiction_count + 1))
        if [[ "$contradiction_count" -le 5 ]]; then
          section="$(get_section_heading "$plan_file" "$line_num")"
          # Truncate long lines for display
          display_line="$line"
          if [[ "${#display_line}" -gt 120 ]]; then
            display_line="${display_line:0:117}..."
          fi
          findings="${findings}
### [MINOR] Potentially stale annotation
- **Check:** audit-trail-bloat
- **Location:** $section
- **Description:** Annotation references a change that may have already been applied: \"$display_line\"
- **Values:** N/A
- **Suggested fix:** Verify the referenced change was applied to the spec, then remove this annotation
"
          finding_count=$((finding_count + 1))
          minor_count=$((minor_count + 1))
        fi
      fi
    fi
  done < "$plan_file"

  if [[ "$contradiction_count" -gt 5 ]]; then
    findings="${findings}
### [MINOR] Many potential stale annotations
- **Check:** audit-trail-bloat
- **Location:** (multiple annotation sections)
- **Description:** Found $contradiction_count annotations referencing changes -- only first 5 shown
- **Values:** Total stale annotation indicators=$contradiction_count
- **Suggested fix:** Review all annotations and remove those whose changes have been applied
"
    finding_count=$((finding_count + 1))
    minor_count=$((minor_count + 1))
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
    echo "## Findings"
    echo "$findings"
  fi
  echo "## Statistics"
  echo "- Total lines: $total_lines"
  echo "- Spec lines: $spec_lines"
  echo "- Annotation lines: $annotation_lines"
  echo "- Annotation ratio: ${annotation_pct}%"
  echo "- Annotation sections found: $annotation_section_count"
  if [[ -n "$annotation_sections" ]]; then
    echo "- Annotation sections:$annotation_sections"
  fi
  echo ""
  echo "## Summary"
  echo "- Total findings: $finding_count"
  echo "- By severity: $critical_count CRITICAL, $serious_count SERIOUS, $minor_count MINOR"
  echo "- Check completed in: ${elapsed} seconds"
} > "$tmp_file"

truncate_output

mv "$tmp_file" "$output_file"
exit 0
