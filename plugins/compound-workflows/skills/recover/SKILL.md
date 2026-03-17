---
name: recover
description: Recover context from a dead or exhausted session
argument-hint: "[session ID or empty for picker]"
disable-model-invocation: true
---

# Recover — Dead Session Recovery

Recovers context from a dead or exhausted Claude Code session by reading its JSONL session log, cross-referencing external state, and producing a structured recovery manifest. This is the **reactive** counterpart to `/do:compact-prep` (proactive).

## Input

<session_id> $ARGUMENTS </session_id>

## Phase 0: Environment Detection

### Step 0.1: Derive session log directory

The session log directory uses the project's absolute path with `/` replaced by `-`:

```bash
SESSION_DIR="$HOME/.claude/projects/${PWD//\//-}"
echo "Session log directory: $SESSION_DIR"
ls "$SESSION_DIR"/*.jsonl 2>/dev/null | wc -l
```

If the directory does not exist or contains zero `.jsonl` files, tell the user: "No session logs found for this project at `$SESSION_DIR`. This command requires Claude Code session logs to exist." Then stop.

### Step 0.2: Detect environment

```bash
which bd 2>/dev/null && echo "BEADS=available" || echo "BEADS=not_available"
```

Note beads availability for Phase 3.

### Step 0.2a: Resolve main root for .workflows/ paths

```bash
git worktree list --porcelain | head -1 | sed 's/^worktree //'
```

Set `WORKFLOWS_ROOT=<main-root>/.workflows`. All `.workflows/` paths in this skill use `$WORKFLOWS_ROOT`, NOT relative `.workflows/`. This ensures artifacts are found at the correct location regardless of whether you are in a worktree or the main checkout.

### Step 0.3: Route by argument

If `<session_id>` is non-empty, skip to **Phase 2** using that session ID to locate the `.jsonl` file at `$SESSION_DIR/<session_id>.jsonl`. If the file does not exist, tell the user: "No session log found for session ID `<session_id>`." Then stop.

If `<session_id>` is empty, proceed to **Phase 1** (Session Discovery).

## Phase 1: Session Discovery (Picker)

Build a picker showing recent sessions for the user to choose from.

### Step 1.1: Gather session metadata

List the 10 most recent `.jsonl` files by modification time:

```bash
ls -t "$SESSION_DIR"/*.jsonl 2>/dev/null | head -10
```

For each file, extract metadata via targeted JSONL parsing. **Do not load full message content** — parse only structural fields to keep context lean.

For each `.jsonl` file, use bash to extract the needed fields. Parse each line as JSON and collect:

- **Session ID** — from filename (strip path and `.jsonl` extension)
- **Session slug** — from any entry's `slug` field (first non-null occurrence)
- **First user text message** — find the first entry where `type` is `"user"` and `message.content` contains a `text` block (not `tool_result`) and the entry does NOT have `isMeta: true`. Extract first 80 characters of the text content as a preview.
- **Last user text message** — same criteria as above, but the last such entry. First 80 characters.
- **Timestamp range** — `timestamp` of the first entry and the last entry (ISO format)
- **Compact boundary count** — count entries where `type` is `"system"` and the message contains `compact_boundary` or `compactMetadata`. Note the `preTokens` value from the last such entry.
- **Exhaustion heuristic** — check if the final entry in the file is an `assistant` type entry (session ended mid-assistant-turn, suggesting exhaustion or crash)

**Parsing approach:** Use `jq` or line-by-line JSON parsing. For large files, avoid reading the entire file into memory. Use `head` and `tail` with line counts to extract the first and last portions. Example approach:

```bash
# Get first entry timestamp and slug
head -1 "$FILE" | jq -r '[.timestamp, .slug] | @tsv'

# Get last entry timestamp and type
tail -1 "$FILE" | jq -r '[.timestamp, .type] | @tsv'

# Get first user text message (scan first ~200 lines)
head -200 "$FILE" | jq -r 'select(.type == "user" and .isMeta != true) | .message.content[]? | select(.type == "text") | .text' 2>/dev/null | head -1 | cut -c1-80

# Get last user text message (scan last ~200 lines)
tail -200 "$FILE" | jq -r 'select(.type == "user" and .isMeta != true) | .message.content[]? | select(.type == "text") | .text' 2>/dev/null | tail -1 | cut -c1-80

# Count compact boundaries
grep -c '"compact_boundary"' "$FILE" 2>/dev/null || echo "0"

# Check if last entry is assistant (exhaustion heuristic)
tail -1 "$FILE" | jq -r '.type' 2>/dev/null
```

Adapt the parsing as needed for the actual JSONL structure — the key constraint is **do not load full content, only structural fields and short previews**.

### Step 1.2: Format and present picker

Format each session as a numbered entry:

```
N. [slug] — "first user message preview..." (time ago, M compactions) [flags]
   Last activity: "last user message preview..."
```

Flags:
- `POSSIBLE EXHAUSTION` — if session ended mid-assistant-turn
- `CURRENT SESSION` — if the session ID matches the current session (warn the user that recovery is for dead sessions)

Present the formatted list via **AskUserQuestion**: "Which session would you like to recover? Enter the number."

### Step 1.3: Offer to see more

After the user selects a session (or if they ask to see more), offer via **AskUserQuestion**: "Would you like to see more sessions?"
- **No — proceed with selection** — continue to Phase 2
- **Show 20 sessions** — re-run Step 1.1 with `head -20`
- **Show 50 sessions** — re-run Step 1.1 with `head -50`
- **Show all sessions** — re-run Step 1.1 without `head` limit

Only offer this after the initial 10 are shown. If the user already selected a session number, skip this and proceed to Phase 2.

## Phase 2: Parse & Extract Selected Session

Parse the selected session's JSONL file using a head + tail strategy. The goal is to extract enough context for recovery without exhausting the current session's context.

**Context budget:** 50KB total extraction. 2KB max per individual entry.

### Step 2.1: Head extraction — Original intent

Extract the first 5 intent-bearing `user` entries. An "intent-bearing" entry meets ALL of these criteria:
- `type` is `"user"`
- `isMeta` is NOT `true`
- `message.content` contains at least one block with `type: "text"` (not only `tool_result` blocks)

For each qualifying entry, extract:
- The `text` content (truncated to 2KB)
- The `timestamp`

These capture the original intent — what the user asked the session to do.

```bash
# Example: extract first 5 intent-bearing user messages
# Scan the file line by line, filter for qualifying entries, take first 5
# Truncate text content to 2048 characters per entry
```

### Step 2.2: Tail extraction — Recent context

Locate the last `compact_boundary` entry in the file:

```bash
grep -n '"compact_boundary"' "$FILE" | tail -1
```

If a compact boundary exists, extract all intent-bearing entries (same criteria as Step 2.1) from that line forward, taking the last 30. If no compact boundary exists, extract the last 30 intent-bearing entries from the end of the file.

For each qualifying entry, extract:
- The `text` content (truncated to 2KB)
- The `timestamp`
- The `type` (user or assistant — include assistant text entries in the tail for conversation flow)

Include both `user` and `assistant` entries in the tail (both with text content, excluding tool_use/tool_result blocks that contain file contents). This captures the conversation flow, not just user messages.

**Total tail budget: 50KB.** If the extracted entries exceed this, truncate from the oldest entries first.

### Step 2.3: Command detection

Scan for the last active command invocation.

> **Dual-namespace detection:** Session logs from before v3.0.0 use `/compound:*` command names;
> logs from v3.0.0+ use `/do:*`. Search for BOTH patterns to handle old and new sessions.

- Look for `user` entries with `isMeta: true` — these are command invocations
- Look for entries whose content contains `<command-name>` tags — these mark command execution
- Extract the command name (e.g., `/do:work`, `/do:brainstorm`, or pre-v3.0.0 `/compound:work`, `/compound:brainstorm`)

If a command is detected, infer its phase by looking at subsequent activity:
- What agents were dispatched (Task/Agent tool_use calls)?
- What files were being written to?
- What AskUserQuestion interactions occurred?

Note the last detected command and its inferred phase. If multiple commands were invoked in the session, track the LAST one (most relevant for recovery) and note prior ones as completed context.

### Step 2.4: Decision extraction

Find AskUserQuestion interactions:
- `assistant` entries containing `tool_use` with `name: "AskUserQuestion"` — extract the question text
- The next `user` entry with a `tool_result` for that tool_use_id — extract the user's response

Collect all Q&A pairs. These are the user's explicit decisions during the session.

### Step 2.5: File path extraction

Find Read, Write, and Edit tool_use calls in `assistant` entries:
- Extract the `file_path` parameter from each
- Deduplicate the list
- Note which files were written/edited vs. only read

This identifies which files the session was actively working on.

### Step 2.6: Error extraction

Find `tool_result` entries in `user` messages where `is_error` is `true`:
- Extract the tool name and a brief error summary (first 200 characters of the error content)
- Note the timestamp

These identify failures that may have contributed to session death.

### Step 2.7: Subagent detection

Find `Agent` and `Task` tool_use calls in `assistant` entries:
- Extract the agent description/prompt (first 100 characters)
- Note whether `run_in_background` was true
- Check if a corresponding completion notification exists later in the log

This identifies background work that may or may not have completed.

## Phase 3: Cross-Reference External State

Check each recovery source to build a picture of the project state at recovery time.

### Step 3.1: .workflows/ artifacts

```bash
ls -lt $WORKFLOWS_ROOT/brainstorm-research/ $WORKFLOWS_ROOT/plan-research/ $WORKFLOWS_ROOT/deepen-plan/ $WORKFLOWS_ROOT/compound-research/ $WORKFLOWS_ROOT/code-review/ $WORKFLOWS_ROOT/work-review/ $WORKFLOWS_ROOT/recover/ 2>/dev/null
```

For directories modified within the dead session's time range (from Phase 2 timestamps), note:
- The workflow type and topic stem
- Whether a manifest.json exists (for deepen-plan) and its `status` field
- Most recently modified files

If `$WORKFLOWS_ROOT` does not exist, note "No .workflows/ directory found at $WORKFLOWS_ROOT" and skip.

### Step 3.2: Beads state

If beads is available (from Phase 0):

```bash
bd list --status=in_progress 2>/dev/null
bd list --status=open 2>/dev/null | head -5
```

If beads is not available, note "Beads: not available" and skip.

### Step 3.3: Git state

```bash
git status --short
git log --oneline -10
git stash list
```

Note uncommitted changes, recent commits (especially those within the session's time range), and any stashes.

### Step 3.4: Plan files

```bash
ls -lt docs/plans/*.md 2>/dev/null | head -5
```

For recent plan files (modified within the session's time range), read the YAML frontmatter and check for:
- `status: active`
- Count of unchecked `- [ ]` items

### Step 3.5: Compact-prep detection

Check if the session log contains `compact_boundary` entries with activity both before and after them. If so, note that compact-prep likely ran during the session — meaning memory was updated and work was committed at that point. Activity after the last compact boundary is the unpreserved context.

## Phase 4: Write Recovery Manifest

Write three files to `$WORKFLOWS_ROOT/recover/<session-id>/`. Create the directory if it does not exist. Overwrite if prior recovery exists (recovery is idempotent — external state may have changed).

```bash
mkdir -p $WORKFLOWS_ROOT/recover/<session-id>
```

### File 1: `summary.md`

```markdown
# Recovery Summary: [session slug or "untitled"]

**Session:** [session-id]
**Time range:** [first timestamp] to [last timestamp]
**Compactions:** [N] (last at [preTokens] tokens)
**Status:** [POSSIBLE EXHAUSTION / normal end / compact-prep ran before end]
**Branch:** [gitBranch from session, note if different from current branch]

## What Was Happening

[Synthesize from head + tail extracts:
- Original intent (from head): what did the user ask to do?
- Last active task (from tail): what was happening when the session died?
- Active command/phase if detected
Keep this to 3-5 sentences — enough to orient a new session.]

## Key Decisions Made

[AskUserQuestion Q&A pairs from Phase 2.4. Format as:]
- **Q:** [question] **A:** [user's response]

[If no decisions found: "No explicit decisions detected in the session log."]

## Files Being Worked On

[Deduplicated file paths from Phase 2.5, grouped by action:]
- **Written/Edited:** [files]
- **Read:** [files]

[If no file activity found: "No file operations detected."]

## External State

- **Beads:** [N in_progress issues, M open issues | not available]
- **Git:** [uncommitted changes summary | clean working tree]
- **Stashes:** [list | none]
- **$WORKFLOWS_ROOT/:** [active artifacts found with types | none | no directory]
- **Plans:** [active plans with unchecked items | none found]

## Recommended Next Step

[If compound command detected:]
"Resume `/do:[command]` — the session was in Phase [N] ([phase description]).
To resume, run: /do:[command] [arguments]
[If the command has built-in recovery (deepen-plan): note it will auto-detect the interrupted state.]
[If the command does not have built-in recovery: note the user starts fresh with recovery context available on disk.]"

[If interactive work (no command):]
"Continue working on [topic summary]. Recovery context is available at $WORKFLOWS_ROOT/recover/<session-id>/."

[If clean — no interrupted work detected:]
"No interrupted work detected. The session appears to have ended normally."
```

### File 2: `session-extract.md`

```markdown
# Session Extract: [session-id]

## Original Intent (Head)

[First 3-5 user messages from Phase 2.1, preserving the user's words.
Each entry prefixed with its timestamp.
Truncated entries noted with "[truncated]".]

## Recent Context (Tail from last compaction)

[Last conversation exchanges from Phase 2.2.
Include both user and assistant text entries to show conversation flow.
Each entry prefixed with its timestamp and role (User/Assistant).
Summarize rather than quote if entries are very long.]

## Active Command

[Detected /do:* (or pre-v3.0.0 /compound:*) command and inferred phase from Phase 2.3, or:]
"No compound command detected — interactive session."
[If multiple commands were invoked, note prior ones as completed.]

## Decisions

[AskUserQuestion Q&A pairs from Phase 2.4:]
- **Q:** [question text]
  **A:** [user response]

[If none: "No AskUserQuestion interactions found."]

## Errors

[Tool errors from Phase 2.6:]
- [timestamp] [tool name]: [brief error summary]

[If none: "No tool errors found."]

## Subagents

[Agent/Task dispatches from Phase 2.7:]
- [description preview] — [completed | possibly incomplete | background]

[If none: "No subagent dispatches found."]
```

### File 3: `state-snapshot.md`

```markdown
# State Snapshot: [current ISO timestamp]

Captured at recovery time — reflects current state, not session-time state.

## Beads

[bd list output from Phase 3.2, or:]
"Beads not available."

## Git

### Status
[git status --short output from Phase 3.3]

### Recent Commits
[git log --oneline -10 output]

### Stashes
[git stash list output, or "No stashes."]

## $WORKFLOWS_ROOT/ Artifacts

[Recently modified directories and their contents from Phase 3.1, or:]
"No .workflows/ directory found at $WORKFLOWS_ROOT."

## Active Plans

[Plans with status: active and unchecked item counts from Phase 3.4, or:]
"No active plans found."
```

## Phase 5: Present Summary & Offer Resume

### Step 5.1: Present summary

Present the content of `summary.md` directly to the user. Do not just say "file written" — show the actual recovery summary so the user has immediate context.

### Step 5.2: Note recovery manifest location

Tell the user: "Full recovery manifest written to `$WORKFLOWS_ROOT/recover/<session-id>/` (summary.md, session-extract.md, state-snapshot.md)."

### Step 5.3: Offer next steps

**If a `/do:*` (or pre-v3.0.0 `/compound:*`) command was detected:**

Tell the user: "The session was running `/do:[command]` [with arguments if detected]. To resume, run:"

```
/do:[command] [arguments]
```

Note whether the command supports auto-recovery:
- `/do:deepen-plan` — detects interrupted manifests and resumes automatically
- Other commands — the user starts fresh, but recovery context is available on disk at `$WORKFLOWS_ROOT/recover/<session-id>/`

Use **AskUserQuestion**: "What would you like to do?"
- **Run the command above to resume** — output the exact command string for the user to copy-paste (commands cannot invoke other commands programmatically)
- **Continue manually** — recovery context is loaded in this session; the user can continue working
- **Done** — just needed the summary

**If interactive work (no command detected):**

Use **AskUserQuestion**: "What would you like to do?"
- **Continue from here** — recovery context is loaded; the user can pick up where the dead session left off
- **Done** — just needed the summary

## Phase 5.5: Memory Extraction

This fills the gap when `/compact-prep` never ran before the session died — decisions and rationale would otherwise be lost.

### Step 5.5.1: Scan for memory-worthy content

Review the session extract (from Phase 2) for:
- **AskUserQuestion responses with rationale** — the user explained WHY, not just what
- **Explicit user preferences** — "I prefer X" or "always do Y" patterns
- **Corrections** — the user corrected an assumption or approach
- **Key decisions with reasoning** — choices between alternatives with stated tradeoffs

### Step 5.5.2: Offer memory update

If memory-worthy content is found, present it via **AskUserQuestion**:

"The dead session contained decisions/rationale that may be worth persisting to memory:
- [Decision/preference 1: brief summary]
- [Decision/preference 2: brief summary]

Update memory files with these?"
- **Yes** — read the relevant memory files, update them with the new information (following the existing format and avoiding duplication), and tell the user what was updated
- **Skip** — don't update memory

If no memory-worthy content is detected, skip this phase silently. Do not ask the user about it.

## Phase 6: Worktree Recovery

After JSONL-based session recovery, check for orphaned session worktrees that may contain uncommitted or unmerged work from prior sessions.

### Step 6.1: Detect default branch

```bash
git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'
```

Read the output as `DEFAULT_BRANCH`. If the command fails (no remote HEAD configured), use `main` as the fallback.

### Step 6.2: Discover session worktrees

```bash
git worktree list
```

Parse the output. Filter for entries whose path contains `.worktrees/session-`. Exclude the current working directory if it is already a session worktree. Track the remaining entries as orphaned session worktrees.

If no session worktrees are found (other than possibly the current CWD), skip to Step 6.4 (Orphan Branch Detection).

If more than 5 session worktrees are found, announce: "N session worktrees found. Showing first 5 — consider manual cleanup for the rest." Process only the first 5.

### Step 6.3: Process each worktree

For each session worktree (one at a time), gather information:

```bash
git -C <path> branch --show-current
```

```bash
git -C <path> status --short | wc -l
```

```bash
git log <DEFAULT_BRANCH>..<branch> --oneline | wc -l
```

For last modified time, use `stat -f '%Sm' <path>` on macOS or `stat -c '%y' <path>` on Linux. Run `uname` first if the platform is unknown.

Present each worktree to the user via **AskUserQuestion**:

"Found session worktree `<name>` (branch: `<branch>`, N uncommitted files, M unmerged commits, last active: <date>). What would you like to do?"

Options:
- **Merge** — "Run `/do:merge <branch>` to merge into `<DEFAULT_BRANCH>`." Output the exact command string for the user to copy-paste. Do not invoke it programmatically.
- **Inspect** — Show `git -C <path> status` and `git -C <path> log --oneline -5` output, then re-present the same AskUserQuestion with the same options.
- **Discard** — Confirm first: "This will delete all uncommitted work in this worktree. Proceed?" If the user confirms, run `bd worktree remove .worktrees/session-<name>` to clean up.
- **Skip** — Leave for later. Move to the next worktree.

### Step 6.4: Orphan Branch Detection

Check for branches matching the session worktree naming pattern that have no corresponding worktree directory. These may contain committed data that was never merged back.

```bash
git branch --list 'session-*'
```

```bash
git worktree list
```

Compare the two outputs: any branch in the `session-*` list that does NOT have a corresponding live worktree is an orphan branch. For each orphan branch found:

```bash
git log <DEFAULT_BRANCH>..<orphan-branch> --oneline | wc -l
```

If orphan branches with unmerged commits exist, present them via **AskUserQuestion**:

"Found N orphan branch(es) with no corresponding worktree (likely from crashed sessions):
- `<branch>`: M unmerged commits
[repeat for each]

These branches contain committed work that was never merged. What would you like to do?"

Options:
- **Merge** — "Run `/do:merge <branch>` for each branch." Output the exact command strings.
- **Delete** — Confirm first: "This will permanently delete these branches and their unmerged commits. Proceed?" If confirmed, run `git branch -D <branch>` for each.
- **Skip** — Leave for later.

### Step 6.5: Include in recovery manifest

Add a `## Worktrees` section to the `state-snapshot.md` file (Phase 4, File 3) with:

```markdown
## Worktrees

### Session Worktrees
[List of session worktrees found in .worktrees/session-*, with branch, uncommitted file count, unmerged commit count, and action taken (merged/discarded/skipped), or:]
"No session worktrees found."

### Orphan Branches
[List of session-* branches with no corresponding worktree directory, with unmerged commit count and action taken, or:]
"No orphan branches found."
```

Also add a worktree summary line to `summary.md` (Phase 4, File 1) in the External State section:

```
- **Worktrees:** [N session worktrees (M merged, K discarded, J skipped), P orphan branches | no session worktrees found]
```

## Edge Cases

Handle these throughout execution:

- **Empty session log** (single entry or no user messages): Show in picker but note "no activity". In Phase 2, produce a minimal extract noting the session had no meaningful content.
- **Very large session** (24MB+): The head + tail strategy with 50KB budget and 2KB per-entry truncation prevents context exhaustion. Do not attempt to read the entire file.
- **No compact boundaries**: Use last 30 filtered entries from end of file for the tail extraction.
- **Current session selected**: Warn the user: "This appears to be the current active session. `/compound-workflows:recover` is designed for dead sessions — recovering a live session may produce incomplete results." Offer to proceed anyway or pick a different session.
- **Session from different branch**: Note the `gitBranch` field from the JSONL in the summary: "Note: This session was on branch `[branch]`, which differs from the current branch `[current]`."
- **Session from different working directory**: Note the `cwd` field if it differs from current `pwd`: "Note: This session's working directory was `[cwd]`, which differs from the current directory."
- **Beads unavailable**: Skip beads checks entirely. Note "Beads: not available" in the state snapshot. No error.
- **No `$WORKFLOWS_ROOT` directory**: Skip artifact checks. Note "No .workflows/ directory found at $WORKFLOWS_ROOT" in the state snapshot. No error.
- **Malformed JSONL line**: Skip the line with a brief warning ("Skipped N malformed lines during parsing"). Continue parsing remaining lines.
- **Multiple commands in one session**: Detect the LAST active command (most relevant for recovery). Note prior commands as completed context in the session extract.
- **Session still active in another terminal**: No reliable detection mechanism. This is a known limitation. If the user notices stale data, they should close the other session first. Document this in the summary if the session's last entry is very recent (within the last few minutes).

## Rules

- **Do not exhaust context recovering context.** The head + tail strategy, 50KB budget, and 2KB per-entry truncation exist to prevent the recovery session from dying the same way the original did. Respect these limits strictly.
- **Do not load full JSONL file content into context.** Use bash commands (jq, grep, head, tail) to extract only what's needed. Parse on disk, not in context.
- **Present the summary, don't just write it.** The user needs to see the recovery context immediately, not hunt for it in files.
- **Commands cannot invoke other commands.** When offering to resume a compound command, output the exact command string for the user to copy-paste. Do not attempt programmatic invocation.
- **Record the why, not just the what.** When extracting decisions, preserve the user's stated reasoning — it's more valuable than the choice itself.
- **Degrade gracefully.** Missing beads, missing $WORKFLOWS_ROOT/, missing plan files — these are all acceptable states. Skip with a note, never error.
- **Recovery is idempotent.** Running recover on the same session twice overwrites the prior manifest with fresh external state. This is intentional.
