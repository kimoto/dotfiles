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

PLUGIN_DIR="$HOME/.tmux/plugins"
TPM="$PLUGIN_DIR/tpm"
if [ ! -d "$TPM" ]; then
  echo "== cloning tpm =="
  mkdir -p "$PLUGIN_DIR"
  git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM"
fi

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

echo "== installing plugins from @tpm_plugins =="
"$TPM/bin/install_plugins"

echo "== installed under $PLUGIN_DIR =="
ls -1 "$PLUGIN_DIR"
