#!/bin/bash
# Puts Homebrew's bin on PATH when brew is installed, so a script finds brew's
# tmux, nvim or zsh (newer than the OS package) without a login shell having
# run first. This file is *sourced*, not executed:
#
#   # shellcheck source=bin/brew_lib.sh
#   . "<path to bin>/brew_lib.sh"
#   load_brew
#
# A machine has one of the two prefixes, so the order never decides anything.

load_brew() {
  if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  elif [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
}
