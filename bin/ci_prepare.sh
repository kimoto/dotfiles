#!/bin/bash
# CI "cache phase" in one place: make the dotfiles world ready for the e2e tests.
# The only thing the workflow still owns around this is the actions/cache
# restore/save pair; *what* gets installed lives here in bin/ (single source of
# truth, runnable locally), instead of being scattered across workflow steps.
#
# A cache-hit signal comes from the workflow as an env var so the expensive,
# cache-populating Homebrew work runs only on a miss:
#   BREW_CACHE_HIT  - skip Homebrew + `brew bundle` when 'true'
# tmux is in Brewfile.basic (the tmux loading test needs it), so it comes in via
# `brew bundle`. fzf is not (it backs the `g` command, not shell load), so it is
# gated on presence instead. The tpm plugins are installed by mkworld
# (idempotent), which also populates the ~/.tmux/plugins cache on a miss.
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

# 2. fzf: not in Brewfile.basic (it backs the `g` command, not shell load), so
#    install on demand. Baked into the brew cache (key suffix -fzf), so this
#    touches the network at most once. tmux already came in via Brewfile.basic.
if command -v brew >/dev/null 2>&1; then
  command -v fzf >/dev/null 2>&1 || brew install fzf
fi

# 3. Symlinks, lefthook, and tpm plugins (mkworld installs the plugins, which
#    populates the ~/.tmux/plugins cache on a miss). brew is handled above.
SKIP_BREW=1 ./bin/mkworld.sh

echo "== cache phase complete =="
