#Requires AutoHotkey v2.0

; At an end time the owner sets, covers every screen with a dark curtain so a
; session that should have ended stops being visible. Nothing is closed. Esc
; held for five seconds lifts it, and it comes back five minutes later while
; the machine is still in use. The Windows half of
; hammerspoon/Spoons/Curtain.spoon, with its rules in curtain-logic.ahk.
;
; mac-keys.ahk includes this file, so the launcher that keeps mac-keys running
; and restarts it when any of its .ahk files changes carries the curtain too. A restart keeps the end:
; it lives in %LOCALAPPDATA%\curtain\deadline, with the Spoon's lines (end,
; snooze, from, set at). Local, not over \\wsl.localhost, so a stalled WSL
; cannot stall the curtain.
;
; Set the end from the tray icon's 暗い幕 menu. A fixed end every night goes in
; %LOCALAPPDATA%\curtain\daily-end, one line per end, e.g. "daily 23:45"
; (the formats are in CurtainLogic.DailyEnds).
#Include %A_LineFile%\..\curtain-logic.ahk

class Curtain {
    static HINT := "ここまで、と決めた時刻です。続ける時だけ Esc を5秒押し続ける"
    static BAR_CELLS := 6
    ; A daily end was armed whenever the machine got to it, so its bar covers the last hour only.
    static AUTO_BAR_SECONDS := 3600
    ; Within the last hour the corner counts down to the second; further out, the end time.
    static COUNTDOWN_SECONDS := 3600
    ; How long after the lift a still-held Esc is eaten at most, in case its release never arrives.
    static DRAIN_MS := 10000

    static dir := EnvGet("LOCALAPPDATA") "\curtain"
    static s := {deadline: 0, snoozeUntil: 0, shown: false, from: "", setAt: 0}
    static tz := 0
    static screens := []
    static ih := ""
    static holdStart := 0
    static draining := false
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
        this.WriteFile("deadline", s.deadline "`n" (s.snoozeUntil || "") "`n" s.from "`n" (s.setAt || "") "`n")
    }

    static Load() {
        lines := StrSplit(this.ReadFile("deadline"), "`n", "`r")
        num(i) => (lines.Length >= i && IsInteger(lines[i])) ? Integer(lines[i]) : 0
        t := num(1)
        if t && CurtainLogic.Now() - t < CurtainLogic.STALE_SECONDS {
            s := this.s
            s.deadline := t, s.snoozeUntil := num(2), s.setAt := num(4)
            s.from := lines.Length >= 3 ? lines[3] : ""
        }
    }

    ; t: the end (0 removes it). from: "" for an end the owner chose, "daily" for the fixed one.
    static SetDeadline(t, from := "", why := "") {
        s := this.s
        if t != s.deadline || from != s.from {
            this.Log(t ? "set" : "clear", Trim((t ? this.Clock(t) " " (from || "chosen") : "") " " why))
            s.setAt := t ? CurtainLogic.Now() : 0
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
            for sc in this.screens
                try WinMoveTop(sc.gui)
            try WinActivate(this.screens[1].gui)
        }
        this.RefreshMenu()
    }

    static Show() {
        s := this.s
        ; Every key goes to the curtain while it is up, so nothing is typed or closed blind
        ; underneath; Esc alone is watched. mac-keys' hotkeys sleep too, or one of them could
        ; move the curtain's window aside.
        ; A lift's drain may still hold the last hook; two hooks would leave Esc eaten for good.
        this.StopDrain(true)
        ih := InputHook("L0 I")
        ih.KeyOpt("{All}", "S")
        ih.KeyOpt("{Esc}", "N")
        ih.OnKeyDown := (ih, vk, sc) => Curtain.EscDown(vk)
        ih.OnKeyUp := (ih, vk, sc) => Curtain.EscUp(vk)
        try {
            loop MonitorGetCount() {
                MonitorGet(A_Index, &l, &t, &r, &b)
                g := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale", "Curtain")
                g.BackColor := "0D0D14"
                g.MarginX := 0, g.MarginY := 0
                w := r - l, h := b - t
                g.SetFont("s96 cF2F2F2", "Yu Gothic UI")
                g.AddText("x0 y" Round(h * 0.30) " w" w " Center", this.Clock(s.deadline))
                g.SetFont("s18 c999999")
                hint := g.AddText("x0 y+24 w" w " Center", this.HINT)
                ; The share of the Esc hold still to go: full at the press, empty at the lift.
                bar := g.AddProgress("x" (w // 2 - 160) " y+36 w320 h10 -Theme cE6E6E6 Background4D4D4D"
                    . " Range0-1000 Hidden", 1000)
                g.Show("x" l " y" t " w" w " h" h)
                WinSetTransparent(245, g)
                this.screens.Push({gui: g, hint: hint, bar: bar})
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
    }

    static EscDown(vk) {
        ; Auto-repeat sends Esc down again and again: only the first starts the count.
        if vk != 0x1B || this.draining || this.holdStart || !this.s.shown
            return
        this.holdStart := A_TickCount
        ; About 30 times a second, so the bar empties smoothly rather than in 5 steps.
        SetTimer(this.HoldTick, 33)
        this.HoldTick.Call()
    }

    static EscUp(vk) {
        if vk != 0x1B
            return
        if this.draining
            return this.StopDrain()
        this.StopHold()
    }

    ; A bound copy, so SetTimer can stop the same object it started.
    static HoldTick := () => Curtain.Hold()

    static Hold() {
        ; A_TickCount does not move with the clock, so changing the time neither shortens nor stretches the hold.
        r := CurtainLogic.HoldLeft((A_TickCount - this.holdStart) / 1000, CurtainLogic.HOLD_SECONDS)
        if r[1] <= 0
            return this.Lift()
        for sc in this.screens {
            sc.bar.Value := Round(r[1] * 1000)
            sc.bar.Visible := true
            sc.hint.Value := "あと " r[2] " 秒"
        }
    }

    static StopHold() {
        SetTimer(this.HoldTick, 0)
        this.holdStart := 0
        for sc in this.screens {
            sc.bar.Visible := false
            sc.hint.Value := this.HINT
        }
    }

    ; The Esc that lifted the curtain is still down: its repeats and its release would land in the
    ; app in front, so they are eaten until the release or DRAIN_MS.
    static Lift() {
        this.Log("lift", "Esc 長押し")
        this.draining := true
        this.ih.KeyOpt("{All}", "-S +V")
        this.ih.KeyOpt("{Esc}", "S")
        SetTimer(() => Curtain.StopDrain(), -this.DRAIN_MS)
        this.Hide()
        this.s.snoozeUntil := CurtainLogic.Now() + CurtainLogic.SNOOZE_SECONDS
        this.Save()
    }

    static StopDrain(always := false) {
        if !this.draining && !always
            return
        this.draining := false
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
