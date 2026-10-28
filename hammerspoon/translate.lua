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
local POPUP_WIDTH = 520
-- Before the page reports its real height; it grows or shrinks at once.
local POPUP_START_HEIGHT = 120
local POPUP_MAX_HEIGHT = 640
-- The popup's title for each job; translate.py --rewrite is the one that
-- keeps the language and changes the voice.
local MODES = {
   translate = { title = "翻訳" },
   rewrite = { title = "文面" },
}

-- DeepL's popup: the translation in a card by the mouse, gone on Esc or ✕.
-- The page draws the whole window (no title bar), takes the text through
-- update(), and reports its own height so the window fits the text instead
-- of a guess at line wrapping.
local POPUP_HTML = [[
<!doctype html><html><head><meta charset="utf-8"><style>
:root { color-scheme: light dark; --bg: #fafafc; --fg: #1d1d1f; --muted: #6e6e73;
  --line: rgba(0,0,0,.1); --hover: rgba(0,0,0,.07); --ok: #248a3d; --err: #d70015; }
@media (prefers-color-scheme: dark) { :root { --bg: #26262a; --fg: #f5f5f7; --muted: #a1a1a6;
  --line: rgba(255,255,255,.12); --hover: rgba(255,255,255,.1); --ok: #30d158; --err: #ff6961; } }
html, body { margin: 0; background: transparent; }
.card { background: var(--bg); color: var(--fg); border: 1px solid var(--line); border-radius: 12px;
  overflow: hidden; font: 15px/1.65 -apple-system, "Hiragino Sans", sans-serif; }
header { display: flex; align-items: center; gap: 6px; padding: 6px 6px 6px 16px;
  border-bottom: 1px solid var(--line); -webkit-user-select: none; cursor: default; }
.title { font-weight: 600; font-size: 13px; }
.status { flex: 1; font-size: 12px; color: var(--muted); }
.status.busy::after { content: ""; display: inline-block; width: 9px; height: 9px; margin-left: 6px;
  vertical-align: -1px; border: 2px solid var(--muted); border-top-color: transparent; border-radius: 50%;
  animation: spin .8s linear infinite; }
.status.done { color: var(--ok); }
.status.error { color: var(--err); }
@keyframes spin { to { transform: rotate(360deg); } }
button { all: unset; width: 30px; height: 30px; border-radius: 7px; display: grid; place-items: center;
  color: var(--muted); cursor: pointer; }
button:hover { background: var(--hover); color: var(--fg); }
button svg { width: 16px; height: 16px; stroke: currentColor; stroke-width: 2; fill: none;
  stroke-linecap: round; stroke-linejoin: round; }
main { padding: 12px 18px 16px; white-space: pre-wrap; overflow-wrap: anywhere; overflow-y: auto;
  max-height: 560px; -webkit-user-select: text; cursor: text; }
main.error { color: var(--err); font-size: 13px; }
</style></head><body><div class="card">
<header>
  <span class="title">{{TITLE}}</span><span class="status busy" id="status"></span>
  <button id="copy" title="コピー"><svg viewBox="0 0 24 24"><rect x="9" y="9" width="11" height="11" rx="2"/>
    <path d="M5 15V6a2 2 0 0 1 2-2h8"/></svg></button>
  <button id="close" title="閉じる（Esc）"><svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18"/></svg></button>
</header>
<main id="text"></main>
</div><script>
const post = (m) => window.webkit.messageHandlers.translate.postMessage(m);
const fit = () => post({ height: Math.ceil(document.querySelector('.card').getBoundingClientRect().height) });
function update(text, status, kind) {
  const t = document.getElementById('text');
  t.textContent = text;
  t.className = kind === 'error' ? 'error' : '';
  const s = document.getElementById('status');
  s.textContent = status;
  s.className = 'status ' + kind;
  fit();
}
document.getElementById('close').onclick = () => post({ close: true });
document.getElementById('copy').onclick = () => post({ copy: true });
post({ ready: true });
</script></body></html>
]]

-- The one popup on screen; a second translation replaces the first.
-- Globals, like the watchers in init.lua: a local would be collected.
translatePopup = nil
translatePopupEsc = nil
local popup = { text = "", status = "", kind = "", ready = false }

local function closePopup()
   if translatePopupEsc then translatePopupEsc:stop() end
   if translatePopup then translatePopup:delete() end
   translatePopupEsc, translatePopup = nil, nil
end

local function renderPopup()
   if not (translatePopup and popup.ready) then return end
   translatePopup:evaluateJavaScript("update(..." .. hs.json.encode({ popup.text, popup.status, popup.kind }) .. ")")
end

local function setPopup(text, status, kind)
   popup.text, popup.status, popup.kind = text, status, kind
   renderPopup()
end

local function fitPopup(height)
   local f = translatePopup:frame()
   local screen = hs.screen.find(f) or hs.mouse.getCurrentScreen()
   local bottom = screen:frame().y + screen:frame().h
   f.h = math.min(POPUP_MAX_HEIGHT, height)
   f.y = math.min(f.y, bottom - f.h)
   translatePopup:frame(f)
end

local function openPopup(mode)
   closePopup()
   popup = { text = "", status = "", kind = "busy", ready = false }
   local content = hs.webview.usercontent.new("translate"):setCallback(function(msg)
      local body = msg.body
      if not translatePopup then return end
      if body.ready then
         popup.ready = true
         renderPopup()
      elseif body.height then
         fitPopup(body.height)
      elseif body.copy then
         hs.pasteboard.setContents(popup.text)
         setPopup(popup.text, "コピーしました", "done")
      elseif body.close then
         closePopup()
      end
   end)
   local mouse = hs.mouse.absolutePosition()
   -- No screen under the mouse right after a display is unplugged.
   local frame = (hs.mouse.getCurrentScreen() or hs.screen.mainScreen()):frame()
   local x = math.max(frame.x, math.min(mouse.x, frame.x + frame.w - POPUP_WIDTH))
   local y = math.min(mouse.y + 16, frame.y + frame.h - POPUP_START_HEIGHT)
   translatePopup = hs.webview.new({ x = x, y = y, w = POPUP_WIDTH, h = POPUP_START_HEIGHT }, {}, content)
      :windowStyle({ "borderless", "nonactivating" })
      :transparent(true)
      :shadow(true)
      :level(hs.drawing.windowLevels.floating)
      :html((POPUP_HTML:gsub("{{TITLE}}", mode.title)))
      :show()
   -- Borderless windows never get key focus, so Esc is watched globally while
   -- the popup is up, and still let through: the app in front (nvim, a
   -- screen selection) keeps its own Esc.
   translatePopupEsc = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
      -- Closed after the key has gone on: deleting the window while the event
      -- is still being delivered loses it for the app in front.
      if e:getKeyCode() == hs.keycodes.map.escape then hs.timer.doAfter(0, closePopup) end
      return false
   end):start()
end

-- The API round trip takes a second or two, past the 1s a key press should
-- answer in: the popup opens at once with only a spinner, and the words are
-- added as they arrive. A screen selection is the exception: a popup opened
-- first would land in the region being captured, so an alert says the key was
-- heard and the popup waits for the first words. A failure always lands in
-- the popup, so "nothing happened" cannot be mistaken for "still working".
translateTask = nil
local runs = 0
local function run(args, mode)
   mode = mode or MODES.translate
   local argv = { SCRIPT, "--quiet" }
   for _, a in ipairs(args) do table.insert(argv, a) end
   if translateTask and translateTask:isRunning() then translateTask:terminate() end
   runs = runs + 1
   local id = runs
   local busy
   if args[1] == "--screen" then
      -- A non-number duration keeps the alert up until closeSpecific.
      busy = hs.alert.show("翻訳中…", {}, hs.screen.mainScreen(), true)
   else
      openPopup(mode)
   end
   local out, err = "", ""
   local function popupOpened()
      if busy then
         hs.alert.closeSpecific(busy)
         busy = nil
         openPopup(mode)
      end
   end
   translateTask = hs.task.new(PYTHON, function(code, stdout, stderr)
      if id ~= runs then  -- replaced by a newer translation
         if busy then hs.alert.closeSpecific(busy) end
         return
      end
      out, err = out .. stdout, err .. stderr
      local text = out:gsub("%s+$", "")
      if code == 0 and text == "" and busy then
         hs.alert.closeSpecific(busy)  -- the screen selection was cancelled
         return
      end
      popupOpened()
      if code == 0 then
         setPopup(text, "コピー済み", "done")
      else
         local reason = err:gsub("%s+$", "")
         if reason == "" then reason = "translate.py が出力なしで終了しました。" end
         setPopup((text ~= "" and text .. "\n\n" or "") .. reason, "失敗（終了コード " .. code .. "）", "error")
      end
   end, function(_, stdout, stderr)
      if id ~= runs then return false end
      out, err = out .. (stdout or ""), err .. (stderr or "")
      if out:find("%S") then
         popupOpened()
         setPopup(out, "", "busy")
      end
      return true
   end, argv)
   translateTask:start()
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
local function translateSelection(args, mode)
   local before = hs.pasteboard.changeCount()
   local deadline = hs.timer.secondsSinceEpoch() + COPY_TIMEOUT
   hs.eventtap.keyStroke({ "cmd" }, "c")
   if translateCopyPoll then translateCopyPoll:stop() end
   translateCopyPoll = hs.timer.doEvery(0.05, function()
      if hs.pasteboard.changeCount() ~= before then
         translateCopyPoll:stop()
         run(args or { "--clipboard" }, mode)
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
hs.hotkey.bind({ "ctrl", "cmd", "shift" }, "d", nil, function() translateSelection() end)
-- Rough notes selected in a message box → the same notes as a message in the
-- user's own voice (the style file: translate.py's header).
hs.hotkey.bind({ "ctrl", "cmd", "shift" }, "w", nil, function()
   translateSelection({ "--rewrite", "--clipboard" }, MODES.rewrite)
end)
-- screencapture runs as Hammerspoon's child and needs its permission; say so
-- up front rather than after a selection that cannot come back with anything.
hs.hotkey.bind({ "ctrl", "cmd", "shift" }, "l", function()
   if not hs.screenRecordingState() then
      openPopup(MODES.translate)
      setPopup("Hammerspoon に「画面収録」の許可がありません。\n"
         .. "システム設定 → プライバシーとセキュリティ → 画面収録 で許可し、Hammerspoon を再起動してください。",
         "画面を撮れません", "error")
      return
   end
   run({ "--screen" })
end)
