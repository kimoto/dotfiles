#!/bin/bash

set -e
set -x

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.."; pwd)

cd "$HOME"

mkdir -p ./tmp
sh "$BASE_DIR/bin/mklink.sh"
sh "$BASE_DIR/bin/setup_homebrew.sh"

if [ ! -d ~/.tmux ]; then
    mkdir -p ~/.tmux/plugins
    git clone "https://github.com/tmux-plugins/tpm" ~/.tmux/plugins/tpm
fi
