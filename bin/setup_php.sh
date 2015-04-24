#!/bin/sh

VER="5.6.2"
PREFIX="/usr/local"
WORKDIR="/tmp"

set -ex
cd $WORKDIR

wget -O ./php-$VER.tar.gz "http://jp1.php.net/get/php-$VER.tar.gz/from/this/mirror"
tar xvfz "./php-$VER.tar.gz"
cd "./php-$VER"

./configure --prefix="$PREFIX" --with-mysql --with-zlib --with-gd --with-jpeg-dir --with-iconv-dir --enable-mbstring --enable-opcache
make
sudo make install

echo "setup successful!!"
