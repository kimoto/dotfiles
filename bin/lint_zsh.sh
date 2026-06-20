#!/bin/bash

# Syntax-check zsh files (zsh -n).
# Single source of truth shared by CI and the lefthook pre-commit hook.
# Pass files as arguments; with none, all tracked zsh files are checked.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

files=()
if [ "$#" -gt 0 ]; then
    files=("$@")
else
    while IFS= read -r f; do
        files+=("$f")
    done < <(git ls-files '.zshrc' '.zshenv' '.zprofile' '*.zsh')
fi

[ "${#files[@]}" -eq 0 ] && exit 0

for f in "${files[@]}"; do
    zsh -n "$f"
done
