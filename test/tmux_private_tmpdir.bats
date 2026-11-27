#!/usr/bin/env bats

# The private TMUX_TMPDIR and its sweep (test/tmux_private_tmpdir.sh): no tmux
# server a test started, or that came back after the test killed it, outlives
# the sweep (#652).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=test/tmux_private_tmpdir.sh
  . "$REPO_ROOT/test/tmux_private_tmpdir.sh"
  command -v tmux >/dev/null 2>&1 || skip "tmux not installed"
  # A server that starts with no -f reads ~/.tmux.conf. This one stays up with
  # no session, as the real config's does, and writes down its pid.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  cat >"$HOME/.tmux.conf" <<'EOF'
set -g exit-empty off
run-shell 'echo #{pid} >>"$HOME/pids"'
EOF
  unset TMUX
  private_tmux_tmpdir
  DIR="$_TMUX_PRIVATE_DIR"
}

teardown() {
  # The stop file first, so test 4's job is done reviving before the sweep;
  # the sweep, not a hand-rolled kill, so a red run leaks nothing either.
  : >"$BATS_TEST_TMPDIR/stop"
  sweep_private_tmux_tmpdir
  # A red probe test started its server in the shared /tmp/tmux-<uid>.
  if [ -n "${PROBE:-}" ]; then
    env -u TMUX_TMPDIR tmux -L "$PROBE" kill-server 2>/dev/null || true
    rm -f "/tmp/tmux-$(id -u)/$PROBE"
  fi
  [ -z "${OLD_KEPT:-}" ] || rm -rf "$OLD_KEPT"
}

# fence_only: the sweep left nothing in the directory but the file that
# keeps a straggler's tmux from starting a server anywhere.
fence_only() {
  [ -f "$DIR/tmux-$(id -u)" ] && [ "$(ls -A "$DIR")" = "tmux-$(id -u)" ]
}

# refusing_tmux: a tmux that reaches a server and is refused, as a client of
# another version is.
refusing_tmux() {
  mkdir -p "$BATS_TEST_TMPDIR/shim"
  printf '#!/bin/sh\necho "protocol version mismatch (client 8, server 7)" >&2\nexit 1\n' \
    >"$BATS_TEST_TMPDIR/shim/tmux"
  chmod +x "$BATS_TEST_TMPDIR/shim/tmux"
  echo "$BATS_TEST_TMPDIR/shim/tmux"
}

# no_live_pid: every server that ever wrote to ~/pids is gone, within 2s of
# being told to go. A zombie counts as gone: it holds no socket, and in a
# container whose pid 1 reaps nothing it stays in the process table for good.
pid_running() {
  case "$(ps -o stat= -p "$1" 2>/dev/null)" in
    '' | Z*) return 1 ;;
  esac
}
no_live_pid() {
  local pid i
  while read -r pid; do
    i=0
    while pid_running "$pid"; do
      i=$((i + 1))
      if [ "$i" -ge 20 ]; then
        echo "tmux server $pid is still running" >&2
        return 1
      fi
      sleep 0.1
    done
  done <"$HOME/pids"
}

@test "the private TMUX_TMPDIR is short, and new for each call" {
  [ "$TMUX_TMPDIR" = "$DIR" ]
  [ -d "$DIR" ]
  # macOS: sun_path is 104 bytes, and tmux adds /tmux-<uid>/<label>.
  [ "${#DIR}" -le 20 ]
  local second
  private_tmux_tmpdir
  second="$_TMUX_PRIVATE_DIR"
  _TMUX_PRIVATE_DIR="$DIR"
  rm -rf "$second"
  [ "$second" != "$DIR" ]
}

@test "the sweep kills a server still running, and leaves only the fence" {
  tmux -L live new-session -d
  tmux -L .dotted new-session -d   # a name a shell glob would skip
  [ -s "$HOME/pids" ]
  sweep_private_tmux_tmpdir
  fence_only
  no_live_pid
}

@test "the sweep finds the directory even after a test points TMUX_TMPDIR elsewhere" {
  tmux -L moved new-session -d
  export TMUX_TMPDIR="$BATS_TEST_TMPDIR/elsewhere"
  sweep_private_tmux_tmpdir
  fence_only
  no_live_pid
}

@test "a server that keeps coming back on the killed socket does not outlive the sweep" {
  # What tmux-menus' init does when its server is killed under it, made
  # relentless: a job of the server's own keeps running a bare
  # `tmux list-keys`, which follows $TMUX to the socket and starts a new server
  # on it whenever none answers. Bounded at 200 tries (over 10s), longer than
  # the sweep's own bound, so only the rename lets the sweep finish; the stop
  # file ends it sooner.
  tmux -L back new-session -d
  tmux -L back run-shell -b "( i=0; while [ ! -f '$BATS_TEST_TMPDIR/stop' ] && [ \$i -lt 200 ]; do
    tmux list-keys >/dev/null 2>&1; i=\$((i + 1)); sleep 0.05; done ) >/dev/null 2>&1 & exit 0"
  tmux -L back kill-server
  # Let it come back at least once, so the sweep has a revived server to find.
  local i=0
  while [ "$(wc -l <"$HOME/pids")" -lt 2 ]; do
    i=$((i + 1))
    [ "$i" -lt 50 ] || { echo "the server never came back; the test proves nothing" >&2; return 1; }
    sleep 0.1
  done

  sweep_private_tmux_tmpdir

  # The job keeps trying for a while after the sweep: nothing it starts may stay.
  sleep 0.5
  : >"$BATS_TEST_TMPDIR/stop"
  fence_only
  no_live_pid
}

@test "a server that answers but will not die fails the sweep, which a second call finishes" {
  # Removing the socket of a server no client can kill would hide it for good.
  tmux -L stuck new-session -d
  _TMUX_SWEEP_CLIENTS="$(refusing_tmux)" run sweep_private_tmux_tmpdir
  [ "$status" -ne 0 ]
  [[ "$output" == *"answers but will not die"* ]]
  [ -n "$(find "$DIR" -type s)" ]

  sweep_private_tmux_tmpdir
  fence_only
  no_live_pid
}

@test "the sweep kills with a tmux that can, not only the one first on PATH" {
  # The server's own tmux may be off the caller's PATH (env -i, TMUX_BIN,
  # Homebrew's): PATH's answers as another version would.
  tmux -L elsewhere new-session -d
  PATH="$(dirname "$(refusing_tmux)"):$PATH" sweep_private_tmux_tmpdir
  fence_only
  no_live_pid
}

@test "a second sweep finds a server that made the socket directory again" {
  # The first sweep fails and fences; then the fence goes and a new server
  # makes tmux-<uid> again, where the first one's moved-aside copy is.
  tmux -L first new-session -d
  _TMUX_SWEEP_CLIENTS="$(refusing_tmux)" run sweep_private_tmux_tmpdir
  [ "$status" -ne 0 ]
  rm "$DIR/tmux-$(id -u)"
  tmux -L again new-session -d

  sweep_private_tmux_tmpdir
  fence_only
  no_live_pid
}

@test "after the sweep, a straggler's tmux -L start fails instead of moving to /tmp/tmux-<uid>" {
  # A pane or a run-shell -b job that outlived its server still has
  # TMUX_TMPDIR pointing here.
  PROBE="probe_$$_$RANDOM"
  tmux -L stuck new-session -d
  sweep_private_tmux_tmpdir

  run tmux -L "$PROBE" -f /dev/null new-session -d
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not a directory"* ]]
  [ ! -e "/tmp/tmux-$(id -u)/$PROBE" ]
}

@test "without a tmux on PATH, no private directory is made" {
  local before after
  before="$(find /tmp/ -maxdepth 1 -name 'tmx.*' | sort)"
  PATH="$BATS_TEST_TMPDIR/empty" private_tmux_tmpdir
  after="$(find /tmp/ -maxdepth 1 -name 'tmx.*' | sort)"
  [ -z "$_TMUX_PRIVATE_DIR" ]
  [ "$before" = "$after" ]
  _TMUX_PRIVATE_DIR="$DIR"
}

@test "a new private directory clears fences more than a day old, and nothing else" {
  local old_fence
  old_fence="$(mktemp -d /tmp/tmx.XXXXXX)"
  : >"$old_fence/tmux-$(id -u)"
  OLD_KEPT="$(mktemp -d /tmp/tmx.XXXXXX)"
  : >"$OLD_KEPT/tmux-$(id -u)"
  mkdir "$OLD_KEPT/swept.0"   # a failed sweep, kept for a look
  touch -t 202001010000 "$old_fence" "$OLD_KEPT"

  private_tmux_tmpdir
  local second="$_TMUX_PRIVATE_DIR"
  _TMUX_PRIVATE_DIR="$DIR"
  rm -rf "$second"
  [ ! -e "$old_fence" ]
  [ -d "$OLD_KEPT" ]
  [ -d "$DIR" ]
}

# server_start_lines <file>: the line numbers that start a tmux server, by
# new-session, its `new` abbreviation, or start-server, or by running a bin/
# script that does, itself or through the bin/ scripts it runs. A comment, a
# grep for the words, or a message naming the script starts nothing.
SERVER_START='new-session|start-server'
SERVER_START+='|(^|[^-_[:alnum:]])tmux([[:space:]]+[^[:space:]|;&]+)*[[:space:]]+new([[:space:]]|$)'
server_start_lines() {
  local script
  code_lines "$1" | grep -E "$SERVER_START" | grep -v grep | cut -d: -f1
  for script in $(bin_calls "$1"); do
    script_starts_server "$script" 4 || continue
    code_lines "$1" | grep -E "$(bin_call_re "${script#bin/}")" | cut -d: -f1
  done
}

# bin_calls <file>: the bin/ scripts it runs, named by a path (".../bin/x.sh",
# "./bin/x.sh") or handed to bash or sh, not a bare word in a message or an ls.
bin_calls() {
  code_lines "$1" | grep -oE "$(bin_call_re '[[:alnum:]_]+\.sh')" | grep -oE 'bin/[[:alnum:]_]+\.sh' | sort -u
}

# bin_call_re <name pattern>: bin/<name> run by path, or by `bash`/`sh`.
bin_call_re() {
  # The ":" for the line number code_lines puts in front.
  printf '%s' "(/|(^|[[:space:]:;&|(])(bash|sh)[[:space:]]+)bin/$1"
}

# script_starts_server <bin/x.sh> <depth>: whether the script, or a bin/
# script it runs within <depth> hops, starts a server. Bounded, because the
# scripts call each other in cycles.
script_starts_server() {
  local f="$REPO_ROOT/$1" next
  [ -f "$f" ] && [ "$2" -gt 0 ] || return 1
  code_lines "$f" | grep -E "$SERVER_START" | grep -qv grep && return 0
  for next in $(bin_calls "$f"); do
    [ "$next" = "$1" ] && continue
    script_starts_server "$next" $(($2 - 1)) && return 0
  done
  return 1
}

# code_lines <file>: `N:line` for each line that is not a comment or a message,
# with any comment after the code cut off.
code_lines() {
  grep -nvE '^[[:space:]]*(#|(die|echo|skip) )' "$1" | sed -E 's/[[:space:]]+#.*$//'
}

@test "the server-start pattern sees every way a test starts a server" {
  local f="$BATS_TEST_TMPDIR/probe.sh"
  printf '%s\n' 'tmux -L s new -d' 'tmux new-session -d || die "no server"' \
    'run "$REPO_ROOT/bin/tmux_render_snapshot.sh"' \
    'grep -q new-session x' 'tmux -L s new-window -d' 'echo renew' '# tmux new pane' 'x=1  # tmux new pane' \
    'die "run bin/tmux_render_snapshot.sh first"' '"$REPO/bin/mkworld.sh"' 'ls -l bin/mkworld.sh' \
    'bash bin/install_tmux_plugins.sh' >"$f"
  run server_start_lines "$f"
  [ "$status" -eq 0 ]
  [ "$(sort -n <<<"$output" | tr '\n' ' ')" = "1 2 3 10 12 " ]
}

@test "every test that starts a tmux server runs it under the private TMUX_TMPDIR" {
  local f first setup bad=0
  for f in "$REPO_ROOT"/test/e2e/*_test.sh "$REPO_ROOT"/test/*.bats; do
    case "${f#"$REPO_ROOT"/}" in
      # Its own tests start servers on purpose and sweep in teardown.
      test/tmux_private_tmpdir.bats) continue ;;
      # speed_report.sh starts its servers with -S under its own measure home,
      # which TMUX_TMPDIR does not reach, and this file runs it with no tmux
      # on PATH.
      test/speed_report.bats) continue ;;
      # Runs mkworld.sh only as MKWORLD_CHECK=1, which exits before the tmux
      # plugin install.
      test/mkworld_check.bats) continue ;;
    esac
    first="$(server_start_lines "$f" | sort -n | head -n1)"
    [ -n "$first" ] || continue
    setup="$(code_lines "$f" | grep -E '(^|[^_[:alnum:]])private_tmux_tmpdir([^_[:alnum:]]|$)' |
      head -n1 | cut -d: -f1)"
    if [ -z "$setup" ] || ! grep -q 'sweep_private_tmux_tmpdir' "$f"; then
      echo "$f starts a tmux server without private_tmux_tmpdir and sweep_private_tmux_tmpdir" >&2
      bad=1
    elif [ "$setup" -gt "$first" ]; then
      echo "$f starts a tmux server on line $first, before private_tmux_tmpdir on line $setup" >&2
      bad=1
    fi
  done
  [ "$bad" -eq 0 ]
}
