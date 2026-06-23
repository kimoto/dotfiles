#!/bin/bash

# Run the bats unit-test suite (test/*.bats).
# Single source of truth shared by CI and the lefthook pre-commit hook, so the
# tests never diverge between local checks and CI.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

if ! command -v bats >/dev/null 2>&1; then
    echo "x bats not found; install it (brew install bats-core, or apt-get install bats)" >&2
    exit 1
fi

bats --print-output-on-failure test/
