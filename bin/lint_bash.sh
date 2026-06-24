#!/bin/bash

# Syntax-check bash dotfiles (bash -n). The bin/*.sh scripts are already covered
# by lint_shell.sh (bash -n + shellcheck); this targets the bash *config* files
# that get sourced into an interactive shell, where a syntax error breaks login.
# Single source of truth shared by CI and the lefthook pre-commit hook. Pass
# files as arguments; with none, all tracked bash dotfiles are checked.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

files=()
if [ "$#" -gt 0 ]; then
    files=("$@")
else
    while IFS= read -r f; do
        files+=("$f")
    done < <(git ls-files '.bashrc' '.bash_profile' '.bash_login' '.bash_logout' '.bash_aliases' '*.bash')
fi

[ "${#files[@]}" -eq 0 ] && exit 0

for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    bash -n "$f"
done
