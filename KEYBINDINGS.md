# Keybindings

Upper layers intercept keys first.

---

## Text editing (every app except the terminal)

Source:
- Mac: `hammerspoon/init.lua`, the rest macOS built-in
- Windows: `windows/autohotkey/mac-keys.ahk`

Same keys on both.

| Key | Action |
|-----|--------|
| ⌥+B / F | Word backward / forward |
| ⌃+W | Delete word backward |
| ⌥+D | Delete word forward (Windows only) |
| ⌃+/ | Undo |
| ⌃+A / E | Beginning / end of line |
| ⌃+B / F | Character backward / forward |
| ⌃+P / N | Line up / down |
| ⌃+H / D | Delete character backward / forward |
| ⌃+K | Delete to end of line |
| ⌘+A/C/F/N/P/R/S/T/V/W/X/Z | Select all, copy, find, new, print, reload, save, new tab, paste, close, cut, undo |
| ⌘+⇧+Z / T | Redo / reopen closed tab |

On Windows these work outside text fields too; close tabs with ⌘+W.

---

## Screenshots

Source:
- Mac: CleanShot X, in-app (`LAVA*` keys of `pl.maketheweb.cleanshotx`)
- Windows: ShareX, `HotkeysConfig.json` under `%USERPROFILE%`

| Mac (CleanShot X) | Windows (ShareX) | Action |
|-------------------|------------------|--------|
| ⌃+⌘+⇧+4 | same | Region → annotate → clipboard |
| ⌘+⇧+4 | Ctrl+PrintScreen (clipboard + file) | Region |
| ⌘+⇧+3 | PrintScreen (clipboard + file) | Full screen |
| ⌘+⇧+4, then Space | Alt+PrintScreen (clipboard + file) | Active window |
| ⌘+⇧+5 | Shift+PrintScreen; Ctrl+Shift+PrintScreen as GIF | Screen recording |

### Annotating (after a screenshot)

Source:
- Mac: CleanShot X defaults
- Windows: ShareX, `ApplicationConfig.json` (`ImageEditorOptions.ToolbarItems`); ⌘+⇧+C via `windows/autohotkey/mac-keys.ahk`

Same keys on both.

| Key | Action |
|-----|--------|
| R | Rectangle (outline) |
| A | Arrow |
| P | Pixelate (CleanShot: Redaction) |
| C | Step counter (1, 2, 3…) |
| T | Text |
| ⌘+⇧+C | Copy and close (Enter also works on Windows) |

---

## Terminal (intercepts before tmux)

Source:
- Mac: `config/ghostty/config`
- Windows: `windows/autohotkey/mac-keys.ahk`, `windows/windows-terminal/keybindings.json`

Mac: Ghostty. Windows: Windows Terminal. Same keys on both.

| Key | Action |
|-----|--------|
| ⌘+1~9 | tmux window 1~9 (sends ESC+1~9) |
| ⌘+⌥+← / → | Previous / next tmux window |
| ⌘+⌥+↑ / ↓ | Previous / next tmux session |
| ⇧+Enter / ⌥+Enter | Newline in Claude Code (Windows only) |
| F12 | Toggle quick terminal (Mac only) |
| ⌘+⇧+O | Toggle background opacity (Mac only) |
| ¥ | Insert `\` (Mac only) |

- Mac: ⌥ is Meta; ⌥+0~5 go to AeroSpace.
- Windows: at a shell prompt, Shift/Alt+Enter run the command. F11 is fullscreen.

---

## macOS (Mac only)

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

---

## Raycast (Mac only)

Source:
- in-app

| Key | Action |
|-----|--------|
| ⌃⌘+V | Clipboard history |
| ⌘+⇧+V | Paste clipboard history items one by one (Paste Sequentially) |
| ⌃⌘+C | Snippets |

---

## Rectangle (Mac only)

Source:
- in-app (`defaults read com.knollsoft.Rectangle`)

| Key | Action |
|-----|--------|
| ⌃⌘+A / D | Left / right half |
| ⌃⌘+K / J | Top / bottom half |
| ⌃⌘+[ / ] | Top-left / top-right quarter |
| ⌃⌘+' / \ | Bottom-left / bottom-right quarter |
| ⌃⌘+F | Maximize |
| ⌃⌘+S | Center |
| ⌃⌘+X | Center half |
| ⌃⌘+; / - | Larger / smaller |
| ⌃⌘+O | Restore |
| ⌃⌘+G | Next display |
| ⌃⌘+←/↓/↑/→ | Move to left / bottom / top / right edge (keeps size) |

Repeat a half / quarter key to cycle ½ → ⅔ → ⅓ (quarters grow horizontally).

---

## AeroSpace (Mac only, intercepts before apps)

Source:
- `.aerospace.toml`

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
| ⌥+F / ⌥+⇧+F | Fullscreen |
| ⌥+0 | Reset layout (flatten workspace tree) |
| ⌥+⇧+; | Enter service mode |

### Service mode (⌥+⇧+;, then...)

| Key | Action |
|-----|--------|
| Esc | Reload config, back to main mode |
| R | Reset layout (flatten workspace tree), back to main mode |
| F | Toggle floating/tiling layout, back to main mode |
| Backspace | Close all windows but current, back to main mode |
| ⌥+⇧+T | Tile all windows in focused workspace, back to main mode |
| ⌥+⇧+F | Float all windows in focused workspace, back to main mode |
| ⌥+⇧+h/j/k/l | Join with window left / down / up / right, back to main mode |
| Down / Up | Volume down / up |
| ⇧+Down | Mute (volume set 0), back to main mode |

---

## tmux (prefix: C-t)

Source:
- `.tmux.conf`

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
| Mouse wheel | Scroll pane / enter copy-mode; scrolling to the bottom exits it |

### With prefix (C-t)

While the prefix is held, status-right shows `? help  g lazygit  t shell`.

| Key | Action |
|-----|--------|
| prefix + C-t | Jump back to the last window (double-tap the prefix) |
| prefix + C-b | Send the prefix through to a nested tmux |
| prefix + Right | Join pane to next window |
| prefix + Left | Join pane to previous window |
| prefix + m | Mark pane |
| prefix + M | Move marked pane here (join-pane) |
| prefix + Space | Cycle layout |
| prefix + r | Reload ~/.tmux.conf |
| prefix + e | Toggle synchronize-panes (⚠ SYNC in status-right while on) |
| prefix + b | Toggle status bar (screen sharing) |
| prefix + g | lazygit in a popup (floating pane on tmux 3.7+) |
| prefix + t | Throwaway shell in a popup (floating pane on tmux 3.7+) |
| prefix + a | New Claude Code session in a floating pane, same cwd (tmux 3.7+) |
| prefix + A | Same, but forking this pane's Claude Code session |
| prefix + f | fzf switcher across all panes of all sessions, most recent first |
| prefix + F | tmux-fzf: fzf menu for sessions/windows/panes (switch, rename, kill, etc.) |
| prefix + \ (or prefix + Enter) | tmux-menus: open popup menu (session/window/pane actions) |
| prefix + ? | tmux-which-key: menu of tmux commands |
| prefix + Ctrl-s | Save session state, incl. Claude Code (auto every 15 min) |
| prefix + Ctrl-r | Restore the last saved session state |
| prefix + Tab | extrakto: pick a word/path/url/line from scrollback (Tab copies, Enter inserts) |
| prefix + * | New floating pane (tmux 3.7+ default binding) |

### Copy mode (vi)

| Key | Action |
|-----|--------|
| v | Begin selection |
| y | Copy to clipboard and exit |
| [ | Jump to previous prompt |
| ] | Jump to next prompt |

---

## zsh

Emacs keybindings.

Source:
- `.zshrc`

| Key | Action |
|-----|--------|
| ⌃+R | History search (fzf; wrapped full-command preview) |
| ⌃+T | File picker (fzf; bat preview; ⌃+O opens in editor) |
| ⌃+G | livegrep (interactive ripgrep → open in editor) |
| ⌃+X ⌃+N | Snippet search → insert |
| ⌃+X ? | Keybinding cheatsheet (keeps the line being edited) |
| ⌃+\ | Undo |
| ⌃+A / E | Beginning / end of line |
| ⌃+W | Delete word backward |
| ⌃+U | Clear line |
| ⌃+L | Clear screen |
| ⌥+B / F | Move word backward / forward |
| ⌥+D | Delete word forward |

### Abbreviations (Space / Enter, command position only)

Source:
- `config/zsh/abbr.zsh`

| Word | Expands to |
|------|------------|
| `ag` | `rg` |
| `ci` | `git commit -a -v` |
| `co` | `git checkout` |
| `di` | `git diff` |
| `ga` | `git add` |
| `gau` | `git add -u` |
| `glg` | `git log --graph` (with color/format) |
| `gr` | `git grep` |
| `lo` | `git log -p` |
| `mysql` | `mysqlsh` |
| `pu` | `git pull` |
| `st` | `git status` |

### Shell helpers

Source:
- `.zshrc`

| Command | Action |
|---------|--------|
| `g [query]` | Jump to a ghq-cloned repo (fzf; README preview) |
| `lg [args]` | lazygit; cd to where you left it |
| `b [query]` | Switch git branch (fzf; last-15-commits preview) |
| `B` | GitHub branch browser (`gh branch` extension) |
| `w [query]` | Jump to a git worktree (fzf) |
| `W <type>/<short-desc>` | New worktree for that branch off the default branch, and cd into it |
| `c` | Switch Kubernetes context (`kubectx`) |
| `l [path]` | Smart viewer: `ll` for dirs, `bat` for files |
| `px` | Toggle between main and sub starship prompt config |
| `temp [prefix]` | cd into a fresh scratch directory under `~/tmp` |
| `snip add [note]` | Save the previous command as a snippet; bare `snip` edits them |
| `keys [query]` | Search these tables (same as ⌃+X ?) |
| `dotfiles-ship` | Push, open a PR, auto-merge, wait for merge, then switch back to `main` |

---

## Neovim (leader: Space)

Source:
- `config/nvim/lua/kimoto/keymaps.lua`
- `config/nvim/lua/kimoto/plugins/*.lua`

Hold a prefix and which-key shows the rest.

### Windows / buffers / tools

| Key | Action |
|-----|--------|
| ⌃+h/j/k/l | Move between windows |
| Space+1~6 | Go to buffer 1~6 |
| Space+n / p | Next / previous buffer |
| Tab / ⇧+Tab | Cycle buffers (bufferline) |
| ⌃+o / ⌃+i | Jump back / forward (jumplist) |
| Space+e | Toggle file tree (nvim-tree) |
| Space+t | Toggle terminal (toggleterm) |
| ⌃+Space | Normal mode: toggle terminal / insert mode: trigger completion |
| Esc | Clear search highlight |

### Telescope

| Key | Action |
|-----|--------|
| Space+ff | Find files |
| Space+fg | Live grep |
| Space+fb | Buffers |
| Space+fh | Help tags |
| Space+fr | Frecency (recent files) |
| Space+fo | Previously opened files (oldfiles) |
| Space+fs | Changed files (git status) |
| Space+fl | Reopen the last picker (resume) |

### LSP / completion

| Key | Action |
|-----|--------|
| gd / gy / gi | Definition / type definition / implementation |
| grn / gra / grr | Rename / code action / references (nvim builtin) |
| K | Hover (nvim builtin) |
| Enter (insert) | Confirm completion (nvim-cmp) |
| Tab / ⇧+Tab (insert) | Next / previous snippet placeholder (LuaSnip) |

### Diagnostics (trouble)

| Key | Action |
|-----|--------|
| Space+xx | Diagnostics, whole workspace |
| Space+xb | Diagnostics, this buffer |
| Space+xq | Quickfix list |
| Space+xl | Location list |

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
| Space+du | Toggle dap-ui |
| Space+dr / Space+dl | Open REPL / run last |
| Space+lp | Set log point |

### Plugin defaults worth knowing

| Key | Action |
|-----|--------|
| gcc / gc{motion} | Toggle comment (Comment.nvim) |
| ys / cs / ds | Add / change / delete surround (vim-surround) |
| ( [ { " ' | Auto-close (nvim-autopairs) |
| Space+j | Jump to definition (any-jump) |
