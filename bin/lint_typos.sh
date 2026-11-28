#!/bin/bash

# Spell-check tracked files with typos, which flags only known misspellings,
# so a hit is almost always a real typo. False positives go in _typos.toml.
#
# Pass files as arguments (lefthook feeds {staged_files}); with none, the whole
# tree is walked (CI).

set -euo pipefail

# shellcheck source=bin/lint_lib.sh
. "$(dirname "$(readlink -f "$0")")/lint_lib.sh"

lint_require typos

# --config: typos looks for its config next to each checked path, so a file
# outside the repo would otherwise be checked without the allowed words.
# --force-exclude: a staged file that _typos.toml excludes stays excluded, as
# it is on the no-argument walk.
typos --config "$BASE_DIR/_typos.toml" --force-exclude "$@"
