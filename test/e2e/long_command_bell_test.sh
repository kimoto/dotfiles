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
need python3
ZSH_BIN="$(command -v zsh)"
REPO="$PWD"
[ -f "$REPO/.zshrc" ] || die "no .zshrc in $REPO"
echo "== $(tmux -V), $("$ZSH_BIN" --version) =="

SOCK="ci_long_command_bell_$$"
WORK="$(mktemp -d)"
CLIENT_PID=
cleanup() {
  exec 4>&- 2>/dev/null || true
  [ -n "$CLIENT_PID" ] && kill "$CLIENT_PID" 2>/dev/null || true
  tmux -L "$SOCK" kill-server 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

t() { tmux -L "$SOCK" "$@"; }

# The marker comes from a precmd hook added after .zshrc's own, so it prints
# only once the bell has been decided — and written ahead of it, if it rang.
# Each command names its own marker: precmd runs more than once per prompt.
MARK=0
run_in() {
  MARK=$((MARK + 1))
  t send-keys -t "$1" "_e2e_tag=$MARK; $2" Enter
  wait_for_pane "$SOCK" "^MARK_$MARK\$" 150 "$1"
}

# alert-bell runs from a deferred callback, so give a ring a moment to land.
rang() {
  local i=0
  while [ "$i" -lt 10 ]; do
    [ "$(t show -gqv @rang)" = 1 ] && return 0
    i=$((i + 1)); sleep 0.1
  done
  return 1
}
reset_bell() { t set -g @rang 0; }

# focus in|out: the report Ghostty sends, then wait for tmux to take it.
focus() {
  echo "$1" >&4
  local want=1 i=0
  [ "$1" = in ] || want=0
  until [ "$(t list-clients -F '#{m:*focused*,#{client_flags}}')" = "$want" ]; do
    i=$((i + 1)); [ "$i" -lt 50 ] || die "client never took focus $1"; sleep 0.1
  done
}

# The repo .tmux.conf, since focus-events there is what makes focus visible.
# Panes and windows by id: the config numbers windows from 1, and .zshrc
# renames them after $PWD.
t -f "$(tmux_conf_path)" new-session -d -s s -x 120 -y 30 \
  "$(zsh_pane_cmd LONG_COMMAND_BELL_SECONDS=1)" || die "failed to start tmux session"
disable_continuum_restore "$SOCK"
t set-hook -g alert-bell 'set -g @rang 1'
PANE="$(t display -p -t s '#{pane_id}')"
SHELL_WIN="$(t display -p -t s '#{window_id}')"
OTHER_WIN="$(t new-window -d -P -F '#{window_id}' 'sleep 600')"
reset_bell
# shellcheck disable=SC2016 # expanded by the zsh in the pane, not here
t send-keys -t "$PANE" '_e2e_mark() { print "MARK_$_e2e_tag" }; precmd_functions+=(_e2e_mark)' Enter
run_in "$PANE" 'true'

# 1) Detached session, long command: nobody is watching, so it rings.
reset_bell
run_in "$PANE" 'sleep 2'
rang || die "a 2s command in an unwatched pane did not ring"
echo "== long command in an unwatched pane rings =="

# 2) Same pane, short command: under the threshold, so it stays quiet.
reset_bell
run_in "$PANE" 'true'
rang && die "a command under the threshold rang"
echo "== short command stays quiet =="

# 3) A focused client showing the pane: the long command stays quiet.
mkfifo "$WORK/focus"
python3 "$DIR/tmux_pty_client.py" "$SOCK" s 120 30 <"$WORK/focus" &
CLIENT_PID=$!
exec 4>"$WORK/focus"
i=0
until [ "$(t display -p -t s '#{session_attached}')" -ge 1 ]; do
  i=$((i + 1)); [ "$i" -lt 100 ] || die "client never attached"; sleep 0.1
done
t select-window -t "$SHELL_WIN"
focus in
reset_bell
run_in "$PANE" 'sleep 2'
rang && die "a long command in the focused, shown pane rang"
echo "== long command in the watched pane stays quiet =="

# 4) Same client, terminal in the background: shown but not looked at, rings.
focus out
reset_bell
run_in "$PANE" 'sleep 2'
rang || die "a long command behind an unfocused terminal did not ring"
echo "== long command behind an unfocused terminal rings =="

# 5) Focused again, but on another window: the pane is not shown, rings.
focus in
t select-window -t "$OTHER_WIN"
reset_bell
run_in "$PANE" 'sleep 2'
rang || die "a long command in a window the client is not showing did not ring"
echo "== long command in a window not shown rings =="

echo "PASS"
