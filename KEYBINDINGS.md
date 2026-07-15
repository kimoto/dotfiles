# Keybindings

Hierarchical keybinding reference. Upper layers intercept keys first.

Sources: AeroSpace (`.aerospace.toml`), `config/ghostty/config`,
`.tmux.conf`, `.zshrc`, `config/nvim/` — each carries a pointer comment back to
this file; update this file whenever a binding changes there.

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
| ⌘⌥+←/→/↑/↓ | → sends ⌥+arrows to tmux (window / session switching) |
| ⌘+⇧+O | Toggle background opacity |
| ¥ | Insert `\` (backslash) |

`macos-option-as-alt = true` — ⌥ always sends ESC prefix (Meta key) to tmux.  
⌥+0~5 are unbound in Ghostty, passed through to AeroSpace.

---

## tmux (prefix: C-t)

### Windows / sessions (no prefix)

| Key | Action |
|-----|--------|
| ⌘+1~9 | Switch to window 1~9 |
| ⌥+T (M-t) | New window |
| ⌥+←/→ (or ⌥⌘+←/→) | Previous / next window |
| ⌥+↑/↓ (or ⌥⌘+↑/↓) | Switch to previous / next session |

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
| prefix + f | fzf switcher across all panes of all sessions with live preview (replaces find-window) |
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
| ⌃+R | History search (fzf; wrapped full-command preview) |
| ⌃+T | File picker (fzf; bat preview; ⌃+O opens in editor) |
| ⌃+G | livegrep (interactive ripgrep → open in editor) |
| ⌃+X ⌃+N | Snippet search (fzf over `config/zsh/snippets`) → insert into command line |
| ⌃+\ | Undo |
| ⌃+A / E | Beginning / end of line |
| ⌃+W | Delete word backward |
| ⌃+U | Clear line |
| ⌃+L | Clear screen |
| ⌥+B / F | Move word backward / forward |
| ⌥+D | Delete word forward |

### Shell helpers

Short interactive commands defined in `.zshrc` for frequent workflows:

| Command | Action |
|---------|--------|
| `g [query]` | Jump to a ghq-cloned repo (fzf; README preview) |
| `lg [args]` | Launch lazygit (args passed through); chase into the directory it was left in |
| `b [query]` | Switch git branch (fzf; last-15-commits preview) |
| `B` | GitHub branch browser (`gh branch`) |
| `w [query]` | Jump to a git worktree (fzf) |
| `c` | Switch Kubernetes context (`kubectx`) |
| `l [path]` | Smart viewer: `ll` for dirs, `bat` for files |
| `px` | Toggle between main and sub starship prompt config |
| `temp [prefix]` | cd into a fresh scratch directory under `~/tmp` |
| `snip add [note]` | Save the previous command as a ⌃+X ⌃+N snippet; bare `snip` edits the snippet file |
| `keys [query]` | Search this file's keybinding/helper tables (fzf) |

---

## Neovim (leader: Space)

Defined in `config/nvim/init.lua` and `config/nvim/lua/kimoto/plugins/*.lua`.

### Windows / buffers / tools

| Key | Action |
|-----|--------|
| ⌃+h/j/k/l | Move between windows |
| Space+1~6 | Go to buffer 1~6 |
| Space+n / p | Next / previous buffer |
| Tab / ⇧+Tab | Cycle buffers (bufferline) |
| Space+e | Toggle file tree (nvim-tree) |
| Space+t | Toggle terminal (toggleterm) |
| ⌃+Space | Normal mode: toggle terminal / insert mode: trigger completion |

### Telescope

| Key | Action |
|-----|--------|
| Space+ff | Find files |
| Space+fg | Live grep |
| Space+fb | Buffers |
| Space+fh | Help tags |
| Space+fr | Frecency (recent files) |

### LSP / completion

| Key | Action |
|-----|--------|
| gd / gy / gi | Definition / type definition / implementation |
| grn / gra / grr | Rename / code action / references (nvim builtin) |
| K | Hover (nvim builtin) |
| Enter (insert) | Confirm completion (nvim-cmp) |

### Yank ring (yanky)

| Key | Action |
|-----|--------|
| p / P / gp / gP | Put (ring-aware) |
| ⌃+p / ⌃+n | Cycle older / newer yank after a put |

### Debug (nvim-dap)

| Key | Action |
|-----|--------|
| F5 | Continue |
| F9 | Toggle breakpoint |
| F10 / F11 / ⇧+F11 | Step over / into / out |
| Space+d | Toggle dap-ui |
| Space+dr / Space+dl | Open REPL / run last |
| Space+lp | Set log point |

### Plugin defaults worth knowing

| Key | Action |
|-----|--------|
| gcc / gc{motion} | Toggle comment (Comment.nvim) |
| ys / cs / ds | Add / change / delete surround (vim-surround) |
| Space+j | Jump to definition (any-jump) |
