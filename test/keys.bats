#!/usr/bin/env bats

# Tests for bin/keys.sh — the keybinding cheatsheet picker behind zsh's
# `keys` helper and ⌃+X ? widget.
#
# Only the extraction half is unit-testable here (--list skips fzf); driving the
# picker itself is bin/ci_keys_command_test.sh. What must hold: every table row
# in KEYBINDINGS.md is emitted exactly once, prefixed with the layer it belongs
# to (plus the subsection, so `prefix + g` is distinguishable from a zsh key),
# and the Markdown scaffolding — header rows and |---| separators — never leaks
# into the list, since those would be unselectable noise in the picker.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/keys.sh"
  TMP="$(mktemp -d)"
  DOC="$TMP/KEYBINDINGS.md"
  cat >"$DOC" <<'EOF'
# Keybindings

Intro prose that must not appear in the list.

## Layer One

| Key | Action |
|-----|--------|
| A | do alpha |

## Layer Two

More prose.

### Sub A

| Key | Action |
|-----|--------|
| B | do beta |

### Sub B

| Command | Action |
|---------|--------|
| `x` | run x |

| Word | Expands to |
|------|------------|
| `ag` | `rg` |
EOF
}

teardown() {
  rm -rf "$TMP"
}

@test "prefixes each row with its layer" {
  KEYBINDINGS_MD="$DOC" run "$SCRIPT" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Layer One] A | do alpha"* ]]
}

@test "appends the subsection to the layer when there is one" {
  KEYBINDINGS_MD="$DOC" run "$SCRIPT" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Layer Two / Sub A] B | do beta"* ]]
  [[ "$output" == *'[Layer Two / Sub B] `x` | run x'* ]]
}

@test "a later subsection does not inherit the previous one" {
  KEYBINDINGS_MD="$DOC" run "$SCRIPT" --list
  [ "$status" -eq 0 ]
  [[ "$output" != *"Sub A / Sub B"* ]]
  [[ "$output" != *"[Layer Two / Sub A] \`x\`"* ]]
}

@test "drops the table scaffolding (header rows and separators)" {
  KEYBINDINGS_MD="$DOC" run "$SCRIPT" --list
  [ "$status" -eq 0 ]
  [[ "$output" != *"Key | Action"* ]]
  [[ "$output" != *"Command | Action"* ]]
  [[ "$output" != *"Word | Expands to"* ]]
  [[ "$output" != *"---"* ]]
}

@test "ignores prose outside the tables" {
  KEYBINDINGS_MD="$DOC" run "$SCRIPT" --list
  [ "$status" -eq 0 ]
  [[ "$output" != *"prose"* ]]
  [ "${#lines[@]}" -eq 4 ]
}

@test "fails loudly when the reference document is missing" {
  KEYBINDINGS_MD="$TMP/nope.md" run "$SCRIPT" --list
  [ "$status" -ne 0 ]
  [[ "$output" == *"nope.md"* ]]
}

@test "lists the repo's own tmux and zsh cheatsheet keys" {
  run "$SCRIPT" --list
  [ "$status" -eq 0 ]
  # prefix + ? is tmux-which-key's menu, not this picker; ⌃+X ? is the binding
  # that opens this picker in zsh.
  [[ "$output" == *"[tmux (prefix: C-t) / With prefix (C-t)] prefix + ?"* ]]
  [[ "$output" == *"[zsh (emacs mode)] ⌃+X ?"* ]]
}
