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

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/tmux_e2e_helpers.sh"

need tmux
need zsh
ZSH_BIN="$(command -v zsh)"
REPO="$PWD"
[ -f "$REPO/.zshrc" ] || die "no .zshrc in $REPO"
echo "== $(tmux -V), $("$ZSH_BIN" --version) =="

SOCK="ci_tmux_e2e_$$"
cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null || true; }
trap cleanup EXIT

# Launch an *interactive* zsh inside a real (tmux) terminal. ZDOTDIR points at
# the repo (same convention as the loading test); CI is cleared so .zshrc does
# not enable err_exit and abort on the first non-zero command; the sync-check
# and the brew bundle check are silenced (like ci_zsh_loading_test.sh does) so
# startup neither touches the network nor burns seconds of the pane's render
# budget on `brew bundle check`.
tmux -L "$SOCK" new-session -d -x 200 -y 50 \
  "env CI= ZDOTDIR='$REPO' DOTFILES_NO_SYNC_CHECK=1 DOTFILES_NO_BREW_CHECK=1 \
TERM=xterm-256color '$ZSH_BIN' -i" ||
  die "failed to start tmux session"

# 1) The interactive shell is live and rendering. Typing a command and seeing
#    its *computed* output ($((6 * 7)) -> 42) on screen proves the full
#    keystroke -> eval -> render path through a genuine terminal.
# shellcheck disable=SC2016  # single-quoted on purpose: zsh in the pane must
# evaluate $((6 * 7)), not this shell.
tmux -L "$SOCK" send-keys 'echo __E2E_READY__$((6 * 7))' Enter
wait_for_pane "$SOCK" '__E2E_READY__42'
echo "== shell is live (echo rendered in pane) =="

# 2) .zshrc actually took effect in a real tty (not just under `script`): an
#    alias it defines resolves interactively. The command line is `type vi`, so
#    only the result line "vi is an alias for nvim" matches vi.*nvim.
tmux -L "$SOCK" send-keys 'type vi' Enter
wait_for_pane "$SOCK" 'vi.*nvim'
echo "== alias resolves interactively (vi -> nvim) =="

# 3) The zsh line editor (zle) responds to a real key press. After running a
#    marked command, C-l (clear-screen, a zle widget that adds no history entry)
#    wipes the pane; pressing Up must then redraw that command into the edit
#    buffer. Clearing first makes the assertion unambiguous: the marker can only
#    reappear via history recall, not from leftover scrollback.
tmux -L "$SOCK" send-keys 'echo __E2E_HIST_MARK__' Enter
wait_for_pane "$SOCK" '__E2E_HIST_MARK__'
tmux -L "$SOCK" send-keys C-l
wait_absent_pane "$SOCK" '__E2E_HIST_MARK__'
tmux -L "$SOCK" send-keys Up
wait_for_pane "$SOCK" 'echo __E2E_HIST_MARK__'
tmux -L "$SOCK" send-keys C-c
echo "== zle Up-arrow recalled previous command =="

echo "PASS"
