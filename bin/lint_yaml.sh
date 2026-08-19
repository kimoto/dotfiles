#!/bin/bash

# Style-lint YAML with yamllint against .yamllint.yml at the repo root. The
# rules there track conventions this repo already enforces elsewhere
# (.editorconfig's 120 columns and its exemptions, ratchet's one-space pin
# comments), so the two never disagree. Syntax validity is a separate check:
# lint_config.sh parses the same files with yq. Single source of truth shared
# by CI and the lefthook pre-commit hook. Pass files as arguments; with none,
# all tracked *.yml/*.yaml files are checked.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

if ! command -v yamllint >/dev/null 2>&1; then
    echo "x yamllint not found; install it (brew install yamllint, or pip install yamllint)" >&2
    exit 1
fi

files=()
if [ "$#" -gt 0 ]; then
    files=("$@")
else
    while IFS= read -r f; do
        files+=("$f")
    done < <(git ls-files '*.yml' '*.yaml')
fi

# Drop paths that no longer exist, so a staged deletion does not fail the hook.
existing=()
for f in "${files[@]}"; do
    [ -f "$f" ] && existing+=("$f")
done

[ "${#existing[@]}" -eq 0 ] && exit 0

# --strict: yamllint exits 0 on warnings by default, which would let most of
# its rules fail silently. Everything it still warns about here is deliberate.
yamllint --strict -c "$BASE_DIR/.yamllint.yml" "${existing[@]}"
