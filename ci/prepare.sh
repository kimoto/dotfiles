#!/bin/bash
# CI "cache phase" in one place: make the dotfiles world ready for the e2e tests.
# The workflow owns only the actions/cache restore/save pair around this; *what*
# gets installed lives here, in one script that also runs locally.
#
# A cache-hit signal comes from the workflow as an env var so the expensive,
# cache-populating Homebrew work runs only on a miss:
#   BREW_CACHE_HIT  - skip Homebrew + `brew bundle` when 'true'
# fzf comes in via `brew bundle`; tmux is in Brewfile.extra, which CI skips, so
# it is installed on demand below. The tpm plugins are installed by mkworld
# (idempotent), which also populates the ~/.tmux/plugins cache on a miss.
set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

# 1. Homebrew + Brewfile.standard — this is what populates the brew cache, so it
#    only needs to run on a cache miss.
if [ "${BREW_CACHE_HIT:-}" = "true" ]; then
  echo "== brew cache hit: skipping Homebrew install =="
else
  echo "== brew cache miss: installing Homebrew + Brewfile.standard =="
  SKIP_BREWFILE_EXTRA=1 ./bin/setup_homebrew.sh
fi

# Put brew on PATH for the rest of this script, whichever path ran above.
# shellcheck source=bin/brew_lib.sh
. "$BASE_DIR/bin/brew_lib.sh"
load_brew

# 2. tmux: in Brewfile.extra (it runs only when typed), but every tmux e2e test
#    needs it. Baked into the brew cache (key suffix -tmux), so this touches
#    the network at most once.
if command -v brew >/dev/null 2>&1; then
  brew list tmux >/dev/null 2>&1 || brew install tmux
fi

# 3. Symlinks, lefthook, and tpm plugins (mkworld installs the plugins, which
#    populates the ~/.tmux/plugins cache on a miss). brew is handled above.
SKIP_BREW=1 MKWORLD_EXPECT=standard ./bin/mkworld.sh

echo "== cache phase complete =="
