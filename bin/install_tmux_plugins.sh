#!/bin/bash
# Headlessly install the tmux plugins declared in .tmux.conf (@tpm_plugins) using
# tpm's own installer, with no interactive `prefix + I`. CI runs this once so it
# can cache ~/.tmux/plugins and skip the clones on later runs; it is idempotent
# (tpm skips plugins that are already present), so re-running it is cheap.
set -euo pipefail

die() { echo "CI error: $*" >&2; exit 1; }

# Prefer a Homebrew tmux (newer) when the shellenv is available.
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

command -v tmux >/dev/null 2>&1 || die "tmux not installed"
command -v git >/dev/null 2>&1 || die "git not installed"

CONF="${TMUX_CONF:-$HOME/.tmux.conf}"
[ -f "$CONF" ] || CONF="$PWD/.tmux.conf"
[ -f "$CONF" ] || die "no .tmux.conf found"

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
LOCK="$BASE_DIR/tmux-plugins.lock"

# Check out a clone at the commit tmux-plugins.lock pins it to. tpm clones the
# branch head, which is whatever upstream pushed last; the pin is what makes a
# push reach this machine only through a reviewed bump. The checkout is
# detached, so tpm's own update (`prefix + U`) fails instead of moving past it.
pin() {
  local repo=$1 dir=$2 sha
  sha=$(awk -v r="$repo" '$1 == r { print $3 }' "$LOCK")
  [ -n "$sha" ] || die "$repo has no pinned commit in $LOCK"
  if ! git -C "$dir" cat-file -e "$sha^{commit}" 2>/dev/null; then
    git -C "$dir" fetch -q --depth 1 origin "$sha" || die "cannot fetch $repo at $sha"
  fi
  git -C "$dir" checkout -q --detach "$sha"
}

PLUGIN_DIR="$HOME/.tmux/plugins"
TPM="$PLUGIN_DIR/tpm"
if [ ! -d "$TPM" ]; then
  echo "== cloning tpm =="
  mkdir -p "$PLUGIN_DIR"
  git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM"
fi
# Before tpm runs, so the installer code below is the pinned one too.
pin tmux-plugins/tpm "$TPM"

# tpm's installer reads @tpm_plugins from a running server and clones into
# $TMUX_PLUGIN_MANAGER_PATH. Spin up a throwaway server, source the real config
# so the option is set, then let tpm do the clones.
export TMUX_PLUGIN_MANAGER_PATH="$PLUGIN_DIR/"
SOCK="tpm_install_$$"
cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null || true; }
trap cleanup EXIT

tmux -L "$SOCK" new-session -d -x 200 -y 50 || die "failed to start tmux server"
# Non-fatal: a missing-plugin `run` in the config can exit non-zero on first run.
tmux -L "$SOCK" source-file "$CONF" 2>/dev/null || true

# Point tpm at the throwaway server. Its scripts call bare `tmux`, and a bare
# tmux client follows $TMUX whenever it is set — and bin/mkworld.sh is normally
# run from inside a tmux session, so $TMUX arrives here pointing at a different
# server entirely. When that inherited server is an older build than the tmux
# now on PATH (a distro /usr/bin/tmux still serving the session while Homebrew
# supplies the client), every tpm call dies with "server version is too old for
# client" and tpm gives up with "FATAL: Tmux Plugin Manager not configured in
# tmux.conf" — which, under mkworld's `set -e`, took the rest of the bootstrap
# (Claude tmux hooks, lefthook) down with it.
TMUX="$(tmux -L "$SOCK" display-message -p '#{socket_path},#{pid},0')"
export TMUX

echo "== installing plugins from @tpm_plugins =="
"$TPM/bin/install_plugins"

echo "== pinning to $LOCK =="
for repo in $(tmux -L "$SOCK" show-option -gqv @tpm_plugins); do
  pin "$repo" "$PLUGIN_DIR/${repo##*/}"
done

echo "== installed under $PLUGIN_DIR =="
ls -1 "$PLUGIN_DIR"
