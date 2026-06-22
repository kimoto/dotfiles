#!/bin/bash

# Validate the syntax of structured config files (TOML / JSON / JSONC / YAML).
# Single source of truth shared by CI and the lefthook pre-commit hook.
# Pass files as arguments; with none, all tracked toml/json/jsonc/yaml files
# are checked.
#
# TOML/JSON/YAML go through yq. .jsonc is validated with biome, which natively
# parses JSON with comments / trailing commas (yq has no JSONC mode).

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

files=()
if [ "$#" -gt 0 ]; then
    files=("$@")
else
    while IFS= read -r f; do
        files+=("$f")
    done < <(git ls-files '*.toml' '*.json' '*.jsonc' '*.yaml' '*.yml')
fi

[ "${#files[@]}" -eq 0 ] && exit 0

rc=0
jsonc=()
for f in "${files[@]}"; do
    case "$f" in
        *.jsonc) jsonc+=("$f"); continue ;;  # validated with biome below
        *.json)  parser=json ;;
        *.toml)  parser=toml ;;
        *)       parser=yaml ;;
    esac
    if ! yq -p "$parser" '.' "$f" >/dev/null 2>&1; then
        echo "x Invalid $parser syntax: $f"
        rc=1
    fi
done

if [ "${#jsonc[@]}" -gt 0 ]; then
    if ! command -v biome >/dev/null 2>&1; then
        echo "x biome not found; install it (brew install biome)" >&2
        rc=1
    elif ! biome lint "${jsonc[@]}"; then
        # biome prints its own parse diagnostics; flag the failure for the summary.
        echo "x Invalid jsonc syntax in: ${jsonc[*]}"
        rc=1
    fi
fi

exit "$rc"
