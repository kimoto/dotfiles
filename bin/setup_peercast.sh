#!/bin/sh

mkdir -p ~/projects/
cd projects/

git clone https://github.com/kimoto/peercast
cd peercast/ui/linux/
make

./peercast --help

