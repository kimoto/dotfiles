#!/usr/bin/env bats

# Tests for bin/check_keybindings.sh.
#
# First layer of #249: pins KEYBINDINGS.md's "Terminal" table against
# config/ghostty/config's `keybind = ` lines, so a renamed or removed Ghostty
# keybind fails here instead of leaving the reference quietly wrong.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/check_keybindings.sh"
  TMP="$(mktemp -d)"
  export CHECK_KEYBINDINGS_GHOSTTY_CONFIG="$TMP/ghostty_config"
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

## macOS (Mac only)
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
