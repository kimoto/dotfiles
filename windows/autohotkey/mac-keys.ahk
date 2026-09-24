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

; init.lua: ctrl+w -> alt+delete (delete word backward).
; DELIBERATELY LEFT OFF on Windows — this is the one remap that does not port:
;   1. Ctrl+W is close-tab / close-window in virtually every Windows app
;      (browsers, Explorer, VS Code, Terminal). Claiming it globally breaks
;      that everywhere. macOS closes with Cmd+W, which is precisely why Ctrl+W
;      is free there for init.lua to take.
;   2. Windows already deletes the previous word on Ctrl+Backspace, so the
;      remap adds far less here than it does on macOS.
; Enable it only as a deliberate trade against close-tab:
; ^w::Send("^{BackSpace}")

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
