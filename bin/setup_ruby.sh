#!/bin/sh

VER="1.9.3.-p327"

#Rubyが依存してるライブラリをインストールします
sudo yum install -y zlib-devel openssl-devel

rbenv install "$VER"
rbenv global "$VER" # これ使いますよ宣言

