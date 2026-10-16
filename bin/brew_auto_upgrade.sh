#!/bin/bash

# Installs and upgrades the homebrew/core formulae the Brewfiles list, with
# nobody at the keyboard. Run daily by the launchd agent that
# setup_brew_auto_upgrade.sh installs.
#
# Only homebrew/core formulae: their version bumps are reviewed by Homebrew
# maintainers, who also hold back freshly published npm/PyPI/RubyGems releases
# during builds, so a second delay here would only postpone security fixes.
# Casks run the vendor's own installer and third-party taps have no such review,
# so both stay with brew_bundle_install.sh, run by a human.
#
# On success it stamps $cache_dir/brew_auto_upgrade_ok, which is what
# brew_bundle_check.sh reads to stop nagging about formulae — and to nag about
# this job instead once it has not succeeded for a while.

set -uo pipefail

REPO_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd) || exit 1
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"

# A name with a slash is tap-qualified (owner/tap/name), so not homebrew/core.
core_formulae() {
    grep -v / | sort -u
}

# Sourced by test/brew_auto_upgrade.bats to unit-test the filter.
[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

if ! command -v brew >/dev/null 2>&1; then
    echo "brew not found" >&2
    exit 1
fi

files=(Brewfile.standard Brewfile.full)
case "$(uname)" in
    Darwin) files+=(Brewfile.macos) ;;
    Linux) files+=(Brewfile.linux) ;;
esac

# No terminal and no sudo: anything that would prompt fails instead of hanging.
exec </dev/null
SUDO_ASKPASS=$(type -P false)
export SUDO_ASKPASS HOMEBREW_NO_ENV_HINTS=1

date
brew update || exit 1

names=()
while IFS= read -r name; do
    [ -n "$name" ] && names+=("$name")
done < <(
    for f in "${files[@]}"; do
        [ -f "$REPO_DIR/$f" ] || continue
        brew bundle list --formula --file="$REPO_DIR/$f" 2>/dev/null
    done | core_formulae
)

if [ "${#names[@]}" -eq 0 ]; then
    echo "no homebrew/core formulae listed; nothing to do"
    exit 1
fi

# `brew install` installs what is missing and upgrades what is outdated.
brew install --formula "${names[@]}" || exit 1

mkdir -p "$cache_dir"
date +%s >|"$cache_dir/brew_auto_upgrade_ok"
