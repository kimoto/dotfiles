#!/bin/bash

# Run the bats unit-test suite (test/*.bats).
# Single source of truth shared by CI and the lefthook pre-commit hook, so the
# tests never diverge between local checks and CI.

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

bats --print-output-on-failure test/
