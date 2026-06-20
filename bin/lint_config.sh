#!/bin/bash

# Validate the syntax of structured config files (TOML / JSON / YAML) via yq.
# Single source of truth shared by CI and the lefthook pre-commit hook.
# Pass files as arguments; with none, all tracked toml/json/yaml files are checked.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

files=()
if [ "$#" -gt 0 ]; then
    files=("$@")
else
    while IFS= read -r f; do
        files+=("$f")
    done < <(git ls-files '*.toml' '*.json' '*.yaml' '*.yml')
fi

[ "${#files[@]}" -eq 0 ] && exit 0

rc=0
for f in "${files[@]}"; do
    case "$f" in
        *.json) parser=json ;;
        *.toml) parser=toml ;;
        *)      parser=yaml ;;
    esac
    if ! yq -p "$parser" '.' "$f" >/dev/null 2>&1; then
        echo "x Invalid $parser syntax: $f"
        rc=1
    fi
done

exit "$rc"
