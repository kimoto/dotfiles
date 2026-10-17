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

## Codex

Run `./windows/link_codex.ps1` in PowerShell. It merges the defaults from [codex/config.toml](../codex/config.toml) while preserving the app's machine-specific settings, then shares Claude instructions and rules through native Windows symlinks. The script locates the checkout automatically; see [Codex setup](../codex/README.md).

## macOS → Windows

| `Brewfile.macos` | Windows | winget ID | Why this one |
|---|---|---|---|
| `rectangle` | PowerToys (FancyZones) | `Microsoft.PowerToys` | Snap-to-region window management. FancyZones is the direct analogue and PowerToys carries Run + Keyboard Manager too. |
| `raycast` | PowerToys (Command Palette, Advanced Paste) | `Microsoft.PowerToys` | Command Palette is the closest launcher to Raycast, and Advanced Paste in the same suite covers the searchable clipboard history that Raycast supplied on the mac. One install instead of a separate launcher. |
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

- **`nikitabobko/tap/aerospace`** — configured and used on macOS
  (`.aerospace.toml`, the AeroSpace section of `KEYBINDINGS.md`), but has no
  Windows counterpart installed here yet. If that changes, GlazeWM
  (`glzr-io.glazewm`) is the match: its defaults are already `Alt+H/J/K/L` to
  focus, `Alt+Shift+…` to move and `Alt+1-0` for workspaces, i.e.
  `.aerospace.toml`'s bindings without editing anything. komorebi is the more
  popular choice but needs a separate hotkey daemon (`LGUG2Z.whkd`) and does
  not follow i3's directional model.
- **`displayplacer`** — drives `hammerspoon/displays.lua`, which restores the
  display arrangement per set of monitors. Windows already remembers that per
  set of monitors on its own, so nothing needs installing.
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

## Window management (the `rectangle` layer)

`autohotkey/mac-keys.ahk` implements the customized Rectangle keys listed in
`KEYBINDINGS.md`, with Ctrl+Win in place of Ctrl+Command. They apply in every
app, including Windows Terminal. The keyboard hook intercepts the chords that
Windows normally uses for virtual desktops or accessibility features.

The script places windows directly in the monitor work area (excluding the
taskbar), rather than forwarding Windows snap keys. It supports halves,
quarters, center, center half, maximize, resize, edges without resizing, and
moving to the next monitor in Windows monitor order. Visible window borders
are used for alignment. Apps may enforce their own minimum size.

Restore returns to the position, size, and maximized state before the first
window operation, until restored or the script exits. Repeated half and quarter keys cycle through 1/2, 2/3, and 1/3;
quarter actions change only the width. Larger/smaller changes each dimension by 10% of the work
area, centered and bounded by the screen; this is an explicit Windows default,
not a value recovered from the Mac. Next display preserves relative geometry
and keeps a maximized window maximized. Todo mode is not used or mapped.

Copy the updated `mac-keys.ahk` to the live script location and reload it.
Do not assign the same shortcuts in Raycast or another window manager.
Elevated apps may require running AutoHotkey at matching privileges. Mixed-DPI
monitor transitions and punctuation keys should also be checked on the actual
keyboard and monitors.

## AutoHotkey: the `hammerspoon` layer, and the keys Windows will not lend out

`autohotkey/mac-keys.ahk` holds both halves. Outside the terminal it ports the
Hammerspoon remaps that carry over; inside it, it reproduces the Ghostty
keybinds that reach tmux.

The second half is not a preference. A Mac keyboard sends Win where the mac
sends Command, and Windows reserves `Win+<key>` for the shell, so no
application may bind it, Windows Terminal included. Its `settings.json` cannot
express these at all, which is what puts them here rather than beside the rest
of the terminal's config. (On this machine the shell's own `Win+<key>`
shortcuts are also turned off, see `NoWinKeys` below, but that does not let
Windows Terminal bind them.)

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

## Restoring this machine's arrangement

`winget import` brings the apps back, but not how they are set up. These are
the steps a wipe has to repeat by hand, in order.

### 1. Turn off the shell's `Win+<key>` shortcuts (`NoWinKeys`)

```powershell
New-Item -Force 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' |
  New-ItemProperty -Name NoWinKeys -PropertyType DWord -Value 1 -Force
```

Sign out and back in to apply. This is what lets ⌘ (Win on a Mac keyboard)
act as Ctrl everywhere without Windows taking the key first.

What it turns off depends on who registers the hotkey, not on whether it
contains `Win`:

- **Off:** anything the shell itself handles: `Win+1..9` (taskbar apps),
  `Win+V` (clipboard history), `Win+E`, `Win+R`, `Win+<arrow>` (snap).
  Clipboard history can show as enabled in Settings and still never open.
- **Still fires:** hotkeys AutoHotkey and PowerToys register through their own
  keyboard hooks, `Win` combos included. Avoiding `Win` in every binding is
  stricter than needed.
- **Exception:** `Win+L` locks the workstation regardless. `NoWinKeys` does not
  disable it and AutoHotkey cannot intercept it, so a remap of it never fires.

### 2. PowerToys

- **Turn on "Run at startup" after every reinstall.** An uninstall and install
  (which winget needs to cross a large version gap) resets it to off, and every
  hotkey below then silently stops working after the next reboot.
- Hotkeys, set in each module's settings:

  | Module | Hotkey | Why |
  |---|---|---|
  | Command Palette | `Ctrl+Space` | The launcher, same key as Raycast on the mac. |
  | Advanced Paste | `Ctrl+Win+V` | ⌃⌘+V on a Mac keyboard, Raycast's clipboard history key. |
  | Peek | `Win+Shift+P` | Ships on `Ctrl+Space`; moved so Command Palette can have it. |
  | PowerToys Run | `Alt+Space` (default) | Left as shipped. |

- **Collisions to expect.** PowerToys' defaults assume `Win+<key>` belongs to
  Windows. Here it does not, so its defaults compete with the AutoHotkey
  bindings, and each newly enabled module is a chance to collide. Known one:
  Text Extractor ships on `Win+Shift+T`, which is ⇧⌘+T (reopen tab) here. It is
  harmless only while Text Extractor stays disabled.
- **Not enabled, but available:** Alt Window Cycle is the counterpart of ⌘+`
  (switch windows within an app).
- The upgrade from 0.51 to 0.101 lost nothing: FancyZones had no custom
  layouts or app history, Keyboard Manager had no remaps, and PowerToys Run was
  on its default hotkey. winget still refuses that upgrade in place, so it
  takes an uninstall and install.

### 3. Start the AutoHotkey script at login

The script cannot be linked (see "Two things this list cannot do"), so:

1. Copy `autohotkey/mac-keys.ahk` to `%USERPROFILE%\bin\`.
2. In the Startup folder (`shell:startup`), create a shortcut whose target is
   `AutoHotkey64.exe` with the copied script as its argument.

After changing the script in this repo, copy it again and reload it.
