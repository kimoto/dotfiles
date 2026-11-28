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

-- Styles: a fixed list, the box by default.
eq("style: box by default", L.validate("highlight", { target = { x = 5, y = 6 } }).style, "box")
eq("style: brackets", L.validate("highlight", { target = { x = 5, y = 6 }, style = "bracket" }).style, "bracket")
eq("style: on an arrow too", L.validate("arrow", { target = { x = 5, y = 6 }, style = "click" }).style, "click")
refused("style: unknown", "highlight", { target = { x = 5, y = 6 }, style = "sparkles" })

-- focus: two lit places in the dark, the pointer and the target.
local fo = L.validate("focus", { target = { x = 5, y = 6 } })
eq("focus: default dim", fo.dim, L.FOCUS_DIM)
eq("focus: default radius", fo.radius, L.RADIUS[2])
eq("focus: a trail by default", fo.trail, true)
eq("focus: short by default", fo.seconds, 30)
eq("focus: capped", L.validate("focus", { target = { x = 5, y = 6 }, seconds = 9999 }).seconds, 300)
eq("focus: no trail", L.validate("focus", { target = { x = 5, y = 6 }, trail = false }).trail, false)
eq("focus: radius kept on screen", L.validate("focus", { target = { x = 5, y = 6 }, radius = 5000 }).radius, 400)
eq("focus: radius never too small", L.validate("focus", { target = { x = 5, y = 6 }, radius = 1 }).radius, 60)
eq("focus: dim never black", L.validate("focus", { target = { x = 5, y = 6 }, dim = 1 }).dim, 0.97)
refused("focus: no target", "focus", {})
refused("focus: trail as text", "focus", { target = { x = 5, y = 6 }, trail = "yes" })

-- steps: a short numbered sequence.
local st = L.validate("steps",
   { steps = { { target = { x = 1, y = 2 }, label = "a" }, { target = { app = "Mail" } } } })
eq("steps: two", #st.steps, 2)
eq("steps: start at the first", st.current, 1)
eq("steps: labels kept", st.steps[1].label, "a")
eq("steps: all done", L.validate("steps", { steps = { { target = { x = 1, y = 2 } } }, current = 2 }).current, 2)
refused("steps: none", "steps", { steps = {} })
refused("steps: too many", "steps", { steps = { { target = { x = 1, y = 1 } }, { target = { x = 1, y = 1 } },
   { target = { x = 1, y = 1 } }, { target = { x = 1, y = 1 } }, { target = { x = 1, y = 1 } },
   { target = { x = 1, y = 1 } } } })
refused("steps: current past the end", "steps", { steps = { { target = { x = 1, y = 2 } } }, current = 3 })
refused("steps: current not whole", "steps", { steps = { { target = { x = 1, y = 2 } } }, current = 1.5 })
refused("steps: a step without a target", "steps", { steps = { { label = "a" } } })
refused("steps: two text searches", "steps", { steps = { { target = { app = "Mail", text = "a" } },
   { target = { app = "Mail", text = "b" } } } })

-- The trail leaves the pointer's circle and stops just outside the target.
local R = { x = 500, y = 380, w = 40, h = 40 }
local tr = L.trail({ x = 100, y = 400 }, R, 140)
eq("trail: starts at the circle's edge", tr.tail.x, 240)
eq("trail: stops outside the target", tr.tip.x, 500 - L.ARROW_GAP)
eq("trail: level when level", tr.tip.y, 400)
eq("trail: head behind the tip", tr.neck.x < tr.tip.x, true)
eq("trail: none once the pointer is there", L.trail({ x = 510, y = 400 }, R, 140), nil)
eq("trail: none when too short to draw", L.trail({ x = 470, y = 400 }, R, 20), nil)
tr = L.trail({ x = 480, y = 400 }, R, 140)
eq("trail: none when the pointer is just short of the target", tr, nil)
tr = L.trail({ x = 520, y = 100 }, R, 60)
eq("trail: from above, stops above the top side", tr.tip.y, 380 - L.ARROW_GAP)

eq("inside: within the pad", L.inside({ x = 495, y = 400 }, R, 8), true)
eq("inside: outside the pad", L.inside({ x = 480, y = 400 }, R, 8), false)

local br = L.brackets({ x = 100, y = 100, w = 300, h = 30 }, 6, 16)
eq("brackets: four corners", #br, 4)
eq("brackets: arm along the long side", br[1][1].x - br[1][2].x, 16)
eq("brackets: short side never fully closed", br[1][3].y - br[1][2].y, 14)
local narrow = L.brackets({ x = 100, y = 100, w = 18, h = 300 }, 6, 16)
eq("brackets: narrow target, arms a third of its width", narrow[2][2].x - narrow[2][1].x, 10)

local cu = L.cursor({ x = 50, y = 60 }, 22)
eq("cursor: tip on the point", cu[1].x == 50 and cu[1].y == 60, true)
eq("cursor: drawn below and right of it", cu[4].x > 50 and cu[4].y > 60, true)

eq("badge: on the corner", L.badge({ x = 300, y = 200, w = 10, h = 10 }, F).x, 300)
eq("badge: kept on screen", L.badge({ x = 0, y = 0, w = 10, h = 10 }, F).x, L.BADGE / 2 + 2)

-- Edges the first tests left open.
eq("steps: current 1 named", L.validate("steps", { steps = { { target = { x = 1, y = 2 } } }, current = 1 }).current, 1)
refused("steps: current 0", "steps", { steps = { { target = { x = 1, y = 2 } } }, current = 0 })
refused("steps: a step that is not an object", "steps", { steps = { "a" } })
local long = { steps = { { target = { x = 1, y = 2 }, label = string.rep("a", 200) } } }
eq("steps: long label cut", #L.validate("steps", long).steps[1].label, L.MAX_LABEL + #"…")
refused("focus: dim as text", "focus", { target = { x = 5, y = 6 }, dim = "dark" })
refused("focus: radius as text", "focus", { target = { x = 5, y = 6 }, radius = "big" })
eq("focus: dim never too faint", L.validate("focus", { target = { x = 5, y = 6 }, dim = 0 }).dim, 0.3)
eq("badge: kept on screen at the bottom right", L.badge({ x = 995, y = 795, w = 10, h = 10 }, F).x,
   F.w - L.BADGE / 2 - 2)
eq("badge: kept on screen at the top", L.badge({ x = 300, y = -20, w = 10, h = 10 }, F).y, L.BADGE / 2 + 2)
eq("badge: kept on screen at the bottom", L.badge({ x = 300, y = 900, w = 10, h = 10 }, F).y, F.h - L.BADGE / 2 - 2)

-- A focus ends when the owner brings the pointer to the target.
local T = { x = 500, y = 380, w = 40, h = 40 }
eq("reached: brought onto the target", L.reached({ x = 100, y = 100 }, { x = 510, y = 400 }, T), true)
eq("reached: just outside the pad", L.reached({ x = 100, y = 100 }, { x = 500 - L.REACH_PAD - 1, y = 400 }, T), false)
eq("reached: on the pad's edge", L.reached({ x = 100, y = 100 }, { x = 500 - L.REACH_PAD, y = 400 }, T), true)
eq("reached: from just outside, a short move in",
   L.reached({ x = 500 - L.REACH_PAD - 2, y = 400 }, { x = 502, y = 400 }, T), true)
eq("reached: started inside, not moved", L.reached({ x = 510, y = 400 }, { x = 515, y = 400 }, T), false)
eq("reached: started inside a big target, then moved", L.reached({ x = 0, y = 0 }, { x = L.REACH_MOVE, y = 0 },
   { x = -100, y = -100, w = 1000, h = 1000 }), true)
eq("reached: moved, but not far enough", L.reached({ x = 0, y = 0 }, { x = L.REACH_MOVE - 1, y = 0 },
   { x = -100, y = -100, w = 1000, h = 1000 }), false)

-- Intros: a fixed list, none by default; auto chooses from where the pointer is.
eq("intro: none by default", L.validate("arrow", { target = { x = 5, y = 6 } }).intro, "none")
eq("intro: named", L.validate("highlight", { target = { x = 5, y = 6 }, intro = "sunburst" }).intro, "sunburst")
refused("intro: unknown", "arrow", { target = { x = 5, y = 6 }, intro = "fireworks" })
local TWO = { F, { x = 1000, y = 0, w = 500, h = 500 } }
local function names(list) return table.concat(list, "+") end
eq("auto: other monitor, which one then where", names(L.intro_for({ x = 100, y = 100 },
   { x = 1200, y = 100, w = 20, h = 20 }, TWO)), "halo+comet")
eq("auto: far on this monitor", names(L.intro_for({ x = 0, y = 0 }, { x = 900, y = 700, w = 20, h = 20 }, TWO)),
   "comet+iris")
eq("auto: nearby", names(L.intro_for({ x = 100, y = 100 }, { x = 500, y = 100, w = 20, h = 20 }, TWO)), "iris")
eq("auto: right there, nothing", names(L.intro_for({ x = 100, y = 100 }, { x = 100 + L.NEAR, y = 100, w = 20, h = 20 },
   TWO)), "")
eq("auto: just past near", names(L.intro_for({ x = 100, y = 100 }, { x = 101 + L.NEAR, y = 100, w = 20, h = 20 },
   TWO)), "iris")

local BIG = { x = 0, y = 0, w = 3000, h = 3000 }
eq("auto: exactly FAR is not far", names(L.intro_for({ x = 0, y = 10 }, { x = L.FAR - 10, y = 0, w = 20, h = 20 },
   { BIG })), "iris")
eq("auto: just past FAR is far", names(L.intro_for({ x = 0, y = 10 }, { x = L.FAR - 9, y = 0, w = 20, h = 20 },
   { BIG })), "comet+iris")

eq("ease: starts at 0", L.ease(0), 0)
eq("ease: ends at 1", L.ease(1), 1)
eq("ease: fast at first", L.ease(0.5) > 0.5, true)
eq("ease: held before the start", L.ease(-1), 0)
eq("ease: held after the end", L.ease(2), 1)

local rays = L.rays({ x = 0, y = 0 }, 4, 0, 100, 10)
eq("rays: as many as asked", #rays, 4)
eq("rays: each starts at the centre", rays[3][1].x == 0 and rays[3][1].y == 0, true)
eq("rays: the first points right", rays[1][2].x, 100)
eq("rays: as wide as asked at the end", math.abs(rays[1][2].y - rays[1][3].y), 20)
eq("rays: spread round the circle", math.floor(rays[2][2].y + 0.5), 100)

if fails > 0 then os.exit(1) end
print("ok")
