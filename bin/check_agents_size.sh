#!/bin/bash

# AGENTS.md is read in full by every agent session that opens this repo, so
# its size is a cost paid on every turn of every session. Keep it an index:
# one line per entry, with the why in the file the entry points at. The cap
# is 6 KiB, about 1,500 tokens, what an index of this repo needs.
# Single source of truth shared by CI and the lefthook pre-commit hook.
# Pass a file as the argument; with none, the repo's AGENTS.md is checked.
# AGENTS_MD_MAX_BYTES overrides the cap (for the test).

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
file="${1:-$BASE_DIR/AGENTS.md}"
max="${AGENTS_MD_MAX_BYTES:-6144}"

size=$(wc -c <"$file" | tr -d ' ')
if [ "$size" -gt "$max" ]; then
    echo "x $file is $size bytes, over the $max-byte cap: move the why into the file it describes" >&2
    exit 1
fi
