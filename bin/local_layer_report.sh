#!/bin/bash
# Say which of the per-machine files the dotfiles source this machine has.
# Their contents never enter the repo, so a rebuilt machine loses that layer
# without a word unless something lists it; local.example/ says what goes in
# each. Reporting only: a missing file is normal on a fresh machine.
set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
home="${HOME:?}"

have=()
missing=()
for example in "$BASE_DIR"/local.example/.*.local; do
    [ -f "$example" ] || continue
    name="${example##*/}"
    if [ -e "$home/$name" ]; then
        have+=("$name")
    else
        missing+=("$name")
    fi
done

echo "local layer: ${have[*]:-none} present"
if [ "${#missing[@]}" -gt 0 ]; then
    echo "local layer: ${missing[*]} absent; what goes in each: $BASE_DIR/local.example/"
fi
