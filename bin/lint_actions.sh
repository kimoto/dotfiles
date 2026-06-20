#!/bin/bash

# Verify every GitHub Actions `uses:` in our workflows is pinned to a full
# commit SHA (not a mutable tag). Single source of truth shared by CI and the
# lefthook pre-commit hook. ratchet only applies to .github/workflows, so all
# workflow files are checked regardless of arguments.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

if ! command -v ratchet >/dev/null 2>&1; then
    echo "x ratchet not found; install it (brew install ratchet)" >&2
    exit 1
fi

files=()
while IFS= read -r f; do
    files+=("$f")
done < <(git ls-files '.github/workflows/*.yml' '.github/workflows/*.yaml')

[ "${#files[@]}" -eq 0 ] && exit 0

ratchet lint "${files[@]}"
