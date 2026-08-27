# Keybindings

Hierarchical keybinding reference. Upper layers intercept keys first.

Sources: `hammerspoon/init.lua`, AeroSpace (`.aerospace.toml`),
`config/ghostty/config`, `.tmux.conf`, `.zshrc`, `config/zsh/abbr.zsh`,
`config/nvim/` — each carries a pointer comment back to this file; update this
file whenever a binding changes there.

Symbols: ⌘ = Command, ⌥ = Option/Alt, ⌃ = Control, ⇧ = Shift

The tables below are also the data behind `bin/keys.sh`, which turns them into a
searchable picker — `prefix + ?` in tmux, `⌃+X ?` (or the `keys` command) in
zsh. Each row it prints is tagged with the layer it came from, so adding a row
here is all it takes to make a new binding discoverable at the keyboard.

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

## Windows (global)

The other machine. A peer of the macOS layer, not another level on top of it —
the two are different devices and never in effect at once. Modifiers are spelled
out because Win is not ⌘: it sits where a Mac keyboard has Alt. Stock Windows
keys are not listed; only what this setup adds.

### ShareX (screen capture)

ShareX's `HotkeysConfig.json` lives under `%USERPROFILE%` and cannot be
symlinked in (a symlink made from WSL under `/mnt/c` is not one Windows can
follow), so this table is the only copy under version control.

| Key | Action |
|-----|--------|
| Ctrl+Shift+Win+4 | Capture region → clipboard only. Stands in for ⌃⇧⌘4; the only one that writes no file, so the only one OneDrive never sees |
| Ctrl+PrintScreen | Capture region → clipboard + file |
| PrintScreen | Capture all screens → clipboard + file |
| Alt+PrintScreen | Capture active window → clipboard + file |
| Shift+PrintScreen | Start / stop screen recording (region) |
| Ctrl+Shift+PrintScreen | Same, as GIF |

Ctrl+Shift+Win+4 collides with Windows' own Win+Ctrl+Shift+&lt;n&gt;; ShareX wins
the `RegisterHotKey` race, so if it ever stops firing, check that first.

---

## Hammerspoon (global remaps, every app except Ghostty)

| Key | Action |
|-----|--------|
| ⌥+B / F | Move word backward / forward (emacs-style) |
| ⌃+W | Delete word backward |
| ⌃+/ | Undo (⌘+Z) |

Ghostty is excluded — the terminal gets these natively via zsh/nvim readline
bindings, so remapping there would double-apply or break them.

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
| ⌥+F / ⌥+⇧+F | Fullscreen |
| ⌥+0 | Reset layout (flatten workspace tree) |
| ⌥+⇧+; | Enter service mode |

⌥+⇧+F means something different once you're in service mode below — it floats
all windows in the workspace instead of toggling fullscreen.

### Service mode (⌥+⇧+;, then...)

| Key | Action |
|-----|--------|
| Esc | Reload config, back to main mode |
| R | Reset layout (flatten workspace tree), back to main mode |
| F | Toggle floating/tiling layout, back to main mode |
| Backspace | Close all windows but current, back to main mode |
| ⌥+⇧+T | Tile all windows in focused workspace (`bin/tile-focused-workspace.sh tiling`), back to main mode |
| ⌥+⇧+F | Float all windows in focused workspace (`bin/tile-focused-workspace.sh floating`), back to main mode |
| ⌥+⇧+h/j/k/l | Join with window left / down / up / right, back to main mode |
| Down / Up | Volume down / up |
| ⇧+Down | Mute (volume set 0), back to main mode |

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
| Mouse wheel | Scroll pane / enter copy-mode; scrolling to the bottom exits copy-mode (tmux-better-mouse-mode) |

⌥⌘+hjkl works because Ghostty sends ESC+hjkl (M-hjkl) even with ⌘ held,
while AeroSpace only intercepts plain ⌥+hjkl.

### With prefix (C-t)

While the prefix is held, status-right turns into a hint of the most-used keys
below (`? help  g lazygit  t shell`), so the common ones never need looking up.
The hint takes the place of the kube/clock segment rather than pushing it along,
which is what keeps the window list from being cut short while you hold the
prefix — that is also why only three keys fit; `prefix + ?` has the rest.
`prefix + b` hides the status bar, and with it the hint.

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
| prefix + t | Throwaway shell in a popup (floating pane on tmux 3.7+; replaces clock-mode) |
| prefix + a | A second Claude Code in a floating pane, same cwd (tmux 3.7+ only, no popup fallback). A fresh session — nothing is carried over from the pane it was opened from |
| prefix + A | Same, but forking the Claude Code session running in this pane: it keeps the conversation so far and writes a separate transcript from there, so a long investigation does not bloat the original |
| prefix + f | fzf switcher across all panes of all sessions with live preview (replaces find-window); most-recently-used first, current pane omitted |
| prefix + F | tmux-fzf: fzf menu for sessions/windows/panes (switch, rename, kill, etc.) |
| prefix + \ (or prefix + Enter) | tmux-menus: open popup menu (session/window/pane actions) |
| prefix + ? | tmux-which-key: menu tree of tmux commands (windows, panes, buffers, sessions, client); its +Keys entry is where `list-keys -N` lives |
| prefix + Ctrl-s | Save tmux session state (tmux-resurrect; tmux-continuum also auto-saves every 15 min and auto-restores it on tmux start; tmux-assistant-resurrect also saves AI coding assistant sessions, e.g. Claude Code) |
| prefix + Ctrl-r | Restore last saved tmux session state (tmux-resurrect; tmux-assistant-resurrect also resumes saved AI coding assistant sessions) |
| prefix + Tab | extrakto: fuzzy-extract word/path/url/line from pane scrollback (Tab copies to clipboard, Enter inserts into pane); opens in a floating pane on tmux 3.7+, taking the half of the window the cursor is not in so it never covers the lines you are picking from |
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
| ⌃+X ? | Keybinding cheatsheet: fzf over this whole file, mid-command (the line being edited is kept; nothing is inserted). Replaces compinit's `_complete_debug` |
| ⌃+\ | Undo |
| ⌃+A / E | Beginning / end of line |
| ⌃+W | Delete word backward |
| ⌃+U | Clear line |
| ⌃+L | Clear screen |
| ⌥+B / F | Move word backward / forward |
| ⌥+D | Delete word forward |

### Abbreviations (Space / Enter, command position only)

Static word → command expansion defined in `config/zsh/abbr.zsh` (a minimal
zsh-abbr replacement). Typing one of these words where a command starts, then
pressing Space or Enter, expands it in place:

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

Short interactive commands defined in `.zshrc` for frequent workflows:

| Command | Action |
|---------|--------|
| `g [query]` | Jump to a ghq-cloned repo (fzf; README preview) |
| `lg [args]` | Launch lazygit (args passed through); chase into the directory it was left in |
| `b [query]` | Switch git branch (fzf; last-15-commits preview) |
| `B` | GitHub branch browser (`gh branch`; needs a manually installed gh extension, e.g. `mislav/gh-branch` — not part of `mkworld.sh`) |
| `w [query]` | Jump to a git worktree (fzf) |
| `c` | Switch Kubernetes context (`kubectx`) |
| `l [path]` | Smart viewer: `ll` for dirs, `bat` for files |
| `px` | Toggle between main and sub starship prompt config |
| `temp [prefix]` | cd into a fresh scratch directory under `~/tmp` |
| `snip add [note]` | Save the previous command as a ⌃+X ⌃+N snippet; bare `snip` edits the snippet file |
| `keys [query]` | Search this file's keybinding/helper tables (fzf; `bin/keys.sh`, same picker as ⌃+X ? and tmux's prefix + ?) |
| `dotfiles-ship` | Push, open a PR, auto-merge, wait for merge, then switch back to `main` |

---

## Neovim (leader: Space)

Defined in `config/nvim/lua/kimoto/keymaps.lua` and
`config/nvim/lua/kimoto/plugins/*.lua`.

Every map is registered with a `desc`, and which-key.nvim renders them: hold a
prefix (Space, `g`, `z`, …) for ~300ms and the follow-ups appear in a popup.
This table is the copy you read on purpose; the popup is the one that reaches
you when you have forgotten a binding exists.

### Windows / buffers / tools

| Key | Action |
|-----|--------|
| ⌃+h/j/k/l | Move between windows |
| Space+1~6 | Go to buffer 1~6 |
| Space+n / p | Next / previous buffer |
| Tab / ⇧+Tab | Cycle buffers (bufferline) |
| ⌃+o / ⌃+i | Jump back / forward (jumplist) — ⌃+i is mapped explicitly so Tab's buffer cycling does not swallow it |
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
| Tab / ⇧+Tab (insert) | Next / previous snippet placeholder (LuaSnip); a plain Tab when no snippet is active |

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
