#!/bin/sh

set -x

BASE_DIR="./dotfiles"

cd $HOME
ln -sf "$BASE_DIR/bin" ./

ln -sf ./dotfiles/.vimrc ./
ln -sf ./dotfiles/.bvirc ./
ln -sf ./dotfiles/.inputrc ./
ln -sf ./dotfiles/.vimperatorrc ./
ln -sf ./dotfiles/.gitconfig ./
ln -sf ./dotfiles/.gitignore ./
ln -sf ./dotfiles/.screenrc ./
ln -sf ./dotfiles/.zshrc ./
ln -sf ./dotfiles/.zlogin ./
ln -sf ./dotfiles/.bashrc ./
ln -sf ./dotfiles/.irbrc ./
ln -sf ./dotfiles/.gitconfig ./
ln -sf ./dotfiles/.gemrc ./
ln -sf ./dotfiles/.nanorc ./
ln -sf ./dotfiles/.tmux.conf ./

ln -sf ./dotfiles/.vim ./
ln -sf ./dotfiles/.zsh ./
ln -sf ./dotfiles/.subversion ./
ln -sf ./dotfiles/.peco ./

ln -sf ./dotfiles/.Xdefaults ./
ln -sf ./dotfiles/.Xmodmap ./

# next generation .emacs!!
ln -sf ./dotfiles/.emacs.d ./
ln -sf ./dotfiles/.emacs ./

# $HOMEに./configというシンボリックリンクがなければ作成する
test -h ./config || ln -sf ./dotfiles ./config
