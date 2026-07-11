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

# zsh_pane_cmd [VAR=value ...]: build the new-session command string that
# launches an interactive zsh pane under the shared CI conventions:
#   - CI is cleared so .zshrc does not enable err_exit and abort on the first
#     non-zero command;
#   - the startup sync-check and brew bundle check are silenced so the pane
#     neither touches the network nor burns seconds of its first-render budget;
#   - TERM is pinned for reproducible rendering.
# Extra VAR=value assignments (e.g. a stubbed PATH) land before zsh. Requires
# $REPO (the ZDOTDIR under test) and $ZSH_BIN, set by every caller.
zsh_pane_cmd() {
  if [ -z "${REPO:-}" ] || [ -z "${ZSH_BIN:-}" ]; then
    die "zsh_pane_cmd needs REPO and ZSH_BIN"
  fi
  local cmd="env CI= ZDOTDIR='$REPO' DOTFILES_NO_SYNC_CHECK=1 DOTFILES_NO_BREW_CHECK=1 TERM=xterm-256color"
  local a
  for a in "$@"; do
    cmd="$cmd $a"
  done
  printf '%s' "$cmd '$ZSH_BIN' -i"
}

# tmux_conf_path: echo the .tmux.conf under test — TMUX_CONF override, else
# $HOME/.tmux.conf, else the repo copy in $PWD.
tmux_conf_path() {
  local conf="${TMUX_CONF:-$HOME/.tmux.conf}"
  [ -f "$conf" ] || conf="$PWD/.tmux.conf"
  [ -f "$conf" ] || die "no .tmux.conf found"
  printf '%s\n' "$conf"
}

# wait_for_pane <socket> <pattern> [tries]: poll `capture-pane -p` until the
# grep -E <pattern> appears, or time out (default 150 tries * 0.1s = 15s).
# Polling beats a fixed sleep — as fast as the shell on a quick runner, as
# forgiving as needed on a slow one; since it returns the instant the pattern
# appears, a larger ceiling never slows a passing assertion, it only widens the
# margin before a genuine failure. The default is deliberately generous: these
# panes run the real .zshrc, whose zsh-defer keeps draining the deferred plugin
# init (fast-syntax-highlighting, autosuggestions, carapace) AFTER the first
# prompt renders, so the shell can be busy for several seconds past the point it
# first looks live — a 5s budget flaked on loaded runners (see the vi-alias step
# in ci_tmux_interactive_test.sh). A step that needs longer still passes an
# explicit larger value.
wait_for_pane() {
  local sock="$1" pattern="$2" tries="${3:-150}" i=0
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
# Same 15s default and rationale as wait_for_pane above.
wait_absent_pane() {
  local sock="$1" pattern="$2" tries="${3:-150}" i=0
  while [ "$i" -lt "$tries" ]; do
    tmux -L "$sock" capture-pane -p 2>/dev/null | grep -qE "$pattern" || return 0
    i=$((i + 1)); sleep 0.1
  done
  die "expected to disappear but still on screen: $pattern"
}
