#!/bin/bash

# Static checks for shell scripts.
# Single source of truth shared by CI (.github/workflows/ci.yml) and the
# lefthook pre-commit hook (lefthook.yml), so the checks never diverge.

set -e

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

# Syntax check each script (bash -n only inspects its first file argument).
for f in bin/*.sh; do
    bash -n "$f"
done

shellcheck bin/*.sh
