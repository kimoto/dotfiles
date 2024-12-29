#!/bin/sh

set -e

cd $HOME
mkdir -p ./tmp

SCRIPT_DIR=$(cd $(dirname $(readlink -f $0))/..; pwd)

sh "$SCRIPT_DIR/bin/mklink.sh"
