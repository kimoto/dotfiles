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
-- The popup's title for each job. Every job but translate keeps the text's
-- language; translate.py's TASKS says what each one asks for. A rewrite can be
-- edited in the popup, and the edit is what translate.py learns the user's
-- preferences from. A reply or a summary is asked for in light Markdown,
-- shown rendered and copied as rich text; a translation or a proofread keeps
-- the text's own marks, which must not turn bold.
local MODES = {
   translate = { title = "翻訳", editable = false },
   rewrite = { title = "清書", editable = true },
   reply = { title = "返信案", editable = false, markdown = true },
   summarize = { title = "要約", editable = false, markdown = true },
   proofread = { title = "誤字チェック", editable = false },
   -- The answer is an SVG: shown as an image and copied as a PNG, never as text.
   diagram = { title = "図解", editable = false, svg = true },
}
for job, mode in pairs(MODES) do mode.job = job end
-- The popup's tabs, in the menu's order: a wrong job is one click from the
-- right one, on the same text.
local TABS = { "rewrite", "reply", "summarize", "proofread", "diagram", "translate" }

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
button[hidden] { display: none; }  /* display: grid above would otherwise win */
button svg { width: 16px; height: 16px; stroke: currentColor; stroke-width: 2; fill: none;
  stroke-linecap: round; stroke-linejoin: round; }
main { padding: 12px 18px 16px; white-space: pre-wrap; overflow-wrap: anywhere; overflow-y: auto;
  max-height: 560px; -webkit-user-select: text; cursor: text; }
main.error { color: var(--err); font-size: 13px; }
main img { display: block; max-width: 100%; height: auto; border-radius: 6px; }
main.markdown { white-space: normal; }
main.markdown p, main.markdown ul, main.markdown ol, main.markdown pre { margin: 0 0 8px; }
main.markdown > :last-child { margin-bottom: 0; }
main.markdown ul, main.markdown ol { list-style: none; padding: 0; }
main.markdown li { padding-left: 1em; text-indent: -1em; }  /* a wrapped line starts under the text */
main.markdown .mark { color: var(--muted); }
main.markdown code, main.markdown pre { font: 13px ui-monospace, Menlo, monospace; background: var(--hover);
  border-radius: 4px; }
main.markdown code { padding: 1px 4px; }
main.markdown pre { padding: 8px 10px; white-space: pre-wrap; }
main.markdown pre code { padding: 0; background: none; }
main[contenteditable="plaintext-only"] { outline: none; }
main[contenteditable="plaintext-only"]:focus { background: var(--hover); }
nav { display: flex; gap: 2px; padding: 4px 10px; border-bottom: 1px solid var(--line); -webkit-user-select: none; }
nav[hidden] { display: none; }
nav button { width: auto; height: 24px; padding: 0 8px; font-size: 12px; }
nav button.current { background: var(--hover); color: var(--fg); font-weight: 600; cursor: default; }
</style></head><body><div class="card">
<header>
  <span class="title">{{TITLE}}</span><span class="status busy" id="status"></span>
  <button id="best" title="標準のモデルでやり直す" hidden><svg viewBox="0 0 24 24"><path d="M20 12a8 8 0 1 1-2.3-5.6"/>
    <path d="M20 4v5h-5"/></svg></button>
  <button id="copy" title="コピー"><svg viewBox="0 0 24 24"><rect x="9" y="9" width="11" height="11" rx="2"/>
    <path d="M5 15V6a2 2 0 0 1 2-2h8"/></svg></button>
  <button id="close" title="閉じる（Esc）"><svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18"/></svg></button>
</header>
<nav id="tabs" hidden></nav>
<main id="text"></main>
</div><script>
const post = (m) => window.webkit.messageHandlers.translate.postMessage(m);
const fit = () => post({ height: Math.ceil(document.querySelector('.card').getBoundingClientRect().height) });
// [[job, title], ...], or null when there is no text to run another job on.
const tabs = {{TABS}};
if (tabs) {
  const nav = document.getElementById('tabs');
  for (const [job, title] of tabs) {
    const b = document.createElement('button');
    b.textContent = title;
    if (title === '{{TITLE}}') b.className = 'current';
    else b.onclick = () => post({ job });
    nav.append(b);
  }
  nav.hidden = false;
}
const editable = {{EDITABLE}};
const markdown = {{MARKDOWN}};
{{MARKDOWN_JS}}
const t = document.getElementById('text');
t.oninput = fit;
// The answer as it came, rendered again whole as each piece arrives.
let raw = '';
let autoCopied = null;
function show(kind) {
  if (markdown && kind !== 'error') { t.classList.add('markdown'); t.innerHTML = renderMarkdown(raw); }
  else t.textContent = raw;
}
// An SVG goes in as an <img>, where its own scripts cannot run, and comes back
// as a PNG: Slack pastes an image, not SVG markup. Drawn once per SVG, so
// the status update that follows the PNG does not draw it again.
let shownSvg = null;
function showSvg(t, svg) {
  if (svg === shownSvg) return;
  shownSvg = svg;
  const img = new Image();
  // Markup that does not parse (an unescaped & in a label) never loads, and a
  // canvas WebKit taints cannot be read: both say so instead of spinning on.
  img.onerror = () => post({ svgError: true });
  img.onload = () => {
    fit();
    try {
      const c = document.createElement('canvas');
      c.width = img.naturalWidth * 2;
      c.height = img.naturalHeight * 2;
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      post({ png: c.toDataURL('image/png') });
    } catch (e) {
      post({ svgError: true });
    }
  };
  img.src = 'data:image/svg+xml;base64,' + btoa(unescape(encodeURIComponent(svg)));
  t.replaceChildren(img);
}
function update(text, status, kind, svg, retry) {
  t.className = kind === 'error' ? 'error' : '';
  if (svg && text) showSvg(t, text); else { shownSvg = null; raw = text; show(kind); }
  // translate.py copied the Markdown; a finished answer is copied again as it
  // is shown, once: the status updates after a copy come back here too.
  if (markdown && kind === 'done' && autoCopied !== raw) { autoCopied = raw; copyRendered(true); }
  document.getElementById('best').hidden = !retry;
  // Only a finished answer: an edit mid-stream would be overwritten by the next words.
  t.contentEditable = editable && kind === 'done' ? 'plaintext-only' : 'false';
  const s = document.getElementById('status');
  s.textContent = status;
  s.className = 'status ' + kind;
  fit();
}
// A streamed piece is added to what is shown, not sent again with all before it.
function append(text) {
  raw += text;
  if (markdown) show('busy'); else t.insertAdjacentText('beforeend', text);
  fit();
}
// Rendered: the plain text (・ bullets) and the rich text (real bullets, the
// ・ dropped), or with ⌥ the Markdown as it came.
const copy = document.getElementById('copy');
if (markdown) copy.title = 'コピー（⌥ クリックで Markdown のまま）';
function copyRendered(auto) {
  const rich = t.cloneNode(true);
  rich.querySelectorAll('.mark').forEach((m) => m.remove());
  post({ copy: true, auto, text: t.innerText, html: rich.innerHTML });
}
copy.onclick = (e) => {
  if (!markdown || t.className === 'error') return post({ copy: true, text: t.innerText });
  if (e.altKey) return post({ copy: true, markdown: true });
  copyRendered(false);
};
document.getElementById('close').onclick = () => post({ close: true });
document.getElementById('best').onclick = () => post({ best: true });
post({ ready: true });
</script></body></html>
]]

local MARKDOWN_JS = (function()
   local f = assert(io.open(hs.configdir .. "/markdown.js"))
   local js = f:read("a")
   f:close()
   return js
end)()

-- The one popup on screen; a second translation replaces the first.
-- Globals, like the watchers in init.lua: a local would be collected.
translatePopup = nil
translatePopupEsc = nil
local popup = { text = "", status = "", kind = "", svg = false, ready = false }

local function closePopup()
   if translatePopupEsc then translatePopupEsc:stop() end
   if translatePopup then translatePopup:delete() end
   translatePopupEsc, translatePopup = nil, nil
end

local function renderPopup()
   if not (translatePopup and popup.ready) then return end
   translatePopup:evaluateJavaScript("update(..."
      .. hs.json.encode({ popup.text, popup.status, popup.kind, popup.svg, popup.retry ~= nil }) .. ")")
end

local function setPopup(text, status, kind, svg)
   popup.text, popup.status, popup.kind, popup.svg = text, status, kind, svg or false
   renderPopup()
end

-- Where the complete UTF-8 characters at the start of `s` end: a piece of
-- output can stop inside a character, and hs.json.encode cannot take half of
-- one.
local function completeUtf8(s)
   for back = 1, math.min(3, #s) do
      local byte = s:byte(#s - back + 1)
      if byte >= 0xC0 then  -- the lead byte of the last character
         local size = byte >= 0xF0 and 4 or byte >= 0xE0 and 3 or 2
         return size > back and #s - back or #s
      elseif byte < 0x80 then
         return #s
      end
   end
   return #s
end

-- A page not ready yet gets it with the rest in the update() sent on ready.
-- Bytes of a character still arriving wait for the piece that finishes it.
local function appendPopup(text)
   popup.text = popup.text .. text
   local held = (popup.held or "") .. text
   local cut = completeUtf8(held)
   popup.held = held:sub(cut + 1)
   if cut == 0 or not (translatePopup and popup.ready) then return end
   translatePopup:evaluateJavaScript("append(..." .. hs.json.encode({ held:sub(1, cut) }) .. ")")
end

-- The pasteboard takes an image object, not a data URL, so the PNG goes
-- through a file. The file stays until the pasteboard has it: imageFromPath
-- reads it lazily. In the user's own temp dir, not os.tmpname()'s /tmp: there
-- another account can plant a symlink at the .png name before io.open follows
-- it. The .png suffix is what NSImage tells the type by.
local function copyPng(dataUrl)
   local data = hs.base64.decode((dataUrl:gsub("^data:image/png;base64,", "")))
   if not data or data == "" then return false end
   local path = (hs.fs.temporaryDirectory():gsub("/$", "")) .. "/desktop-translate-diagram.png"
   local f = assert(io.open(path, "wb"))
   f:write(data)
   f:close()
   local image = hs.image.imageFromPath(path)
   local ok = image ~= nil and hs.pasteboard.writeObjects(image)
   os.remove(path)
   return ok
end

local function fitPopup(height)
   local f = translatePopup:frame()
   local screen = hs.screen.find(f) or hs.mouse.getCurrentScreen()
   local bottom = screen:frame().y + screen:frame().h
   f.h = math.min(POPUP_MAX_HEIGHT, height)
   f.y = math.min(f.y, bottom - f.h)
   translatePopup:frame(f)
end

-- Global, like translateTask below: a task nothing else refers to can be
-- collected before it has read its input.
translateEditTask = nil
local function recordEdit(text)
   translateEditTask = hs.task.new(PYTHON, nil, { SCRIPT, "--record-edit" })
   if not translateEditTask then return end
   -- Input first: given after start(), it never reaches the child's stdin.
   translateEditTask:setInput(text)
   if translateEditTask:start() then translateEditTask:closeInput() end
end

local run  -- below; the popup's retry button and tabs start it again

-- The arguments that run `job` on `source` itself, not on the clipboard: by
-- the time a tab is clicked, the clipboard holds the first answer.
local function jobArgs(job, source)
   local args = {}
   if job ~= "translate" then table.insert(args, "--" .. job) end
   table.insert(args, "--")  -- text that starts with "-" is still text
   table.insert(args, source)
   return args
end

-- `source` is the text the job ran on, for the tabs; nil (a screen region)
-- shows none. `at` is the popup being replaced, so a tab or the retry does not
-- move it to wherever the mouse has gone since.
local function openPopup(mode, source, at)
   closePopup()
   popup = { text = "", status = "", kind = "busy", svg = false, ready = false }
   -- Set once this popup's window exists: a message still in flight from the
   -- one it replaced must not write into this one.
   local view
   local content = hs.webview.usercontent.new("translate"):setCallback(function(msg)
      local body = msg.body
      if not translatePopup or translatePopup ~= view then return end
      if body.ready then
         popup.ready = true
         renderPopup()
      elseif body.height then
         fitPopup(body.height)
      elseif body.png then
         popup.png = body.png
         if copyPng(body.png) then
            setPopup(popup.text, "画像をコピー済み", "done", true)
         else
            setPopup(popup.text, "画像をコピーできませんでした", "error", true)
         end
      elseif body.svgError then
         setPopup("図を表示できませんでした（返ってきた SVG が壊れています）。", "失敗", "error")
      elseif body.copy then
         if popup.svg then
            if popup.png and copyPng(popup.png) then
               setPopup(popup.text, "画像をコピーしました", "done", true)
            else
               setPopup(popup.text, "画像をコピーできませんでした", "error", true)
            end
            return
         end
         if body.markdown then
            hs.pasteboard.setContents(popup.text)
            setPopup(popup.text, "Markdown でコピーしました", "done")
            return
         end
         -- An editable page hands back a trailing newline the draft never had.
         local text = (body.text or popup.text):gsub("%s+$", "")
         if body.html then
            -- The charset is what keeps Japanese from pasting as mojibake.
            hs.pasteboard.writeAllData({
               ["public.html"] = '<meta charset="utf-8">' .. body.html,
               ["public.utf8-plain-text"] = text,
            })
         else
            hs.pasteboard.setContents(text)
         end
         if body.auto then return end  -- the status already says コピー済み
         local edited = mode.editable and popup.kind == "done" and text ~= popup.text
         if edited then recordEdit(text) end
         -- A rendered answer keeps its Markdown, which the plain text lost.
         setPopup(mode.markdown and popup.text or text,
            edited and "直しを記録してコピーしました" or "コピーしました", "done")
      elseif body.best then
         if popup.retry then run(popup.retry, mode, nil, translatePopup:frame()) end
      elseif body.job then
         if source and MODES[body.job] then
            run(jobArgs(body.job, source), MODES[body.job], nil, translatePopup:frame())
         end
      elseif body.close then
         closePopup()
      end
   end)
   local x, y
   if at then
      x, y = at.x, at.y
   else
      local mouse = hs.mouse.absolutePosition()
      -- No screen under the mouse right after a display is unplugged.
      local frame = (hs.mouse.getCurrentScreen() or hs.screen.mainScreen()):frame()
      x = math.max(frame.x, math.min(mouse.x, frame.x + frame.w - POPUP_WIDTH))
      y = math.min(mouse.y + 16, frame.y + frame.h - POPUP_START_HEIGHT)
   end
   local tabs = "null"
   if source then
      local list = {}
      for i, job in ipairs(TABS) do list[i] = { job, MODES[job].title } end
      tabs = hs.json.encode(list)
   end
   translatePopup = hs.webview.new({ x = x, y = y, w = POPUP_WIDTH, h = POPUP_START_HEIGHT }, {}, content)
      :windowStyle({ "borderless", "nonactivating" })
      -- Lets a click give the popup the keyboard, so a rewrite can be edited.
      :allowTextEntry(mode.editable)
      :transparent(true)
      :shadow(true)
      :level(hs.drawing.windowLevels.floating)
      :html((POPUP_HTML:gsub("{{TITLE}}", mode.title):gsub("{{EDITABLE}}", tostring(mode.editable))
         :gsub("{{MARKDOWN}}", tostring(mode.markdown == true))
         :gsub("{{TABS}}", function() return tabs end)
         :gsub("{{MARKDOWN_JS}}", function() return MARKDOWN_JS end)))
      :show()
   view = translatePopup
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

-- translate.py --wait, started at the key press: loading the SDK and reading
-- the key take a few tenths of a second, spent while the copy lands and the
-- menu is open instead of after. It sends nothing until run() gives it a job;
-- cancel() ends it when no job comes. An exit before the job (Python itself
-- broken) is kept for run() to show, or the popup would spin forever. The job
-- goes through a file in the user's own temp dir: input given to a task
-- already started never reaches it.
local prepared = 0
local function prepare()
   prepared = prepared + 1
   local job = string.format("%sdesktop-translate-job-%d-%d.json", hs.fs.temporaryDirectory(), os.time(), prepared)
   local handlers = {}
   local task = hs.task.new(PYTHON, function(...)
      if handlers.done then handlers.done(...) else handlers.exited = { ... } end
   end, function(...)
      if handlers.stream then return handlers.stream(...) end
      return true
   end, { SCRIPT, "--wait", job })
   local started = task and task:start()
   return {
      task = task,
      job = job,
      handlers = handlers,
      started = started,
      cancel = function() if started then task:terminate() end end,
   }
end

-- The same job on the default model, given the text itself: by then the
-- clipboard holds the first answer, not what was asked about.
local function bestRetry(args, source)
   local retry = {}
   for _, a in ipairs(args) do
      if a == "--" then break end  -- the text itself, from a tab: added back below
      if a ~= "--clipboard" then table.insert(retry, a) end
   end
   table.insert(retry, "--best")
   table.insert(retry, "--")  -- text that starts with "-" is still text
   table.insert(retry, source)
   return retry
end

function run(args, mode, ready, at)
   mode = mode or MODES.translate
   ready = ready or prepare()
   local source
   for i, a in ipairs(args) do
      if a == "--clipboard" then source = hs.pasteboard.getContents() end
      if a == "--" then source = args[i + 1] end
   end
   local argv = { "--quiet" }
   for _, a in ipairs(args) do table.insert(argv, a) end
   if translateTask and translateTask ~= ready.task and translateTask:isRunning() then
      translateTask:terminate()
   end
   runs = runs + 1
   local id = runs
   local busy
   if args[1] == "--screen" then
      -- A non-number duration keeps the alert up until closeSpecific.
      busy = hs.alert.show("翻訳中…", {}, hs.screen.mainScreen(), true)
   else
      openPopup(mode, source, at)
   end
   local out, err = "", ""
   local streaming = false  -- the popup shows out so far, and takes the rest by appendPopup
   local function popupOpened()
      if busy then
         hs.alert.closeSpecific(busy)
         busy = nil
         openPopup(mode, source, at)
      end
   end
   ready.handlers.done = function(code, stdout, stderr)
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
      if code == 0 and mode.svg then
         setPopup(text, "", "busy", true)  -- done once the PNG is copied
      elseif code == 0 then
         -- Matches FAST_MODEL_MARK in translate.py.
         local fast = err:match("@fast%-model (%S+)")
         if fast and source then popup.retry = bestRetry(args, source) end
         setPopup(text, fast and "コピー済み（" .. fast:gsub("^claude%-", "") .. "）" or "コピー済み", "done")
      else
         local reason = err:gsub("%s+$", "")
         if reason == "" then reason = "translate.py が出力なしで終了しました。" end
         -- Half an SVG is markup, not a reason; only the reason is shown.
         if mode.svg then text = "" end
         setPopup((text ~= "" and text .. "\n\n" or "") .. reason, "失敗（終了コード " .. code .. "）", "error")
      end
   end
   ready.handlers.stream = function(_, stdout, stderr)
      if id ~= runs then return false end
      out, err = out .. (stdout or ""), err .. (stderr or "")
      -- An SVG half written is only markup: the spinner stays until it is done.
      if streaming then
         appendPopup(stdout or "")
      elseif out:find("%S") and not mode.svg then
         popupOpened()
         setPopup(out, "", "busy")
         streaming = true
      end
      return true
   end
   translateTask = ready.task
   -- A missing venv never calls back, so the spinner would turn for good.
   if not ready.started then
      popupOpened()
      setPopup(PYTHON .. " を起動できません。\n準備の手順は translate.py の先頭にあります。",
         "起動できません", "error")
      return
   end
   local exited = ready.handlers.exited
   if exited then return ready.handlers.done(exited[1], exited[2], exited[3]) end
   -- Renamed into place, so the waiting translate.py never reads half of it.
   local f = io.open(ready.job .. ".part", "w")
   if not (f and f:write(hs.json.encode(argv)) and f:close() and os.rename(ready.job .. ".part", ready.job)) then
      ready.cancel()
      setPopup("translate.py に仕事を渡せませんでした（" .. ready.job .. "）。", "失敗", "error")
   end
end

local function chooseLanguageThen(args, ready)
   local chooser = hs.chooser.new(function(choice)
      if not choice then return ready.cancel() end
      local argv = { "--to", choice.lang }
      for _, a in ipairs(args) do table.insert(argv, a) end
      run(argv, nil, ready)
   end)
   chooser:choices({
      { text = "日本語へ", lang = "ja" },
      { text = "英語へ", lang = "en" },
   })
   chooser:show()
end

-- Copy the selection, then hand it on. Waiting on the clipboard's change
-- count, not a fixed delay: with nothing selected ⌘C changes nothing, and
-- working on whatever was copied before would answer the wrong question.
-- A global: a timer only its own callback refers to can be collected.
translateCopyPoll = nil
local function copySelectionThen(andThen, ready)
   local before = hs.pasteboard.changeCount()
   local deadline = hs.timer.secondsSinceEpoch() + COPY_TIMEOUT
   hs.eventtap.keyStroke({ "cmd" }, "c")
   if translateCopyPoll then translateCopyPoll:stop() end
   translateCopyPoll = hs.timer.doEvery(0.05, function()
      if hs.pasteboard.changeCount() ~= before then
         translateCopyPoll:stop()
         andThen()
      elseif hs.timer.secondsSinceEpoch() > deadline then
         translateCopyPoll:stop()
         ready.cancel()
         hs.alert.show("選択された文がありません")
      end
   end)
end

local function translateSelection()
   local ready = prepare()
   copySelectionThen(function() run({ "--clipboard" }, nil, ready) end, ready)
end

-- One key for every job, and no menu to pick from first: the job is guessed
-- from where the selection is, and a wrong guess is one tab away. Only the
-- written jobs are guessed; ⌃⌘⇧D is translation.
local CHAT_APPS = {
   ["com.tinyspeck.slackmacgap"] = true,
   ["com.hnc.Discord"] = true,
   ["com.apple.MobileSMS"] = true,
   ["com.microsoft.teams2"] = true,
   ["jp.naver.line.mac"] = true,
   ["com.apple.mail"] = true,
}
-- A selection in one of these is the user's own draft.
local TEXT_ROLES = { AXTextArea = true, AXTextField = true, AXComboBox = true }
-- Longer than a chat message is worth answering line by line: summarize it.
local REPLY_MAX_CHARS = 600

local function guessJob(bundleID, role, text)
   if TEXT_ROLES[role] then return "rewrite" end
   local chars = select(2, (text or ""):gsub("[^\128-\191]", ""))
   if CHAT_APPS[bundleID] and chars <= REPLY_MAX_CHARS then return "reply" end
   return "summarize"
end

-- Read before the copy, while the app with the selection is still in front.
-- An app that exposes no focused element reads as not a text field.
local function whereSelected()
   local app = hs.application.frontmostApplication()
   local focused = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
   return app and app:bundleID(), focused and focused:attributeValue("AXRole")
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
      local ready = prepare()
      hs.timer.doAfter(CLIPBOARD_WAIT, function()
         if shift then chooseLanguageThen({ "--clipboard" }, ready) else run({ "--clipboard" }, nil, ready) end
      end)
   else
      lastCopy = now
   end
   return false
end)
translateCopyWatcher:start()

-- On release, not press, so the ⌘C sent does not land while D is still down.
hs.hotkey.bind({ "ctrl", "cmd", "shift" }, "d", nil, translateSelection)
-- 清書 and 返信案 write in the user's voice from the style file; 清書 falls back
-- to a plain one without it (translate.py's header).
hs.hotkey.bind({ "ctrl", "cmd", "shift" }, "w", nil, function()
   local ready = prepare()
   local bundleID, role = whereSelected()
   copySelectionThen(function()
      local job = guessJob(bundleID, role, hs.pasteboard.getContents())
      run({ "--" .. job, "--clipboard" }, MODES[job], ready)
   end, ready)
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
