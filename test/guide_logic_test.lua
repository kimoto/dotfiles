-- The Guide spoon's rules (hammerspoon/Spoons/Guide.spoon/logic.lua) in plain Lua, no Hammerspoon.
-- Run from the repo root: luajit test/guide_logic_test.lua (test/guide.bats does).
local L = dofile("hammerspoon/Spoons/Guide.spoon/logic.lua")
local fails = 0
local function eq(name, got, want)
   if got ~= want then
      fails = fails + 1
      print("FAIL " .. name .. ": got " .. tostring(got) .. ", want " .. tostring(want))
   end
end
local function refused(name, cmd, args)
   local out, err = L.validate(cmd, args)
   if out ~= nil or type(err) ~= "string" then
      fails = fails + 1
      print("FAIL " .. name .. ": was accepted")
   end
end

-- Requests: only a POST from this machine, with the token, and not from a web page.
local H = { Host = "127.0.0.1:4777", ["X-Guide-Token"] = "abc" }
eq("request: accepted", L.check_request("POST", H, "abc", 4777), nil)
eq("request: header names in any case", L.check_request("POST", { host = "localhost:4777", ["x-guide-token"] = "abc" },
   "abc", 4777), nil)
eq("request: GET refused", L.check_request("GET", H, "abc", 4777), 405)
eq("request: wrong token", L.check_request("POST", { Host = "127.0.0.1:4777", ["X-Guide-Token"] = "abX" },
   "abc", 4777), 401)
eq("request: no token", L.check_request("POST", { Host = "127.0.0.1:4777" }, "abc", 4777), 401)
eq("request: a token one byte short", L.check_request("POST", { Host = "127.0.0.1:4777", ["X-Guide-Token"] = "ab" },
   "abc", 4777), 401)
eq("request: from a browser", L.check_request("POST",
   { Host = "127.0.0.1:4777", ["X-Guide-Token"] = "abc", Origin = "https://example.com" }, "abc", 4777), 403)
eq("request: rebound host name", L.check_request("POST", { Host = "evil.example:4777", ["X-Guide-Token"] = "abc" },
   "abc", 4777), 403)

-- Commands: a fixed list, nothing else.
refused("unknown command", "eval", { code = "hs.reload()" })
refused("no lifting the curtain", "lift", {})
refused("no clearing the curtain's end", "curtain_clear", {})

-- Every overlay ends on its own.
eq("message: default seconds", L.validate("message", { text = "hi" }).seconds, 60)
eq("message: capped", L.validate("message", { text = "hi", seconds = 99999 }).seconds, 600)
eq("spotlight: capped at 30 minutes", L.validate("spotlight", { app = "Safari", seconds = 7200 }).seconds, 1800)
refused("seconds: zero", "arrow", { target = { x = 1, y = 2 }, seconds = 0 })
refused("seconds: not a number", "arrow", { target = { x = 1, y = 2 }, seconds = "5" })
refused("seconds: NaN", "arrow", { target = { x = 1, y = 2 }, seconds = 0 / 0 })

eq("message: centred by default", L.validate("message", { text = "hi" }).position, "center")
eq("message: near a target by default", L.validate("message", { text = "hi", target = { app = "Mail" } }).position,
   "near")
refused("message: near needs a target", "message", { text = "hi", position = "near" })
refused("message: blank", "message", { text = "   " })
refused("message: odd position", "message", { text = "hi", position = "left" })
eq("message: long text cut", #L.validate("message", { text = string.rep("a", 1000) }).text, L.MAX_TEXT + #"…")
eq("truncate: never splits a character", L.truncate("あいう", 4), "あ…")
eq("truncate: short text untouched", L.truncate("あい", 6), "あい")

eq("ask: two choices", #L.validate("ask", { text = "q", choices = { "a", "b" } }).choices, 2)
refused("ask: one choice", "ask", { text = "q", choices = { "a" } })
refused("ask: five choices", "ask", { text = "q", choices = { "1", "2", "3", "4", "5" } })
refused("ask: a blank choice", "ask", { text = "q", choices = { "a", "" } })

eq("target: an app", L.validate("arrow", { target = { app = "Mail" } }).target.kind, "app")
eq("target: an element by its text", L.validate("arrow", { target = { app = "Mail", text = "Send" } }).target.text,
   "Send")
eq("target: a point", L.validate("arrow", { target = { x = 5, y = 6 } }).target.kind, "point")
eq("target: a rectangle", L.validate("highlight", { target = { x = 5, y = 6, w = 7, h = 8 } }).target.kind, "rect")
refused("target: none", "arrow", {})
refused("target: empty rectangle", "highlight", { target = { x = 5, y = 6, w = 0, h = 8 } })
refused("target: half a rectangle", "highlight", { target = { x = 5, y = 6, w = 3 } })

eq("spotlight: default dim", L.validate("spotlight", { app = "Mail" }).dim, 0.85)
eq("spotlight: dim never fully black", L.validate("spotlight", { app = "Mail", dim = 1 }).dim, 0.97)
eq("spotlight: dim never too faint", L.validate("spotlight", { app = "Mail", dim = 0 }).dim, 0.3)
refused("spotlight: no app", "spotlight", {})

-- The curtain: an AI may set an end, within limits, and only when the owner is not deciding.
eq("curtain: minutes", L.validate("curtain", { minutes = 15 }).minutes, 15)
eq("curtain: now", L.validate("curtain", { minutes = 0 }).minutes, 0)
refused("curtain: negative", "curtain", { minutes = -1 })
refused("curtain: too far", "curtain", { minutes = 15 * 60 })
eq("curtain: at", L.validate("curtain", { at = "18:30" }).at, "18:30")
refused("curtain: bad time", "curtain", { at = "25:00" })
refused("curtain: neither", "curtain", {})

local now = 1700000000
eq("refusal: none", L.curtain_refusal({ shown = false }, now), nil)
eq("refusal: no curtain", type(L.curtain_refusal(nil, now)), "string")
eq("refusal: up", type(L.curtain_refusal({ shown = true }, now)), "string")
eq("refusal: just lifted", type(L.curtain_refusal({ snooze_until = now + 60 }, now)), "string")
eq("refusal: snooze over", L.curtain_refusal({ snooze_until = now - 1 }, now), nil)
eq("refusal: paused", type(L.curtain_refusal({ paused = 300 }, now)), "string")

eq("sooner: no end yet", L.curtain_later({}, now + 60), nil)
eq("sooner: before the end", L.curtain_later({ deadline = now + 600 }, now + 60), nil)
eq("sooner: never later", type(L.curtain_later({ deadline = now + 600 }, now + 900)), "string")
eq("sooner: not the same end again", type(L.curtain_later({ deadline = now + 600 }, now + 600)), "string")
eq("under the curtain: status", L.UNDER_CURTAIN.status, true)
eq("under the curtain: no spotlight", L.UNDER_CURTAIN.spotlight, nil)
eq("under the curtain: no message", L.UNDER_CURTAIN.message, nil)

local tz = 9 * 3600
-- 1700000000 is 2023-11-15 07:13:20 at +09:00.
eq("end: in minutes", L.curtain_end({ minutes = 10 }, now, tz), now + 600)
eq("end: later today", L.curtain_end({ at = "08:00" }, now, tz), now + 46 * 60 + 40)
eq("end: past today means tomorrow, if close", L.curtain_end({ at = "07:00" }, now, tz), nil)
eq("end: a few minutes later today", L.curtain_end({ at = "07:20" }, now, tz), now + 400)
eq("end: past today, so tomorrow morning", L.curtain_end({ at = "08:00" }, now + 16 * 3600, tz) - (now + 16 * 3600),
   (8 * 60 + 47) * 60 - 20)
eq("end: just after midnight", L.curtain_end({ at = "00:30" }, now + 16 * 3600, tz) - (now + 16 * 3600),
   (24 * 60 + 30 - (23 * 60 + 13)) * 60 - 20)

-- 1700000000 is 2023-11-14T22:13:20 UTC.
eq("since: the curtain's stamp", L.since("2023-11-14T22:13:20", now), 0)
eq("since: across a month and a leap day", L.since("2024-03-01T00:00:00", 1709251200), 0)
eq("since: no stamp", L.since("", now), nil)
eq("owner: just decided", type(L.owner_deciding("2023-11-14T22:10:00", now)), "string")
eq("owner: long ago", L.owner_deciding("2023-11-14T21:00:00", now), nil)
eq("owner: never", L.owner_deciding("", now), nil)

eq("muted", L.muted(now + 1, now), true)
eq("not muted", L.muted(nil, now), false)
eq("mute over", L.muted(now, now), false)

eq("match: case-blind", L.matches("send", "Send Now"), true)
eq("match: literal, not a pattern", L.matches("a.b", "axb"), false)
eq("match: no text", L.matches("x", nil), false)

-- Arrows start on the side with the most room and point just outside the target.
local F = { x = 0, y = 0, w = 1000, h = 800 }
local a = L.arrow({ x = 50, y = 380, w = 40, h = 40 }, F)
eq("arrow: from the right of a target at the left edge", a.side.dx, 1)
eq("arrow: tip outside the target", a.tip.x, 90 + L.ARROW_GAP)
eq("arrow: tail further right", a.tail.x > a.tip.x, true)
eq("arrow: shaft is level", a.tail.y, 400)
a = L.arrow({ x = 480, y = 700, w = 40, h = 40 }, F)
eq("arrow: from above a target at the bottom", a.side.dy, -1)
eq("arrow: tail on screen", a.tail.y >= 0, true)
eq("arrow: head corners either side", a.left.x ~= a.right.x, true)

a = L.arrow({ x = 0, y = 0, w = 1000, h = 800 }, F)
eq("arrow: a full-screen target, from inside", a.tip.x, 500)
eq("arrow: inside, tail above the tip and on screen", a.tail.y < a.tip.y and a.tail.y >= 0, true)

local b = L.box("near", 300, 100, F, { x = 900, y = 750, w = 50, h = 40 })
eq("box: kept inside on the right", b.x + b.w <= F.w - 8, true)
eq("box: above a target at the bottom", b.y + b.h <= 750, true)
eq("box: centred", L.box("center", 200, 100, F).x, 400)

eq("screen of: second screen", L.screen_of({ F, { x = 1000, y = 0, w = 500, h = 500 } }, { x = 1200, y = 10 }).x, 1000)
eq("screen of: off every screen", L.screen_of({ F }, { x = -5, y = -5 }).x, 0)
eq("clip: inside", L.clip({ x = 10, y = 10, w = 5, h = 5 }, F).w, 5)
eq("clip: across the edge", L.clip({ x = 990, y = 10, w = 50, h = 5 }, F).w, 10)
eq("clip: outside", L.clip({ x = 1100, y = 10, w = 5, h = 5 }, F), nil)

if fails > 0 then os.exit(1) end
print("ok")
