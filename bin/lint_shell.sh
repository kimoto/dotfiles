#!/bin/bash

# Static checks for every tracked *.sh script (bash -n syntax + shellcheck),
# not just bin/.

set -euo pipefail

# shellcheck source=bin/lint_lib.sh
. "$(dirname "$(readlink -f "$0")")/lint_lib.sh"

lint_collect '*.sh' -- "$@"

# Before any "${files[@]}": expanding an empty array under `set -u` aborts on
# bash 3.2 (macOS).
[ "${#files[@]}" -eq 0 ] && exit 0

# Syntax check each script (bash -n only inspects its first file argument).
for f in "${files[@]}"; do
    bash -n "$f"
done

# -x follows the lint_lib.sh source line, so a lint script staged on its own
# still sees the variables the lib sets.
shellcheck -x "${files[@]}"
