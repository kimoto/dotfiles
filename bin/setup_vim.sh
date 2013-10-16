#!/bin/sh

VER="7.3"
DIRVER="73"
WORKDIR="/tmp"
PREFIX="/usr/local"

cd $WORKDIR
wget -N "ftp://ftp.vim.org/pub/vim/unix/vim-$VER.tar.bz2"
tar xvfj "./vim-$VER.tar.bz2"
cd "./vim$DIRVER"

sudo yum install -y ncurses-devel
./configure --with-features=huge --enable-pythoninterp --enable-rubyinterp --prefix=$PREFIX

make
sudo make install

