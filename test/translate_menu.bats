#!/usr/bin/env bats

# Tests for hammerspoon/translate.lua's keys, under plain luajit with a fake
# `hs` (test/fixtures/hs_stub.lua), since Hammerspoon runs only on a Mac. What
# must hold: ⌃⌘⇧W copies the selection before the menu opens (the menu takes
# the focus, so a later ⌘C would miss the app), each menu row starts
# translate.py with its own job and the clipboard under its own popup title,
# and a diagram never shows as SVG markup, ends in a reason when it fails, and
# is pasted as an image. The popup's look and the real keys are checked by
# hand on a Mac.

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
図解|--quiet --diagram --clipboard
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

# Runs the 図解 row with its popup's page loaded, then the Lua in $1.
diagram() {
  drive "
    stub.hotkeys['ctrl+cmd+shift+w']()
    stub.tick()
    stub.choose('図解')
    local view, task = stub.popups[#stub.popups], stub.tasks[#stub.tasks]
    view:post({ ready = true })
    $1"
}

@test "each menu row opens its popup under its own title" {
  local label
  for label in 清書 返信案 要約 誤字チェック 図解 翻訳; do
    run drive "
      stub.hotkeys['ctrl+cmd+shift+w']()
      stub.tick()
      stub.choose('$label')
      print(stub.popups[#stub.popups].page:match('class=\"title\">([^<]*)<'))"
    [ "$status" -eq 0 ] || { echo "$label: $output"; return 1; }
    [ "$output" = "$label" ] || { echo "$label: titled '$output'"; return 1; }
  done
}

@test "a diagram half written never shows as markup" {
  run diagram "
    task.stream(task, '<svg width=\"480\"><rect', '')
    print(stub.lastUpdate())"
  [ "$status" -eq 0 ]
  [[ "$output" != *"<svg"* ]]
}

@test "a finished diagram goes to the page as an SVG" {
  run diagram "
    task.done(0, '<svg width=\"480\"></svg>', '')
    print(stub.lastUpdate())"
  [ "$status" -eq 0 ]
  [[ "$output" == *'<svg'*'"busy",true])' ]]
}

@test "a failed diagram shows only the reason, not half an SVG" {
  run diagram "
    task.done(1, '<svg width=\"480\"><rect', '図になりませんでした')
    print(stub.lastUpdate())"
  [ "$status" -eq 0 ]
  [[ "$output" == *'図になりませんでした'*'"error"'* ]]
  [[ "$output" != *"<svg"* ]]
}

@test "an SVG the page cannot draw ends in an error, not a spinner" {
  run diagram "
    task.done(0, '<svg width=\"480\">R&D</svg>', '')
    view:post({ svgError = true })
    print(stub.lastUpdate())"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"error"'* ]]
}

@test "the page's PNG is pasted as an image, and its files are removed" {
  run diagram "
    task.done(0, '<svg width=\"480\"></svg>', '')
    view:post({ png = 'data:image/png;base64,QUJD' })
    print(stub.pasted[1], stub.lastUpdate())
    for _, path in ipairs(stub.written) do assert(not io.open(path), path .. ' left behind') end"
  [ "$status" -eq 0 ]
  [[ "$output" == "PNG:QUJD"*"画像をコピー済み"* ]]
}

# /tmp is shared: another account could plant a symlink at the name before
# the PNG is written through it.
@test "the PNG goes through the user's own temp dir, not the shared /tmp" {
  run diagram "
    task.done(0, '<svg width=\"480\"></svg>', '')
    view:post({ png = 'data:image/png;base64,QUJD' })
    print(stub.written[1])"
  [ "$status" -eq 0 ]
  [[ "$output" == "$BATS_TEST_TMPDIR/"* ]]
}

@test "a message from a popup that was replaced is ignored" {
  run diagram "
    local old = view
    stub.hotkeys['ctrl+cmd+shift+w']()
    stub.tick()
    stub.choose('清書')
    old:post({ png = 'data:image/png;base64,QUJD' })
    print(#stub.pasted)"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

# Resending the whole answer on every streamed piece grows with its square:
# a 50,000-character answer sent 313 MB to the page this way.
@test "streamed words go to the page one piece at a time, all of them once it is ready" {
  run drive "
    stub.hotkeys['ctrl+cmd+shift+d']()
    stub.tick()
    local view, task = stub.popups[#stub.popups], stub.tasks[#stub.tasks]
    task.stream(task, 'FIRST', '')
    view:post({ ready = true })
    print(stub.lastUpdate())
    task.stream(task, ' SECOND', '')
    print(stub.lastUpdate())
    task.done(0, '', '')
    print(stub.lastUpdate())"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *'FIRST'* ]]
  [[ "${lines[1]}" == *'SECOND'* && "${lines[1]}" != *'FIRST'* ]]
  [[ "${lines[2]}" == *'FIRST SECOND'*'"done"'* ]]
}

@test "a character split across two pieces reaches the page whole" {
  run drive "
    stub.hotkeys['ctrl+cmd+shift+d']()
    stub.tick()
    local view, task = stub.popups[#stub.popups], stub.tasks[#stub.tasks]
    task.stream(task, 'A', '')
    view:post({ ready = true })
    local sent = #view.updates
    local a = 'あ'
    task.stream(task, a:sub(1, 2), '')
    print(#view.updates - sent)
    task.stream(task, a:sub(3), '')
    print(stub.lastUpdate())"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = 0 ]
  [ "${lines[1]}" = 'append(...["あ"])' ]
}
