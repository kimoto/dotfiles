#!/bin/sh

set -x

BASE_DIR="./svn"

cd $HOME
ln -sf "$BASE_DIR/config" ./
ln -sf "$BASE_DIR/utils" ./
ln -sf "$BASE_DIR/sandbox" ./
ln -sf "$BASE_DIR/system" ./

ln -sf ./config/.vimrc ./
ln -sf ./config/.inputrc ./
ln -sf ./config/.vimperatorrc ./
ln -sf ./config/.gitconfig ./
ln -sf ./config/.gitignore ./
ln -sf ./config/.screenrc ./
ln -sf ./config/.zshrc ./
ln -sf ./config/.zlogin ./
ln -sf ./config/.bashrc ./
ln -sf ./config/.irbrc ./

ln -sf ./config/.vim ./
ln -sf ./config/.subversion ./

ln -sf ./config/.Xdefaults ./
ln -sf ./config/.Xmodmap ./

# next generation .emacs!!
ln -sf ./config/.emacs.d ./
ln -sf ./config/.emacs ./

