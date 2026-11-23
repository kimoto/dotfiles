-- What the curtain should do at a given moment, kept apart from Hammerspoon so
-- it can be tested with plain Lua (test/curtain_logic_test.lua at the repo root).
-- tz everywhere: seconds the owner's clock is ahead of UTC, whatever zone the Mac is in.
local M = {}

-- Esc must be held this long to lift the curtain, so a reflex press is not enough.
M.HOLD_SECONDS = 5
-- A lifted curtain comes back after this, if the Mac is still in use.
M.SNOOZE_SECONDS = 5 * 60
-- Idle this long, counted from the deadline, means the owner walked away: the
-- deadline is done. Idle that began before the deadline (a video watched
-- without touching the keys) does not count, so the curtain still comes up.
M.GONE_SECONDS = 10 * 60

-- A deadline older than this belongs to an earlier sitting: dropped on load and
-- cleared when met, since a closed lid stops the idle count from ever reaching GONE.
M.STALE_SECONDS = 3 * 3600

-- s: { deadline = epoch|nil, snooze_until = epoch|nil, shown = bool }
-- Returns "show", "hide", "clear" (forget the deadline and hide) or nil.
function M.decide(s, now, idle)
   if not s.deadline or now < s.deadline then
      return s.shown and "hide" or nil
   end
   if now - s.deadline >= M.STALE_SECONDS then return "clear" end
   if idle >= M.GONE_SECONDS and now - idle >= s.deadline then return "clear" end
   if s.shown then return nil end
   if s.snooze_until and now < s.snooze_until then return nil end
   return "show"
end

-- "12:30" or "1230" to the next such time after now (tomorrow if already past).
function M.parse_time(text, now, tz)
   local h, m = (text or ""):match("^%s*(%d%d?):?(%d%d)%s*$")
   h, m = tonumber(h), tonumber(m)
   if not h or h > 23 or m > 59 then return nil end
   local local_now = now + tz
   local day_start = local_now - local_now % 86400
   local t = day_start + h * 3600 + m * 60
   if t <= local_now then t = t + 86400 end
   return t - tz
end

-- The next n half-hour marks after now, at least 10 minutes ahead so a pick is
-- never one that fires straight away. Epochs, for the "この時刻に" menu.
function M.slots(now, tz, n)
   local out, t = {}, now + 10 * 60
   t = t - (t + tz) % 1800 + 1800
   if (t - now) - 1800 >= 10 * 60 then t = t - 1800 end
   for i = 1, n do out[i] = t + (i - 1) * 1800 end
   return out
end

-- "2時間5分" / "7分" / "1分未満" until the deadline, for the menu bar.
function M.left(now, deadline)
   local m = math.floor((deadline - now) / 60)
   if m < 1 then return "1分未満" end
   if m < 60 then return m .. "分" end
   return math.floor(m / 60) .. "時間" .. (m % 60 > 0 and (m % 60 .. "分") or "")
end

-- Time left to the second, "12:34" or "1:02:03", for the menu bar's countdown.
function M.countdown(now, deadline)
   local left = math.max(0, deadline - now)
   local h, m, sec = math.floor(left / 3600), math.floor(left % 3600 / 60), left % 60
   if h > 0 then return string.format("%d:%02d:%02d", h, m, sec) end
   return string.format("%d:%02d", m, sec)
end

-- Times offered by the "ほかの時刻" picker, at least 5 minutes ahead and less
-- than 14 hours, so a mistyped time cannot set tomorrow. With no query: every
-- 10 minutes. With digits: every minute whose "HHMM" starts with them, then
-- those whose "HMM" (hour without its zero) does, 10-minute marks first in
-- each, at most 40. So "10" is 10:xx, "123" is 12:3x then 1:23, "945" is 9:45.
-- A time with a colon ("1:23") is taken as that time and comes first.
M.PICK_MAX = 40
function M.time_choices(now, tz, query)
   local q = (query or ""):gsub("%D", "")
   local first = now + 5 * 60
   if q == "" then
      local out, t = {}, first - (first + tz) % 600
      if t < first then t = t + 600 end
      while t < now + 14 * 3600 do out[#out + 1] = t; t = t + 600 end
      return out
   end
   local buckets = { {}, {}, {}, {} } -- HHMM mark, HHMM other, HMM mark, HMM other
   local t = first - (first + tz) % 60
   if t < first then t = t + 60 end
   while t < now + 14 * 3600 do
      local hhmm = os.date("!%H%M", t + tz)
      local mark = (t + tz) % 600 == 0 and 0 or 1
      if hhmm:sub(1, #q) == q then
         table.insert(buckets[1 + mark], t)
      elseif hhmm:sub(1, 1) == "0" and hhmm:sub(2, 1 + #q) == q then
         table.insert(buckets[3 + mark], t)
      end
      t = t + 60
   end
   local out = {}
   local exact = (query or ""):find("%d:%d%d") and M.parse_time(query, now, tz)
   if exact and exact >= first and exact < now + 14 * 3600 then out[1] = exact end
   for _, b in ipairs(buckets) do
      for _, x in ipairs(b) do
         if #out < M.PICK_MAX and x ~= out[1] then out[#out + 1] = x end
      end
   end
   return out
end

-- A fixed end every night ("HH:MM"): the next such time, if at least a minute and
-- under 14 hours away and later than skip (an end the owner removed). So a late start does not
-- stretch the evening: the end stays where it is whatever time the evening started.
function M.daily_end(now, tz, hhmm, skip)
   local t = M.parse_time(hhmm, now, tz)
   if not t then return nil end
   if t < now + 60 or t >= now + 14 * 3600 or t <= (skip or 0) then return nil end
   return t
end

-- Several fixed ends (the daily-end file, one per line): "daily HH:MM", "weekday HH:MM" or
-- "weekend HH:MM"; a bare "HH:MM" is daily. So a weekday can have an afternoon end and the end of
-- the night both. A weekday/weekend line counts by the owner's day the end falls on. Returns the
-- earliest one daily_end accepts.
function M.daily_ends(now, tz, conf, skip)
   local best
   for line in (conf or ""):gmatch("[^\n]+") do
      local kind, hhmm = line:match("^%s*(%a+)%s+(%S+)%s*$")
      if not kind then kind, hhmm = "daily", line:match("^%s*(%S+)%s*$") end
      local t = hhmm and M.daily_end(now, tz, hhmm, skip)
      if t then
         local wday = os.date("!*t", t + tz).wday
         local weekend = wday == 1 or wday == 7
         local ok = kind == "daily" or (kind == "weekday" and not weekend) or (kind == "weekend" and weekend)
         if ok and (not best or t < best) then best = t end
      end
   end
   return best
end

-- Ends the curtain set by itself (from = "daily" or a name the config adds), rather than
-- the owner deciding: removing one on purpose remembers it as skipped, and it cannot be paused.
function M.auto_from(from)
   return from ~= nil and from ~= ""
end

-- Pause (⏸) is for an end the owner chose, before it comes: an automatic end is not
-- a countdown the owner started, and one that came is the curtain's business, lifted only by Esc.
function M.can_pause(s, now)
   return s.deadline ~= nil and s.deadline > now and not s.shown and not s.from
end

-- Resume (▶) with `left` seconds: the new end, or "wait" while an end has come (the curtain is up
-- or snoozed). The paused end was chosen, so like any chosen time it replaces an automatic end
-- armed meanwhile, sooner or later.
function M.resume_plan(s, now, left)
   if s.deadline and s.deadline <= now then return "wait" end
   return now + left
end

-- The share of the countdown left, as `cells` cells for the menu bar (▰ left, ▱ gone): the owner
-- wanted to see it as a proportion. Rounded up, so the last cell stays until the end comes.
function M.bar(now, start, deadline, cells)
   if not start or not deadline or now >= deadline then return nil end
   if start > now then start = now end
   local total = deadline - start
   if total <= 0 then return nil end
   local full = math.ceil((deadline - now) / total * cells)
   if full > cells then full = cells end
   return string.rep("▰", full) .. string.rep("▱", cells - full)
end

-- What the key tap does with one event. While the curtain is up it eats everything.
-- Once a held Esc has lifted it, the same Esc is still down: its repeats and its
-- release would land in the app in front, so they are eaten too, and the release ends that.
function M.tap_action(shown, draining, is_esc, is_up)
   if shown then return "swallow" end
   if not (draining and is_esc) then return "pass" end
   if is_up then return "swallow_stop" end
   return "swallow"
end

-- How long after the lift a still-held Esc is eaten at most, in case its release never arrives.
M.DRAIN_SECONDS = 10

return M
