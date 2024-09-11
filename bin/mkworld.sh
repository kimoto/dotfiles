#!/bin/sh

set -e
set -x 

cd $HOME
mkdir -p ./tmp

CURRENT_DIR=`dirname $0`
. "$CURRENT_DIR/mklink.sh"
# . "$CURRENT_DIR/mkcrontab.sh"
