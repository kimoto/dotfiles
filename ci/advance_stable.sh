#!/bin/bash
# Fast-forward the `stable` branch to the commit a full bootstrap just passed
# on, so the install line in README can start a new machine from a commit that
# was bootstrapped end to end instead of whatever main holds that minute.
#
#   ci/advance_stable.sh <sha>
#
# Needs GITHUB_REPOSITORY, and GH_TOKEN with contents and workflows write:
# stable may land on a commit that changes .github/workflows.
#
# Only ever moves stable forward: a run that finishes after a newer one already
# advanced it (the macOS and Linux bootstraps race) leaves it where it is.
set -euo pipefail

sha="${1:?usage: advance_stable.sh <sha>}"
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"

# Only a 404 means stable is missing; a bad or expired token must not read as one.
# 2>&1 >/dev/null keeps gh's error message and drops the ref JSON.
if ! err="$(gh api "repos/$repo/git/ref/heads/stable" 2>&1 >/dev/null)"; then
    case "$err" in
        *"HTTP 404"*)
            gh api -X POST "repos/$repo/git/refs" -f ref=refs/heads/stable -f sha="$sha" >/dev/null
            echo "created stable at $sha"
            exit 0
            ;;
        *)
            echo "cannot read stable: $err" >&2
            exit 1
            ;;
    esac
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
