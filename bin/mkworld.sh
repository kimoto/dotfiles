#!/bin/sh

set -x 

cd $HOME
mkdir ./tmp 

CURRENT_DIR=`dirname $0`
. "$CURRENT_DIR/mklink.sh"
. "$CURRENT_DIR/mkcrontab.sh"
