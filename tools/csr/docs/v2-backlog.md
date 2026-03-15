# csr v2 Backlog

Tracked originally as beads epic `Strategy-256` in the Strategy repo. Migrated here for continued development.

## P2 — Notification Improvements (Brainstorm)

**Trigger:** Adam's feedback after first real usage day.

Current hooks work but aren't satisfying. Core problem: with 20 terminal tabs across 4 Cursor windows, a macOS notification doesn't tell you WHICH session needs attention. You still have to hunt through tabs.

Session identification is limited: only `/rename`d sessions show their name in notifications. Auto-generated titles aren't stored in JSONL, so most sessions fall back to the directory basename (usually "Strategy" for everything).

Areas to explore:
- Debounce/rate-limiting (15+ sessions = noisy)
- Better session identification (auto-title not in JSONL, only /rename titles work)
- Notification grouping (multiple permission prompts at once)
- Actionable notifications (approve from notification? click-to-focus?)
- Visual differentiation between sessions
- Alternative to osascript (terminal-notifier? alerter? supports click-to-focus?)
- Sound fatigue — configurable or silent option

## P3 — Shell Tab-Completion

Add bash/zsh completions for csr. Complete subcommands (`list`, `restore`, `version`, `help`) and session names for `csr restore <TAB>`. Session names pulled from `csr list` output.

## P3 — fzf Integration

Add fzf support for browsing and selecting sessions. Options:
- `csr list | fzf` piping (works today with minor formatting)
- Built-in `csr pick` subcommand that pipes list through fzf and restores the selection
- Fallback gracefully if fzf not installed

## P4 — `--json` Output

Add `--json` flag to `csr list` for structured output. Enables composition with jq, piping into other tools, scripted restore subsets.

## P4 — Layout Save/Restore

Save and restore tmux window layout (positions, sizes) alongside session names. Before building, re-evaluate whether claude-squad or agent-deck already solve this.
