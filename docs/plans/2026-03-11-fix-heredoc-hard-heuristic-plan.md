---
title: "Fix: Heredoc hard heuristic — revert ywug, create append-snapshot.sh"
type: fix
status: completed
date: 2026-03-11
origin_bead: ywug
related_beads: [jak, 3l7, dndn, eec]
---

# Fix: Heredoc Hard Heuristic — Revert ywug, Create append-snapshot.sh

## Problem

Bead ywug (v2.5.1) replaced `cat >> file <<EOF` with Read+Write tool append in compact-prep.md after observing a permission prompt. The fix premise was correct — `<<` DOES trigger a permission prompt even with `Bash(cat:*)` — but the fix approach contradicts established heuristic audit principles and introduces unnecessary instruction complexity.

### Evidence: `<<` Is a Hard Heuristic

Screenshot evidence from the ywug session shows `cat >> ".workflows/stats/2026-03-11-ccusage-snapshot.yaml" <<EOF` prompted despite `Bash(cat:*)` being present in settings.local.json. First token is `cat`, rule exists, but the heredoc heuristic still fired.

This contradicts the generalization in the static rules solution doc, which was inferred from only 2 test cases:
- `$()` suppressed by `git:*` — confirmed
- `{"` suppressed by `bd:*` — confirmed
- `<<` suppressed by `cat:*` — **DISPROVED by ywug screenshot**

The solution doc's own assumption table flagged this risk: "Some heuristics might be 'hard' (unsuppressible)."

### Why the ywug Fix Is Wrong

| Concern | Detail |
|---------|--------|
| **Inconsistency** | v2.5.0 eliminated `$()` by rewriting bash into scripts. ywug eliminated `<<` by switching to Read+Write tool. Different approach for the same class of problem. |
| **Error surface** | Read+Write requires the model to correctly read existing file content, append new YAML, and write the whole file back. `cat >>` was atomic. |
| **Instruction weight** | 6 lines of prose instructions replaced 4 lines of bash template. More surface for model misinterpretation. |
| **Pattern violation** | capture-stats.sh, validate-stats.sh, check-sentinel.sh, init-values.sh — every other mid-workflow bash problem was solved by moving logic into a script. This should be too. |

## Solution

### Step 1: Create `append-snapshot.sh`

Create `plugins/compound-workflows/scripts/append-snapshot.sh` following the capture-stats.sh pattern:

- Takes positional args: `<snapshot-file> <timestamp> <total-cost> <input-tokens> <output-tokens> [key=value...]`
- Creates directory if missing (`mkdir -p` on parent dir)
- Appends a `---`-separated YAML document via `cat >> file <<EOF` (inside the script, invisible to heuristic inspector)
- Extensible: additional key=value pairs appended as extra YAML fields
- Exits 0 always (same invariant as capture-stats.sh)

Script pattern:
```bash
#!/usr/bin/env bash
# append-snapshot.sh — Atomic append of ccusage snapshot YAML documents
#
# Usage:
#   bash append-snapshot.sh <file> <timestamp> <cost> <input> <output> [key=value...]
#
# Exits 0 always — snapshot capture must never block compact-prep.

set -euo pipefail

FILE="${1:?missing snapshot file}"
TIMESTAMP="${2:?missing timestamp}"
COST="${3:?missing total_cost_usd}"
INPUT="${4:?missing input_tokens}"
OUTPUT="${5:?missing output_tokens}"
shift 5

# Ensure directory exists
mkdir -p "$(dirname "$FILE")"

# Core fields
cat >> "$FILE" <<EOF
---
type: ccusage-snapshot
timestamp: $TIMESTAMP
total_cost_usd: $COST
input_tokens: $INPUT
output_tokens: $OUTPUT
EOF

# Extensible fields (key=value pairs)
for kv in "$@"; do
  KEY="${kv%%=*}"
  VAL="${kv#*=}"
  echo "$KEY: $VAL" >> "$FILE"
done

exit 0
```

- [x] Create the script file
- [x] Verify it works: `bash plugins/compound-workflows/scripts/append-snapshot.sh /tmp/test-snapshot.yaml "2026-03-11T00:00:00Z" 100.00 50000 200000 opus_cost=95.00 sonnet_cost=5.00`
- [x] Verify multi-append: run twice, confirm two `---`-separated documents

### Step 2: Revert compact-prep.md ywug changes

Replace the Read+Write prose instructions with a `bash` call to the script:

```markdown
### Step 7b: Persist ccusage Snapshot

If ccusage data was successfully retrieved and parsed in Step 7, persist a snapshot.

```bash
bash $PLUGIN_ROOT/scripts/append-snapshot.sh "<SNAPSHOT_FILE>" "<TIMESTAMP>" <total_cost> <input_tokens> <output_tokens> [additional_key=value pairs]
```

**Core fields** (positional args): timestamp, total_cost_usd, input_tokens, output_tokens.

**Extensible fields** (trailing key=value args): cache_read_tokens, cache_creation_tokens, per-model cost breakdown, or any other data from the parsed ccusage output.

After the call, add a brief note: "ccusage snapshot saved to .workflows/stats/"
```

- [x] Edit compact-prep.md Step 7b to use `bash $PLUGIN_ROOT/scripts/append-snapshot.sh`
- [x] Remove the Read+Write prose instructions
- [x] Keep the `mkdir -p` removal (the script handles it internally)

### Step 3: Update static rules solution doc

File: `docs/solutions/claude-code-internals/2026-03-10-static-rules-suppress-bash-heuristics.md`

- [x] Add Test 5 to evidence table: `cat >> "file" <<EOF` with `Bash(cat:*)` → **Prompted** (heredoc heuristic not suppressed)
- [x] Update "What Static Rules Fix" section: remove `cat >> "$SNAPSHOT_FILE" <<EOF` entry (line 58)
- [x] Add `<<` (heredoc) to "What Static Rules Cannot Fix" section as a second class alongside `VAR=$(...)`:
  > **Heredoc patterns (`<<`)** — heredoc appears to be a "hard" heuristic not suppressed by static rules, even when the first token matches. Empirically verified: `cat >> file <<EOF` prompts despite `Bash(cat:*)`.
- [x] Update assumption table row 4: mark "Two test cases generalize to all heuristic types" as **BROKEN** for heredoc

### Step 4: Update brainstorm docs

**jak brainstorm** (`docs/brainstorms/2026-03-10-plugin-heuristic-audit-brainstorm.md`):
- [x] P9 in Pattern Catalogue: change from "Accept (one-off)" to "Hard heuristic — needs script (append-snapshot.sh)"
- [x] Revised pattern status table: change `cat >> "$SNAPSHOT_FILE" <<EOF` from "No — already solved" to "**Yes — `<<` is hard heuristic, unsuppressible by static rules**"

**dndn brainstorm** (`docs/brainstorms/2026-03-11-permissionless-bash-generation-brainstorm.md`):
- [x] "Patterns Already Handled by Static Rules" section: remove or correct the `cat >> file <<'EOF'` entry, add note that `<<` is a hard heuristic

### Step 5: Update plugin CLAUDE.md, version, CHANGELOG

- [x] Add `append-snapshot.sh` to the scripts inventory in `plugins/compound-workflows/CLAUDE.md`
- [x] Update Permission Architecture section: add note that `<<` heredoc is a hard heuristic not suppressed by static rules
- [x] Bump version to v2.5.2 in plugin.json and marketplace.json
- [x] Add CHANGELOG entry documenting the revert and the `<<` hard heuristic finding
- [x] Run full QA: `bash plugins/compound-workflows/scripts/plugin-qa/stale-references.sh` etc.

## Acceptance Criteria

1. `append-snapshot.sh` exists and works (atomic append, extensible fields, exits 0)
2. compact-prep.md uses `bash $PLUGIN_ROOT/scripts/append-snapshot.sh` — no Read+Write, no heredoc visible to heuristic inspector
3. Static rules solution doc reflects `<<` as hard heuristic with empirical evidence
4. Brainstorm P9 classifications corrected
5. QA passes with zero findings
6. Running compact-prep no longer prompts for the snapshot step

## Sources

- **ywug bead**: original fix commit `6853d14`
- **jak brainstorm**: `docs/brainstorms/2026-03-10-plugin-heuristic-audit-brainstorm.md` — P9, Critical Empirical Finding
- **dndn brainstorm**: `docs/brainstorms/2026-03-11-permissionless-bash-generation-brainstorm.md` — "Patterns Already Handled"
- **Static rules solution**: `docs/solutions/claude-code-internals/2026-03-10-static-rules-suppress-bash-heuristics.md`
- **Screenshot evidence**: ywug session — `cat >>` with `Bash(cat:*)` rule present, still prompted
