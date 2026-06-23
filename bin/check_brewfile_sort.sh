#!/bin/bash

# Verify each Brewfile keeps its tap/brew/cask entries sorted A-Z (case-insensitive),
# matching the "Keep entries sorted A-Z" convention.
# Single source of truth shared by CI and the lefthook pre-commit hook.
# Pass files as arguments; with none, the repo's four Brewfiles are checked.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

files=("$@")
if [ "${#files[@]}" -eq 0 ]; then
    files=(Brewfile.basic Brewfile.common Brewfile.linux Brewfile.macos)
fi

rc=0
for bf in "${files[@]}"; do
    [ -f "$bf" ] || continue
    for kind in tap brew cask; do
        names=$(grep -E "^$kind \"" "$bf" | sed -E "s/^$kind \"([^\"]+)\".*/\1/" || true)
        [ -z "$names" ] && continue
        if [ "$names" != "$(printf '%s\n' "$names" | LC_ALL=C sort -f)" ]; then
            echo "x $bf: $kind entries are not sorted A-Z"
            rc=1
        fi
    done
done

exit "$rc"
