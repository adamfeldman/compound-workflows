---
title: "fix: Remove .tmp→mv atomic write pattern from LLM agents"
type: fix
status: completed
date: 2026-03-12
---

# Remove .tmp→mv Atomic Write Pattern from LLM Agents

## Summary

Two LLM-interpreted files instruct agents to write to `.tmp` then `mv` to the final path — a shell atomicity pattern that's unnecessary with the Write tool (already atomic). This causes `mv` permission prompts. Fix the two files, add a QA script to prevent recurrence, and update file counts.

## Background

**Root cause:** The `.tmp→mv` pattern originated in `lib.sh` (legitimate for bash scripts) and was cargo-culted into agent/skill prompts where the Write tool is the correct primitive.

**Impact:** Every invocation of semantic-checks or classify-stats triggers unnecessary permission prompts:
- semantic-checks: 1 `mv` prompt per invocation (every plan readiness check)
- classify-stats: 1 `mv` + 1 `<<` heredoc prompt per file per invocation

**Correct pattern:** All other agents/skills use direct Write tool writes with no `.tmp` intermediary (disk-persist-agents canonical pattern, do-work sentinel/scratch files, all research agents).

## Scope

### In scope

1. **Remove `.tmp→mv` from semantic-checks.md** (2 line edits)
2. **Remove `.tmp→mv` from classify-stats/SKILL.md** (rewrite steps 4-5, remove bash example, update Rules)
3. **New QA script** `no-shell-atomicity.sh` to prevent recurrence
4. **Update file counts** in CLAUDE.md, AGENTS.md, README.md (7→8 scripts)
5. **Version bump** to 3.0.2 (PATCH)

### Out of scope (with rationale)

- **`lib.sh` line 41** — Legitimate shell atomicity for plan-check bash scripts. KEEP.
- **`do-plan/SKILL.md` line 344 and `do-deepen-plan/SKILL.md` line 1089** — Orchestrator `rm -f *.tmp` cleanup for shell script timeout orphans. These are valid because shell scripts (via lib.sh) still produce `.tmp` files. KEEP.
- **Worktree relative paths in do-work/SKILL.md** — SpecFlow analysis (see `.workflows/plan-research/remove-tmp-mv-pattern/agents/specflow.md`, Gaps 9-11) determined that sentinel and scratch paths work correctly in worktrees: the sentinel is created/cleared/checked within the same cwd (the worktree), and the hook resolves relative to cwd. The bead notes' "cd+write heuristic" claim likely refers to the `date +%s >` redirect prompt in Phase 1.2.1, which is a separate issue already accepted in the permission-prompt-optimization plan. Removing from scope to keep this fix focused.

## Implementation

### Step 1: Fix semantic-checks.md

File: `plugins/compound-workflows/agents/workflow/plan-checks/semantic-checks.md`

**Edit 1 — Line 53 (Execution Procedure step 6):**

Replace:
```
6. Write the output file to `output_path.tmp` first, then move to `output_path` (atomic write).
```
With:
```
6. Write the output file to `output_path`.
```

**Edit 2 — Line 179 (Output Template section):**

Replace:
```
Write the output to `output_path.tmp`, then move to `output_path`.
```
With:
```
Write the output to `output_path`.
```

### Step 2: Fix classify-stats/SKILL.md

File: `plugins/compound-workflows/skills/classify-stats/SKILL.md`

**Edit 1 — Lines 204-215 (the numbered steps 4-5 under "Phase 4 > Apply Classifications" + the bash code example):**

Replace numbered steps 4-5 and the bash code example with a single step, then renumber step 6→5 (the "Important" note about preserving fields stays as the next paragraph, no step number needed):
```
4. **Write** the modified content to `<filename>` using the Write tool
```

Remove the entire bash code block (lines 207-215: `cat > ... << 'YAML_EOF'` ... `mv`). The downstream "Important" paragraph (line 217) is unnumbered prose — no renumbering needed.

**Edit 2 — Line 245 (Rules section):**

Replace:
```
- **Non-destructive**: Uses tmp+mv atomic write strategy. Original files are never partially overwritten.
```
With:
```
- **Non-destructive**: Write tool writes are atomic. Original files are never partially overwritten.
```

### Step 3: Add QA script `no-shell-atomicity.sh`

File: `plugins/compound-workflows/scripts/plugin-qa/no-shell-atomicity.sh`

**Design:** Follow `unslugged-paths.sh` as structural template (newest script, cleanest pattern).

**Scan scope:** Same as context-lean-grep.sh Check 5:
- `commands/compound/*.md`
- `skills/*/SKILL.md`
- `agents/**/*.md` (recursively, excluding `*/references/*`)

**Detection:**
- Pattern: lines containing `\.tmp` (literal dot + tmp)
- Exempt: lines matching `rm -f` or `rm ` (orchestrator cleanup commands)
- Exempt: lines with `# shell-atomicity-exempt` marker
- Exempt: CHANGELOG.md (historical)
- Do NOT skip code blocks (they're executable instructions, not documentation — same rationale as context-lean-grep.sh)

**Exclude from scan:**
- `.sh` files (legitimate shell — lib.sh, plan-check scripts)
- `*/references/*` subdirectories (illustrative content)

**Severity:** SERIOUS (causes `mv` permission prompts)

**Structure:**
```bash
#!/usr/bin/env bash
# name: no-shell-atomicity
# description: Detect .tmp atomic write instructions in LLM-interpreted files
#
# Shell atomicity patterns (.tmp→mv) are legitimate in .sh scripts but
# unnecessary in agent/skill .md files where the Write tool is atomic.
#
# Usage: ./no-shell-atomicity.sh [plugin-root-path]

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/lib.sh"

resolve_plugin_root "${1:-}"
init_findings

# --- Collect scannable files ---
# commands/compound/*.md, skills/*/SKILL.md, agents/**/*.md (excluding references/)

scan_files=()

cmd_dir="$PLUGIN_ROOT/commands/compound"
if [[ -d "$cmd_dir" ]]; then
  for f in "$cmd_dir"/*.md; do
    [[ -f "$f" ]] || continue
    scan_files+=("$f")
  done
fi

for f in "$PLUGIN_ROOT"/skills/*/SKILL.md; do
  [[ -f "$f" ]] || continue
  scan_files+=("$f")
done

while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  case "$f" in */references/*) continue ;; esac
  scan_files+=("$f")
done < <(find "$PLUGIN_ROOT/agents" -name "*.md" 2>/dev/null)

if [[ "${#scan_files[@]}" -eq 0 ]]; then
  echo "Warning: no scannable files found" >&2
  emit_output "Shell Atomicity in Prompts Check"
  exit 0
fi

# --- Grep for .tmp and filter exemptions ---

for f in "${scan_files[@]}"; do
  matches="$(grep -nE '\.tmp' "$f" || true)"
  [[ -n "$matches" ]] || continue

  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    line_num="$(echo "$match" | cut -d: -f1)"
    line_text="$(echo "$match" | cut -d: -f2-)"

    # Exempt: rm -f cleanup lines (orchestrator cleanup)
    case "$line_text" in
      *"rm -f"*|*"rm "*) continue ;;
    esac

    # Exempt: lines with shell-atomicity-exempt marker
    case "$line_text" in
      *"shell-atomicity-exempt"*) continue ;;
    esac

    add_finding "SERIOUS" "$f" "$line_num" "shell-atomicity-in-prompt" \
      ".tmp atomic write pattern in LLM-interpreted file — use Write tool (already atomic)"
  done <<< "$matches"
done

emit_output "Shell Atomicity in Prompts Check"
exit 0
```

### Step 4: Update file counts

Update the script count from 7 to 8 in all locations:
- [ ] `plugins/compound-workflows/CLAUDE.md` — scripts section table and `scripts/plugin-qa/` directory listing comment
- [ ] `AGENTS.md` — "7 scripts + lib.sh" → "8 scripts + lib.sh" in the plugin-qa description
- [ ] `plugins/compound-workflows/README.md` — update QA script count from "7 bash scripts" to "8 bash scripts" in the plugin-qa section; verify no other count references

Also add the new script to the CLAUDE.md scripts section description table:
`| no-shell-atomicity.sh | Detect .tmp atomic write instructions in LLM-interpreted files |`

And to the AGENTS.md QA scripts table:
`| `no-shell-atomicity.sh` | Detect .tmp atomic write instructions in LLM-interpreted files |`

### Step 5: Version bump and changelog

- [ ] Bump version to 3.0.2 in `plugins/compound-workflows/.claude-plugin/plugin.json`
- [ ] Bump version to 3.0.2 in `.claude-plugin/marketplace.json`
- [ ] Add CHANGELOG.md entry:

```markdown
## 3.0.2 — 2026-03-12

### Fixed

- **Remove .tmp→mv from LLM agents** — semantic-checks.md and classify-stats/SKILL.md no longer instruct agents to write to `.tmp` then `mv`. The Write tool is already atomic; the shell pattern caused unnecessary `mv` and heredoc permission prompts. lib.sh and orchestrator cleanup are unchanged (legitimate shell).
- **New QA script: no-shell-atomicity.sh** — Tier 1 check detects `.tmp` write instructions in agent/skill `.md` files. Exempts `rm -f` cleanup lines, `.sh` scripts, and `*/references/*`. Prevents recurrence of the cargo-culted shell pattern.
```

### Step 6: Run QA

- [ ] Run the new `no-shell-atomicity.sh` against the fixed codebase — expect 0 findings
- [ ] Run full plugin QA (`/compound-workflows:plugin-changes-qa`) — all checks must pass

## Acceptance Criteria

- [ ] `grep -r '\.tmp' plugins/compound-workflows/agents/**/*.md plugins/compound-workflows/skills/*/SKILL.md` returns only `rm -f` cleanup lines (do-plan, do-deepen-plan) — no write instructions
- [ ] `no-shell-atomicity.sh` returns 0 findings on the fixed codebase
- [ ] `no-shell-atomicity.sh` would have caught the original pattern (verify via `git stash && bash no-shell-atomicity.sh && git stash pop`, or by temporarily reverting one .tmp line and re-running)
- [ ] `file-counts.sh` passes with the new count (8 scripts)
- [ ] All existing QA scripts pass
- [ ] Version is 3.0.2 in plugin.json, marketplace.json, CHANGELOG.md

## Sources

- **Bead:** `compound-workflows-marketplace-xnep` — original bug report with affected file list
- **Research:** `.workflows/plan-research/remove-tmp-mv-pattern/agents/` — repo research, learnings, specflow analysis
- **Institutional knowledge:** `docs/solutions/claude-code-internals/2026-03-11-script-file-shell-substitution-bypass.md` — Write tool atomicity, `$()` heuristic details
- **Institutional knowledge:** `docs/solutions/claude-code-internals/2026-03-10-static-rules-suppress-bash-heuristics.md` — `<<` hard heuristic (fires even with static rules)
- **Institutional knowledge:** `docs/solutions/qa-infrastructure/2026-03-08-bash-qa-script-patterns.md` — QA script failure modes and best practices
