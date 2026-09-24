# Keybindings

Hierarchical keybinding reference. Upper layers intercept keys first.

Symbols: ⌘ = Command, ⌥ = Option/Alt, ⌃ = Control, ⇧ = Shift

Search these tables from zsh with `keys` or ⌃+X ?.

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
| ⌃+⌘+⇧+3 / 4 | Same full / selection capture, clipboard only (no file) |

---

## Raycast (macOS, global)

Source: set in-app, not in this repo

| Key | Action |
|-----|--------|
| ⌃⌘+V | Clipboard history |
| ⌃⌘+C | Snippets |

---

## Rectangle (macOS, global)

Source: in-app, readable with `defaults read com.knollsoft.Rectangle`

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
| ⌃⌥+B | Toggle Todo mode (Logseq pinned as a side column) |
| ⌃⌥+N | Reflow Todo |

---

## Windows (global)

Driven from a Mac keyboard, so ⌘ arrives as **Win**. Stock Windows keys are not listed.

### AutoHotkey (global remaps, every app except Windows Terminal)

Source: `windows/autohotkey/mac-keys.ahk`

| Key | Action |
|-----|--------|
| Alt+B / F | Move word backward / forward (sends Ctrl+←/→) |
| Ctrl+/ | Undo (sends Ctrl+Z) |
| Ctrl+A / E | Beginning / end of line |
| Ctrl+B / F | Move one character backward / forward |
| Ctrl+P / N | Move up / down |
| Ctrl+H / D | Delete one character backward / forward |
| Ctrl+K | Delete to end of line; at line end, delete the next newline. No kill ring |
| Ctrl+W / Alt+D | Delete previous / next word |
| Win+A/C/F/N/P/R/S/T/V/W/X/Z | Send the corresponding Ctrl shortcut (select all, copy, find, new, print, reload, save, new tab, paste, close, cut, undo) |
| Win+Shift+Z / T | Redo (Ctrl+Y) / reopen closed tab |
| Win+Left / Right | Beginning / end of line |
| Win+Up / Down | Beginning / end of document |

These apply outside text fields too: close a tab with Win+W, not Ctrl+W.

### AutoHotkey (inside Windows Terminal only)

Source: `windows/autohotkey/mac-keys.ahk`

| Key | Action |
|-----|--------|
| Win+1~9 | → sends ESC+1~9 to tmux (select window 1~9) |
| Win+Alt+←/→ | → sends ⌥+←/→ to tmux (previous / next window) |
| Win+Alt+↑/↓ | → sends ⌥+↑/↓ to tmux (previous / next session) |

### Windows Terminal (all profiles)

Source: `windows/windows-terminal/keybindings.json`

| Key | Action |
|-----|--------|
| Shift+Enter / Alt+Enter | Send LF (Ctrl+J): insert a newline in Claude Code, including through tmux |

At a shell prompt these run the command like Enter. F11 toggles fullscreen.

### ShareX (screen capture)

Source: `HotkeysConfig.json` under `%USERPROFILE%`, not in this repo

| Key | Action |
|-----|--------|
| Ctrl+Shift+Win+4 | Capture region → image editor → Enter copies it to the clipboard (no file) |
| Ctrl+PrintScreen | Capture region → clipboard + file |
| PrintScreen | Capture all screens → clipboard + file |
| Alt+PrintScreen | Capture active window → clipboard + file |
| Shift+PrintScreen | Start / stop screen recording (region) |
| Ctrl+Shift+PrintScreen | Same, as GIF |

### ShareX image editor (after Ctrl+Shift+Win+4)

Source: `ApplicationConfig.json` (`ImageEditorOptions.ToolbarItems`), not in this repo

| Key | Action |
|-----|--------|
| R | Rectangle (outline) |
| A | Arrow |
| P | Pixelate |
| C | Step counter (1, 2, 3…) |
| T | Text (outlined) |
| Enter | Done: copy to clipboard and close. While typing text, it only commits the text |
| Win+Shift+C (⇧⌘C) | Same as Enter, via `mac-keys.ahk` |

---

## Hammerspoon (global remaps, every app except Ghostty)

Source: `hammerspoon/init.lua`

| Key | Action |
|-----|--------|
| ⌥+B / F | Move word backward / forward (emacs-style) |
| ⌃+W | Delete word backward |
| ⌃+/ | Undo (⌘+Z) |

---

## AeroSpace (global, intercepts before apps)

Source: `.aerospace.toml`

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

## Ghostty (intercepts before tmux)

Source: `config/ghostty/config`

| Key | Action |
|-----|--------|
| F12 | Toggle quick terminal (global) |
| ⌘+1~9 | → sends ESC+1~9 to tmux (window switching) |
| ⌘⌥+←/→/↑/↓ | → sends ⌥+arrows to tmux (window / session switching) |
| ⌘+⇧+O | Toggle background opacity |
| ¥ | Insert `\` (backslash) |

⌥ acts as Meta (ESC prefix). ⌥+0~5 pass through to AeroSpace.

---

## tmux (prefix: C-t)

Source: `.tmux.conf`

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
| prefix + Ctrl-s | Save session state, Claude Code sessions included (also auto-saved every 15 min) |
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

## zsh (emacs mode)

Source: `.zshrc`

| Key | Action |
|-----|--------|
| ⌃+R | History search (fzf; wrapped full-command preview) |
| ⌃+T | File picker (fzf; bat preview; ⌃+O opens in editor) |
| ⌃+G | livegrep (interactive ripgrep → open in editor) |
| ⌃+X ⌃+N | Snippet search (fzf over `config/zsh/snippets`) → insert into command line |
| ⌃+X ? | Keybinding cheatsheet (keeps the line being edited) |
| ⌃+\ | Undo |
| ⌃+A / E | Beginning / end of line |
| ⌃+W | Delete word backward |
| ⌃+U | Clear line |
| ⌃+L | Clear screen |
| ⌥+B / F | Move word backward / forward |
| ⌥+D | Delete word forward |

### Abbreviations (Space / Enter, command position only)

Source: `config/zsh/abbr.zsh`

Type the word where a command starts, then Space or Enter.

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

Source: `.zshrc`

| Command | Action |
|---------|--------|
| `g [query]` | Jump to a ghq-cloned repo (fzf; README preview) |
| `lg [args]` | Launch lazygit (args passed through); chase into the directory it was left in |
| `b [query]` | Switch git branch (fzf; last-15-commits preview) |
| `B` | GitHub branch browser (`gh branch` extension) |
| `w [query]` | Jump to a git worktree (fzf) |
| `W <type>/<short-desc>` | New worktree for that branch off the default branch, and cd into it |
| `c` | Switch Kubernetes context (`kubectx`) |
| `l [path]` | Smart viewer: `ll` for dirs, `bat` for files |
| `px` | Toggle between main and sub starship prompt config |
| `temp [prefix]` | cd into a fresh scratch directory under `~/tmp` |
| `snip add [note]` | Save the previous command as a ⌃+X ⌃+N snippet; bare `snip` edits the snippet file |
| `keys [query]` | Search these tables (same as ⌃+X ?) |
| `dotfiles-ship` | Push, open a PR, auto-merge, wait for merge, then switch back to `main` |

---

## Neovim (leader: Space)

Source: `config/nvim/lua/kimoto/keymaps.lua`, `config/nvim/lua/kimoto/plugins/*.lua`

Hold a prefix (Space, `g`, `z`, …) and which-key shows what follows.

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
| ( [ { " ' | Auto-closed (nvim-autopairs); Enter stays with vim-endwise so `end` still gets added |
| Space+j | Jump to definition (any-jump) |
