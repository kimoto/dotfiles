#!/bin/bash

set -e
set -x

echo $(dirname $(readlink -f $0))
SCRIPT_DIR=$(cd $(dirname $(readlink -f $0))/..; pwd)

cd $HOME
mkdir -p ./tmp
sh "$SCRIPT_DIR/bin/mklink.sh"
