# Stats Capture Schema

Reference document for per-dispatch stats collection. Each orchestrator command includes a short inline instruction that points here for field derivation rules, capture mechanics, and the `capture-stats.sh` interface.

## YAML Entry Schema

Each dispatch produces one YAML document appended to the stats file:

```yaml
---
command: work
bead: 22l
stem: quota-optimization
agent: general-purpose
step: "1"
model: opus
run_id: a1b2c3d4
tokens: 20121
tools: 13
duration_ms: 43364
timestamp: 2026-03-09T14:23:00Z
status: success
complexity: null
output_type: null
```

### Field Descriptions

| Field | Type | Source | Description |
|-------|------|--------|-------------|
| command | string | Fixed per command | `work` / `brainstorm` / `plan` / `deepen-plan` / `review` |
| bead | string or null | `bd show` output (work only) | Bead ID. `null` for non-work commands. |
| stem | string | Derived per command (see table below) | Links to `.workflows/` artifacts for the same command run. |
| agent | string | Dispatch agent name | `general-purpose`, `repo-research-analyst`, `red-team-relay`, etc. |
| step | string | Varies by command (see table below) | Step number (work) or agent role name (others). Always quoted in YAML. |
| model | string | Resolved per algorithm below | `opus` / `sonnet` / `haiku` |
| run_id | string | Generated at command start | Short UUID (`uuidgen \| cut -c1-8`), shared by all entries in one command run. Disambiguates same-day reruns. |
| tokens | integer or null | `<usage>` total_tokens | `null` if `<usage>` absent or unparseable. |
| tools | integer or null | `<usage>` tool_uses | `null` if `<usage>` absent or unparseable. |
| duration_ms | integer or null | `<usage>` duration_ms | `null` if `<usage>` absent or unparseable. |
| timestamp | string | System time at capture | ISO 8601 with Z timezone (UTC). |
| status | string | Dispatch outcome | `success` / `failure` / `timeout` |
| complexity | string or null | Classifier (post-hoc) | `rote` / `mechanical` / `analytical` / `judgment` / `null`. Populated by `/compound-workflows:classify-stats`. |
| output_type | string or null | Classifier (post-hoc) | `code-edit` / `research` / `review` / `relay` / `synthesis` / `null`. Populated by `/compound-workflows:classify-stats`. |

## Where to Find `<usage>`

Look for `<usage>...</usage>` in the Task/Agent response (foreground inline) or in the completion notification (background). The format is identical in all four scenarios:

- **Foreground Task** (e.g., work.md sequential dispatches): `<usage>` appears at the end of the inline Task response.
- **Background Task** (e.g., review.md parallel dispatches): `<usage>` appears in the automatic completion notification.
- **Foreground Agent** (e.g., deepen-plan.md synthesis): `<usage>` appears at the end of the inline Agent response.
- **Background Agent** (e.g., deepen-plan.md research batches): `<usage>` appears in the automatic completion notification.

Expected format:
```
<usage>total_tokens: 20121, tool_uses: 13, duration_ms: 43364</usage>
```

The model extracts `total_tokens`, `tool_uses`, and `duration_ms` values from the `<usage>` notification and formats them as a named-field string. The model does NOT pass raw `<usage>` XML to the script — it extracts numeric values and formats as `"total_tokens: N, tool_uses: N, duration_ms: N"`. This keeps angle brackets out of Bash tool commands.

**Important:** `<usage>` is an observed API, not a documented contract. A future Claude Code update may change the format. If `capture-stats.sh` emits a warning about format changes, consider filing a bug to update the parser.

## How to Call `capture-stats.sh`

### Standard Call (after successful dispatch)

Pass usage data as the 9th positional argument. The model extracts values from `<usage>` and formats them as a named-field string:

```bash
bash $PLUGIN_ROOT/scripts/capture-stats.sh \
  "<stats-file>" "<command>" "<agent>" "<step>" "<model>" "<stem>" "<bead>" "$RUN_ID" "<usage-data>"
```

Where `<usage-data>` is `"total_tokens: N, tool_uses: N, duration_ms: N"` or `"null"`.

Example:

```bash
bash $PLUGIN_ROOT/scripts/capture-stats.sh \
  ".workflows/stats/2026-03-09-work-quota-optimization.yaml" \
  "work" "general-purpose" "1" "opus" "quota-optimization" "22l" "a1b2c3d4" \
  "total_tokens: 20121, tool_uses: 13, duration_ms: 43364"
```

### Timeout Call (dispatch timed out)

When a background dispatch does not produce a completion notification within the command's configured timeout:

```bash
bash $PLUGIN_ROOT/scripts/capture-stats.sh --timeout \
  "<stats-file>" "<command>" "<agent>" "<step>" "<model>" "<stem>" "<bead>" "$RUN_ID"
```

No `<usage-line>` argument. The script writes an entry with `status: timeout` and null token fields.

### Failure Handling

If `<usage>` is absent from the response, pass `"null"` as the usage-data argument:

```bash
bash $PLUGIN_ROOT/scripts/capture-stats.sh \
  "<stats-file>" "work" "general-purpose" "1" "opus" "quota-optimization" "22l" "$RUN_ID" "null"
```

The script writes `status: failure` with null token fields. If `<usage>` is present but in an unexpected format, the script attempts best-effort extraction, prints a warning to stderr, and writes whatever it could parse.

## Stats File Naming

Files are stored in `.workflows/stats/` with the naming convention:

```
.workflows/stats/<date>-<command>-<stem>.yaml
```

Examples:
- `.workflows/stats/2026-03-09-work-quota-optimization.yaml`
- `.workflows/stats/2026-03-09-brainstorm-per-agent-token-instrumentation.yaml`
- `.workflows/stats/2026-03-10-plan-per-agent-token-instrumentation.yaml`
- `.workflows/stats/2026-03-10-review-feat-user-dashboard.yaml`
- `.workflows/stats/2026-03-10-deepen-plan-per-agent-token-instrumentation.yaml`

The `<date>` is the current date (`date +%Y-%m-%d`). Same-day reruns of the same command+stem append to the same file. Use `run_id` to distinguish entries from different runs.

Ensure `mkdir -p .workflows/stats` is called before the first dispatch in each command.

## Post-Dispatch Validation

After all dispatches in a command run complete, count YAML documents in the stats file and compare against the number of completed dispatches:

```bash
ENTRY_COUNT=$(grep -c '^---$' "$STATS_FILE" 2>/dev/null || echo 0)
```

If `ENTRY_COUNT` does not match the expected dispatch count:
- Warn with the names of missing agents, not just the count delta
- Example: "Stats capture: expected 5 entries but found 3. Missing agents: security-sentinel, performance-oracle"
- Do not fail the command — this is a diagnostic warning only

For commands with conditional dispatches (plan.md, review.md, deepen-plan.md), track the actual dispatched agent count dynamically (increment a counter when each dispatch fires).

## Worktree Handling

`/do:work` runs subagents inside git worktrees. The orchestrator (not the subagent) captures stats. Key points:

- STATS_FILE is an absolute path to the main repo's `.workflows/stats/`. Works from any CWD including worktrees.
- Subagent completion notifications arrive in the main conversation context regardless of where the subagent ran.
- Stats files are written to the main repo's `.workflows/stats/`, never to the worktree's `.workflows/stats/`.
- Worktree cleanup destroys the worktree's `.workflows/` but does not affect the main repo's stats.

## Model Resolution Algorithm

Resolve the `model` field using this 4-step priority chain:

1. **Dispatch `model:` parameter override** — If the dispatch includes an explicit `model:` parameter (e.g., `Agent red-team-relay model: sonnet`), use that value.
2. **Agent YAML frontmatter `model:` field** — Read the dispatched agent's YAML frontmatter. If it specifies a concrete model (e.g., `model: sonnet`), use that.
3. **`CLAUDE_CODE_SUBAGENT_MODEL` env var** — If the agent has `model: inherit` or no model field, check the env var. If set, use that value.
4. **Default to parent context model** — If no env var, default to the parent context's model (typically `opus` for orchestrator commands).

**Required:** Check `CLAUDE_CODE_SUBAGENT_MODEL` once at the start of each command run (alongside `mkdir -p` and config check) and cache the result. Pass the cached value to `capture-stats.sh` as the `<model>` argument for agents without an explicit model override.

## Stem Derivation Per Command

| Command | Derivation | Example |
|---------|-----------|---------|
| work | Plan filename: strip date prefix + `-plan.md` suffix. Fallback: branch name. | `quota-optimization` |
| brainstorm | topic-stem (already derived in Phase 1.1) | `per-agent-token-instrumentation` |
| plan | plan-stem (already derived in Phase 1) | `per-agent-token-instrumentation` |
| deepen-plan | plan-stem (from plan filename, already derived) | `per-agent-token-instrumentation` |
| review | topic-stem (already derived in Step 2) | `feat-user-dashboard` |

## Step Derivation Per Command

| Command | Step Value | Example |
|---------|-----------|---------|
| work | Bead issue number or sequential loop counter | `"1"`, `"3"` |
| brainstorm | Agent role name | `"repo-research-analyst"` |
| plan | Agent role name | `"learnings-researcher"` |
| deepen-plan | Category--agent-name | `"research--security-sentinel"`, `"synthesis--convergence-advisor"` |
| review | Agent role name | `"typescript-reviewer"` |

**Note:** The `step` field is polymorphic — it holds a bead issue number when `command=work`, and an agent role name for all other commands. Downstream consumers should always filter by `command` before aggregating by `step`.
