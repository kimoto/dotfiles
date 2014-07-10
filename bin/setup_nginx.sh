#!/bin/sh

VER="1.7.3"
PASSENGER_PATH="`passenger-config --root`/ext/nginx"
PREFIX="/usr/local/nginx"
WORKDIR="/tmp"

cd $WORKDIR

wget "http://nginx.org/download/nginx-$VER.tar.gz"
tar xvfz "./nginx-$VER.tar.gz"
cd "./nginx-$VER"

git clone git://gitorious.org/ngx-fancyindex/ngx-fancyindex.git ngx-fancyindex
sudo yum install -y libcurl-devel pcre-devel gd gd-devel

./configure --prefix="$PREFIX" --with-http_ssl_module --with-cc-opt='-Wno-error -O3' --add-module="$PASSENGER_PATH" --with-http_stub_status_module --add-module=./ngx-fancyindex/ --conf-path="$PREFIX/conf/nginx.conf" 
make
sudo make install

curl -L1 https://gist.github.com/kimoto/3046138/raw/4531d38d660129079146bba6232c3ce87caedb82/nginx > ./nginx
sudo mv ./nginx /etc/init.d/nginx
sudo chmod u+x /etc/init.d/nginx

sudo service nginx configtest 
echo "setup successful!!"

