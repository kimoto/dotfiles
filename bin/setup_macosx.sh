#!/bin/sh

set -eu

# 音量アイコンをMenuBarに表示
defaults write com.apple.systemuiserver "NSStatusItem Visible com.apple.menuextra.volume" 1

# Quick Lookウィンドウのアニメーションをオフ
defaults write -g QLPanelAnimationDuration -float 0

# 隠しファイルを常に表示
defaults write com.apple.finder AppleShowAllFiles -bool YES

# 拡張子を表示
defaults write -g AppleShowAllExtensions -bool true

# key repeat
defaults write -g KeyRepeat -int 1
defaults write -g InitialKeyRepeat -int 10

# CleanShot X: keep every capture as a file outside the Desktop, copied too,
# in sRGB so it looks the same in any app. A running copy picks these up
# without a restart.
mkdir -p "$HOME/Pictures/Screenshots"
# The app stores an absolute path and does not expand "~".
defaults write pl.maketheweb.cleanshotx exportPath -string "$HOME/Pictures/Screenshots"
# After-capture rows: 1 = Copy file to clipboard, 2 = Save. Integers, not
# strings: with strings the app falls back to its default without a word.
defaults write pl.maketheweb.cleanshotx afterScreenshotActions -array -integer 1 -integer 2
# Off, so "Capture Area & Annotate" and "& Pin" shortcuts save as well.
defaults write pl.maketheweb.cleanshotx ignoreAfterCaptureInShortcutsWithAction -bool false
defaults write pl.maketheweb.cleanshotx convertTosRGB -bool true
defaults write pl.maketheweb.cleanshotx screenshotFormat -string png
# 20261025_075835@2x.png: sorts by capture time, no spaces.
defaults write pl.maketheweb.cleanshotx mediaNameTemplate -array %y %m %d _ %H %M %S

# 起動音をミュート（sudoが要るのはここだけなので、既に設定済みならスキップする）
if [ "$(nvram StartupMute 2>/dev/null | awk '{print $2}')" != "%01" ]; then
    sudo nvram StartupMute=%01
fi
