#!/bin/bash

# Syntax-check zsh files (zsh -n).

set -euo pipefail

# shellcheck source=bin/lint_lib.sh
. "$(dirname "$(readlink -f "$0")")/lint_lib.sh"

lint_collect '.zshrc' '.zshenv' '.zprofile' '*.zsh' -- "$@"

[ "${#files[@]}" -eq 0 ] && exit 0

for f in "${files[@]}"; do
    zsh -n "$f"
done
