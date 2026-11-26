#Requires AutoHotkey v2.0
; The Windows curtain's rules (windows/autohotkey/curtain-logic.ahk), with the
; same cases as test/curtain_logic_test.lua so the two ports cannot drift apart.
; Run: AutoHotkey64.exe /ErrorStdOut test\curtain_logic_test.ahk; exits 1 on a failure.
#Include %A_ScriptDir%\..\windows\autohotkey\curtain-logic.ahk
; A runtime error would otherwise wait on a dialog nobody closes.
OnError((err, *) => (FileAppend("ERROR " err.Message " at line " err.Line "`n", "*", "UTF-8"), ExitApp(2)))
L := CurtainLogic
fails := 0
Eq(name, got, want) {
    global fails
    if (got !== want) {
        fails += 1
        FileAppend("FAIL " name ": got " got ", want " want "`n", "*", "UTF-8")
    }
}
S(deadline := 0, snoozeUntil := 0, shown := false) => {deadline: deadline, snoozeUntil: snoozeUntil, shown: shown}

Eq("finish: an end the owner chose", L.CanFinish(""), true)
Eq("finish: not the daily end", L.CanFinish("daily"), false)
Eq("finish: not straight after the curtain comes up", L.FinishReady(L.DONE_GRACE_SECONDS - 0.1), false)
Eq("finish: after the grace", L.FinishReady(L.DONE_GRACE_SECONDS), true)
Eq("reason 1", L.AnswerOf(1, 1), "区切りが悪い")
Eq("reason 5", L.AnswerOf(1, 5), "その他")
Eq("no reason 6", L.AnswerOf(1, 6), "")
Eq("main task", L.AnswerOf(2, 1), "本題")
Eq("no answer 3 to the second", L.AnswerOf(2, 3), "")
Eq("question line", L.QuestionLine(2), "続けるのは本題?　1 本題　2 脇道")
Eq("question line: the first, all five in order", L.QuestionLine(1),
    "なぜ続ける?　1 区切りが悪い　2 仕事・締切　3 ただ続けたい　4 まだ眠くない　5 その他")
Eq("answers: both", L.AnswersDetail(Map(1, "区切りが悪い", 2, "脇道")), "区切りが悪い 脇道")
Eq("answers: only the first", L.AnswersDetail(Map(1, "区切りが悪い")), "区切りが悪い なし")
Eq("answers: none given", L.AnswersDetail(Map()), "なし なし")
Eq("hold: first lift", L.HoldSeconds(0), 5)
Eq("hold: second lift", L.HoldSeconds(1), 10)
Eq("hold: third lift", L.HoldSeconds(2), 15)
Eq("hold: capped", L.HoldSeconds(20), L.MAX_HOLD_SECONDS)
Eq("hold: a new press starts it", L.StartsHold(false, false), true)
Eq("hold: the press that brought the questions does not", L.StartsHold(false, true), false)
Eq("hold: not twice at once", L.StartsHold(true, false), false)
TypeWord(keys) {
    n := 0
    loop parse keys
        n := CurtainLogic.EmergencyStep(n, A_LoopField)
    return n
}
Eq("emergency: the word", TypeWord("exit"), StrLen(L.EMERGENCY_WORD))
Eq("emergency: a slip starts again", TypeWord("exxit"), 0)
Eq("emergency: a restart on the first letter", TypeWord("exeexit"), StrLen(L.EMERGENCY_WORD))
Eq("emergency: half way", TypeWord("ex"), 2)
Eq("emergency: a key with no name", L.EmergencyStep(4, ""), 0)
Eq("emergency: upper case is another key", TypeWord("EXIT"), 0)
Eq("first hold asks", L.AfterHold(false), "ask")
Eq("hold while asking lifts", L.AfterHold(true), "lift")
Eq("past: first minute", L.Past(160, 101), "ちょうど今")
Eq("past: minutes", L.Past(100 + 27 * 60, 100), "過ぎて 27分")
Eq("past: hours", L.Past(100 + 65 * 60, 100), "過ぎて 1時間5分")

Eq("no deadline", L.Decide(S(), 100, 0), "")
Eq("before deadline", L.Decide(S(200), 100, 0), "")
Eq("deadline reached", L.Decide(S(100), 100, 0), "show")
Eq("already shown", L.Decide(S(100, 0, true), 150, 0), "")
Eq("snoozed", L.Decide(S(100, 400), 300, 0), "")
Eq("snooze over", L.Decide(S(100, 400), 400, 0), "show")
Eq("walked away", L.Decide(S(100, 0, true), 1000, L.GONE_SECONDS), "clear")
Eq("idle since before the deadline still shows", L.Decide(S(1000), 1000, L.GONE_SECONDS), "show")
Eq("next morning after sleep", L.Decide(S(100, 0, true), 100 + L.STALE_SECONDS, 0), "clear")
Eq("deadline moved later while shown", L.Decide(S(500, 0, true), 100, 0), "hide")

TZ := 9 * 3600
; 2026-11-22 00:00 in a UTC+9 zone
now := 1795305600 - TZ
nine := L.ParseTime("09:00", now, TZ)
Eq("09:00 today", nine - now, 9 * 3600)
Eq("0900 form", L.ParseTime("0900", now, TZ), nine)
Eq("past time is tomorrow", L.ParseTime("00:00", now + 60, TZ) - now, 86400)
Eq("bad hour", L.ParseTime("25:00", now, TZ), 0)
Eq("junk", L.ParseTime("soon", now, TZ), 0)
Eq("clock", L.Clock(nine + 5 * 60, TZ), "09:05")

sl := L.Slots(nine + 7 * 60, TZ, 3)
Eq("first slot 09:30", sl[1] - nine, 30 * 60)
Eq("slots every 30 min", sl[3] - sl[1], 3600)
Eq("too close skipped", L.Slots(nine + 25 * 60, TZ, 1)[1] - nine, 3600)
Eq("on the mark", L.Slots(nine, TZ, 1)[1] - nine, 30 * 60)
Eq("left minutes", L.Left(0, 7 * 60 + 30), "7分")
Eq("left hours", L.Left(0, 2 * 3600 + 5 * 60), "2時間5分")
Eq("left whole hour", L.Left(0, 3600), "1時間")
Eq("left under a minute", L.Left(0, 30), "1分未満")

evening := now + 22 * 3600
Eq("daily end: midnight tonight", L.DailyEnd(evening, TZ, "00:00") - evening, 2 * 3600)
Eq("daily end: a removed end does not come back", L.DailyEnd(evening, TZ, "00:00", evening + 2 * 3600), 0)
Eq("daily end: not more than 14 hours ahead", L.DailyEnd(now + 9 * 3600, TZ, "00:00"), 0)
Eq("daily end: junk", L.DailyEnd(evening, TZ, "soon"), 0)
; evening is Sunday 22:00; the next day is Monday
monAfternoon := now + 86400 + 15 * 3600
two := "weekday 19:45`ndaily 23:45"
Eq("ends: the weekday end first on a weekday", L.DailyEnds(monAfternoon, TZ, two) - monAfternoon, 4 * 3600 + 45 * 60)
Eq("ends: then the night end", L.DailyEnds(monAfternoon + 5 * 3600, TZ, two) - monAfternoon, 8 * 3600 + 45 * 60)
Eq("ends: no weekday end on Sunday", L.DailyEnds(now + 15 * 3600, TZ, two) - (now + 15 * 3600), 8 * 3600 + 45 * 60)
Eq("ends: CRLF lines",
    L.DailyEnds(monAfternoon, TZ, "weekday 19:45`r`ndaily 23:45`r`n") - monAfternoon, 4 * 3600 + 45 * 60)
Eq("ends: bare time is daily", L.DailyEnds(evening, TZ, "00:00") - evening, 2 * 3600)
Eq("ends: removed end skipped, next one used",
    L.DailyEnds(monAfternoon, TZ, two, monAfternoon + 4 * 3600 + 45 * 60) - monAfternoon, 8 * 3600 + 45 * 60)
Eq("ends: empty", L.DailyEnds(evening, TZ, ""), 0)
Eq("ends: kinds are lower case, as on the Mac", L.DailyEnds(evening, TZ, "Daily 23:45"), 0)

T0 := 1000000
Eq("bar: full at the start", L.Bar(T0, T0, T0 + 600, 6), "▰▰▰▰▰▰")
Eq("bar: half way", L.Bar(T0 + 300, T0, T0 + 600, 6), "▰▰▰▱▱▱")
Eq("bar: a little left still shows one cell", L.Bar(T0 + 590, T0, T0 + 600, 6), "▰▱▱▱▱▱")
Eq("bar: none when the end has come", L.Bar(T0 + 600, T0, T0 + 600, 6), "")
Eq("bar: none without a start", L.Bar(T0, 0, T0 + 600, 6), "")
Eq("bar: a start after now counts as now", L.Bar(T0, T0 + 60, T0 + 600, 6), "▰▰▰▰▰▰")

Eq("countdown: minutes and seconds", L.Countdown(T0, T0 + 754), "12:34")
Eq("countdown: seconds keep their zero", L.Countdown(T0, T0 + 65), "1:05")
Eq("countdown: under a minute", L.Countdown(T0, T0 + 9), "0:09")
Eq("countdown: an hour or more shows hours", L.Countdown(T0, T0 + 3723), "1:02:03")
Eq("countdown: never below zero", L.Countdown(T0 + 5, T0), "0:00")

h := L.HoldLeft(0, 5), Eq("hold: full at the press", h[1], 1), Eq("hold: all seconds left", h[2], 5)
h := L.HoldLeft(2.5, 5), Eq("hold: half way", h[1], 0.5), Eq("hold: seconds round up", h[2], 3)
h := L.HoldLeft(4.99, 5), Eq("hold: one second shown until the end", h[2], 1)
h := L.HoldLeft(6, 5), Eq("hold: never below empty", h[1], 0), Eq("hold: seconds never below zero", h[2], 0)

if fails {
    FileAppend(fails " failed`n", "*", "UTF-8")
    ExitApp(1)
}
FileAppend("ok`n", "*", "UTF-8")
ExitApp(0)
