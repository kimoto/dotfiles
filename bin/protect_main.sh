#!/bin/bash

# Refuse to put commits on, or push to, the 'main' branch. Work happens on
# feature branches + PRs; GitHub branch protection is the server-side
# enforcement, this is the fast local feedback. Single source of truth shared
# by the lefthook pre-commit and pre-push hooks, so the rule lives in ONE place
# instead of inline YAML.
#
# Usage:
#   protect_main.sh commit          # pre-commit: blocks if HEAD is 'main'
#   protect_main.sh push            # pre-push: reads git's pre-push stdin
#                                   #   (lines: <local-ref> <local-sha> <remote-ref> <remote-sha>)
#                                   #   and blocks any push to refs/heads/main
# Intentional bypass: git commit/push --no-verify

set -euo pipefail

mode="${1:-}"

case "$mode" in
    commit)
        branch=$(git rev-parse --abbrev-ref HEAD)
        if [ "$branch" = "main" ]; then
            echo "x Direct commits to 'main' are blocked."
            echo "  Create a feature branch and open a PR:"
            echo "    git switch -c <type>/<short-desc>"
            echo "  Intentional bypass: git commit --no-verify"
            exit 1
        fi
        ;;
    push)
        while read -r _ _ remote_ref _; do
            case "$remote_ref" in
                refs/heads/main)
                    echo "x Direct push to 'main' is blocked. Open a PR instead."
                    echo "  Intentional bypass: git push --no-verify"
                    exit 1
                    ;;
            esac
        done
        ;;
    *)
        echo "usage: $(basename "$0") {commit|push}" >&2
        exit 2
        ;;
esac
