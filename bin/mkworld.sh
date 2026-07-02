#!/bin/bash

set -euo pipefail
set -x

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.."; pwd)

cd "$HOME"

mkdir -p ./tmp
sh "$BASE_DIR/bin/mklink.sh"
if [ "${SKIP_BREW:-0}" = "0" ]; then
    sh "$BASE_DIR/bin/setup_homebrew.sh"
fi

# Vim (legacy .vimrc): fetch the NeoBundle plugin manager, tracked as a
# submodule under .vim/bundle/. With it present, the first `vim` launch runs
# NeoBundleCheck to install the remaining plugins instead of erroring on every
# NeoBundle command. (.vimrc also self-bootstraps neobundle at launch; this just
# makes it available up front, at install time.)
git -C "$BASE_DIR" submodule update --init --recursive

# Make brew-installed tools (e.g. lefthook) available on PATH
if [ -x "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Install tpm and its plugins headlessly (idempotent). Needs tmux on PATH; on a
# fresh box that doesn't have it yet, skip rather than fail so the rest of the
# bootstrap (symlinks, hooks) still completes.
if command -v tmux >/dev/null 2>&1; then
    "$BASE_DIR/bin/install_tmux_plugins.sh"
else
    echo "tmux not found on PATH; skipping tmux plugin install" >&2
fi

# Claude Code: register the tmux state-indicator hooks (pane/window colors for
# waiting-for-input / finished states) in ~/.claude/settings.json. Idempotent;
# warns and skips instead of failing when jq is missing.
sh "$BASE_DIR/bin/install_claude_tmux_hooks.sh"

# Install git hooks (lefthook) and the commit message template
if command -v lefthook >/dev/null 2>&1; then
    (cd "$BASE_DIR" && lefthook install && git config --local commit.template .gitmessage)
fi

# macOS: enable weekly background brew auto-upgrade (formulae; casks stay manual).
# Non-fatal so a hiccup here never aborts the bootstrap.
if [ "$(uname)" = "Darwin" ] && [ "${SKIP_BREW:-0}" = "0" ]; then
    sh "$BASE_DIR/bin/setup_brew_autoupdate.sh" || true
fi

# macOS: apply system preferences (Finder, key repeat, startup mute — needs
# sudo for nvram). Non-fatal so a denied sudo never aborts the bootstrap.
if [ "$(uname)" = "Darwin" ]; then
    sh "$BASE_DIR/bin/setup_macosx.sh" || true
fi
