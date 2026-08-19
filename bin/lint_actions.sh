#!/bin/bash

# Lint the GitHub Actions workflows two ways: ratchet checks that every `uses:`
# is pinned to a full commit SHA (not a mutable tag), actionlint checks the
# workflow itself — expression syntax, context properties, runner labels, plus
# a shellcheck pass over every `run:` block. Single source of truth shared by
# CI and the lefthook pre-commit hook. Both only look at .github/workflows, so
# workflow files are checked regardless of arguments.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

if ! command -v ratchet >/dev/null 2>&1; then
    echo "x ratchet not found; install it (brew install ratchet)" >&2
    exit 1
fi

if ! command -v actionlint >/dev/null 2>&1; then
    echo "x actionlint not found; install it (brew install actionlint)" >&2
    exit 1
fi

files=()
while IFS= read -r f; do
    files+=("$f")
done < <(git ls-files '.github/workflows/*.yml' '.github/workflows/*.yaml')

[ "${#files[@]}" -eq 0 ] && exit 0

ratchet lint "${files[@]}"
actionlint "${files[@]}"
