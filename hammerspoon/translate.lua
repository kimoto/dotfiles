-- DeepL's shortcuts, answered by translate.py (Claude) instead of the DeepL
-- app. Why, and the one-time setup: the header of translate.py.
-- NOTE: keybindings below are documented in KEYBINDINGS.md ("Translation") —
-- update it when they change.

local PYTHON = os.getenv("HOME") .. "/.local/share/desktop-translate/bin/python"
local SCRIPT = hs.configdir .. "/translate.py"
-- The second C must come within this many seconds to count as ⌘C+C.
local DOUBLE_PRESS = 0.5
-- The first ⌘C is a real copy; give the app time to fill the clipboard.
local CLIPBOARD_WAIT = 0.15
-- How long a sent ⌘C may take to reach the clipboard before "nothing was
-- selected" is the better guess than "the app is slow".
local COPY_TIMEOUT = 0.5
local POPUP_WIDTH = 440

local function escapeHtml(s)
   return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- DeepL's popup: the translation in a small window by the mouse, gone on Esc.
-- A global, so a second translation replaces the first instead of stacking.
translatePopup = nil
local function showPopup(text)
   if translatePopup then translatePopup:delete() end
   -- About 28 full-width characters fit on a line; a half-width one takes half.
   local lines = 1
   for line in (text .. "\n"):gmatch("([^\n]*)\n") do
      local ascii = select(2, line:gsub("[\1-\127]", ""))
      local width = (utf8.len(line) - ascii) + ascii / 2
      lines = lines + math.max(1, math.ceil(width / 28))
   end
   local height = math.min(600, 40 + lines * 20)
   local mouse = hs.mouse.absolutePosition()
   local frame = hs.mouse.getCurrentScreen():frame()
   local x = math.min(mouse.x, frame.x + frame.w - POPUP_WIDTH)
   local y = math.min(mouse.y + 16, frame.y + frame.h - height)
   translatePopup = hs.webview.new({ x = x, y = y, w = POPUP_WIDTH, h = height })
      :windowStyle({ "titled", "closable", "utility", "HUD" })
      :windowTitle("翻訳（コピー済み）")
      :closeOnEscape(true)
      :deleteOnClose(true)
      -- The webview paints white unless the page opts into dark mode, so the
      -- colours follow the system instead of being fixed to one of them.
      :html("<body style='color-scheme:light dark;font:14px -apple-system;white-space:pre-wrap;margin:12px'>"
         .. escapeHtml(text) .. "</body>")
      :show()
      :bringToFront(true)
end

-- The API round trip takes a few seconds, past the 1s a key press should
-- answer in, so say at once that it was heard and drop that when it ends.
local function run(args)
   local argv = { SCRIPT, "--quiet" }
   for _, a in ipairs(args) do table.insert(argv, a) end
   -- A non-number duration keeps the alert up until closeSpecific.
   local busy = hs.alert.show("翻訳中…", {}, hs.screen.mainScreen(), true)
   hs.task.new(PYTHON, function(code, stdout, stderr)
      hs.alert.closeSpecific(busy)
      if code == 0 and stdout ~= "" then
         showPopup((stdout:gsub("%s+$", "")))
      elseif stderr ~= "" then
         hs.alert.show(stderr)
      end
   end, argv):start()
end

local function chooseLanguageThen(args)
   local chooser = hs.chooser.new(function(choice)
      if not choice then return end
      local argv = { "--to", choice.lang }
      for _, a in ipairs(args) do table.insert(argv, a) end
      run(argv)
   end)
   chooser:choices({
      { text = "日本語へ", lang = "ja" },
      { text = "英語へ", lang = "en" },
   })
   chooser:show()
end

-- Copy the selection, then translate it. Waiting on the clipboard's change
-- count, not a fixed delay: with nothing selected ⌘C changes nothing, and
-- translating whatever was copied before would answer the wrong question.
-- A global: a timer only its own callback refers to can be collected.
translateCopyPoll = nil
local function translateSelection()
   local before = hs.pasteboard.changeCount()
   local deadline = hs.timer.secondsSinceEpoch() + COPY_TIMEOUT
   hs.eventtap.keyStroke({ "cmd" }, "c")
   if translateCopyPoll then translateCopyPoll:stop() end
   translateCopyPoll = hs.timer.doEvery(0.05, function()
      if hs.pasteboard.changeCount() ~= before then
         translateCopyPoll:stop()
         run({ "--clipboard" })
      elseif hs.timer.secondsSinceEpoch() > deadline then
         translateCopyPoll:stop()
         hs.alert.show("選択された文がありません")
      end
   end)
end

local lastCopy = 0
local C = hs.keycodes.map["c"]
local AUTOREPEAT = hs.eventtap.event.properties.keyboardEventAutorepeat

-- ⌘C+C is two presses of C with ⌘ held, which hs.hotkey cannot express, so
-- watch every keyDown and let it through untouched: the copy still happens.
-- A global, like the watchers in init.lua: a local would be collected.
translateCopyWatcher = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
   if e:getKeyCode() ~= C or e:getProperty(AUTOREPEAT) ~= 0 then return false end
   local flags = e:getFlags()
   if not flags.cmd or flags.alt or flags.ctrl then return false end

   local now = hs.timer.secondsSinceEpoch()
   if now - lastCopy < DOUBLE_PRESS then
      lastCopy = 0
      local shift = flags.shift
      hs.timer.doAfter(CLIPBOARD_WAIT, function()
         if shift then chooseLanguageThen({ "--clipboard" }) else run({ "--clipboard" }) end
      end)
   else
      lastCopy = now
   end
   return false
end)
translateCopyWatcher:start()

-- On release, not press, so the ⌘C sent does not land while D is still down.
hs.hotkey.bind({ "ctrl", "cmd", "shift" }, "d", nil, translateSelection)
hs.hotkey.bind({ "ctrl", "cmd", "shift" }, "l", function() run({ "--screen" }) end)
