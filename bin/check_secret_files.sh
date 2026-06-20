#!/bin/bash

# Block sensitive files (private keys, .env, keystores, ...) by name.
# Single source of truth shared by CI and the lefthook pre-commit hook.
# Pass files as arguments; with none, all tracked files are checked.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

if [ "$#" -gt 0 ]; then
    list=$(printf '%s\n' "$@")
else
    list=$(git ls-files)
fi

bad=$(printf '%s\n' "$list" \
    | grep -iE '(^|/)(id_rsa|id_dsa|id_ecdsa|id_ed25519)$|\.(pem|key|p12|pfx|ppk|keychain|keystore|jks|kdbx)$|(^|/)\.env(\.[^/]+)?$' \
    | grep -viE '\.env\.(example|sample|template|dist)$' || true)

if [ -n "$bad" ]; then
    echo "x Sensitive files detected:"
    printf '%s\n' "$bad" | sed 's/^/    /'
    echo "  If intentional, add to .gitignore or run: git commit --no-verify"
    exit 1
fi
