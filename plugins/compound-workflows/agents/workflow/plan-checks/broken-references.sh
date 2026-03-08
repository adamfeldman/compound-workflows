#!/usr/bin/env bash
# name: broken-references
# description: "Detect cross-references pointing to wrong or non-existent targets"
# type: mechanical
# verify_only: true
#
# Usage: ./broken-references.sh <plan-file-path> <output-file-path>

set -euo pipefail
source "$(dirname "$0")/lib.sh"

validate_inputs "$@"

# Resolve project root (git root or plan file's directory as fallback)
project_root="$(cd "$(dirname "$plan_file")" && git rev-parse --show-toplevel 2>/dev/null)" || {
  project_root="$(cd "$(dirname "$plan_file")" && pwd -P)"
}

start_time="$(date +%s)"

# --- Build reference index ---
# Collect all defined targets in the plan

# 1. Section headings (for "Step N", "### heading" references)
headings_file="$(mktemp)"
steps_file="$(mktemp)"
ref_ids_file="$(mktemp)"
decision_ids_file="$(mktemp)"
findings_file="$(mktemp)"
trap 'rm -f "$headings_file" "$steps_file" "$ref_ids_file" "$decision_ids_file" "$findings_file"' EXIT

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
  if [[ "$in_fence" = true ]]; then
    continue
  fi
  if [[ "$line" =~ ^#{1,6}[[:space:]] ]]; then
    echo "$line" >> "$headings_file"
    # Extract step numbers from headings like "### Step 1:", "### Step 4.2:"
    step="$(echo "$line" | grep -oE 'Step [0-9]+(\.[0-9]+)?' || true)"
    if [[ -n "$step" ]]; then
      echo "$step" >> "$steps_file"
    fi
  fi
  # Extract defined reference IDs like (R1), (S1), (D1) when they appear to be definitions
  # Definitions are typically at the start or in a definition context
  ref_defs="$(echo "$line" | grep -oE '\([A-Z][0-9]+\)' || true)"
  if [[ -n "$ref_defs" ]]; then
    while IFS= read -r ref; do
      echo "$ref" >> "$ref_ids_file"
    done <<< "$ref_defs"
  fi
  # Extract Decision #N definitions
  decision_defs="$(echo "$line" | grep -oE 'Decision #[0-9]+' || true)"
  if [[ -n "$decision_defs" ]]; then
    while IFS= read -r dec; do
      echo "$dec" >> "$decision_ids_file"
    done <<< "$decision_defs"
  fi
done < "$plan_file"

# Deduplicate reference indices
if [[ -s "$ref_ids_file" ]]; then
  sort -u "$ref_ids_file" > "${ref_ids_file}.dedup"
  mv "${ref_ids_file}.dedup" "$ref_ids_file"
fi
if [[ -s "$decision_ids_file" ]]; then
  sort -u "$decision_ids_file" > "${decision_ids_file}.dedup"
  mv "${decision_ids_file}.dedup" "$decision_ids_file"
fi
if [[ -s "$steps_file" ]]; then
  sort -u "$steps_file" > "${steps_file}.dedup"
  mv "${steps_file}.dedup" "$steps_file"
fi

# --- Check references ---
finding_count=0
critical_count=0
serious_count=0
minor_count=0

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
  if [[ "$in_fence" = true ]]; then
    continue
  fi

  # 1. Check parenthetical reference IDs: (R12), (S3), etc.
  #    Only check references that look like back-references (not definitions)
  #    We check ALL occurrences but verify they exist somewhere in the file
  refs="$(echo "$line" | grep -oE '\([A-Z][0-9]+\)' || true)"
  if [[ -n "$refs" ]]; then
    while IFS= read -r ref; do
      # Check if this ref exists in the file at least twice (definition + reference)
      # or at least once (could be a reference to something defined elsewhere)
      ref_count="$(grep -cF "$ref" "$plan_file" 2>/dev/null || echo "0")"
      if [[ "$ref_count" -lt 2 ]]; then
        # Only one occurrence means it references something not defined elsewhere
        # But we should check if there's a corresponding definition pattern
        # e.g., (R1) should have at least a definition somewhere
        inner="$(echo "$ref" | tr -d '()')"
        letter="$(echo "$inner" | sed -E 's/[0-9]+//')"
        number="$(echo "$inner" | sed -E 's/[A-Z]//')"
        # Check if this is an isolated reference (appears only once in the whole file)
        if [[ "$ref_count" -eq 1 ]]; then
          section="$(get_section_heading "$plan_file" "$line_num")"
          echo "### [MINOR] Isolated reference: $ref
- **Check:** broken-references
- **Location:** $section
- **Description:** Reference $ref appears only once in the plan -- if this is a cross-reference, its target is missing
- **Values:** Reference=$ref, Occurrences=$ref_count
- **Suggested fix:** Add the target definition for $ref or remove the dangling reference
" >> "$findings_file"
          finding_count=$((finding_count + 1))
          minor_count=$((minor_count + 1))
        fi
      fi
    done <<< "$refs"
  fi

  # 2. Check "Step N" or "Step N.N" references (not in headings)
  if [[ ! "$line" =~ ^#{1,6}[[:space:]] ]]; then
    step_refs="$(echo "$line" | grep -oE 'Step [0-9]+(\.[0-9]+)?' || true)"
    if [[ -n "$step_refs" ]]; then
      while IFS= read -r step_ref; do
        if [[ -s "$steps_file" ]]; then
          if ! grep -qF "$step_ref" "$steps_file" 2>/dev/null; then
            section="$(get_section_heading "$plan_file" "$line_num")"
            echo "### [SERIOUS] Broken step reference: $step_ref
- **Check:** broken-references
- **Location:** $section
- **Description:** Reference to \"$step_ref\" but no heading defines this step
- **Values:** Reference=$step_ref
- **Suggested fix:** Verify the step number is correct or add the missing step heading
" >> "$findings_file"
            finding_count=$((finding_count + 1))
            serious_count=$((serious_count + 1))
          fi
        fi
      done <<< "$step_refs"
    fi
  fi

  # 3. Check "Decision #N" references
  decision_refs="$(echo "$line" | grep -oE 'Decision #[0-9]+' || true)"
  if [[ -n "$decision_refs" ]]; then
    while IFS= read -r dec_ref; do
      dec_count="$(grep -cF "$dec_ref" "$plan_file" 2>/dev/null || echo "0")"
      if [[ "$dec_count" -lt 2 ]]; then
        section="$(get_section_heading "$plan_file" "$line_num")"
        echo "### [SERIOUS] Isolated Decision reference: $dec_ref
- **Check:** broken-references
- **Location:** $section
- **Description:** \"$dec_ref\" appears only once -- if referencing a decision defined elsewhere, the target is missing
- **Values:** Reference=$dec_ref, Occurrences=$dec_count
- **Suggested fix:** Verify the decision number exists or add the missing decision definition
" >> "$findings_file"
        finding_count=$((finding_count + 1))
        serious_count=$((serious_count + 1))
      fi
    done <<< "$decision_refs"
  fi

  # 4. Check file path references (paths containing / that look like file references)
  #    Only check paths that look like project-relative paths, not URLs
  file_refs="$(echo "$line" | grep -oE '`[a-zA-Z0-9_./-]+/[a-zA-Z0-9_./-]+`' || true)"
  if [[ -n "$file_refs" ]]; then
    while IFS= read -r file_ref; do
      # Strip backticks
      ref_path="$(echo "$file_ref" | tr -d '`')"
      # Skip URLs, protocol references, and glob patterns
      if echo "$ref_path" | grep -qE '(https?://|ftp://|\*)'; then
        continue
      fi
      # Flag ../ paths as suspicious instead of silently skipping
      if echo "$ref_path" | grep -qF '../'; then
        section="$(get_section_heading "$plan_file" "$line_num")"
        echo "### [MINOR] Suspicious path traversal reference
- **Check:** broken-references
- **Location:** $section
- **Description:** Reference contains \`../\` path traversal: \`$ref_path\`
- **Suggested fix:** Use a path relative to the project root instead of relative parent traversal
" >> "$findings_file"
        finding_count=$((finding_count + 1))
        minor_count=$((minor_count + 1))
        continue
      fi
      # Skip if it looks like a namespace or command reference (contains :)
      if echo "$ref_path" | grep -qF ':'; then
        continue
      fi
      # Resolve relative to project root
      full_path="${project_root}/${ref_path}"
      # Validate the resolved path stays within project directory
      if [[ -e "$full_path" ]]; then
        resolved="$(cd "$(dirname "$full_path")" 2>/dev/null && pwd -P)/$(basename "$full_path")" || continue
        case "$resolved" in
          "${project_root}/"*) ;; # OK - within project
          *)
            section="$(get_section_heading "$plan_file" "$line_num")"
            echo "### [CRITICAL] Path traversal: $ref_path
- **Check:** broken-references
- **Location:** $section
- **Description:** File reference \`$ref_path\` resolves outside the project directory
- **Values:** Resolved=$resolved, Project root=$project_root
- **Suggested fix:** Fix the path to stay within the project directory
" >> "$findings_file"
            finding_count=$((finding_count + 1))
            critical_count=$((critical_count + 1))
            ;;
        esac
      fi
      # Note: we don't flag missing files as broken references since the plan
      # may reference files that will be created during implementation
    done <<< "$file_refs"
  fi

done < "$plan_file"

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
    echo ""
    if [[ -s "$findings_file" ]]; then
      cat "$findings_file"
    fi
  fi
  echo "## Summary"
  echo "- Total findings: $finding_count"
  echo "- By severity: $critical_count CRITICAL, $serious_count SERIOUS, $minor_count MINOR"
  echo "- Check completed in: ${elapsed} seconds"
} > "$tmp_file"

truncate_output

mv "$tmp_file" "$output_file"
exit 0
