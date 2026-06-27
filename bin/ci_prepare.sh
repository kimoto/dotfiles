#!/bin/bash
# CI "cache phase" in one place: make the dotfiles world ready for the e2e tests.
# The only thing the workflow still owns around this is the actions/cache
# restore/save pair; *what* gets installed lives here in bin/ (single source of
# truth, runnable locally), instead of being scattered across workflow steps.
#
# A cache-hit signal comes from the workflow as an env var so the expensive,
# cache-populating Homebrew work runs only on a miss:
#   BREW_CACHE_HIT  - skip Homebrew + `brew bundle` when 'true'
# tmux/fzf are gated on presence instead: they live in the brew cache but not in
# Brewfile.basic, so a `command -v` check is the right idempotent guard. The tpm
# plugins are installed by mkworld (idempotent), which also populates the
# ~/.tmux/plugins cache on a miss and is a near no-op on a hit.
set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

# 1. Homebrew + Brewfile.basic — this is what populates the brew cache, so it
#    only needs to run on a cache miss.
if [ "${BREW_CACHE_HIT:-}" = "true" ]; then
  echo "== brew cache hit: skipping Homebrew install =="
else
  echo "== brew cache miss: installing Homebrew + Brewfile.basic =="
  ./bin/setup_homebrew.sh
fi

# Put brew on PATH for the rest of this script, whichever path ran above.
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# 2. tmux + fzf: not in Brewfile.basic (not needed to start the shell), so
#    install on demand — before mkworld, which needs tmux to install the tpm
#    plugins. They are baked into the brew cache (key suffix -tmux-fzf), so this
#    touches the network at most once.
if command -v brew >/dev/null 2>&1; then
  command -v tmux >/dev/null 2>&1 || brew install tmux
  command -v fzf >/dev/null 2>&1 || brew install fzf
fi

# 3. Symlinks, lefthook, and tpm plugins (mkworld installs the plugins, which
#    populates the ~/.tmux/plugins cache on a miss). brew is handled above.
SKIP_BREW=1 ./bin/mkworld.sh

echo "== cache phase complete =="
