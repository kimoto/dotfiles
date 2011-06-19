#!/bin/sh
# 注意: $HOMEディレクトリのファイルが消えます
# Notice: this script, remove all files in $HOME

set -x

cd $HOME
rm "$BASE_DIR/bin" ./

rm -rf ./*

rm ./.vimrc
rm ./.inputrc
rm ./.vimperatorrc 
rm ./.gitconfig
rm ./.gitignore
rm ./.screenrc
rm ./.zshrc
rm ./.zlogin
rm ./.bashrc
rm ./.irbrc

rm ./.vim
rm ./.subversion

rm ./.Xdefaults
rm ./.Xmodmap

rm ./.emacs.d
rm ./.emacs

