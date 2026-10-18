#!/bin/bash

# Syntax-check bash dotfiles (bash -n). The bin/*.sh scripts are already covered
# by lint_shell.sh (bash -n + shellcheck); this targets the bash *config* files
# that get sourced into an interactive shell, where a syntax error breaks login.

set -euo pipefail

# shellcheck source=bin/lint_lib.sh
. "$(dirname "$(readlink -f "$0")")/lint_lib.sh"

lint_collect '.bashrc' '.bash_profile' '.bash_login' '.bash_logout' '.bash_aliases' '*.bash' -- "$@"

[ "${#files[@]}" -eq 0 ] && exit 0

for f in "${files[@]}"; do
    bash -n "$f"
done
