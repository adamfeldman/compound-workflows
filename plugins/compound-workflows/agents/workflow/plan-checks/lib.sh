# Shared library for plan-check scripts
# Sourced (not executed directly) -- do NOT add a shebang or make executable
#
# Provides:
#   validate_inputs   -- arg count, file existence, output dir resolution, overwrite guard
#   get_section_heading -- markdown section heading for a given line number
#   truncate_output   -- cap output file at 150 lines

# --- Input validation ---
# Sets: plan_file, output_file, tmp_file
# Exits on error.
validate_inputs() {
  if [[ $# -ne 2 ]]; then
    echo "status: error" >&2
    echo "Usage: $0 <plan-file-path> <output-file-path>" >&2
    exit 1
  fi

  plan_file="$1"
  output_file="$2"

  if [[ ! -f "$plan_file" ]]; then
    echo "status: error" >&2
    echo "Plan file not found: $plan_file" >&2
    exit 1
  fi

  local output_dir
  output_dir="$(cd "$(dirname "$output_file")" 2>/dev/null && pwd -P)" || {
    echo "status: error" >&2
    echo "Output directory does not exist: $(dirname "$output_file")" >&2
    exit 1
  }
  output_file="$output_dir/$(basename "$output_file")"

  if [[ "$plan_file" = "$output_file" ]]; then
    echo "Error: output path must differ from plan file path" >&2
    exit 1
  fi

  tmp_file="${output_file}.tmp"
}

# --- Helper: get current section heading for a line number ---
# Tracks code fences to avoid treating shell comments as markdown headings
get_section_heading() {
  local file="$1"
  local target_line="$2"
  local heading=""
  local line_num=0
  local in_fence=false
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    if [[ "$line" =~ ^'```' ]]; then
      if [[ "$in_fence" = true ]]; then
        in_fence=false
      else
        in_fence=true
      fi
    fi
    if [[ "$in_fence" = false ]] && [[ "$line" =~ ^#{1,6}[[:space:]] ]]; then
      heading="$line"
    fi
    if [[ "$line_num" -eq "$target_line" ]]; then
      break
    fi
  done < "$file"
  if [[ -n "$heading" ]]; then
    echo "$heading"
  else
    echo "(before first heading)"
  fi
}

# --- Truncation: cap output at 150 lines ---
# Operates on $tmp_file (must be set by caller via validate_inputs)
truncate_output() {
  local line_count
  line_count="$(wc -l < "$tmp_file" | tr -d ' ')"
  if [[ "$line_count" -gt 150 ]]; then
    head -n 140 "$tmp_file" > "${tmp_file}.trunc"
    echo "" >> "${tmp_file}.trunc"
    echo "Output truncated at 140 lines. Additional findings omitted -- see full analysis for details." >> "${tmp_file}.trunc"
    echo "" >> "${tmp_file}.trunc"
    tail -n 5 "$tmp_file" >> "${tmp_file}.trunc"
    mv "${tmp_file}.trunc" "$tmp_file"
  fi
}
