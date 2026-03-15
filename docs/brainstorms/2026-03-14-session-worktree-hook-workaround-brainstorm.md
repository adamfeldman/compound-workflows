---
title: "Session Worktree Hook Workaround — PreToolUse Bridge + /do:start"
type: fix
date: 2026-03-14
origin_bead: wxco
related_beads: [s7qj, wr96, fyg9]
---

# Session Worktree Hook Workaround

**Bead:** wxco
**Problem:** Session worktree isolation (v3.2.0, bead s7qj) is architecturally complete but the delivery mechanism is broken. SessionStart hooks don't fire for new sessions — the hook script executes but its output is discarded by Claude Code. Six open upstream bugs confirm this is not our issue.

## Why This Approach

**SessionStart hooks are broken upstream.** Six open GitHub issues document the problem:

| Issue | Problem |
|-------|---------|
| [#10373](https://github.com/anthropics/claude-code/issues/10373) | Hook output discarded for new sessions (our exact bug) |
| [#10997](https://github.com/anthropics/claude-code/issues/10997) | Doesn't execute on first run with marketplace plugins |
| [#11509](https://github.com/anthropics/claude-code/issues/11509) | Never executes for local file-based marketplace plugins |
| [#12671](https://github.com/anthropics/claude-code/issues/12671) | Shows "hook error" even with exit 0 |
| [#27145](https://github.com/anthropics/claude-code/issues/27145) | CLAUDE_PLUGIN_ROOT not set during SessionStart |
| [#12117](https://github.com/anthropics/claude-code/issues/12117) | Hook not injecting prompt at conversation start |

**PreToolUse hooks are confirmed working.** auto-approve.sh proves this on every tool call across every session. PreToolUse is the reliable hook type.

**Critical: SessionStart hooks still EXECUTE — their output is just discarded.** This means any state written by the SessionStart path (sentinel files, etc.) takes effect even though the model never sees the output. The hook design must account for this.

**`additionalContext` field empirically verified (2026-03-14).** Test hook returning `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "additionalContext": "TEST_MARKER..."}}` — model received the message and mentioned TEST_MARKER in its response. Multiple PreToolUse hooks fire independently (no short-circuiting). Verified but not used in final design (exit 2 chosen instead).

## What We're Building

### 1. PreToolUse bridge in session-worktree.sh

Modify the existing `session-worktree.sh` hook to work as BOTH a PreToolUse and SessionStart hook. Single script detects its context from stdin JSON and adapts.

**Critical design constraint (from R2 red team):** The hook NEVER writes the sentinel. Only `/do:start` writes the sentinel after successful initialization. This prevents two failure modes:
- SessionStart hook executes silently (output discarded), writes sentinel → PreToolUse sees sentinel → skips → user never gets prompted [Gemini R2 CRITICAL]
- Hook writes sentinel at same time as exit 2 → model ignores instruction → sentinel exists → hook never fires again [Gemini R2 SERIOUS]

**PreToolUse path:**
1. Read `session_id` from stdin JSON
2. Check for `agent_type` field — if present, this is a **subagent** tool call: exit 0 immediately. Subagents cannot run `/do:start` and should not see initialization errors. [Opus R2 SERIOUS]
3. Check sentinel file `.workflows/.session-init/<session_id>` — if exists: exit 0 immediately (~1ms)
4. If no sentinel: run worktree detection logic (config read, orphan check, dirty-main check), output instruction via stderr: "Run `/do:start --trigger=pretooluse`", exit 2 (blocks the tool call)
5. The hook blocks on EVERY tool call until `/do:start` creates the sentinel. This ensures the model cannot proceed without initializing. [Gemini R2 recommendation]

**SessionStart path:**
- Runs worktree detection logic, outputs via stderr: "Run `/do:start --trigger=sessionstart`", exit 2
- Does NOT write sentinel (see constraint above)
- Kept as bridge — will work when upstream fixes the bugs. When it works, model sees the instruction via SessionStart AND gets blocked on first PreToolUse (until `/do:start` creates sentinel). The SessionStart message arrives first, giving the model advance notice.

**Context detection:** PreToolUse stdin JSON contains `tool_name` field. SessionStart does not. Script checks for `tool_name` to determine which path to take. If schema changes and detection fails, falls through to SessionStart path (blocks rather than silently passes — fail-safe). [Opus R1 MINOR: use positive detection where possible, e.g., check `hook_event_name` if available]

**Subagent detection:** PreToolUse stdin JSON contains `agent_type` field for subagent tool calls. If `agent_type` is present, exit 0 immediately — subagents should not be blocked by session initialization. [Opus R2 SERIOUS: subagent first tool call would get incomprehensible error about `/do:start`]

**Output mechanism — exit 2 for both paths:**

Exit 2 blocks the tool call and shows stderr to the model:
- **Makes the instruction highly visible** — the model must deal with the error before any tool call succeeds. Exit 0 + additionalContext risks the model ignoring the instruction (it arrives alongside a tool result). Note: "forces" is too strong — exit 2 makes the instruction hard to ignore but the model could still skip it. The repeated blocking (no sentinel until `/do:start`) is the real enforcement. [Opus R2 SERIOUS: "forces" overstates the mechanism]
- **Avoids auto-approve side effect.** Exit 0 with `permissionDecision: allow` would blanket-approve whatever the first tool call is. [Opus R1 S3]
- **Blocks until initialized.** Unlike the R1 design (one blocked tool call), the hook blocks EVERY tool call until `/do:start` creates the sentinel. No way to silently skip initialization.
- **Proven delivery mechanism.** stderr + exit 2 = shown to model. PostToolUse uses this (different context — PostToolUse fires after success, PreToolUse fires before — but the delivery infrastructure is the same). [Opus R2 MINOR: conflation acknowledged]

### 2. Minimal /do:start skill

New thin skill that handles session initialization:

- **Receives `--trigger` argument** from hook stderr: `--trigger=pretooluse` or `--trigger=sessionstart`
- **Worktree entry:** Detect worktree state, call EnterWorktree (or skip if user opts out)
- **Write sentinel:** After successful initialization, write `.workflows/.session-init/<session_id>` with trigger source and ISO timestamp (e.g., `pretooluse 2026-03-14T15:30:00Z`). This is the ONLY place the sentinel is created. Files are retained as analytics data — session frequency, trigger source distribution, upstream fix detection over time.
- **NOT bd prime.** bd has its own SessionStart hook for priming. If that hook is also broken by the same upstream bugs, that's bd's problem to solve — /do:start should not own another tool's initialization.
- **Debug reporting:** When `session_worktree_debug: true` in config (off by default), report which hook path fired. If trigger is `sessionstart`, the upstream bug is fixed — plugin developer gets notified.
- **Extensible:** wr96 expands this into a full adaptive ceremony router later

**Sentinel is the success signal.** The hook blocks every tool call until the sentinel exists. `/do:start` creates the sentinel after successful worktree entry. This ensures:
- The model cannot proceed without initializing
- If `/do:start` fails or the model ignores it, the hook keeps blocking
- Successful initialization is recorded for the rest of the session

**Sentinel race condition:** Use `mkdir` for atomic sentinel creation (create-or-fail). Prevents parallel first tool calls from both triggering initialization. [OpenAI R1 S4, Opus R2 S3: TOCTOU race, fix with atomic mkdir]

**Upstream fix detection asymmetry:** If the sentinel contains `sessionstart`, that reliably means SessionStart works. But `pretooluse` does NOT reliably mean SessionStart is broken — SessionStart might have fired but lost the race to PreToolUse. This is acceptable for a debug-only diagnostic. [Opus R2 MINOR]

### 3. Settings.json registration

Add PreToolUse entry for session-worktree.sh alongside the existing SessionStart entry:

```json
"PreToolUse": [
  { "matcher": "", "hooks": [{"type": "command", "command": "bash .claude/hooks/auto-approve.sh"}] },
  { "matcher": "", "hooks": [{"type": "command", "command": "bash .claude/hooks/session-worktree.sh"}] }
],
"SessionStart": [
  { "matcher": "", "hooks": [{"type": "command", "command": "bash .claude/hooks/session-worktree.sh"}] }
]
```

Both point to the same script. The script detects which context it's in.

## Key Decisions

1. **Single script, detect context** — one file to maintain. PreToolUse vs SessionStart detected from stdin JSON (`tool_name` present = PreToolUse). User reasoning: "any reason to do 2 scripts?" — no, detection is trivial.

2. **Bridge, keep both hooks** — PreToolUse is the working mechanism. SessionStart registration stays for when upstream fixes the bugs. User reasoning: chose bridge to notice when SessionStart starts working again. Trigger source passed to `/do:start` via `--trigger` argument for observability.

3. **Sentinel written ONLY by /do:start** — the hook NEVER creates the sentinel. This prevents: (a) SessionStart silently pre-empting PreToolUse [Gemini R2 CRITICAL], (b) sentinel existing before model actually initialized [Gemini R2 SERIOUS]. The hook blocks every tool call until `/do:start` confirms success by writing the sentinel. [R2 consensus across all 3 providers]

4. **Exit 2 (block until initialized)** — blocks every tool call until `/do:start` creates the sentinel. Chosen over exit 0 + additionalContext because: (a) makes instruction highly visible — the model must deal with the error, (b) avoids auto-approve side effect, (c) repeated blocking is the real enforcement mechanism. [R1: Gemini C2, Opus S5. R2: refined from "one block" to "block until sentinel"]

5. **Subagent skip** — hook detects `agent_type` in PreToolUse stdin JSON. If present, exit 0 immediately. Subagents cannot run `/do:start` and should not see initialization errors. [Opus R2 SERIOUS]

6. **Trigger source via argument** — hook stderr says `Run /do:start --trigger=pretooluse` (or `--trigger=sessionstart`). `/do:start` records the trigger in the sentinel file. Debug mode reports which path fired. User reasoning: "how will we know which hook fired?" → pass as argument, simplest approach.

7. **Minimal /do:start over direct EnterWorktree** — hook says "Run `/do:start`" not "Call EnterWorktree." The skill handles the interactive flow and is extensible. User reasoning: wr96 already plans a full /do:start; minimal version now seeds that vision.

8. **CLI wrapper rejected** — Gemini proposed `alias claude='bash setup-worktree.sh && command claude'`. Simpler but: not portable via plugin, can't use EnterWorktree (native tool), doesn't integrate with compact-prep/merge/recover flow, breaks `claude --resume`.

9. **Process lesson captured** — bead fyg9 created for "verify upstream feature availability during brainstorm/plan." Memory feedback saved.

## Red Team Resolution

### Round 1 (3 providers)

| Finding | Provider(s) | Severity | Resolution |
|---------|-------------|----------|------------|
| `additionalContext` unverified | Opus | CRITICAL | **Empirically verified working (2026-03-14).** Not used in final design (exit 2 chosen). |
| First tool executes in wrong worktree | Gemini | CRITICAL | **Resolved by exit 2.** Tool blocked until initialized. |
| Sentinel dedup contradiction | All 3 | SERIOUS | **Redesigned in R2:** sentinel written only by /do:start, not by hook. |
| Exit 2 dismissed without analysis | Opus | SERIOUS | **Resolved: exit 2 chosen** after full tradeoff analysis. |
| Multi-hook interaction untested | Opus | SERIOUS | **Empirically verified (2026-03-14).** Two PreToolUse hooks fire independently. |
| Auto-approve side effect | Opus | SERIOUS | **Resolved by exit 2.** No permissionDecision in output. |
| CLI wrapper alternative | Gemini | SERIOUS | **Rejected with reasoning.** Not portable, breaks --resume. |
| "No open questions" premature | Opus, OpenAI | SERIOUS | **Fixed:** open questions updated. |
| Sentinel race condition | OpenAI | SERIOUS | **Fixed in R2:** use atomic mkdir for sentinel creation. |
| Core isolation voluntary | OpenAI | CRITICAL | **By design.** Users who opt out accept contamination risk. Feature is opt-out. |
| `session_id` reliability | Gemini | CRITICAL | **Open question:** verify during implementation. Fallback: PID-based. |
| Context detection fragile | Opus | MINOR | **Accepted.** Fails safe (falls through to blocking path). |
| Sentinel cleanup | Opus | MINOR | **Deferred.** Tiny files, cleanup can be added later. |
| Hook-to-skill coupling | Opus | MINOR | **Accepted.** Same pattern as auto-approve.sh. |

### Round 2 (3 providers — focused on R1 resolutions)

| Finding | Provider(s) | Severity | Resolution |
|---------|-------------|----------|------------|
| SessionStart executes + writes sentinel → PreToolUse skipped | Gemini | CRITICAL | **Redesigned:** sentinel written only by /do:start. Hook never writes sentinel. |
| Premature sentinel creation disables enforcement | Gemini | SERIOUS | **Redesigned:** hook blocks every tool call until /do:start creates sentinel. |
| SessionStart path can't get session_id | Gemini, OpenAI | SERIOUS | **Resolved:** SessionStart path doesn't write sentinel. Trigger source passed via --trigger argument. |
| Subagent tool calls blocked with incomprehensible errors | Opus | SERIOUS | **Fixed:** hook detects agent_type and skips for subagents. |
| "Forces compliance" overstated | Opus | SERIOUS | **Acknowledged:** exit 2 makes instruction visible, repeated blocking is the enforcement. Wording updated. |
| Sentinel creation race condition (re-raised from R1) | Opus | SERIOUS | **Fixed:** atomic mkdir for sentinel creation. |
| "All resolved" contradicts deferred session_id | OpenAI | SERIOUS | **Fixed:** session_id is explicitly an open question. |
| Fail-safe context detection may cause repeated blocking | OpenAI | SERIOUS | **Accepted:** repeated blocking is intentional — fail-safe means "block if unsure," not "pass if unsure." |
| Sentinel content detection asymmetric | Opus | MINOR | **Acknowledged:** pretooluse doesn't reliably mean SessionStart broken. Acceptable for debug diagnostic. |
| "Proven mechanism" conflates delivery with model behavior | Opus | MINOR | **Acknowledged:** delivery infrastructure is shared, model behavioral response is context-dependent. |
| bd prime double-execution risk uncharacterized | Opus | MINOR | **Deferred:** bd prime is likely idempotent. Verify during implementation. |
| "Core isolation voluntary" resolution is tautological | Opus | MINOR | **Strengthened:** users who opt out accept contamination risk. Persistent opt-out preference could reduce repeat prompts (future). |

## Open Questions

1. **session_id presence verification** — need to confirm `session_id` is reliably present in PreToolUse stdin JSON during implementation. Fallback: PID-based sentinel if absent. Go/no-go: do not ship until verified.

## Deferred Questions

1. ~~**Sentinel cleanup**~~ **Resolved: keep for analytics.** Sentinel files are a session log — each contains trigger source (`pretooluse`/`sessionstart`) and timestamp. Over time this is a dataset: session frequency, when SessionStart starts working (if ever), worktree adoption rate. Files are ~20 bytes each; thousands of sessions = kilobytes. No cleanup needed. Use `mkdir` for atomic creation (prevents TOCTOU race).

2. ~~**bd prime integration**~~ **Resolved: not /do:start's responsibility.** bd has its own SessionStart hook. If that hook is broken by the same upstream bugs, bd should solve it independently. /do:start owns worktree entry only.

3. **PreToolUse exit 0 empty stdout** — when the sentinel exists, the hook exits 0 with no stdout. Verify Claude Code doesn't require a JSON response on exit 0 for PreToolUse hooks. auto-approve.sh exits 0 with empty stdout on non-matching tools — precedent suggests this is fine.

## Sources

- **Upstream issues:** GitHub search confirmed 6 open SessionStart bugs (see table above)
- **Repo research:** `.workflows/brainstorm-research/session-worktree-hook-workaround/repo-research.md` — PreToolUse stdin format, sentinel patterns, auto-approve.sh architecture
- **Context research:** `.workflows/brainstorm-research/session-worktree-hook-workaround/context-research.md` — .work-in-progress.d sentinel precedent, original brainstorm foreshadowing
- **Claude Code guide:** PreToolUse exit code behavior (exit 2 blocks, exit 0 + JSON additionalContext allows)
- **Red team R1:** `.workflows/brainstorm-research/session-worktree-hook-workaround/red-team--{gemini,openai,opus}.md`
- **Red team R2:** `.workflows/brainstorm-research/session-worktree-hook-workaround/red-team-r2--{gemini,openai,opus}.md`
- **Empirical tests (2026-03-14):**
  - A2: Model asks for confirmation before calling EnterWorktree — one "yes" per session
  - additionalContext: Test hook confirmed model receives the field in PreToolUse context
  - Multi-hook: Two PreToolUse hooks fire independently, no short-circuiting
