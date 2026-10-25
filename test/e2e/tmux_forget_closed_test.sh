#!/bin/bash
# Closing every tmux session by hand must not come back on the next start,
# while a crash or reboot still does. Drives the real .tmux.conf, with the
# session-closed hook and tmux-resurrect/continuum loaded by tpm, and reads
# resurrect's "last" save to see which way each case went.
#
# The hook only forgets on a socket named default, so the servers here run on
# one under a private TMUX_TMPDIR, never the developer's own, and resurrect
# saves into a scratch @resurrect-dir.
set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/tmux_e2e_helpers.sh"

need tmux
CONF="$(tmux_conf_path)"
[ -f "${TMUX_PLUGIN_MANAGER_PATH:-$HOME/.tmux/plugins/}tmux-resurrect/scripts/helpers.sh" ] ||
  die "tmux-resurrect not installed (run bin/install_tmux_plugins.sh)"

WORK="$(mktemp -d)"
export TMUX_TMPDIR="$WORK/sock"
mkdir -p "$TMUX_TMPDIR"
SAVES="$WORK/resurrect"
SOCK=default
OTHER="other_$$"
cleanup() {
  tmux -L "$SOCK" kill-server 2>/dev/null || true
  tmux -L "$OTHER" kill-server 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# seed_save: a non-empty last save, standing in for continuum's 15-minute one.
seed_save() {
  rm -rf "$SAVES"
  mkdir -p "$SAVES"
  printf 'pane\tseeded\t0\t1\t:*\t0\tx\t:%s\t1\tsh\t:\n' "$WORK" >"$SAVES/tmux_resurrect_seed.txt"
  ln -s tmux_resurrect_seed.txt "$SAVES/last"
}

# start <socket> <restore-max-delay>: a server with sessions a and b on the real
# config. A max delay of -1 stops continuum from restoring the seeded save
# into it; the default (10s) lets it, as a fresh start from ghostty would.
start() {
  tmux -L "$1" new-session -d -s a sh
  tmux -L "$1" set -g @resurrect-dir "$SAVES"
  if [ "$2" = no-restore ]; then
    tmux -L "$1" set -g @continuum-restore-max-delay -1
  fi
  tmux -L "$1" source-file "$CONF" 2>/dev/null || die "$CONF failed to load"
  if [ "$2" = no-restore ]; then
    disable_continuum_restore "$1"
  fi
  tmux -L "$1" new-session -d -s b sh
  SERVER_PID="$(tmux -L "$1" display-message -p '#{pid}')"
}

# wait_server_gone <socket>: until the process start() recorded is gone, not
# only until it stops answering. A server ending in the hook still holds its
# socket while the hook's job runs, and a client that reaches it then gets
# "server exited unexpectedly".
wait_server_gone() {
  local i=0
  while kill -0 "$SERVER_PID" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge 50 ]; then
      echo "---- server $1 at timeout ----" >&2
      tmux -L "$1" list-panes -a -F '#{session_name} #{pane_pid} #{pane_dead}' >&2 2>&1 || true
      tmux -L "$1" show-messages >&2 2>&1 || true
      ps -o pid,ppid,stat,args -g "$(ps -o sid= -p "$SERVER_PID" | tr -d ' ')" >&2 2>&1 || true
      ls -l "$SAVES" >&2 2>&1 || true
      die "server $1 still running"
    fi
    sleep 0.1
  done
}

# end_shell <socket> <session>: the shell in <session> exits, as typing exit
# would (an interactive sh ignores TERM, so HUP). Not send-keys: the loaded
# config can leave a pane in copy mode, where the keys become copy-mode
# commands.
end_shell() {
  kill -HUP "$(tmux -L "$1" display-message -p -t "$2:" '#{pane_pid}')"
}

last_size() { wc -c <"$SAVES/last" | tr -d ' '; }

echo "== $(tmux -V) =="

echo "== exiting one shell keeps the save =="
seed_save
start "$SOCK" no-restore
end_shell "$SOCK" b
sleep 1
tmux -L "$SOCK" has-session -t a 2>/dev/null || die "the server went with the first session"
[ "$(readlink "$SAVES/last")" = tmux_resurrect_seed.txt ] || die "closing one of two sessions emptied the save"

echo "== exiting every shell empties the save and ends the server =="
end_shell "$SOCK" a
wait_server_gone "$SOCK"
[ "$(readlink "$SAVES/last")" != tmux_resurrect_seed.txt ] || die "last still points at the old save"
[ "$(last_size)" = 0 ] || die "last save is not empty"

echo "== the next start restores nothing =="
start "$SOCK" restore
sleep 3   # continuum restores 1s after load, in the background
n="$(tmux -L "$SOCK" list-sessions | wc -l | tr -d ' ')"
[ "$n" = 2 ] || { tmux -L "$SOCK" list-sessions; die "expected only a and b, got $n sessions"; }
tmux -L "$SOCK" kill-server
wait_server_gone "$SOCK"

echo "== a crash or reboot (SIGTERM) keeps the save =="
seed_save
start "$SOCK" no-restore
kill -TERM "$SERVER_PID"
wait_server_gone "$SOCK"
[ "$(readlink "$SAVES/last")" = tmux_resurrect_seed.txt ] || die "SIGTERM emptied the save"

echo "== and the next start restores it =="
# Also what keeps the "restores nothing" check above honest: continuum skips
# its restore when it sees another tmux process, which would pass that check
# without testing anything.
start "$SOCK" restore
sleep 3
tmux -L "$SOCK" has-session -t seeded 2>/dev/null || die "the saved session did not come back"
tmux -L "$SOCK" kill-server
wait_server_gone "$SOCK"

echo "== a server on another socket keeps the save, and still exits =="
seed_save
start "$OTHER" no-restore
end_shell "$OTHER" b
sleep 0.5
end_shell "$OTHER" a
wait_server_gone "$OTHER"
[ "$(readlink "$SAVES/last")" = tmux_resurrect_seed.txt ] || die "a -L server emptied the save"

echo "== ok =="
