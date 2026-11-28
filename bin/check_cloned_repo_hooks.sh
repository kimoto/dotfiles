#!/bin/bash

# Flag any non-sample file under <repo>/.git/hooks/. A real `git clone` ships
# only *.sample templates; anything else was added after the clone, which is
# how a planted post-checkout/post-merge hook gets distributed inside a repo
# handed to you by someone else (it runs automatically, with no prompt).
# Human-only triage tool, not wired into CI/lefthook: it targets arbitrary
# external repos, not this one.
# Usage: bin/check_cloned_repo_hooks.sh <path-to-repo>

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path-to-repo>" >&2
    exit 2
fi

hooks_dir="$1/.git/hooks"

if [ ! -d "$hooks_dir" ]; then
    echo "x Not a git repo (missing $hooks_dir): $1" >&2
    exit 2
fi

suspicious=$(find "$hooks_dir" -maxdepth 1 -type f ! -name '*.sample')

if [ -n "$suspicious" ]; then
    echo "x Non-sample file(s) in $hooks_dir:"
    printf '%s\n' "$suspicious" | sed 's/^/    /'
    echo "  Read each one before trusting this clone - it runs automatically on checkout/commit/etc."
    exit 1
fi

echo "ok: only *.sample hooks in $hooks_dir"
