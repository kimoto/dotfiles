#!/bin/bash
# e2e for the long-command bell in .zshrc. The bell is read from tmux's
# alert-bell hook, not window_bell_flag: tmux never flags the window a client
# is looking at, so the flag cannot tell a quiet watched pane from a ringing one.
set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/tmux_e2e_helpers.sh"

need tmux
need zsh
need script
ZSH_BIN="$(command -v zsh)"
REPO="$PWD"
[ -f "$REPO/.zshrc" ] || die "no .zshrc in $REPO"
echo "== $(tmux -V), $("$ZSH_BIN" --version) =="

SOCK="ci_long_command_bell_$$"
CLIENT_PID=
cleanup() {
  [ -n "$CLIENT_PID" ] && kill "$CLIENT_PID" 2>/dev/null || true
  tmux -L "$SOCK" kill-server 2>/dev/null || true
}
trap cleanup EXIT

t() { tmux -L "$SOCK" "$@"; }

# wait_for_pane reads only the active pane; this takes a target.
wait_in() {
  local i=0
  while [ "$i" -lt 150 ]; do
    t capture-pane -p -t "$1" 2>/dev/null | grep -qE "$2" && return 0
    i=$((i + 1)); sleep 0.1
  done
  t capture-pane -p -t "$1" >&2 || true
  die "timed out waiting in $1 for: $2"
}

# The marker shows once the command and its precmd are done.
run_in() {
  t send-keys -t "$1" "$2; echo $3" Enter
  wait_in "$1" "^$3"
}

rang() { [ "$(t show -gqv @rang)" = 1 ]; }
reset_bell() { t set -g @rang 0; }

# Windows by index: .zshrc renames them after $PWD.
t -f /dev/null new-session -d -s s -x 120 -y 30 \
  "$(zsh_pane_cmd LONG_COMMAND_BELL_SECONDS=1)" || die "failed to start tmux session"
t set-hook -g alert-bell 'set -g @rang 1'
t new-window -d -n other 'sleep 600'
t set -g @rang 0
run_in s:0 'true' READY_1

# 1) Detached session, long command: nobody is watching, so it rings.
reset_bell
run_in s:0 'sleep 2' DONE_LONG
rang || die "a 2s command in an unwatched pane did not ring"
echo "== long command in an unwatched pane rings =="

# 2) Same pane, short command: under the threshold, so it stays quiet.
reset_bell
run_in s:0 'true' DONE_SHORT
rang && die "a command under the threshold rang"
echo "== short command stays quiet =="

# 3) An attached client looking at the pane: the long command stays quiet.
t select-window -t s:0
script -qfc "env TERM=xterm-256color tmux -L $SOCK attach -t s" /dev/null >/dev/null 2>&1 </dev/null &
CLIENT_PID=$!
i=0
until [ "$(t display -p -t s '#{session_attached}')" -ge 1 ]; do
  i=$((i + 1)); [ "$i" -lt 100 ] || die "client never attached"; sleep 0.1
done
reset_bell
run_in s:0 'sleep 2' DONE_WATCHED
rang && die "a long command in the watched pane rang"
echo "== long command in the watched pane stays quiet =="

echo "PASS"
