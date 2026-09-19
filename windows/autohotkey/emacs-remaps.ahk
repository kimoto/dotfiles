#Requires AutoHotkey v2.0
#SingleInstance Force

; Windows port of hammerspoon/init.lua's global emacs-style remaps.
; Keep the two in sync, and update KEYBINDINGS.md when either changes.
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

#HotIf
