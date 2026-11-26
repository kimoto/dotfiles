#Requires AutoHotkey v2.0

; At an end time the owner sets, covers every screen with a dark curtain so a
; session that should have ended stops being visible, and shows the time. Nothing
; is closed. Esc held for five seconds (five more for each lift of the same end)
; brings up two questions, answered with number keys and logged; then it lifts,
; and comes back five minutes later while the machine is still in use. Typing
; exit lifts it at once. The Windows half of
; hammerspoon/Spoons/Curtain.spoon, with its rules in curtain-logic.ahk.
;
; mac-keys.ahk includes this file, so the launcher that keeps mac-keys running
; and restarts it when any of its .ahk files changes carries the curtain too. A restart keeps the end:
; it lives in %LOCALAPPDATA%\curtain\deadline, with the Spoon's lines (end,
; snooze, from, set at, lifts). Local, not over \\wsl.localhost, so a stalled WSL
; cannot stall the curtain.
;
; Set the end from the tray icon's 暗い幕 menu. A fixed end every night goes in
; %LOCALAPPDATA%\curtain\daily-end, one line per end, e.g. "daily 23:45"
; (the formats are in CurtainLogic.DailyEnds).
#Include %A_LineFile%\..\curtain-logic.ahk

class Curtain {
    static BAR_CELLS := 6
    ; A daily end was armed whenever the machine got to it, so its bar covers the last hour only.
    static AUTO_BAR_SECONDS := 3600
    ; Within the last hour the corner counts down to the second; further out, the end time.
    static COUNTDOWN_SECONDS := 3600
    ; How long after the lift the keys still held are eaten at most, in case a release never arrives.
    static DRAIN_MS := 10000

    static dir := EnvGet("LOCALAPPDATA") "\curtain"
    static s := {deadline: 0, snoozeUntil: 0, shown: false, from: "", setAt: 0, lifts: 0}
    static tz := 0
    static screens := []
    static ih := ""
    static holdStart := 0
    static draining := false
    ; The question being asked (0 for none) and the answers so far, question to answer.
    static asking := 0
    static answers := Map()
    ; Every key held under the curtain, so a repeat is told from a press and a lift can eat the releases.
    static keysDown := Map()
    ; The keys still to be released after a lift.
    static drainKeys := Map()
    ; The Esc press that brought the questions up, until it is released.
    static escSpent := false
    ; How much of the emergency word is typed.
    static typed := 0
    ; When the curtain came up (A_TickCount), for the grace before Enter counts.
    static shownTick := 0
    static wasSuspended := false
    static badge := ""
    static badgeText := ""
    static menu := ""

    static Start() {
        DirCreate(this.dir)
        this.tz := CurtainLogic.LocalOffset()
        this.Load()
        this.BuildMenu()
        SetTimer(() => Curtain.Step(), 1000)
        ; Twice a second, so the countdown never skips a second.
        SetTimer(() => Curtain.RefreshBadge(), 500)
        this.Step()
    }

    static File(name) => this.dir "\" name

    static ReadFile(name) {
        try return FileRead(this.File(name), "UTF-8")
        return ""
    }

    static WriteFile(name, text) {
        ; Through a temp file, so a restart mid-write cannot leave half an end behind.
        ; A file held a moment by antivirus or the indexer is written on the next change; a dialog
        ; here could open under the curtain, where nobody can close it.
        try {
            tmp := this.File(name ".tmp")
            f := FileOpen(tmp, "w", "UTF-8-RAW")
            f.Write(text), f.Close()
            FileMove(tmp, this.File(name), true)
        }
    }

    static Log(what, detail := "") {
        now := CurtainLogic.Now(), z := Abs(this.tz)
        line := FormatTime(CurtainLogic.Stamp(now, this.tz), "yyyy-MM-dd'T'HH:mm:ss")
            . Format("{}{:02d}:{:02d}", this.tz < 0 ? "-" : "+", z // 3600, Mod(z, 3600) // 60)
            . "`t" what "`t" RegExReplace(detail, "[`t`n]", " ") "`n"
        try FileAppend(line, this.File("log.tsv"), "UTF-8-RAW")
    }

    static Clock(t) => CurtainLogic.Clock(t, this.tz)

    static Save() {
        s := this.s
        if !s.deadline {
            try FileDelete(this.File("deadline"))
            return
        }
        this.WriteFile("deadline", s.deadline "`n" (s.snoozeUntil || "") "`n" s.from "`n" (s.setAt || "") "`n"
            . s.lifts "`n")
    }

    static Load() {
        lines := StrSplit(this.ReadFile("deadline"), "`n", "`r")
        num(i) => (lines.Length >= i && IsInteger(lines[i])) ? Integer(lines[i]) : 0
        t := num(1)
        if t && CurtainLogic.Now() - t < CurtainLogic.STALE_SECONDS {
            s := this.s
            s.deadline := t, s.snoozeUntil := num(2), s.setAt := num(4), s.lifts := num(5)
            s.from := lines.Length >= 3 ? lines[3] : ""
        }
    }

    ; t: the end (0 removes it). from: "" for an end the owner chose, "daily" for the fixed one.
    static SetDeadline(t, from := "", why := "") {
        s := this.s
        if t != s.deadline || from != s.from {
            this.Log(t ? "set" : "clear", Trim((t ? this.Clock(t) " " (from || "chosen") : "") " " why))
            s.setAt := t ? CurtainLogic.Now() : 0
            ; A new end starts the count of lifts again.
            if t != s.deadline
                s.lifts := 0
            ; Only a new end ends a snooze, so setting the same end again does not bring the curtain straight back.
            s.snoozeUntil := 0
        }
        s.deadline := t, s.from := from
        this.Save()
        this.RefreshMenu()
    }

    ; Removing the daily end by hand remembers it, so the next check does not set the same one again.
    static ClearDeadline() {
        s := this.s
        if s.from = "daily" && s.deadline
            this.WriteFile("daily-skip", s.deadline "`n")
        this.Hide()
        this.SetDeadline(0, "", "manual")
    }

    static DailyEnd(now) {
        conf := this.ReadFile("daily-end")
        if conf = ""
            return 0
        skip := Trim(this.ReadFile("daily-skip"), " `r`n")
        return CurtainLogic.DailyEnds(now, this.tz, conf, IsInteger(skip) ? Integer(skip) : 0)
    }

    static CheckDaily(now) {
        s := this.s
        if s.deadline && (s.from != "daily" || now >= s.deadline)
            return
        ; Only an earlier end replaces the one set: DailyEnd drops an end in its last minute.
        d := this.DailyEnd(now)
        if d && (!s.deadline || d < s.deadline)
            this.SetDeadline(d, "daily")
    }

    static Step() {
        s := this.s, now := CurtainLogic.Now()
        this.tz := CurtainLogic.LocalOffset()
        this.CheckDaily(now)
        switch CurtainLogic.Decide(s, now, A_TimeIdlePhysical // 1000) {
            case "show": this.Show()
            case "hide": this.Log("hide", "end moved or removed"), this.Hide()
            case "clear": this.Hide(), this.SetDeadline(0, s.from, "expired")
        }
        ; Another window brought to the front (a notification, an app that steals focus) goes back under.
        if s.shown && this.screens.Length {
            this.RefreshClock()
            for sc in this.screens
                try WinMoveTop(sc.gui)
            try WinActivate(this.screens[1].gui)
        }
        this.RefreshMenu()
    }

    static Show() {
        s := this.s
        ; Every key goes to the curtain while it is up, so nothing is typed or closed blind
        ; underneath; every key is watched, for Esc, the answers and the way out. mac-keys' hotkeys
        ; sleep too, or one of them could move the curtain's window aside.
        ; A lift's drain may still hold the last hook; two hooks would leave Esc eaten for good.
        this.StopDrain(true)
        ih := InputHook("L0 I")
        ih.KeyOpt("{All}", "SN")
        ih.OnKeyDown := (ih, vk, sc) => Curtain.KeyDown(vk, sc)
        ih.OnKeyUp := (ih, vk, sc) => Curtain.KeyUp(vk)
        this.keysDown := Map(), this.escSpent := false, this.typed := 0
        ; An Enter already held when the curtain comes up repeats under it; known as held, its
        ; repeats are not taken for a fresh press.
        if GetKeyState("Enter", "P")
            this.keysDown[0x0D] := true
        this.shownTick := A_TickCount
        this.asking := 0, this.answers := Map()
        now := CurtainLogic.Now()
        try {
            loop MonitorGetCount() {
                MonitorGet(A_Index, &l, &t, &r, &b)
                g := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale", "Curtain")
                g.BackColor := "0D0D14"
                g.MarginX := 0, g.MarginY := 0
                w := r - l, h := b - t
                ; The time now, so a curtain left up still tells the time.
                g.SetFont("s96 cF2F2F2", "Yu Gothic UI")
                clock := g.AddText("x0 y" Round(h * 0.30) " w" w " Center", this.Clock(now))
                ; The end and how long ago it was, or the question. Two lines high: the first question
                ; with its five choices wraps on a laptop screen.
                g.SetFont("s22 cBFBFBF")
                sub := g.AddText("x40 y+16 w" (w - 80) " h80 Center", this.SubLine())
                g.SetFont("s18 c999999")
                hint := g.AddText("x0 y+16 w" w " Center", this.Hint())
                ; The share of the Esc hold still to go: full at the press, empty at the lift.
                bar := g.AddProgress("x" (w // 2 - 160) " y+36 w320 h10 -Theme cE6E6E6 Background4D4D4D"
                    . " Range0-1000 Hidden", 1000)
                ; Small and dim at the bottom, so the way out is not forgotten on a machine that rarely needs it.
                g.SetFont("s11 c595959")
                g.AddText("x0 y" (h - 60) " w" w " Center",
                    "非常口: " CurtainLogic.EMERGENCY_WORD " と打つ（記録に残ります）")
                g.Show("x" l " y" t " w" w " h" h)
                WinSetTransparent(245, g)
                this.screens.Push({gui: g, clock: clock, sub: sub, hint: hint, bar: bar})
            }
        } catch as err {
            ; A half-built curtain would swallow keys over a screen that is not covered.
            this.Hide()
            this.Log("not-shown", err.Message)
            s.snoozeUntil := CurtainLogic.Now() + 15
            this.Save()
            return
        }
        if !this.screens.Length {
            s.snoozeUntil := CurtainLogic.Now() + 15
            return
        }
        s.shown := true
        this.ih := ih
        ih.Start()
        this.wasSuspended := A_IsSuspended
        Suspend(true)
        if this.badge
            this.badge.Hide()
        this.Log("show", this.Clock(s.deadline))
    }

    static Hide() {
        this.StopHold()
        for sc in this.screens
            try sc.gui.Destroy()
        this.screens := []
        if this.ih && !this.draining
            this.ih.Stop(), this.ih := ""
        if this.s.shown
            Suspend(this.wasSuspended)
        this.s.shown := false
        this.asking := 0, this.answers := Map()
    }

    ; The hint line when Esc is not held: how to lift, or how to answer while asking.
    static Hint() {
        secs := CurtainLogic.HoldSeconds(this.s.lifts)
        if this.asking
            return "数字キーで答える（答えずに上げるなら、Esc を一度離してもう" secs "秒）"
        return (CurtainLogic.CanFinish(this.s.from) ? CurtainLogic.DONE "なら Enter　・　" : "")
            . "続ける時だけ Esc を" secs "秒押し続ける"
            . (this.s.lifts > 0 ? "（この終わりで " this.s.lifts + 1 "回目）" : "")
    }

    ; The line under the clock: the end and how long ago it was, or the question being asked.
    static SubLine() {
        if this.asking
            return CurtainLogic.QuestionLine(this.asking)
        d := this.s.deadline
        return d ? this.Clock(d) " に終わり・" CurtainLogic.Past(CurtainLogic.Now(), d) : ""
    }

    static RefreshClock() {
        now := this.Clock(CurtainLogic.Now()), sub := this.SubLine()
        for sc in this.screens {
            if sc.clock.Value != now
                sc.clock.Value := now
            if sc.sub.Value != sub
                sc.sub.Value := sub
        }
    }

    static SetHint(text) {
        for sc in this.screens
            sc.hint.Value := text
    }

    ; The number a key types, top row or keypad, or 0.
    ; The keypad by its scan codes, so it answers with NumLock off too, when it sends End, Down and so
    ; on; the arrow keys share those virtual keys but have extended scan codes, so they do not answer.
    static PAD_DIGITS := Map(0x4F, 1, 0x50, 2, 0x51, 3, 0x4B, 4, 0x4C, 5, 0x4D, 6, 0x47, 7, 0x48, 8, 0x49, 9)
    static Digit(vk, sc) => (vk >= 0x31 && vk <= 0x39) ? vk - 0x30 : this.PAD_DIGITS.Get(sc, 0)

    ; Whether the key is down now: a release lost to the lock screen, or a key that sends no release
    ; (半角/全角), must not leave it counted as held for good.
    static IsDown(vk) => GetKeyState("vk" Format("{:X}", vk), "P")

    ; Starts asking question q, or lifts once every question has an answer.
    static Ask(q) {
        if q > CurtainLogic.QUESTIONS.Length
            return this.Lift()
        this.asking := q
        this.RefreshClock()
        if !this.holdStart
            this.SetHint(this.Hint())
    }

    static KeyDown(vk, sc) {
        if this.draining || !this.s.shown
            return
        ; Auto-repeat sends a held key down again and again: only its first press counts.
        isRepeat := this.keysDown.Has(vk) && this.IsDown(vk)
        this.keysDown[vk] := true
        if vk != 0x1B {
            if isRepeat
                return
            this.typed := CurtainLogic.EmergencyStep(this.typed, GetKeyName(Format("vk{:X}", vk)))
            if this.typed = StrLen(CurtainLogic.EMERGENCY_WORD)
                return this.Lift(CurtainLogic.EMERGENCY)
            ; Enter, on the main keyboard or the keypad: the work is done.
            if vk = 0x0D && CurtainLogic.CanFinish(this.s.from)
                && CurtainLogic.FinishReady((A_TickCount - this.shownTick) / 1000)
                return this.Finish()
            n := this.Digit(vk, sc)
            if this.asking && n {
                answer := CurtainLogic.AnswerOf(this.asking, n)
                if answer != "" {
                    this.answers[this.asking] := answer
                    this.Ask(this.asking + 1)
                }
            }
            return
        }
        if !CurtainLogic.StartsHold(this.holdStart != 0, this.escSpent)
            return
        this.holdStart := A_TickCount
        ; About 30 times a second, so the bar empties smoothly rather than in steps.
        SetTimer(this.HoldTick, 33)
        this.HoldTick.Call()
    }

    static KeyUp(vk) {
        if this.draining {
            if this.drainKeys.Has(vk)
                this.drainKeys.Delete(vk)
            if !this.drainKeys.Count
                this.StopDrain()
            return
        }
        if this.keysDown.Has(vk)
            this.keysDown.Delete(vk)
        if vk = 0x1B {
            this.escSpent := false
            this.StopHold()
        }
    }

    ; A bound copy, so SetTimer can stop the same object it started.
    static HoldTick := () => Curtain.Hold()

    static Hold() {
        ; A_TickCount does not move with the clock, so changing the time neither shortens nor stretches the hold.
        r := CurtainLogic.HoldLeft((A_TickCount - this.holdStart) / 1000, CurtainLogic.HoldSeconds(this.s.lifts))
        if r[1] <= 0 {
            if CurtainLogic.AfterHold(this.asking) = "lift"
                return this.Lift()
            ; The questions come up and the hold ends there: holding on does nothing, so skipping
            ; them takes a release and a second press, never the same press held a little long.
            this.escSpent := true
            this.StopHold()
            return this.Ask(1)
        }
        for sc in this.screens {
            sc.bar.Value := Round(r[1] * 1000)
            sc.bar.Visible := true
            sc.hint.Value := (this.asking ? "答えずに上げるまで あと " : "あと ") r[2] " 秒"
        }
    }

    static StopHold() {
        SetTimer(this.HoldTick, 0)
        this.holdStart := 0
        for sc in this.screens {
            sc.bar.Visible := false
            sc.hint.Value := this.Hint()
        }
    }

    ; Lifts the curtain and logs the answers given, "なし" for the rest, or detail instead.
    static Lift(detail := "") {
        this.Log("lift", detail != "" ? detail : CurtainLogic.AnswersDetail(this.answers))
        this.DrainHeld()
        this.Hide()
        this.s.snoozeUntil := CurtainLogic.Now() + CurtainLogic.SNOOZE_SECONDS
        this.s.lifts += 1
        this.Save()
    }

    ; The work is done: the curtain goes and the end with it, so it does not come back.
    static Finish() {
        d := this.s.deadline
        this.Log("done", d ? this.Clock(d) " " CurtainLogic.Past(CurtainLogic.Now(), d) : "")
        this.DrainHeld()
        this.Hide()
        this.SetDeadline(0, "", "done")
    }

    ; The keys still down (Esc held, the number key that answered last, Enter) would send their
    ; repeats and releases to the app in front, so they are eaten until released or DRAIN_MS.
    static DrainHeld() {
        this.drainKeys := Map()
        for vk in this.keysDown
            if this.IsDown(vk)
                this.drainKeys[vk] := true
        if this.drainKeys.Count {
            this.draining := true
            this.ih.KeyOpt("{All}", "-S +V")
            for vk in this.drainKeys
                this.ih.KeyOpt("{vk" Format("{:X}", vk) "}", "S")
            SetTimer(() => Curtain.StopDrain(), -this.DRAIN_MS)
        }
    }

    static StopDrain(always := false) {
        if !this.draining && !always
            return
        this.draining := false
        this.drainKeys := Map()
        if this.ih && (always || !this.s.shown)
            this.ih.Stop(), this.ih := ""
    }

    static CornerText() {
        s := this.s, now := CurtainLogic.Now()
        if !s.deadline || s.shown
            return ""
        if s.deadline > now {
            start := s.from = "daily" ? s.deadline - this.AUTO_BAR_SECONDS : s.setAt
            bar := CurtainLogic.Bar(now, start, s.deadline, this.BAR_CELLS)
            text := s.deadline - now <= this.COUNTDOWN_SECONDS
                ? "あと " CurtainLogic.Countdown(now, s.deadline) : this.Clock(s.deadline) "まで"
            return "⏳" (bar != "" ? bar " " : " ") text
        }
        if s.snoozeUntil > now
            return "⏳ " this.Clock(s.snoozeUntil) "にまた幕"
        return ""
    }

    ; The time left, small in the corner above the clock, always on top and click-through, as the
    ; Mac shows it in the menu bar.
    static RefreshBadge() {
        text := this.CornerText()
        A_IconTip := text != "" ? text : "暗い幕: 終わりの時刻は未設定"
        if text = "" {
            if this.badge
                this.badge.Hide()
            return
        }
        if !this.badge {
            ; E0x20 lets clicks through, which needs a layered window (E0x80000).
            g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x80000")
            g.BackColor := "1A1A22"
            g.MarginX := 10, g.MarginY := 4
            g.SetFont("s11 cF2F2F2", "Yu Gothic UI")
            this.badgeText := g.AddText("w240", text)
            this.badge := g
        }
        if this.badgeText.Value != text
            this.badgeText.Value := text
        MonitorGetWorkArea(MonitorGetPrimary(), , , &r, &b)
        this.badge.Show("NoActivate AutoSize Hide")
        WinGetPos(, , &w, &h, this.badge)
        this.badge.Show("NoActivate x" (r - w - 12) " y" (b - h - 12))
        WinSetTransparent(220, this.badge)
    }

    static SetIn(minutes) => (*) => Curtain.SetDeadline(CurtainLogic.Now() + minutes * 60)

    static AskTime() {
        r := InputBox("終わりの時刻（例 2330・23:30）", "暗い幕", "w300 h120")
        if r.Result != "OK"
            return
        now := CurtainLogic.Now()
        t := CurtainLogic.ParseTime(r.Value, now, this.tz)
        ; At least 5 minutes ahead and under 14 hours, so a mistyped time cannot set tomorrow.
        if !t || t < now + 300 || t >= now + 14 * 3600
            return TrayTip("「" r.Value "」は時刻として使えません", "暗い幕")
        this.SetDeadline(t)
    }

    static BuildMenu() {
        m := Menu()
        m.Add("終わりの時刻は未設定", (*) => 0)
        m.Disable("1&")
        m.Add()
        ; 2 and 5 on purpose: short focus blocks.
        for minutes in [2, 5, 10, 15, 25, 50, 90]
            m.Add("あと " CurtainLogic.Left(0, minutes * 60) "で終わる", this.SetIn(minutes))
        m.Add("時刻で決める…", (*) => Curtain.AskTime())
        m.Add()
        m.Add("今すぐ暗くする", (*) => (Curtain.SetDeadline(CurtainLogic.Now()), Curtain.Step()))
        m.Add("終わりを消す", (*) => Curtain.ClearDeadline())
        A_TrayMenu.Insert("1&", "暗い幕", m)
        A_TrayMenu.Insert("2&")
        this.menu := m
    }

    static RefreshMenu() {
        if !this.menu
            return
        s := this.s, now := CurtainLogic.Now()
        head := "終わりの時刻は未設定"
        if s.deadline
            head := "終わり " this.Clock(s.deadline)
                . (s.deadline > now ? "（あと" CurtainLogic.Left(now, s.deadline) "）" : "")
                . (s.from = "daily" ? "・毎日の終わり" : "")
        try this.menu.Rename("1&", head)
    }
}

Curtain.Start()
