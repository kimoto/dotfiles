#!/bin/bash

set -euo pipefail

# The installer runs as a script fetched over the network, so it runs from a
# commit a person has read rather than whatever HEAD holds that minute, and
# only if its bytes match the hash recorded with that commit. Renovate proposes
# a newer commit in its monthly PR once it is a week old; that PR stays red
# until someone reads the new installer and records its hash here.
# renovate: datasource=github-digest depName=Homebrew/install branch=main
HOMEBREW_INSTALL_REF="7a3f48c7e498d7df3237fd41c30f4d492857edf4"
HOMEBREW_INSTALL_SHA256="5f333bbe53bc490e51e7ccb1df8779b3dd6ee73a1a7379efda216edb08ccb148"

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1;

# Everything here is discovery, for the normal case of a machine that may not
# have Homebrew yet. A caller that already knows where brew is passes BREW_BIN
# and skips the lot -- including the `shellenv` eval, which prepends a prefix to
# PATH and would otherwise decide the answer for it.
if [ -z "${BREW_BIN:-}" ]; then
    if ! command -v brew >/dev/null 2>&1; then
        os="$(uname)"
        if [ "$os" = "Darwin" ] || [ "$os" = "Linux" ]; then
            installer="$(mktemp)"
            trap 'rm -f "$installer"' EXIT
            curl -fsSL -o "$installer" \
                "https://raw.githubusercontent.com/Homebrew/install/$HOMEBREW_INSTALL_REF/install.sh"
            # shasum ships with macOS, sha256sum with coreutils on Linux.
            if command -v sha256sum >/dev/null 2>&1; then
                got="$(sha256sum "$installer" | cut -d' ' -f1)"
            else
                got="$(shasum -a 256 "$installer" | cut -d' ' -f1)"
            fi
            if [ "$got" != "$HOMEBREW_INSTALL_SHA256" ]; then
                echo "Homebrew installer at $HOMEBREW_INSTALL_REF hashes to $got, expected $HOMEBREW_INSTALL_SHA256" >&2
                exit 1
            fi
            /bin/bash "$installer"
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
fi
if [ -z "${BREW_BIN:-}" ]; then
    echo "brew not found after installation" >&2
    exit 1
fi

"$BREW_BIN" bundle install --file=Brewfile.standard

# Brewfile.extra and the platform Brewfile are the extra and platform phases:
# the expensive half, and a caller that only needs a shell to start says so.
# Deliberately not keyed on $CI: Actions exports CI=true into every step, so the
# one job built to bootstrap with nothing skipped could not opt back in, and
# installed nothing but Brewfile.standard.
if [ "${SKIP_BREWFILE_EXTRA:-0}" != "1" ]; then
    "$BREW_BIN" bundle install --file=Brewfile.extra
    case "$(uname)" in
        Darwin)
            "$BREW_BIN" bundle install --file=Brewfile.macos
            ;;
        Linux)
            "$BREW_BIN" bundle install --file=Brewfile.linux
            ;;
    esac
fi
