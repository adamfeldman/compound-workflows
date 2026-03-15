---
title: Tmux Keybinding Overhaul
type: plan
status: applied
date: 2026-03-15
---

# Tmux Keybinding Overhaul

## Goal

Align Ctrl-b direct bindings with tmux-which-key's category-based layout
(Spacemacs-style), so both entry points teach the same mental model.

## Context

- tmux-which-key installed with organized submenus: `c` = copy, `w` = windows,
  `p` = panes, `s` = sessions, `b` = buffers
- Default tmux bindings conflict: `c` = new window, `p` = previous window, etc.
- User is a Spacemacs user — category-based navigation is natural
- New tmux setup — minimal muscle memory to break

## Applied: .tmux.conf keybindings

### Rebound

| Key | Default | New binding | Rationale |
|-----|---------|-------------|-----------|
| `c` | `new-window` | `copy-mode` | Matches which-key `c` = Copy |
| `n` | `next-window` | `new-window -c #{pane_current_path}` | "New", frees brackets for nav |
| `[` | `copy-mode` | `previous-window` | Bracket nav (left = prev) |
| `]` | `paste-buffer` | `next-window` | Bracket nav (right = next) |
| `P` | *unbound* | `paste-buffer` | Capital P = Paste |
| `h` | *unbound* | `select-pane -L` | Vim-style pane nav |
| `j` | *unbound* | `select-pane -D` | Vim-style pane nav |
| `k` | *unbound* | `select-pane -U` | Vim-style pane nav |
| `l` | `last-window` | `select-pane -R` | Vim-style pane nav |
| `BSpace` | *unbound* | `last-window` | Replaces `l` for last window |

### Unchanged

| Key | Action |
|-----|--------|
| `;` | Last pane |
| `%` / `"` | Split horizontal / vertical (with current path) |
| `S` | Sync panes toggle |
| `d` | Detach |
| `s` | Choose sessions |
| `w` | Choose windows |
| `0-9` | Select window by number |
| `y` / `Y` | Yank line / cwd (tmux-yank) |
| `u` | fzf URLs |
| `f` | fpp file picker |
| `t` | Fingers (hint copy) |
| `Tab` | Extrakto |
| `Ctrl-s` / `Ctrl-r` | Save / restore session (resurrect) |
| `b` | Beads dashboard (floating popup) |
| `g` | Switch session by name (sessionist) |
| `C` | Create new session (sessionist) |
| `X` | Kill current session (sessionist) |
| `@` | Promote pane to session (sessionist) |
| `:` | Command prompt |
| `?` | List keys |
| `Space` | which-key menu |

## Applied: which-key config

### Root level items
| Key | Action |
|-----|--------|
| `Space` | Command prompt |
| `Tab` | Extrakto (hint — use `^b Tab` directly) |
| `BSpace` | Last window |
| `` ` `` | Last pane |
| `c` | +Copy submenu |
| `w` | +Windows submenu |
| `p` | +Panes submenu |
| `b` | +Buffers submenu |
| `s` | +Sessions submenu |
| `C` | +Client submenu |
| `x` | +Tools submenu |
| `t` | Fingers (hint — use `^b t` directly) |
| `T` | Clock mode |
| `~` | Show messages |
| `?` | +Keys |

### Tools submenu (`x`)
All plugin entries are hint labels (direct `Ctrl-b <key>` shortcuts shown) because
`run-shell` inside `display-menu` cannot properly interact with the pane — it either
fails silently or hangs. Native tmux commands (like sync panes toggle) work fine.

## Applied: Full plugin list

| Plugin | Purpose | Notes |
|--------|---------|-------|
| tpm | Plugin manager | |
| tmux-resurrect | Session save/restore | |
| dracula/tmux | Status bar theme | Pinned to `f385531` — custom ✓/· continuum icons |
| tmux-continuum | Auto-save sessions | Must be after dracula (status-right order). 1-min interval. |
| tmux-fzf-url | URL picker | `Ctrl-b u` |
| tmux-yank | Clipboard integration | Fallback for Mosh (no OSC 52) |
| tmux-fpp | File path picker | `Ctrl-b f` |
| extrakto | Fuzzy scrollback search | `Ctrl-b Tab` |
| tmux-which-key | Discoverable keybinding menus | `Ctrl-b Space`. Config must be rebuilt after YAML edits. |
| tmux-fingers | Easymotion-style hint copy | `Ctrl-b t` |
| tmux-sessionist | Session management | `g`=switch, `C`=create, `X`=kill, `@`=promote. `S` overridden to sync panes post-TPM. |

## Applied: Status bar (Dracula)

Modules (left to right): git, ssh-session, continuum, synchronize-panes

| Module | Behavior |
|--------|----------|
| git | Branch + dirty status |
| ssh-session | Hidden when local, shows user@host when remote |
| continuum | Alert mode: `·` normally, `✓` flash for 2s on save |
| synchronize-panes | Auto-hidden when off, shows `⚡Sync` when on |

## Applied: Other config

- **Prefix:** Explicitly set to `C-b` (prevents wipe on plugin reload)
- **Window titles:** `automatic-rename-format '#{pane_title}'` — shows Claude session names
- **Mosh compat:** `set-titles off` and `focus-events off` when `$MOSH_CONNECTION` detected
- **Display time:** 3000ms for tmux messages
- **Clipboard:** OSC 52 via `set-clipboard on` + `allow-passthrough on`
- **Vi copy mode:** `v` to select, `y` to yank
- **zsh alias:** `tg` = `tmux new-session -t` (grouped sessions)
- **oh-my-zsh tmux plugin:** Kept for aliases and auto-attach wrapper
- **Beads popup:** `Ctrl-b b` opens a floating `display-popup` with a `bd sql` query showing open beads sorted by priority and impact score. Piped through `less -S`. Bead `7th3` tracks adding a `next` column once workflow skills persist next-action in metadata.
- **Post-plugin override:** `bind S setw synchronize-panes` after TPM runs — sessionist binds `S` to `switch-client -l`, which we override back to sync panes.

## Full .tmux.conf reference

Every setting in the config, grouped by purpose.

### Prefix
| Setting | Value | Why |
|---------|-------|-----|
| `prefix` | `C-b` | Explicit — prevents wipe on plugin reload |

### Window & Pane Titles
| Setting | Value | Why |
|---------|-------|-----|
| `set-titles` | `on` | Push pane title to terminal title bar (Cursor tabs, Moshi) |
| `set-titles-string` | `#T` | Use the pane title (set by shell/Claude Code) |
| `pane-border-format` | `#{pane_title}` | Show pane title as label above each pane |
| `pane-border-status` | `top` | Labels appear above panes, not below |

### Mouse
| Setting | Value | Why |
|---------|-------|-----|
| `mouse` | `on` | Click panes, drag resize, scroll, select text |

### Window Behavior
| Setting | Value | Why |
|---------|-------|-----|
| `renumber-windows` | `on` | Fill gaps when windows close (1,3,4 → 1,2,3) |
| `automatic-rename` | `on` | Window tabs auto-update |
| `automatic-rename-format` | `#{pane_title}` | Show Claude session names in tabs, not process name |
| `allow-rename` | `on` | Let apps set window names via escape sequences |

### Terminal & Color
| Setting | Value | Why |
|---------|-------|-----|
| `default-terminal` | `tmux-256color` | Proper terminal type for 256 colors |
| `terminal-overrides` | `*:Tc` | Enable true 24-bit color. Uses `-g` not `-as` to avoid duplicates on reload. |
| `terminal-features` | `xterm*:...:sync` | Enables synchronized output (DEC 2026) — batches rapid redraws. Requires tmux restart (not just source). |
| `extended-keys` | `on` | Fixes modifier key combos (Ctrl-Shift, etc.) in TUI apps |
| `escape-time` | `0` | No delay after Escape — critical for vim/vi-mode |

### Clipboard (OSC 52)
| Setting | Value | Why |
|---------|-------|-----|
| `mode-keys` | `vi` | Vim keybindings in copy mode |
| `allow-passthrough` | `on` | OSC 52 reaches terminal for clipboard access |
| `set-clipboard` | `on` | tmux writes to system clipboard via OSC 52 |

Copy mode: `v` to select, `y` to yank. Works over SSH in modern terminals.
Does NOT work over Mosh — tmux-yank provides `pbcopy` fallback.

### Copy Mode Quick Reference
Enter with `Ctrl-b c`, exit with `q`.

| Key | Action |
|-----|--------|
| `h/j/k/l` | Move cursor |
| `w/b` | Forward/back by word |
| `0` / `$` | Start/end of line |
| `g` / `G` | Top/bottom of scrollback |
| `Ctrl-u/d` | Half page up/down |
| `Ctrl-b/f` | Full page up/down (prefix doesn't fire in copy mode) |
| `/` / `?` | Search forward/backward |
| `n` / `N` | Next/previous match |
| `v` | Start selection |
| `V` | Select whole line |
| `y` | Copy selection to system clipboard |
| `q` | Exit copy mode (returns to bottom) |

Note: `Escape` does not reliably exit copy mode when zsh-vi-mode is active — use `q`.

### Scrollback & Display
| Setting | Value | Why |
|---------|-------|-----|
| `history-limit` | `500000` | 500K lines scrollback (default: 2000) |
| `display-time` | `3000` | tmux messages visible for 3s (default: 750ms) |
| `focus-events` | `on` | Programs detect pane focus changes (auto-save etc.) |

### Dracula Continuum Icons (custom edit)
In `~/.tmux/plugins/tmux/scripts/continuum.sh` (pinned commit `f385531`):
- Normal state: `·` (subtle dot placeholder)
- After save (2s flash): `✓`
- Overdue: shows last save timestamp

### Mosh Compatibility
When `$MOSH_CONNECTION` is set, disables `set-titles` and `focus-events` — both
use escape sequences that Mosh strips.

### Shell Integration
- **zsh alias:** `tg` = `tmux new-session -t` (create grouped session)
- **oh-my-zsh tmux plugin:** Kept for `ta`, `ts`, `tl`, `tds` aliases and auto-attach wrapper

### Grouped Sessions
`tg <session-name>` creates or reattaches to a grouped session — both tabs share
the same windows but each can view a different window independently. This is how
to have 2 terminal tabs with different tmux windows on the same session.

`tg` is a zsh function (not a simple alias) that prevents session pile-up:
1. If an unattached grouped session for `<name>` exists, reattaches to it
2. If all grouped sessions are attached, creates a new one

This stops the `plugin-41, plugin-42, ...` accumulation that happens with
bare `tmux new-session -t` since each closed terminal tab leaves a detached
group member that never gets reused.

### Window Management
- `Ctrl-b ,` — Rename current window (quick shortcut)
- `Ctrl-b Space w .` — Move window before an index (reorder)
- `Ctrl-b Space w s` — Swap window with another index
- `Ctrl-b .` — Also prompts to move current window (direct binding)

### Session Cleanup
Resurrect + continuum restore old sessions on tmux start. Periodically kill stale
unattached sessions to prevent clutter. `tmux kill-session -t <name>` or `tkss <name>`.

### Evaluated and Declined
- **tmux-open** — Open files/URLs from copy mode. Declined because fingers, extrakto,
  fzf-url, and fpp already cover the same use cases with fewer steps.
- **tmux-thumbs** — Easymotion-style hint copy. Abandoned (last commit 2023), no ARM Mac
  binary, requires Rust to compile. Replaced by tmux-fingers.
- **Zellij** — Same Claude Code scroll issues as tmux. tmux is 8x faster in benchmarks.

## Lessons learned

- **`run-shell` in `display-menu` is broken** — commands that need pane context
  (extrakto, fingers, fpp, fzf-url) fail or hang when invoked from which-key menus.
  Workaround: hint labels that show the direct keybinding.
- **which-key config must be compiled** — editing `config.yaml` alone does nothing.
  Run `python3 plugin/build.py config.yaml plugin/init.tmux` then source.
- **Menu name collision** — which-key build fails if two submenus share the same name
  (e.g., `+Plugins` existed in both Client submenu and our custom menu).
- **Continuum plugin order matters** — Dracula overwrites `status-right`, wiping
  continuum's save trigger. Continuum must load after Dracula.
- **Prefix can get wiped** — if not explicitly set in config, plugin reloads can
  reset it to `None`. Always set `set -g prefix C-b` explicitly.
- **tmux-thumbs is abandoned** — last commit 2023. tmux-fingers (Feb 2026) is the
  actively maintained alternative. Fingers installed via Homebrew, not compiled.
- **`-as` terminal-overrides appends on every reload** — duplicated `*:Tc` 35+ times.
  Use `set -g` (replace) instead of `set -as` (append) for settings in sourced configs.
- **which-key keys should prefer lowercase** — defaults used unnecessary capitals
  (`R`, `X`, `D`, `N`, `S`). Changed to lowercase where no conflicts exist.

## Known upstream issue: Claude Code scroll jumping in tmux

Claude Code generates 4,000-6,700 scroll events/second which overwhelms tmux's
terminal emulation layer. This causes scroll position jumping, flickering, and
jitter. Multiple open GitHub issues:

- [#9935](https://github.com/anthropics/claude-code/issues/9935) — Excessive scroll events (4,000-6,700/sec vs typical 10-100/sec)
- [#33367](https://github.com/anthropics/claude-code/issues/33367) — Scroll position jumps during streaming
- [#25682](https://github.com/anthropics/claude-code/issues/25682) — Scroll-up during processing causes runaway scroll to top
- [#4851](https://github.com/anthropics/claude-code/issues/4851) — Scrollback rewind lag after extended use

**No tmux config fully fixes this.** Our config already includes all community-recommended
mitigations: `allow-passthrough on`, `escape-time 0`, `history-limit 500000`,
`mouse on`, `focus-events on`, `extended-keys on`, `terminal-features sync`.
The fix needs to come from Claude Code throttling its terminal output.

Tested disabling individually: `automatic-rename`, `pane-border-status`, `status-interval`,
`allow-passthrough`, `focus-events`, `mouse` — none resolved the jumping.

Reference: [sethdford/tmux-claude-code](https://github.com/sethdford/tmux-claude-code) — community optimized tmux config for Claude Code.

## Future work

- [ ] Restart tmux to enable `sync` terminal feature — potential scroll fix
- [x] tmux-sessionist — installed. `g`=switch, `C`=create, `X`=kill, `@`=promote pane. `S` overridden back to sync panes.
- [x] Popup scripts — beads dashboard (`Ctrl-b b`). Declined lazygit (uses Cursor/Claude instead) and htop (not needed).
- [x] ~~Evaluate `Ctrl-Space` as prefix~~ — declined. Potential Mosh/input method conflicts, and `Ctrl-b` is the universal standard.
- [ ] Bead `tetl` — plugin-ize the tmux config for portability
