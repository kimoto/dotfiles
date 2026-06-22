#!/bin/bash

# Validate structured config files against the JSON Schema they declare via a
# top-level "$schema" key. Single source of truth shared by CI and the lefthook
# pre-commit hook. Pass files as arguments; with none, all tracked
# json/jsonc/toml/yaml files are checked.
#
# Files without a "$schema" key are skipped. Schemas whose host refuses
# automated downloads (see SKIP_HOSTS) are skipped with a notice — validate
# those in a browser or vendor the schema into the repo instead.
#
# .jsonc is comment-stripped to JSON before validation (check-jsonschema only
# parses json/toml/yaml). Downloaded schemas are cached by check-jsonschema, so
# repeat runs do not hit the network.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

# Schema hosts that block programmatic GETs (HTTP 403); no usable mirror.
SKIP_HOSTS="starship.rs"

if ! command -v check-jsonschema >/dev/null 2>&1; then
    echo "x check-jsonschema not found; install it (pipx install check-jsonschema)" >&2
    exit 1
fi

# stdin: JSONC -> stdout: JSON (string-aware comment + trailing-comma stripper).
jsonc_to_json() {
    python3 -c '
import sys
s = sys.stdin.read()
out = []
i, n = 0, len(s)
in_str = esc = False
while i < n:
    c = s[i]
    if in_str:
        out.append(c)
        if esc: esc = False
        elif c == "\\": esc = True
        elif c == "\"": in_str = False
        i += 1; continue
    if c == "\"":
        in_str = True; out.append(c); i += 1; continue
    if c == "/" and i + 1 < n and s[i+1] == "/":
        i += 2
        while i < n and s[i] != "\n": i += 1
        continue
    if c == "/" and i + 1 < n and s[i+1] == "*":
        i += 2
        while i + 1 < n and not (s[i] == "*" and s[i+1] == "/"): i += 1
        i += 2; continue
    out.append(c); i += 1
import re
sys.stdout.write(re.sub(r",(\s*[}\]])", r"\1", "".join(out)))
'
}

files=()
if [ "$#" -gt 0 ]; then
    files=("$@")
else
    while IFS= read -r f; do
        files+=("$f")
    done < <(git ls-files '*.json' '*.jsonc' '*.toml' '*.yaml' '*.yml')
fi

[ "${#files[@]}" -eq 0 ] && exit 0

# check-jsonschema writes both its "ok" and its errors to stdout, so capture
# the output and surface it only on failure. $1=display name, rest=ec args.
rc=0
validate() {
    local disp=$1 schema=$2; shift 2
    local out
    if out=$(check-jsonschema --schemafile "$schema" "$@" 2>&1); then
        echo "ok $disp (against $schema)"
    else
        echo "$out"
        echo "x schema validation failed: $disp"
        rc=1
    fi
}

for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    # The quoted yq expressions are yq syntax, not shell variables.
    # shellcheck disable=SC2016
    case "$f" in
        *.jsonc) schema=$(jsonc_to_json <"$f" | yq -p json -oy '.["$schema"] // ""') ;;
        *.json)  schema=$(yq -p json  -oy '.["$schema"] // ""' "$f") ;;
        *.toml)  schema=$(yq -p toml  -oy '.["$schema"] // ""' "$f") ;;
        *)       schema=$(yq -p yaml  -oy '.["$schema"] // ""' "$f") ;;
    esac
    [ -z "$schema" ] && continue

    host=${schema#*://}; host=${host%%/*}
    skip=0
    for h in $SKIP_HOSTS; do
        [ "$host" = "$h" ] && skip=1
    done
    if [ "$skip" -eq 1 ]; then
        echo "- skip $f: schema host '$host' refuses automated downloads"
        continue
    fi

    if [ "${f##*.}" = "jsonc" ]; then
        tmp=$(mktemp --suffix=.json)
        jsonc_to_json <"$f" >"$tmp"
        validate "$f" "$schema" --force-filetype json "$tmp"
        rm -f "$tmp"
    else
        validate "$f" "$schema" "$f"
    fi
done

exit "$rc"
