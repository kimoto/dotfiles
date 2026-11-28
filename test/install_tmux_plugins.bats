#!/usr/bin/env bats

# Guards bin/install_tmux_plugins.sh against the inherited-$TMUX trap.
#
# The script spins up a throwaway tmux server on its own `-L` socket and hands
# off to tpm's installer — but tpm's scripts call bare `tmux`, and a bare tmux
# client follows $TMUX whenever it is set. bin/mkworld.sh is normally run from
# inside a tmux session, so $TMUX is inherited and pointed at a completely
# different server: the throwaway one has the config sourced and
# @tpm_plugins set, the inherited one does not. tpm then fails with
# "FATAL: Tmux Plugin Manager not configured in tmux.conf" (and, when the two
# servers are different builds, "server version is too old for client"), which
# under mkworld's `set -e` aborted the rest of the bootstrap — no Claude tmux
# hooks, no lefthook install.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  # shellcheck source=test/tmux_private_tmpdir.sh
  . "$REPO_ROOT/test/tmux_private_tmpdir.sh"
  private_tmux_tmpdir
  cd "$REPO_ROOT"
}

@test "hands tpm the throwaway server, not whatever \$TMUX it inherited" {
  # Static half of the guard: portable, and the one that actually pins the fix.
  # tpm resolves its server the same way any bare tmux client does, so the only
  # thing standing between the installer and the inherited session is this
  # export.
  grep -q '^export TMUX$' bin/install_tmux_plugins.sh
  grep -qF 'TMUX="$(tmux -L "$SOCK" display-message -p' bin/install_tmux_plugins.sh
}

@test "installs plugins when the inherited session runs an older tmux build" {
  command -v tmux >/dev/null 2>&1 || skip "tmux not installed"
  command -v git >/dev/null 2>&1 || skip "git not installed"

  # Reproducing this needs a genuinely older server, not just a different one:
  # tpm reads the plugin list from ~/.tmux.conf on disk, so a same-version
  # stranger server goes unnoticed. It is the version handshake that fails
  # ("server version is too old for client"), which is the real-world shape —
  # a distro /usr/bin/tmux still serving the session while Homebrew supplies
  # the client on PATH.
  client="$(command -v tmux)"
  old=""
  for cand in /usr/bin/tmux /bin/tmux /usr/local/bin/tmux /opt/homebrew/bin/tmux; do
    [ -x "$cand" ] || continue
    [ "$(readlink -f "$cand")" = "$(readlink -f "$client")" ] && continue
    [ "$("$cand" -V)" = "$("$client" -V)" ] && continue
    old="$cand"
    break
  done
  [ -n "$old" ] || skip "no second, older tmux build on this machine"

  HOST_SOCK="host_$$"
  "$old" -L "$HOST_SOCK" -f /dev/null new-session -d -x 200 -y 50
  # Built by hand: the old server cannot answer a display-message from the new
  # client, which is the whole point.
  export TMUX="$("$old" -L "$HOST_SOCK" display-message -p '#{socket_path}'),1,0"

  run ./bin/install_tmux_plugins.sh
  "$old" -L "$HOST_SOCK" kill-server 2>/dev/null || true

  [ "$status" -eq 0 ]
  [[ "$output" != *"Tmux Plugin Manager not configured"* ]]
  [[ "$output" != *"server version is too old"* ]]
}

@test "stops when a plugin cannot be checked out at its pinned commit" {
  command -v tmux >/dev/null 2>&1 || skip "tmux not installed"
  # tpm is already cloned, but from a remote that does not have the commit
  # tmux-plugins.lock pins: the script must stop rather than run tpm unpinned.
  git init -q --bare "$BATS_TEST_TMPDIR/empty.git"
  git init -q "$BATS_TEST_TMPDIR/home/.tmux/plugins/tpm"
  git -C "$BATS_TEST_TMPDIR/home/.tmux/plugins/tpm" remote add origin "$BATS_TEST_TMPDIR/empty.git"

  run env HOME="$BATS_TEST_TMPDIR/home" ./bin/install_tmux_plugins.sh

  [ "$status" -ne 0 ]
  [[ "$output" == *"CI error: cannot fetch tmux-plugins/tpm at "* ]]
}

# A throwaway home holding the plugins. Copies this machine's installed
# plugins when there are any, so the usual run clones nothing.
plugin_home() {
  command -v tmux >/dev/null 2>&1 || skip "tmux not installed"
  command -v git >/dev/null 2>&1 || skip "git not installed"
  home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.tmux"
  ln -s "$REPO_ROOT/.tmux.conf" "$home/.tmux.conf"
  ln -s "$REPO_ROOT/bin" "$home/bin"
  if [ -d "$HOME/.tmux/plugins/tpm" ]; then
    cp -R "$HOME/.tmux/plugins" "$home/.tmux/plugins"
  else
    install_in_plugin_home || skip "no installed plugins to copy, and cloning them failed"
  fi
}

install_in_plugin_home() {
  env -u TMUX HOME="$home" "$@" ./bin/install_tmux_plugins.sh
}

teardown() {
  # The older build's server takes a kill only from its own client: left to
  # the sweep, a test that failed before its own kill would read as "will
  # not die" and hide what failed.
  if [ -n "${old:-}" ] && [ -n "${HOST_SOCK:-}" ]; then
    "$old" -L "$HOST_SOCK" kill-server 2>/dev/null || true
  fi
  sweep_private_tmux_tmpdir
}

@test "pins every plugin even when the throwaway server is gone after tpm ran" {
  plugin_home
  # One plugin drifts off its pin, and tpm's installer takes the server down.
  drifted="$home/.tmux/plugins/extrakto"
  git -C "$drifted" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m drift
  printf '#!/bin/sh\ntmux kill-server\n' >"$home/.tmux/plugins/tpm/bin/install_plugins"

  run install_in_plugin_home

  [ "$status" -eq 0 ]
  pinned=$(awk '$1 == "laktak/extrakto" { print $3 }' tmux-plugins.lock)
  [ -n "$pinned" ]
  [ "$(git -C "$drifted" rev-parse HEAD)" = "$pinned" ]
}

@test "stops when the config names no plugins, rather than pinning none" {
  plugin_home
  # The server reads ~/.tmux.conf by itself at start, so that one goes too.
  rm "$home/.tmux.conf"
  : >"$BATS_TEST_TMPDIR/empty.conf"

  run install_in_plugin_home TMUX_CONF="$BATS_TEST_TMPDIR/empty.conf"

  [ "$status" -ne 0 ]
  [[ "$output" == *"CI error: @tpm_plugins is empty"* ]]
}
