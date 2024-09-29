#!/bin/sh

set -e
set -x

BASE_DIR=$(cd $(dirname $0)/..; pwd)

cd $HOME
ln -sf "$BASE_DIR/bin" ./
ln -sf "$BASE_DIR/config" ./.config

ln -sf "$BASE_DIR/.inputrc" ./
ln -sf "$BASE_DIR/.gitconfig" ./
ln -sf "$BASE_DIR/.gitignore" ./
ln -sf "$BASE_DIR/.tmux.conf" ./
ln -sf "$BASE_DIR/.zshrc" ./
ln -sf "$BASE_DIR/.zlogin" ./
ln -sf "$BASE_DIR/.irbrc" ./
ln -sf "$BASE_DIR/.gemrc" ./
ln -sf "$BASE_DIR/.nanorc" ./

ln -sf "$BASE_DIR/.vimrc" ./
ln -sf "$BASE_DIR/.vim" ./

ln -sf "$BASE_DIR/.Xdefaults" ./
ln -sf "$BASE_DIR/.Xmodmap" ./
