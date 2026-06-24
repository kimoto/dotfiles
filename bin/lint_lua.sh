#!/bin/bash

# Syntax-check Lua files (luajit -b, parse only, no bytecode kept).
# LuaJIT is Neovim's own runtime (Lua 5.1 semantics), so this catches exactly
# the syntax errors nvim would choke on at startup. Single source of truth
# shared by CI and the lefthook pre-commit hook. Pass files as arguments; with
# none, all tracked *.lua files are checked.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

if ! command -v luajit >/dev/null 2>&1; then
    echo "x luajit not found; install it (brew install luajit, or apt-get install luajit)" >&2
    exit 1
fi

files=()
if [ "$#" -gt 0 ]; then
    files=("$@")
else
    while IFS= read -r f; do
        files+=("$f")
    done < <(git ls-files '*.lua')
fi

[ "${#files[@]}" -eq 0 ] && exit 0

rc=0
for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    # -b compiles to bytecode (parses the whole file); discard the output.
    if luajit -b "$f" /dev/null; then
        echo "ok $f"
    else
        echo "x lua syntax check failed: $f"
        rc=1
    fi
done

exit "$rc"
