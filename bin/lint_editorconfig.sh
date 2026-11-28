#!/bin/bash

# Enforce .editorconfig rules (max_line_length, trailing whitespace, final
# newline) with editorconfig-checker. Indentation enforcement is turned off in
# .editorconfig-checker.json; .editorconfig still advertises indent rules to
# editors.
#
# Pass files as arguments (lefthook feeds {staged_files}); with none, the whole
# tree is walked (CI), honouring the excludes in .editorconfig-checker.json.

set -euo pipefail

# shellcheck source=bin/lint_lib.sh
. "$(dirname "$(readlink -f "$0")")/lint_lib.sh"

# The release binary mise.toml installs is named `ec`; Homebrew uses the long
# name.
if command -v editorconfig-checker >/dev/null 2>&1; then
    checker=editorconfig-checker
elif command -v ec >/dev/null 2>&1; then
    checker=ec
else
    echo "x editorconfig-checker not found; run 'mise install' in this repo" >&2
    exit 1
fi

# With explicit files, editorconfig-checker still reads .editorconfig + .editorconfig-checker.json
# from the repo root, so per-file rules and disabled checks are respected.
"$checker" "$@"
