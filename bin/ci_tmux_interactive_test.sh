#!/bin/bash
# Interactive end-to-end test: drives a real terminal by sending keystrokes into
# a tmux pane and asserting on the rendered screen (capture-pane) — the TUI
# equivalent of a browser e2e (Playwright). This is deliberately distinct from
# ci_zsh_loading_test.sh: that one only checks that .zshrc *loads* (via a
# `script` pty), whereas this drives an interactive zsh rendered in a real
# terminal and verifies it responds correctly to typed input and zle key
# presses — the line editor, history recall, and aliases-in-a-real-tty path that
# a non-interactive load can never exercise.
#
# Scope note: tmux's own key bindings (prefix tables) cannot be exercised this
# way. `send-keys` feeds the pane's program directly and bypasses tmux's key
# interpretation, so a sent `M-t` reaches zsh rather than triggering a binding.
# Driving tmux bindings would require attaching a real client, which is not
# available headless; .tmux.conf parsing is covered by ci_tmux_loading_test.sh.
set -euo pipefail

die() { echo "CI error: $*" >&2; exit 1; }

# Prefer a Homebrew zsh/tmux (newer) when the shellenv is available.
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

command -v tmux >/dev/null 2>&1 || die "tmux not installed"
command -v zsh >/dev/null 2>&1 || die "zsh not installed"
ZSH_BIN="$(command -v zsh)"
REPO="$PWD"
[ -f "$REPO/.zshrc" ] || die "no .zshrc in $REPO"
echo "== $(tmux -V), $("$ZSH_BIN" --version) =="

SOCK="ci_tmux_e2e_$$"
cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null || true; }
trap cleanup EXIT

# Poll capture-pane until $1 (a grep -E pattern) appears, or time out. Sampling
# the pane in a loop (rather than a fixed sleep) keeps the test as fast as the
# shell on a quick runner and as forgiving as needed on a slow one.
wait_for() {
  local pattern="$1" tries="${2:-50}" i=0
  while [ "$i" -lt "$tries" ]; do
    if tmux -L "$SOCK" capture-pane -p 2>/dev/null | grep -qE "$pattern"; then
      return 0
    fi
    i=$((i + 1))
    sleep 0.1
  done
  echo "---- pane contents at timeout ----" >&2
  tmux -L "$SOCK" capture-pane -p >&2 || true
  die "timed out waiting for: $pattern"
}

# Poll until $1 is no longer on screen (used to confirm a clear-screen landed
# before asserting that history recall re-draws a previously cleared line).
wait_absent() {
  local pattern="$1" tries="${2:-50}" i=0
  while [ "$i" -lt "$tries" ]; do
    if ! tmux -L "$SOCK" capture-pane -p 2>/dev/null | grep -qE "$pattern"; then
      return 0
    fi
    i=$((i + 1))
    sleep 0.1
  done
  die "expected to disappear but still on screen: $pattern"
}

# Launch an *interactive* zsh inside a real (tmux) terminal. ZDOTDIR points at
# the repo (same convention as the loading test); CI is cleared so .zshrc does
# not enable err_exit and abort on the first non-zero command; the sync-check is
# silenced so it neither touches the network nor adds noise to the pane.
tmux -L "$SOCK" new-session -d -x 200 -y 50 \
  "env CI= ZDOTDIR='$REPO' DOTFILES_NO_SYNC_CHECK=1 TERM=xterm-256color '$ZSH_BIN' -i" ||
  die "failed to start tmux session"

# 1) The interactive shell is live and rendering. Typing a command and seeing
#    its *computed* output ($((6 * 7)) -> 42) on screen proves the full
#    keystroke -> eval -> render path through a genuine terminal.
# shellcheck disable=SC2016  # single-quoted on purpose: zsh in the pane must
# evaluate $((6 * 7)), not this shell.
tmux -L "$SOCK" send-keys 'echo __E2E_READY__$((6 * 7))' Enter
wait_for '__E2E_READY__42'
echo "== shell is live (echo rendered in pane) =="

# 2) .zshrc actually took effect in a real tty (not just under `script`): an
#    alias it defines resolves interactively. The command line is `type vi`, so
#    only the result line "vi is an alias for nvim" matches vi.*nvim.
tmux -L "$SOCK" send-keys 'type vi' Enter
wait_for 'vi.*nvim'
echo "== alias resolves interactively (vi -> nvim) =="

# 3) The zsh line editor (zle) responds to a real key press. After running a
#    marked command, C-l (clear-screen, a zle widget that adds no history entry)
#    wipes the pane; pressing Up must then redraw that command into the edit
#    buffer. Clearing first makes the assertion unambiguous: the marker can only
#    reappear via history recall, not from leftover scrollback.
tmux -L "$SOCK" send-keys 'echo __E2E_HIST_MARK__' Enter
wait_for '__E2E_HIST_MARK__'
tmux -L "$SOCK" send-keys C-l
wait_absent '__E2E_HIST_MARK__'
tmux -L "$SOCK" send-keys Up
wait_for 'echo __E2E_HIST_MARK__'
tmux -L "$SOCK" send-keys C-c
echo "== zle Up-arrow recalled previous command =="

echo "PASS"
