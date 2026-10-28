#!/usr/bin/env bats

# Tests for hammerspoon/translate.lua's keys, under plain luajit with a fake
# `hs` (test/fixtures/hs_stub.lua), since Hammerspoon runs only on a Mac. What
# must hold: ⌃⌘⇧W copies the selection before the menu opens (the menu takes
# the focus, so a later ⌘C would miss the app), and each menu row starts
# translate.py with its own job and the clipboard. The popup's look and the
# real keys are checked by hand on a Mac.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

# Loads translate.lua under the stub, then runs the Lua in $1 and prints what
# it prints.
drive() {
  luajit -e "
    dofile('$REPO_ROOT/test/fixtures/hs_stub.lua')
    dofile('$REPO_ROOT/hammerspoon/translate.lua')
    $1"
}

# Presses ⌃⌘⇧W, lets the copy land, picks the row, and prints the argv given
# to translate.py.
pick() {
  drive "
    stub.hotkeys['ctrl+cmd+shift+w']()
    assert(#stub.choosers == 0, 'menu opened before the copy landed')
    stub.tick()
    stub.choose('$1')
    print(table.concat(stub.tasks[#stub.tasks].argv, ' ', 2))"
}

@test "⌃⌘⇧W copies the selection, then opens the menu" {
  run drive "
    stub.hotkeys['ctrl+cmd+shift+w']()
    print(table.concat(stub.keystrokes, ','), #stub.choosers)
    stub.tick()
    print(#stub.choosers, #stub.tasks)"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf 'cmd+c\t0')" ]
  [ "${lines[1]}" = "$(printf '1\t0')" ]
}

@test "each menu row starts translate.py with its own job on the clipboard" {
  local label expected
  while IFS='|' read -r label expected; do
    run pick "$label"
    [ "$status" -eq 0 ] || { echo "$label: $output"; return 1; }
    [ "$output" = "$expected" ] || { echo "$label: got '$output'"; return 1; }
  done <<'ROWS'
清書|--quiet --rewrite --clipboard
返信案|--quiet --reply --clipboard
要約|--quiet --summarize --clipboard
誤字チェック|--quiet --proofread --clipboard
翻訳|--quiet --clipboard
ROWS
}

@test "every menu row names a job translate.py knows" {
  run drive "for _, row in ipairs((function()
      stub.hotkeys['ctrl+cmd+shift+w'](); stub.tick()
      return stub.choosers[#stub.choosers].list end)()) do print(row.job) end"
  [ "$status" -eq 0 ]
  for job in "${lines[@]}"; do
    [ "$job" = translate ] && continue
    grep -q "const=\"$job\"" "$REPO_ROOT/hammerspoon/translate.py" || { echo "unknown job $job"; return 1; }
  done
}

@test "⌃⌘⇧D still translates the selection straight away, without a menu" {
  run drive "
    stub.hotkeys['ctrl+cmd+shift+d']()
    stub.tick()
    print(#stub.choosers, table.concat(stub.tasks[1].argv, ' ', 2))"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '0\t--quiet --clipboard')" ]
}
