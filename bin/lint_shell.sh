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

# bash 3.2 (macOS /bin/sh) in a UTF-8 locale reads a non-ASCII byte right after
# an unbraced variable as part of its name, so a Japanese full stop right after
# one aborts the script under `set -u`. dash and newer
# bash do not, so CI on Linux never sees it — and shellcheck does not flag it.
if LC_ALL=C grep -HnE '\$[A-Za-z_][A-Za-z0-9_]*[^ -~]' "${files[@]}"; then
    # shellcheck disable=SC2016 # literal text, not an expansion
    echo 'error: brace the variable above (${name}, not $name)' >&2
    exit 1
fi

# -x follows the lint_lib.sh source line, so a lint script staged on its own
# still sees the variables the lib sets.
shellcheck -x "${files[@]}"
