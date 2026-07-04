# Keybindings

Hierarchical keybinding reference. Upper layers intercept keys first.

Symbols: ⌘ = Command, ⌥ = Option/Alt, ⌃ = Control, ⇧ = Shift

---

## macOS (global)

| Key | Action |
|-----|--------|
| ⌘+Tab | Switch apps |
| ⌘+` | Switch windows within app |
| ⌘+Space | Spotlight |
| ⌘+H | Hide app |
| ⌘+M | Minimize |
| ⌘+Q | Quit app |
| ⌘+W | Close window |
| ⌃+Left / Right | Switch spaces |
| ⌃+Up | Mission Control |
| ⌃+Down | Application windows |
| ⌘+⇧+3 | Screenshot (full) |
| ⌘+⇧+4 | Screenshot (selection) |
| ⌘+⇧+5 | Screenshot menu |

---

## AeroSpace (global, intercepts before apps)

| Key | Action |
|-----|--------|
| ⌥+h/j/k/l | Focus window left / down / up / right |
| ⌥+⇧+h/j/k/l | Move window left / down / up / right |
| ⌥+1~5 | Switch to workspace 1~5 |
| ⌥+⇧+1~5 | Move window to workspace 1~5 |
| ⌥+Tab | Workspace back and forth |
| ⌥+⇧+Tab | Move workspace to next monitor |
| ⌥+/ | Layout: tiles (horizontal/vertical) |
| ⌥+, | Layout: accordion (horizontal/vertical) |
| ⌥+- | Resize -50 |
| ⌥+= | Resize +50 |
| ⌥+F | Fullscreen |
| ⌥+0 | Reset layout (flatten workspace tree) |
| ⌥+⇧+; | Enter service mode |

---

## Ghostty (intercepts before tmux)

| Key | Action |
|-----|--------|
| F12 | Toggle quick terminal (global) |
| ⌘+1~9 | → sends ESC+1~9 to tmux (window switching) |
| ⌘+⇧+O | Toggle background opacity |
| ¥ | Insert `\` (backslash) |

`macos-option-as-alt = true` — ⌥ always sends ESC prefix (Meta key) to tmux.  
⌥+0~5 are unbound in Ghostty, passed through to AeroSpace.

---

## tmux (prefix: C-t)

### Windows (no prefix)

| Key | Action |
|-----|--------|
| ⌘+1~9 | Switch to window 1~9 |
| ⌘+T (M-t) | New window |
| ⌥⌘+Left / Right | Previous / next window |

### Sessions (no prefix)

| Key | Action |
|-----|--------|
| ⌥⌘+Up / Down | Switch to previous / next session |

### Panes (no prefix)

| Key | Action |
|-----|--------|
| ⌥⌘+h/j/k/l | Select pane left / down / up / right |
| ⌥+Z (M-z) | Toggle pane zoom (🔍 in window status while zoomed) |

⌥⌘+hjkl works because Ghostty sends ESC+hjkl (M-hjkl) even with ⌘ held,
while AeroSpace only intercepts plain ⌥+hjkl.

### With prefix (C-t)

| Key | Action |
|-----|--------|
| prefix + Right | Join pane to next window |
| prefix + Left | Join pane to previous window |
| prefix + m | Mark pane |
| prefix + M | Move marked pane here (join-pane) |
| prefix + Space | Cycle layout |
| prefix + r | Reload ~/.tmux.conf |
| prefix + e | Toggle synchronize-panes (⚠ SYNC in status-right while on) |
| prefix + b | Toggle status bar (screen sharing) |
| prefix + g | lazygit in a popup (floating pane on tmux 3.7+) |
| prefix + t | Throwaway shell in a popup (floating pane on tmux 3.7+; replaces clock-mode) |
| prefix + f | fzf switcher across all sessions/windows with live preview (replaces find-window) |
| prefix + * | New floating pane (tmux 3.7+ default binding) |

### Copy mode (vi)

| Key | Action |
|-----|--------|
| v | Begin selection |
| y | Copy to clipboard and exit |
| [ | Jump to previous prompt |
| ] | Jump to next prompt |

---

## zsh (emacs mode)

| Key | Action |
|-----|--------|
| ⌃+R | History search |
| ⌃+A / E | Beginning / end of line |
| ⌃+W | Delete word backward |
| ⌃+U | Clear line |
| ⌃+L | Clear screen |
| ⌥+B / F | Move word backward / forward |
| ⌥+D | Delete word forward |
