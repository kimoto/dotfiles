#!/bin/bash

# Static checks for shell scripts (bash -n syntax + shellcheck).
# Single source of truth shared by CI (.github/workflows/ci.yml) and the
# lefthook pre-commit hook (lefthook.yml), so the checks never diverge.
# Covers every tracked *.sh script (bin/, vscode/, .claude/hooks/, …), not
# just bin/. Pass files as arguments; with none, all tracked *.sh are checked.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

# Keep only files that still exist: a staged deletion can reach us as an arg,
# and expanding an empty array under `set -u` aborts on bash 3.2 (macOS).
files=()
if [ "$#" -gt 0 ]; then
    for f in "$@"; do
        [ -f "$f" ] && files+=("$f")
    done
else
    while IFS= read -r f; do
        [ -f "$f" ] && files+=("$f")
    done < <(git ls-files '*.sh')
fi

[ "${#files[@]}" -eq 0 ] && exit 0

# Syntax check each script (bash -n only inspects its first file argument).
for f in "${files[@]}"; do
    bash -n "$f"
done

shellcheck "${files[@]}"
