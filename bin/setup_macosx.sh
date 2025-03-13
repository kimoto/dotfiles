#!/bin/sh

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

# 起動音をミュート
sudo nvram StartupMute=%01
