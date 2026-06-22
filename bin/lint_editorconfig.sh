#!/bin/bash

# Enforce .editorconfig rules (max_line_length, trailing whitespace, final
# newline) with editorconfig-checker. Indentation enforcement is turned off in
# .editorconfig-checker.json; .editorconfig still advertises indent rules to
# editors. Single source of truth shared by CI and the lefthook pre-commit hook.
#
# Pass files as arguments (lefthook feeds {staged_files}); with none, the whole
# tree is walked (CI), honouring the excludes in .editorconfig-checker.json.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

if ! command -v ec >/dev/null 2>&1; then
    echo "x editorconfig-checker (ec) not found; install it (brew install editorconfig-checker)" >&2
    exit 1
fi

# With explicit files, ec still reads .editorconfig + .editorconfig-checker.json
# from the repo root, so per-file rules and disabled checks are respected.
ec "$@"
