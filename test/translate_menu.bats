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
    hs.configdir = '$REPO_ROOT/hammerspoon'  -- translate.lua reads markdown.js from it
    dofile('$REPO_ROOT/hammerspoon/translate.lua')
    $1"
}

# Presses ⌃⌘⇧W, lets the copy land, picks the row, and prints the job sent to
# translate.py.
pick() {
  drive "
    stub.hotkeys['ctrl+cmd+shift+w']()
    assert(#stub.choosers == 0, 'menu opened before the copy landed')
    stub.tick()
    stub.choose('$1')
    print(stub.sent(stub.tasks[#stub.tasks]))"
}

@test "⌃⌘⇧W copies the selection, then opens the menu" {
  run drive "
    stub.hotkeys['ctrl+cmd+shift+w']()
    print(table.concat(stub.keystrokes, ','), #stub.choosers)
    stub.tick()
    print(#stub.choosers)"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf 'cmd+c\t0')" ]
  [ "${lines[1]}" = "1" ]
}

@test "translate.py starts getting ready at the key press, and gets its job from the menu in a file of the user's" {
  run drive "
    -- The script polls for the job's name, so the job must never be written
    -- under it: a read between two writes would take half a job.
    local open, written = io.open, {}
    io.open = function(path, how) if how == 'w' then written[path] = true end return open(path, how) end
    stub.hotkeys['ctrl+cmd+shift+w']()
    local task = stub.tasks[1]
    print(#stub.tasks, task.argv[2], tostring(stub.sent(task)))
    stub.tick()
    stub.choose('要約')
    local own = task.argv[3]:find(os.getenv('BATS_TEST_TMPDIR'), 1, true) == 1
    print(#stub.tasks, stub.sent(task), tostring(own), tostring(io.open(task.argv[3] .. '.part')))
    assert(not written[task.argv[3]], 'job written in place')"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf '1\t--wait\tnil')" ]
  [ "${lines[1]}" = "$(printf '1\t--quiet --summarize --clipboard\ttrue\tnil')" ]
}

@test "translate.py dying before its job still ends in its reason, not a spinner" {
  run drive "
    stub.hotkeys['ctrl+cmd+shift+w']()
    stub.tasks[1].done(1, '', 'No module named anthropic')
    stub.tick()
    stub.choose('要約')
    stub.popups[#stub.popups]:post({ ready = true })
    print(stub.lastUpdate())"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No module named anthropic"*"error"* ]]
}

@test "a translator that cannot start ends in its reason, not a spinner" {
  run drive "
    local new = hs.task.new
    hs.task.new = function(...)
      local t = new(...)
      function t:start() return false end
      return t
    end
    stub.hotkeys['ctrl+cmd+shift+w']()
    stub.tick()
    stub.choose('要約')
    stub.popups[#stub.popups]:post({ ready = true })
    print(stub.lastUpdate(), tostring(stub.sent(stub.tasks[1])))"
  [ "$status" -eq 0 ]
  [[ "$output" == *"を起動できません"*"error"*"nil" ]]
}

@test "the waiting translate.py is ended when the menu is dismissed or nothing was selected" {
  run drive "
    stub.hotkeys['ctrl+cmd+shift+w']()
    stub.tick()
    stub.choosers[1].callback(nil)
    print(tostring(stub.tasks[1].terminated), tostring(stub.sent(stub.tasks[1])))
    hs.eventtap.keyStroke = function() end  -- the app copies nothing
    stub.hotkeys['ctrl+cmd+shift+d']()
    hs.timer.secondsSinceEpoch = function() return 10 end
    stub.tick()
    print(tostring(stub.tasks[2].terminated), tostring(stub.sent(stub.tasks[2])))"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf 'true\tnil')" ]
  [ "${lines[1]}" = "$(printf 'true\tnil')" ]
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
    print(#stub.choosers, stub.sent(stub.tasks[1]))"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '0\t--quiet --clipboard')" ]
}

# A faster model's answer can be redone on the default one; by then the
# clipboard holds that answer, so the retry carries the text that was copied.
@test "an answer from a faster model offers a retry on the default model, with the original text" {
  run drive "
    stub.hotkeys['ctrl+cmd+shift+w']()
    stub.tick()
    stub.choose('要約')
    local view, task = stub.popups[#stub.popups], stub.tasks[#stub.tasks]
    view:post({ ready = true })
    stub.clipboard = 'the summary'
    task.done(0, 'the summary', '@fast-model claude-haiku-5-5\\n')
    print(stub.lastUpdate())
    view:post({ best = true })
    print(#stub.tasks, stub.sent(stub.tasks[#stub.tasks]))"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"haiku-5-5"*'"done",false,true])' ]]
  [ "${lines[1]}" = "$(printf '2\t--quiet --summarize --best -- the copied text')" ]
}

@test "an answer from the default model offers no retry" {
  run drive "
    stub.hotkeys['ctrl+cmd+shift+w']()
    stub.tick()
    stub.choose('清書')
    local view, task = stub.popups[#stub.popups], stub.tasks[#stub.tasks]
    view:post({ ready = true })
    task.done(0, 'the message', '')
    view:post({ best = true })
    print(stub.lastUpdate(), #stub.tasks)"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"done",false,false])'*"$(printf '\t1')" ]]
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
  [[ "$output" == *'<svg'*'"busy",true,false])' ]]
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

@test "a summary is copied as rich and plain text, or with ⌥ as the Markdown it came as" {
  run drive "
    stub.hotkeys['ctrl+cmd+shift+w']()
    stub.tick()
    stub.choose('要約')
    local view, task = stub.popups[#stub.popups], stub.tasks[#stub.tasks]
    view:post({ ready = true })
    task.done(0, '- **A**', '')
    view:post({ copy = true, text = '・A', html = '<ul><li><strong>A</strong></li></ul>' })
    local rich = stub.pasted[#stub.pasted]
    print(rich['public.utf8-plain-text'], rich['public.html'])
    view:post({ copy = true, markdown = true })
    print(stub.pasted[#stub.pasted], view.page:match('const markdown = (%a+)'))"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = $'・A\t<meta charset="utf-8"><ul><li><strong>A</strong></li></ul>' ]
  [ "${lines[1]}" = $'- **A**\ttrue' ]
}

@test "the page's own copy of a finished summary replaces the Markdown, and keeps the status" {
  run drive "
    stub.hotkeys['ctrl+cmd+shift+w']()
    stub.tick()
    stub.choose('要約')
    local view, task = stub.popups[#stub.popups], stub.tasks[#stub.tasks]
    view:post({ ready = true })
    task.done(0, '- **A**', '')
    local before = #view.updates
    view:post({ copy = true, auto = true, text = '・A', html = '<ul><li>A</li></ul>' })
    print(stub.pasted[#stub.pasted]['public.utf8-plain-text'], #view.updates - before)"
  [ "$status" -eq 0 ]
  [ "$output" = $'・A\t0' ]
}

# By the time a tab is clicked the clipboard holds the first answer, so the
# rerun carries the text that was copied.
@test "a tab reruns the copied text as another job, where the popup already is" {
  run drive "
    stub.hotkeys['ctrl+cmd+shift+d']()
    stub.tick()
    local view, task = stub.popups[#stub.popups], stub.tasks[#stub.tasks]
    view:post({ ready = true })
    stub.clipboard = 'the translation'
    task.done(0, 'the translation', '')
    view.rect = { x = 300, y = 400, w = 520, h = 200 }
    view:post({ job = 'summarize' })
    local now = stub.popups[#stub.popups]
    print(stub.sent(stub.tasks[#stub.tasks]))
    print(now.page:match('class=\"title\">([^<]*)<'), now.rect.x, now.rect.y, view.deleted)"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "--quiet --summarize -- the copied text" ]
  [ "${lines[1]}" = $'要約\t300\t400\ttrue' ]
}

@test "a retry after a tab names the text once" {
  run drive "
    stub.hotkeys['ctrl+cmd+shift+d']()
    stub.tick()
    local view = stub.popups[#stub.popups]
    view:post({ ready = true })
    view:post({ job = 'summarize' })
    view = stub.popups[#stub.popups]
    view:post({ ready = true })
    stub.tasks[#stub.tasks].done(0, 'the summary', '@fast-model claude-haiku-5-5\\n')
    view:post({ best = true })
    print(stub.sent(stub.tasks[#stub.tasks]))"
  [ "$status" -eq 0 ]
  [ "$output" = "--quiet --summarize --best -- the copied text" ]
}

@test "a popup with text to rerun has the tabs, a screen region's has none" {
  run drive "
    stub.hotkeys['ctrl+cmd+shift+d']()
    stub.tick()
    print(stub.popups[#stub.popups].page:match('const tabs = (%S+);'))"
  [ "$status" -eq 0 ]
  [[ "$output" == '[["rewrite","清書"],'*'["translate","翻訳"]]' ]]
  run drive "
    hs.screenRecordingState = function() return true end
    stub.hotkeys['ctrl+cmd+shift+l']()
    stub.tasks[#stub.tasks].done(0, 'the translation', '')
    print(stub.popups[#stub.popups].page:match('const tabs = (%S+);'))"
  [ "$status" -eq 0 ]
  [ "$output" = null ]
}

@test "a translation is not rendered, so its own marks stay as they are" {
  run drive "
    stub.hotkeys['ctrl+cmd+shift+d']()
    stub.tick()
    print(stub.popups[#stub.popups].page:match('const markdown = (%a+)'))"
  [ "$status" -eq 0 ]
  [ "$output" = false ]
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
