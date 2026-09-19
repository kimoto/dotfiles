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
