#!/bin/sh

set -e
set -x

SCRIPT_DIR=$(cd $(dirname $(readlink -f $0))/..; pwd)

cd $HOME
ln -sf "$SCRIPT_DIR/bin" ./
ln -sf "$SCRIPT_DIR/config" ./.config

ln -sf "$SCRIPT_DIR/.inputrc" ./
ln -sf "$SCRIPT_DIR/.gitconfig" ./
ln -sf "$SCRIPT_DIR/.gitignore" ./
ln -sf "$SCRIPT_DIR/.tmux.conf" ./
ln -sf "$SCRIPT_DIR/.zshrc" ./
ln -sf "$SCRIPT_DIR/.zlogin" ./
ln -sf "$SCRIPT_DIR/.irbrc" ./

ln -sf "$SCRIPT_DIR/.vimrc" ./
ln -sf "$SCRIPT_DIR/.vim" ./

ln -sf "$SCRIPT_DIR/.Xdefaults" ./
ln -sf "$SCRIPT_DIR/.Xmodmap" ./
