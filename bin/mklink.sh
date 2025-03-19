#!/bin/sh

set -e
set -x

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.."; pwd)

cd "$HOME"
ln -nsf "$BASE_DIR/bin/" ./bin
ln -nsf "$BASE_DIR/config" ./.config
ln -nsf "$BASE_DIR/hammerspoon" ./.hammerspoon
ln -nsf "$BASE_DIR/.vim" ./.vim

ln -sf "$BASE_DIR/.inputrc" ./
ln -sf "$BASE_DIR/.editrc" ./
ln -sf "$BASE_DIR/.gitconfig" ./
ln -sf "$BASE_DIR/.gitconfig.default_user" ./
ln -sf "$BASE_DIR/.gitignore" ./
ln -sf "$BASE_DIR/.tmux.conf" ./
ln -sf "$BASE_DIR/.zshrc" ./
ln -sf "$BASE_DIR/.zlogin" ./
ln -sf "$BASE_DIR/.irbrc" ./
ln -sf "$BASE_DIR/.vimrc" ./
