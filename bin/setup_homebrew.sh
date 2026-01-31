#!/bin/bash

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1;

if ! command -v brew >/dev/null 2>&1; then
    os="$(uname)"
    if [ "$os" = "Darwin" ] || [ "$os" = "Linux" ]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
fi

if [ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -x "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

BREW_BIN="$(command -v brew 2>/dev/null || true)"
if [ -z "$BREW_BIN" ]; then
    if [ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
        BREW_BIN="/home/linuxbrew/.linuxbrew/bin/brew"
    elif [ -x "/opt/homebrew/bin/brew" ]; then
        BREW_BIN="/opt/homebrew/bin/brew"
    fi
fi
if [ -z "$BREW_BIN" ]; then
    echo "brew not found after installation" >&2
    exit 1
fi

"$BREW_BIN" bundle install --file=Brewfile.basic
if [ "${CI:-}" != "true" ]; then
    "$BREW_BIN" bundle install --file=Brewfile.common
fi

case "$(uname)" in
    Darwin)
        "$BREW_BIN" bundle install --file=Brewfile.macos
        ;;
    Linux)
        "$BREW_BIN" bundle install --file=Brewfile.linux
        ;;
esac
