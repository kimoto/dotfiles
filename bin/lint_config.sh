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

# A mise.toml edited without `mise lock` (a bumped version, a pipx tool whose
# uv project directory was never written) stops every `mise install --locked`,
# and for a missing uv directory the error never names the file. `mise lock
# --check` runs offline and lists each such problem, so run it wherever a
# mise.toml is linted. It refuses an untrusted config instead of prompting, and
# a fresh clone or CI step has never trusted this checkout (a mise.local.toml
# beside it included); the ceiling keeps it from reading a mise.toml above the
# checkout, which nothing here trusts either.
for f in "${files[@]}"; do
    [ "${f##*/}" = mise.toml ] || continue
    lock="$(dirname "$f")/mise.lock"
    [ -f "$lock" ] || continue
    dir="$(cd "$(dirname "$f")" && pwd -P)"
    if ! command -v mise >/dev/null 2>&1; then
        echo "x mise not found; it is needed to check $lock" >&2
        rc=1
    elif ! MISE_TRUSTED_CONFIG_PATHS="${MISE_TRUSTED_CONFIG_PATHS:+$MISE_TRUSTED_CONFIG_PATHS:}$dir" \
        MISE_CEILING_PATHS="$(dirname "$dir")" \
        mise lock --check -C "$dir" >/dev/null; then
        # mise prints why on stderr; a stale entry ends with a `mise lock` hint.
        echo "x mise lock --check rejected $lock; see mise's reason above"
        rc=1
    fi
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
