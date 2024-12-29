#!/bin/bash

BASE_DIR=$(cd $(dirname $(readlink -f $0))/..; pwd)
cd $BASE_DIR

if [ $(uname) = Darwin ]; then
    if ! type brew &> /dev/null ; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    brew bundle install --file=Brewfile
fi
