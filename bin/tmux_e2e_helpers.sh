#!/bin/bash
# Shared helpers for the tmux e2e tests (bin/ci_tmux_*_test.sh). This file is
# *sourced*, not executed — it only defines functions and, as a side effect of
# sourcing, puts a Homebrew tmux/zsh on PATH when available. Keep it dependency-
# free so every test can source it the same way:
#
#   DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
#   # shellcheck source=/dev/null
#   . "$DIR/tmux_e2e_helpers.sh"

# Prefer a Homebrew tmux/zsh (newer) when the shellenv is available.
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

die() { echo "CI error: $*" >&2; exit 1; }

# need <cmd>: abort unless <cmd> is on PATH.
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not installed"; }

# tmux_conf_path: echo the .tmux.conf under test — TMUX_CONF override, else
# $HOME/.tmux.conf, else the repo copy in $PWD.
tmux_conf_path() {
  local conf="${TMUX_CONF:-$HOME/.tmux.conf}"
  [ -f "$conf" ] || conf="$PWD/.tmux.conf"
  [ -f "$conf" ] || die "no .tmux.conf found"
  printf '%s\n' "$conf"
}

# wait_for_pane <socket> <pattern> [tries]: poll `capture-pane -p` until the
# grep -E <pattern> appears, or time out (default 50 tries * 0.1s). Polling
# beats a fixed sleep — as fast as the shell on a quick runner, as forgiving as
# needed on a slow one.
wait_for_pane() {
  local sock="$1" pattern="$2" tries="${3:-50}" i=0
  while [ "$i" -lt "$tries" ]; do
    tmux -L "$sock" capture-pane -p 2>/dev/null | grep -qE "$pattern" && return 0
    i=$((i + 1)); sleep 0.1
  done
  echo "---- pane contents at timeout ----" >&2
  tmux -L "$sock" capture-pane -p >&2 2>/dev/null || true
  die "timed out waiting for: $pattern"
}

# wait_absent_pane <socket> <pattern> [tries]: poll until <pattern> is no longer
# on screen (e.g. to confirm a clear-screen landed before asserting a redraw).
wait_absent_pane() {
  local sock="$1" pattern="$2" tries="${3:-50}" i=0
  while [ "$i" -lt "$tries" ]; do
    tmux -L "$sock" capture-pane -p 2>/dev/null | grep -qE "$pattern" || return 0
    i=$((i + 1)); sleep 0.1
  done
  die "expected to disappear but still on screen: $pattern"
}
