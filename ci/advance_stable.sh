#!/bin/bash
# Fast-forward the `stable` branch to the commit a full bootstrap just passed
# on, so the install line in README can start a new machine from a commit that
# was bootstrapped end to end instead of whatever main holds that minute.
#
#   ci/advance_stable.sh <sha>
#
# Needs GH_TOKEN with contents:write and GITHUB_REPOSITORY. Only ever moves
# stable forward: a run that finishes after a newer one already advanced it
# (the macOS and Linux bootstraps race) leaves it where it is.
set -euo pipefail

sha="${1:?usage: advance_stable.sh <sha>}"
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"

if ! gh api "repos/$repo/git/ref/heads/stable" >/dev/null 2>&1; then
    gh api -X POST "repos/$repo/git/refs" -f ref=refs/heads/stable -f sha="$sha" >/dev/null
    echo "created stable at $sha"
    exit 0
fi

# stable...sha: "ahead" means sha descends from stable.
status="$(gh api "repos/$repo/compare/stable...$sha" --jq .status)"
case "$status" in
    ahead)
        gh api -X PATCH "repos/$repo/git/refs/heads/stable" -f sha="$sha" -F force=false >/dev/null
        echo "advanced stable to $sha"
        ;;
    identical)
        echo "stable is already at $sha"
        ;;
    behind)
        echo "stable is already past $sha; leaving it"
        ;;
    *)
        echo "stable and $sha have diverged ($status); not moving it" >&2
        exit 1
        ;;
esac
