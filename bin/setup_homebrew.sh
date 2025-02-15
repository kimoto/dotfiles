#!/bin/bash

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1;

if ! type "brew" &> /dev/null ; then
    os="$(uname)"
    if [ "$os" == "Darwin" ] || [ "$os" == "Linux" ]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
fi

brew bundle install --file=Brewfile
