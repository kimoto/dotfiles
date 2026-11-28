-- The Guide spoon's rules, kept free of hs.* so they run in plain LuaJIT (test/guide_logic_test.lua).
-- Everything an AI sends goes through validate() first: a request names one of a fixed set of
-- commands with bounded arguments, never code, so nothing it sends can reach the curtain's way out.
local M = {}

-- How long each kind may stay up, in seconds: { default, most }. Every overlay ends on its own,
-- so one the AI forgets never stays on the screen.
M.SECONDS = {
   message = { 60, 600 },
   arrow = { 30, 600 },
   highlight = { 30, 600 },
   spotlight = { 300, 1800 },
   ask = { 120, 600 },
   -- Short by default: a screen dimmed for long reads as a broken display.
   focus = { 30, 300 },
   steps = { 120, 600 },
}
-- Enough for one step of a walkthrough; more on the screen at once stops guiding the eye.
M.MAX_OVERLAYS = 12
-- How a pointed-at target is marked: a box round it, a line under text, corner brackets that leave
-- the glyphs clear, rings that spread from a small icon, or a cursor-shaped marker for "click here".
M.STYLES = { box = true, underline = true, bracket = true, ripple = true, click = true }
-- A one-shot movement, under a second, that brings the eye to a target before its mark settles:
-- iris, a ring that closes in from the size of the screen; sunburst, rays from the target across every
-- screen; halo, a glow round the edge of the target's screen ("this monitor"); comet, a spark that
-- flies from the pointer to the target. auto picks from where the pointer is (M.intro_for).
M.INTROS = { none = true, auto = true, iris = true, sunburst = true, halo = true, comet = true }

-- More numbered steps on screen than this stop reading as one sequence.
M.MAX_STEPS = 5
-- The lit circle round the pointer in a focus: under 60 the pointer is lost in the dark, over 400 the
-- dark no longer narrows the eye.
M.RADIUS = { 60, 140, 400 }
-- focus dims less than a spotlight by default: two holes have to read through it.
M.FOCUS_DIM = 0.7
M.MAX_TEXT = 400
M.MAX_LABEL = 80
M.MAX_CHOICE = 30
M.MAX_CHOICES = 4
-- Below 0.3 the rest of the screen still pulls the eye; above 0.97 it reads as a broken display.
M.DIM = { 0.3, 0.85, 0.97 }
-- The curtain's own limit for an end set from elsewhere: within one working stretch.
M.CURTAIN_MAX_MINUTES = 14 * 60
M.POSITIONS = { center = true, top = true, bottom = true, near = true }

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

-- Cuts s to at most n bytes without splitting a UTF-8 character (Japanese text is 3 bytes a character).
function M.truncate(s, n)
   if #s <= n then return s end
   local cut = n
   -- A continuation byte is 10xxxxxx; step back to the start of its character.
   while cut > 0 and s:byte(cut + 1) and s:byte(cut + 1) >= 0x80 and s:byte(cut + 1) < 0xC0 do cut = cut - 1 end
   return s:sub(1, cut) .. "…"
end

local function text(v, n, name)
   if type(v) ~= "string" or v:match("^%s*$") then return nil, name .. " must be non-empty text" end
   return M.truncate(v, n)
end

function M.seconds(kind, v)
   local d, most = M.SECONDS[kind][1], M.SECONDS[kind][2]
   if v == nil then return d end
   if not finite(v) or v <= 0 then return nil, "seconds must be a positive number" end
   return math.min(v, most)
end

-- A target is an app (its frontmost window, or the element in it whose text contains `text`),
-- a rectangle, or a point, in screen points with the origin at the top left of the main screen.
function M.target(t)
   if type(t) ~= "table" then return nil, "target must be an object" end
   if t.app ~= nil then
      local app, err = text(t.app, 100, "target.app")
      if not app then return nil, err end
      local needle
      if t.text ~= nil then
         needle, err = text(t.text, 100, "target.text")
         if not needle then return nil, err end
      end
      return { kind = "app", app = app, text = needle }
   end
   if not (finite(t.x) and finite(t.y)) then return nil, "target needs app, or x and y" end
   if t.w == nil and t.h == nil then return { kind = "point", x = t.x, y = t.y } end
   if not (finite(t.w) and finite(t.h) and t.w > 0 and t.h > 0) then return nil, "target w and h must be positive" end
   return { kind = "rect", x = t.x, y = t.y, w = t.w, h = t.h }
end

-- Returns the cleaned arguments for cmd, or nil and why. Unknown fields are dropped.
function M.validate(cmd, a)
   a = type(a) == "table" and a or {}
   local out, err = {}, nil
   if cmd == "status" or cmd == "clear" then
      if a.id ~= nil then
         if type(a.id) ~= "string" then return nil, "id must be text" end
         out.id = a.id
      end
      return out
   elseif cmd == "answer" then
      if type(a.id) ~= "string" then return nil, "id must be text" end
      return { id = a.id }
   elseif cmd == "message" or cmd == "ask" then
      out.text, err = text(a.text, M.MAX_TEXT, "text")
      if not out.text then return nil, err end
      out.position = a.position or (a.target and "near" or "center")
      if not M.POSITIONS[out.position] then return nil, "position must be center, top, bottom or near" end
      if a.target ~= nil then
         out.target, err = M.target(a.target)
         if not out.target then return nil, err end
      elseif out.position == "near" then
         return nil, "position near needs a target"
      end
      out.seconds, err = M.seconds(cmd, a.seconds)
      if not out.seconds then return nil, err end
      if cmd == "ask" then
         if type(a.choices) ~= "table" or #a.choices < 2 or #a.choices > M.MAX_CHOICES then
            return nil, "choices must list 2 to " .. M.MAX_CHOICES .. " options"
         end
         out.choices = {}
         for i, c in ipairs(a.choices) do
            out.choices[i], err = text(c, M.MAX_CHOICE, "each choice")
            if not out.choices[i] then return nil, err end
         end
      end
      return out
   elseif cmd == "arrow" or cmd == "highlight" then
      out.target, err = M.target(a.target)
      if not out.target then return nil, err end
      if a.label ~= nil then
         out.label, err = text(a.label, M.MAX_LABEL, "label")
         if not out.label then return nil, err end
      end
      out.style = a.style or "box"
      if not M.STYLES[out.style] then return nil, "style must be box, underline, bracket, ripple or click" end
      out.intro = a.intro or "none"
      if not M.INTROS[out.intro] then
         return nil, "intro must be none, auto, iris, sunburst, halo or comet"
      end
      out.seconds, err = M.seconds(cmd, a.seconds)
      if not out.seconds then return nil, err end
      return out
   elseif cmd == "focus" then
      out.target, err = M.target(a.target)
      if not out.target then return nil, err end
      if a.label ~= nil then
         out.label, err = text(a.label, M.MAX_LABEL, "label")
         if not out.label then return nil, err end
      end
      if a.dim == nil then out.dim = M.FOCUS_DIM
      elseif finite(a.dim) then out.dim = math.max(M.DIM[1], math.min(M.DIM[3], a.dim))
      else return nil, "dim must be a number" end
      if a.radius == nil then out.radius = M.RADIUS[2]
      elseif finite(a.radius) then out.radius = math.max(M.RADIUS[1], math.min(M.RADIUS[3], a.radius))
      else return nil, "radius must be a number" end
      if a.trail ~= nil and type(a.trail) ~= "boolean" then return nil, "trail must be true or false" end
      out.trail = a.trail ~= false
      out.seconds, err = M.seconds(cmd, a.seconds)
      if not out.seconds then return nil, err end
      return out
   elseif cmd == "steps" then
      if type(a.steps) ~= "table" or #a.steps < 1 or #a.steps > M.MAX_STEPS then
         return nil, "steps must list 1 to " .. M.MAX_STEPS .. " steps"
      end
      out.steps = {}
      local byText = 0
      for i, s in ipairs(a.steps) do
         if type(s) ~= "table" then return nil, "each step must be an object" end
         local t
         t, err = M.target(s.target)
         if not t then return nil, "step " .. i .. ": " .. err end
         -- Finding by text walks the accessibility tree, and one walk is allowed every few seconds.
         if t.text then byText = byText + 1 end
         if byText > 1 then return nil, "at most one step may find its target by text" end
         local label
         if s.label ~= nil then
            label, err = text(s.label, M.MAX_LABEL, "step " .. i .. " label")
            if not label then return nil, err end
         end
         out.steps[i] = { target = t, label = label }
      end
      if a.current == nil then out.current = 1
      elseif finite(a.current) and a.current == math.floor(a.current) and a.current >= 1
         and a.current <= #out.steps + 1 then
         out.current = a.current
      else
         return nil, "current must be a step number, or one past the last when all are done"
      end
      out.seconds, err = M.seconds(cmd, a.seconds)
      if not out.seconds then return nil, err end
      return out
   elseif cmd == "spotlight" then
      out.app, err = text(a.app, 100, "app")
      if not out.app then return nil, err end
      if a.dim == nil then out.dim = M.DIM[2]
      elseif finite(a.dim) then out.dim = math.max(M.DIM[1], math.min(M.DIM[3], a.dim))
      else return nil, "dim must be a number" end
      if a.message ~= nil then
         out.message, err = text(a.message, M.MAX_TEXT, "message")
         if not out.message then return nil, err end
      end
      out.seconds, err = M.seconds(cmd, a.seconds)
      if not out.seconds then return nil, err end
      return out
   elseif cmd == "curtain" then
      if a.minutes ~= nil then
         if not finite(a.minutes) or a.minutes < 0 or a.minutes > M.CURTAIN_MAX_MINUTES then
            return nil, "minutes must be 0 to " .. M.CURTAIN_MAX_MINUTES
         end
         out.minutes = a.minutes
      elseif type(a.at) == "string" and a.at:match("^%d%d?:%d%d$") then
         local h, m = a.at:match("^(%d+):(%d+)$")
         if tonumber(h) > 23 or tonumber(m) > 59 then return nil, "at must be a time like 18:30" end
         out.at = a.at
      else
         return nil, "curtain needs minutes, or at like 18:30"
      end
      if a.reason ~= nil then
         out.reason, err = text(a.reason, M.MAX_LABEL, "reason")
         if not out.reason then return nil, err end
      end
      return out
   end
   return nil, "unknown command"
end

local function header(headers, name)
   for k, v in pairs(headers or {}) do
      if type(k) == "string" and k:lower() == name then return v end
   end
   return nil
end

-- Compares every byte, so how long the check takes says nothing about how much of the token matched.
local function same(a, b)
   if type(a) ~= "string" or type(b) ~= "string" or #a ~= #b then return false end
   local diff = 0
   for i = 1, #a do diff = diff + (a:byte(i) == b:byte(i) and 0 or 1) end
   return diff == 0
end

-- nil when the request may go on, else an HTTP status and why. A web page can reach 127.0.0.1 too:
-- it sends Origin, and through DNS rebinding a Host that is not ours, and never knows the token.
function M.check_request(method, headers, token, port)
   if method ~= "POST" then return 405, "POST only" end
   if header(headers, "origin") then return 403, "no browser requests" end
   local host = header(headers, "host")
   local okHost = { ["127.0.0.1:" .. port] = true, ["localhost:" .. port] = true }
   if not okHost[host or ""] then return 403, "wrong host" end
   if not same(header(headers, "x-guide-token"), token) then return 401, "bad token" end
   return nil
end

-- Why an AI may not move the curtain now, or nil. While the curtain is up, just after the owner lifted
-- it, or while they paused it, the decision is theirs: a new end there would bring it straight back.
function M.curtain_refusal(s, now)
   if not s then return "the curtain is not running on this Mac" end
   if s.shown then return "the curtain is up; the owner decides when it goes" end
   if s.snooze_until and s.snooze_until > now then return "the owner lifted the curtain a moment ago" end
   if s.paused then return "the owner paused the curtain" end
   return nil
end

-- Seconds since the UTC stamp "YYYY-MM-DDTHH:MM:SS" (the curtain's lastChange()), or nil for none.
function M.since(stamp, now)
   local y, mo, d, h, mi, s = (stamp or ""):match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
   if not y then return nil end
   y, mo = tonumber(y), tonumber(mo)
   -- Days from 1970-01-01 to the date (the civil-from-days algorithm), so no time zone is involved.
   if mo <= 2 then y = y - 1 end
   local era = math.floor(y / 400)
   local yoe = y - era * 400
   local doy = math.floor((153 * (mo + (mo > 2 and -3 or 9)) + 2) / 5) + tonumber(d) - 1
   local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
   local days = era * 146097 + doe - 719468
   return now - (days * 86400 + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(s))
end

-- After the owner chooses, finishes or removes an end, it is theirs for a while: an AI bringing
-- the curtain back the moment they said "done" would overrule them.
M.OWNER_SECONDS = 10 * 60
function M.owner_deciding(stamp, now)
   local ago = M.since(stamp, now)
   if ago and ago >= 0 and ago < M.OWNER_SECONDS then return "the owner set or ended the curtain a moment ago" end
   return nil
end

-- An AI may bring the end sooner, never later: moving it on before it comes would remove the curtain
-- in all but name. nil when t is allowed, else why.
function M.curtain_later(s, t)
   if s.deadline and t >= s.deadline then return "an AI may only bring the end sooner than it is now" end
   return nil
end

-- While the curtain is up, only reading and clearing: anything that draws, or that brings an app
-- forward (one that turns on Secure Input makes the curtain stand down), is the owner's time to decide.
M.UNDER_CURTAIN = { status = true, answer = true, clear = true }

-- The end an AI asked for, as an epoch, or nil and why. at: the next HH:MM on the owner's clock
-- (tz seconds ahead of UTC), within CURTAIN_MAX_MINUTES.
function M.curtain_end(a, now, tz)
   if a.minutes then return now + math.floor(a.minutes * 60) end
   local h, m = a.at:match("^(%d+):(%d+)$")
   local day = now + tz - (now + tz) % 86400
   local t = day + tonumber(h) * 3600 + tonumber(m) * 60 - tz
   if t <= now then t = t + 86400 end
   if t - now > M.CURTAIN_MAX_MINUTES * 60 then
      return nil, a.at .. " is more than " .. M.CURTAIN_MAX_MINUTES / 60 .. " hours away"
   end
   return t
end

function M.muted(mute_until, now) return mute_until ~= nil and mute_until > now end

-- Case-blind substring match for finding an element by its visible text.
function M.matches(needle, hay)
   return type(hay) == "string" and hay:lower():find(needle:lower(), 1, true) ~= nil
end

function M.center(r) return { x = r.x + r.w / 2, y = r.y + r.h / 2 } end

-- An arrow that points at r from the side of the screen f with the most room, so it never starts
-- off screen. Returns the tail, the tip (just outside r) and the two back corners of the head.
M.ARROW_LENGTH = 160
M.ARROW_GAP = 8
M.HEAD = 26
function M.arrow(r, f)
   local c = M.center(r)
   local room = {
      { dx = -1, dy = 0, n = r.x - f.x },
      { dx = 1, dy = 0, n = f.x + f.w - (r.x + r.w) },
      { dx = 0, dy = -1, n = r.y - f.y },
      { dx = 0, dy = 1, n = f.y + f.h - (r.y + r.h) },
   }
   local best = room[1]
   for i = 2, 4 do if room[i].n > best.n then best = room[i] end end
   local tip = { x = c.x + best.dx * (r.w / 2 + M.ARROW_GAP), y = c.y + best.dy * (r.h / 2 + M.ARROW_GAP) }
   -- No room on any side (a maximised window): point down at its middle from inside it instead.
   if best.n < M.ARROW_GAP + M.HEAD + 50 then
      best = { dx = 0, dy = -1, n = r.h / 2 }
      tip = { x = c.x, y = c.y }
   end
   -- Shorter than ARROW_LENGTH when that side is narrow, but never into the screen edge.
   local len = math.max(40, math.min(M.ARROW_LENGTH, best.n - M.ARROW_GAP - 10))
   local tail = { x = tip.x + best.dx * len, y = tip.y + best.dy * len }
   -- The head's back corners: HEAD back along the shaft, HEAD * 0.6 to each side.
   local bx, by = tip.x + best.dx * M.HEAD, tip.y + best.dy * M.HEAD
   local px, py = -best.dy * M.HEAD * 0.6, best.dx * M.HEAD * 0.6
   return { tail = tail, tip = tip, left = { x = bx + px, y = by + py }, right = { x = bx - px, y = by - py },
            side = best }
end

-- Whether p is within pad of rectangle r.
function M.inside(p, r, pad)
   pad = pad or 0
   return p.x >= r.x - pad and p.x <= r.x + r.w + pad and p.y >= r.y - pad and p.y <= r.y + r.h + pad
end

-- Whether a focus has done its job: the pointer is on the target (within REACH_PAD) and was brought
-- there, at least REACH_MOVE from where it started. A pointer that starts inside a big target (a whole
-- window) still counts once the owner moves it, rather than leaving the screen dark until it expires.
M.REACH_PAD = 4
M.REACH_MOVE = 30
function M.reached(start, p, r)
   if not M.inside(p, r, M.REACH_PAD) then return false end
   local dx, dy = p.x - start.x, p.y - start.y
   return not M.inside(start, r, M.REACH_PAD) or dx * dx + dy * dy >= M.REACH_MOVE * M.REACH_MOVE
end

-- The line a focus draws from the pointer to the target: it leaves the lit circle round the pointer
-- (radius) and stops just outside r, with the head's back corners. nil when the pointer is already
-- at the target or the gap is too short to draw.
M.TRAIL_HEAD = 18
function M.trail(p, r, radius)
   local c = M.center(r)
   local dx, dy = c.x - p.x, c.y - p.y
   local d = math.sqrt(dx * dx + dy * dy)
   if d == 0 or M.inside(p, r, M.ARROW_GAP) then return nil end
   local ux, uy = dx / d, dy / d
   -- Where the line meets r's outline, ARROW_GAP out: the nearer of its vertical and horizontal sides.
   local hw, hh = r.w / 2 + M.ARROW_GAP, r.h / 2 + M.ARROW_GAP
   local tx = ux ~= 0 and hw / math.abs(ux) or math.huge
   local ty = uy ~= 0 and hh / math.abs(uy) or math.huge
   local toEdge = d - math.min(tx, ty)
   local from = radius
   if toEdge - from < M.TRAIL_HEAD * 1.5 then return nil end
   local tip = { x = p.x + ux * toEdge, y = p.y + uy * toEdge }
   local bx, by = tip.x - ux * M.TRAIL_HEAD, tip.y - uy * M.TRAIL_HEAD
   local px, py = -uy * M.TRAIL_HEAD * 0.6, ux * M.TRAIL_HEAD * 0.6
   return { tail = { x = p.x + ux * from, y = p.y + uy * from }, tip = tip, neck = { x = bx, y = by },
            left = { x = bx + px, y = by + py }, right = { x = bx - px, y = by - py } }
end

-- Corner brackets round r, pad out: four L-shapes of arm length n (never more than a third of a side),
-- each three points running along one edge, round the corner, and down the other.
function M.brackets(r, pad, n)
   local x1, y1, x2, y2 = r.x - pad, r.y - pad, r.x + r.w + pad, r.y + r.h + pad
   local ax = math.min(n, (x2 - x1) / 3)
   local ay = math.min(n, (y2 - y1) / 3)
   return {
      { { x = x1 + ax, y = y1 }, { x = x1, y = y1 }, { x = x1, y = y1 + ay } },
      { { x = x2 - ax, y = y1 }, { x = x2, y = y1 }, { x = x2, y = y1 + ay } },
      { { x = x1 + ax, y = y2 }, { x = x1, y = y2 }, { x = x1, y = y2 - ay } },
      { { x = x2 - ax, y = y2 }, { x = x2, y = y2 }, { x = x2, y = y2 - ay } },
   }
end

-- A pointer-shaped outline of height s with its tip at p, for "click exactly here". It leans the
-- way the system pointer does, so it reads as "a pointer goes here" rather than as an arrow.
function M.cursor(p, s)
   local k = s / 22
   local pts = { { 0, 0 }, { 0, 17 }, { 4.5, 13 }, { 7.5, 20 }, { 10.5, 18.7 }, { 7.5, 12 }, { 13, 12 } }
   local out = {}
   for i, q in ipairs(pts) do out[i] = { x = p.x + q[1] * k, y = p.y + q[2] * k } end
   return out
end

-- The intros auto plays, from the pointer p to target r on screens (frames). On another screen the
-- question is "which monitor?" first, then "where on it?"; far away on the same screen, a spark from
-- the hand and a ring closing on the spot; close by, the ring alone; right there, nothing.
M.NEAR = 150
M.FAR = 800
function M.intro_for(p, r, screens)
   local c = M.center(r)
   if M.screen_of(screens, p) ~= M.screen_of(screens, c) then return { "halo", "comet" } end
   if M.inside(p, r, M.NEAR) then return {} end
   local dx, dy = c.x - p.x, c.y - p.y
   if math.sqrt(dx * dx + dy * dy) > M.FAR then return { "comet", "iris" } end
   return { "iris" }
end

-- Fast at first and settling at the end, so a movement reads as arriving rather than stopping.
function M.ease(t)
   t = math.max(0, math.min(1, t))
   return 1 - (1 - t) ^ 3
end

-- n thin wedges from point c, turned by angle (radians), each len long and 2 * far wide at its end:
-- whichever way the eye is, one passes near it and leads back to c.
function M.rays(c, n, angle, len, far)
   local out = {}
   for i = 0, n - 1 do
      local a = angle + i * 2 * math.pi / n
      local ux, uy = math.cos(a), math.sin(a)
      local ex, ey = c.x + ux * len, c.y + uy * len
      out[#out + 1] = { { x = c.x, y = c.y }, { x = ex - uy * far, y = ey + ux * far },
                        { x = ex + uy * far, y = ey - ux * far } }
   end
   return out
end

-- Where a step's numbered badge sits: on r's top-left corner, pulled inside the screen f so a target
-- at the edge still shows its number.
M.BADGE = 30
function M.badge(r, f)
   local half = M.BADGE / 2
   local x = math.max(f.x + half + 2, math.min(f.x + f.w - half - 2, r.x))
   local y = math.max(f.y + half + 2, math.min(f.y + f.h - half - 2, r.y))
   return { x = x, y = y }
end

-- Where a w×h box goes on screen f: centred, at the top or bottom, or beside target rect r
-- (below it, else above it), kept inside the screen.
function M.box(position, w, h, f, r)
   local x, y = f.x + (f.w - w) / 2, f.y + (f.h - h) / 2
   if position == "top" then y = f.y + f.h * 0.08
   elseif position == "bottom" then y = f.y + f.h * 0.92 - h
   elseif position == "near" and r then
      x = r.x + r.w / 2 - w / 2
      y = (r.y + r.h + 16 + h <= f.y + f.h) and (r.y + r.h + 16) or (r.y - 16 - h)
   end
   x = math.max(f.x + 8, math.min(f.x + f.w - w - 8, x))
   y = math.max(f.y + 8, math.min(f.y + f.h - h - 8, y))
   return { x = x, y = y, w = w, h = h }
end

-- The screen frame of the list that holds point p, else the first.
function M.screen_of(frames, p)
   for _, f in ipairs(frames) do
      if p.x >= f.x and p.x < f.x + f.w and p.y >= f.y and p.y < f.y + f.h then return f end
   end
   return frames[1]
end

-- The part of r inside f, or nil when they do not overlap: a spotlight hole is cut per screen.
function M.clip(r, f)
   local x1, y1 = math.max(r.x, f.x), math.max(r.y, f.y)
   local x2, y2 = math.min(r.x + r.w, f.x + f.w), math.min(r.y + r.h, f.y + f.h)
   if x2 <= x1 or y2 <= y1 then return nil end
   return { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end

return M
