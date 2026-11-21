#!/bin/bash

# Validate the syntax of structured config files (TOML / JSON / JSONC / YAML).
# TOML/JSON/YAML go through yq. .jsonc is validated with biome, which natively
# parses JSON with comments / trailing commas (yq has no JSONC mode).

set -euo pipefail

# shellcheck source=bin/lint_lib.sh
. "$(dirname "$(readlink -f "$0")")/lint_lib.sh"

lint_collect '*.toml' '*.json' '*.jsonc' '*.yaml' '*.yml' -- "$@"

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

# A pipx: tool is locked through a uv project directory that mise.lock only
# points at. A version bump that rewrites the pointer without writing the
# directory (`mise lock` not run) stops every `mise install` with an error that
# never names the file, so check the pointers wherever a mise.toml is linted.
for f in "${files[@]}"; do
    [ "${f##*/}" = mise.toml ] || continue
    lock="$(dirname "$f")/mise.lock"
    [ -f "$lock" ] || continue
    if ! uv_paths="$(yq -p toml -o tsv '.tools[][] | select(.uv.path) | .uv.path' "$lock" 2>&1)"; then
        echo "x cannot read the uv lock paths in $lock: $uv_paths"
        rc=1
        continue
    fi
    while IFS= read -r uv_path; do
        [ -n "$uv_path" ] || continue
        if [ ! -e "$(dirname "$lock")/$uv_path" ]; then
            echo "x $lock names $uv_path, which does not exist; run 'mise lock'"
            rc=1
        fi
    done <<<"$uv_paths"
done

if [ "${#jsonc[@]}" -gt 0 ]; then
    if ! command -v biome >/dev/null 2>&1; then
        echo "x biome not found; install it (run 'mise install' in this repo)" >&2
        rc=1
    elif ! biome lint "${jsonc[@]}"; then
        # biome prints its own parse diagnostics; flag the failure for the summary.
        echo "x Invalid jsonc syntax in: ${jsonc[*]}"
        rc=1
    fi
fi

exit "$rc"
