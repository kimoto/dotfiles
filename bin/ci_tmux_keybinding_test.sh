#!/bin/bash
# Interactive end-to-end test for tmux's OWN key bindings (prefix tables) —
# the everyday operations send-keys-into-a-pane cannot reach.
#
# ci_tmux_interactive_test.sh drives the program *inside* a pane (zsh), so a sent
# `M-t` reaches that program, not tmux: send-keys bypasses tmux's key
# interpretation. To exercise bindings we nest tmux: an OUTER tmux (vanilla, so
# its own bindings never interfere) runs a pane whose program is an INNER tmux
# that loads the real .tmux.conf. Keys sent to the OUTER pane are delivered to
# the INNER client as terminal input, so the INNER server interprets them as
# bindings — exactly as a human's keystrokes would. Assertions then query the
# INNER server's state directly (list-windows / display-message), which is far
# more robust than scraping capture-pane.
set -euo pipefail

die() { echo "CI error: $*" >&2; exit 1; }

# Prefer a Homebrew tmux (newer) when the shellenv is available.
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

command -v tmux >/dev/null 2>&1 || die "tmux not installed"
echo "== $(tmux -V) =="

CONF="${TMUX_CONF:-$HOME/.tmux.conf}"
[ -f "$CONF" ] || CONF="$PWD/.tmux.conf"
[ -f "$CONF" ] || die "no .tmux.conf found"
echo "== driving bindings from: $CONF =="

OUTER="ci_tmux_kb_out_$$"
INNER="ci_tmux_kb_in_$$"
cleanup() {
  tmux -L "$INNER" kill-server 2>/dev/null || true
  tmux -L "$OUTER" kill-server 2>/dev/null || true
}
trap cleanup EXIT

# Send a key (or key sequence) to the OUTER pane -> reaches the INNER client.
keys() { tmux -L "$OUTER" send-keys "$@"; }
# Number of windows the INNER server currently has.
win_count() { tmux -L "$INNER" list-windows -F '#{window_index}' 2>/dev/null | grep -c .; }
# Active window index on the INNER server.
active_idx() { tmux -L "$INNER" display-message -p '#{window_index}' 2>/dev/null; }

# Poll until win_count equals $1, or time out.
wait_count() {
  local want="$1" tries="${2:-50}" i=0 got
  while [ "$i" -lt "$tries" ]; do
    got="$(win_count || echo 0)"
    [ "$got" = "$want" ] && return 0
    i=$((i + 1)); sleep 0.1
  done
  echo "---- INNER windows at timeout ----" >&2
  tmux -L "$INNER" list-windows >&2 2>/dev/null || true
  die "expected $want windows, saw ${got:-?}"
}

# Poll until the active window index equals $1, or time out.
wait_active() {
  local want="$1" tries="${2:-50}" i=0 got
  while [ "$i" -lt "$tries" ]; do
    got="$(active_idx || true)"
    [ "$got" = "$want" ] && return 0
    i=$((i + 1)); sleep 0.1
  done
  die "expected active window $want, saw ${got:-?}"
}

# OUTER is vanilla (-f /dev/null): its bindings must not shadow the keys we send.
# Its single pane runs the INNER tmux, which loads the config under test.
tmux -L "$OUTER" -f /dev/null new-session -d -x 200 -y 50 \
  "tmux -L '$INNER' -f '$CONF' new-session" ||
  die "failed to start nested tmux"

# Wait for the INNER server to come up (its first window to exist).
wait_count 1
echo "== nested tmux is live =="

# 1) base-index 1 + renumber-windows: the first window is index 1, not 0.
first_idx="$(tmux -L "$INNER" list-windows -F '#{window_index}' | head -n1)"
[ "$first_idx" = "1" ] || die "base-index expected 1, got $first_idx"
echo "== base-index: first window is 1 =="

# 2) Root-table binding `bind -n M-t new-window`: a bare Alt-t opens a window.
keys M-t
wait_count 2
keys M-t
wait_count 3
echo "== M-t opens new windows (3 total) =="

# 3) `bind -n M-2 select-window -t 2`: Alt-2 jumps straight to window 2.
keys M-1   # move away first so the M-2 jump is observable
wait_active 1
keys M-2
wait_active 2
echo "== M-2 selects window 2 =="

# 4) Custom prefix `C-t`: prefix then `c` (tmux's default new-window) works.
keys C-t c
wait_count 4
echo "== custom prefix C-t fires (C-t c -> new window) =="

# 5) `bind-key Right join-pane -t :+`: prefix Right pulls the current window's
#    pane into the next window. The source window then closes, so the window
#    count drops by one and a window ends up with two panes — a genuine
#    pane-management op (not just a window switch) driven entirely by a binding.
keys M-1
wait_active 1
keys C-t Right
wait_count 3
max_panes="$(tmux -L "$INNER" list-windows -F '#{window_panes}' | sort -rn | head -n1)"
[ "$max_panes" = "2" ] || die "join-pane expected a 2-pane window, max was ${max_panes:-?}"
echo "== prefix Right joins a pane (3 windows, one with 2 panes) =="

echo "PASS"
