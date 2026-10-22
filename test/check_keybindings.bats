#!/usr/bin/env bats

# Tests for bin/check_keybindings.sh.
#
# Three layers of #249: pins KEYBINDINGS.md's "Terminal" table against
# config/ghostty/config's `keybind = ` lines, its "AeroSpace" /
# "Service mode" tables against .aerospace.toml's `key = command` bindings,
# and its tmux "With prefix" / "Copy mode" tables against .tmux.conf, so a
# renamed or removed keybind fails here instead of leaving the reference
# quietly wrong.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/check_keybindings.sh"
  TMP="$(mktemp -d)"
  export CHECK_KEYBINDINGS_GHOSTTY_CONFIG="$TMP/ghostty_config"
  export CHECK_KEYBINDINGS_AEROSPACE_CONFIG="$TMP/aerospace.toml"
  export CHECK_KEYBINDINGS_TMUX_CONFIG="$TMP/tmux.conf"
  export CHECK_KEYBINDINGS_DOC="$TMP/KEYBINDINGS.md"
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
if-shell -F '#{>=:#{version},3.7}' \
  'bind-key -N "New Claude Code" a new-pane; bind-key -N "Fork it" A run-shell true'
EOF
  cat >"$CHECK_KEYBINDINGS_DOC" <<'EOF'
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

@test "an unbind-key is not a binding" {
  sed -i.bak '/"Start a selection"/d' "$CHECK_KEYBINDINGS_TMUX_CONFIG"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"names 'v'"* ]]
}
