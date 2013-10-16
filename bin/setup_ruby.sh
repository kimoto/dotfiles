#!/bin/sh

VER="1.9.3-p448"

#Rubyが依存してるライブラリをインストールします
sudo yum install -y zlib-devel openssl-devel bzip2-devel

rbenv install "$VER"
rbenv global "$VER" # これ使いますよ宣言

