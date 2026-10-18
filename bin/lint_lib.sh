#!/bin/bash
# Shared plumbing for the bin/lint_*.sh scripts, which CI and the lefthook
# pre-commit hook both call. This file is *sourced*, not executed:
#
#   # shellcheck source=bin/lint_lib.sh
#   . "$(dirname "$(readlink -f "$0")")/lint_lib.sh"
#
# Sourcing it moves to the repo root, so tracked paths resolve the same from
# any cwd.

BASE_DIR=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

# lint_require TOOL [HINT]: exit 1 unless TOOL is on PATH.
lint_require() {
    command -v "$1" >/dev/null 2>&1 && return 0
    echo "x $1 not found; ${2:-install it (run 'mise install' in this repo)}" >&2
    exit 1
}

# lint_collect PATTERN... -- ARG...: set `files` to the ARGs (lefthook's staged
# files) or, with none, every tracked file matching a PATTERN. Paths that no
# longer exist are dropped: a staged deletion can still arrive as an ARG.
lint_collect() {
    local patterns=() f
    while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
        patterns+=("$1")
        shift
    done
    [ "$#" -gt 0 ] && shift
    files=()
    if [ "$#" -gt 0 ]; then
        for f in "$@"; do
            if [ -f "$f" ]; then files+=("$f"); fi
        done
    else
        while IFS= read -r f; do
            if [ -f "$f" ]; then files+=("$f"); fi
        done < <(git ls-files "${patterns[@]}")
    fi
}
