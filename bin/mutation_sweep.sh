#!/bin/bash

# Find failure paths no test notices: flip each `exit 1` / `return 1` to 0,
# one at a time, run the tests that cover the script, and report the flips
# that left them green. A survivor is a failure exit that could go quiet with
# nobody told — the cue to add a test that watches it fail.
#
# Usage:
#   mutation_sweep.sh [SCRIPT...]   default: bin/*.sh .claude/hooks/*.sh ci/*.sh
# Prints one line per mutant, `survived <file>:<line>  <text>` or
# `killed <file>:<line>`, then a count. Exit 0 either way: survivors are a
# list to choose from, not a failure.
#
# Which tests cover a script is run_tests.sh's own selection (RUN_TESTS_LIST),
# the same set pre-commit runs, so a survivor means "the tests you would run
# for this file miss it". MUTATION_RUNNER replaces `bats` (for this script's
# own tests).
#
# Not mutated, because a test for them buys nothing: a guard after `cd` (the
# script's own directory, or one it just created) — it fails only when the
# checkout itself is broken. Lines that are comments are skipped too.
#
# The file is edited in place and restored from a copy after each run, and on
# any exit, so an interrupted sweep never leaves a mutant behind.

set -uo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1
runner=${MUTATION_RUNNER:-bats}

if [ "$#" -eq 0 ]; then
    set -- bin/*.sh .claude/hooks/*.sh ci/*.sh
fi

backup=$(mktemp "${TMPDIR:-/tmp}/mutation_sweep.XXXXXX") || exit 1
current=""
restore() {
    [ -n "$current" ] && cp "$backup" "$current"
    current=""
}
trap 'restore; rm -f "$backup"' EXIT
trap 'exit 130' INT TERM

survived=0 killed=0
for f in "$@"; do
    [ -f "$f" ] || continue
    # No mapfile: macOS's /bin/bash is 3.2.
    tests=()
    while IFS= read -r t; do
        case "$t" in *.bats) tests+=("$t") ;; esac
    done < <(RUN_TESTS_LIST=1 ./bin/run_tests.sh "$f" 2>/dev/null)
    if [ "${#tests[@]}" -eq 0 ]; then
        echo "untested $f"
        continue
    fi
    while IFS=: read -r ln text; do
        case "$text" in
            *"cd "*"|| exit 1"* | *"cd "*"|| return 1"*) continue ;;
        esac
        cp "$f" "$backup"
        current=$f
        sed -i.orig -E "${ln}s/(^|[^[:alnum:]_])(exit|return) 1([^0-9]|\$)/\1\2 0\3/" "$f" && rm -f "$f.orig"
        if "$runner" "${tests[@]}" >/dev/null 2>&1; then
            survived=$((survived + 1))
            printf 'survived %s:%s  %s\n' "$f" "$ln" "$(sed -E 's/^[[:space:]]+//' <<<"$text")"
        else
            killed=$((killed + 1))
            echo "killed $f:$ln"
        fi
        restore
    done < <(grep -nE '^([^#]*[^[:alnum:]_#])?(exit|return) 1([^0-9]|$)' "$f")
done
echo "== $survived survived, $killed killed =="
