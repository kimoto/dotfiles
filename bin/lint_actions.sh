#!/bin/bash

# Lint the GitHub Actions workflows three ways: ratchet checks that every
# `uses:` is pinned to a full commit SHA (not a mutable tag), actionlint checks
# the workflow itself — expression syntax, context properties, runner labels,
# plus a shellcheck pass over every `run:` block — and zizmor audits for
# security misconfigurations (missing `permissions:`, credential persistence,
# injection risks) that the other two don't cover. zizmor runs --offline: this
# repo's own SHA-pinning is already covered by ratchet, so the audits that need
# network access to resolve remote tags add little here, and offline keeps the
# check working the same in CI and over a flaky local connection. Single
# source of truth shared by CI and the lefthook pre-commit hook. All three only
# look at .github/workflows, so workflow files are checked regardless of
# arguments.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

if ! command -v ratchet >/dev/null 2>&1; then
    echo "x ratchet not found; install it (brew install ratchet)" >&2
    exit 1
fi

if ! command -v actionlint >/dev/null 2>&1; then
    echo "x actionlint not found; install it (brew install actionlint)" >&2
    exit 1
fi

if ! command -v zizmor >/dev/null 2>&1; then
    echo "x zizmor not found; install it (brew install zizmor)" >&2
    exit 1
fi

files=()
while IFS= read -r f; do
    files+=("$f")
done < <(git ls-files '.github/workflows/*.yml' '.github/workflows/*.yaml')

[ "${#files[@]}" -eq 0 ] && exit 0

ratchet lint "${files[@]}"
actionlint "${files[@]}"
zizmor --offline --no-progress "${files[@]}"
