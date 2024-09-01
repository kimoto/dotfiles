#!/bin/sh

set -x

BASE_DIR="./dotfiles"

cd $HOME
ln -sf "$BASE_DIR/bin" ./
ln -sf ./dotfiles/config ./.config

ln -sf ./dotfiles/.vimrc ./
ln -sf ./dotfiles/.inputrc ./
ln -sf ./dotfiles/.gitconfig ./
ln -sf ./dotfiles/.gitignore ./
ln -sf ./dotfiles/.tmux.conf ./
ln -sf ./dotfiles/.zshrc ./
ln -sf ./dotfiles/.zlogin ./
ln -sf ./dotfiles/.irbrc ./
ln -sf ./dotfiles/.gemrc ./
ln -sf ./dotfiles/.nanorc ./

ln -sf ./dotfiles/.vim ./
ln -sf ./dotfiles/.zsh ./

ln -sf ./dotfiles/.Xdefaults ./
ln -sf ./dotfiles/.Xmodmap ./
