# Translator on Windows (and Linux)

Design only; nothing here is built yet. The Mac translator (`hammerspoon/translate.lua` + `hammerspoon/translate.py`, keys in `KEYBINDINGS.md` "Translation") gets a Windows version, and the question is whether to keep Hammerspoon or move everything to one cross-platform app.

**Decision: keep a thin hotkey shell per OS, and make everything behind it shared.** Hammerspoon stays on the Mac, AutoHotkey v2 (already installed for `mac-keys.ahk` and the curtain) is the Windows shell, and Linux gets the CLI only. What becomes shared: the Python core, already OS-agnostic except for four calls, and the popup page, which moves out of `translate.lua` into one HTML file that both hosts load.

## Why not one cross-platform app

The part that differs per OS is small and is exactly what an OS-native tool does best: a global hotkey, sending the copy keystroke, and asking the focused app what kind of element has focus (`hs.axuielement` on the Mac; UI Automation on Windows). A cross-platform framework does not remove that part; it wraps it in a third-party crate or package and moves the OS permissions onto a binary we build ourselves.

| Option | Hotkey / selection | Popup | Effort to parity | Cost that decides it |
|---|---|---|---|---|
| **A. Per-OS shell + shared core and popup** (chosen) | Hammerspoon / AHK v2, both already installed and permitted | one HTML page; `hs.webview` on Mac, pywebview (WebView2) on Windows | ~3–4 days, 3 PRs | two shells to keep in step, ~150 lines each |
| B. Tauri app | `global-shortcut` plugin; copy keystroke and focus role via extra crates | system webview | 2–3 weeks | Rust toolchain; an unsigned rebuild on the Mac can lose its Accessibility and Screen Recording grants, which Hammerspoon already holds |
| C. Python tray app on all OSes | pynput / keyboard | pywebview | 1.5–2 weeks | macOS grants attach to the venv's Python, so a Python upgrade silently drops them; replaces a Mac version that works |
| D. PowerToys Command Palette extension | none: it is a launcher, text is pasted in | palette list | ~1 week | Windows only, C#, and changes the UX from "select and press" to "open and paste" |

Dropping Hammerspoon would buy nothing: Windows needs its own hotkey layer whatever the Mac uses, and the curtain Spoon lives there too.

## What each OS does

| Concern | Mac (today) | Windows (new) | Linux |
|---|---|---|---|
| Hotkeys | `hs.hotkey.bind` ⌃⌘⇧D/S/L/W | AHK v2 in `mac-keys.ahk`'s include set; Ctrl+Win+Shift+D/S/L/W, the same physical keys, since a Mac keyboard sends Win for ⌘ (`mac-keys.ahk`); Ctrl+Win+Shift+B is the one combination Windows reserves | none: `translate.py` from a terminal |
| Selected text | ⌘C, then wait on `hs.pasteboard.changeCount` (0.5 s) | `A_Clipboard := ""`, `^c`, `ClipWait 0.5` | stdin, or `wl-paste` / `xclip` if present |
| Which job ⌃⌘⇧W guesses | `AXRole` of the focused element + app bundle ID | process name (`WinGetProcessName`) for chat apps; focused control class for text fields. Weaker in Electron and browsers, so a wrong guess is one tab away, as on the Mac | — |
| Region (⌃⌘⇧L) | `screencapture -i` | `ms-screenclip:` (Snipping Tool), then the core reads the image from the clipboard | `--image FILE` |
| Popup | `hs.webview` + `POPUP_HTML` | the same page in a pywebview window, started once at login by AHK and kept running, so a key press only sends a job | — |
| Key store | `security` (Keychain) | Windows Credential Manager | Secret Service, or no key: ant sign-in |

## The shared core

`translate.py` keeps its CLI and its job logic. Four calls become per-OS behind one small module:

- **Key store** → the `keyring` package. Its macOS backend reads the same generic password (`service=desktop-translate`, `account=anthropic`), so the Mac needs no migration. The key is still read inside the process, never from the environment.
- **Clipboard** → `pbcopy`/`pbpaste` on the Mac, the Win32 clipboard on Windows (through pywebview's own pythonnet, or `ctypes`), so no extra package for text.
- **Screen region** → `screencapture` / clipboard image.
- **Fallback dialog** (`osascript`) → only for `--quiet`-less CLI use; on Windows and Linux the result goes to stdout and the clipboard.

Data stays where it is per OS: `~/.local/share/desktop-translate/` on Mac and Linux, `%LOCALAPPDATA%\desktop-translate\` on Windows (config, instructions, style, rewrite log; same 0600 intent, set with an ACL on Windows).

## The shared popup

`POPUP_HTML` (tabs, streaming, ⚙ settings, editable rewrite, rich-text and PNG copy) moves to `hammerspoon/translate-popup.html`, next to `markdown.js`. The page talks to its host through one tiny bridge object, `host.send(msg)` / `window.update(...)`, implemented by `hs.webview.usercontent` on the Mac and by pywebview's `js_api` on Windows. One page means one place to fix, and it can be tested headless in a browser.

## Auth

- **ant sign-in** (`ant auth login`): `ant` ships for macOS, Linux and Windows, and the core already finds its profile through the SDK's `CredentialsFile`, which knows each OS's path. This is the default on a new machine, since it needs no key at all.
- **API key**: from Bitwarden, piped into the store, never typed into argv: `bw get password <item> | translate.py --save-key anthropic` (a new flag reading stdin), or the popup's ⚙ as today.
- Both stay on the machine; nothing secret enters this repo.

## Install

- Mac: unchanged (venv + `requirements.txt` with hashes).
- Windows: `windows/setup.ps1` gains a step: `winget` Python (pinned ID), a venv at `%LOCALAPPDATA%\desktop-translate\venv`, `pip install --require-hashes -r` a Windows lock (pywebview adds pythonnet and its own deps, so the lock is per-OS). AHK includes `translate.ahk` from `mac-keys.ahk`, so no new Startup entry. `winget-packages.json` drops DeepL once this works.
- Linux: nothing by default; the CLI works from the checkout with the Mac's requirements.

## Tests and CI

The repo is public, so the extra Windows minutes are free.

- Core: the existing `test/translate.bats` cases, with the OS module stubbed, also on the `windows-2025` job that already runs bats in Git Bash.
- Popup: a Playwright test that loads `translate-popup.html` with a fake host and checks streaming, tabs and copy, on Linux. It covers both hosts' page.
- Windows shell: `test/translate_ahk.ps1` next to `test/curtain_ahk.ps1`, driving the real AutoHotkey on the runner with the core replaced by a stub that echoes its arguments.
- Real translations and the real Mac GUI stay manual, as `hammerspoon_translate_test.sh` does today (`docs/scouts.md`).

## Order of work

1. Core: the OS module, `keyring`, `--save-key` from stdin. Mac behaviour unchanged, checked by the existing bats.
2. Popup page out of `translate.lua`, behind the bridge, with its Playwright test. Mac behaviour unchanged.
3. Windows: pywebview host, `translate.ahk`, `setup.ps1` step, tests. Then one hand check on the real Windows machine (about 30 minutes: install, sign in, the four keys).

Stop there if the Windows popup's first words take over a second after the key press with the resident host; that would point back to option B's resident app, not to more tuning.
