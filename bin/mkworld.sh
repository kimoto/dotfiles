#!/bin/sh

set -x 

cd $HOME
mkdir ./tmp 
#mkdir ./work
#mkdir -p ./local
mkdir -p ./archive/flat
mkdir -p ./var/log

CURRENT_DIR=`dirname $0`
. "$CURRENT_DIR/mklink.sh"
. "$CURRENT_DIR/mkcrontab.sh"
