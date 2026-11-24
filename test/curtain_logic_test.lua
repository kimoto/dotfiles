-- The Curtain spoon's rules (hammerspoon/Spoons/Curtain.spoon/logic.lua) in plain Lua, no Hammerspoon.
-- Run from the repo root: luajit test/curtain_logic_test.lua (test/curtain_logic.bats does).
local L = dofile("hammerspoon/Spoons/Curtain.spoon/logic.lua")
local fails = 0
local function eq(name, got, want)
   if got ~= want then
      fails = fails + 1
      print("FAIL " .. name .. ": got " .. tostring(got) .. ", want " .. tostring(want))
   end
end

eq("no deadline", L.decide({}, 100, 0), nil)
eq("before deadline", L.decide({ deadline = 200 }, 100, 0), nil)
eq("deadline reached", L.decide({ deadline = 100 }, 100, 0), "show")
eq("already shown", L.decide({ deadline = 100, shown = true }, 150, 0), nil)
eq("snoozed", L.decide({ deadline = 100, snooze_until = 400 }, 300, 0), nil)
eq("snooze over", L.decide({ deadline = 100, snooze_until = 400 }, 400, 0), "show")
eq("walked away", L.decide({ deadline = 100, shown = true }, 1000, L.GONE_SECONDS), "clear")
eq("idle since before the deadline still shows", L.decide({ deadline = 1000 }, 1000, L.GONE_SECONDS), "show")
eq("next morning after the lid was closed",
   L.decide({ deadline = 100, shown = true }, 100 + L.STALE_SECONDS, 0), "clear")
eq("deadline moved later while shown", L.decide({ deadline = 500, shown = true }, 100, 0), "hide")

local TZ = 9 * 3600
-- 2026-11-22 00:00 in a UTC+9 zone: midnight UTC of that date, less nine hours
local now = 1795305600 - TZ
local nine = L.parse_time("09:00", now, TZ)
eq("09:00 today", nine - now, 9 * 3600)
eq("0900 form", L.parse_time("0900", now, TZ), nine)
eq("past time is tomorrow", L.parse_time("00:00", now + 60, TZ) - now, 86400)
eq("bad hour", L.parse_time("25:00", now, TZ), nil)
eq("junk", L.parse_time("soon", now, TZ), nil)

local sl = L.slots(nine + 7 * 60, TZ, 3) -- 09:07
eq("first slot 09:30", sl[1] - nine, 30 * 60)
eq("slots every 30 min", sl[3] - sl[1], 3600)
eq("too close skipped", L.slots(nine + 25 * 60, TZ, 1)[1] - nine, 3600) -- 09:25 -> 10:00
eq("on the mark", L.slots(nine, TZ, 1)[1] - nine, 30 * 60)
eq("left minutes", L.left(0, 7 * 60 + 30), "7分")
eq("left hours", L.left(0, 2 * 3600 + 5 * 60), "2時間5分")
eq("left whole hour", L.left(0, 3600), "1時間")
eq("left under a minute", L.left(0, 30), "1分未満")

local nine07 = nine + 7 * 60
local all = L.time_choices(nine07, TZ, "")
eq("picker starts at next 10-min mark 5+ min ahead", all[1] - nine, 20 * 60)
eq("picker spans 14 hours", #all, 83) -- 09:20 … 23:00
local function first(now, q) local r = L.time_choices(now, TZ, q); return r[1] and (r[1] - nine) end
eq("123 is 12:30 first", first(nine07, "123"), 3 * 3600 + 30 * 60)
eq("1245 off the mark", first(nine07, "12:45"), 3 * 3600 + 45 * 60)
eq("945 is 9:45", first(nine07, "945"), 45 * 60)
eq("10 late at night is tomorrow 10:00, not 1:00", first(nine + 13 * 3600, "10"), 25 * 3600)
eq("1:23 with a colon beats 12:3x", first(nine - 9 * 3600, "1:23"), -9 * 3600 + 83 * 60)
eq("a time just passed is not tomorrow", first(nine07, "0906"), nil)
eq("the time now is not offered", first(nine07, "0907"), nil)
eq("4 minutes ahead is not offered", first(nine07, "0911"), nil)
eq("at most PICK_MAX rows", #L.time_choices(nine07, TZ, "1"), L.PICK_MAX)

local evening = now + 22 * 3600 -- 22:00
eq("daily end: midnight tonight", L.daily_end(evening, TZ, "00:00") - evening, 2 * 3600)
eq("daily end: a removed end does not come back", L.daily_end(evening, TZ, "00:00", evening + 2 * 3600), nil)
eq("daily end: not more than 14 hours ahead", L.daily_end(now + 9 * 3600, TZ, "00:00"), nil) -- 09:00 -> 15 h
eq("daily end: junk", L.daily_end(evening, TZ, "soon"), nil)
-- evening is Sunday 22:00; the next day is Monday
local monAfternoon = now + 86400 + 15 * 3600 -- Monday 15:00
local two = "weekday 19:45\ndaily 23:45"
eq("ends: the weekday end first on a weekday", L.daily_ends(monAfternoon, TZ, two) - monAfternoon, 4 * 3600 + 45 * 60)
eq("ends: then the night end", L.daily_ends(monAfternoon + 5 * 3600, TZ, two) - monAfternoon, 8 * 3600 + 45 * 60)
eq("ends: no weekday end on Sunday", L.daily_ends(now + 15 * 3600, TZ, two) - (now + 15 * 3600), 8 * 3600 + 45 * 60)
eq("one night end every day", L.daily_ends(evening, TZ, "daily 23:45") - evening, 3600 + 45 * 60)
eq("no weekday line, no weekday end", L.daily_ends(monAfternoon, TZ, "daily 23:45") - monAfternoon, 8 * 3600 + 45 * 60)
eq("an empty file turns the ends off", L.daily_ends(evening, TZ, ""), nil)
eq("ends: bare time is daily", L.daily_ends(evening, TZ, "00:00") - evening, 2 * 3600)
eq("ends: removed end skipped, next one used",
   L.daily_ends(monAfternoon, TZ, two, monAfternoon + 4 * 3600 + 45 * 60) - monAfternoon, 8 * 3600 + 45 * 60)
eq("ends: empty", L.daily_ends(evening, TZ, ""), nil)

-- pause and resume
local T0 = 1000000
eq("pause: a chosen end still to come", L.can_pause({ deadline = T0 + 600 }, T0), true)
eq("pause: not an automatic end", L.can_pause({ deadline = T0 + 600, from = "daily" }, T0), false)
eq("pause: not once it came", L.can_pause({ deadline = T0 - 1 }, T0), false)
eq("pause: not while shown", L.can_pause({ deadline = T0 + 600, shown = true }, T0), false)
eq("pause: nothing set", L.can_pause({}, T0), false)
eq("resume: no end set -> now + left", L.resume_plan({}, T0, 360), T0 + 360)
eq("resume: a later automatic end is replaced",
   L.resume_plan({ deadline = T0 + 3600, from = "daily" }, T0, 360), T0 + 360)
eq("resume: a sooner automatic end is replaced too, as a chosen time would",
   L.resume_plan({ deadline = T0 + 60, from = "daily" }, T0, 360), T0 + 360)
eq("resume: waits while an end has come (up or snoozed)",
   L.resume_plan({ deadline = T0 - 60, from = "daily" }, T0, 360), "wait")

-- the menu bar's remaining-time bar
eq("bar: full at the start", L.bar(T0, T0, T0 + 600, 6), "▰▰▰▰▰▰")
eq("bar: half way", L.bar(T0 + 300, T0, T0 + 600, 6), "▰▰▰▱▱▱")
eq("bar: a little left still shows one cell", L.bar(T0 + 590, T0, T0 + 600, 6), "▰▱▱▱▱▱")
eq("bar: none when the end has come", L.bar(T0 + 600, T0, T0 + 600, 6), nil)
eq("bar: none without a start", L.bar(T0, nil, T0 + 600, 6), nil)
eq("bar: a start after now counts as now", L.bar(T0, T0 + 60, T0 + 600, 6), "▰▰▰▰▰▰")

-- the menu bar's countdown, to the second
eq("countdown: minutes and seconds", L.countdown(T0, T0 + 754), "12:34")
eq("countdown: seconds keep their zero", L.countdown(T0, T0 + 65), "1:05")
eq("countdown: under a minute", L.countdown(T0, T0 + 9), "0:09")
eq("countdown: an hour or more shows hours", L.countdown(T0, T0 + 3723), "1:02:03")
eq("countdown: never below zero", L.countdown(T0 + 5, T0), "0:00")

-- after the hold lifts the curtain, the Esc still held must not reach the app in front
eq("tap: curtain up swallows", L.tap_action(true, false, true, false), "swallow")
eq("tap: still held after the lift is swallowed", L.tap_action(false, true, true, false), "swallow")
eq("tap: the release after the lift is swallowed, then the tap stops",
   L.tap_action(false, true, true, true), "swallow_stop")
eq("tap: other keys after the lift pass", L.tap_action(false, true, false, false), "pass")
eq("tap: nothing held, nothing swallowed", L.tap_action(false, false, true, true), "pass")

-- the ring shown while Esc is held: the share of the hold still to go, and whole seconds left
local f, n = L.hold_left(0, 5); eq("hold: full ring at the press", f, 1); eq("hold: all seconds left", n, 5)
f, n = L.hold_left(2.5, 5); eq("hold: half the ring half way", f, 0.5); eq("hold: seconds round up", n, 3)
f, n = L.hold_left(4.99, 5); eq("hold: one second shown until the end", n, 1)
f, n = L.hold_left(6, 5); eq("hold: ring never below empty", f, 0); eq("hold: seconds never below zero", n, 0)

if fails > 0 then os.exit(1) end
print("ok")
