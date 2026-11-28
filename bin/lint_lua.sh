#!/bin/bash

# Syntax-check Lua files (luajit -b, parse only, no bytecode kept).
# LuaJIT is Neovim's own runtime (Lua 5.1 semantics), so this catches exactly
# the syntax errors nvim would choke on at startup.

set -euo pipefail

# shellcheck source=bin/lint_lib.sh
. "$(dirname "$(readlink -f "$0")")/lint_lib.sh"

lint_require luajit "install it (brew install luajit, or apt-get install luajit)"

lint_collect '*.lua' -- "$@"

[ "${#files[@]}" -eq 0 ] && exit 0

rc=0
for f in "${files[@]}"; do
    # -b compiles to bytecode (parses the whole file); discard the output.
    if luajit -b "$f" /dev/null; then
        echo "ok $f"
    else
        echo "x lua syntax check failed: $f"
        rc=1
    fi
done

exit "$rc"
