#Requires AutoHotkey v2.0

; The curtain's rules with no windows in them, so test/curtain_logic_test.ahk can
; run them. A port of hammerspoon/Spoons/Curtain.spoon/logic.lua: keep the
; numbers and the answers the same, so the curtain behaves alike on both
; machines. Times are Unix seconds; tz is how far the owner's clock is ahead of
; UTC. "No time" is 0, as AutoHotkey has no nil.
class CurtainLogic {
    ; Esc must be held this long to lift the curtain, so a reflex press is not enough.
    static HOLD_SECONDS := 5
    ; A lifted curtain comes back after this, if the machine is still in use.
    static SNOOZE_SECONDS := 5 * 60
    ; Idle this long, counted from the end, means the owner walked away: the end is done.
    ; Idle that began before the end (a video watched hands off) does not count.
    static GONE_SECONDS := 10 * 60
    ; An end older than this belongs to an earlier sitting: dropped on load and cleared when met,
    ; since a sleeping machine never counts idle up to GONE_SECONDS.
    static STALE_SECONDS := 3 * 3600

    static Now() => DateDiff(A_NowUTC, "19700101000000", "Seconds")

    ; This machine's offset now, rounded to the minute, so a DST change is followed.
    static LocalOffset() => Round(DateDiff(A_Now, A_NowUTC, "Seconds") / 60) * 60

    static Stamp(t, tz) => DateAdd("19700101000000", t + tz, "Seconds")

    static Clock(t, tz) => FormatTime(this.Stamp(t, tz), "HH:mm")

    ; s: {deadline, snoozeUntil, shown}. Returns "show", "hide", "clear" (forget the end and hide) or "".
    static Decide(s, now, idle) {
        if !s.deadline || now < s.deadline
            return s.shown ? "hide" : ""
        if now - s.deadline >= this.STALE_SECONDS
            return "clear"
        if idle >= this.GONE_SECONDS && now - idle >= s.deadline
            return "clear"
        if s.shown
            return ""
        if s.snoozeUntil && now < s.snoozeUntil
            return ""
        return "show"
    }

    ; "12:30" or "1230" to the next such time after now (tomorrow if already past), or 0.
    static ParseTime(text, now, tz) {
        if !RegExMatch(text, "^\s*(\d\d?):?(\d\d)\s*$", &m)
            return 0
        h := Integer(m[1]), mi := Integer(m[2])
        if h > 23 || mi > 59
            return 0
        localNow := now + tz
        t := localNow - Mod(localNow, 86400) + h * 3600 + mi * 60
        if t <= localNow
            t += 86400
        return t - tz
    }

    ; The next n half-hour marks, at least 10 minutes ahead so a pick never fires straight away.
    static Slots(now, tz, n) {
        t := now + 600
        t := t - Mod(t + tz, 1800) + 1800
        if (t - now) - 1800 >= 600
            t -= 1800
        out := []
        loop n
            out.Push(t + (A_Index - 1) * 1800)
        return out
    }

    ; "2時間5分" / "7分" / "1分未満" until the end.
    static Left(now, deadline) {
        m := Floor((deadline - now) / 60)
        if m < 1
            return "1分未満"
        if m < 60
            return m "分"
        return Floor(m / 60) "時間" (Mod(m, 60) > 0 ? Mod(m, 60) "分" : "")
    }

    ; Time left to the second, "12:34" or "1:02:03".
    static Countdown(now, deadline) {
        left := Max(0, deadline - now)
        h := Floor(left / 3600), m := Floor(Mod(left, 3600) / 60), sec := Mod(left, 60)
        return h > 0 ? Format("{:d}:{:02d}:{:02d}", h, m, sec) : Format("{:d}:{:02d}", m, sec)
    }

    ; The share of the countdown left as cells (▰ left, ▱ gone), rounded up so the last cell
    ; stays until the end comes. "" when there is nothing to show.
    static Bar(now, start, deadline, cells) {
        if !start || !deadline || now >= deadline
            return ""
        start := Min(start, now)
        total := deadline - start
        if total <= 0
            return ""
        full := Min(cells, Ceil((deadline - now) / total * cells))
        out := ""
        loop cells
            out .= A_Index <= full ? "▰" : "▱"
        return out
    }

    ; While Esc is held: [share of the hold still to go (1 at the press, 0 at the lift), whole seconds left].
    static HoldLeft(elapsed, total) {
        f := Max(0, Min(1, 1 - elapsed / total))
        return [f, Max(0, Ceil(total - elapsed))]
    }

    ; Asked in turn once Esc has been held, each answered with a number key, so the log can show what
    ; keeps the owner going: why, and whether it is still the main task or a side track.
    static QUESTIONS := [
        {title: "なぜ続ける?", choices: ["区切りが悪い", "仕事・締切", "ただ続けたい", "まだ眠くない", "その他"]},
        {title: "続けるのは本題?", choices: ["本題", "脇道"]}
    ]
    static NO_ANSWER := "なし"

    ; A way out if the curtain itself goes wrong: typing this word lifts at once. A word, not a
    ; chord, as on the Mac, where Caps Lock holds four modifiers. Logged as EMERGENCY.
    static EMERGENCY := "非常口"
    static EMERGENCY_WORD := "exit"

    ; How much of the word is typed after key (a key name, "e"), given typed letters before it:
    ; a wrong key starts again, from 1 when it is the first letter.
    static EmergencyStep(typed, key) {
        w := this.EMERGENCY_WORD
        if key = ""
            return 0
        if typed < StrLen(w) && SubStr(w, typed + 1, 1) == key
            return typed + 1
        return SubStr(w, 1, 1) == key ? 1 : 0
    }

    ; Saying the work is done (Enter) takes the curtain down at once and removes the end, logged as
    ; done. Only for an end the owner chose: an automatic end was not set for a task.
    static DONE := "終わった"
    static CanFinish(from) => from = ""
    ; Enter counts only this long after the curtain came up, so the Enter that sends a message being
    ; typed as it appears does not remove the end by accident.
    static DONE_GRACE_SECONDS := 3
    static FinishReady(shownFor) => shownFor >= this.DONE_GRACE_SECONDS

    ; Question q's answer for number key n, or "" for a key that is not one of its choices.
    static AnswerOf(q, n) {
        c := this.QUESTIONS[q].choices
        return n >= 1 && n <= c.Length ? c[n] : ""
    }

    ; Question q as one line for the curtain, "なぜ続ける?　1 区切りが悪い　2 …".
    static QuestionLine(q) {
        out := this.QUESTIONS[q].title
        for i, c in this.QUESTIONS[q].choices
            out .= "　" i " " c
        return out
    }

    ; The answers (a Map from question to answer) for the log, "なし" for one not given.
    static AnswersDetail(answers) {
        out := ""
        loop this.QUESTIONS.Length
            out .= (A_Index > 1 ? " " : "") (answers.Has(A_Index) ? answers[A_Index] : this.NO_ANSWER)
        return out
    }

    ; Each lift for the same end makes the next hold longer: 5, 10, 15 … seconds, up to 30. The weight
    ; is on going on again and again, not on an answer, so an honest "side track" costs no more.
    static MAX_HOLD_SECONDS := 30
    static HoldSeconds(lifts) => Min(this.HOLD_SECONDS * (lifts + 1), this.MAX_HOLD_SECONDS)

    ; What a finished Esc hold does: the first asks why, one held while asking lifts without a reason.
    static AfterHold(asking) => asking ? "lift" : "ask"

    ; An Esc press starts the hold only when no hold runs and the press is not spent: the press that
    ; brought the questions up is, until released, so skipping them takes a second press.
    static StartsHold(holding, spent) => !holding && !spent

    ; How long the end has been passed, for the line under the clock: "ちょうど今" in its first minute.
    static Past(now, deadline) => now - deadline < 60 ? "ちょうど今" : "過ぎて " this.Left(deadline, now)

    ; A fixed end ("HH:MM"): the next such time, if at least a minute and under 14 hours away and
    ; later than skip (an end removed by hand), else 0. So a late start does not stretch the evening.
    static DailyEnd(now, tz, hhmm, skip := 0) {
        t := this.ParseTime(hhmm, now, tz)
        if !t || t < now + 60 || t >= now + 14 * 3600 || t <= skip
            return 0
        return t
    }

    ; The daily-end file, one per line: "daily HH:MM", "weekday HH:MM", "weekend HH:MM" or a bare
    ; "HH:MM" (daily). A weekday/weekend line counts by the day the end falls on. The earliest, or 0.
    static DailyEnds(now, tz, conf, skip := 0) {
        best := 0
        loop parse conf, "`n", "`r" {
            if RegExMatch(A_LoopField, "^\s*([A-Za-z]+)\s+(\S+)\s*$", &m)
                kind := m[1], hhmm := m[2]
            else if RegExMatch(A_LoopField, "^\s*(\S+)\s*$", &m)
                kind := "daily", hhmm := m[1]
            else
                continue
            t := this.DailyEnd(now, tz, hhmm, skip)
            if !t
                continue
            wday := Integer(FormatTime(this.Stamp(t, tz), "WDay"))  ; 1 Sunday … 7 Saturday
            weekend := wday = 1 || wday = 7
            ; == as in logic.lua: "Daily 23:45" means nothing on the Mac, so it must not here either.
            if (kind == "daily" || (kind == "weekday" && !weekend) || (kind == "weekend" && weekend))
                && (!best || t < best)
                best := t
        }
        return best
    }
}
