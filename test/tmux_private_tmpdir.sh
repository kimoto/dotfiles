#!/bin/bash
# A TMUX_TMPDIR of the test's own, and a sweep that leaves no server behind in
# it (#652). Every test that starts a tmux server uses it: a server started
# with the real config and killed within a second can come back, because
# tmux-menus' background init still runs a bare `tmux list-keys`, which starts
# a fresh server on the dead one's socket, and `exit-empty off` keeps it alive.
# One such leftover is enough for tmux-continuum to skip the next restore.
# This file is *sourced*, not executed, and needs nothing else:
#
#   # shellcheck source=test/tmux_private_tmpdir.sh
#   . "<repo>/test/tmux_private_tmpdir.sh"
#   private_tmux_tmpdir          # before the first server starts
#   ...
#   sweep_private_tmux_tmpdir    # last thing the cleanup does

# private_tmux_tmpdir: export a fresh, empty TMUX_TMPDIR for every tmux the
# test runs, children included. Under /tmp, not $TMPDIR: macOS caps a socket
# path at 104 bytes, and its $TMPDIR (/var/folders/...) already takes half.
# Without a tmux there is no server to keep apart, and a test that will skip
# leaves no directory behind; the sweep then has nothing to do.
private_tmux_tmpdir() {
  _TMUX_PRIVATE_DIR=""
  command -v tmux >/dev/null 2>&1 || return 0
  _tmux_prune_fences
  _TMUX_PRIVATE_DIR="$(mktemp -d /tmp/tmx.XXXXXX)" || {
    echo "CI error: cannot create a private TMUX_TMPDIR" >&2
    return 1
  }
  export TMUX_TMPDIR="$_TMUX_PRIVATE_DIR"
}

# _tmux_prune_fences: remove what finished sweeps left behind (a directory
# holding only its fence file) once it is a day old, when no straggler that
# might still need blocking is left. A failed sweep's directory stays.
_tmux_prune_fences() {
  local d uid
  uid="$(id -u)"
  # /tmp/ with the slash: on macOS /tmp is a link, which find would not enter.
  while IFS= read -r d; do
    [ "$(ls -A "$d")" = "tmux-$uid" ] && [ -f "$d/tmux-$uid" ] && rm -rf "$d"
  done < <(find /tmp/ -maxdepth 1 -name 'tmx.*' -type d -user "$uid" -mtime +0 2>/dev/null)
  return 0
}

# _tmux_clients: the tmux binaries to kill a server with, one per line. The
# one that started it may be off PATH (a test's env -i, TMUX_BIN, Homebrew's
# where the caller has the OS one), and only a client of its own version can
# kill it, so every tmux at hand is a candidate. _TMUX_SWEEP_CLIENTS replaces
# the list, for a test of a server none of them can kill.
_tmux_clients() {
  if [ -n "${_TMUX_SWEEP_CLIENTS:-}" ]; then
    printf '%s\n' "$_TMUX_SWEEP_CLIENTS"
    return
  fi
  local c seen=" "
  for c in "${TMUX_BIN:-}" "$(command -v tmux 2>/dev/null)" /opt/homebrew/bin/tmux \
    /home/linuxbrew/.linuxbrew/bin/tmux /usr/local/bin/tmux /usr/bin/tmux; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    case "$seen" in *" $c "*) continue ;; esac
    seen="$seen$c "
    printf '%s\n' "$c"
  done
}

# _tmux_kill_socket <socket>: 0 when a server was there and was told to go,
# 1 when nothing listens, 2 when a server answers every client and dies for
# none. A failure is read by what it says: "no server running" and "error
# connecting" mean nothing listens; anything else came from a server that
# answered and refused, as one of another tmux version does.
_tmux_kill_socket() {
  local c said refused="no tmux to ask"
  while IFS= read -r c; do
    said="$("$c" -S "$1" kill-server 2>&1)" && return 0
    case "$said" in
      "no server running"* | "error connecting to"*) return 1 ;;
      # A server already on its way out.
      *"exited unexpectedly"*) return 0 ;;
      *) refused="$said" ;;
    esac
  done < <(_tmux_clients)
  echo "CI error: the tmux server on $1 answers but will not die: $refused" >&2
  return 2
}

# sweep_private_tmux_tmpdir: kill every server under the private TMUX_TMPDIR,
# then empty it. Uses the directory it created, not $TMUX_TMPDIR, which a
# test may have pointed elsewhere since.
#
# It first fences the socket directory off: tmux-<uid> is moved aside and a
# regular file takes its name. A late `tmux list-keys` reaches its server by
# the socket path in $TMUX, and through a file it can neither connect nor
# start one ("Not a directory"); `tmux -L` fails the same way ("is not a
# directory"). A server that bound its socket before the move has it in the
# moved directory, where the kill finds it. Only then is a quiet pass proof
# that nothing is left: unfenced, one "no server running" says nothing about
# a server the init starts a moment later.
#
# The fence outlives the sweep. A pane or a run-shell -b job can outlive its
# server, and with TMUX_TMPDIR gone its `tmux -L` would fall back to
# /tmp/tmux-<uid> and start the leak there; private_tmux_tmpdir clears
# fences a day later.
#
# A server that answers but dies for no client stops the sweep, which keeps
# what it moved aside and fails: removing that socket would leave the server
# running where nothing can reach it. Called again in the same shell, as a
# bats teardown does after a test's own sweep failed, it carries on.
#
# Bounded: 50 passes 0.1s apart at most. A server that still answers after
# that is reported the same way.
sweep_private_tmux_tmpdir() {
  local dir="${_TMUX_PRIVATE_DIR:-}" fence sock rc live quiet=0 pass=0 tries=0 n=0
  [ -n "$dir" ] && [ -d "$dir" ] || return 0
  fence="$dir/tmux-$(id -u)"
  # A client that falls in between the move and the file makes the directory
  # again; that one is moved aside as well, each to a name not yet taken.
  until [ -f "$fence" ]; do
    if [ "$tries" -ge 10 ]; then
      echo "CI error: cannot fence $fence off" >&2
      return 1
    fi
    if [ -e "$fence" ]; then
      while [ -e "$dir/swept.$n" ]; do n=$((n + 1)); done
      mv "$fence" "$dir/swept.$n" || return 1
    fi
    : >"$fence" 2>/dev/null || true
    tries=$((tries + 1))
  done
  # Two quiet passes 0.1s apart: a server between bind() and listen() refuses
  # the first one. find, not a glob: a socket at any depth, dot names too.
  while [ "$quiet" -lt 2 ]; do
    if [ "$pass" -ge 50 ]; then
      echo "CI error: a tmux server under $dir still answers kill-server" >&2
      return 1
    fi
    live=0
    while IFS= read -r sock; do
      # Its status as data: under errexit a bare non-zero would end the sweep.
      _tmux_kill_socket "$sock" && rc=0 || rc=$?
      case "$rc" in
        0) live=1 ;;
        2) return 1 ;;
      esac
    done < <(find "$dir" -type s 2>/dev/null)
    if [ "$live" -eq 1 ]; then quiet=0; else quiet=$((quiet + 1)); fi
    pass=$((pass + 1))
    [ "$quiet" -ge 2 ] || sleep 0.1
  done
  find "$dir" -mindepth 1 ! -path "$fence" -exec rm -rf {} + 2>/dev/null || true
  _TMUX_PRIVATE_DIR=""
}
