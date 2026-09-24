# Windows software list

The Windows-side counterpart to `Brewfile.macos`: the apps to reinstall after a
wipe, and which macOS app each one stands in for.

Apply with:

```powershell
winget import --import-file windows\winget-packages.json
```

Already-installed packages are skipped, so re-running it is cheap. It can also
be driven from WSL as `winget.exe import ...`, though anything needing admin
will prompt on the Windows side.

## macOS → Windows

| `Brewfile.macos` | Windows | winget ID | Why this one |
|---|---|---|---|
| `rectangle` | PowerToys (FancyZones) | `Microsoft.PowerToys` | Snap-to-region window management. FancyZones is the direct analogue and PowerToys carries Run + Keyboard Manager too. |
| `raycast` | ueli | `OliverSchwendener.ueli` | Cross-platform launcher in the Alfred/Raycast mould. PowerToys Run is the fallback if one launcher is enough. |
| `hammerspoon` | AutoHotkey v2 | `AutoHotkey.AutoHotkey` | The Hammerspoon config is global emacs-style text remaps that exclude one app (Ghostty). PowerToys Keyboard Manager can remap but cannot *exclude* an app, which is the whole trick — AHK's `#HotIf not WinActive(...)` can. |
| `cleanshot` | ShareX | `ShareX.ShareX` | Region/window/scrolling capture, annotation, upload. The usual CleanShot answer on Windows. |
| `monitorcontrol` | Twinkle Tray | `xanderfrangos.twinkletray` | DDC/CI brightness for external displays from the tray, same job. |
| `ghostty` | Windows Terminal | `Microsoft.WindowsTerminal` | Already the WSL host terminal — see the profile note below. |
| `google-japanese-ime` | same | `Google.JapaneseIME` | Same product. |
| `deepl` | same | `DeepL.DeepL` | Same product. |

## Deliberately not here

- **`stats` → TrafficMonitor** and **`mysql-shell` → MySQL Shell** — fine
  packages, just not wanted on this machine yet. Add
  `zhongyang219.TrafficMonitor.Full` / `Oracle.MySQLShell` to the manifest if
  that changes.
- **`font-jetbrains-mono-nerd-font`** — winget's only offer is
  `DEVCOM.JetBrainsMonoNerdFont`, and its installer is an MSI built by
  `github.com/DevelopersCommunity/wix-JetBrainsMonoNF`: a 34-star, 0-fork,
  single-purpose repo with no publisher URL, whose relationship to ryanoasis'
  official Nerd Fonts releases is not stated. No sign of anything wrong with it,
  but an elevated third-party MSI is a poor trade for a *font*. The font is
  already installed on this machine (the Windows Terminal profile renders with
  it); to reinstall it after a wipe, use scoop's official bucket instead, which
  unpacks ryanoasis' own release assets into the user font directory with no
  admin rights:

  ```powershell
  scoop bucket add nerd-fonts
  scoop install nerd-fonts/JetBrainsMono-NF
  ```

- **`nikitabobko/tap/aerospace`** — the tiling WM is not actually used, so no
  Windows counterpart is installed. If that changes, GlazeWM (`glzr-io.glazewm`)
  is the match: its defaults are already `Alt+H/J/K/L` to focus, `Alt+Shift+…`
  to move and `Alt+1-0` for workspaces, i.e. `.aerospace.toml`'s bindings
  without editing anything. komorebi is the more popular choice but needs a
  separate hotkey daemon (`LGUG2Z.whkd`) and does not follow i3's directional
  model.
- **`gitify`** — no equivalent worth installing; GitHub notifications are read
  in the browser or through `gh`.
- **`font-bitstream-vera-sans-mono-nerd-font`** — not in the winget catalog.
  Scoop's `nerd-fonts` bucket carries it if it is ever needed.
- **`telnet`** — a Windows *optional feature*
  (`dism /online /Enable-Feature /FeatureName:TelnetClient`), not a package.

## Two things this list cannot do

**Config files cannot be symlinked in.** `mklink.sh`'s whole model is symlinks
into `$HOME`, and a symlink created from WSL under `/mnt/c` is not one Windows
can follow — verified here: `LinkType` comes back empty and `Get-Content` fails
with an IOException. Anything under `%APPDATA%` (Windows Terminal's
`settings.json`, an AutoHotkey script, FancyZones layouts) has to be *copied*
into place, not linked.

**`winget export` is not a source of truth.** Exporting this machine produced 66
entries, of which nearly half were redistributables pulled in as dependencies
(11 × VCRedist, 9 × WindowsAppRuntime, 3 × UI.Xaml, 2 × VCLibs), while
everything winget could not map to a source — LINE, NVIDIA Control Panel,
Realtek Audio Control — was dropped silently. Use an export as raw material for
this list, never as the list itself.

## Windows Terminal

Merge the `actions` and `keybindings` arrays from `windows-terminal/keybindings.json`
into the live `settings.json`, retaining other entries and replacing existing
bindings for the same keys. This is a merge fragment, not a complete settings file.
Shift+Enter and Alt+Enter (Option on the Mac keyboard) send LF / Ctrl+J,
which inserts a newline in Claude Code, including through tmux. Plain Enter is unchanged.
These bindings apply to every Terminal profile: at a shell prompt they can execute
commands, and Alt+Enter replaces Terminal's default fullscreen shortcut. Use F11 instead.

`config/ghostty/config` pins `theme = Iterm2 Solarized Dark`, and that exact
scheme has a Windows Terminal port under the same name in
[iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes/blob/master/windowsterminal/iTerm2%20Solarized%20Dark.json).
It is applied to the Ubuntu profile here, and `windows-terminal/schemes.json`
keeps a copy of every custom scheme on this machine so it survives a wipe.

Note it is *not* Windows Terminal's built-in "Solarized Dark", which the profile
used before: the built-in differs from iTerm2's on `brightBlack` (`#002B36` vs
`#335E69`), so the two do not render identically next to a mac.

To restore after a wipe, merge the `schemes` key of
`windows-terminal/schemes.json` into Windows Terminal's `settings.json` and set
the profile's `"colorScheme": "iTerm2 Solarized Dark"`. It has to be a copy, not
a symlink — see above.

Still unmatched: Ghostty runs at `background-opacity = 0.6`; Windows Terminal's
equivalent is `"opacity": 60` with `"useAcrylic": false` on the profile.

## Window management (the `rectangle` layer)

Prefer what already ships. Rectangle's job splits three ways on Windows and
only the last one needs anything installed:

| Want | Use | Setup |
|---|---|---|
| Halves, quarters | **`Win` + arrows** (built in) | none — `WindowArrangementActive` is already 1 |
| Thirds, wider layouts | **`Win` + `Z`** Snap Layouts (Windows 11, pick with number keys) | none — on by default |
| Irregular zones a fraction cannot express | **PowerToys FancyZones** | needs PowerToys upgraded first, see below |

`Win` + `←` then `Win` + `↑` lands a window top-left, i.e. the quadrant keys
Rectangle spends `⌃⌥U/I/J/K` on are already there under a different grip.

What genuinely does *not* survive the port is Rectangle's **key choice**.
Nothing off-the-shelf will put this on `⌃⌥` + arrows: FancyZones cannot rebind
its own trigger keys, and PowerToys Keyboard Manager can scope a remap *to* an
app but has no exclusion, which is
[a long-standing open request](https://github.com/microsoft/PowerToys/issues/29641).
So the choice is Windows' keys with zero moving parts, or a hotkey tool.

**FancyZones needs PowerToys upgraded first.** The installed build is 0.51.1
(2021); current is 0.100.2, and winget cannot upgrade across it — the installer
technology changed, so it wants an uninstall and reinstall, which risks the
existing PowerToys settings.

## AutoHotkey: the `hammerspoon` layer, and the keys Windows will not lend out

`autohotkey/mac-keys.ahk` holds both halves. Outside the terminal it ports the
Hammerspoon remaps that carry over; inside it, it reproduces the Ghostty
keybinds that reach tmux.

The second half is not a preference. A Mac keyboard sends Win where the mac
sends Command, and Windows reserves every `Win+<key>` for the shell — so
`Win+1` launches the first taskbar app and no application may bind it, Windows
Terminal included. Its `settings.json` cannot express these at all, which is
what puts them here rather than beside the rest of the terminal's config.

It is config for an off-the-shelf tool rather than a program, but it *is*
something to maintain, so the alternatives, and why they were not taken:

- **PowerToys Keyboard Manager** — same exclusion gap as above. A global
  `Alt+B` → `Ctrl+Left` would also fire inside Windows Terminal, where zsh
  already binds `Alt+B` to backward-word natively. Breaking the shell to fix
  everything else is the wrong way round.
- **XKeymacs / Keyhac** — real products that do have per-app conditions, but
  both install a whole Emacs-emulation layer. The needed subset is kept in the existing AHK script.

The GUI remaps also cover Ctrl+A/E (line start/end), Ctrl+B/F (character motion),
Ctrl+P/N (up/down), Ctrl+H/D (backward/forward delete), Ctrl+K (delete to line end),
Ctrl+W (delete previous word), and Alt+D (delete next word). Ctrl+K does not keep
an Emacs kill ring. These apply outside Windows Terminal even when focus is not
in a text field, replacing the apps' native Ctrl shortcuts. Use Command/Win+A/F/N/P/W
for select-all, find, new, print, and close-tab instead. Terminal retains native
shell/editor bindings. Reload the copied AHK script after changing it.
