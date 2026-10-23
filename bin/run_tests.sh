#!/bin/bash

# Run the bats unit-test suite (test/*.bats).
# Single source of truth shared by CI and the lefthook pre-commit hook, so the
# tests never diverge between local checks and CI.
#
# No arguments runs the whole suite (CI). Given paths (pre-commit's staged
# files), it runs only the .bats files those paths reach: a staged .bats file
# itself, and every .bats file that names a staged script. The whole suite
# takes over a minute, and a pre-commit that slow gets skipped with
# --no-verify; CI still runs all of it. RUN_TESTS_LIST=1 prints the selection
# instead of running it, so the selection itself can be tested.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

# lefthook calls this from a git hook, so the whole suite would inherit GIT_DIR
# and GIT_INDEX_FILE. Each fixture drops them too; doing it here as well keeps a
# fixture that forgets from writing into the checkout under test.
# shellcheck source=/dev/null
. "$BASE_DIR/bin/git_fixture_helpers.sh"
isolate_git_env

if ! command -v bats >/dev/null 2>&1; then
    echo "x bats not found; install it (brew install bats-core, or apt-get install bats)" >&2
    exit 1
fi

if [ "$#" -eq 0 ]; then
    targets=(test/)
else
    targets=()
    for path in "$@"; do
        case "$path" in
            test/*.bats) [ -f "$path" ] && targets+=("$path") ;;
            *.sh)
                # Matches the basename, so a test that calls the script by
                # $REPO_ROOT/bin/<name> or sources it is found either way.
                while IFS= read -r bats_file; do
                    targets+=("$bats_file")
                done < <(grep -l -F "$(basename "$path")" test/*.bats || true)
                ;;
        esac
    done
    if [ "${#targets[@]}" -eq 0 ]; then
        echo "no .bats file covers the given paths; skipping"
        exit 0
    fi
    # No mapfile: macOS's /bin/bash is 3.2.
    unique=()
    while IFS= read -r bats_file; do
        unique+=("$bats_file")
    done < <(printf '%s\n' "${targets[@]}" | sort -u)
    targets=("${unique[@]}")
fi

if [ -n "${RUN_TESTS_LIST:-}" ]; then
    printf '%s\n' "${targets[@]}"
    exit 0
fi

# Files in parallel when there is more than one and GNU parallel is there for
# bats to use: the whole suite drops from about a minute and a half to about
# half a minute on four cores. Tests within one file stay in order; several
# share a fixture across a file, and running them apart was slower anyway.
# One file, or no GNU parallel (bats needs it for --jobs): one at a time.
jobs=()
if { [ "${#targets[@]}" -gt 1 ] || [ -d "${targets[0]}" ]; } &&
    command -v parallel >/dev/null 2>&1; then
    cpus=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
    [ "$cpus" -gt 1 ] && jobs=(--jobs "$cpus" --no-parallelize-within-files)
fi

# ${jobs[@]+...}: macOS's bash 3.2 calls an empty array unbound under set -u.
bats ${jobs[@]+"${jobs[@]}"} --print-output-on-failure "${targets[@]}"
