#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; Runs mac-keys.ahk straight from the WSL checkout and restarts it when the
; file changes, so a pull is the whole deploy. This is the one file copied to
; Windows, and it says so when its copy has drifted from the repo's. The
; watching lives here, not in mac-keys.ahk, because a read over
; \\wsl.localhost can stall, and there it would stall the hotkeys with it.
;
; Usage: AutoHotkey64.exe launch-mac-keys.ahk \\wsl.localhost\<distro>\...\mac-keys.ahk

if (A_Args.Length != 1
    || !RegExMatch(A_Args[1], "i)^\\\\wsl(?:\.localhost|\$)\\([^\\]+)\\", &match))
    Fail("Usage: launch-mac-keys.ahk \\wsl.localhost\<distro>\...\mac-keys.ahk")
target := A_Args[1]
distro := match[1]

; Start the distro first, so the path is served by WSL when it is read rather
; than resolved by whatever answers the name while WSL is still booting. At
; login this start is the wait, which is why it has no timeout.
A_IconTip := "mac-keys: starting WSL (" distro ")"
; Both exit -1 without running anything: a quoted distro name, and -e given a
; bare `true` rather than a path. Distro names cannot hold spaces.
if (RunWait("wsl.exe -d " distro " -e /bin/true", , "Hide") != 0)
    Fail("wsl.exe could not start the distro " distro ".")
if !FileExist(target)
    Fail(target " does not exist. If the checkout moved or was a removed worktree, "
        . "run windows\install_mac_keys.ps1 from the main checkout.")

A_IconTip := "mac-keys: running " target
try loadedTime := FileGetTime(target, "M")
catch as err
    Fail("Cannot read " target ": " err.Message)
Run('"' A_AhkPath '" "' target '"')
SetTimer(RestartWhenChanged, 2000)
WarnIfLauncherDrifted()

; Restarts only once the mtime has held for one tick, so a checkout caught
; mid-write is not loaded. A version that fails to load needs no guard:
; AutoHotkey refuses it with a dialog and keeps the running one. (mac-keys.ahk
; does nothing at load but define hotkeys, so failing to load is the only way
; a pulled version can break it.) The poll also keeps WSL from idling out,
; which the hotkeys depend on anyway.
RestartWhenChanged() {
    global loadedTime
    static changedTime := "", unreadable := false
    try now := FileGetTime(target, "M")
    catch {
        ; A WSL restart passes in a tick or two; a moved checkout does not, so
        ; say it once rather than stop following the repo in silence.
        if !unreadable
            TrayTip("Cannot read " target "; not following the repo until it is back.", "mac-keys", "Iconx")
        unreadable := true
        A_IconTip := "mac-keys: cannot read " target
        return
    }
    if unreadable {
        unreadable := false
        A_IconTip := "mac-keys: running " target
    }
    if (now = loadedTime) {
        changedTime := ""
        return
    }
    if (now != changedTime) {
        changedTime := now
        return
    }
    loadedTime := now
    Run('"' A_AhkPath '" /restart "' target '"')
}

WarnIfLauncherDrifted() {
    SplitPath(target, , &repoDir)
    repoCopy := repoDir "\launch-mac-keys.ahk"
    try repoText := FileRead(repoCopy)
    catch {
        MsgBox("Cannot read " repoCopy " to check this launcher against it.", "mac-keys", "Icon!")
        return
    }
    if (repoText !== FileRead(A_ScriptFullPath))  ; != ignores case
        MsgBox(A_ScriptFullPath " differs from the repo's copy.`n"
            . "Run windows\install_mac_keys.ps1 again.", "mac-keys", "Icon!")
}

Fail(message) {
    MsgBox(message, "mac-keys", "Iconx")
    ExitApp(1)
}
