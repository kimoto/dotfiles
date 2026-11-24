--- === Curtain ===
---
--- At an end time the owner sets, covers every screen with a dark curtain so a
--- session that should have ended stops being visible. Nothing is closed: apps
--- and unsaved work stay as they are under it. Lifting it takes Esc held for
--- five seconds, so a reflex press is not enough, and it comes back five
--- minutes later while the Mac is still in use. Rules: logic.lua.
---
--- Opt in per machine, in ~/.hammerspoon.local:
---   hs.loadSpoon("Curtain"):start()
--- Settings go between loadSpoon and start (see the fields below). A machine
--- with its own additions (requests from elsewhere, its own automatic ends) uses the
--- methods marked "for extensions" instead of copying this file.

local obj = {}
obj.__index = obj
obj.name = "Curtain"
obj.version = "1.0"
obj.license = "MIT - https://opensource.org/licenses/MIT"

local HERE = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$")
local L = dofile(HERE .. "/logic.lua")
obj.logic = L

-- Settings. Each one can be changed before start().
-- Where the end time, the log and the files below live. Kept across reloads and restarts.
obj.stateDir = os.getenv("HOME") .. "/.local/state/curtain"
-- Seconds the owner's clock is ahead of UTC; nil takes this Mac's zone at start.
obj.utcOffset = nil
-- Extra "end at this time" menu rows with a note, e.g. { { "18:50", "before dinner" } }.
obj.marks = {}
-- Fixed daily ends when stateDir/daily-end does not exist (logic.daily_ends format), e.g. "daily 23:45".
-- nil turns them off; an empty daily-end file also does.
obj.dailyDefault = nil
-- Menu header note for an automatic end, by its from; daily is built in.
obj.fromLabels = {}
-- function(now), each tick before the curtain decides: a machine's own automatic ends go here.
obj.onStep = nil
-- Automatic ends a later poll may replace with an earlier one; removing one by hand skips it
-- (stateDir/<from>-skip) so the same end is not set again. An extension with its own polled
-- source adds it here, e.g. polled.calendar = true (daily is always polled). Such a
-- source must never set an end later than dailyEnd(), or the daily check swaps the two back
-- and forth each tick.
obj.polled = { daily = true }

local JST_FALLBACK = 9 * 3600
local ESC = hs.keycodes.map["escape"]
local HINT = "ここまで、と決めた時刻です。続ける時だけ Esc を5秒押し続ける"
local NEAR_SECONDS = 15 * 60
-- Six cells: readable at a glance, and short enough for a crowded menu bar.
local BAR_CELLS = 6
-- A polled end was armed whenever the Mac got to it, so its bar covers the last hour only.
local AUTO_BAR_SECONDS = 3600
-- Within the last hour the menu bar counts down to the second; further out, the end time.
local COUNTDOWN_SECONDS = 3600
-- A few weeks of evenings, and at most LOG_TRIM_BYTES/2, so a copy of it stays small.
local LOG_KEEP = 2000
local LOG_TRIM_BYTES = 300 * 1000

local function path(self, name) return self.stateDir .. "/" .. name end

-- This Mac's offset now, from %z ("+0900"), so a DST change is followed at the next tick.
local function localOffset()
   local sign, h, m = os.date("%z"):match("^([+-])(%d%d)(%d%d)$")
   if not sign then return JST_FALLBACK end
   return (sign == "-" and -1 or 1) * (tonumber(h) * 3600 + tonumber(m) * 60)
end

function obj:refreshOffset() self.tz = self.utcOffset or localOffset() end

function obj:clock(t) return os.date("!%H:%M", t + self.tz) end

-- For extensions: make stateDir (and its parents) exist.
function obj:ensureState()
   local p = ""
   for part in self.stateDir:gmatch("[^/]+") do
      p = p .. "/" .. part
      hs.fs.mkdir(p)
   end
end

-- For extensions: one tab-separated line (owner's time, event, detail) in stateDir/log.tsv, so a later
-- look can tell "it never came" from "it was lifted".
function obj:log(what, detail)
   self:ensureState()
   local f = io.open(self:logFile(), "a")
   if not f then return end
   local z = math.abs(self.tz)
   f:write(os.date("!%Y-%m-%dT%H:%M:%S", os.time() + self.tz)
      .. string.format("%s%02d:%02d", self.tz < 0 and "-" or "+", math.floor(z / 3600), math.floor(z % 3600 / 60))
      .. "\t" .. what .. "\t" .. tostring(detail or ""):gsub("[\t\n]", " ") .. "\n")
   f:close()
end

function obj:logFile() return path(self, "log.tsv") end

function obj:trimLog()
   local file = self:logFile()
   local f = io.open(file, "r")
   if not f then return end
   local lines = {}
   for l in f:lines() do lines[#lines + 1] = l end
   f:close()
   local first, bytes = #lines + 1, 0
   while first > 1 and #lines - first + 1 < LOG_KEEP and bytes + #lines[first - 1] + 1 <= LOG_TRIM_BYTES / 2 do
      first = first - 1; bytes = bytes + #lines[first] + 1
   end
   if first == 1 then return end
   -- Through a temp file, so a reload mid-write cannot leave (and let anyone copy) a cut log.
   f = io.open(file .. ".tmp", "w")
   if not f then return end
   for i = first, #lines do f:write(lines[i] .. "\n") end
   f:close()
   os.rename(file .. ".tmp", file)
end

local function readLine(p)
   local f = io.open(p, "r")
   if not f then return nil end
   local l = f:read("*l"); f:close()
   return (l and l ~= "") and l or nil
end

function obj:saveDeadline()
   self:ensureState()
   local s = self.s
   if s.deadline then
      -- Lines: end, snooze (so a reload during it does not bring the curtain straight back), from,
      -- and when the end was set (the start of the menu bar's bar).
      local f = io.open(path(self, "deadline"), "w")
      if f then
         f:write(tostring(s.deadline) .. "\n" .. tostring(s.snooze_until or "") .. "\n" .. (s.from or "") .. "\n"
            .. tostring(s.set_at or "") .. "\n")
         f:close()
      end
   else
      os.remove(path(self, "deadline"))
   end
end

function obj:loadDeadline()
   local f = io.open(path(self, "deadline"), "r")
   if not f then return end
   local t = tonumber(f:read("*l") or "")
   local z = tonumber(f:read("*l") or "")
   local from = f:read("*l")
   local set_at = tonumber(f:read("*l") or "")
   f:close()
   if t and os.time() - t < L.STALE_SECONDS then
      local s = self.s
      s.deadline, s.snooze_until, s.from, s.set_at = t, z, L.auto_from(from) and from or nil, set_at
   end
end

-- A pause outlives a reload, like the end time.
function obj:savePaused()
   self:ensureState()
   local s = self.s
   if not s.paused then os.remove(path(self, "paused")); return end
   local f = io.open(path(self, "paused"), "w")
   if f then
      f:write(tostring(s.paused) .. "\n" .. tostring(s.paused_at) .. "\n" .. tostring(s.paused_total or "") .. "\n")
      f:close()
   end
end

function obj:loadPaused()
   local f = io.open(path(self, "paused"), "r")
   if not f then return end
   local left, at = tonumber(f:read("*l") or ""), tonumber(f:read("*l") or "")
   local total = tonumber(f:read("*l") or "")
   f:close()
   if left and at and os.time() - at < L.STALE_SECONDS then
      self.s.paused, self.s.paused_at, self.s.paused_total = left, at, total
   else
      os.remove(path(self, "paused"))
   end
end

function obj:setText(sub)
   for _, c in ipairs(self.canvases) do c[3].text = sub end
end

-- The ring under the hint shows how much of the Esc hold is still to go: a full circle at the
-- press that empties until the lift. nil hides it (Esc released, or not held yet).
local RING_COLOR = { white = 0.9, alpha = 0.9 }
local RING_TRACK = { white = 0.3, alpha = 0.6 }
local HIDDEN = { alpha = 0 }
function obj:setRing(share)
   for _, c in ipairs(self.canvases) do
      c[4].strokeColor = share and RING_TRACK or HIDDEN
      c[5].strokeColor = share and share > 0 and RING_COLOR or HIDDEN
      -- Just short of 360: an arc whose ends meet may draw as nothing rather than a full circle.
      if share and share > 0 then c[5].endAngle = 359.9 * share end
   end
end

function obj:stopHold()
   if self.holdTimer then self.holdTimer:stop(); self.holdTimer = nil end
   self:setRing(nil)
end

function obj:hide()
   for _, c in ipairs(self.canvases) do c:delete() end
   self.canvases = {}
   self:stopHold()
   if self.escTap and not self.drainTimer then self.escTap:stop() end
   self.s.shown = false
end

function obj:stopDrain()
   if self.drainTimer then self.drainTimer:stop(); self.drainTimer = nil end
   if self.escTap and not self.s.shown then self.escTap:stop() end
end

function obj:lift()
   self:log("lift", "Esc 長押し")
   if self.drainTimer then self.drainTimer:stop() end
   self.drainTimer = hs.timer.doAfter(L.DRAIN_SECONDS, function() self:stopDrain() end)
   self:hide()
   self.s.snooze_until = os.time() + L.SNOOZE_SECONDS
   self:saveDeadline()
end

-- A curtain Esc cannot lift would lock the owner out, so it is not shown. It is tried again after
-- `after` seconds. The log line and the alert come once per reason, not on every retry, so a reason
-- that lasts (Secure Keyboard Entry left on) does not flood either.
local RETRY_SECONDS = 60
function obj:cannotShow(why, msg, after)
   self:hide()
   self.s.snooze_until = os.time() + (after or RETRY_SECONDS)
   self:saveDeadline()
   if why == self.notShownWhy then return end
   self.notShownWhy = why
   self:log("not-shown", why)
   hs.alert.show("幕を出せません: " .. msg, 6)
end

local RING_RADIUS = 48
local RING_WIDTH = 8
function obj:show(redraw)
   local s = self.s
   -- Under Secure Input the key tap sees nothing, so Esc would never reach it.
   if hs.eventtap.isSecureInputEnabled() then
      return self:cannotShow("secure input", "パスワード入力中などでキーを読めません（解ければ出ます）")
   end
   self.escTap:start()
   if not self.escTap:isEnabled() then
      return self:cannotShow("tap off", "Hammerspoon にアクセシビリティの許可が要ります", L.SNOOZE_SECONDS)
   end
   s.shown = true
   local title = s.deadline and self:clock(s.deadline) or "おしまい"
   -- A half-built curtain (an error on the second screen, or no screen at all just after wake)
   -- would swallow keys over a screen that is not covered.
   local ok, err = pcall(function()
      for _, screen in ipairs(hs.screen.allScreens()) do
         local f = screen:fullFrame()
         local c = hs.canvas.new(f)
         c:level(hs.canvas.windowLevels.screenSaver)
         c:behavior({ "canJoinAllSpaces", "stationary" })
         -- Swallow clicks so the apps underneath cannot be used through the curtain.
         c:canvasMouseEvents(true, true)
         c:mouseCallback(function() end)
         c:clickActivating(false)
         c[1] = { type = "rectangle", action = "fill",
                  fillColor = { red = 0.05, green = 0.05, blue = 0.08, alpha = 0.96 } }
         c[2] = {
            type = "text", text = title,
            textSize = 120, textColor = { white = 0.95 }, textAlignment = "center",
            frame = { x = 0, y = f.h * 0.30, w = f.w, h = 180 },
         }
         c[3] = {
            type = "text", text = HINT,
            textSize = 22, textColor = { white = 0.6 }, textAlignment = "center",
            frame = { x = 0, y = f.h * 0.30 + 190, w = f.w, h = 40 },
         }
         -- The hold ring: a dim track and the arc left on it, hidden until Esc is held (setRing).
         local ring = { x = f.w / 2, y = f.h * 0.30 + 190 + 40 + 30 + RING_RADIUS }
         c[4] = { type = "circle", action = "stroke", center = ring, radius = RING_RADIUS,
                  strokeWidth = RING_WIDTH, strokeColor = HIDDEN }
         c[5] = { type = "arc", action = "stroke", arcRadii = false, center = ring, radius = RING_RADIUS,
                  startAngle = 0, endAngle = 359.9, strokeWidth = RING_WIDTH, strokeColor = HIDDEN }
         c:show()
         table.insert(self.canvases, c)
      end
   end)
   if not ok or #self.canvases == 0 then
      -- A screen just plugged in or woken is often ready by the next tick, so retry soon.
      return self:cannotShow(ok and "no screen" or ("canvas: " .. tostring(err)), "画面を覆えませんでした", 15)
   end
   self.notShownWhy = nil
   if not redraw then self:log("show", s.deadline and self:clock(s.deadline) or "") end
end

-- While the curtain is up every key and scroll is swallowed, so nothing is typed or closed blind
-- underneath. Esc held: a key down starts the count, a key up before it ends cancels it. After the
-- lift it eats Esc alone, until a release or L.DRAIN_SECONDS.
function obj:makeEscTap()
   local T = hs.eventtap.event.types
   return hs.eventtap.new({ T.keyDown, T.keyUp, T.flagsChanged, T.scrollWheel }, function(e)
      if not self.s.shown then
         local act = L.tap_action(false, self.drainTimer ~= nil, e:getKeyCode() == ESC, e:getType() == T.keyUp)
         if act == "swallow_stop" then self:stopDrain() end
         return act ~= "pass"
      end
      if e:getType() == T.scrollWheel or e:getType() == T.flagsChanged then return true end
      if e:getKeyCode() ~= ESC then return true end
      if e:getType() == T.keyUp then
         self:stopHold()
         self:setText(HINT)
         return true
      end
      if self.holdTimer then return true end
      -- Redrawn about 30 times a second so the ring empties smoothly rather than in 5 steps.
      -- A monotonic clock, so a clock change while Esc is held neither shortens nor stretches the hold.
      local function seconds() return hs.timer.absoluteTime() / 1e9 end
      local pressed = seconds()
      local function redraw()
         local share, left = L.hold_left(seconds() - pressed, L.HOLD_SECONDS)
         if share <= 0 then self:lift(); return end
         self:setRing(share)
         self:setText("あと " .. left .. " 秒")
      end
      self.holdTimer = hs.timer.doEvery(1 / 30, redraw)
      redraw()
      return true
   end)
end

function obj:refreshMenu()
   if not self.menu then return end
   local s, now = self.s, os.time()
   -- Paused, unless a sooner end is near or has come: that one is what the owner needs to see.
   if s.paused and not (s.deadline and s.deadline - now <= NEAR_SECONDS) then
      self.menu:setTitle("⏸ あと" .. L.left(0, s.paused)
         .. (s.deadline and ("・" .. self:clock(s.deadline) .. "に幕") or ""))
   elseif not s.deadline then
      self.menu:setTitle("⏳")
   elseif s.deadline > now then
      -- The bar shows the share left since the end was set; the text, minutes or the time.
      local start = self:isPolled(s.from or "") and s.deadline - AUTO_BAR_SECONDS or s.set_at
      local bar = L.bar(now, start, s.deadline, BAR_CELLS)
      local text = s.deadline - now <= COUNTDOWN_SECONDS and ("あと " .. L.countdown(now, s.deadline))
         or (self:clock(s.deadline) .. "まで")
      self.menu:setTitle("⏳" .. (bar and (bar .. " ") or " ") .. text)
   elseif s.snooze_until and s.snooze_until > now then
      self.menu:setTitle("⏳ " .. self:clock(s.snooze_until) .. "にまた幕")
   else
      self.menu:setTitle("⏳ " .. self:clock(s.deadline) .. "過ぎ")
   end
end

function obj:dropPause(why)
   local s = self.s
   if not s.paused then return end
   s.paused, s.paused_at, s.paused_total = nil, nil, nil
   self:savePaused(); self:log("pause-dropped", why)
   self:refreshMenu()
end

-- For extensions: set (t, an epoch) or remove (nil) the end time. from: nil for an end the owner
-- or a remote request chose, or the name of an automatic source. why: for the log only.
function obj:setDeadline(t, from, why)
   local s = self.s
   -- A chosen time replaces a pause; an automatic end does not.
   if t and s.paused and not L.auto_from(from) then self:dropPause("chosen") end
   if t ~= s.deadline or from ~= s.from then
      local d = {}
      if t then d[#d + 1] = self:clock(t); d[#d + 1] = from or "chosen" end
      if why then d[#d + 1] = why end
      self:log(t and "set" or "clear", table.concat(d, " "))
      s.set_at = t and os.time() or nil
      -- Only a new end ends a snooze, so setting the same end again does not bring the curtain straight back.
      s.snooze_until = nil
      -- A new end gets its own alert if it cannot be shown either.
      self.notShownWhy = nil
   end
   s.deadline, s.from = t, from
   self:saveDeadline()
   -- An end that ran out is not a decision: it must not make a newer request look stale.
   if not L.auto_from(from) and why ~= "expired" then
      self:ensureState()
      local f = io.open(path(self, "changed"), "w")
      if f then f:write(os.date("!%Y-%m-%dT%H:%M:%S") .. "\n"); f:close() end
   end
   self:refreshMenu()
end

-- For extensions: when the end time last changed by choice (UTC, "YYYY-MM-DDTHH:MM:SS"), or "".
-- A request from elsewhere older than this is stale: the owner has decided since.
function obj:lastChange() return readLine(path(self, "changed")) or "" end

-- For extensions: whether from is a polled source. Daily always is, even if polled is replaced by a
-- table without it.
function obj:isPolled(from) return from == "daily" or (self.polled or {})[from] == true end

-- For extensions: the end of this polled source that was removed by hand, or nil.
function obj:skipOf(from)
   if not self:isPolled(from or "") then return nil end
   return tonumber(readLine(path(self, from .. "-skip")) or "")
end

-- For extensions: remove the end time on purpose. A polled end is remembered as skipped,
-- so the next poll does not set the same one again.
function obj:clearDeadline(why)
   local s = self.s
   if why ~= "paused" then self:dropPause(why or "manual") end
   if self:isPolled(s.from or "") and s.deadline then
      self:ensureState()
      local f = io.open(path(self, s.from .. "-skip"), "w")
      if f then f:write(tostring(s.deadline) .. "\n"); f:close() end
   end
   self:setDeadline(nil, nil, why or "manual")
end

-- For extensions: the state (deadline, snooze_until, shown, from, paused, set_at). Read it; change it
-- only through setDeadline and clearDeadline.
function obj:state() return self.s end

-- For extensions: true while the curtain is up or the held Esc is still being eaten, when a reload
-- would drop the key tap halfway.
function obj:busy() return self.s.shown or self.drainTimer ~= nil end

function obj:dailyEnd(now)
   local f = io.open(path(self, "daily-end"), "r")
   local conf = self.dailyDefault
   if f then conf = f:read("*a"); f:close() end
   if not conf then return nil end
   return L.daily_ends(now, self.tz, conf, self:skipOf("daily"))
end

function obj:checkDaily(now)
   local s = self.s
   if s.deadline and (not self:isPolled(s.from or "") or now >= s.deadline) then return end
   -- Only an earlier end replaces the one set: daily_end drops an end in its last minute, so recomputing
   -- from nothing would lose tonight's curtain.
   local d = self:dailyEnd(now)
   if d and (not s.deadline or d < s.deadline) then self:setDeadline(d, "daily") end
end

function obj:step()
   local s, now = self.s, os.time()
   self:refreshOffset()
   -- Secure Input turned on under a curtain already up: Esc can no longer reach the tap.
   if s.shown and hs.eventtap.isSecureInputEnabled() then
      self:cannotShow("secure input", "パスワード入力中などでキーを読めません（解ければ出ます）")
   end
   if s.paused and now - s.paused_at >= L.STALE_SECONDS then self:dropPause("stale") end
   self:refreshMenu()
   if self.onStep then self.onStep(now) end
   self:checkDaily(now)
   local a = L.decide(s, os.time(), hs.host.idleTime())
   if a == "show" then self:show()
   elseif a == "hide" then self:log("hide", "end moved or removed"); self:hide()
   elseif a == "clear" then self:hide(); self:setDeadline(nil, s.from, "expired") end
   local attr = hs.fs.attributes(self:logFile())
   if attr and attr.size > LOG_TRIM_BYTES then self:trimLog() end
end

-- A Spotlight-like picker: typing "1230", "12" or "945" narrows the list, arrows and Enter choose.
local NONE = { text = "当てはまる時刻がありません", subText = "例 1230・12:30・945" }

function obj:choicesFor(query)
   local now, out = os.time(), {}
   for _, t in ipairs(L.time_choices(now, self.tz, query)) do
      out[#out + 1] = { text = self:clock(t), subText = "あと" .. L.left(now, t), t = t }
   end
   if #out == 0 then out[1] = NONE end
   return out
end

function obj:makeChooser()
   local c = hs.chooser.new(function(choice)
      if not choice then return end
      if not choice.t then hs.alert.show("終わりの時刻は決まっていません"); return end
      -- The list was built when the query last changed; the picker may have sat open since.
      if choice.t <= os.time() then hs.alert.show(self:clock(choice.t) .. " はもう過ぎました"); return end
      self:setDeadline(choice.t)
      hs.alert.show("終わり " .. self:clock(choice.t))
   end)
   c:placeholderText("終わりの時刻（例 1230）")
   c:rows(8)
   c:queryChangedCallback(function(q) c:choices(self:choicesFor(q)) end)
   return c
end

function obj:askTime()
   self.chooser:query("")
   self.chooser:choices(self:choicesFor(""))
   self.chooser:show()
end

function obj:pick(t, note)
   return { title = "  " .. self:clock(t) .. (note and ("（" .. note .. "）") or ""), checked = self.s.deadline == t,
            fn = function() self:setDeadline(t) end }
end

function obj:menuItems()
   local s, now = self.s, os.time()
   local label = s.from == "daily" and "・毎日の終わり"
      or self.fromLabels[s.from or ""] or ""
   local head = s.deadline
      and ("終わり " .. self:clock(s.deadline)
           .. (s.deadline > now and ("（あと" .. L.left(now, s.deadline) .. "）") or "") .. label)
      or "終わりの時刻は未設定"
   local m = { { title = head, disabled = true } }
   -- Pause keeps what is left; resume starts it again from now. The state is read again on click:
   -- a poll may have changed it while the menu was open.
   if s.paused and L.resume_plan(s, now, s.paused) ~= "wait" then
      table.insert(m, { title = "▶ 再開（あと" .. L.left(0, s.paused) .. "）", fn = function()
         local now2, left = os.time(), s.paused
         if not left then return end
         local plan = L.resume_plan(s, now2, left)
         if plan == "wait" then return end
         local total = s.paused_total
         s.paused, s.paused_at, s.paused_total = nil, nil, nil; self:savePaused()
         self:log("resume", L.left(0, left))
         self:setDeadline(plan)
         -- The bar goes on from where it stopped, not full again.
         if total then s.set_at = plan - total; self:saveDeadline(); self:refreshMenu() end
      end })
      table.insert(m, { title = "⏸ を捨てる", fn = function() self:dropPause("manual") end })
   elseif L.can_pause(s, now) then
      table.insert(m, { title = "⏸ 一時停止（残りを取っておく）", fn = function()
         if not L.can_pause(s, os.time()) then return end
         local left = s.deadline - os.time()
         s.paused, s.paused_at = left, os.time()
         s.paused_total = s.set_at and (s.deadline - s.set_at) or nil
         self:savePaused()
         self:log("pause", L.left(0, left))
         self:clearDeadline("paused")
      end })
   end
   table.insert(m, { title = "-" })
   table.insert(m, { title = "あと何分で終わる", disabled = true })
   -- 2 and 5 on purpose (short focus blocks), unlike the slots below, which start 10 minutes out.
   for _, min in ipairs({ 2, 5, 10, 15, 25, 50, 90 }) do
      table.insert(m, { title = "  " .. L.left(0, min * 60),
                        fn = function() self:setDeadline(os.time() + min * 60) end })
   end
   table.insert(m, { title = "-" })
   table.insert(m, { title = "この時刻に終わる", disabled = true })
   for _, t in ipairs(L.slots(now, self.tz, 6)) do table.insert(m, self:pick(t)) end
   for _, mk in ipairs(self.marks) do
      local t = L.parse_time(mk[1], now, self.tz)
      if t and t - now >= 10 * 60 and t - now < 14 * 3600 then table.insert(m, self:pick(t, mk[2])) end
   end
   table.insert(m, { title = "  ほかの時刻…", fn = function() self:askTime() end })
   table.insert(m, { title = "-" })
   table.insert(m, { title = "今すぐ暗くする", fn = function() self:setDeadline(os.time()); self:step() end })
   table.insert(m, { title = "終わりを消す", fn = function() self:hide(); self:clearDeadline() end,
                     disabled = not s.deadline })
   return m
end

--- Curtain:start()
--- Method
--- Loads the saved state and starts the menu bar item, the key tap and the timers.
function obj:start()
   self:stop()
   self:refreshOffset()
   self.s = { deadline = nil, snooze_until = nil, shown = false, from = nil, paused = nil, paused_at = nil }
   self.canvases = {}
   self.escTap = self:makeEscTap()
   self.chooser = self:makeChooser()
   self.menu = hs.menubar.new()
   self.menu:setMenu(function() return self:menuItems() end)
   -- A screen plugged in or resized while the curtain is up gets covered too.
   self.screens = hs.screen.watcher.new(function()
      if self.s.shown then self:hide(); self:show(true) end
   end)
   self.screens:start()
   self:trimLog()
   self:loadDeadline()
   self:loadPaused()
   self:log("load", self.s.deadline and (self:clock(self.s.deadline) .. " " .. (self.s.from or "chosen")) or "")
   self:refreshMenu()
   -- Every 15 seconds: the curtain may come up up to that late, which is fine for an end time.
   self.tick = hs.timer.doEvery(15, function() self:step() end)
   -- The 15s tick is too slow for a countdown in seconds. Twice a second, so a timer that drifts across
   -- a second boundary never shows one second twice; at the end it runs step() so the curtain is on time.
   self.secondTimer = hs.timer.doEvery(0.5, function()
      local now, d = os.time(), self.s.deadline
      if not d or d - now > COUNTDOWN_SECONDS or now - d > 1 then return end
      if now >= d then self:step() else self:refreshMenu() end
   end)
   self:step()
   return self
end

--- Curtain:stop()
--- Method
--- Takes the curtain down and stops everything start() started. The end time stays saved.
function obj:stop()
   if self.s and self.s.shown then self:hide() end
   for _, k in ipairs({ "tick", "secondTimer", "holdTimer", "drainTimer" }) do
      if self[k] then self[k]:stop(); self[k] = nil end
   end
   if self.escTap then self.escTap:stop(); self.escTap = nil end
   if self.screens then self.screens:stop(); self.screens = nil end
   if self.menu then self.menu:delete(); self.menu = nil end
   if self.chooser then self.chooser:delete(); self.chooser = nil end
   return self
end

return obj
