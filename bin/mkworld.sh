#!/bin/bash

set -e
set -x

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.."; pwd)

cd "$HOME"

mkdir -p ./tmp
sh "$BASE_DIR/bin/mklink.sh"
if [ "${SKIP_BREW:-0}" = "0" ]; then
    sh "$BASE_DIR/bin/setup_homebrew.sh"
fi

if [ ! -d ~/.tmux ]; then
    mkdir -p ~/.tmux/plugins
    git clone "https://github.com/tmux-plugins/tpm" ~/.tmux/plugins/tpm
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

# Install git hooks (lefthook) and the commit message template
if command -v lefthook >/dev/null 2>&1; then
    (cd "$BASE_DIR" && lefthook install && git config --local commit.template .gitmessage)
fi
