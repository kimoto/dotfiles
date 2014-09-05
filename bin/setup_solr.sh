#!/bin/sh

base_url="http://ftp.riken.jp/net/apache/lucene/solr"
ver="4.7.0"
curdir=`cd $(dirname $0);pwd`/../
prefix="/usr/local"

USER=root # solrのownerを誰にするか
GROUP=root    # groupをどうするか

if [ `whoami` != 'root' ]; then
	echo "you arent root user"
	exit 1
fi

# すでにinstallされてるか調べる
if [ -e "$prefix/solr-$ver" ]; then
	echo "Apache Solr: already installed"
	exit 1
fi

# ログ出力
set -xe

# 実行ファイルを取ってくる
tmpdir=`mktemp -d`
cd $tmpdir
wget -N -O solr-${ver}.tgz ${base_url}/${ver}/solr-${ver}.tgz 
tar xvfz ./solr-${ver}.tgz

# appの下に配置
mkdir -p $prefix
chown -R $USER:$GROUP solr-${ver}
mv solr-${ver} $prefix
ln -s $prefix/solr-${ver} $prefix/solr

# exampleフォルダをapplicationと変えて、設定ファイルは ./etc/solr で上書きする
cd $prefix/solr/
if [ -d ./example ]; then
  mv ./example ./application
fi
cd ./application
#rm -rf ./solr
mv ./solr ./solr.old # backup
#cp -a $curdir/etc/solr ./solr
