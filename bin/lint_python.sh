#!/bin/bash

# Lint the repo's Python (the e2e pty client and the stub LSP) with ruff's
# default rules: pyflakes errors and syntax mistakes, no style opinions, so the
# hand-formatted files stay as written.
#
# Pass files as arguments (lefthook feeds {staged_files}); with none, every
# tracked .py is checked (CI).

set -euo pipefail

# shellcheck source=bin/lint_lib.sh
. "$(dirname "$(readlink -f "$0")")/lint_lib.sh"

lint_require ruff
lint_collect '*.py' -- "$@"

[ "${#files[@]}" -eq 0 ] && exit 0

# --no-cache: ruff would otherwise leave .ruff_cache in the repo root.
ruff check --no-cache "${files[@]}"
