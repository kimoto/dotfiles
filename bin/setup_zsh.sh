#!/bin/sh

VER="5.0.7"
PREFIX="/usr/local"
WORKDIR="/tmp"

set -ex
cd $WORKDIR

wget -O ./zsh-$VER.tar.gz "http://downloads.sourceforge.net/project/zsh/zsh/$VER/zsh-$VER.tar.gz?r=&ts=1413967727&use_mirror=jaist"
tar xvfz "./zsh-$VER.tar.gz"
cd "./zsh-$VER"

./configure --prefix="$PREFIX"
make
sudo make install

echo "setup successful!!"
