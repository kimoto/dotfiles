--- === Guide ===
---
--- Lets an AI on this Mac guide where the owner looks: dim every app but one, dim all but the pointer
--- and a target, point an arrow at a window or a button, mark something (box, underline, brackets,
--- ripple, click), number the steps of a sequence, enlarge a small target beside it, show a message,
--- or ask a question with buttons and hear the answer. It can also bring the Curtain spoon's end
--- sooner (never later). guide_mcp.py beside this file is the MCP server an AI client starts; it
--- reaches this spoon over 127.0.0.1 with a token only this user can read. Rules: logic.lua.
---
--- What an AI can never do here: run code (a request is one of a fixed set of commands), lift or
--- remove the curtain, push its end later, show anything while it is up, or take the keyboard.
--- Nothing here installs a key tap, so the curtain's Esc hold and `exit` work exactly as before, and
--- the curtain sits above every guide overlay.
--- The owner's own ways out: switching to another app ends a spotlight, bringing the pointer to the
--- target ends a focus, a click closes a message, every overlay ends on its own, and ⌃⌥⌘Esc clears
--- everything and mutes the AI for 30 minutes.
---
--- Opt in per machine, in ~/.hammerspoon.local, after the curtain (or without it):
---   local guide = hs.loadSpoon("Guide")
---   guide.curtain = curtain   -- the started Curtain spoon, or leave out
---   guide:start()

local obj = {}
obj.__index = obj
obj.name = "Guide"
obj.version = "1.0"
obj.license = "MIT - https://opensource.org/licenses/MIT"

local HERE = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$")
local L = dofile(HERE .. "/logic.lua")
obj.logic = L

-- Settings. Each one can be changed before start().
-- The endpoint file (port and token) and the log live here; guide_mcp.py reads the same path.
obj.stateDir = os.getenv("HOME") .. "/.local/state/guide"
-- nil picks a free port at random on each start, like the token: a process that took a fixed port
-- first would be handed the token and could answer as if it were the owner.
obj.port = nil
-- The started Curtain spoon, for the curtain command; nil turns that command off.
obj.curtain = nil
obj.muteKey = { { "ctrl", "alt", "cmd" }, "escape" }
obj.muteSeconds = 30 * 60

-- Over app windows, under dialogs and the menu bar: a label must never sit on a system prompt's button.
-- The curtain (screenSaver) is far above.
local LEVEL = hs.canvas.windowLevels.floating
local ACCENT = { red = 1, green = 0.62, blue = 0.1, alpha = 1 }
local CARD = { red = 0.11, green = 0.11, blue = 0.14, alpha = 0.97 }
local JSONH = { ["Content-Type"] = "application/json" }
-- An answer is kept this long for the client still polling for it.
local ANSWER_KEEP = 15 * 60
local EVENTS_KEEP = 20
-- Looking for a button by its text walks the app's accessibility tree; a big window has thousands of
-- nodes and a hung app answers slowly, so the walk stops at whichever limit comes first.
local AX_NODES = 3000
local AX_SECONDS = 1.5
-- One accessibility call waits this long at most (macOS's own default is about 6 s), and one walk may
-- start every AX_GAP seconds: the walk runs on the thread the curtain's key tap needs.
local AX_CALL_SECONDS = 0.2
local AX_GAP = 2
local LOG_TRIM_BYTES = 200 * 1000

-- On the owner's clock, the curtain's when there is one (its utcOffset may differ from this Mac's).
function obj:clock(t)
   if self.curtain and self.curtain.tz then return self.curtain:clock(t) end
   return os.date("%H:%M", t)
end

-- Quoted for /bin/sh, so a home directory with a ' in it still gets its permissions set.
local function sq(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

function obj:log(what, detail)
   local f = io.open(self.stateDir .. "/log.tsv", "a")
   if not f then return end
   f:write(os.date("%Y-%m-%dT%H:%M:%S%z") .. "\t" .. what .. "\t" .. tostring(detail or ""):gsub("[\t\n]", " ") .. "\n")
   f:close()
end

-- Something the owner did, for the AI to read back in status: answered, dismissed, left, muted.
function obj:event(id, what, detail)
   table.insert(self.events, { at = os.time(), id = id, what = what, detail = detail })
   while #self.events > EVENTS_KEEP do table.remove(self.events, 1) end
   self:log(what, (id or "") .. " " .. (detail or ""))
end

-- The state dir and the endpoint file are this user's only: the token is the whole of the access check.
function obj:writeEndpoint()
   local p = self.stateDir .. "/endpoint"
   local tmp = p .. ".tmp"
   -- umask 077 as well as chmod: the file is never readable by others, not even for a moment.
   local dir = sq(self.stateDir)
   local ok = os.execute("umask 077 && /bin/mkdir -p " .. dir .. " && /bin/chmod 700 " .. dir
      .. " && /bin/rm -f " .. sq(tmp) .. " && /usr/bin/touch " .. sq(tmp) .. " && /bin/chmod 600 " .. sq(tmp))
   if not ok then return false end
   local f = io.open(tmp, "w")
   if not f then return false end
   f:write(tostring(self.boundPort) .. "\n" .. self.token .. "\n")
   f:close()
   return os.rename(tmp, p)
end

function obj:trimLog()
   local p = self.stateDir .. "/log.tsv"
   local attr = hs.fs.attributes(p)
   if not attr or attr.size < LOG_TRIM_BYTES then return end
   local f = io.open(p, "r")
   if not f then return end
   local all = f:read("*a"); f:close()
   local keep = all:sub(-LOG_TRIM_BYTES / 2):gsub("^[^\n]*\n", "")
   f = io.open(p .. ".tmp", "w")
   if not f then return end
   f:write(keep); f:close()
   os.rename(p .. ".tmp", p)
end

-- ===== Finding what to point at =====

local function findApp(name)
   local app = hs.application.get(name)
   if app then return app end
   for _, a in ipairs(hs.application.runningApplications()) do
      if (a:name() or ""):lower() == name:lower() then return a end
   end
   return nil
end

local function axFrame(el)
   local f = el:attributeValue("AXFrame")
   if type(f) == "table" and f.w and f.h then return { x = f.x, y = f.y, w = f.w, h = f.h } end
   local p, s = el:attributeValue("AXPosition"), el:attributeValue("AXSize")
   if type(p) == "table" and type(s) == "table" and s.w then return { x = p.x, y = p.y, w = s.w, h = s.h } end
   return nil
end

local AX_TEXT = { "AXTitle", "AXDescription", "AXValue", "AXPlaceholderValue", "AXHelp" }

-- Breadth-first from the app's focused window, then the whole app (its menus), for the first element
-- whose visible text contains needle and that has a size on screen.
local function findElement(app, needle)
   local root = hs.axuielement.applicationElement(app)
   if not root then return nil, "cannot read " .. app:name() .. " (accessibility permission?)" end
   root:setTimeout(AX_CALL_SECONDS)
   local win = root:attributeValue("AXFocusedWindow")
   if win then win:setTimeout(AX_CALL_SECONDS) end
   local queue, seen, n = { win or root }, 0, 1
   if win then queue[2] = root end
   local deadline = hs.timer.secondsSinceEpoch() + AX_SECONDS
   local head = 1
   while head <= #queue and seen < AX_NODES and hs.timer.secondsSinceEpoch() < deadline do
      local el = queue[head]; queue[head] = false; head = head + 1; seen = seen + 1
      for _, attr in ipairs(AX_TEXT) do
         if L.matches(needle, el:attributeValue(attr)) then
            local f = axFrame(el)
            if f and f.w > 0 and f.h > 0 then return f end
         end
      end
      for _, child in ipairs(el:attributeValue("AXChildren") or {}) do
         child:setTimeout(AX_CALL_SECONDS)
         n = n + 1; queue[n] = child
      end
   end
   return nil, "no element showing \"" .. needle .. "\" in " .. app:name()
end

-- The target as a rectangle on screen, or nil and why.
function obj:resolve(t)
   if t.kind == "point" then return { x = t.x - 20, y = t.y - 20, w = 40, h = 40 } end
   if t.kind == "rect" then return { x = t.x, y = t.y, w = t.w, h = t.h } end
   local app = findApp(t.app)
   if not app then return nil, "no running app named " .. t.app end
   if t.text then
      local now = hs.timer.secondsSinceEpoch()
      if self.lastWalk and now - self.lastWalk < AX_GAP then
         return nil, "finding by text: one search every " .. AX_GAP .. " seconds"
      end
      self.lastWalk = now
      return findElement(app, t.text)
   end
   local w = app:focusedWindow() or app:mainWindow() or app:visibleWindows()[1]
   if not w then return nil, t.app .. " has no window on screen" end
   local f = w:frame()
   return { x = f.x, y = f.y, w = f.w, h = f.h }
end

local function screenFrames()
   local out = {}
   for _, s in ipairs(hs.screen.allScreens()) do
      local f = s:fullFrame()
      out[#out + 1] = { x = f.x, y = f.y, w = f.w, h = f.h }
   end
   return out
end

-- ===== Overlays =====

local function fullCanvas(f)
   local c = hs.canvas.new(f)
   c:level(LEVEL)
   c:behavior({ "canJoinAllSpaces", "stationary" })
   -- No mouse callback: clicks go through to the app underneath.
   return c
end

local function toLocal(p, f) return { x = p.x - f.x, y = p.y - f.y } end

function obj:newId(kind)
   self.seq = self.seq + 1
   return kind .. "-" .. self.seq
end

function obj:remove(id, why)
   local ov = self.overlays[id]
   if not ov then return end
   self.overlays[id] = nil
   for _, t in ipairs(ov.timers) do t:stop() end
   for _, c in ipairs(ov.canvases) do c:delete() end
   -- An intro still playing: its own canvases, outside the ones a redraw replaces.
   for _, c in ipairs(ov.extra or {}) do c:delete() end
   if ov.onEnd then ov.onEnd(why) end
   self:log("end", id .. " " .. (why or ""))
   self:refreshMenu()
end

function obj:clearAll(why)
   for id in pairs(self.overlays) do self:remove(id, why) end
end

function obj:count()
   local n = 0
   for _ in pairs(self.overlays) do n = n + 1 end
   return n
end

-- Registers an overlay that ends after `seconds`; draw(ov) builds its canvases.
function obj:add(kind, seconds, ov)
   ov.id, ov.kind, ov.timers, ov.canvases = self:newId(kind), kind, {}, ov.canvases or {}
   ov.ends = os.time() + seconds
   self.overlays[ov.id] = ov
   table.insert(ov.timers, hs.timer.doAfter(seconds, function() self:remove(ov.id, "expired") end))
   self:refreshMenu()
   return ov
end

-- A slow pulse in the accent colour, so the eye finds it without it flashing. ov.pulseCanvas, when
-- set, keeps it to that one canvas: the others use the same indexes for other things.
function obj:pulse(ov, indexes)
   local t0 = hs.timer.secondsSinceEpoch()
   table.insert(ov.timers, hs.timer.doEvery(1 / 20, function()
      local a = 0.65 + 0.35 * math.cos((hs.timer.secondsSinceEpoch() - t0) * math.pi)
      for _, c in ipairs(ov.pulseCanvas and { ov.pulseCanvas } or ov.canvases) do
         for _, i in ipairs(indexes) do
            local col = { red = ACCENT.red, green = ACCENT.green, blue = ACCENT.blue, alpha = a }
            if c[i].action == "fill" then c[i].fillColor = col else c[i].strokeColor = col end
         end
      end
   end))
end

-- Every label says it is from the AI, so it never reads as part of the app underneath.
local function labelElement(text, p, f)
   text = "AI・" .. text
   local size = hs.drawing.getTextDrawingSize(text, { size = 20 })
   local w = math.min(size.w + 28, f.w - 16)
   local x = math.max(8, math.min(f.w - w - 8, p.x - w / 2))
   local y = math.max(8, math.min(f.h - 44, p.y))
   return { type = "rectangle", action = "fill", fillColor = CARD, roundedRectRadii = { xRadius = 8, yRadius = 8 },
            frame = { x = x, y = y, w = w, h = 36 }, withShadow = true },
          { type = "text", text = text, textSize = 20, textColor = { white = 1 }, textAlignment = "center",
            frame = { x = x, y = y + 5, w = w, h = 30 } }
end

local function stroke(width, coordinates)
   return { type = "segments", action = "stroke", strokeWidth = width, strokeColor = ACCENT, withShadow = true,
            strokeCapStyle = "round", strokeJoinStyle = "round", coordinates = coordinates }
end

-- Appends the mark of `style` round o (r's position on canvas c). Returns { pulse = the indexes
-- pulse() animates }, and for a ripple also rings (its spreading rings' indexes) and base (their radius).
local function mark(c, style, o, r)
   local n = #c
   local box = { x = o.x, y = o.y, w = r.w, h = r.h }
   local mid = L.center(box)
   if style == "underline" then
      c[n + 1] = stroke(5, { { x = o.x - 4, y = o.y + r.h + 5 }, { x = o.x + r.w + 4, y = o.y + r.h + 5 } })
      return { pulse = { n + 1 } }
   elseif style == "bracket" then
      local out = {}
      for i, arm in ipairs(L.brackets(box, 6, 18)) do c[n + i] = stroke(5, arm); out[i] = n + i end
      return { pulse = out }
   elseif style == "ripple" then
      local base = math.max(r.w, r.h) / 2 + 6
      for i = 1, 3 do
         c[n + i] = { type = "circle", action = "stroke", strokeWidth = i == 1 and 4 or 3, strokeColor = ACCENT,
                      center = mid, radius = base }
      end
      return { pulse = { n + 1 }, rings = { n + 2, n + 3 }, base = base }
   elseif style == "click" then
      -- A ring where the click lands, and a pointer shape on it with a white edge. Twice the system
      -- pointer's size and never fading, so it is not taken for the real one; only the ring pulses.
      c[n + 1] = { type = "circle", action = "stroke", strokeWidth = 3, strokeColor = ACCENT,
                   center = mid, radius = 18 }
      local shape = L.cursor(mid, 44)
      c[n + 2] = { type = "segments", action = "fill", closed = true, fillColor = ACCENT, withShadow = true,
                   coordinates = shape }
      c[n + 3] = { type = "segments", action = "stroke", closed = true, strokeWidth = 1.5,
                   strokeColor = { white = 1 }, coordinates = shape }
      return { pulse = { n + 1 } }
   end
   c[n + 1] = { type = "rectangle", action = "stroke", strokeWidth = 5, strokeColor = ACCENT,
                roundedRectRadii = { xRadius = 10, yRadius = 10 },
                frame = { x = o.x - 6, y = o.y - 6, w = r.w + 12, h = r.h + 12 } }
   return { pulse = { n + 1 } }
end

-- Rings that spread out from the target and fade, three times over, then stop: motion finds the eye,
-- and motion that never stops becomes noise to tune out.
local RIPPLE_PERIOD, RIPPLE_TIMES, RIPPLE_SPREAD = 1.2, 3, 60
function obj:ripple(ov)
   local t0 = hs.timer.secondsSinceEpoch()
   local timer
   timer = hs.timer.doEvery(1 / 30, function()
      local t = (hs.timer.secondsSinceEpoch() - t0) / RIPPLE_PERIOD
      local c = ov.canvases[1]
      if not c then return end
      local done = t >= RIPPLE_TIMES
      for k, i in ipairs(ov.marked.rings) do
         local phase = (t + (k - 1) * 0.5) % 1
         c[i].radius = ov.marked.base + RIPPLE_SPREAD * phase
         c[i].strokeColor = { red = ACCENT.red, green = ACCENT.green, blue = ACCENT.blue,
                              alpha = done and 0 or 0.9 * (1 - phase) }
      end
      -- A redraw after this (the window moved) draws the rings again; they must stay hidden.
      if done then ov.rippleDone = true; timer:stop() end
   end)
   table.insert(ov.timers, timer)
end

-- ===== Intros: one movement, under a second, that brings the eye before the mark settles =====

local function accent(alpha)
   return { red = ACCENT.red, green = ACCENT.green, blue = ACCENT.blue, alpha = alpha }
end

-- Runs step(t) with t going 0 → 1 over seconds, then deletes the canvases it drew on. They are kept in
-- ov.extra so clearing the overlay mid-flight takes them too.
local INTRO_HZ = 60
function obj:animate(ov, canvases, seconds, step)
   ov.extra = ov.extra or {}
   for _, c in ipairs(canvases) do ov.extra[#ov.extra + 1] = c; c:show() end
   -- Under the mark: a glow at the screen's edge must not cover a target in the menu bar or Dock.
   for _, m in ipairs(ov.canvases) do m:orderAbove() end
   local t0 = hs.timer.secondsSinceEpoch()
   local timer
   timer = hs.timer.doEvery(1 / INTRO_HZ, function()
      local t = math.min(1, (hs.timer.secondsSinceEpoch() - t0) / seconds)
      local ok, why = pcall(step, t)
      if not ok then self:log("error", ov.id .. " intro: " .. tostring(why)) end
      if t >= 1 or not ok then
         timer:stop()
         for _, c in ipairs(canvases) do
            c:delete()
            for i, e in ipairs(ov.extra) do if e == c then table.remove(ov.extra, i); break end end
         end
      end
   end)
   table.insert(ov.timers, timer)
end

-- A ring the size of the screen closes onto the target, a second one just behind it.
local IRIS_SECONDS, IRIS_LAG, IRIS_TRAVEL = 0.45, 0.12, 400
-- The last part of the run fades the rings, so they settle into the mark rather than blink out.
local IRIS_FADE = 0.2
function obj:iris(ov, r, frames)
   local f = L.screen_of(frames, L.center(r))
   local c = fullCanvas(f)
   local mid = toLocal(L.center(r), f)
   local to = math.max(r.w, r.h) / 2 + 10
   -- Always from well outside the target, so a whole-window target still sees the ring close in.
   local from = math.max(math.max(f.w, f.h) * 0.6, to + IRIS_TRAVEL)
   for i = 1, 2 do
      c[i] = { type = "circle", action = "stroke", center = mid, radius = from, strokeColor = accent(0) }
   end
   local total = IRIS_SECONDS + IRIS_LAG
   self:animate(ov, { c }, total, function(t)
      for i = 1, 2 do
         local k = L.ease((t * total - (i - 1) * IRIS_LAG) / IRIS_SECONDS)
         c[i].radius = from + (to - from) * k
         c[i].strokeWidth = 28 - 24 * k
         local fade = t > 1 - IRIS_FADE and (1 - t) / IRIS_FADE or 1
         c[i].strokeColor = accent(k <= 0 and 0 or (0.55 + 0.4 * k) * (i == 1 and 1 or 0.6) * fade)
      end
   end)
end

-- Eight thin rays from the target across every screen turn a sixteenth of a turn, then fade.
local SUN_SECONDS, SUN_RAYS, SUN_ALPHA = 0.7, 8, 0.3
function obj:sunburst(ov, r, frames)
   local mid = L.center(r)
   local reach = 0
   for _, f in ipairs(frames) do
      for _, x in ipairs({ f.x, f.x + f.w }) do
         for _, y in ipairs({ f.y, f.y + f.h }) do
            reach = math.max(reach, math.sqrt((x - mid.x) ^ 2 + (y - mid.y) ^ 2))
         end
      end
   end
   local canvases, list = {}, {}
   for _, f in ipairs(frames) do
      local c = fullCanvas(f)
      list[#list + 1] = c
      for i = 1, SUN_RAYS do
         c[i] = { type = "segments", action = "fill", closed = true, fillColor = accent(SUN_ALPHA),
                  coordinates = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } } }
      end
      canvases[#canvases + 1] = { c = c, f = f }
   end
   self:animate(ov, list, SUN_SECONDS, function(t)
      local rays = L.rays(mid, SUN_RAYS, math.pi / 8 * L.ease(t), reach, 70)
      local alpha = SUN_ALPHA * (t < 0.7 and 1 or (1 - t) / 0.3)
      for _, e in ipairs(canvases) do
         for i, ray in ipairs(rays) do
            e.c[i].coordinates = { toLocal(ray[1], e.f), toLocal(ray[2], e.f), toLocal(ray[3], e.f) }
            e.c[i].fillColor = accent(alpha)
         end
      end
   end)
end

-- A wide glow round the inside edge of the target's screen, once: "this monitor". It holds for a
-- moment before fading: the eye that catches it at the edge of vision needs that moment to turn.
local HALO_SECONDS, HALO_HOLD, HALO_ALPHA, HALO_WIDTH = 0.8, 0.3, 0.9, 80
function obj:halo(ov, r, frames)
   local f = L.screen_of(frames, L.center(r))
   local c = fullCanvas(f)
   -- A stroke is centred on its frame's edge: inset by half its width, or half of it falls off screen.
   local half = HALO_WIDTH / 2
   c[1] = { type = "rectangle", action = "stroke", strokeWidth = HALO_WIDTH, strokeColor = accent(HALO_ALPHA),
            frame = { x = half, y = half, w = f.w - HALO_WIDTH, h = f.h - HALO_WIDTH } }
   self:animate(ov, { c }, HALO_SECONDS, function(t)
      c[1].strokeColor = accent(HALO_ALPHA * (1 - L.ease((t - HALO_HOLD) / (1 - HALO_HOLD))))
   end)
end

-- A spark with a fading tail flies once from the pointer to the target. Its own small canvas moves,
-- so nothing full-screen redraws and it crosses from one monitor to the other as it goes.
local COMET_SECONDS, COMET_SIZE = 0.5, 320
local COMET_HEAD, COMET_CORE, COMET_TAIL, COMET_TAIL_WIDTH, COMET_SLICES = 22, 9, 150, 20, 6
function obj:comet(ov, r)
   local from, to = hs.mouse.absolutePosition(), L.center(r)
   local dx, dy = to.x - from.x, to.y - from.y
   local d = math.sqrt(dx * dx + dy * dy)
   if d < 1 then return false end
   local ux, uy = dx / d, dy / d
   local h = COMET_SIZE / 2
   local c = hs.canvas.new({ x = from.x - h, y = from.y - h, w = COMET_SIZE, h = COMET_SIZE })
   c:level(LEVEL)
   c:behavior({ "canJoinAllSpaces", "stationary" })
   -- The tail: a narrowing wedge behind the head, made of slices that fade towards its end.
   local slices = COMET_SLICES
   for i = 1, slices do
      local a, b = (i - 1) / slices, i / slices
      local w1, w2 = COMET_TAIL_WIDTH * (1 - a), COMET_TAIL_WIDTH * (1 - b)
      local l1, l2 = COMET_TAIL * a, COMET_TAIL * b
      c[i] = { type = "segments", action = "fill", closed = true, fillColor = accent(0.85 * (1 - a)),
               coordinates = { { x = h - ux * l1 - uy * w1, y = h - uy * l1 + ux * w1 },
                               { x = h - ux * l2 - uy * w2, y = h - uy * l2 + ux * w2 },
                               { x = h - ux * l2 + uy * w2, y = h - uy * l2 - ux * w2 },
                               { x = h - ux * l1 + uy * w1, y = h - uy * l1 - ux * w1 } } }
   end
   c[slices + 1] = { type = "circle", action = "fill", center = { x = h, y = h }, radius = COMET_HEAD,
                     fillColor = ACCENT,
                     withShadow = true }
   c[slices + 2] = { type = "circle", action = "fill", center = { x = h, y = h }, radius = COMET_CORE,
                     fillColor = { white = 1 } }
   self:animate(ov, { c }, COMET_SECONDS, function(t)
      local k = L.ease(t)
      c:topLeft({ x = from.x + dx * k - h, y = from.y + dy * k - h })
   end)
end

-- Plays the intro(s) and returns the names that did play, or nil for none: comet has nothing to fly
-- when the pointer is already on the target.
function obj:intro(ov, which, r)
   if which == "none" then return nil end
   local frames = screenFrames()
   local list = which == "auto" and L.intro_for(hs.mouse.absolutePosition(), r, frames) or { which }
   local played = {}
   for _, name in ipairs(list) do
      if self[name](self, ov, r, frames) ~= false then played[#played + 1] = name end
   end
   return #played > 0 and played or nil
end

-- Draws the mark (and for an arrow, the arrow) around rect r, and redraws when an app's window moves.
function obj:pointAt(kind, args)
   local r, err = self:resolve(args.target)
   if not r then return nil, err end
   local ov = self:add(kind, args.seconds, {})
   local function draw(rect)
      for _, c in ipairs(ov.canvases) do c:delete() end
      ov.canvases = {}
      local f = L.screen_of(screenFrames(), L.center(rect))
      local c = fullCanvas(f)
      ov.canvases[1] = c
      local o = toLocal(rect, f)
      local marked = mark(c, args.style, o, rect)
      if marked.rings and ov.rippleDone then
         for _, i in ipairs(marked.rings) do c[i].strokeColor = { white = 0, alpha = 0 } end
      end
      local labelAt = { x = o.x + rect.w / 2, y = o.y + rect.h + (args.style == "click" and 48 or 14) }
      if kind == "arrow" then
         local a = L.arrow(rect, f)
         local tail, tip, l, rt = toLocal(a.tail, f), toLocal(a.tip, f), toLocal(a.left, f), toLocal(a.right, f)
         local n = #c
         c[n + 1] = { type = "segments", action = "stroke", strokeWidth = 10, strokeColor = ACCENT, withShadow = true,
                      coordinates = { tail, { x = (l.x + rt.x) / 2, y = (l.y + rt.y) / 2 } } }
         c[n + 2] = { type = "segments", action = "fill", closed = true, fillColor = ACCENT, withShadow = true,
                      coordinates = { tip, l, rt } }
         table.insert(marked.pulse, n + 1)
         table.insert(marked.pulse, n + 2)
         labelAt = { x = tail.x, y = tail.y + (a.side.dy < 0 and -50 or 14) }
      end
      if args.label then
         local bg, tx = labelElement(args.label, labelAt, f)
         c[#c + 1] = bg; c[#c + 1] = tx
      end
      c:show()
      ov.canvases[1] = c
      ov.rect = rect
      ov.marked = marked
   end
   local drawn, why = pcall(draw, r)
   if not drawn then self:remove(ov.id, "error"); return nil, "could not draw: " .. tostring(why) end
   self:pulse(ov, ov.marked.pulse)
   if ov.marked.rings then self:ripple(ov) end
   -- The mark is up whatever happens here: an intro that fails is logged, and the reply still has the id.
   local introOk, played = pcall(self.intro, self, ov, args.intro, r)
   if not introOk then self:log("error", ov.id .. " intro: " .. tostring(played)); played = nil end
   if args.target.kind == "app" and not args.target.text then
      table.insert(ov.timers, hs.timer.doEvery(0.5, function()
         local nr = self:resolve(args.target)
         if not nr then
            self:event(ov.id, "gone", "target not on screen"); self:remove(ov.id, "gone")
         elseif (nr.x ~= ov.rect.x or nr.y ~= ov.rect.y or nr.w ~= ov.rect.w or nr.h ~= ov.rect.h)
            and not pcall(draw, nr) then
            self:event(ov.id, "gone", "could not redraw"); self:remove(ov.id, "error")
         end
      end))
   end
   self:log(kind, ov.id .. " " .. (args.label or ""))
   local out = { id = ov.id, at = r, intro = played }
   -- An app behind another window may be covered where the arrow points; say so, so the AI can
   -- bring it forward (a spotlight does) rather than point at whatever is on top.
   if args.target.kind == "app" then
      local front, app = hs.application.frontmostApplication(), findApp(args.target.app)
      out.in_front = front ~= nil and app ~= nil and front:pid() == app:pid()
   end
   return out
end

-- A card with the text and, for ask, a button per choice. Only the card takes clicks.
function obj:card(kind, args)
   local r
   if args.target then
      local err
      r, err = self:resolve(args.target)
      if not r then return nil, err end
   end
   local frames = screenFrames()
   local f = r and L.screen_of(frames, L.center(r)) or L.screen_of(frames, hs.mouse.absolutePosition())
   local w = math.min(560, f.w - 32)
   local inner = w - 56
   -- size.h already covers every line; the widest line over the width adds the wrapped ones (roughly).
   local size = hs.drawing.getTextDrawingSize(args.text, { size = 22 })
   local textH = size.h * math.max(1, math.ceil(size.w / inner)) + 6
   local buttons = args.choices and 64 or 0
   local h = 28 + textH + 24 + buttons + 18
   local box = L.box(args.position, w, h, f, r)
   local c = hs.canvas.new(box)
   c:level(LEVEL)
   c:behavior({ "canJoinAllSpaces", "stationary" })
   c:clickActivating(false)
   c[1] = { type = "rectangle", action = "fill", fillColor = CARD, roundedRectRadii = { xRadius = 14, yRadius = 14 },
            withShadow = true, trackMouseUp = true, id = "card" }
   c[2] = { type = "rectangle", action = "fill", fillColor = ACCENT, frame = { x = 0, y = 0, w = 6, h = h } }
   c[3] = { type = "text", text = args.text, textSize = 22, textColor = { white = 0.97 },
            trackMouseUp = true, id = "card",
            frame = { x = 28, y = 24, w = inner, h = textH + 4 } }
   c[4] = { type = "text", text = kind == "ask" and "AI からの質問・× で閉じる" or "AI から・押すと閉じる",
            textSize = 12, textColor = { white = 0.5 }, frame = { x = 28, y = h - 26, w = inner, h = 16 } }
   c[5] = { type = "text", text = "×", textSize = 20, textColor = { white = 0.6 }, trackMouseUp = true, id = "close",
            frame = { x = w - 34, y = 6, w = 24, h = 26 } }
   if args.choices then
      local n, gap = #args.choices, 10
      local bw = (inner - gap * (n - 1)) / n
      for i, choice in ipairs(args.choices) do
         local bx = 28 + (i - 1) * (bw + gap)
         c[#c + 1] = { type = "rectangle", action = "fill", fillColor = { white = 0.24, alpha = 1 },
                       roundedRectRadii = { xRadius = 8, yRadius = 8 }, trackMouseUp = true, id = "choice" .. i,
                       frame = { x = bx, y = 24 + textH + 14, w = bw, h = 44 } }
         c[#c + 1] = { type = "text", text = choice, textSize = 18, textColor = { white = 1 },
                       textAlignment = "center", trackMouseUp = true, id = "choice" .. i,
                       frame = { x = bx, y = 24 + textH + 24, w = bw, h = 30 } }
      end
   end
   local ov = self:add(kind, args.seconds, { canvases = { c } })
   if kind == "ask" then
      self.answers[ov.id] = { pending = true, at = os.time(), choices = args.choices }
      ov.onEnd = function(why)
         local a = self.answers[ov.id]
         if a and a.pending then
            a.pending, a.answer, a.at = nil, nil, os.time()
            a.ended = why
            -- Only the owner's own act counts as turning the question down.
            local owner = { clicked = true, owner = true, muted = true }
            self:event(ov.id, why == "expired" and "unanswered" or owner[why] and "dismissed" or "ended", why)
         end
      end
   end
   c:mouseCallback(function(_, msg, el)
      if msg ~= "mouseUp" then return end
      local i = tonumber(tostring(el):match("^choice(%d)$") or "")
      if kind == "ask" and i then
         local a = self.answers[ov.id]
         a.pending, a.answer, a.at = nil, args.choices[i], os.time()
         self:event(ov.id, "answered", args.choices[i])
         self:remove(ov.id, "answered")
      elseif el == "close" or kind == "message" then
         -- A question records its own "dismissed" as it ends (onEnd); a message has no onEnd.
         if kind == "message" then self:event(ov.id, "dismissed", "clicked") end
         self:remove(ov.id, "clicked")
      end
   end)
   c:show()
   self:log(kind, ov.id .. " " .. args.text)
   return { id = ov.id }
end

-- Dims every screen except the windows of one app. Switching to any other app ends it: that is the
-- owner choosing to look elsewhere, and the AI reads it back as a "left" event.
function obj:spotlight(args)
   local app = findApp(args.app)
   if not app then return nil, "no running app named " .. args.app end
   local first = false
   for _, w in ipairs(app:visibleWindows()) do first = first or w:isStandard() end
   if not first then return nil, args.app .. " has no window on screen to keep in the light" end
   self:replaceFor("spotlight")
   local ov = self:add("spotlight", args.seconds, {})
   local dark = { red = 0, green = 0, blue = 0.02, alpha = args.dim }
   local function holes()
      local out = {}
      for _, w in ipairs(app:visibleWindows()) do
         if w:isStandard() then local f = w:frame(); out[#out + 1] = { x = f.x, y = f.y, w = f.w, h = f.h } end
      end
      return out
   end
   local function key(rects)
      local k = {}
      for _, h in ipairs(rects) do k[#k + 1] = h.x .. "," .. h.y .. "," .. h.w .. "," .. h.h end
      return table.concat(k, ";")
   end
   local last
   local function draw()
      local hl = holes()
      local k = key(hl)
      if k == last then return end
      last = k
      for _, c in ipairs(ov.canvases) do c:delete() end
      ov.canvases = {}
      for i, f in ipairs(screenFrames()) do
         local c = fullCanvas(f)
         c[1] = { type = "rectangle", action = "fill", fillColor = dark }
         -- Each window cut out of the dark: "clear" erases what is under it in this canvas.
         for _, h in ipairs(hl) do
            local cl = L.clip(h, f)
            if cl then
               local o = toLocal(cl, f)
               c[#c + 1] = { type = "rectangle", action = "fill", compositeRule = "clear", fillColor = { white = 0 },
                             frame = { x = o.x, y = o.y, w = cl.w, h = cl.h } }
            end
         end
         if i == 1 and args.message then
            local bg, tx = labelElement(args.message, { x = f.w / 2, y = f.h * 0.04 }, f)
            c[#c + 1] = bg; c[#c + 1] = tx
         end
         c:show()
         ov.canvases[#ov.canvases + 1] = c
      end
   end
   app:activate()
   draw()
   -- An app that quit takes its spotlight with it, rather than failing on every tick.
   table.insert(ov.timers, hs.timer.doEvery(0.3, function()
      if not pcall(draw) then self:event(ov.id, "left", "app gone"); self:remove(ov.id, "app gone") end
   end))
   local front = hs.application.frontmostApplication()
   local settled = front ~= nil and front:pid() == app:pid()
   -- An app macOS will not bring forward never sends its own activation: settle anyway, soon.
   table.insert(ov.timers, hs.timer.doAfter(1.5, function() settled = true end))
   local watcher = hs.application.watcher.new(function(name, ev, a)
      if ev ~= hs.application.watcher.activated then return end
      -- Until the app has come forward, other activations are activate() settling, not the owner.
      if a and a:pid() == app:pid() then settled = true; return end
      if not settled then return end
      self:event(ov.id, "left", name)
      self:remove(ov.id, "left")
   end)
   watcher:start()
   table.insert(ov.timers, watcher)
   self:log("spotlight", ov.id .. " " .. args.app)
   return { id = ov.id }
end

-- spotlight and focus both dim the screen, so a new one of either takes the place of the old;
-- a new steps takes the place of the old steps.
local REPLACES = { spotlight = { spotlight = true, focus = true }, focus = { spotlight = true, focus = true },
                   steps = { steps = true } }
function obj:replaceFor(kind)
   for id, o in pairs(self.overlays) do
      if REPLACES[kind] and REPLACES[kind][o.kind] then self:remove(id, "replaced") end
   end
end

-- Dims every screen but two lit places: a circle round the pointer, which follows it, and the target,
-- with a line from one to the other. Bringing the pointer to the target is the owner finding it, so
-- the dark lifts by itself and the AI reads a "reached" event. An app target is brought forward,
-- or the hole would show whatever covers it, and followed when its window moves.
local FOLLOW_HZ = 30
local TRACK_SECONDS = 0.5
function obj:focus(args)
   local r, err = self:resolve(args.target)
   if not r then return nil, err end
   local app = args.target.kind == "app" and findApp(args.target.app) or nil
   if app then app:activate() end
   self:replaceFor("focus")
   local ov = self:add("focus", args.seconds, {})
   ov.frames = {}
   local dark = { red = 0, green = 0, blue = 0.02, alpha = args.dim }
   local clear = { white = 0 }
   local none = { x = 0, y = 0 }
   local frames = screenFrames()
   local home = L.screen_of(frames, L.center(r))
   local start = hs.mouse.absolutePosition()
   -- The same element at the same index on every screen's canvas, so the ticks can move them.
   local HOLE, POINTER, FRAME, SHAFT, HEAD, LABEL = 2, 3, 4, 5, 6, 7
   local function holeFrame(o, rect, pad)
      return { x = o.x - pad, y = o.y - pad, w = rect.w + 2 * pad, h = rect.h + 2 * pad }
   end
   for _, f in ipairs(frames) do
      local c = fullCanvas(f)
      local o = toLocal(r, f)
      c[1] = { type = "rectangle", action = "fill", fillColor = dark }
      c[HOLE] = { type = "rectangle", action = "fill", compositeRule = "clear", fillColor = clear,
                  roundedRectRadii = { xRadius = 10, yRadius = 10 }, frame = holeFrame(o, r, 10) }
      c[POINTER] = { type = "circle", action = "fill", compositeRule = "clear", fillColor = clear,
                     center = toLocal(start, f), radius = args.radius }
      c[FRAME] = { type = "rectangle", action = "stroke", strokeWidth = 4, strokeColor = ACCENT, withShadow = true,
                   roundedRectRadii = { xRadius = 12, yRadius = 12 }, frame = holeFrame(o, r, 12) }
      -- Butt caps: a zero-length shaft (no trail yet) then draws nothing at all.
      c[SHAFT] = { type = "segments", action = "stroke", strokeWidth = 5, strokeColor = ACCENT, withShadow = true,
                   coordinates = { none, none } }
      c[HEAD] = { type = "segments", action = "fill", closed = true, fillColor = ACCENT, withShadow = true,
                  coordinates = { none, none, none } }
      if args.label and f == home then
         local bg, tx = labelElement(args.label, { x = o.x + r.w / 2, y = o.y + r.h + 20 }, f)
         c[LABEL] = bg; c[LABEL + 1] = tx
      end
      c:show()
      ov.canvases[#ov.canvases + 1] = c
      ov.frames[#ov.frames + 1] = f
   end
   local last
   local function follow(force)
      local p = hs.mouse.absolutePosition()
      if not force and last and p.x == last.x and p.y == last.y then return end
      last = p
      if L.reached(start, p, r) then
         self:event(ov.id, "reached", args.label or "")
         self:remove(ov.id, "reached")
         return
      end
      local t = args.trail and L.trail(p, r, args.radius)
      for i, c in ipairs(ov.canvases) do
         local f = ov.frames[i]
         c[POINTER].center = toLocal(p, f)
         if args.trail then
            c[SHAFT].coordinates = t and { toLocal(t.tail, f), toLocal(t.neck, f) } or { none, none }
            c[HEAD].coordinates = t and { toLocal(t.tip, f), toLocal(t.left, f), toLocal(t.right, f) }
               or { none, none, none }
         end
      end
   end
   -- The hole, its frame and the label move with the app's window; the label stays on the screen it
   -- started on, which is where the owner was told to look.
   local function place(nr)
      r = nr
      for i, c in ipairs(ov.canvases) do
         local f = ov.frames[i]
         local o = toLocal(r, f)
         c[HOLE].frame = holeFrame(o, r, 10)
         c[FRAME].frame = holeFrame(o, r, 12)
         if c[LABEL] then
            local bg, tx = labelElement(args.label, { x = o.x + r.w / 2, y = o.y + r.h + 20 }, f)
            c[LABEL].frame = bg.frame; c[LABEL + 1].frame = tx.frame
         end
      end
      follow(true)
   end
   local drawn, why = pcall(follow)
   if not drawn then self:remove(ov.id, "error"); return nil, "could not draw: " .. tostring(why) end
   table.insert(ov.timers, hs.timer.doEvery(1 / FOLLOW_HZ, function()
      if self.overlays[ov.id] and not pcall(follow) then self:remove(ov.id, "error") end
   end))
   if app and not args.target.text then
      table.insert(ov.timers, hs.timer.doEvery(TRACK_SECONDS, function()
         if not self.overlays[ov.id] then return end
         local nr = self:resolve(args.target)
         if not nr then
            self:event(ov.id, "gone", "target not on screen"); self:remove(ov.id, "gone")
         elseif nr.x ~= r.x or nr.y ~= r.y or nr.w ~= r.w or nr.h ~= r.h then
            if not pcall(place, nr) then self:remove(ov.id, "error") end
         end
      end))
   end
   -- No pulse: the dark already does the work, and a pulse would redraw every screen 20 times a second.
   self:log("focus", ov.id .. " " .. (args.label or ""))
   local out = { id = ov.id, at = r }
   if app then
      local front = hs.application.frontmostApplication()
      out.in_front = front ~= nil and front:pid() == app:pid()
   end
   return out
end

-- A short numbered sequence: a badge on each target, the current one outlined and pulsing with its
-- label, the done ones grey with a tick, the later ones faint. The AI sends it again with the next
-- `current` to move on; a new one replaces the old.
local DONE = { white = 0.45, alpha = 0.95 }
local LATER = { red = ACCENT.red, green = ACCENT.green, blue = ACCENT.blue, alpha = 0.35 }

-- One step's target as a rectangle. A target found by its text is remembered, so moving on neither
-- walks the accessibility tree again (one walk every AX_GAP seconds) nor fails when a done step's
-- button has gone, as a pressed dialog button does.
function obj:stepRect(t, done)
   local key = t.text and (t.app .. "\0" .. t.text) or nil
   if key and self.stepTexts[key] then return self.stepTexts[key] end
   local r, err = self:resolve(t)
   if r and key then self.stepTexts[key] = r end
   if not r and done then return false end
   return r, err
end

function obj:steps(args)
   -- A sequence started again from the first step finds its buttons afresh.
   if args.current == 1 then self.stepTexts = {} end
   local rects = {}
   for i, s in ipairs(args.steps) do
      local r, err = self:stepRect(s.target, i < args.current)
      if r == nil then return nil, "step " .. i .. ": " .. err end
      rects[i] = r
   end
   self:replaceFor("steps")
   local ov = self:add("steps", args.seconds, {})
   local frames = screenFrames()
   local byScreen, order = {}, {}
   local function canvasFor(f)
      local key = f.x .. "," .. f.y
      if not byScreen[key] then
         byScreen[key] = fullCanvas(f)
         order[#order + 1] = byScreen[key]
      end
      return byScreen[key]
   end
   local pulsing = {}
   for i, r in ipairs(rects) do
      -- A done step whose target has gone keeps its place in the count but has nothing to mark.
      if r then
         local f = L.screen_of(frames, L.center(r))
         local c = canvasFor(f)
         local o = toLocal(r, f)
         local b = toLocal(L.badge(r, f), f)
         local now, done = i == args.current, i < args.current
         if now then
            pulsing = mark(c, "box", o, r).pulse
            ov.pulseCanvas = c
            if args.steps[i].label then
               local bg, tx = labelElement(i .. ". " .. args.steps[i].label,
                  { x = o.x + r.w / 2, y = o.y + r.h + 14 }, f)
               c[#c + 1] = bg; c[#c + 1] = tx
            end
         end
         local half = L.BADGE / 2
         c[#c + 1] = { type = "circle", action = "fill", withShadow = true, center = b, radius = half,
                       fillColor = done and DONE or now and ACCENT or LATER }
         c[#c + 1] = { type = "circle", action = "stroke", strokeWidth = 2, strokeColor = { white = 1, alpha = 0.9 },
                       center = b, radius = half }
         c[#c + 1] = { type = "text", text = done and "✓" or tostring(i), textSize = 17, textColor = { white = 1 },
                       textAlignment = "center", frame = { x = b.x - half, y = b.y - 11, w = L.BADGE, h = 24 } }
      end
   end
   for _, c in ipairs(order) do c:show(); ov.canvases[#ov.canvases + 1] = c end
   if #pulsing > 0 then self:pulse(ov, pulsing) end
   self:log("steps", ov.id .. " " .. args.current .. "/" .. #rects)
   return { id = ov.id, current = args.current, of = #rects }
end

-- An enlarged copy of a small target in a card beside it, joined to it by two lines: the eye gets the
-- thing itself, not only a mark round something too small to read. The copy is taken once, with the
-- other overlays hidden for that moment so it shows the screen as it is, and kept only in memory.
-- Without Screen Recording permission macOS hands back the wallpaper alone, so the loupe is refused
-- rather than shown empty. The card always says it is the AI's, and a click on it closes it rather
-- than reaching whatever is under it.
local LOUPE_GROW = 0.25
-- Under the 0.1 s a person notices, and enough for the window server to take hidden windows away: it
-- does so only once Hammerspoon goes back to its run loop, so this is a timer, never a sleep.
local LOUPE_HIDE_WAIT = 0.08
local FUNNEL = { 2, 3 }
function obj:loupe(args)
   if hs.screenRecordingState and not hs.screenRecordingState(false) then
      return nil, "Hammerspoon has no Screen Recording permission (System Settings > Privacy & Security > "
         .. "Screen & System Audio Recording), so a loupe would show only the wallpaper; use highlight instead"
   end
   local r, err = self:resolve(args.target)
   if not r then return nil, err end
   local frames = screenFrames()
   local f = L.screen_of(frames, L.center(r))
   if not L.clip(r, f) then return nil, "the target is not on any screen" end
   local lens = L.lens(r, f, args.zoom)
   if not lens then return nil, "no room to show the target larger than it is; use highlight" end
   local screen
   for i, fr in ipairs(frames) do if fr == f then screen = hs.screen.allScreens()[i] end end
   local so = toLocal(lens.src, f)
   local shown = {}
   for _, o in pairs(self.overlays) do
      for _, c in ipairs(o.canvases) do if c:isShowing() then c:hide(); shown[#shown + 1] = c end end
   end
   local ov = self:add("loupe", args.seconds, {})
   local function draw()
      -- An overlay may have been cleared while waiting: its canvas is gone, and that is fine.
      local function unhide() for _, c in ipairs(shown) do pcall(c.show, c) end end
      local img = screen:snapshot({ x = so.x, y = so.y, w = lens.src.w, h = lens.src.h })
      unhide()
      if not img then error("could not copy the screen") end
      -- Under the card: the outline round the copied area and the funnel to the card.
      local back = fullCanvas(f)
      ov.canvases = { back }
      back[1] = { type = "rectangle", action = "stroke", strokeWidth = 3, strokeColor = ACCENT, withShadow = true,
                  roundedRectRadii = { xRadius = 6, yRadius = 6 },
                  frame = { x = so.x, y = so.y, w = lens.src.w, h = lens.src.h } }
      local a, b = L.funnel(lens.src, lens.dst)
      back[FUNNEL[1]] = stroke(2, { toLocal(a[1], f), toLocal(a[2], f) })
      back[FUNNEL[2]] = stroke(2, { toLocal(b[1], f), toLocal(b[2], f) })
      -- The funnel shows once the card has arrived; drawn during the grow it would point at nothing.
      for _, i in ipairs(FUNNEL) do back[i].strokeColor = { white = 0, alpha = 0 } end
      back:show()
      local card = hs.canvas.new({ x = lens.src.x, y = lens.src.y, w = lens.src.w, h = lens.src.h })
      ov.canvases[2] = card
      card:level(LEVEL)
      card:behavior({ "canJoinAllSpaces", "stationary" })
      card:clickActivating(false)
      local head = L.LOUPE_HEADER
      card[1] = { type = "rectangle", action = "fill", fillColor = CARD, withShadow = true, trackMouseUp = true,
                  roundedRectRadii = { xRadius = 12, yRadius = 12 } }
      card[2] = { type = "text", text = "AI・" .. (args.label or "拡大") .. "・押すと閉じる", textSize = 14,
                  textColor = { white = 1 }, textAlignment = "center", textLineBreak = "truncateTail",
                  frame = { x = 8, y = 8, w = "100%", h = head - 8 } }
      card[3] = { type = "image", image = img, imageScaling = "scaleProportionally", trackMouseUp = true,
                  frame = { x = 6, y = head, w = lens.dst.w - 12, h = lens.dst.h - head - 6 } }
      card[4] = { type = "rectangle", action = "stroke", strokeWidth = 4, strokeColor = ACCENT,
                  roundedRectRadii = { xRadius = 12, yRadius = 12 } }
      card:mouseCallback(function(_, msg)
         if msg == "mouseUp" then self:event(ov.id, "dismissed", "clicked"); self:remove(ov.id, "clicked") end
      end)
      card:show()
      -- The card grows out of the copied area to its place, so the eye follows it from the thing itself.
      -- Until it has arrived the header and copy are left out: squeezed small they read as noise.
      card[2].textColor = { white = 1, alpha = 0 }
      local t0 = hs.timer.secondsSinceEpoch()
      local grow
      grow = hs.timer.doEvery(1 / 60, function()
         local k = L.ease((hs.timer.secondsSinceEpoch() - t0) / LOUPE_GROW)
         local s0, d = lens.src, lens.dst
         card:frame({ x = s0.x + (d.x - s0.x) * k, y = s0.y + (d.y - s0.y) * k,
                      w = s0.w + (d.w - s0.w) * k, h = s0.h + (d.h - s0.h) * k })
         if k >= 1 then
            for _, i in ipairs(FUNNEL) do back[i].strokeColor = ACCENT end
            card[2].textColor = { white = 1 }
            grow:stop()
         end
      end)
      table.insert(ov.timers, grow)
   end
   -- The copy waits for the other overlays to leave the screen; a failure then is logged and shown
   -- to the AI as a "gone" event, since the reply has already gone out.
   table.insert(ov.timers, hs.timer.doAfter(#shown > 0 and LOUPE_HIDE_WAIT or 0, function()
      local ok, why = pcall(draw)
      if not ok then
         for _, c in ipairs(shown) do pcall(c.show, c) end
         self:log("error", ov.id .. " loupe: " .. tostring(why))
         self:event(ov.id, "gone", "could not draw")
         self:remove(ov.id, "error")
      end
   end))
   self:log("loupe", ov.id .. " " .. (args.label or ""))
   return { id = ov.id, at = r, zoom = lens.zoom }
end

function obj:setCurtain(args)
   local c, now = self.curtain, os.time()
   local no = L.curtain_refusal(c and c:state(), now) or L.owner_deciding(c:lastChange(), now)
   if no then return nil, no end
   local t, err = L.curtain_end(args, now, c.tz)
   if not t then return nil, err end
   no = L.curtain_later(c:state(), t)
   if no then return nil, no end
   -- An automatic source, not the owner's choice: it leaves no mark that the owner decided, which
   -- a request from elsewhere would read as newer than its own.
   c:setDeadline(t, "ai", args.reason)
   c:step()
   self:log("curtain", self:clock(t) .. " " .. (args.reason or ""))
   return { ["end"] = self:clock(t), shown = c:state().shown == true }
end

function obj:status()
   local s = { screens = {}, windows = {}, overlays = {}, events = self.events, now = self:clock(os.time()) }
   for i, f in ipairs(screenFrames()) do f.main = i == 1; s.screens[i] = f end
   local front = hs.application.frontmostApplication()
   s.frontmost = front and front:name() or nil
   for _, w in ipairs(hs.window.orderedWindows()) do
      if #s.windows >= 20 then break end
      local app = w:application()
      local f = w:frame()
      s.windows[#s.windows + 1] = { app = app and app:name() or "?", title = L.truncate(w:title() or "", 80),
                                    frame = { x = f.x, y = f.y, w = f.w, h = f.h } }
   end
   for id, o in pairs(self.overlays) do
      s.overlays[#s.overlays + 1] = { id = id, kind = o.kind, ends = self:clock(o.ends) }
   end
   if L.muted(self.muteUntil, os.time()) then s.muted_until = self:clock(self.muteUntil) end
   if self.curtain then
      local cs = self.curtain:state() or {}
      s.curtain = { ["end"] = cs.deadline and self:clock(cs.deadline) or nil, shown = cs.shown == true,
                    back_at = (cs.snooze_until and cs.snooze_until > os.time()) and self:clock(cs.snooze_until) or nil,
                    paused = cs.paused ~= nil }
   end
   return s
end

-- Runs one checked command. Returns the reply table, or nil and why (sent as HTTP 409).
function obj:run(cmd, a)
   local now = os.time()
   for id, ans in pairs(self.answers) do
      if not ans.pending and now - ans.at > ANSWER_KEEP then self.answers[id] = nil end
   end
   if cmd == "status" then return self:status() end
   if cmd == "answer" then
      local ans = self.answers[a.id]
      if not ans then return nil, "no question " .. a.id end
      return { pending = ans.pending == true, answer = ans.answer, ended = ans.ended }
   end
   if cmd == "clear" then
      if a.id then self:remove(a.id, "cleared") else self:clearAll("cleared") end
      return { cleared = a.id or "all" }
   end
   if L.muted(self.muteUntil, now) then return nil, "the owner muted guidance until " .. self:clock(self.muteUntil) end
   local cs = self.curtain and self.curtain:state()
   if cs and cs.shown and not L.UNDER_CURTAIN[cmd] then
      return nil, "the curtain is up; nothing is shown over it"
   end
   if cmd == "curtain" then return self:setCurtain(a) end
   local replaces = false
   for _, o in pairs(self.overlays) do
      replaces = replaces or (REPLACES[cmd] ~= nil and REPLACES[cmd][o.kind] == true)
   end
   if self:count() >= L.MAX_OVERLAYS and not replaces then
      return nil, "too many overlays on screen; clear some first"
   end
   if cmd == "spotlight" then return self:spotlight(a) end
   if cmd == "focus" then return self:focus(a) end
   if cmd == "steps" then return self:steps(a) end
   if cmd == "loupe" then return self:loupe(a) end
   if cmd == "arrow" or cmd == "highlight" then return self:pointAt(cmd, a) end
   return self:card(cmd, a)
end

function obj:handle(method, path, headers, body)
   local code, why = L.check_request(method, headers, self.token, self.boundPort)
   if code then return hs.json.encode({ error = why }), code, JSONH end
   if path ~= "/v1" then return hs.json.encode({ error = "not found" }), 404, JSONH end
   local ok, req = pcall(hs.json.decode, body or "")
   if not ok or type(req) ~= "table" or type(req.cmd) ~= "string" then
      return hs.json.encode({ error = "body must be {cmd, args}" }), 400, JSONH
   end
   local args, err = L.validate(req.cmd, req.args)
   if not args then return hs.json.encode({ error = err }), 400, JSONH end
   local ran, res, err2 = pcall(self.run, self, req.cmd, args)
   if not ran then
      self:log("error", tostring(res))
      return hs.json.encode({ error = tostring(res) }), 500, JSONH
   end
   if res == nil then return hs.json.encode({ error = err2 or "refused" }), 409, JSONH end
   return hs.json.encode(res), 200, JSONH
end

-- ===== The owner's controls =====

-- A mute outlives a reload (a dotfiles pull reloads Hammerspoon), or the AI would be back early.
function obj:saveMute()
   local p = self.stateDir .. "/mute"
   if not self.muteUntil then os.remove(p); return end
   local f = io.open(p, "w")
   if f then f:write(tostring(self.muteUntil) .. "\n"); f:close() end
end

function obj:loadMute()
   local f = io.open(self.stateDir .. "/mute", "r")
   if not f then return end
   local t = tonumber(f:read("*l") or ""); f:close()
   self.muteUntil = L.muted(t, os.time()) and t or nil
end

function obj:mute()
   self:clearAll("muted")
   self.muteUntil = os.time() + self.muteSeconds
   self:saveMute()
   self:event(nil, "muted", "until " .. self:clock(self.muteUntil))
   hs.alert.show("AI の表示を消しました（" .. self:clock(self.muteUntil) .. " まで出しません）", 3)
   self:refreshMenu()
end

-- The menu bar item is there only while the AI shows something or is muted, so the owner always
-- knows where an arrow or a dimmed screen came from.
function obj:refreshMenu()
   local muted = L.muted(self.muteUntil, os.time())
   if self:count() == 0 and not muted then
      if self.menu then self.menu:delete(); self.menu = nil end
      return
   end
   if not self.menu then
      self.menu = hs.menubar.new()
      self.menu:setMenu(function()
         local m = {
            { title = "AI の表示をすべて消す", fn = function() self:clearAll("owner") end,
              disabled = self:count() == 0 },
            { title = "30分 AI に出させない（⌃⌥⌘Esc）", fn = function() self:mute() end },
         }
         if L.muted(self.muteUntil, os.time()) then
            table.insert(m, { title = "また出してよい", fn = function()
               self.muteUntil = nil; self:saveMute(); self:event(nil, "unmuted", "owner"); self:refreshMenu()
            end })
         end
         return m
      end)
   end
   self.menu:setTitle(muted and ("🔕 " .. self:clock(self.muteUntil)) or ("👁 AI " .. self:count()))
end

--- Guide:start()
--- Method
--- Starts the local server, the mute hotkey and a new token.
function obj:start()
   self:stop()
   self.overlays, self.answers, self.events, self.seq, self.stepTexts = {}, {}, {}, 0, {}
   self.token = (hs.host.uuid() .. hs.host.uuid()):gsub("-", "")
   math.randomseed(os.time() + hs.timer.absoluteTime() % 1000000)
   -- A random port can be taken by another service: a few tries, then give up with an alert.
   for _ = 1, self.port and 1 or 5 do
      self.server = hs.httpserver.new(false, false)
      self.server:setInterface("localhost")
      self.server:setPort(self.port or math.random(20000, 60999))
      self.server:setCallback(function(...) return self:handle(...) end)
      self.server:start()
      -- The port it really got; the endpoint is written only once something of ours listens there.
      self.boundPort = self.server:getPort()
      if self.boundPort and self.boundPort ~= 0 then break end
      self.server:stop()
   end
   if not self.boundPort or self.boundPort == 0 or not self:writeEndpoint() then
      hs.alert.show("Guide: 起動できませんでした", 5)
      self.server:stop(); self.server = nil
      return self
   end
   self:trimLog()
   self:loadMute()
   self:refreshMenu()
   if self.curtain then self.curtain.fromLabels.ai = self.curtain.fromLabels.ai or "・AI から" end
   self.hotkey = hs.hotkey.bind(self.muteKey[1], self.muteKey[2], function() self:mute() end)
   -- Clears the 🔕 once the mute runs out.
   self.muteTimer = hs.timer.doEvery(60, function() self:refreshMenu() end)
   self:log("start", tostring(self.boundPort))
   return self
end

--- Guide:stop()
--- Method
--- Clears every overlay and stops the server. The endpoint file goes too, so a client says
--- "not running" rather than sending a token nobody checks.
function obj:stop()
   if self.overlays then self:clearAll("stopped") end
   if self.server then self.server:stop(); self.server = nil end
   if self.hotkey then self.hotkey:delete(); self.hotkey = nil end
   if self.muteTimer then self.muteTimer:stop(); self.muteTimer = nil end
   if self.menu then self.menu:delete(); self.menu = nil end
   os.remove(self.stateDir .. "/endpoint")
   return self
end

return obj
