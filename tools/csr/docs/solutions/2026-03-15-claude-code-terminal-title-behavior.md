---
title: "Claude Code terminal title behavior: auto-generated vs /rename"
category: claude-code/terminal
validated: partial
date: 2026-03-15
---

# Claude Code Terminal Title Behavior

## Problem

Claude Code has two naming systems for sessions. Understanding which names appear where is important for tmux integration, notification hooks, and session management tooling.

## Two Naming Systems

| System | How it's set | Stored in JSONL | Shows in tmux tab |
|--------|-------------|:-:|:-:|
| Auto-generated title | Claude Code generates from conversation content | No | Probably yes |
| `/rename` custom title | User runs `/rename <name>` in session | Yes (`custom-title` record) | Probably no |

## What We Know (Verified)

1. **`/rename` writes `custom-title` records to JSONL.** Confirmed by grepping session files — 19 named sessions found with `grep '"type":"custom-title"'`.

2. **Auto-generated titles are NOT in JSONL.** Scanning all record types with `jq` shows: `assistant`, `user`, `system`, `progress`, `file-history-snapshot`, `queue-operation`, `custom-title`. No record type for auto-generated titles.

3. **Claude Code does emit terminal title escape sequences.** tmux tabs show session-related text (not just "claude"), confirming escape sequence emission.

4. **The terminal title chain works via:**
   - oh-my-zsh auto-title enabled (`DISABLE_AUTO_TITLE` commented out in `.zshrc`)
   - Claude Code emits `\033]2;<title>\033\\`
   - tmux captures this as pane title
   - `set-titles-string "#T"` displays it as window title
   - `pane-border-format "#{pane_title}"` shows in pane borders

## What We Observed (Single Data Point, Needs More Testing)

5. **A `/rename`d session appeared to NOT update the tmux tab title.** After running `/rename setup`, the tab still showed "2.1.76" (Claude Code version). However, this was a single observation and could have alternative explanations:
   - The escape sequence might not emit until the next response
   - The session might not have had an auto-generated title yet
   - Timing between `/rename` and tmux title refresh

6. **An auto-generated title ("csr and claude notifications") DID appear in a tmux tab** for a different session in the same tmux instance.

## Practical Implications

- **Notification hooks** can only identify sessions by `/rename` title (because that's in JSONL)
- **tmux tabs** probably show auto-generated titles (because those are emitted as escape sequences)
- **These are likely two independent systems** — naming a session with `/rename` helps hooks but may not change the tmux tab

## Replication Plan

To definitively test:
1. Start a fresh Claude session in tmux
2. Note the tmux tab title (should show auto-generated title after first few exchanges)
3. Run `/rename test-title-change`
4. Check if tmux tab updates to "test-title-change" or stays as auto-generated
5. Send another message and check again (in case escape sequence emits on next response)
6. Compare: start a second session, don't `/rename` it, confirm auto-generated title appears in tab
