#!/usr/bin/env bats

# Tests for bin/check_keybindings.sh.
#
# Pins KEYBINDINGS.md's "Terminal" table against
# config/ghostty/config's `keybind = ` lines, its "AeroSpace" /
# "Service mode" tables against .aerospace.toml's `key = command` bindings,
# its tmux "With prefix" / "Copy mode" tables against .tmux.conf, and
# hammerspoon/init.lua's remaps against its "Text editing" table, and its
# zsh / "Abbreviations" tables against .zshrc's `bindkey` lines and
# config/zsh/abbr.zsh's ABBR_MAP, so a
# renamed or removed keybind fails here instead of leaving the reference
# quietly wrong.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/check_keybindings.sh"
  TMP="$(mktemp -d)"
  export CHECK_KEYBINDINGS_GHOSTTY_CONFIG="$TMP/ghostty_config"
  export CHECK_KEYBINDINGS_AEROSPACE_CONFIG="$TMP/aerospace.toml"
  export CHECK_KEYBINDINGS_TMUX_CONFIG="$TMP/tmux.conf"
  export CHECK_KEYBINDINGS_HAMMERSPOON_CONFIG="$TMP/init.lua"
  export CHECK_KEYBINDINGS_DOC="$TMP/KEYBINDINGS.md"
  export CHECK_KEYBINDINGS_ZSHRC="$TMP/zshrc"
  export CHECK_KEYBINDINGS_ABBR_CONFIG="$TMP/abbr.zsh"
  export CHECK_KEYBINDINGS_NVIM_DIR="$TMP/nvim"
  mkdir -p "$CHECK_KEYBINDINGS_NVIM_DIR/plugins"
  cat >"$CHECK_KEYBINDINGS_NVIM_DIR/keymaps.lua" <<'EOF'
vim.keymap.set('n', '<C-l>', '<C-w>l', { desc = 'Window: focus right' })
for i = 1, 3 do
  vim.keymap.set('n', '<leader>' .. i, ':b ' .. i .. '<CR>', { desc = 'Buffer ' .. i })
end
vim.keymap.set('n', '<leader>n', ':bn<CR>', { desc = 'Buffer: next' })
vim.keymap.set("n", "<leader>p", ':bp<CR>', { desc = 'Buffer: previous' })
EOF
  cat >"$CHECK_KEYBINDINGS_NVIM_DIR/plugins/telescope.lua" <<'EOF'
vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = 'Find files' })
vim.keymap.set('n', '<leader>dr', dap.repl.open, { desc = 'Debug: open REPL' })
vim.keymap.set('n', '<leader>dl', dap.run_last, { desc = 'Debug: run last' })
EOF
  cat >"$CHECK_KEYBINDINGS_ZSHRC" <<'EOF'
bindkey -e
bindkey "^\\" undo
bindkey '^X^N' search_snippet_and_replace_lbuffer
  bindkey '^X?' keys_widget
EOF
  cat >"$CHECK_KEYBINDINGS_ABBR_CONFIG" <<'EOF'
typeset -gA ABBR_MAP=(
  ci    'make check'
  glg   "tail -n 20 \
--follow"
)
bindkey ' ' _abbr_expand_space
EOF
  cat >"$CHECK_KEYBINDINGS_HAMMERSPOON_CONFIG" <<'EOF'
remapKey({"alt"}, "b", keyCode("left", {"alt"}))
remapKey({"alt"}, "f", keyCode("right", {"alt"}))
remapKey({"ctrl"}, "/", keyCode("z", {"cmd"}))
EOF
  cat >"$CHECK_KEYBINDINGS_GHOSTTY_CONFIG" <<'EOF'
keybind = global:f12=toggle_quick_terminal
keybind = ¥=text:\\
keybind = super+digit_1=text:\x1b1
keybind = super+digit_2=text:\x1b2
keybind = super+alt+arrow_left=text:\x1b[1;3D
keybind = super+alt+arrow_right=text:\x1b[1;3C
keybind = super+shift+o=toggle_background_opacity
keybind = alt+digit_0=unbind
EOF
  cat >"$CHECK_KEYBINDINGS_AEROSPACE_CONFIG" <<'EOF'
[mode.main.binding]
    alt-h = 'focus left'
    alt-j = 'focus down'
    alt-k = 'focus up'
    alt-l = 'focus right'
    alt-1 = 'workspace 1'
    alt-2 = 'workspace 2'
    alt-slash = 'layout tiles horizontal vertical'

[mode.service.binding]
    esc = ['reload-config', 'mode main']
    alt-shift-h = ['join-with left', 'mode main']
    alt-shift-j = ['join-with down', 'mode main']
    alt-shift-k = ['join-with up', 'mode main']
    alt-shift-l = ['join-with right', 'mode main']

[[on-window-detected]]
  run = 'layout floating'
EOF
  cat >"$CHECK_KEYBINDINGS_TMUX_CONFIG" <<'EOF'
# Each bind-key carries a -N note.
bind-key -N "Jump back to the last window" C-t last-window
unbind-key -T copy-mode-vi v
bind-key -N "Start a selection" -T copy-mode-vi v send-keys -X begin-selection
bind-key -N "Jump to the previous shell prompt" -T copy-mode-vi '[' send-keys -X previous-prompt
bind-key -N "New window" -n M-t new-window
bind-key -N "Reload" r source-file ~/.tmux.conf \; display-message "config reloaded"
bind-key -N "Split right across the window" '\' split-window -fh
if-shell -F '#{>=:#{version},3.7}' \
  'bind-key -N "New Claude Code" a new-pane; bind-key -N "Fork it" A run-shell true'
EOF
  cat >"$CHECK_KEYBINDINGS_DOC" <<'EOF'
## Text editing (every app except the terminal)

| Key | Action |
|-----|--------|
| ⌥+B / F | Word backward / forward |
| ⌥+D | Delete word forward (Windows only) |
| ⌃+/ | Undo |
| ⌃+A / E | Beginning / end of line |

---

## Terminal (intercepts before tmux)

| Key | Action |
|-----|--------|
| ⌘+1~2 | tmux window 1~2 (sends ESC+1~2) |
| ⌘+⌥+← / → | Previous / next tmux window |
| ⇧+Enter / ⌥+Enter | Newline in Claude Code (Windows only) |
| F12 | Toggle quick terminal (Mac only) |
| ⌘+⇧+O | Toggle background opacity (Mac only) |
| ¥ | Insert `\` (Mac only) |

- Mac: ⌥ is Meta; ⌥+0 go to AeroSpace.

---

## AeroSpace (Mac only, intercepts before apps)

| Key | Action |
|-----|--------|
| ⌥+h/j/k/l | Focus window left / down / up / right |
| ⌥+1~2 | Switch to workspace 1~2 |
| ⌥+/ | Layout: tiles (horizontal/vertical) |

### Service mode (⌥+⇧+;, then...)

| Key | Action |
|-----|--------|
| Esc | Reload config, back to main mode |
| ⌥+⇧+h/j/k/l | Join with window left / down / up / right, back to main mode |

---

## tmux (prefix: C-t)

### With prefix (C-t)

| Key | Action |
|-----|--------|
| prefix + C-t | Jump back to the last window |
| prefix + m | Mark pane |
| prefix + r | Reload ~/.tmux.conf |
| prefix + a | New Claude Code session |
| prefix + A | Same, but forking |
| prefix + \ (or prefix + Enter) | tmux-menus |
| prefix + Ctrl-s | Save session state |
| prefix + g, then 1–4 / arrows | Move the floating pane |

### Copy mode (vi)

| Key | Action |
|-----|--------|
| v | Begin selection |
| [ | Jump to previous prompt |

---
EOF
  cat >>"$CHECK_KEYBINDINGS_DOC" <<'EOF'

## zsh

| Key | Action |
|-----|--------|
| ⌃+R | History search |
| ⌃+X ⌃+N | Snippet search |
| ⌃+X ? | Keybinding cheatsheet |
| ⌃+\ | Undo |
| ⌃+A / E | Beginning / end of line |

### Abbreviations (Space / Enter, command position only)

| Word | Expands to |
|------|------------|
| `ci` | `make check` |
| `glg` | `tail -n 20` |

### Shell helpers

| Command | Action |
|---------|--------|
| `g [query]` | Jump to a repo |

---

## Neovim (leader: Space)

### Windows / buffers / tools

| Key | Action |
|-----|--------|
| ⌃+h/j/k/l | Move between windows |
| Space+1~3 | Go to buffer 1~3 |
| Space+n / p | Next / previous buffer |
| ⌃+Space | Toggle terminal |

### Telescope

| Key | Action |
|-----|--------|
| Space+ff | Find files |
| Space+dr / Space+dl | Open REPL / run last |
| Space+j | Jump to definition (any-jump) |
EOF
}

teardown() {
  rm -rf "$TMP"
}

@test "the repo's own KEYBINDINGS.md matches config/ghostty/config" {
  run "$REPO_ROOT/bin/check_keybindings.sh"
  [ "$status" -eq 0 ]
}

@test "accepts a Ghostty config and doc that agree" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "a physical punctuation key name matches the symbol the doc shows" {
  cat >>"$CHECK_KEYBINDINGS_GHOSTTY_CONFIG" <<'EOF'
keybind = ctrl+alt+bracket_left=csi:91;7u
keybind = ctrl+alt+bracket_right=csi:93;7u
keybind = ctrl+alt+quote=csi:39;7u
keybind = ctrl+alt+backslash=csi:92;7u
keybind = ctrl+alt+semicolon=csi:59;7u
keybind = ctrl+alt+minus=csi:45;7u
EOF
  cat >"$TMP/rows" <<'EOF'
| ⌃+⌥+[ / ] | Top-left / top-right quarter |
| ⌃+⌥+' / \ | Bottom-left / bottom-right quarter |
| ⌃+⌥+; / - | Larger / smaller |
EOF
  # Into the existing Terminal table, after its last row.
  sed -i.bak "/^| ¥ |/r $TMP/rows" "$CHECK_KEYBINDINGS_DOC"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "a Windows-only row needs no Ghostty keybind" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Enter"* ]]
}

@test "the AeroSpace-passthrough footnote keys need no row" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"alt+0"* ]]
}

@test "fails when a Ghostty keybind is renamed out from under the doc" {
  sed -i.bak 's/super+shift+o=toggle_background_opacity/super+shift+p=toggle_background_opacity/' \
    "$CHECK_KEYBINDINGS_GHOSTTY_CONFIG"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cmd+shift+p"* ]]
  [[ "$output" == *"cmd+shift+o"* ]]
}

@test "fails when the doc renames a key no Ghostty keybind binds" {
  sed -i.bak 's/| F12 | Toggle quick terminal (Mac only) |/| F11 | Toggle quick terminal (Mac only) |/' \
    "$CHECK_KEYBINDINGS_DOC"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"f12"* ]]
  [[ "$output" == *"f11"* ]]
}

@test "fails when a Ghostty keybind is removed with no matching doc edit" {
  sed -i.bak '/super+shift+o=toggle_background_opacity/d' "$CHECK_KEYBINDINGS_GHOSTTY_CONFIG"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cmd+shift+o"* ]]
}

@test "accepts an AeroSpace config and doc that agree" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "expands an unspaced letter-list cell into one key per letter" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"alt+h"* ]]
  [[ "$output" != *"alt+j"* ]]
  [[ "$output" != *"alt+k"* ]]
  [[ "$output" != *"alt+l"* ]]
}

@test "fails when an AeroSpace main-mode binding is renamed out from under the doc" {
  sed -i.bak "s/alt-slash = 'layout tiles horizontal vertical'/alt-comma = 'layout tiles horizontal vertical'/" \
    "$CHECK_KEYBINDINGS_AEROSPACE_CONFIG"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"alt+,"* ]]
  [[ "$output" == *"alt+/"* ]]
}

@test "fails when the doc renames an AeroSpace key no binding binds" {
  sed -i.bak 's/| Esc | Reload config, back to main mode |/| Delete | Reload config, back to main mode |/' \
    "$CHECK_KEYBINDINGS_DOC"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"esc"* ]]
  [[ "$output" == *"delete"* ]]
}

@test "fails when an AeroSpace service-mode binding is removed with no matching doc edit" {
  sed -i.bak "/alt-shift-l = \['join-with right', 'mode main'\]/d" "$CHECK_KEYBINDINGS_AEROSPACE_CONFIG"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"shift+alt+l"* ]]
}

@test "accepts a tmux config and doc that agree, plugin and default keys included" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"tmux"* ]]
}

@test "fails when a tmux prefix binding is renamed out from under the doc" {
  sed -i.bak 's/"Reload" r source-file/"Reload" R source-file/' "$CHECK_KEYBINDINGS_TMUX_CONFIG"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"binds 'R'"* ]]
  [[ "$output" == *"names 'r'"* ]]
}

@test "fails when a tmux binding inside an if-shell string has no row" {
  sed -i.bak '/| prefix + A |/d' "$CHECK_KEYBINDINGS_DOC"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"binds 'A'"* ]]
}

@test "fails when the doc names a copy-mode key tmux.conf does not bind" {
  sed -i.bak 's/^| \[ | Jump to previous prompt |$/| ] | Jump to previous prompt |/' "$CHECK_KEYBINDINGS_DOC"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"binds '['"* ]]
  [[ "$output" == *"names ']'"* ]]
}

@test "a cell's escaped pipe is the | key, not the end of the cell" {
  echo "bind-key -N \"Split right\" '|' split-window -h" >>"$CHECK_KEYBINDINGS_TMUX_CONFIG"
  awk '{ print } /^\| prefix \+ m \|/ { print "| prefix + \\| | Split right |" }' \
    "$CHECK_KEYBINDINGS_DOC" >"$TMP/doc" && mv "$TMP/doc" "$CHECK_KEYBINDINGS_DOC"
  grep -qxF '| prefix + \| | Split right |' "$CHECK_KEYBINDINGS_DOC"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "a bare double-quote cell is the \" key the config quotes" {
  echo "bind-key -N \"Split below\" '\"' split-window -v" >>"$CHECK_KEYBINDINGS_TMUX_CONFIG"
  awk '{ print } /^\| prefix \+ m \|/ { print "| prefix + \" | Split below |" }' \
    "$CHECK_KEYBINDINGS_DOC" >"$TMP/doc" && mv "$TMP/doc" "$CHECK_KEYBINDINGS_DOC"
  grep -qxF '| prefix + " | Split below |' "$CHECK_KEYBINDINGS_DOC"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "an unbind-key is not a binding" {
  sed -i.bak '/"Start a selection"/d' "$CHECK_KEYBINDINGS_TMUX_CONFIG"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"names 'v'"* ]]
}

@test "a Text editing row with no Hammerspoon remap is a macOS built-in, not a mismatch" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ctrl+a"* ]]
}

@test "fails when a Hammerspoon remap is renamed out from under the doc" {
  sed -i.bak 's|remapKey({"ctrl"}, "/"|remapKey({"ctrl"}, "."|' "$CHECK_KEYBINDINGS_HAMMERSPOON_CONFIG"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"binds 'ctrl+.'"* ]]
}

@test "a Windows-only Text editing row does not cover a Hammerspoon remap" {
  echo 'remapKey({"alt"}, "d", keyCode("forwarddelete", {"alt"}))' >>"$CHECK_KEYBINDINGS_HAMMERSPOON_CONFIG"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"binds 'alt+d'"* ]]
}

@test "accepts a zsh config and doc that agree, fzf and emacs-keymap keys included" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "fails when a zsh bindkey is renamed out from under the doc" {
  sed -i.bak "s/'^X^N'/'^X^S'/" "$CHECK_KEYBINDINGS_ZSHRC"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"binds 'ctrl+x ctrl+s' but KEYBINDINGS.md's zsh table has no row"* ]]
  [[ "$output" == *"zsh table names 'ctrl+x ctrl+n' but no"* ]]
}

@test "a double-quoted \\\\ in a bindkey is the one backslash key the doc shows" {
  sed -i.bak '/undo/d' "$CHECK_KEYBINDINGS_ZSHRC"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"zsh table names 'ctrl+\\' but no"* ]]
}

@test "a bindkey with an option is not a key binding" {
  echo "bindkey -M viins '^Y' yank" >>"$CHECK_KEYBINDINGS_ZSHRC"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "a bindkey into the emacs keymap by name still needs a row" {
  echo "bindkey -M emacs '^Y' yank" >>"$CHECK_KEYBINDINGS_ZSHRC"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"binds 'ctrl+y' but KEYBINDINGS.md's zsh table has no row"* ]]
}

@test "a bindkey into the main keymap by name still needs a row" {
  echo "bindkey -M main ^Y yank" >>"$CHECK_KEYBINDINGS_ZSHRC"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"binds 'ctrl+y' but KEYBINDINGS.md's zsh table has no row"* ]]
}

@test "a commented-out bindkey is not a binding" {
  echo "# bindkey '^Y' yank" >>"$CHECK_KEYBINDINGS_ZSHRC"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "binding a key fzf or the emacs keymap owns is fine while its row stays" {
  echo "bindkey '^R' my-history-widget" >>"$CHECK_KEYBINDINGS_ZSHRC"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "an Escape-prefixed bindkey is the Alt key" {
  echo "bindkey '\\eq' push-line" >>"$CHECK_KEYBINDINGS_ZSHRC"
  echo "bindkey '^[w' copy-region" >>"$CHECK_KEYBINDINGS_ZSHRC"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"binds 'alt+q' but"* ]]
  [[ "$output" == *"binds 'alt+w' but"* ]]
}

@test "a single-quoted ^\\\\ is the same backslash key as the double-quoted one" {
  sed -i.bak '/undo/d' "$CHECK_KEYBINDINGS_ZSHRC"
  echo "bindkey '^\\\\' undo" >>"$CHECK_KEYBINDINGS_ZSHRC"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "an indented continuation of an abbreviation's value is not an abbreviation" {
  sed -i.bak 's/^--follow"/    --follow -q"/' "$CHECK_KEYBINDINGS_ABBR_CONFIG"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "fails when ABBR_MAP cannot be found at all" {
  sed -i.bak 's/^typeset -gA ABBR_MAP=(/typeset -A ABBR_MAP=(/' "$CHECK_KEYBINDINGS_ABBR_CONFIG"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no ABBR_MAP entries found"* ]]
}

@test "fails when an abbreviation is added with no row" {
  awk '/^  ci /{print "  gp    \047make push\047"} {print}' "$CHECK_KEYBINDINGS_ABBR_CONFIG" >"$TMP/abbr.new"
  mv "$TMP/abbr.new" "$CHECK_KEYBINDINGS_ABBR_CONFIG"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ABBR_MAP binds 'gp' but KEYBINDINGS.md's Abbreviations table has no row"* ]]
}

@test "fails when the doc names an abbreviation ABBR_MAP does not have" {
  sed -i.bak 's/^| `ci` |/| `cm` |/' "$CHECK_KEYBINDINGS_DOC"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Abbreviations table names 'cm' but no"* ]]
}

@test "accepts Neovim leader maps and a doc that agree, loop and plugin-default keys included" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "fails when a Neovim leader map is renamed out from under the doc" {
  sed -i.bak "s/'<leader>ff'/'<leader>fF'/" "$CHECK_KEYBINDINGS_NVIM_DIR/plugins/telescope.lua"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"binds 'Space+fF' but KEYBINDINGS.md's Neovim section has no row"* ]]
  [[ "$output" == *"Neovim section names 'Space+ff' but no"* ]]
}

@test "fails when a leader map's loop range grows past the doc's range" {
  sed -i.bak 's/^for i = 1, 3 do/for i = 1, 4 do/' "$CHECK_KEYBINDINGS_NVIM_DIR/keymaps.lua"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"binds 'Space+4' but KEYBINDINGS.md's Neovim section has no row"* ]]
}

@test "fails when the second alternate of a Space row loses its map" {
  sed -i.bak '/<leader>p/d' "$CHECK_KEYBINDINGS_NVIM_DIR/keymaps.lua"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Neovim section names 'Space+p' but no"* ]]
}

@test "a commented-out leader map is not a binding" {
  echo "-- vim.keymap.set('n', '<leader>zz', ':q<CR>')" >>"$CHECK_KEYBINDINGS_NVIM_DIR/keymaps.lua"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "fails when ABBR_MAP is lost and the doc's Abbreviations rows go with it" {
  sed -i.bak 's/^typeset -gA ABBR_MAP=(/typeset -A ABBR_MAP=(/' "$CHECK_KEYBINDINGS_ABBR_CONFIG"
  sed -i.bak '/^| `ci` |/d; /^| `glg` |/d' "$CHECK_KEYBINDINGS_DOC"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no ABBR_MAP entries found"* ]]
}

@test "fails when a leader map's lhs cannot be expanded, though every other key agrees" {
  echo "vim.keymap.set('n', '<leader>' .. key, ':q<CR>')" >>"$CHECK_KEYBINDINGS_NVIM_DIR/keymaps.lua"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot expand <leader> .. key"* ]]
}
