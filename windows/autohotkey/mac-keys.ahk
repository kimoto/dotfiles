#Requires AutoHotkey v2.0
#SingleInstance Force

; The Mac keyboard's keys, made to mean on Windows what they mean on the mac.
; Two halves, and the split is the whole design: outside the terminal this ports
; hammerspoon/init.lua's emacs remaps, inside it this ports the Ghostty keybinds
; that reach tmux. Keep all three in sync, and update KEYBINDINGS.md when any of
; them changes.
;
; Why any of this needs AutoHotkey at all: a Mac keyboard sends Win where the
; mac sends Command, and Windows reserves every Win+<key> for the shell -- Win+1
; launches the first taskbar app and no application, Windows Terminal included,
; is allowed to bind it. Intercepting it here is the only way to get the mac's
; Command+1 back.
;
; init.lua disables its remaps whenever Ghostty is frontmost, because zsh and
; nvim implement these bindings themselves and remapping there would either
; double-apply or shadow the real ones. Windows Terminal is the same terminal
; on this side, so it gets the same exemption — #HotIf is evaluated per
; keystroke against the active window, which is what the Hammerspoon app
; watcher is doing by hand.
#HotIf !WinActive("ahk_exe WindowsTerminal.exe")

; init.lua: alt+b -> alt+left, alt+f -> alt+right (move by word).
; Neither OS binds Alt+B/Alt+F to word motion natively, so this is the part
; that genuinely carries over.
!b::Send("^{Left}")
!f::Send("^{Right}")

; init.lua: ctrl+/ -> cmd+z (undo).
^/::Send("^z")

; Basic Emacs-style editing outside Windows Terminal. Command/Win shortcuts
; below retain select-all, find, new, print, and close-tab on the Mac keyboard.
; These apply throughout GUI apps, including when focus is not in a text field.
; Ctrl+K deletes to end of line (or the next newline at EOL); no kill ring.
^a::Send("{Home}")
^e::Send("{End}")
^b::Send("{Left}")
^f::Send("{Right}")
^p::Send("{Up}")
^n::Send("{Down}")
^h::Send("{BackSpace}")
^d::Send("{Delete}")
^k::Send("+{End}{Delete}")
^w::Send("^{BackSpace}")
!d::Send("^{Delete}")

; --- Command as Command ---------------------------------------------------
; The Mac keyboard's Command arrives as Win, so ⌘+C is physically Win+C, and
; Windows spends Win+<letter> on shell shortcuts. Except here: NoWinKeys is set
; on this machine, which kills every one of them. Nothing is being taken away,
; which is the only reason these are a straight remap rather than a negotiation.
;
; Left out on purpose, each because the mac key means something Windows has no
; equal of rather than because the chord is taken:
;   ⌘+Q  quits the application; Alt+F4 closes a window. Same finger, different
;        blast radius, and the wrong one is unrecoverable.
;   ⌘+H  hides an application. Windows has no such state.
;   ⌘+M  minimises -- Win+Down already does, and is not shadowed here.
;   ⌘+Tab is a held-modifier cycle with its own switcher UI. Send can produce
;        one hop, which feels like a broken Alt+Tab rather than a Command+Tab.
;   ⌘+L  would be the address bar, and is the one entry here that is not a
;        judgement call: Win+L locks the workstation from below the hook layer,
;        where NoWinKeys does not reach and AutoHotkey cannot intercept. The
;        remap would not fire and the screen would lock instead.
#a::Send("^a")
#c::Send("^c")
#f::Send("^f")
#n::Send("^n")
#p::Send("^p")
#r::Send("^r")
#s::Send("^s")
#t::Send("^t")
#v::Send("^v")
#w::Send("^w")
#x::Send("^x")
#z::Send("^z")

#+z::Send("^y")        ; ⇧⌘+Z  redo
#+t::Send("^+t")       ; ⇧⌘+T  reopen the tab just closed

; Line and document motion. Win+<arrow> is Windows' snap, and is dead here for
; the same reason as the letters above.
#Left::Send("{Home}")
#Right::Send("{End}")
#Up::Send("^{Home}")
#Down::Send("^{End}")

#HotIf

; ---------------------------------------------------------------------------
; Inside Windows Terminal: what Ghostty's Command bindings reach on the mac.
; ---------------------------------------------------------------------------
; .tmux.conf binds these with -n (no prefix): M-1..9 select a window,
; M-Left/Right change window, M-Up/Down change session. So all this has to do is
; put Alt on the wire and let the terminal encode it -- Windows Terminal turns
; Alt+Left into the same ESC [1;3D that Ghostty spells out by hand, because
; Ghostty is starting from Command+Option and has no Alt chord to forward.
;
; Sending those bytes literally instead does not work, and fails in a way worth
; recording: Send("{Esc}") and SendText("[1;3D") are injected through different
; paths, so the body arrives as separate character events, tmux never sees a CSI
; and the terminal prints a bare `1;3D`.
#HotIf WinActive("ahk_exe WindowsTerminal.exe")

#1::Send("!1")
#2::Send("!2")
#3::Send("!3")
#4::Send("!4")
#5::Send("!5")
#6::Send("!6")
#7::Send("!7")
#8::Send("!8")
#9::Send("!9")

#!Left::Send("!{Left}")
#!Right::Send("!{Right}")
#!Up::Send("!{Up}")
#!Down::Send("!{Down}")

#HotIf

; ShareX's image editor hard-codes Ctrl+Shift+C to "copy annotation", so ⇧⌘C
; sends Enter ("done", which copies the image) instead, as in CleanShot X.
#HotIf WinActive("ShareX - Image Editor ahk_exe ShareX.exe")
#+c::Send("{Enter}")
#HotIf

; Rectangle-style window controls, including Windows Terminal. See KEYBINDINGS.md.
; Force the keyboard hook so Windows desktop/accessibility shortcuts do not win.
; Repeated half/quarter keys cycle 1/2 -> 2/3 -> 1/3 like Rectangle.
; Quarter actions keep half height and cycle only their width.
#HotIf
$^#a::RectangleMove("left")
$^#d::RectangleMove("right")
$^#k::RectangleMove("top")
$^#j::RectangleMove("bottom")
$^#[::RectangleMove("topLeft")
$^#]::RectangleMove("topRight")
$^#'::RectangleMove("bottomLeft")
$^#\::RectangleMove("bottomRight")
$^#f::RectangleMove("maximize")
$^#s::RectangleMove("center")
$^#x::RectangleMove("centerHalf")
$^#;::RectangleMove("larger")
$^#-::RectangleMove("smaller")
$^#o::RectangleMove("restore")
$^#g::RectangleMove("next")
$^#Left::RectangleMove("edgeLeft")
$^#Right::RectangleMove("edgeRight")
$^#Up::RectangleMove("edgeTop")
$^#Down::RectangleMove("edgeBottom")

RectangleMove(action, hwnd := 0) {
    static originals := Map()
    static cycles := Map()
    if !hwnd
        hwnd := WinExist("A")
    if !hwnd
        return
    target := "ahk_id " hwnd
    ; Use physical pixels consistently across monitors with different scaling.
    previousDpi := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        if WinGetClass(target) ~= "^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd)$"
            return
        ; Discard closed windows and protect against a reused HWND from another process.
        for savedHwnd, saved in originals.Clone() {
            if !WinExist("ahk_id " savedHwnd) || WinGetPID("ahk_id " savedHwnd) != saved.pid {
                originals.Delete(savedHwnd)
                if cycles.Has(savedHwnd)
                    cycles.Delete(savedHwnd)
            }
        }
        if action = "restore" {
            if originals.Has(hwnd) {
                saved := originals[hwnd]
                WinRestore(target)
                WinMove(saved.x, saved.y, saved.w, saved.h, target)
                if saved.maximized
                    WinMaximize(target)
                originals.Delete(hwnd)
            }
            if cycles.Has(hwnd)
                cycles.Delete(hwnd)
            return
        }
        if action = "next" && MonitorGetCount() = 1
            return
        wasMaximized := WinGetMinMax(target) = 1
        monitor := RectangleMonitor(hwnd)
        if wasMaximized
            WinRestore(target)
        WinGetPos(&x, &y, &w, &h, target)
        if !originals.Has(hwnd)
            originals[hwnd] := {x: x, y: y, w: w, h: h, pid: WinGetPID(target), maximized: wasMaximized}
        if action = "maximize" {
            if cycles.Has(hwnd)
                cycles.Delete(hwnd)
            WinMaximize(target)
            return
        }
        MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
        ; DWM visible borders exclude Windows' invisible resize frame.
        frame := Buffer(16)
        visible := DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 9,
            "ptr", frame, "uint", frame.Size, "int") = 0
        ml := visible ? NumGet(frame, 0, "int") - x : 0
        mt := visible ? NumGet(frame, 4, "int") - y : 0
        mr := visible ? x + w - NumGet(frame, 8, "int") : 0
        mb := visible ? y + h - NumGet(frame, 12, "int") : 0
        x += ml, y += mt, w -= ml + mr, h -= mt + mb
        areaW := right - left, areaH := bottom - top
        halfW := Floor(areaW / 2), halfH := Floor(areaH / 2)
        cycleActions := Map("left", true, "right", true, "top", true, "bottom", true,
            "topLeft", true, "topRight", true, "bottomLeft", true, "bottomRight", true)
        if cycleActions.Has(action) {
            previous := cycles.Has(hwnd) ? cycles[hwnd] : {action: "", step: 0}
            step := previous.action = action ? Mod(previous.step, 3) + 1 : 1
            cycles[hwnd] := {action: action, step: step}
        } else {
            if cycles.Has(hwnd)
                cycles.Delete(hwnd)
            step := 1
        }
        fraction := step = 1 ? 0.5 : step = 2 ? 2 / 3 : 1 / 3
        switch action {
            case "left":
                x := left, y := top, w := Round(areaW * fraction), h := areaH
            case "right":
                w := Round(areaW * fraction), x := right - w, y := top, h := areaH
            case "top":
                x := left, y := top, w := areaW, h := Round(areaH * fraction)
            case "bottom":
                h := Round(areaH * fraction), x := left, y := bottom - h, w := areaW
            case "topLeft", "topRight", "bottomLeft", "bottomRight":
                isRight := InStr(action, "Right"), isBottom := InStr(action, "bottom")
                w := Round(areaW * fraction)
                x := isRight ? right - w : left, y := top + (isBottom ? halfH : 0)
                h := isBottom ? areaH - halfH : halfH
            case "centerHalf":
                w := halfW, h := areaH, x := left + Floor((areaW - w) / 2), y := top
            case "center":
                x := left + Floor((areaW - w) / 2), y := top + Floor((areaH - h) / 2)
            case "larger", "smaller":
                direction := action = "larger" ? 1 : -1
                newW := Min(areaW, Max(160, w + Round(areaW * 0.1) * direction))
                newH := Min(areaH, Max(100, h + Round(areaH * 0.1) * direction))
                x := Max(left, Min(right - newW, x - Floor((newW - w) / 2)))
                y := Max(top, Min(bottom - newH, y - Floor((newH - h) / 2)))
                w := newW, h := newH
            case "edgeLeft":
                x := left
            case "edgeRight":
                x := right - w
            case "edgeTop":
                y := top
            case "edgeBottom":
                y := bottom - h
            case "next":
                MonitorGetWorkArea(Mod(monitor, MonitorGetCount()) + 1, &nl, &nt, &nr, &nb)
                ; Preserve relative size/position when moving between unlike displays.
                x := nl + Round((x - left) * (nr - nl) / areaW)
                y := nt + Round((y - top) * (nb - nt) / areaH)
                w := Min(nr - nl, Round(w * (nr - nl) / areaW))
                h := Min(nb - nt, Round(h * (nb - nt) / areaH))
                x := Max(nl, Min(nr - w, x)), y := Max(nt, Min(nb - h, y))
        }
        WinMove(x - ml, y - mt, w + ml + mr, h + mt + mb, target)
        if action = "next" && wasMaximized
            WinMaximize(target)
    } catch TargetError {
        ; The focused window may close between the hotkey and WinMove.
        return
    } catch OSError as err {
        ; Some elevated or non-resizable apps refuse window operations.
        TrayTip("Window could not be moved: " err.Message, "Rectangle shortcuts")
    } finally {
        if previousDpi
            DllCall("SetThreadDpiAwarenessContext", "ptr", previousDpi, "ptr")
    }
}

RectangleMonitor(hwnd) {
    handle := DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr")
    info := Buffer(40, 0)
    NumPut("uint", 40, info)
    if DllCall("GetMonitorInfoW", "ptr", handle, "ptr", info) {
        loop MonitorGetCount() {
            MonitorGet(A_Index, &left, &top, &right, &bottom)
            if left = NumGet(info, 4, "int") && top = NumGet(info, 8, "int")
                return A_Index
        }
    }
    return MonitorGetPrimary()
}
