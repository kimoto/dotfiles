#!/bin/sh

sudo yum install -y libxml2 libxml2-devel libxslt libxslt-devel mysql-devel ImageMagick ImageMagick-devel

cd ./projects/peercast.in
bundle install

